import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:crypto/crypto.dart';

import '../domain/medication_models.dart';
import '../domain/medication_occurrence_service.dart';
import 'firebase_medication_gateway.dart';
import 'medication_gateway.dart';
import 'medication_mutation_store.dart';
import 'medication_repository.dart';

final class FirebaseMedicationRepository implements MedicationRepository {
  FirebaseMedicationRepository({
    MedicationGateway? gateway,
    MedicationMutationStore? mutationStore,
  }) : _gateway = gateway ?? FirebaseMedicationGateway(),
       _mutationStore =
           mutationStore ?? SharedPreferencesMedicationMutationStore();

  final MedicationGateway _gateway;
  final MedicationMutationStore _mutationStore;
  final Map<String, String> _pendingMutationIds = {};
  final Random _random = Random.secure();

  @override
  Stream<MedicationSnapshot> observeMedication(String householdId) {
    if (!_validId(householdId)) {
      return Stream.error(
        const MedicationRepositoryException(
          MedicationRepositoryErrorCode.invalidInput,
        ),
      );
    }
    return _gateway.observe(householdId).map(_decode).handleError((
      Object error,
    ) {
      throw _mapped(error);
    });
  }

  @override
  Future<String> createPlan({
    required String householdId,
    required String petId,
    required String medicationName,
    String? purpose,
    String? possibleSideEffects,
    required String effectiveFromLocalDate,
    required List<int> weekdays,
    required List<MedicationPlanSlotInput> slots,
  }) async {
    final payload = _planPayload(
      householdId: householdId,
      petId: petId,
      medicationName: medicationName,
      purpose: purpose,
      possibleSideEffects: possibleSideEffects,
      effectiveFromLocalDate: effectiveFromLocalDate,
      weekdays: weekdays,
      slots: slots,
    );
    final result = await _call('createMedicationPlan', payload);
    final medicationId = result['medicationID'];
    if (medicationId is! String) throw _malformed();
    return medicationId;
  }

  @override
  Future<void> replacePlan({
    required String householdId,
    required Medication medication,
    required String medicationName,
    String? purpose,
    String? possibleSideEffects,
    required String effectiveFromLocalDate,
    required List<int> weekdays,
    required List<MedicationPlanSlotInput> slots,
  }) async {
    final payload =
        _planPayload(
          householdId: householdId,
          petId: medication.petId,
          medicationName: medicationName,
          purpose: purpose,
          possibleSideEffects: possibleSideEffects,
          effectiveFromLocalDate: effectiveFromLocalDate,
          weekdays: weekdays,
          slots: slots,
        )..addAll({
          'medicationID': medication.id,
          'expectedMedicationRevision': medication.revision,
          'expectedScheduleVersionID': medication.currentScheduleVersionId,
        });
    await _call('replaceMedicationPlan', payload);
  }

  @override
  Future<void> stopPlan({
    required String householdId,
    required Medication medication,
    required String effectiveUntilLocalDate,
  }) async {
    await _call('stopMedicationPlan', {
      'householdID': householdId,
      'medicationID': medication.id,
      'expectedMedicationRevision': medication.revision,
      'effectiveUntilLocalDate': effectiveUntilLocalDate,
    });
  }

  @override
  Future<void> claim({
    required String householdId,
    required PlannedMedicationOccurrence occurrence,
  }) => _mutate(householdId, occurrence, 'claim');

  @override
  Future<void> administer({
    required String householdId,
    required PlannedMedicationOccurrence occurrence,
  }) => _mutate(householdId, occurrence, 'administer');

  @override
  Future<void> skip({
    required String householdId,
    required PlannedMedicationOccurrence occurrence,
    required MedicationSkipReasonCode reasonCode,
    String? reasonNote,
  }) => _mutate(
    householdId,
    occurrence,
    'skip',
    reasonCode: reasonCode,
    reasonNote: reasonNote,
  );

  Future<void> _mutate(
    String householdId,
    PlannedMedicationOccurrence occurrence,
    String action, {
    MedicationSkipReasonCode? reasonCode,
    String? reasonNote,
  }) async {
    await _call('mutateMedicationOccurrence', {
      'householdID': householdId,
      'medicationID': occurrence.medicationId,
      'scheduleVersionID': occurrence.scheduleVersionId,
      'localDate': occurrence.localDate,
      'slotID': occurrence.slotId,
      'action': action,
      'skippedReasonCode': reasonCode?.name,
      'skippedReasonNote': _nullableTrim(reasonNote),
    });
  }

  Map<String, Object?> _planPayload({
    required String householdId,
    required String petId,
    required String medicationName,
    String? purpose,
    String? possibleSideEffects,
    required String effectiveFromLocalDate,
    required List<int> weekdays,
    required List<MedicationPlanSlotInput> slots,
  }) {
    final normalizedName = medicationName.trim();
    final normalizedPurpose = _nullableTrim(purpose);
    final normalizedSideEffects = _nullableTrim(possibleSideEffects);
    final normalizedDays = [...weekdays]..sort();
    final normalizedSlots = [...slots]
      ..sort((left, right) {
        final hour = left.hour.compareTo(right.hour);
        return hour != 0 ? hour : left.minute.compareTo(right.minute);
      });
    if (!_validId(householdId) ||
        !_validId(petId) ||
        normalizedName.isEmpty ||
        normalizedName.length > 120 ||
        (normalizedPurpose?.length ?? 0) > 500 ||
        (normalizedSideEffects?.length ?? 0) > 500 ||
        !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(effectiveFromLocalDate) ||
        normalizedDays.isEmpty ||
        normalizedDays.toSet().length != normalizedDays.length ||
        normalizedDays.any((day) => day < 1 || day > 7) ||
        normalizedSlots.isEmpty ||
        normalizedSlots.length > 8 ||
        normalizedSlots.any(
          (slot) =>
              slot.hour < 0 ||
              slot.hour > 23 ||
              slot.minute < 0 ||
              slot.minute > 59 ||
              slot.doseText.trim().isEmpty ||
              slot.doseText.trim().length > 80 ||
              (slot.instructions?.trim().length ?? 0) > 500,
        )) {
      throw const MedicationRepositoryException(
        MedicationRepositoryErrorCode.invalidInput,
      );
    }
    final slotIds = normalizedSlots.map(_slotId).toList(growable: false);
    if (slotIds.toSet().length != slotIds.length) {
      throw const MedicationRepositoryException(
        MedicationRepositoryErrorCode.invalidInput,
      );
    }
    return {
      'householdID': householdId,
      'petID': petId,
      'medicationName': normalizedName,
      'purpose': normalizedPurpose,
      'possibleSideEffects': normalizedSideEffects,
      'effectiveFromLocalDate': effectiveFromLocalDate,
      'weekdays': normalizedDays,
      'slots': [
        for (final slot in normalizedSlots)
          {
            'slotID': _slotId(slot),
            'hour': slot.hour,
            'minute': slot.minute,
            'doseText': slot.doseText.trim(),
            'instructions': _nullableTrim(slot.instructions),
          },
      ],
    };
  }

  Future<Map<String, Object?>> _call(
    String callable,
    Map<String, Object?> payload,
  ) async {
    final requestHash = sha256
        .convert(utf8.encode('$callable:${_stablePayload(payload)}'))
        .toString();
    String mutationId;
    try {
      final persisted = await _mutationStore.readOrCreate(
        requestHash,
        _newMutationId,
      );
      mutationId = _pendingMutationIds.putIfAbsent(
        requestHash,
        () => persisted,
      );
    } on Object catch (error) {
      throw _mapped(error);
    }
    try {
      final result = await _gateway.call(callable, {
        ...payload,
        'clientMutationID': mutationId,
      });
      _pendingMutationIds.remove(requestHash);
      await _mutationStore.clear(requestHash);
      return result;
    } on Object catch (error) {
      final mapped = _mapped(error);
      if (mapped.code != MedicationRepositoryErrorCode.network &&
          mapped.code != MedicationRepositoryErrorCode.backendUnavailable) {
        _pendingMutationIds.remove(requestHash);
        try {
          await _mutationStore.clear(requestHash);
        } on Object {
          throw const MedicationRepositoryException(
            MedicationRepositoryErrorCode.backendUnavailable,
          );
        }
      }
      throw mapped;
    }
  }

  @override
  Future<void> stopObserving() => _gateway.stopObserving();

  MedicationSnapshot _decode(MedicationGatewaySnapshot snapshot) {
    try {
      final medications = snapshot.medications.map(_decodeMedication).toList();
      final schedules = snapshot.schedules.map(_decodeSchedule).toList();
      final occurrences = snapshot.occurrences
          .map(
            (item) => _decodeOccurrence(
              item,
              !snapshot.isFromCache && !snapshot.hasPendingWrites,
            ),
          )
          .toList();
      final medicationsById = {for (final item in medications) item.id: item};
      final schedulesById = {
        for (final item in schedules) '${item.medicationId}:${item.id}': item,
      };
      for (final medication in medications) {
        final current =
            schedulesById['${medication.id}:${medication.currentScheduleVersionId}'];
        if (current == null ||
            current.version != medication.currentScheduleVersion ||
            current.petId != medication.petId) {
          throw _malformed();
        }
      }
      final occurrenceService = MedicationOccurrenceService();
      for (final occurrence in occurrences) {
        final medication = medicationsById[occurrence.medicationId];
        final schedule =
            schedulesById['${occurrence.medicationId}:${occurrence.scheduleVersionId}'];
        final slot = schedule?.slots
            .where((item) => item.slotId == occurrence.slotId)
            .firstOrNull;
        if (medication == null ||
            schedule == null ||
            slot == null ||
            occurrence.scheduleVersion != schedule.version ||
            occurrence.petId != schedule.petId ||
            occurrence.petNameSnapshot != schedule.petNameSnapshot ||
            occurrence.medicationNameSnapshot !=
                schedule.medicationNameSnapshot ||
            occurrence.doseText != slot.doseText ||
            occurrence.instructions != slot.instructions) {
          throw _malformed();
        }
        final planned = occurrenceService.forDay(
          selectedInstant: occurrence.dueAt,
          schedules: [schedule],
          persisted: [occurrence],
        );
        if (planned.length != 1) {
          throw _malformed('occurrence-not-planned');
        }
        if (planned.single.id != occurrence.id) {
          throw _malformed('occurrence-id-mismatch');
        }
        if (!planned.single.dueAt.isAtSameMomentAs(occurrence.dueAt)) {
          throw _malformed('occurrence-time-mismatch');
        }
      }
      return MedicationSnapshot(
        medications: List.unmodifiable(medications),
        schedules: List.unmodifiable(schedules),
        occurrences: List.unmodifiable(occurrences),
        isServerConfirmed: !snapshot.isFromCache && !snapshot.hasPendingWrites,
      );
    } on MedicationRepositoryException {
      rethrow;
    } on Object {
      throw _malformed();
    }
  }

  static Medication _decodeMedication(MedicationStoredDocument document) {
    final data = document.data;
    final id = _string(data['id'], document.id);
    final currentVersion = _integer(data['currentScheduleVersion']);
    final currentVersionId = _string(data['currentScheduleVersionID']);
    final revision = _integer(data['revision']);
    if (id != document.id ||
        currentVersion < 1 ||
        currentVersionId != _versionId(currentVersion) ||
        revision < 0) {
      throw _malformed();
    }
    return Medication(
      id: id,
      petId: _string(data['petID']),
      displayName: _string(data['displayName']),
      purpose: _nullableString(data['purpose']),
      possibleSideEffects: _nullableString(data['possibleSideEffects']),
      isActive: _boolean(data['isActive']),
      currentScheduleVersion: currentVersion,
      currentScheduleVersionId: currentVersionId,
      revision: revision,
    );
  }

  static MedicationScheduleVersion _decodeSchedule(
    MedicationStoredDocument document,
  ) {
    final data = document.data;
    final slots = data['slots'];
    final weekdays = data['weekdays'];
    if (slots is! List || weekdays is! List) throw _malformed();
    final id = _string(data['id'], document.id);
    final version = _integer(data['version']);
    final decodedWeekdays = weekdays.map(_integer).toList(growable: false);
    final start = _localDate(_string(data['effectiveFromLocalDate']));
    final endValue = _nullableString(data['effectiveUntilLocalDate']);
    final end = endValue == null ? null : _localDate(endValue);
    if (id != document.id ||
        version < 1 ||
        id != _versionId(version) ||
        decodedWeekdays.isEmpty ||
        decodedWeekdays.length > 7 ||
        decodedWeekdays.toSet().length != decodedWeekdays.length ||
        decodedWeekdays.any((day) => day < 1 || day > 7) ||
        !_strictlyIncreasing(decodedWeekdays) ||
        (end != null && !end.isAfter(start))) {
      throw _malformed();
    }
    final decodedSlots = slots
        .map((value) {
          if (value is! Map) throw _malformed();
          final slot = Map<String, Object?>.from(value);
          final hour = _integer(slot['hour']);
          final minute = _integer(slot['minute']);
          final slotId = _string(slot['slotID']);
          if (hour < 0 ||
              hour > 23 ||
              minute < 0 ||
              minute > 59 ||
              slotId !=
                  '${hour.toString().padLeft(2, '0')}'
                      '${minute.toString().padLeft(2, '0')}') {
            throw _malformed();
          }
          return MedicationSlot(
            slotId: slotId,
            hour: hour,
            minute: minute,
            doseText: _string(slot['doseText']),
            instructions: _nullableString(slot['instructions']),
          );
        })
        .toList(growable: false);
    if (decodedSlots.isEmpty ||
        decodedSlots.length > 8 ||
        decodedSlots.map((slot) => slot.slotId).toSet().length !=
            decodedSlots.length ||
        !_strictlyIncreasing(
          decodedSlots.map((slot) => int.parse(slot.slotId)).toList(),
        )) {
      throw _malformed();
    }
    return MedicationScheduleVersion(
      id: id,
      medicationId: _string(data['medicationID']),
      version: version,
      petId: _string(data['petID']),
      petNameSnapshot: _string(data['petName']),
      medicationNameSnapshot: _string(data['medicationName']),
      weekdays: List.unmodifiable(decodedWeekdays),
      slots: List.unmodifiable(decodedSlots),
      timeZoneIdentifier: _string(data['timeZoneIdentifier']),
      effectiveFromLocalDate: _dateString(start),
      effectiveUntilLocalDate: end == null ? null : _dateString(end),
    );
  }

  static MedicationOccurrence _decodeOccurrence(
    MedicationStoredDocument document,
    bool isServerConfirmed,
  ) {
    final data = document.data;
    final id = _string(data['id'], document.id);
    final medicationId = _string(data['medicationID']);
    final scheduleVersionId = _string(data['scheduleVersionID']);
    final scheduleVersion = _integer(data['scheduleVersion']);
    final slotId = _string(data['slotID']);
    final localDate = _string(data['localDate']);
    final responsibility = MedicationResponsibilityStatus.values.byName(
      _string(data['responsibilityStatus']),
    );
    final responsibleById = _nullableString(data['responsibleByID']);
    final responsibleByName = _nullableString(data['responsibleByName']);
    final claimedAt = _nullableDate(data['claimedAt']);
    final outcome = MedicationOutcomeStatus.values.byName(
      _string(data['outcomeStatus']),
    );
    final outcomeById = _nullableString(data['outcomeByID']);
    final outcomeByName = _nullableString(data['outcomeByName']);
    final outcomeAt = _nullableDate(data['outcomeAt']);
    final reason = data['skippedReasonCode'] == null
        ? null
        : MedicationSkipReasonCode.values.byName(
            _string(data['skippedReasonCode']),
          );
    final reasonNote = _nullableString(data['skippedReasonNote']);
    final revision = _integer(data['revision']);
    final canonicalId =
        '${medicationId}_${scheduleVersionId}_${localDate}_$slotId';
    final responsibilityValid = switch (responsibility) {
      MedicationResponsibilityStatus.unclaimed =>
        responsibleById == null &&
            responsibleByName == null &&
            claimedAt == null,
      MedicationResponsibilityStatus.claimed =>
        responsibleById != null &&
            responsibleByName != null &&
            claimedAt != null,
    };
    final outcomeValid = switch (outcome) {
      MedicationOutcomeStatus.unresolved =>
        outcomeById == null &&
            outcomeByName == null &&
            outcomeAt == null &&
            reason == null &&
            reasonNote == null,
      MedicationOutcomeStatus.administered =>
        outcomeById != null &&
            outcomeByName != null &&
            outcomeAt != null &&
            reason == null &&
            reasonNote == null,
      MedicationOutcomeStatus.skipped =>
        outcomeById != null &&
            outcomeByName != null &&
            outcomeAt != null &&
            reason != null &&
            (reason != MedicationSkipReasonCode.other || reasonNote != null),
    };
    if (id != document.id ||
        id != canonicalId ||
        scheduleVersion < 1 ||
        scheduleVersionId != _versionId(scheduleVersion) ||
        !RegExp(r'^([01]\d|2[0-3])[0-5]\d$').hasMatch(slotId) ||
        _dateString(_localDate(localDate)) != localDate ||
        revision < 0 ||
        !responsibilityValid ||
        !outcomeValid) {
      throw _malformed();
    }
    return MedicationOccurrence(
      id: id,
      medicationId: medicationId,
      scheduleVersionId: scheduleVersionId,
      scheduleVersion: scheduleVersion,
      slotId: slotId,
      localDate: localDate,
      dueAt: _date(data['dueAt']),
      petId: _string(data['petID']),
      petNameSnapshot: _string(data['petName']),
      medicationNameSnapshot: _string(data['medicationName']),
      doseText: _string(data['doseText']),
      instructions: _nullableString(data['instructions']),
      responsibilityStatus: responsibility,
      responsibleById: responsibleById,
      responsibleByNameSnapshot: responsibleByName,
      claimedAt: claimedAt,
      outcomeStatus: outcome,
      outcomeById: outcomeById,
      outcomeByNameSnapshot: outcomeByName,
      outcomeAt: outcomeAt,
      skippedReasonCode: reason,
      skippedReasonNote: reasonNote,
      revision: revision,
      isServerConfirmed: isServerConfirmed,
    );
  }

  String _newMutationId() {
    final random = _random.nextInt(1 << 32).toRadixString(16);
    return '${DateTime.now().microsecondsSinceEpoch}-$random';
  }

  static String _stablePayload(Map<String, Object?> payload) {
    return jsonEncode(_canonicalJson(payload));
  }

  static Object? _canonicalJson(Object? value) => switch (value) {
    Map<String, Object?>() => {
      for (final key in (value.keys.toList()..sort()))
        key: _canonicalJson(value[key]),
    },
    List<Object?>() => value.map(_canonicalJson).toList(growable: false),
    null || String() || num() || bool() => value,
    _ => throw const MedicationRepositoryException(
      MedicationRepositoryErrorCode.invalidInput,
    ),
  };

  static String _slotId(MedicationPlanSlotInput slot) =>
      '${slot.hour.toString().padLeft(2, '0')}'
      '${slot.minute.toString().padLeft(2, '0')}';

  static bool _validId(String value) =>
      value.isNotEmpty && value.length <= 200 && !value.contains('/');

  static String? _nullableTrim(String? value) {
    final normalized = value?.trim();
    return normalized == null || normalized.isEmpty ? null : normalized;
  }

  static String _string(Object? value, [String? fallback]) {
    final result = value ?? fallback;
    if (result is! String || result.isEmpty) throw _malformed();
    return result;
  }

  static String? _nullableString(Object? value) =>
      value == null ? null : _string(value);

  static int _integer(Object? value) {
    if (value is! int) throw _malformed();
    return value;
  }

  static bool _boolean(Object? value) {
    if (value is! bool) throw _malformed();
    return value;
  }

  static DateTime _date(Object? value) {
    if (value is Timestamp) return value.toDate().toUtc();
    if (value is DateTime) return value.toUtc();
    throw _malformed();
  }

  static DateTime? _nullableDate(Object? value) =>
      value == null ? null : _date(value);

  static DateTime _localDate(String value) {
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) throw _malformed();
    final parsed = DateTime.tryParse(value);
    if (parsed == null || _dateString(parsed) != value) throw _malformed();
    return parsed;
  }

  static String _dateString(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';

  static String _versionId(int version) =>
      'v${version.toString().padLeft(6, '0')}';

  static bool _strictlyIncreasing(List<int> values) {
    for (var index = 1; index < values.length; index += 1) {
      if (values[index] <= values[index - 1]) return false;
    }
    return true;
  }

  static MedicationRepositoryException _malformed([String? diagnosticCode]) =>
      MedicationRepositoryException(
        MedicationRepositoryErrorCode.malformedData,
        diagnosticCode: diagnosticCode,
      );

  static MedicationRepositoryException _mapped(Object error) {
    if (error is MedicationRepositoryException) return error;
    final code = switch (error) {
      FirebaseFunctionsException() => error.code,
      FirebaseException() => error.code,
      _ => 'unknown',
    };
    if (code == 'already-exists') {
      final details = error is FirebaseFunctionsException
          ? error.details
          : null;
      final terminal = details is Map && details['outcomeStatus'] != null;
      return MedicationRepositoryException(
        terminal
            ? MedicationRepositoryErrorCode.terminalConflict
            : MedicationRepositoryErrorCode.responsibilityConflict,
      );
    }
    return MedicationRepositoryException(switch (code) {
      'invalid-argument' => MedicationRepositoryErrorCode.invalidInput,
      'permission-denied' ||
      'unauthenticated' => MedicationRepositoryErrorCode.permission,
      'aborted' => MedicationRepositoryErrorCode.stale,
      'unavailable' ||
      'deadline-exceeded' ||
      'network-request-failed' => MedicationRepositoryErrorCode.network,
      'data-loss' => MedicationRepositoryErrorCode.malformedData,
      _ => MedicationRepositoryErrorCode.backendUnavailable,
    });
  }
}
