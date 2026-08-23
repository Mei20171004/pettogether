import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';
import '../utils/care_calendar.dart';
import '../utils/extensions.dart';
import '../utils/id.dart';
import 'care_service.dart';

/// An offline [CareService] used when Firebase is not configured and for
/// previews/tests. It seeds a small demo household and persists to
/// `shared_preferences`, mirroring `MockCareService.swift` (minus the legacy
/// migration path).
class MockCareService implements CareService {
  static const demoPartner = Caregiver(
    id: 'demo-caregiver-partner',
    displayName: 'Alex',
  );

  Household _household = const Household(
    id: 'demo-household',
    name: 'Mochi Family',
    inviteCode: 'PAW123',
    pets: [Pet(id: 'demo-pet', name: 'Mochi', type: PetType.cat)],
  );

  List<CareTask> _tasks = [];
  List<Caregiver> _caregivers = [];
  List<CareRoutine> _routines = [];
  Caregiver? _caregiver;

  void Function(Household)? _householdObserver;
  void Function(List<CareTask>)? _taskObserver;
  void Function(List<Caregiver>)? _caregiverObserver;
  void Function(List<CareRoutine>)? _routineObserver;

  Future<void> _loaded = Future.value();

  MockCareService() {
    _loaded = _load();
  }

  // -------------------------------------------------------------------------
  // Persistence
  // -------------------------------------------------------------------------

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final householdRaw = prefs.getString('copaw.mock.household');
    final caregiverRaw = prefs.getString('copaw.mock.caregiver');
    final caregiversRaw = prefs.getString('copaw.mock.caregivers');
    final routinesRaw = prefs.getString('copaw.mock.routines');
    final tasksRaw = prefs.getString('copaw.mock.tasks');

    if (householdRaw != null) {
      _household =
          Household.fromJson(jsonDecode(householdRaw) as Map<String, dynamic>);
    }
    if (caregiverRaw != null) {
      _caregiver =
          Caregiver.fromJson(jsonDecode(caregiverRaw) as Map<String, dynamic>);
    }
    if (caregiversRaw != null) {
      _caregivers = (jsonDecode(caregiversRaw) as List)
          .map((e) => Caregiver.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    if (routinesRaw != null) {
      _routines = (jsonDecode(routinesRaw) as List)
          .map((e) => CareRoutine.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    if (tasksRaw != null) {
      _tasks = (jsonDecode(tasksRaw) as List)
          .map((e) => CareTask.fromJson(e as Map<String, dynamic>))
          .toList();
    }

    if (_caregiver == null) {
      _caregivers = [demoPartner];
    }
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        'copaw.mock.household', jsonEncode(_household.toJson()));
    if (_caregiver != null) {
      await prefs.setString(
          'copaw.mock.caregiver', jsonEncode(_caregiver!.toJson()));
    }
    await prefs.setString('copaw.mock.caregivers',
        jsonEncode(_caregivers.map((e) => e.toJson()).toList()));
    await prefs.setString('copaw.mock.routines',
        jsonEncode(_routines.map((e) => e.toJson()).toList()));
    await prefs.setString(
        'copaw.mock.tasks', jsonEncode(_tasks.map((e) => e.toJson()).toList()));
  }

  // -------------------------------------------------------------------------
  // Session
  // -------------------------------------------------------------------------

  @override
  Future<CareSession?> restoreSession() async {
    await _loaded;
    final caregiver = _caregiver;
    if (caregiver == null) return null;
    _ensureRoster(caregiver);
    await _persist();
    return CareSession(household: _household, caregiver: caregiver);
  }

  @override
  Future<CareSession> createHousehold({
    required String name,
    required String petName,
    required PetType petType,
    required String caregiverName,
  }) async {
    await _loaded;
    _household = _household.copyWith(
      name: name,
      pets: [Pet(id: uuid(), name: petName, type: petType)],
    );
    final caregiver = Caregiver(id: uuid(), displayName: caregiverName);
    _caregiver = caregiver;
    _caregivers = [caregiver, demoPartner];
    _routines = _seedRoutines(caregiver);
    _tasks = _seedTaskOverrides(caregiver, demoPartner);
    await _persist();
    _notifyAll();
    return CareSession(household: _household, caregiver: caregiver);
  }

  @override
  Future<CareSession> joinHousehold({
    required String inviteCode,
    required String caregiverName,
  }) async {
    await _loaded;
    final normalized = inviteCode.trim().toUpperCase();
    if (normalized != _household.inviteCode) {
      throw const CareServiceError(CareServiceErrorType.invalidInviteCode);
    }

    final caregiver = Caregiver(id: uuid(), displayName: caregiverName);
    _caregiver = caregiver;
    _ensureRoster(caregiver);
    if (_routines.isEmpty) {
      _routines = _seedRoutines(caregiver);
    }
    if (_tasks.isEmpty) {
      _tasks = _seedTaskOverrides(caregiver, demoPartner);
    }
    await _persist();
    _notifyAll();
    return CareSession(household: _household, caregiver: caregiver);
  }

  // -------------------------------------------------------------------------
  // Observers
  // -------------------------------------------------------------------------

  @override
  void observeHousehold({
    required String householdID,
    required void Function(Household) onChange,
    required void Function(Object error) onError,
  }) {
    if (householdID != _household.id) {
      onError(const CareServiceError(CareServiceErrorType.householdMismatch));
      return;
    }
    _householdObserver = onChange;
    onChange(_household);
  }

  @override
  void observeTasks({
    required String householdID,
    required void Function(List<CareTask>) onChange,
    required void Function(Object error) onError,
  }) {
    if (householdID != _household.id) {
      onError(const CareServiceError(CareServiceErrorType.householdMismatch));
      return;
    }
    _taskObserver = onChange;
    onChange(_tasks);
  }

  @override
  void observeCaregivers({
    required String householdID,
    required void Function(List<Caregiver>) onChange,
    required void Function(Object error) onError,
  }) {
    if (householdID != _household.id) {
      onError(const CareServiceError(CareServiceErrorType.householdMismatch));
      return;
    }
    _caregiverObserver = onChange;
    onChange(_caregivers);
  }

  @override
  void observeRoutines({
    required String householdID,
    required void Function(List<CareRoutine>) onChange,
    required void Function(Object error) onError,
  }) {
    if (householdID != _household.id) {
      onError(const CareServiceError(CareServiceErrorType.householdMismatch));
      return;
    }
    _routineObserver = onChange;
    onChange(_routines);
  }

  // -------------------------------------------------------------------------
  // Mutations
  // -------------------------------------------------------------------------

  @override
  Future<void> addTask(CareTask task, String householdID) async {
    _validateHousehold(householdID);
    if (_tasks.any((t) => t.id == task.id)) {
      throw const CareServiceError(CareServiceErrorType.duplicateTask);
    }
    if (task.kind != CareTaskKind.oneOff ||
        task.status != CareTaskStatus.unclaimed ||
        task.assigneeID != null ||
        task.completedAt != null) {
      throw const CareServiceError(CareServiceErrorType.invalidTransition);
    }
    if (task.createdByID != null) {
      _validateMemberID(task.createdByID!);
    }
    _tasks = [..._tasks, task];
    await _persist();
    _notifyTasks();
  }

  @override
  Future<void> addRoutine(CareRoutine routine, String householdID) async {
    _validateHousehold(householdID);
    _validateMemberID(routine.createdByID);
    if (_routines.any((r) => r.id == routine.id)) {
      throw const CareServiceError(CareServiceErrorType.duplicateRoutine);
    }
    if (routine.hour < 0 ||
        routine.hour >= 24 ||
        routine.minute < 0 ||
        routine.minute >= 60) {
      throw const CareServiceError(CareServiceErrorType.invalidTransition);
    }
    _routines = [..._routines, routine];
    await _persist();
    _notifyRoutines();
  }

  @override
  Future<void> updateProfile(Household household, Caregiver caregiver) async {
    _validateHousehold(household.id);
    final saved = _validatedMember(caregiver);

    final householdName = household.name.trim();
    final petName = household.petName.trim();
    final caregiverName = caregiver.displayName.trim();
    if (householdName.isEmpty ||
        householdName.length > 60 ||
        petName.isEmpty ||
        petName.length > 60 ||
        caregiverName.isEmpty ||
        caregiverName.length > 50) {
      throw const CareServiceError(CareServiceErrorType.invalidProfile);
    }

    _household =
        _household.copyWith(name: householdName, pets: household.pets);
    final updated = saved.copyWith(displayName: caregiverName);
    _caregiver = updated;
    _caregivers = [
      for (final c in _caregivers) c.id == updated.id ? updated : c,
    ];
    await _persist();
    _notifyAll();
  }

  @override
  Future<void> addPet(String householdID, Pet pet) async {
    _validateHousehold(householdID);
    _household = _household.copyWith(pets: [..._household.pets, pet]);
    await _persist();
    _notifyAll();
  }

  @override
  Future<void> updatePet(String householdID, Pet pet) async {
    _validateHousehold(householdID);
    _household = _household.copyWith(
      pets: [
        for (final p in _household.pets) p.id == pet.id ? pet : p,
      ],
    );
    await _persist();
    _notifyAll();
  }

  @override
  Future<void> removePet(String householdID, String petID) async {
    _validateHousehold(householdID);
    _household = _household.copyWith(
      pets: _household.pets.where((p) => p.id != petID).toList(),
    );
    await _persist();
    _notifyAll();
  }

  @override
  Future<void> claimTask(
    CareTask task,
    String householdID,
    Caregiver caregiver,
  ) async {
    _validateHousehold(householdID);
    final saved = _validatedMember(caregiver);
    final existing = _materialize(task);
    _requireUnclaimed(existing.task);

    final updated = existing.task.copyWith(
      status: CareTaskStatus.claimed,
      clearAssignmentRequest: true,
      assigneeID: saved.id,
      assigneeNameSnapshot: saved.displayName,
      claimedAt: DateTime.now(),
      revision: existing.task.revision + 1,
    );
    _replaceOrAppend(updated, existing.index);
  }

  @override
  Future<void> requestAssignment(
    CareTask task,
    String householdID,
    Caregiver requester,
    Caregiver requestedCaregiver,
  ) async {
    _validateHousehold(householdID);
    final savedRequester = _validatedMember(requester);
    final savedRecipient = _validatedMember(requestedCaregiver);
    if (savedRequester.id == savedRecipient.id) {
      throw const CareServiceError(CareServiceErrorType.cannotRequestSelf);
    }

    final existing = _materialize(task);
    _requireUnclaimed(existing.task);

    final request = existing.task.assignmentRequest;
    if (request != null) {
      if (request.requestedByID == savedRequester.id &&
          request.requestedToID == savedRecipient.id) {
        return;
      }
      throw const CareServiceError(CareServiceErrorType.assignmentRequestChanged);
    }

    final updated = existing.task.copyWith(
      assignmentRequest: AssignmentRequest(
        id: uuid(),
        requestedByID: savedRequester.id,
        requestedByNameSnapshot: savedRequester.displayName,
        requestedToID: savedRecipient.id,
        requestedToNameSnapshot: savedRecipient.displayName,
        createdAt: DateTime.now(),
      ),
      revision: existing.task.revision + 1,
    );
    _replaceOrAppend(updated, existing.index);
  }

  @override
  Future<void> requestOpenAssignment(
    CareTask task,
    String householdID,
    Caregiver requester,
  ) async {
    _validateHousehold(householdID);
    final savedRequester = _validatedMember(requester);
    final existing = _materialize(task);
    _requireUnclaimed(existing.task);

    final request = existing.task.assignmentRequest;
    if (request != null) {
      if (request.requestedByID == savedRequester.id &&
          request.mode == AssignmentMode.open) {
        return;
      }
      throw const CareServiceError(CareServiceErrorType.assignmentRequestChanged);
    }

    final updated = existing.task.copyWith(
      assignmentRequest: AssignmentRequest(
        id: uuid(),
        requestedByID: savedRequester.id,
        requestedByNameSnapshot: savedRequester.displayName,
        mode: AssignmentMode.open,
        createdAt: DateTime.now(),
      ),
      revision: existing.task.revision + 1,
    );
    _replaceOrAppend(updated, existing.index);
  }

  @override
  Future<void> acceptAssignmentRequest(
    String taskID,
    String requestID,
    String householdID,
    Caregiver caregiver,
  ) async {
    _validateHousehold(householdID);
    final saved = _validatedMember(caregiver);
    final index = _taskIndex(taskID);
    final task = _tasks[index];
    _requireUnclaimed(task);
    final request = task.assignmentRequest;
    if (request == null || request.id != requestID) {
      throw const CareServiceError(CareServiceErrorType.assignmentRequestChanged);
    }
    if (request.requestedToID != saved.id) {
      throw const CareServiceError(CareServiceErrorType.notRequestRecipient);
    }

    final updated = task.copyWith(
      status: CareTaskStatus.claimed,
      clearAssignmentRequest: true,
      assigneeID: saved.id,
      assigneeNameSnapshot: saved.displayName,
      claimedAt: DateTime.now(),
      revision: task.revision + 1,
    );
    _replaceOrAppend(updated, index);
  }

  @override
  Future<void> declineAssignmentRequest(
    String taskID,
    String requestID,
    String householdID,
    Caregiver caregiver,
  ) async {
    _validateHousehold(householdID);
    final saved = _validatedMember(caregiver);
    final index = _taskIndex(taskID);
    final task = _tasks[index];
    _requireUnclaimed(task);
    final request = task.assignmentRequest;
    if (request == null || request.id != requestID) {
      throw const CareServiceError(CareServiceErrorType.assignmentRequestChanged);
    }
    if (request.requestedToID != saved.id) {
      throw const CareServiceError(CareServiceErrorType.notRequestRecipient);
    }

    _replaceOrAppend(
      task.copyWith(
        clearAssignmentRequest: true,
        revision: task.revision + 1,
      ),
      index,
    );
  }

  @override
  Future<void> cancelAssignmentRequest(
    String taskID,
    String requestID,
    String householdID,
    Caregiver caregiver,
  ) async {
    _validateHousehold(householdID);
    final saved = _validatedMember(caregiver);
    final index = _taskIndex(taskID);
    final task = _tasks[index];
    _requireUnclaimed(task);
    final request = task.assignmentRequest;
    if (request == null || request.id != requestID) {
      throw const CareServiceError(CareServiceErrorType.assignmentRequestChanged);
    }
    if (request.requestedByID != saved.id) {
      throw const CareServiceError(CareServiceErrorType.notRequestOwner);
    }

    _replaceOrAppend(
      task.copyWith(
        clearAssignmentRequest: true,
        revision: task.revision + 1,
      ),
      index,
    );
  }

  @override
  Future<void> completeTask(
    String taskID,
    String householdID,
    Caregiver caregiver,
  ) async {
    _validateHousehold(householdID);
    final saved = _validatedMember(caregiver);
    final index = _taskIndex(taskID);
    final task = _tasks[index];

    switch (task.status) {
      case CareTaskStatus.unclaimed:
        throw const CareServiceError(CareServiceErrorType.taskNotClaimed);
      case CareTaskStatus.claimed:
        if (task.assigneeID != saved.id) {
          throw const CareServiceError(CareServiceErrorType.notAssignee);
        }
      case CareTaskStatus.completed:
        throw const CareServiceError(CareServiceErrorType.taskAlreadyCompleted);
    }

    final updated = task.copyWith(
      status: CareTaskStatus.completed,
      clearAssignmentRequest: true,
      completedByID: saved.id,
      completedBy: saved.displayName,
      completedAt: DateTime.now(),
      revision: task.revision + 1,
    );
    _replaceOrAppend(updated, index);
  }

  @override
  void stopObserving() {
    _householdObserver = null;
    _taskObserver = null;
    _caregiverObserver = null;
    _routineObserver = null;
  }

  @override
  void leaveHousehold() {
    stopObserving();
    _caregiver = null;
    SharedPreferences.getInstance().then((prefs) {
      prefs.remove('copaw.mock.caregiver');
    });
  }

  // -------------------------------------------------------------------------
  // Helpers
  // -------------------------------------------------------------------------

  void _validateHousehold(String householdID) {
    if (householdID != _household.id) {
      throw const CareServiceError(CareServiceErrorType.householdMismatch);
    }
  }

  Caregiver _validatedMember(Caregiver caregiver) {
    return _caregivers.firstWhere(
      (c) => c.id == caregiver.id,
      orElse: () =>
          throw const CareServiceError(CareServiceErrorType.notHouseholdMember),
    );
  }

  void _validateMemberID(String id) {
    if (!_caregivers.any((c) => c.id == id)) {
      throw const CareServiceError(CareServiceErrorType.notHouseholdMember);
    }
  }

  void _requireUnclaimed(CareTask task) {
    switch (task.status) {
      case CareTaskStatus.unclaimed:
        return;
      case CareTaskStatus.claimed:
        throw CareServiceError(
          CareServiceErrorType.taskAlreadyClaimed,
          assigneeName: task.assigneeNameSnapshot,
        );
      case CareTaskStatus.completed:
        throw const CareServiceError(CareServiceErrorType.taskAlreadyCompleted);
    }
  }

  int _taskIndex(String taskID) {
    final index = _tasks.indexWhere((t) => t.id == taskID);
    if (index < 0) {
      throw const CareServiceError(CareServiceErrorType.taskNotFound);
    }
    return index;
  }

  /// Returns the persisted task for [task], or the task itself when it is a
  /// valid, not-yet-materialized routine occurrence (index null).
  ({CareTask task, int? index}) _materialize(CareTask task) {
    final index = _tasks.indexWhere((t) => t.id == task.id);
    if (index >= 0) return (task: _tasks[index], index: index);

    final routineID = task.routineID;
    if (task.kind == CareTaskKind.routine && routineID != null) {
      final routine = _routines
          .where((r) => r.id == routineID && r.isActive)
          .firstOrNull;
      if (routine != null &&
          task.id == occurrenceID(routine, task.dueTime)) {
        return (task: task, index: null);
      }
    }
    throw const CareServiceError(CareServiceErrorType.taskNotFound);
  }

  void _replaceOrAppend(CareTask task, int? index) {
    if (index != null) {
      final copy = [..._tasks];
      copy[index] = task;
      _tasks = copy;
    } else {
      _tasks = [..._tasks, task];
    }
    _persist();
    _notifyTasks();
  }

  void _notifyTasks() => _taskObserver?.call(_tasks);
  void _notifyRoutines() => _routineObserver?.call(_routines);

  void _notifyAll() {
    _householdObserver?.call(_household);
    _taskObserver?.call(_tasks);
    _caregiverObserver?.call(_caregivers);
    _routineObserver?.call(_routines);
  }

  void _ensureRoster(Caregiver current) {
    _caregivers = [
      current,
      ..._caregivers.where(
          (c) => c.id != current.id && c.id != demoPartner.id),
      demoPartner,
    ];
  }

  List<CareRoutine> _seedRoutines(Caregiver caregiver) {
    final start = startOfDay(DateTime.now());
    return [
      CareRoutine(
        id: 'demo-routine-brush-coat',
        title: 'Brush coat',
        category: CareCategory.grooming,
        hour: 7,
        minute: 30,
        startDate: start,
        timeZoneIdentifier: _household.timeZoneIdentifier,
        createdByID: caregiver.id,
        createdByNameSnapshot: caregiver.displayName,
      ),
      CareRoutine(
        id: 'demo-routine-morning-meal',
        title: 'Morning meal',
        category: CareCategory.feeding,
        hour: 8,
        minute: 0,
        startDate: start,
        timeZoneIdentifier: _household.timeZoneIdentifier,
        createdByID: caregiver.id,
        createdByNameSnapshot: caregiver.displayName,
      ),
      CareRoutine(
        id: 'demo-routine-allergy-medicine',
        title: 'Give allergy medicine',
        category: CareCategory.medication,
        hour: 10,
        minute: 30,
        startDate: start,
        timeZoneIdentifier: _household.timeZoneIdentifier,
        createdByID: caregiver.id,
        createdByNameSnapshot: caregiver.displayName,
      ),
      CareRoutine(
        id: 'demo-routine-evening-walk',
        title: 'Evening walk',
        category: CareCategory.walking,
        hour: 18,
        minute: 30,
        startDate: start,
        timeZoneIdentifier: _household.timeZoneIdentifier,
        createdByID: caregiver.id,
        createdByNameSnapshot: caregiver.displayName,
      ),
    ];
  }

  List<CareTask> _seedTaskOverrides(
    Caregiver caregiver,
    Caregiver partner,
  ) {
    final routine = _routines.where((r) => r.id == 'demo-routine-brush-coat').firstOrNull;
    if (routine == null) return [];
    final due = dueTimeForRoutine(routine, DateTime.now());
    if (due == null) return [];

    return [
      CareTask(
        id: occurrenceID(routine, due),
        title: routine.title,
        category: routine.category,
        dueTime: due,
        kind: CareTaskKind.routine,
        priority: routine.priority,
        routineID: routine.id,
        status: CareTaskStatus.completed,
        assigneeID: partner.id,
        assigneeNameSnapshot: partner.displayName,
        claimedAt: due,
        createdByID: caregiver.id,
        createdBy: caregiver.displayName,
        createdAt: routine.startDate,
        completedByID: partner.id,
        completedBy: partner.displayName,
        completedAt: due.add(const Duration(minutes: 15)),
        revision: 1,
      ),
    ];
  }
}
