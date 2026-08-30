import 'package:cloud_firestore/cloud_firestore.dart';

import 'models.dart';
import 'time_zone_identifier.dart';

enum DomainDiagnosticCode {
  malformedData,
  legacyNeedsTimezone,
  legacyUnsafeToMutate,
  partialAssignmentRequest,
  legacySynthesizedPet,
}

final class DomainDiagnostic {
  const DomainDiagnostic({
    required this.code,
    required this.documentId,
    required this.message,
    this.field,
  });

  final DomainDiagnosticCode code;
  final String documentId;
  final String message;
  final String? field;
}

final class DomainDecodeResult<T> {
  const DomainDecodeResult({required this.value, this.diagnostics = const []});

  final T? value;
  final List<DomainDiagnostic> diagnostics;

  bool get hasValue => value != null;
  bool get hasDiagnostics => diagnostics.isNotEmpty;
}

final class LegacyFirestoreCodec {
  const LegacyFirestoreCodec();

  DomainDecodeResult<Pet> decodePet(
    String documentId,
    Map<String, Object?> data,
  ) {
    final name = _string(data['name']);
    final rawSpecies = data['species'];
    final species = rawSpecies == null
        ? null
        : _enumValue(rawSpecies, PetSpecies.values, _petSpeciesWireValue);
    final isArchived = data['isArchived'] is bool
        ? data['isArchived'] as bool
        : null;
    final createdAt = _dateTime(data['createdAt']);
    final updatedAt = _dateTime(data['updatedAt']);
    if (name == null ||
        (rawSpecies != null && species == null) ||
        isArchived == null ||
        createdAt == null ||
        updatedAt == null) {
      return _malformed(
        documentId,
        'Pet contains missing or invalid canonical fields.',
      );
    }
    return DomainDecodeResult(
      value: Pet(
        id: documentId,
        name: name,
        species: species,
        isArchived: isArchived,
        createdAt: createdAt,
        updatedAt: updatedAt,
      ),
    );
  }

  Map<String, Object?> encodePetStorageFields(Pet pet) {
    if (pet.id.isEmpty ||
        pet.name.isEmpty ||
        pet.name.length > 60 ||
        pet.createdAt == null ||
        pet.updatedAt == null) {
      throw ArgumentError('Pet cannot be encoded with invalid base fields.');
    }
    return <String, Object?>{
      'id': pet.id,
      'name': pet.name,
      'species': pet.species == null
          ? null
          : _petSpeciesWireValue(pet.species!),
      'isArchived': pet.isArchived,
      'createdAt': Timestamp.fromDate(pet.createdAt!),
      'updatedAt': Timestamp.fromDate(pet.updatedAt!),
    };
  }

  DomainDecodeResult<Household> decodeHousehold(
    String documentId,
    Map<String, Object?> data,
  ) {
    final name = _string(data['name']);
    final inviteCode = _string(data['inviteCode']);
    final petName = _string(data['petName']);
    if (name == null || inviteCode == null || petName == null) {
      return _malformed(
        documentId,
        'Household requires name, inviteCode, and petName strings.',
      );
    }

    final rawTimeZone = _string(data['timeZoneIdentifier']);
    final timeZone =
        rawTimeZone != null && isPlausibleTimeZoneIdentifier(rawTimeZone)
        ? rawTimeZone
        : null;
    final diagnostics = <DomainDiagnostic>[];
    if (timeZone == null) {
      diagnostics.add(
        DomainDiagnostic(
          code: DomainDiagnosticCode.legacyNeedsTimezone,
          documentId: documentId,
          field: 'timeZoneIdentifier',
          message:
              'Household timezone must be repaired before saving schedules.',
        ),
      );
    }

    return DomainDecodeResult(
      value: Household(
        id: documentId,
        name: name,
        inviteCode: inviteCode,
        petName: petName,
        timeZoneIdentifier: timeZone,
        ownerId: _string(data['ownerID']),
      ),
      diagnostics: diagnostics,
    );
  }

  Map<String, Object?> encodeHouseholdStorageFields(Household household) {
    final timeZone = household.timeZoneIdentifier;
    if (timeZone == null || !isPlausibleTimeZoneIdentifier(timeZone)) {
      throw ArgumentError.value(
        timeZone,
        'household.timeZoneIdentifier',
        'A repaired timezone is required for canonical writes.',
      );
    }
    return <String, Object?>{
      'id': household.id,
      'name': household.name,
      'inviteCode': household.inviteCode,
      'petName': household.petName,
      'timeZoneIdentifier': timeZone,
    };
  }

  DomainDecodeResult<Caregiver> decodeCaregiver(
    String documentId,
    Map<String, Object?> data,
  ) {
    final displayName = _string(data['displayName']);
    if (displayName == null) {
      return _malformed(documentId, 'Caregiver requires displayName string.');
    }
    return DomainDecodeResult(
      value: Caregiver(id: documentId, displayName: displayName),
    );
  }

  Map<String, Object?> encodeCaregiverStorageFields(Caregiver caregiver) =>
      <String, Object?>{
        'id': caregiver.id,
        'displayName': caregiver.displayName,
      };

  DomainDecodeResult<CareRoutine> decodeRoutine(
    String documentId,
    Map<String, Object?> data,
  ) {
    final title = _string(data['title']);
    final category = _enumValue(
      data['category'],
      CareCategory.values,
      _careCategoryWireValue,
    );
    final priority = _enumValue(
      data['priority'],
      CarePriority.values,
      _carePriorityWireValue,
    );
    final rawFrequency = data['frequency'];
    final frequency = rawFrequency == null
        ? CareRoutineFrequency.daily
        : _enumValue(
            rawFrequency,
            CareRoutineFrequency.values,
            _routineFrequencyWireValue,
          );
    final weekdays = data['weekdays'] == null
        ? const [1, 2, 3, 4, 5, 6, 7]
        : _intList(data['weekdays']);
    final hour = _int(data['hour']);
    final minute = _int(data['minute']);
    final startDate = _dateTime(data['startDate']);
    final timeZone = _string(data['timeZoneIdentifier']);
    final createdById = _string(data['createdByID']);
    final createdByName = _string(data['createdByName']);
    final isActive = data['isActive'] is bool ? data['isActive'] as bool : null;
    final petId = _string(data['petID']) ?? legacyPrimaryPetId;
    final petName = _string(data['petName']);

    final validWeekdays =
        weekdays != null &&
        weekdays.isNotEmpty &&
        weekdays.every((weekday) => weekday >= 1 && weekday <= 7) &&
        weekdays.toSet().length == weekdays.length;
    final validTime =
        hour != null &&
        hour >= 0 &&
        hour <= 23 &&
        minute != null &&
        minute >= 0 &&
        minute <= 59;
    if (title == null ||
        category == null ||
        priority == null ||
        frequency == null ||
        !validWeekdays ||
        !validTime ||
        startDate == null ||
        timeZone == null ||
        !isPlausibleTimeZoneIdentifier(timeZone) ||
        createdById == null ||
        createdByName == null ||
        isActive == null) {
      return _malformed(
        documentId,
        'Routine contains missing or invalid canonical fields.',
      );
    }

    return DomainDecodeResult(
      value: CareRoutine(
        id: documentId,
        title: title,
        category: category,
        priority: priority,
        frequency: frequency,
        weekdays: List.unmodifiable(weekdays),
        hour: hour,
        minute: minute,
        startDate: startDate,
        timeZoneIdentifier: timeZone,
        createdById: createdById,
        createdByNameSnapshot: createdByName,
        isActive: isActive,
        petId: petId,
        petNameSnapshot: petName,
      ),
    );
  }

  Map<String, Object?> encodeRoutineStorageFields(CareRoutine routine) {
    final weekdaysAreValid =
        routine.weekdays.isNotEmpty &&
        routine.weekdays.every((day) => day >= 1 && day <= 7) &&
        routine.weekdays.toSet().length == routine.weekdays.length;
    if (!weekdaysAreValid ||
        routine.hour < 0 ||
        routine.hour > 23 ||
        routine.minute < 0 ||
        routine.minute > 59 ||
        !isPlausibleTimeZoneIdentifier(routine.timeZoneIdentifier)) {
      throw ArgumentError('Routine cannot be encoded with invalid schedule.');
    }
    return <String, Object?>{
      'id': routine.id,
      'title': routine.title,
      'category': _careCategoryWireValue(routine.category),
      'priority': _carePriorityWireValue(routine.priority),
      'frequency': _routineFrequencyWireValue(routine.frequency),
      'weekdays': routine.weekdays,
      'hour': routine.hour,
      'minute': routine.minute,
      'startDate': Timestamp.fromDate(routine.startDate),
      'timeZoneIdentifier': routine.timeZoneIdentifier,
      'createdByID': routine.createdById,
      'createdByName': routine.createdByNameSnapshot,
      'isActive': routine.isActive,
      'petID': routine.petId,
      'petName': routine.petNameSnapshot,
    };
  }

  DomainDecodeResult<CareTask> decodeTask(
    String documentId,
    Map<String, Object?> data,
  ) {
    final title = _string(data['title']);
    final category = _enumValue(
      data['category'],
      CareCategory.values,
      _careCategoryWireValue,
    );
    final dueTime = _dateTime(data['dueTime']);
    final status = _taskStatus(data['status']);
    final createdBy = _string(data['createdBy']);
    if (title == null ||
        category == null ||
        dueTime == null ||
        status == null ||
        createdBy == null) {
      return _malformed(
        documentId,
        'Task requires title, category, dueTime, status, and createdBy.',
      );
    }

    final kind =
        _enumValue(data['kind'], CareTaskKind.values, _taskKindWireValue) ??
        CareTaskKind.oneOff;
    final priority =
        _enumValue(
          data['priority'],
          CarePriority.values,
          _carePriorityWireValue,
        ) ??
        CarePriority.normal;
    final createdAt = data['createdAt'] == null
        ? dueTime
        : _dateTime(data['createdAt']);
    final revision = data['revision'] == null ? 0 : _int(data['revision']);
    if (createdAt == null || revision == null) {
      return _malformed(
        documentId,
        'Task createdAt must be a Timestamp and revision must be an integer.',
      );
    }

    final diagnostics = <DomainDiagnostic>[];
    const canonicalNullableFields = <String>{
      'routineID',
      'assignmentRequestID',
      'assignmentMode',
      'requestedByID',
      'requestedByName',
      'requestedToID',
      'requestedToName',
      'assignmentRequestedAt',
      'assigneeID',
      'assigneeName',
      'claimedAt',
      'completedByID',
      'completedBy',
      'completedAt',
    };
    final rawRevision = _int(data['revision']);
    final hasCanonicalPetSnapshot =
        _string(data['petID']) != null && _string(data['petName']) != null;
    final isLegacyUnsafe =
        data['id'] != documentId ||
        data['status'] == 'pending' ||
        !CareTaskKind.values.any(
          (value) => _taskKindWireValue(value) == data['kind'],
        ) ||
        !CarePriority.values.any(
          (value) => _carePriorityWireValue(value) == data['priority'],
        ) ||
        data['createdAt'] is! Timestamp ||
        rawRevision == null ||
        rawRevision < 0 ||
        _string(data['createdByID']) == null ||
        !hasCanonicalPetSnapshot ||
        canonicalNullableFields.any((field) => !data.containsKey(field));
    if (isLegacyUnsafe) {
      diagnostics.add(
        DomainDiagnostic(
          code: DomainDiagnosticCode.legacyUnsafeToMutate,
          documentId: documentId,
          message:
              'Task remains readable but needs canonical repair before mutation.',
        ),
      );
    }
    final assignmentRequest = _decodeAssignmentRequest(
      documentId,
      data,
      diagnostics,
    );
    if (diagnostics.any(
      (item) => item.code == DomainDiagnosticCode.partialAssignmentRequest,
    )) {
      diagnostics.add(
        DomainDiagnostic(
          code: DomainDiagnosticCode.legacyUnsafeToMutate,
          documentId: documentId,
          message: 'Partial assignment data must be repaired before mutation.',
        ),
      );
    }

    final task = CareTask(
      id: documentId,
      title: title,
      category: category,
      dueTime: dueTime,
      kind: kind,
      priority: priority,
      routineId: _string(data['routineID']),
      status: status,
      assignmentRequest: assignmentRequest,
      assigneeId: _string(data['assigneeID']),
      assigneeNameSnapshot: _string(data['assigneeName']),
      claimedAt: _nullableDateTime(data, 'claimedAt', documentId, diagnostics),
      createdById: _string(data['createdByID']),
      createdBy: createdBy,
      createdAt: createdAt,
      completedById: _string(data['completedByID']),
      completedBy: _string(data['completedBy']),
      completedAt: _nullableDateTime(
        data,
        'completedAt',
        documentId,
        diagnostics,
      ),
      revision: revision,
      petId: _string(data['petID']) ?? legacyPrimaryPetId,
      petNameSnapshot: _string(data['petName']),
    );
    final stateIsConsistent = switch (task.status) {
      CareTaskStatus.unclaimed =>
        task.assigneeId == null &&
            task.assigneeNameSnapshot == null &&
            task.claimedAt == null &&
            task.completedById == null &&
            task.completedBy == null &&
            task.completedAt == null,
      CareTaskStatus.claimed =>
        task.assigneeId != null &&
            task.assigneeNameSnapshot != null &&
            task.claimedAt != null &&
            task.assignmentRequest == null &&
            task.completedById == null &&
            task.completedBy == null &&
            task.completedAt == null,
      CareTaskStatus.completed =>
        task.assigneeId != null &&
            task.assigneeNameSnapshot != null &&
            task.claimedAt != null &&
            task.assignmentRequest == null &&
            task.completedById != null &&
            task.completedBy != null &&
            task.completedAt != null &&
            task.completedById == task.assigneeId,
    };
    if (!stateIsConsistent) {
      diagnostics.add(
        DomainDiagnostic(
          code: DomainDiagnosticCode.malformedData,
          documentId: documentId,
          field: 'status',
          message: 'Task state and actor/time overlays are inconsistent.',
        ),
      );
      diagnostics.add(
        DomainDiagnostic(
          code: DomainDiagnosticCode.legacyUnsafeToMutate,
          documentId: documentId,
          message: 'Inconsistent task state must be repaired before mutation.',
        ),
      );
    }

    return DomainDecodeResult(value: task, diagnostics: diagnostics);
  }

  Map<String, Object?> encodeTaskStorageFields(CareTask task) {
    if (task.title.isEmpty || task.createdById == null || task.revision < 0) {
      throw ArgumentError('Task cannot be encoded with invalid base fields.');
    }
    final request = task.assignmentRequest;
    final stateIsConsistent = switch (task.status) {
      CareTaskStatus.unclaimed =>
        task.assigneeId == null &&
            task.assigneeNameSnapshot == null &&
            task.claimedAt == null &&
            task.completedById == null &&
            task.completedBy == null &&
            task.completedAt == null,
      CareTaskStatus.claimed =>
        request == null &&
            task.assigneeId != null &&
            task.assigneeNameSnapshot != null &&
            task.claimedAt != null &&
            task.completedById == null &&
            task.completedBy == null &&
            task.completedAt == null,
      CareTaskStatus.completed =>
        request == null &&
            task.assigneeId != null &&
            task.assigneeNameSnapshot != null &&
            task.claimedAt != null &&
            task.completedById == task.assigneeId &&
            task.completedBy != null &&
            task.completedAt != null,
    };
    if (!stateIsConsistent) {
      throw ArgumentError('Task cannot be encoded with inconsistent state.');
    }
    return <String, Object?>{
      'id': task.id,
      'title': task.title,
      'category': _careCategoryWireValue(task.category),
      'dueTime': Timestamp.fromDate(task.dueTime),
      'kind': _taskKindWireValue(task.kind),
      'priority': _carePriorityWireValue(task.priority),
      'routineID': task.routineId,
      'status': _taskStatusWireValue(task.status),
      'assignmentRequestID': request?.id,
      'assignmentMode': request == null
          ? null
          : _assignmentModeWireValue(request.mode),
      'requestedByID': request?.requestedById,
      'requestedByName': request?.requestedByNameSnapshot,
      'requestedToID': request?.requestedToId,
      'requestedToName': request?.requestedToNameSnapshot,
      'assignmentRequestedAt': request == null
          ? null
          : Timestamp.fromDate(request.createdAt),
      'assigneeID': task.assigneeId,
      'assigneeName': task.assigneeNameSnapshot,
      'claimedAt': task.claimedAt == null
          ? null
          : Timestamp.fromDate(task.claimedAt!),
      'createdByID': task.createdById,
      'createdBy': task.createdBy,
      'createdAt': Timestamp.fromDate(task.createdAt),
      'completedByID': task.completedById,
      'completedBy': task.completedBy,
      'completedAt': task.completedAt == null
          ? null
          : Timestamp.fromDate(task.completedAt!),
      'revision': task.revision,
      'petID': task.petId,
      'petName': task.petNameSnapshot,
    };
  }

  AssignmentRequest? _decodeAssignmentRequest(
    String documentId,
    Map<String, Object?> data,
    List<DomainDiagnostic> diagnostics,
  ) {
    const fields = <String>[
      'assignmentRequestID',
      'assignmentMode',
      'requestedByID',
      'requestedByName',
      'requestedToID',
      'requestedToName',
      'assignmentRequestedAt',
    ];
    final hasRequestValue = fields.any((field) => data[field] != null);
    if (!hasRequestValue) {
      return null;
    }

    final id = _string(data['assignmentRequestID']);
    final requestedById = _string(data['requestedByID']);
    final requestedByName = _string(data['requestedByName']);
    final requestedToId = _string(data['requestedToID']);
    final requestedToName = _string(data['requestedToName']);
    final createdAt = _dateTime(data['assignmentRequestedAt']);
    final rawMode = data['assignmentMode'];
    final mode = rawMode == null
        ? (requestedToId == null ? AssignmentMode.open : AssignmentMode.direct)
        : _enumValue(rawMode, AssignmentMode.values, _assignmentModeWireValue);
    final targetIsConsistent = mode == AssignmentMode.open
        ? requestedToId == null && requestedToName == null
        : requestedToId != null && requestedToName != null;
    if (id == null ||
        requestedById == null ||
        requestedByName == null ||
        createdAt == null ||
        mode == null ||
        !targetIsConsistent) {
      diagnostics.add(
        DomainDiagnostic(
          code: DomainDiagnosticCode.partialAssignmentRequest,
          documentId: documentId,
          field: 'assignmentRequestID',
          message:
              'Task assignment request overlay is partial or inconsistent.',
        ),
      );
      return null;
    }

    return AssignmentRequest(
      id: id,
      requestedById: requestedById,
      requestedByNameSnapshot: requestedByName,
      requestedToId: requestedToId,
      requestedToNameSnapshot: requestedToName,
      mode: mode,
      createdAt: createdAt,
    );
  }
}

DomainDecodeResult<T> _malformed<T>(String documentId, String message) =>
    DomainDecodeResult<T>(
      value: null,
      diagnostics: [
        DomainDiagnostic(
          code: DomainDiagnosticCode.malformedData,
          documentId: documentId,
          message: message,
        ),
      ],
    );

String? _string(Object? value) =>
    value is String && value.isNotEmpty ? value : null;

int? _int(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num && value.isFinite && value == value.roundToDouble()) {
    return value.toInt();
  }
  return null;
}

List<int>? _intList(Object? value) {
  if (value is! List) {
    return null;
  }
  final result = value.map(_int).toList();
  return result.any((item) => item == null) ? null : result.cast<int>();
}

DateTime? _dateTime(Object? value) =>
    value is Timestamp ? value.toDate().toUtc() : null;

DateTime? _nullableDateTime(
  Map<String, Object?> data,
  String field,
  String documentId,
  List<DomainDiagnostic> diagnostics,
) {
  final value = data[field];
  if (value == null) {
    return null;
  }
  final date = _dateTime(value);
  if (date == null) {
    diagnostics.add(
      DomainDiagnostic(
        code: DomainDiagnosticCode.malformedData,
        documentId: documentId,
        field: field,
        message: '$field must be a Timestamp when present.',
      ),
    );
  }
  return date;
}

T? _enumValue<T>(Object? value, List<T> values, String Function(T) wireValue) {
  if (value is! String) {
    return null;
  }
  for (final candidate in values) {
    if (wireValue(candidate) == value) {
      return candidate;
    }
  }
  return null;
}

CareTaskStatus? _taskStatus(Object? value) => switch (value) {
  'pending' || 'unclaimed' => CareTaskStatus.unclaimed,
  'claimed' => CareTaskStatus.claimed,
  'completed' => CareTaskStatus.completed,
  _ => null,
};

String _taskStatusWireValue(CareTaskStatus value) => switch (value) {
  CareTaskStatus.unclaimed => 'unclaimed',
  CareTaskStatus.claimed => 'claimed',
  CareTaskStatus.completed => 'completed',
};

String _taskKindWireValue(CareTaskKind value) => switch (value) {
  CareTaskKind.routine => 'routine',
  CareTaskKind.oneOff => 'oneOff',
};

String _carePriorityWireValue(CarePriority value) => switch (value) {
  CarePriority.normal => 'normal',
  CarePriority.urgent => 'urgent',
};

String _careCategoryWireValue(CareCategory value) => switch (value) {
  CareCategory.feeding => 'feeding',
  CareCategory.walking => 'walking',
  CareCategory.medication => 'medication',
  CareCategory.grooming => 'grooming',
  CareCategory.other => 'other',
};

String _assignmentModeWireValue(AssignmentMode value) => switch (value) {
  AssignmentMode.direct => 'direct',
  AssignmentMode.open => 'open',
};

String _routineFrequencyWireValue(CareRoutineFrequency value) =>
    switch (value) {
      CareRoutineFrequency.daily => 'daily',
      CareRoutineFrequency.selectedDays => 'selectedDays',
    };

String _petSpeciesWireValue(PetSpecies value) => switch (value) {
  PetSpecies.dog => 'dog',
  PetSpecies.cat => 'cat',
  PetSpecies.rabbit => 'rabbit',
  PetSpecies.other => 'other',
};
