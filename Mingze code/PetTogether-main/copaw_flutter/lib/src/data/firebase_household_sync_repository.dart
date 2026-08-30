import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../domain/legacy_firestore_codec.dart';
import '../domain/models.dart';
import 'firebase_household_sync_gateway.dart';
import 'household_data_gateway.dart';
import 'household_repository.dart';
import 'household_sync_gateway.dart';
import 'household_sync_repository.dart';

final class FirebaseHouseholdSyncRepository implements HouseholdSyncRepository {
  FirebaseHouseholdSyncRepository({HouseholdSyncGateway? gateway})
    : _gateway = gateway ?? FirebaseHouseholdSyncGateway();

  final HouseholdSyncGateway _gateway;
  final LegacyFirestoreCodec _codec = const LegacyFirestoreCodec();
  StreamSubscription<StoredDocument>? _householdSubscription;
  StreamSubscription<StoredDocument>? _memberSubscription;
  StreamSubscription<List<StoredDocument>>? _membersSubscription;
  StreamController<HouseholdSyncSnapshot>? _controller;
  int _generation = 0;

  @override
  Stream<HouseholdSyncSnapshot> observeSession({
    required String householdId,
    required String userId,
  }) {
    final controller = StreamController<HouseholdSyncSnapshot>();
    unawaited(_replaceObservation(householdId, userId, controller));
    return controller.stream;
  }

  Future<void> _replaceObservation(
    String householdId,
    String userId,
    StreamController<HouseholdSyncSnapshot> controller,
  ) async {
    await stopObserving();
    final generation = ++_generation;
    _controller = controller;
    DomainDecodeResult<Household>? householdResult;
    DomainDecodeResult<Caregiver>? memberResult;
    DateTime? memberJoinedAt;
    List<Caregiver>? membersResult;

    void emitIfReady() {
      if (generation != _generation || controller.isClosed) return;
      final household = householdResult?.value;
      final member = memberResult?.value;
      if (household == null || member == null) return;
      controller.add(
        HouseholdSyncSnapshot(
          household: household,
          caregiver: member,
          memberJoinedAt: memberJoinedAt,
          members: membersResult ?? [member],
          diagnostics: [
            ...householdResult!.diagnostics,
            ...memberResult!.diagnostics,
          ],
        ),
      );
    }

    void addError(Object error) {
      if (generation == _generation && !controller.isClosed) {
        controller.addError(_mapped(error));
      }
    }

    _householdSubscription = _gateway.observeHousehold(householdId).listen((
      doc,
    ) {
      if (generation != _generation) return;
      if (!doc.exists) {
        addError(
          const HouseholdRepositoryException(
            HouseholdRepositoryErrorCode.permission,
          ),
        );
        return;
      }
      householdResult = _codec.decodeHousehold(doc.id, doc.data);
      if (householdResult!.value == null) {
        addError(
          const HouseholdRepositoryException(
            HouseholdRepositoryErrorCode.malformedData,
          ),
        );
        return;
      }
      emitIfReady();
    }, onError: addError);

    _memberSubscription = _gateway.observeMember(householdId, userId).listen((
      doc,
    ) {
      if (generation != _generation) return;
      if (!doc.exists) {
        addError(
          const HouseholdRepositoryException(
            HouseholdRepositoryErrorCode.permission,
          ),
        );
        return;
      }
      memberResult = _codec.decodeCaregiver(doc.id, doc.data);
      memberJoinedAt = _date(doc.data['joinedAt']);
      if (memberResult!.value == null) {
        addError(
          const HouseholdRepositoryException(
            HouseholdRepositoryErrorCode.malformedData,
          ),
        );
        return;
      }
      emitIfReady();
    }, onError: addError);

    _membersSubscription = _gateway.observeMembers(householdId).listen((docs) {
      if (generation != _generation) return;
      final decoded = <Caregiver>[];
      for (final doc in docs) {
        final result = _codec.decodeCaregiver(doc.id, doc.data);
        if (result.value case final Caregiver member) decoded.add(member);
      }
      membersResult = List.unmodifiable(decoded);
      emitIfReady();
    }, onError: addError);
  }

  @override
  Future<void> updateProfile({
    required String householdId,
    required String userId,
    required String householdName,
    required String petName,
    required String caregiverName,
  }) async {
    final normalizedHousehold = householdName.trim();
    final normalizedPet = petName.trim();
    final normalizedCaregiver = caregiverName.trim();
    if (normalizedHousehold.isEmpty ||
        normalizedHousehold.length > 60 ||
        normalizedPet.isEmpty ||
        normalizedPet.length > 60 ||
        normalizedCaregiver.isEmpty ||
        normalizedCaregiver.length > 50) {
      throw const HouseholdRepositoryException(
        HouseholdRepositoryErrorCode.invalidInput,
      );
    }

    try {
      await _gateway.updateProfileAtomically(
        UpdateProfileCommand(
          householdId: householdId,
          userId: userId,
          householdName: normalizedHousehold,
          petName: normalizedPet,
          caregiverName: normalizedCaregiver,
        ),
      );
    } on Object catch (error) {
      throw _mapped(error);
    }
  }

  @override
  Future<void> stopObserving() async {
    _generation += 1;
    final household = _householdSubscription;
    final member = _memberSubscription;
    final members = _membersSubscription;
    final controller = _controller;
    _householdSubscription = null;
    _memberSubscription = null;
    _membersSubscription = null;
    _controller = null;
    await household?.cancel();
    await member?.cancel();
    await members?.cancel();
    await controller?.close();
  }

  static HouseholdRepositoryException _mapped(Object error) {
    if (error is HouseholdRepositoryException) return error;
    if (error is FirebaseException) {
      return HouseholdRepositoryException(switch (error.code) {
        'network-request-failed' ||
        'unavailable' => HouseholdRepositoryErrorCode.network,
        'permission-denied' => HouseholdRepositoryErrorCode.permission,
        _ => HouseholdRepositoryErrorCode.backendUnavailable,
      });
    }
    return householdSyncError(error);
  }

  static DateTime? _date(Object? value) => switch (value) {
    Timestamp timestamp => timestamp.toDate().toUtc(),
    DateTime date => date.toUtc(),
    _ => null,
  };
}
