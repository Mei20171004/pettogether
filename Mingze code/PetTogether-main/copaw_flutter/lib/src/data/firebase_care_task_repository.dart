import 'dart:async';

import 'package:firebase_core/firebase_core.dart';

import '../domain/legacy_firestore_codec.dart';
import '../domain/models.dart';
import '../domain/time_zone_identifier.dart';
import 'care_task_gateway.dart';
import 'care_task_repository.dart';
import 'firebase_care_task_gateway.dart';
import 'household_data_gateway.dart';
import 'household_repository.dart';

final class FirebaseCareTaskRepository
    implements CareTaskRepository, PetBoundCareTaskWriter {
  FirebaseCareTaskRepository({CareTaskGateway? gateway})
    : _gateway = gateway ?? FirebaseCareTaskGateway();

  final CareTaskGateway _gateway;
  final LegacyFirestoreCodec _codec = const LegacyFirestoreCodec();
  StreamSubscription<StoredCareDocuments>? _routineSubscription;
  StreamSubscription<StoredCareDocuments>? _taskSubscription;
  StreamController<CareTaskSnapshot>? _controller;
  int _generation = 0;

  @override
  Stream<CareTaskSnapshot> observeCare(String householdId) {
    final controller = StreamController<CareTaskSnapshot>();
    unawaited(_replaceObservation(householdId, controller));
    return controller.stream;
  }

  Future<void> _replaceObservation(
    String householdId,
    StreamController<CareTaskSnapshot> controller,
  ) async {
    await stopObserving();
    final generation = ++_generation;
    _controller = controller;
    List<StoredDocument>? routineDocuments;
    List<StoredDocument>? taskDocuments;
    var routinesServerConfirmed = false;
    var tasksServerConfirmed = false;

    void emitIfReady() {
      if (generation != _generation || controller.isClosed) return;
      if (routineDocuments == null || taskDocuments == null) return;

      final routines = <CareRoutine>[];
      final tasks = <CareTask>[];
      final diagnostics = <DomainDiagnostic>[];
      for (final document in routineDocuments!) {
        final result = _codec.decodeRoutine(document.id, document.data);
        diagnostics.addAll(result.diagnostics);
        if (result.value case final CareRoutine value) routines.add(value);
      }
      for (final document in taskDocuments!) {
        final result = _codec.decodeTask(document.id, document.data);
        diagnostics.addAll(result.diagnostics);
        if (result.value case final CareTask value) tasks.add(value);
      }
      controller.add(
        CareTaskSnapshot(
          routines: List.unmodifiable(routines),
          tasks: List.unmodifiable(tasks),
          diagnostics: List.unmodifiable(diagnostics),
          isServerConfirmed: routinesServerConfirmed && tasksServerConfirmed,
        ),
      );
    }

    void addError(Object error) {
      if (generation == _generation && !controller.isClosed) {
        controller.addError(_mapped(error));
      }
    }

    _routineSubscription = _gateway.observeRoutines(householdId).listen((
      stored,
    ) {
      if (generation != _generation) return;
      routineDocuments = stored.documents;
      routinesServerConfirmed = stored.isServerConfirmed;
      emitIfReady();
    }, onError: addError);
    _taskSubscription = _gateway.observeTasks(householdId).listen((stored) {
      if (generation != _generation) return;
      taskDocuments = stored.documents;
      tasksServerConfirmed = stored.isServerConfirmed;
      emitIfReady();
    }, onError: addError);
  }

  @override
  Future<String> createOneOffTask({
    required String householdId,
    required String title,
    required CareCategory category,
    required DateTime dueTime,
    required CarePriority priority,
    required String createdById,
    required String createdByName,
  }) async {
    final petName = await _resolveLegacyPetName(householdId);
    return createOneOffTaskForPet(
      householdId: householdId,
      petId: legacyPrimaryPetId,
      petName: petName,
      title: title,
      category: category,
      dueTime: dueTime,
      priority: priority,
      createdById: createdById,
      createdByName: createdByName,
    );
  }

  @override
  Future<String> createOneOffTaskForPet({
    required String householdId,
    required String petId,
    required String petName,
    required String title,
    required CareCategory category,
    required DateTime dueTime,
    required CarePriority priority,
    required String createdById,
    required String createdByName,
  }) async {
    final normalizedTitle = title.trim();
    final normalizedCreator = createdByName.trim();
    final normalizedPetId = petId.trim();
    final normalizedPetName = petName.trim();
    if (householdId.isEmpty ||
        createdById.isEmpty ||
        !_validPetId(normalizedPetId) ||
        !_validLength(normalizedPetName, 60) ||
        normalizedTitle.isEmpty ||
        normalizedTitle.length > 120 ||
        normalizedCreator.isEmpty ||
        normalizedCreator.length > 50) {
      throw const HouseholdRepositoryException(
        HouseholdRepositoryErrorCode.invalidInput,
      );
    }

    final taskId = _gateway.newTaskId(householdId);
    final command = CreateOneOffTaskCommand(
      householdId: householdId,
      taskId: taskId,
      title: normalizedTitle,
      category: category.name,
      dueTime: dueTime,
      priority: priority.name,
      createdById: createdById,
      createdByName: normalizedCreator,
      petId: normalizedPetId,
      petName: normalizedPetName,
    );
    try {
      await _gateway.createOneOffTask(command);
      return taskId;
    } on Object catch (error) {
      throw _mapped(error);
    }
  }

  @override
  Future<String> createRoutine({
    required String householdId,
    required String title,
    required CareCategory category,
    required CarePriority priority,
    required CareRoutineFrequency frequency,
    required List<int> weekdays,
    required int hour,
    required int minute,
    required DateTime startDate,
    required String timeZoneIdentifier,
    required String createdById,
    required String createdByName,
  }) async {
    final petName = await _resolveLegacyPetName(householdId);
    return createRoutineForPet(
      householdId: householdId,
      petId: legacyPrimaryPetId,
      petName: petName,
      title: title,
      category: category,
      priority: priority,
      frequency: frequency,
      weekdays: weekdays,
      hour: hour,
      minute: minute,
      startDate: startDate,
      timeZoneIdentifier: timeZoneIdentifier,
      createdById: createdById,
      createdByName: createdByName,
    );
  }

  @override
  Future<String> createRoutineForPet({
    required String householdId,
    required String petId,
    required String petName,
    required String title,
    required CareCategory category,
    required CarePriority priority,
    required CareRoutineFrequency frequency,
    required List<int> weekdays,
    required int hour,
    required int minute,
    required DateTime startDate,
    required String timeZoneIdentifier,
    required String createdById,
    required String createdByName,
  }) async {
    final normalizedTitle = title.trim();
    final normalizedCreator = createdByName.trim();
    final normalizedPetId = petId.trim();
    final normalizedPetName = petName.trim();
    final validWeekdays =
        weekdays.isNotEmpty &&
        weekdays.length <= 7 &&
        weekdays.toSet().length == weekdays.length &&
        weekdays.every((day) => day >= 1 && day <= 7);
    if (householdId.isEmpty ||
        createdById.isEmpty ||
        !_validPetId(normalizedPetId) ||
        !_validLength(normalizedPetName, 60) ||
        normalizedTitle.isEmpty ||
        normalizedTitle.length > 120 ||
        normalizedCreator.isEmpty ||
        normalizedCreator.length > 50 ||
        hour < 0 ||
        hour > 23 ||
        minute < 0 ||
        minute > 59 ||
        !validWeekdays ||
        !isPlausibleTimeZoneIdentifier(timeZoneIdentifier)) {
      throw const HouseholdRepositoryException(
        HouseholdRepositoryErrorCode.invalidInput,
      );
    }
    final routineId = _gateway.newRoutineId(householdId);
    try {
      await _gateway.createRoutine(
        CreateRoutineCommand(
          householdId: householdId,
          routineId: routineId,
          title: normalizedTitle,
          category: category.name,
          priority: priority.name,
          frequency: frequency.name,
          weekdays: List.unmodifiable(weekdays),
          hour: hour,
          minute: minute,
          startDate: startDate,
          timeZoneIdentifier: timeZoneIdentifier,
          createdById: createdById,
          createdByName: normalizedCreator,
          petId: normalizedPetId,
          petName: normalizedPetName,
        ),
      );
      return routineId;
    } on Object catch (error) {
      throw _mapped(error);
    }
  }

  @override
  Future<void> stopObserving() async {
    _generation += 1;
    final routine = _routineSubscription;
    final task = _taskSubscription;
    final controller = _controller;
    _routineSubscription = null;
    _taskSubscription = null;
    _controller = null;
    await routine?.cancel();
    await task?.cancel();
    await controller?.close();
  }

  Future<String> _resolveLegacyPetName(String householdId) async {
    if (householdId.isEmpty) {
      throw const HouseholdRepositoryException(
        HouseholdRepositoryErrorCode.invalidInput,
      );
    }
    try {
      final document = await _gateway.readHousehold(householdId);
      if (!document.exists) {
        throw const HouseholdRepositoryException(
          HouseholdRepositoryErrorCode.malformedData,
        );
      }
      final household = _codec
          .decodeHousehold(document.id, document.data)
          .value;
      if (household == null) {
        throw const HouseholdRepositoryException(
          HouseholdRepositoryErrorCode.malformedData,
        );
      }
      return household.petName;
    } on Object catch (error) {
      throw _mapped(error);
    }
  }

  static bool _validPetId(String value) =>
      value.isNotEmpty && value.length <= 128 && !value.contains('/');

  static bool _validLength(String value, int maximum) =>
      value.isNotEmpty && value.length <= maximum;

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
    return careTaskError(error);
  }
}
