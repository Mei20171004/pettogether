import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../domain/legacy_firestore_codec.dart';
import '../domain/models.dart';
import '../domain/time_zone_identifier.dart';
import 'active_household_store.dart';
import 'firebase_household_data_gateway.dart';
import 'household_data_gateway.dart';
import 'household_repository.dart';

final class FirebaseHouseholdRepository implements HouseholdRepository {
  FirebaseHouseholdRepository({
    HouseholdDataGateway? gateway,
    ActiveHouseholdStore? activeHouseholdStore,
    PendingHouseholdStore? pendingHouseholdStore,
    InviteCodeGenerator? inviteCodeGenerator,
  }) : _providedGateway = gateway,
       _activeHouseholdStore =
           activeHouseholdStore ?? SharedPreferencesActiveHouseholdStore(),
       _pendingHouseholdStore =
           pendingHouseholdStore ?? SharedPreferencesPendingHouseholdStore(),
       _inviteCodeGenerator =
           inviteCodeGenerator ?? RandomInviteCodeGenerator();

  static const _inviteCodeAttempts = 5;

  final HouseholdDataGateway? _providedGateway;
  late final HouseholdDataGateway _gateway =
      _providedGateway ?? FirebaseHouseholdDataGateway();
  final ActiveHouseholdStore _activeHouseholdStore;
  final PendingHouseholdStore _pendingHouseholdStore;
  final InviteCodeGenerator _inviteCodeGenerator;
  final LegacyFirestoreCodec _codec = const LegacyFirestoreCodec();

  @override
  Future<HouseholdSession?> restoreSession() async {
    try {
      final householdId = await _activeHouseholdStore.read();
      if (householdId != null) {
        return await _restoreById(householdId);
      }
      final pending = await _pendingHouseholdStore.read();
      if (pending == null) return null;
      return await _reconcilePendingHousehold();
    } on Object catch (error) {
      throw _mapped(error);
    }
  }

  @override
  Future<HouseholdSession> createHousehold({
    required String householdName,
    required String petName,
    required String caregiverName,
    required String timeZoneIdentifier,
  }) async {
    final normalizedHouseholdName = householdName.trim();
    final normalizedPetName = petName.trim();
    final normalizedCaregiverName = caregiverName.trim();
    final normalizedTimeZone = timeZoneIdentifier.trim();
    if (!_validLength(normalizedHouseholdName, 60) ||
        !_validLength(normalizedPetName, 60) ||
        !_validLength(normalizedCaregiverName, 50) ||
        !isPlausibleTimeZoneIdentifier(normalizedTimeZone)) {
      throw const HouseholdRepositoryException(
        HouseholdRepositoryErrorCode.invalidInput,
      );
    }
    try {
      final pendingSession = await _reconcilePendingHousehold();
      if (pendingSession != null) return pendingSession;
      final userId = await _gateway.ensureAnonymousUserId();
      final householdId = _gateway.newHouseholdId();

      for (var attempt = 0; attempt < _inviteCodeAttempts; attempt += 1) {
        final inviteCode = _inviteCodeGenerator.next();
        final command = CreateHouseholdCommand(
          householdId: householdId,
          ownerId: userId,
          householdName: normalizedHouseholdName,
          petName: normalizedPetName,
          caregiverName: normalizedCaregiverName,
          inviteCode: inviteCode,
          timeZoneIdentifier: normalizedTimeZone,
        );
        try {
          await _pendingHouseholdStore.save(
            PendingHouseholdMarker(
              householdId: householdId,
              inviteCode: inviteCode,
            ),
          );
          await _gateway.createHouseholdAtomically(command);
          final persistence = await _saveActiveHousehold(householdId);
          if (persistence == LocalSessionPersistence.saved) {
            await _pendingHouseholdStore.clear();
          }
          return HouseholdSession(
            household: Household(
              id: householdId,
              name: normalizedHouseholdName,
              inviteCode: inviteCode,
              petName: normalizedPetName,
              timeZoneIdentifier: normalizedTimeZone,
              ownerId: userId,
            ),
            caregiver: Caregiver(
              id: userId,
              displayName: normalizedCaregiverName,
            ),
            localPersistence: persistence,
          );
        } on InviteCodeCollision {
          continue;
        }
      }
      throw const HouseholdRepositoryException(
        HouseholdRepositoryErrorCode.inviteCodeUnavailable,
      );
    } on Object catch (error) {
      throw _mapped(error);
    }
  }

  @override
  Future<HouseholdSession> joinHousehold({
    required String inviteCode,
    required String caregiverName,
  }) async {
    final normalizedCode = inviteCode.trim().toUpperCase();
    final normalizedCaregiverName = caregiverName.trim();
    if (!_validLength(normalizedCaregiverName, 50)) {
      throw const HouseholdRepositoryException(
        HouseholdRepositoryErrorCode.invalidInput,
      );
    }
    if (!RegExp(r'^[A-Z0-9]{6}$').hasMatch(normalizedCode)) {
      throw const HouseholdRepositoryException(
        HouseholdRepositoryErrorCode.invalidInviteCode,
      );
    }

    try {
      final userId = await _gateway.ensureAnonymousUserId();
      final result = await _gateway.joinHouseholdAtomically(
        JoinHouseholdCommand(
          userId: userId,
          caregiverName: normalizedCaregiverName,
          inviteCode: normalizedCode,
        ),
      );
      final householdDocument = await _gateway.readHousehold(
        result.householdId,
      );
      if (!householdDocument.exists) {
        throw const HouseholdRepositoryException(
          HouseholdRepositoryErrorCode.invalidInviteCode,
        );
      }
      final householdResult = _codec.decodeHousehold(
        householdDocument.id,
        householdDocument.data,
      );
      final household = householdResult.value;
      if (household == null) {
        throw const HouseholdRepositoryException(
          HouseholdRepositoryErrorCode.malformedData,
        );
      }
      final persistence = await _saveActiveHousehold(household.id);
      return HouseholdSession(
        household: household,
        caregiver: Caregiver(id: userId, displayName: normalizedCaregiverName),
        diagnostics: householdResult.diagnostics,
        localPersistence: persistence,
      );
    } on Object catch (error) {
      throw _mapped(error);
    }
  }

  @override
  Future<void> leaveHousehold() async {
    await _pendingHouseholdStore.clear();
    await _activeHouseholdStore.clear();
  }

  HouseholdSession _decodeSession(
    StoredDocument householdDocument,
    StoredDocument memberDocument,
  ) {
    final householdResult = _codec.decodeHousehold(
      householdDocument.id,
      householdDocument.data,
    );
    final memberResult = _codec.decodeCaregiver(
      memberDocument.id,
      memberDocument.data,
    );
    final household = householdResult.value;
    final member = memberResult.value;
    if (household == null || member == null) {
      throw const HouseholdRepositoryException(
        HouseholdRepositoryErrorCode.malformedData,
      );
    }
    return HouseholdSession(
      household: household,
      caregiver: member,
      memberJoinedAt: _date(memberDocument.data['joinedAt']),
      diagnostics: [
        ...householdResult.diagnostics,
        ...memberResult.diagnostics,
      ],
    );
  }

  Future<HouseholdSession?> _restoreById(String householdId) async {
    final userId = await _gateway.ensureAnonymousUserId();
    final memberDocument = await _gateway.readMember(householdId, userId);
    if (!memberDocument.exists) {
      await _activeHouseholdStore.clear();
      return null;
    }
    final householdDocument = await _gateway.readHousehold(householdId);
    if (!householdDocument.exists) {
      await _activeHouseholdStore.clear();
      return null;
    }
    return _decodeSession(householdDocument, memberDocument);
  }

  Future<LocalSessionPersistence> _saveActiveHousehold(
    String householdId,
  ) async {
    try {
      await _activeHouseholdStore.save(householdId);
      return LocalSessionPersistence.saved;
    } on Object {
      return LocalSessionPersistence.unavailable;
    }
  }

  Future<HouseholdSession?> _reconcilePendingHousehold() async {
    final pending = await _pendingHouseholdStore.read();
    if (pending == null) return null;
    final restored = await _restoreById(pending.householdId);
    if (restored == null) {
      await _pendingHouseholdStore.clear();
      return null;
    }
    final persistence = await _saveActiveHousehold(pending.householdId);
    if (persistence == LocalSessionPersistence.saved) {
      await _pendingHouseholdStore.clear();
    }
    return HouseholdSession(
      household: restored.household,
      caregiver: restored.caregiver,
      memberJoinedAt: restored.memberJoinedAt,
      diagnostics: restored.diagnostics,
      localPersistence: persistence,
    );
  }

  static HouseholdRepositoryException _mapped(Object error) {
    if (error is HouseholdRepositoryException) {
      return error;
    }
    if (error is InvalidInvite) {
      return const HouseholdRepositoryException(
        HouseholdRepositoryErrorCode.invalidInviteCode,
      );
    }
    if (error is FirebaseException) {
      return HouseholdRepositoryException(switch (error.code) {
        'network-request-failed' ||
        'unavailable' => HouseholdRepositoryErrorCode.network,
        'permission-denied' => HouseholdRepositoryErrorCode.permission,
        'user-disabled' ||
        'operation-not-allowed' => HouseholdRepositoryErrorCode.authentication,
        _ => HouseholdRepositoryErrorCode.backendUnavailable,
      });
    }
    return const HouseholdRepositoryException(
      HouseholdRepositoryErrorCode.backendUnavailable,
    );
  }

  static bool _validLength(String value, int maximum) =>
      value.isNotEmpty && value.length <= maximum;

  static DateTime? _date(Object? value) => switch (value) {
    Timestamp timestamp => timestamp.toDate().toUtc(),
    DateTime date => date.toUtc(),
    _ => null,
  };
}

final class RandomInviteCodeGenerator implements InviteCodeGenerator {
  RandomInviteCodeGenerator({Random? random})
    : _random = random ?? Random.secure();

  static const _alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  final Random _random;

  @override
  String next() => String.fromCharCodes(
    List.generate(
      6,
      (_) => _alphabet.codeUnitAt(_random.nextInt(_alphabet.length)),
    ),
  );
}
