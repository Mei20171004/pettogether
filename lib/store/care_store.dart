import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/care_catalog.dart';
import '../models/health.dart';
import '../models/models.dart';
import '../services/care_service.dart';
import '../services/firebase_care_service.dart';
import '../services/notification_service.dart';
import '../services/storage_service.dart';
import '../utils/care_calendar.dart';
import '../utils/extensions.dart';
import '../utils/id.dart';

/// Shared application state and actions, ported from `CareStore.swift`.
/// Exposes a [ChangeNotifier] that Flutter widgets rebuild from.
class CareStore extends ChangeNotifier {
  CareStore(
    this._service, {
    NotificationService? notificationService,
    // ignore: prefer_initializing_formals
  }) : _notificationService = notificationService {
    loadCustomCategories();
  }

  final CareService _service;
  final NotificationService? _notificationService;

  Household? _household;
  Caregiver? _currentCaregiver;
  List<CareTask> _tasks = [];
  List<Caregiver> _caregivers = [];
  List<CareRoutine> _routines = [];
  List<MedicationPlan> _medicationPlans = [];
  List<HealthRecord> _healthRecords = [];

  HouseholdInvitation? _invitationPreview;
  HouseholdInvitation? _activeInvitation;
  HouseholdJoinRequest? _pendingJoinRequest;
  List<HouseholdJoinRequest> _joinRequests = [];
  StreamSubscription<HouseholdJoinRequest?>? _pendingJoinSubscription;
  StreamSubscription<List<HouseholdJoinRequest>>? _joinRequestsSubscription;

  bool _notificationsEnabled = false;
  bool _completingApprovedJoin = false;
  NotificationPermissionState _notificationPermission =
      NotificationPermissionState.unavailable;

  String? _errorMessage;
  bool _isLoading = false;
  bool _isRestoringSession = true;
  bool _isSavingTask = false;
  bool _isSavingProfile = false;
  Set<String> _mutatingTaskIDs = {};
  bool _isSavingHealth = false;
  List<CareCategory> _customCategories = [];

  int _sessionRequestGeneration = 0;
  bool _didAttemptSessionRestore = false;

  // -------------------------------------------------------------------------
  // Getters
  // -------------------------------------------------------------------------

  Household? get household => _household;
  List<CareCategory> get customCategories => _customCategories;
  Caregiver? get currentCaregiver => _currentCaregiver;
  List<CareTask> get tasks => _tasks;
  List<Caregiver> get caregivers => _caregivers;
  List<CareRoutine> get routines => _routines;
  String? get errorMessage => _errorMessage;
  bool get isLoading => _isLoading;
  bool get isRestoringSession => _isRestoringSession;
  bool get isSavingTask => _isSavingTask;
  bool get isSavingProfile => _isSavingProfile;
  bool get isSavingHealth => _isSavingHealth;
  Set<String> get mutatingTaskIDs => _mutatingTaskIDs;
  List<MedicationPlan> get medicationPlans => _medicationPlans;
  List<HealthRecord> get healthRecords => _healthRecords;

  HouseholdInvitation? get invitationPreview => _invitationPreview;
  HouseholdInvitation? get activeInvitation => _activeInvitation;
  HouseholdJoinRequest? get pendingJoinRequest => _pendingJoinRequest;
  List<HouseholdJoinRequest> get joinRequests => _joinRequests;
  bool get notificationsEnabled => _notificationsEnabled;
  NotificationPermissionState get notificationPermission =>
      _notificationPermission;

  /// True when the store runs against a real Firebase service rather than the
  /// offline mock (QR scanning etc. is gated on this).
  bool get isCloudBacked => _service is FirebaseCareService;

  /// Whether the current caregiver is the household owner. Legacy documents
  /// without an [Household.ownerID] fall back to the sole-member case.
  bool get isOwner {
    final household = _household;
    final caregiver = _currentCaregiver;
    if (household == null || caregiver == null) return false;
    final ownerID = household.ownerID;
    if (ownerID != null) return ownerID == caregiver.id;
    return _caregivers.length == 1 && _caregivers.first.id == caregiver.id;
  }

  bool get hasHousehold => _household != null;

  Caregiver? get partnerCaregiver {
    final current = _currentCaregiver;
    if (current == null) return null;
    return _caregivers.where((c) => c.id != current.id).firstOrNull;
  }

  List<CareTask> get todayTasks => tasksOn(DateTime.now());
  List<CareTask> get unclaimedTasks => unclaimedTasksOn(DateTime.now());
  List<CareTask> get claimedTasks => claimedTasksOn(DateTime.now());
  List<CareTask> get completedTasks => completedTasksOn(DateTime.now());
  List<CareTask> get skippedTasks => tasksOn(DateTime.now())
      .where((t) => t.status == CareTaskStatus.skipped)
      .toList();

  set errorMessage(String? value) {
    _errorMessage = value;
    notifyListeners();
  }

  // -------------------------------------------------------------------------
  // Task expansion (mirrors CareStore.tasks(on:))
  // -------------------------------------------------------------------------

  List<CareTask> tasksOn(DateTime date) {
    final household = _household;
    if (household == null) return const [];

    final selectedDay = startOfDay(date);
    final nextDay = selectedDay.add(const Duration(days: 1));
    final persistedForDay = _tasks
        .where((t) => !t.dueTime.isBefore(selectedDay) && t.dueTime.isBefore(nextDay))
        .toList();
    final overridesByID = {for (final t in persistedForDay) t.id: t};

    final result = <CareTask>[];
    final includedIDs = <String>{};

    for (final routine in _routines.where((r) => r.isActive)) {
      if (!routineRunsOn(routine, selectedDay)) continue;

      final due = dueTimeForRoutine(routine, selectedDay);
      if (due == null || !due.isBefore(nextDay)) continue;

      final taskID = occurrenceID(routine, selectedDay);
      final occurrence = overridesByID[taskID] ??
          CareTask(
            id: taskID,
            title: routine.title,
            category: routine.category,
            dueTime: due,
            kind: CareTaskKind.routine,
            priority: routine.priority,
            routineID: routine.id,
            petID: routine.petID,
            // Carry petIds across too. Without it a multi-pet routine expands
            // into an occurrence with no pets at all, which every pet filter
            // then reads as "applies to all of them".
            petIds: routine.petIds,
            status: CareTaskStatus.unclaimed,
            createdByID: routine.createdByID,
            createdBy: routine.createdByNameSnapshot,
            createdAt: routine.startDate,
          );
      result.add(occurrence);
      includedIDs.add(taskID);
    }

    for (final task in persistedForDay) {
      if (!includedIDs.contains(task.id)) {
        result.add(task);
        includedIDs.add(task.id);
      }
    }

    result.sort((a, b) {
      final byTime = a.dueTime.compareTo(b.dueTime);
      if (byTime != 0) return byTime;
      return a.title.toLowerCase().compareTo(b.title.toLowerCase());
    });
    return result;
  }

  List<CareTask> unclaimedTasksOn(DateTime date) =>
      tasksOn(date).where((t) => t.status == CareTaskStatus.unclaimed).toList();

  List<CareTask> claimedTasksOn(DateTime date) =>
      tasksOn(date).where((t) => t.status == CareTaskStatus.claimed).toList();

  List<CareTask> completedTasksOn(DateTime date) {
    final completed = tasksOn(date)
        .where((t) => t.status == CareTaskStatus.completed)
        .toList();
    completed.sort((a, b) => (b.completedAt ?? b.dueTime)
        .compareTo(a.completedAt ?? a.dueTime));
    return completed;
  }

  // -------------------------------------------------------------------------
  // Medication, expressed as ordinary care tasks
  // -------------------------------------------------------------------------

  /// The dose times of one course. A course given twice a day is two routines
  /// sharing a plan id.
  List<CareRoutine> routinesForPlan(String planId) {
    final routines =
        _routines.where((r) => r.medicationPlanId == planId).toList();
    routines.sort((a, b) =>
        (a.hour * 60 + a.minute).compareTo(b.hour * 60 + b.minute));
    return routines;
  }

  /// Every medication dose scheduled on [date] — which is to say, the care
  /// tasks whose routine belongs to a medication course.
  ///
  /// These are the same objects Today and the calendar show, so a dose can be
  /// claimed, handed to someone else, completed or skipped exactly like a walk.
  List<CareTask> doseTasksOn(DateTime date, {String? petId, String? planId}) {
    final planByRoutine = <String, String>{
      for (final routine in _routines)
        if (routine.medicationPlanId != null)
          routine.id: routine.medicationPlanId!,
    };
    if (planByRoutine.isEmpty) return const [];

    return tasksOn(date).where((task) {
      final routineID = task.routineID;
      if (routineID == null) return false;
      final taskPlanId = planByRoutine[routineID];
      if (taskPlanId == null) return false;
      if (planId != null && taskPlanId != planId) return false;
      if (petId != null && !task.effectivePetIds.contains(petId)) return false;
      return true;
    }).toList();
  }

  List<CareTask> get todayDoseTasks => doseTasksOn(DateTime.now());

  /// The course a task belongs to, or null when it is an ordinary care task.
  MedicationPlan? planForTask(CareTask task) {
    final routineID = task.routineID;
    if (routineID == null) return null;
    final routine = _routines.where((r) => r.id == routineID).firstOrNull;
    final planId = routine?.medicationPlanId;
    if (planId == null) return null;
    return _medicationPlans.where((p) => p.id == planId).firstOrNull;
  }

  /// The routine behind a task, so a dose card can read its dose text.
  CareRoutine? routineForTask(CareTask task) {
    final routineID = task.routineID;
    if (routineID == null) return null;
    return _routines.where((r) => r.id == routineID).firstOrNull;
  }

  List<MedicationPlan> plansForPet(String petId, {bool? active}) {
    final plans = _medicationPlans.where((p) {
      if (p.petId != petId) return false;
      if (active == null) return true;
      return _isPlanRunning(p) == active;
    }).toList();
    plans.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return plans;
  }

  /// A course is running while the plan is active and at least one of its
  /// routines still has days left.
  bool _isPlanRunning(MedicationPlan plan) {
    if (!plan.isActive) return false;
    final today = startOfDay(DateTime.now());
    return routinesForPlan(plan.id).any((routine) {
      if (!routine.isActive) return false;
      final end = routine.endDate;
      return end == null || !today.isAfter(startOfDay(end));
    });
  }

  bool isPlanRunning(MedicationPlan plan) => _isPlanRunning(plan);

  /// The course window, derived from its routines. Null end = ongoing.
  ({DateTime start, DateTime? end})? courseWindow(String planId) {
    final routines = routinesForPlan(planId);
    if (routines.isEmpty) return null;
    var start = startOfDay(routines.first.startDate);
    DateTime? end = routines.first.endDate;
    var ongoing = end == null;
    for (final routine in routines.skip(1)) {
      final routineStart = startOfDay(routine.startDate);
      if (routineStart.isBefore(start)) start = routineStart;
      final routineEnd = routine.endDate;
      if (routineEnd == null) {
        ongoing = true;
      } else if (end != null && routineEnd.isAfter(end)) {
        end = routineEnd;
      }
    }
    return (start: start, end: ongoing ? null : end);
  }

  /// Which day of the course [date] is, 1-based, or null when out of range.
  int? courseDayNumber(String planId, DateTime date) {
    final window = courseWindow(planId);
    if (window == null) return null;
    final day = startOfDay(date);
    if (day.isBefore(window.start)) return null;
    final end = window.end;
    if (end != null && day.isAfter(startOfDay(end))) return null;
    return day.difference(window.start).inDays + 1;
  }

  /// Total days in the course, or null when it is open-ended.
  int? courseLengthDays(String planId) {
    final window = courseWindow(planId);
    final end = window?.end;
    if (window == null || end == null) return null;
    return startOfDay(end).difference(window.start).inDays + 1;
  }

  /// How much of a course actually happened over the last [days] days.
  ///
  /// The denominator is rebuilt from the routines rather than counted from
  /// stored documents, so a dose nobody ever touched still counts against the
  /// rate. Only elapsed doses count — this evening's dose is not a miss yet.
  MedicationAdherence adherence({
    String? petId,
    String? planId,
    int days = 7,
  }) {
    final now = DateTime.now();
    var given = 0;
    var skipped = 0;
    var missed = 0;

    for (var offset = days - 1; offset >= 0; offset -= 1) {
      final day = startOfDay(now).subtract(Duration(days: offset));
      for (final task in doseTasksOn(day, petId: petId, planId: planId)) {
        if (task.dueTime.isAfter(now)) continue;
        switch (task.status) {
          case CareTaskStatus.completed:
            // An unconfirmed completion is not evidence the dose happened.
            if (task.isServerConfirmed) {
              given += 1;
            } else {
              missed += 1;
            }
          case CareTaskStatus.skipped:
            skipped += 1;
          case CareTaskStatus.unclaimed:
          case CareTaskStatus.claimed:
            missed += 1;
        }
      }
    }
    return MedicationAdherence(given: given, skipped: skipped, missed: missed);
  }


  // -------------------------------------------------------------------------
  // Health records
  // -------------------------------------------------------------------------

  /// A pet's medical history, newest first.
  List<HealthRecord> recordsForPet(String petId, {HealthRecordType? type}) {
    final records = _healthRecords
        .where((r) => r.petId == petId && (type == null || r.type == type))
        .toList();
    records.sort((a, b) => b.occurredAt.compareTo(a.occurredAt));
    return records;
  }

  HealthRecord? recordByID(String recordID) =>
      _healthRecords.where((r) => r.id == recordID).firstOrNull;

  /// Vaccinations and dewormings coming due (or already overdue), soonest
  /// first. This is what turns a filed vaccination record into a reminder.
  List<HealthDueReminder> upcomingHealthDue({String? petId}) {
    final now = DateTime.now();
    final due = <HealthDueReminder>[];
    for (final record in _healthRecords) {
      if (!record.type.hasNextDue) continue;
      if (petId != null && record.petId != petId) continue;
      final days = record.daysUntilDue(now);
      if (days == null || days > HealthDueReminder.lookAheadDays) continue;
      due.add(HealthDueReminder(record: record, daysUntilDue: days));
    }
    due.sort((a, b) => a.daysUntilDue.compareTo(b.daysUntilDue));
    return due;
  }

  /// The pet's most recent vet visit, used by the health summary.
  HealthRecord? lastVetVisitForPet(String petId) => recordsForPet(petId)
      .where((r) => r.type == HealthRecordType.vetVisit)
      .firstOrNull;

  // -------------------------------------------------------------------------
  // Session
  // -------------------------------------------------------------------------

  Future<void> restoreSession() async {
    if (_didAttemptSessionRestore) return;
    _didAttemptSessionRestore = true;
    await _restoreSessionIfAvailable();
    // No household (yet): the user may have a pending join request waiting
    // for owner approval.
    if (_household == null && _pendingJoinRequest == null) {
      try {
        final request = await _service.restorePendingJoinRequest();
        if (request != null) _watchPendingRequest(request);
      } catch (error) {
        _setError(error);
      }
    }
  }

  Future<void> createHousehold({
    required String name,
    required List<Pet> pets,
    required String caregiverName,
  }) async {
    if (_isLoading) return;
    _sessionRequestGeneration++;
    final generation = _sessionRequestGeneration;
    _isLoading = true;
    notifyListeners();

    await _performSessionRequest(generation, () => _service.createHousehold(
          name: name,
          pets: pets,
          caregiverName: caregiverName,
        ));
  }

  // -------------------------------------------------------------------------
  // Invitations (one-time 24h link/QR + owner approval)
  // -------------------------------------------------------------------------

  /// Parses an invitation value (a deep link or a bare invitation id) and
  /// shows a preview of the destination household.
  Future<void> previewInvitation(String value) async {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return;
    await _runLoading(() async {
      _invitationPreview = await _service.loadInvitation(_invitationID(trimmed));
    });
  }

  static String _invitationID(String value) {
    final uri = Uri.tryParse(value);
    if (uri != null &&
        uri.scheme == 'pettogether' &&
        uri.host == 'invite' &&
        uri.pathSegments.isNotEmpty) {
      return uri.pathSegments.last;
    }
    return value;
  }

  Future<void> handleInvitationLink(Uri uri) async {
    if (uri.scheme != 'pettogether' || uri.host != 'invite') return;
    if (hasHousehold) {
      _setError(const CareServiceError(CareServiceErrorType.alreadyMember));
      return;
    }
    await previewInvitation(uri.toString());
  }

  void clearInvitationPreview() {
    _invitationPreview = null;
    _errorMessage = null;
    notifyListeners();
  }

  Future<void> requestToJoin({required String caregiverName}) async {
    final invitation = _invitationPreview;
    if (invitation == null) return;
    await _runLoading(() async {
      final request = await _service.requestToJoin(
        invitation: invitation,
        name: caregiverName,
      );
      _invitationPreview = null;
      _watchPendingRequest(request);
    });
  }

  Future<void> createInvitation() async {
    final household = _household;
    final caregiver = _currentCaregiver;
    if (household == null || caregiver == null) return;
    await _runLoading(() async {
      final previous = _activeInvitation;
      if (previous != null && previous.isActive) {
        await _service.revokeInvitation(previous.id);
        _activeInvitation = null;
      }
      _activeInvitation = await _service.createInvitation(
        householdID: household.id,
        inviterName: caregiver.displayName,
      );
    });
  }

  Future<void> revokeInvitation() async {
    final invitation = _activeInvitation;
    if (invitation == null) return;
    final succeeded = await _runLoading<bool>(() async {
      await _service.revokeInvitation(invitation.id);
      return true;
    });
    if (succeeded ?? false) {
      _activeInvitation = null;
      notifyListeners();
    }
  }

  Future<void> reviewJoinRequest(
    HouseholdJoinRequest request, {
    required bool approve,
  }) async {
    final household = _household;
    if (household == null) return;
    final succeeded = await _runLoading<bool>(() async {
      await _service.reviewJoinRequest(
        householdID: household.id,
        request: request,
        approve: approve,
      );
      return true;
    });
    if (succeeded ?? false) {
      _joinRequests =
          _joinRequests.where((item) => item.userId != request.userId).toList();
      notifyListeners();
    }
  }

  Future<void> removeMember(Caregiver caregiver) async {
    final household = _household;
    if (household == null || !isOwner) return;
    await _runLoading<bool>(() async {
      await _service.removeMember(household.id, caregiver.id);
      return true;
    });
  }

  // -------------------------------------------------------------------------
  // Notifications
  // -------------------------------------------------------------------------

  Future<bool> enableNotifications() async {
    final household = _household;
    final caregiver = _currentCaregiver;
    final notifications = _notificationService;
    if (household == null || caregiver == null || notifications == null) {
      return false;
    }
    final permission = await _runLoading(
      () => notifications.requestAndSync(
        householdId: household.id,
        caregiverId: caregiver.id,
      ),
    );
    if (permission == null) return false;
    _notificationPermission = permission;
    _notificationsEnabled = permission.isGranted;
    notifyListeners();
    return _notificationsEnabled;
  }

  Future<void> disableNotifications() async {
    final household = _household;
    final caregiver = _currentCaregiver;
    final notifications = _notificationService;
    if (household == null || caregiver == null || notifications == null) {
      return;
    }
    await _runLoading(
      () => notifications.disableForMember(
        householdId: household.id,
        caregiverId: caregiver.id,
      ),
    );
    _notificationsEnabled = false;
    _notificationPermission = NotificationPermissionState.unavailable;
    notifyListeners();
  }

  // -------------------------------------------------------------------------
  // Skip / restore a single routine occurrence
  // -------------------------------------------------------------------------

  /// Skips a single occurrence. Medication doses pass a [reason] — a missed
  /// dose is only useful to a vet with one attached.
  Future<bool> skipTaskOccurrence(
    CareTask task, {
    MedicationSkipReason? reason,
    String? note,
  }) {
    final household = _household;
    final caregiver = _currentCaregiver;
    if (household == null || caregiver == null) {
      return Future.value(false);
    }
    return _performTaskMutation(task.id, () => _service.skipTaskOccurrence(
          task,
          household.id,
          caregiver,
          reason: reason,
          note: note,
        ));
  }

  Future<bool> restoreTaskOccurrence(CareTask task) {
    final household = _household;
    final caregiver = _currentCaregiver;
    if (household == null || caregiver == null) {
      return Future.value(false);
    }
    return _performTaskMutation(task.id, () => _service.restoreTaskOccurrence(
          task,
          household.id,
          caregiver,
        ));
  }

  // -------------------------------------------------------------------------
  // Custom care modules
  // -------------------------------------------------------------------------

  static const _customCategoriesKey = 'pettogetter.customCategories';

  Future<void> loadCustomCategories() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_customCategoriesKey);
      if (raw == null) return;
      final list = jsonDecode(raw) as List;
      _customCategories = list
          .map((e) => CareCategory.fromRaw(
                (e as Map<String, dynamic>)['id'] as String,
                name: e['name'] as String?,
              ))
          .toList();
      notifyListeners();
    } catch (_) {
      _customCategories = [];
    }
  }

  Future<void> addCustomCategory(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    final category = CareCategory.custom(
      id: generateCustomCategoryId(),
      name: trimmed,
    );
    _customCategories = [..._customCategories, category];
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _customCategoriesKey,
      jsonEncode(_customCategories
          .map((c) => {'id': c.id, 'name': c.name})
          .toList()),
    );
  }

  // -------------------------------------------------------------------------
  // Adds
  // -------------------------------------------------------------------------

  Future<bool> addTask({
    required String title,
    required CareCategory category,
    required CareTaskKind kind,
    required CarePriority priority,
    required DateTime date,
    CareRoutineFrequency frequency = CareRoutineFrequency.daily,
    List<int> weekdays = const [1, 2, 3, 4, 5, 6, 7],
    int interval = 1,
    String? petID,
    List<String> petIds = const [],
  }) async {
    final household = _household;
    final currentCaregiver = _currentCaregiver;
    if (household == null || currentCaregiver == null || _isSavingTask) {
      return false;
    }

    // Multi-pet selection is stored in `petIds`; the legacy single `petID`
    // field is kept in sync for backward compatibility.
    final List<String> effectivePetIds = petIds.isNotEmpty
        ? petIds
        : (petID == null ? const <String>[] : [petID]);
    final effectivePetID = effectivePetIds.length == 1
        ? effectivePetIds.first
        : (petID != null && petIds.isEmpty ? petID : null);

    final generation = _sessionRequestGeneration;
    _isSavingTask = true;
    _errorMessage = null;
    notifyListeners();

    try {
      switch (kind) {
        case CareTaskKind.oneOff:
          final task = CareTask(
            id: uuid(),
            title: title,
            category: category,
            dueTime: date,
            kind: CareTaskKind.oneOff,
            priority: priority,
            petID: effectivePetID,
            petIds: effectivePetIds,
            status: CareTaskStatus.unclaimed,
            createdByID: currentCaregiver.id,
            createdBy: currentCaregiver.displayName,
            createdAt: DateTime.now(),
          );
          await _service.addTask(task, household.id);
        case CareTaskKind.routine:
          final routine = CareRoutine(
            id: uuid(),
            title: title,
            category: category,
            priority: priority,
            frequency: frequency,
            weekdays: weekdays,
            interval: interval,
            petID: effectivePetID,
            petIds: effectivePetIds,
            hour: date.hour,
            minute: date.minute,
            startDate: startOfDay(date),
            timeZoneIdentifier: household.timeZoneIdentifier,
            createdByID: currentCaregiver.id,
            createdByNameSnapshot: currentCaregiver.displayName,
          );
          await _service.addRoutine(routine, household.id);
      }
      return generation == _sessionRequestGeneration;
    } catch (error) {
      if (generation != _sessionRequestGeneration) return false;
      _errorMessage = _describe(error);
      return false;
    } finally {
      _isSavingTask = false;
      notifyListeners();
    }
  }

  Future<bool> addOneOffTask({
    required String title,
    required CareCategory category,
    required DateTime dueTime,
  }) {
    return addTask(
      title: title,
      category: category,
      kind: CareTaskKind.oneOff,
      priority: CarePriority.normal,
      date: dueTime,
    );
  }

  // -------------------------------------------------------------------------
  // Profile
  // -------------------------------------------------------------------------

  Future<bool> updateProfile({
    required String caregiverName,
    required String householdName,
    required String petName,
    required PetType petType,
  }) async {
    final existingHousehold = _household;
    final existingCaregiver = _currentCaregiver;
    if (existingHousehold == null || existingCaregiver == null || _isSavingProfile) {
      return false;
    }

    final caregiver = caregiverName.trim();
    final household = householdName.trim();
    final pet = petName.trim();
    if (caregiver.isEmpty ||
        caregiver.length > 50 ||
        household.isEmpty ||
        household.length > 60 ||
        pet.isEmpty ||
        pet.length > 60) {
      _errorMessage = const CareServiceError(
              CareServiceErrorType.invalidProfile)
          .message;
      notifyListeners();
      return false;
    }

    final updatedHousehold = existingHousehold.copyWith(
      name: household,
      pets: existingHousehold.pets.isEmpty
          ? [Pet(id: uuid(), name: pet, type: petType)]
          : [
              existingHousehold.pets.first.copyWith(name: pet, type: petType),
              ...existingHousehold.pets.skip(1),
            ],
    );
    final updatedCaregiver = existingCaregiver.copyWith(displayName: caregiver);

    final generation = _sessionRequestGeneration;
    _isSavingProfile = true;
    _errorMessage = null;
    notifyListeners();

    try {
      await _service.updateProfile(updatedHousehold, updatedCaregiver);
      if (generation != _sessionRequestGeneration) return false;
      _household = updatedHousehold;
      _currentCaregiver = updatedCaregiver;
      _caregivers = [
        for (final c in _caregivers)
          c.id == updatedCaregiver.id ? updatedCaregiver : c,
      ];
      return true;
    } catch (error) {
      if (generation != _sessionRequestGeneration) return false;
      _errorMessage = _describe(error);
      return false;
    } finally {
      _isSavingProfile = false;
      notifyListeners();
    }
  }

  Future<bool> addPet({
    required String name,
    required PetType type,
    int? ageYears,
    String? habits,
    double? weightKg,
  }) async {
    final household = _household;
    if (household == null) return false;
    final pet = Pet(
      id: uuid(),
      name: name.trim(),
      type: type,
      ageYears: ageYears,
      habits: habits?.trim(),
      weightKg: weightKg,
      weightHistory: weightKg == null
          ? const []
          : [PetWeightEntry(date: DateTime.now(), weightKg: weightKg)],
    );
    try {
      await _service.addPet(household.id, pet);
      return true;
    } catch (error) {
      _errorMessage = _describe(error);
      notifyListeners();
      return false;
    }
  }

  Future<bool> updatePet(Pet pet) async {
    final household = _household;
    if (household == null) return false;
    try {
      var updated = pet;
      final existing =
          household.pets.where((p) => p.id == pet.id).firstOrNull;
      if (existing != null &&
          pet.weightKg != null &&
          pet.weightKg != existing.weightKg) {
        updated = pet.copyWith(
          weightHistory: [
            ...pet.weightHistory,
            PetWeightEntry(date: DateTime.now(), weightKg: pet.weightKg!),
          ],
        );
      }
      await _service.updatePet(household.id, updated);
      return true;
    } catch (error) {
      _errorMessage = _describe(error);
      notifyListeners();
      return false;
    }
  }

  Future<bool> removePet(String petID) async {
    final household = _household;
    if (household == null) return false;
    try {
      await _service.removePet(household.id, petID);
      return true;
    } catch (error) {
      _errorMessage = _describe(error);
      notifyListeners();
      return false;
    }
  }

  Future<void> savePetPhoto(Pet pet, Uint8List bytes) async {
    final household = _household;
    if (household == null) return;
    try {
      final url = await StorageService.instance.uploadPetPhoto(
        householdID: household.id,
        petID: pet.id,
        bytes: bytes,
      );
      await updatePet(pet.copyWith(photoURL: url));
    } catch (error) {
      _errorMessage = _describe(error);
      notifyListeners();
    }
  }

  // -------------------------------------------------------------------------
  // Medication actions
  // -------------------------------------------------------------------------

  /// Creates or replaces a medication course: the drug details, one routine per
  /// dose time, and the medical-history entry that records the course.
  ///
  /// Replacing rewrites the routines rather than patching them, so what is
  /// scheduled always matches what the editor showed. Doses already completed
  /// or skipped live in their own task documents and are left alone.
  Future<MedicationPlan?> saveMedicationCourse({
    required MedicationPlan plan,
    required List<MedicationDoseTime> times,
    required List<int> weekdays,
    required DateTime startDate,
    DateTime? endDate,
  }) async {
    final household = _household;
    final caregiver = _currentCaregiver;
    if (household == null || caregiver == null) return null;

    if (!plan.isValid ||
        times.isEmpty ||
        times.length > MedicationPlan.maxDoseTimes ||
        !times.every((t) => t.isValid) ||
        weekdays.isEmpty ||
        (endDate != null &&
            startOfDay(endDate).isBefore(startOfDay(startDate)))) {
      _errorMessage =
          const CareServiceError(CareServiceErrorType.invalidMedicationPlan)
              .message;
      notifyListeners();
      return null;
    }

    _isSavingHealth = true;
    _errorMessage = null;
    notifyListeners();
    try {
      await _service.saveMedicationPlan(plan, household.id);

      for (final existing in routinesForPlan(plan.id)) {
        await _service.deleteRoutine(existing.id, household.id);
      }
      final sorted = [...times]
        ..sort((a, b) => a.minutesOfDay.compareTo(b.minutesOfDay));
      for (final time in sorted) {
        final instructions = time.instructions?.trim();
        await _service.addRoutine(
          CareRoutine(
            id: uuid(),
            title: plan.name,
            category: CareCategory.medication,
            frequency: weekdays.length >= 7
                ? CareRoutineFrequency.daily
                : CareRoutineFrequency.selectedDays,
            weekdays: weekdays,
            petID: plan.petId,
            petIds: [plan.petId],
            hour: time.hour,
            minute: time.minute,
            startDate: startOfDay(startDate),
            endDate: endDate == null ? null : startOfDay(endDate),
            timeZoneIdentifier: household.timeZoneIdentifier,
            createdByID: caregiver.id,
            createdByNameSnapshot: caregiver.displayName,
            medicationPlanId: plan.id,
            doseText: time.doseText.trim(),
            doseInstructions:
                instructions == null || instructions.isEmpty ? null : instructions,
          ),
          household.id,
        );
      }

      await _writeCourseHealthRecord(
        plan: plan,
        times: sorted,
        startDate: startDate,
        endDate: endDate,
        caregiver: caregiver,
        householdID: household.id,
      );
      return plan;
    } catch (error) {
      _errorMessage = _describe(error);
      return null;
    } finally {
      _isSavingHealth = false;
      notifyListeners();
    }
  }

  /// Ends a course today. Nothing is deleted, so the history and the adherence
  /// figures stay readable.
  Future<bool> stopMedicationCourse(MedicationPlan plan) async {
    final household = _household;
    if (household == null) return false;
    final today = startOfDay(DateTime.now());
    try {
      for (final routine in routinesForPlan(plan.id)) {
        await _service.updateRoutine(
          routine.copyWith(endDate: today, isActive: false),
          household.id,
        );
      }
      await _service.saveMedicationPlan(
        plan.copyWith(isActive: false, revision: plan.revision + 1),
        household.id,
      );
      final record = courseHealthRecord(plan.id);
      if (record != null) {
        await _service.saveHealthRecord(
          record.copyWith(notes: _courseNotes(plan, endedOn: today)),
          household.id,
        );
      }
      return true;
    } catch (error) {
      _errorMessage = _describe(error);
      notifyListeners();
      return false;
    }
  }

  /// Removes the course, its dose times and its medical-history entry. Doses
  /// already recorded stay — they describe what actually happened.
  Future<bool> deleteMedicationCourse(MedicationPlan plan) async {
    final household = _household;
    if (household == null) return false;
    try {
      for (final routine in routinesForPlan(plan.id)) {
        await _service.deleteRoutine(routine.id, household.id);
      }
      final record = courseHealthRecord(plan.id);
      if (record != null) {
        await _service.deleteHealthRecord(record.id, household.id);
      }
      await _service.deleteMedicationPlan(plan.id, household.id);
      return true;
    } catch (error) {
      _errorMessage = _describe(error);
      notifyListeners();
      return false;
    }
  }

  /// The auto-generated medical-history entry for a course, if it exists.
  HealthRecord? courseHealthRecord(String planId) =>
      _healthRecords.where((r) => r.medicationPlanId == planId).firstOrNull;

  /// How many doses of [plan] are still ahead of now, so "stop this course"
  /// can say what it is about to cancel.
  int remainingDoseCount(MedicationPlan plan) {
    final now = DateTime.now();
    final routines = routinesForPlan(plan.id);
    if (routines.isEmpty) return 0;
    // An open-ended course has no finite tail; count the next 30 days so the
    // confirmation still says something concrete.
    final window = courseWindow(plan.id);
    final last = window?.end ?? startOfDay(now).add(const Duration(days: 30));

    var count = 0;
    for (var day = startOfDay(now);
        !day.isAfter(startOfDay(last));
        day = day.add(const Duration(days: 1))) {
      for (final routine in routines) {
        if (!routine.isActive) continue;
        final due = dueTimeForRoutine(routine, day);
        if (due != null && due.isAfter(now)) count += 1;
      }
    }
    return count;
  }

  /// How many doses of [plan] anyone has already completed or skipped.
  int recordedDoseCount(MedicationPlan plan) {
    final routineIds = routinesForPlan(plan.id).map((r) => r.id).toSet();
    if (routineIds.isEmpty) return 0;
    return _tasks
        .where((t) =>
            t.routineID != null &&
            routineIds.contains(t.routineID) &&
            (t.status == CareTaskStatus.completed ||
                t.status == CareTaskStatus.skipped))
        .length;
  }

  /// Writes (or refreshes) the "started this medicine" entry in the pet's
  /// medical history, so a course sits alongside vet visits and reaches the vet
  /// visit pack without any extra wiring.
  Future<void> _writeCourseHealthRecord({
    required MedicationPlan plan,
    required List<MedicationDoseTime> times,
    required DateTime startDate,
    DateTime? endDate,
    required Caregiver caregiver,
    required String householdID,
  }) async {
    final pet = _household?.pets.where((p) => p.id == plan.petId).firstOrNull;
    if (pet == null) return;
    final existing = courseHealthRecord(plan.id);
    final schedule = times.map((t) => '${t.label} ${t.doseText}').join(', ');

    await _service.saveHealthRecord(
      HealthRecord(
        id: existing?.id ?? uuid(),
        petId: plan.petId,
        petNameSnapshot: pet.name,
        type: HealthRecordType.medication,
        occurredAt: startDate,
        title: plan.name,
        treatment: schedule,
        notes: _courseNotes(plan, endDate: endDate),
        medicationPlanId: plan.id,
        createdByID: existing?.createdByID ?? caregiver.id,
        createdByNameSnapshot:
            existing?.createdByNameSnapshot ?? caregiver.displayName,
        createdAt: existing?.createdAt ?? DateTime.now(),
        updatedAt: existing == null ? null : DateTime.now(),
        updatedByID: existing == null ? null : caregiver.id,
        updatedByNameSnapshot: existing == null ? null : caregiver.displayName,
        revision: existing?.revision ?? 0,
      ),
      householdID,
    );
  }

  String? _courseNotes(
    MedicationPlan plan, {
    DateTime? endedOn,
    DateTime? endDate,
  }) {
    String stamp(DateTime d) =>
        '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    final parts = <String>[
      if (plan.purpose != null && plan.purpose!.isNotEmpty) plan.purpose!,
      if (plan.sideEffects != null && plan.sideEffects!.isNotEmpty)
        plan.sideEffects!,
      if (endedOn != null)
        'Stopped ${stamp(endedOn)}'
      else if (endDate != null)
        'Until ${stamp(endDate)}',
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }

  // -------------------------------------------------------------------------
  // Health record actions
  // -------------------------------------------------------------------------

  /// Creates or updates a medical record.
  ///
  /// A weight record also lands in the pet's weight history, so the existing
  /// trend chart picks it up without a second source of truth.
  Future<bool> saveHealthRecord(HealthRecord record) async {
    final household = _household;
    if (household == null) return false;
    if (!record.isValid) {
      _errorMessage =
          const CareServiceError(CareServiceErrorType.invalidHealthRecord)
              .message;
      notifyListeners();
      return false;
    }
    _isSavingHealth = true;
    _errorMessage = null;
    notifyListeners();
    try {
      await _service.saveHealthRecord(record, household.id);
      final weight = record.weightKg;
      if (record.type == HealthRecordType.weight && weight != null) {
        await _syncPetWeight(record.petId, weight, record.occurredAt);
      }
      return true;
    } catch (error) {
      _errorMessage = _describe(error);
      return false;
    } finally {
      _isSavingHealth = false;
      notifyListeners();
    }
  }

  Future<bool> deleteHealthRecord(HealthRecord record) async {
    final household = _household;
    if (household == null) return false;
    try {
      await _service.deleteHealthRecord(record.id, household.id);
      for (final attachment in record.attachments) {
        unawaited(
          StorageService.instance.deleteHealthAttachment(attachment.storagePath),
        );
      }
      return true;
    } catch (error) {
      _errorMessage = _describe(error);
      notifyListeners();
      return false;
    }
  }

  /// Uploads one photo for [recordID] and returns the attachment to store on
  /// the record. Returns null and surfaces the error on failure.
  Future<HealthAttachment?> uploadHealthAttachment({
    required String recordID,
    required Uint8List bytes,
  }) async {
    final household = _household;
    if (household == null) return null;
    try {
      return await StorageService.instance.uploadHealthAttachment(
        householdID: household.id,
        recordID: recordID,
        bytes: bytes,
      );
    } catch (error) {
      _errorMessage = _describe(error);
      notifyListeners();
      return null;
    }
  }

  Future<void> _syncPetWeight(
    String petId,
    double weightKg,
    DateTime measuredAt,
  ) async {
    final pet = _household?.pets.where((p) => p.id == petId).firstOrNull;
    if (pet == null) return;
    final history = [
      ...pet.weightHistory.where((e) => !_sameDay(e.date, measuredAt)),
      PetWeightEntry(date: measuredAt, weightKg: weightKg),
    ]..sort((a, b) => a.date.compareTo(b.date));
    // The headline weight only moves when this is the newest measurement, so
    // backfilling an old reading does not rewrite "current weight".
    final isLatest = history.last.date == measuredAt;
    await _service.updatePet(
      _household!.id,
      pet.copyWith(
        weightHistory: history,
        weightKg: isLatest ? weightKg : pet.weightKg,
      ),
    );
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  // -------------------------------------------------------------------------
  // Task actions
  // -------------------------------------------------------------------------

  Future<bool> claim(CareTask task) async {
    final household = _household;
    final currentCaregiver = _currentCaregiver;
    if (household == null || currentCaregiver == null) return false;
    return _performTaskMutation(task.id, () => _service.claimTask(
          task,
          household.id,
          currentCaregiver,
        ));
  }

  Future<bool> request(CareTask task, Caregiver requestedCaregiver) async {
    final household = _household;
    final currentCaregiver = _currentCaregiver;
    if (household == null || currentCaregiver == null) return false;
    return _performTaskMutation(task.id, () => _service.requestAssignment(
          task,
          household.id,
          currentCaregiver,
          requestedCaregiver,
        ));
  }

  Future<bool> requestPartner(CareTask task) async {
    final partner = partnerCaregiver;
    if (partner == null) {
      _errorMessage = const CareServiceError(
              CareServiceErrorType.caregiverNotFound)
          .message;
      notifyListeners();
      return false;
    }
    return request(task, partner);
  }

  Future<bool> requestAnyone(CareTask task) async {
    final household = _household;
    final currentCaregiver = _currentCaregiver;
    if (household == null || currentCaregiver == null) return false;
    return _performTaskMutation(task.id, () => _service.requestOpenAssignment(
          task,
          household.id,
          currentCaregiver,
        ));
  }

  Future<bool> acceptRequest(CareTask task) async {
    final household = _household;
    final currentCaregiver = _currentCaregiver;
    final request = task.assignmentRequest;
    if (household == null || currentCaregiver == null || request == null) {
      return false;
    }
    return _performTaskMutation(task.id, () => _service.acceptAssignmentRequest(
          task.id,
          request.id,
          household.id,
          currentCaregiver,
        ));
  }

  Future<bool> declineRequest(CareTask task) async {
    final household = _household;
    final currentCaregiver = _currentCaregiver;
    final request = task.assignmentRequest;
    if (household == null || currentCaregiver == null || request == null) {
      return false;
    }
    return _performTaskMutation(task.id, () => _service.declineAssignmentRequest(
          task.id,
          request.id,
          household.id,
          currentCaregiver,
        ));
  }

  Future<bool> cancelRequest(CareTask task) async {
    final household = _household;
    final currentCaregiver = _currentCaregiver;
    final request = task.assignmentRequest;
    if (household == null || currentCaregiver == null || request == null) {
      return false;
    }
    return _performTaskMutation(task.id, () => _service.cancelAssignmentRequest(
          task.id,
          request.id,
          household.id,
          currentCaregiver,
        ));
  }

  Future<bool> complete(CareTask task) async {
    final household = _household;
    final currentCaregiver = _currentCaregiver;
    if (household == null || currentCaregiver == null) return false;
    return _performTaskMutation(task.id, () => _service.completeTask(
          task.id,
          household.id,
          currentCaregiver,
        ));
  }

  void leaveHousehold() {
    _sessionRequestGeneration++;
    _cancelSubscriptions();
    _service.leaveHousehold();
    _household = null;
    _currentCaregiver = null;
    _tasks = [];
    _caregivers = [];
    _routines = [];
    _mutatingTaskIDs = {};
    _invitationPreview = null;
    _activeInvitation = null;
    _pendingJoinRequest = null;
    _joinRequests = [];
    _isLoading = false;
    _isSavingTask = false;
    _isSavingProfile = false;
    _errorMessage = null;
    notifyListeners();
  }

  // -------------------------------------------------------------------------
  // Internals
  // -------------------------------------------------------------------------

  /// Runs [operation] under the shared loading flag, returning the operation's
  /// result (or null on error / when a newer session request superseded it).
  Future<T?> _runLoading<T>(Future<T> Function() operation) async {
    if (_isLoading) return null;
    final generation = _sessionRequestGeneration;
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final result = await operation();
      return generation == _sessionRequestGeneration ? result : null;
    } catch (error) {
      if (generation != _sessionRequestGeneration) return null;
      _setError(error);
      return null;
    } finally {
      if (generation == _sessionRequestGeneration) {
        _isLoading = false;
      }
      notifyListeners();
    }
  }

  Future<bool> _performTaskMutation(
    String taskID,
    Future<void> Function() mutation,
  ) async {
    if (_mutatingTaskIDs.contains(taskID)) return false;
    final generation = _sessionRequestGeneration;
    _mutatingTaskIDs = {..._mutatingTaskIDs, taskID};
    _errorMessage = null;
    notifyListeners();

    try {
      await mutation();
      return generation == _sessionRequestGeneration;
    } catch (error) {
      if (generation != _sessionRequestGeneration) return false;
      _errorMessage = _describe(error);
      return false;
    } finally {
      _mutatingTaskIDs = {..._mutatingTaskIDs}..remove(taskID);
      notifyListeners();
    }
  }

  Future<void> _performSessionRequest(
    int generation,
    Future<CareSession> Function() request,
  ) async {
    _errorMessage = null;
    try {
      final session = await request();
      if (generation != _sessionRequestGeneration) return;
      _household = session.household;
      _currentCaregiver = session.caregiver;
      _observeDomain(session);
    } catch (error) {
      if (generation != _sessionRequestGeneration) return;
      _errorMessage = _describe(error);
    } finally {
      if (generation == _sessionRequestGeneration) {
        _isLoading = false;
      }
      notifyListeners();
    }
  }

  Future<void> _restoreSessionIfAvailable() async {
    final generation = _sessionRequestGeneration;
    try {
      final session = await _service.restoreSession();
      if (generation != _sessionRequestGeneration) return;
      if (session == null) return;
      _household = session.household;
      _currentCaregiver = session.caregiver;
      _observeDomain(session);
    } catch (error) {
      if (generation != _sessionRequestGeneration) return;
      _errorMessage = _describe(error);
    } finally {
      _isRestoringSession = false;
      notifyListeners();
    }
  }

  void _observeDomain(CareSession session) {
    _service.stopObserving();
    _service.observeHousehold(
      householdID: session.household.id,
      onChange: (household) {
        _household = household;
        notifyListeners();
      },
      onError: (error) => _setError(error),
    );
    _service.observeTasks(
      householdID: session.household.id,
      onChange: (tasks) {
        _tasks = tasks;
        notifyListeners();
      },
      onError: (error) => _setError(error),
    );
    _service.observeCaregivers(
      householdID: session.household.id,
      onChange: (caregivers) {
        _caregivers = caregivers;
        final currentID = _currentCaregiver?.id;
        if (currentID != null) {
          final updated = caregivers.where((c) => c.id == currentID).firstOrNull;
          if (updated != null) _currentCaregiver = updated;
        }
        notifyListeners();
      },
      onError: (error) => _setError(error),
    );
    _service.observeRoutines(
      householdID: session.household.id,
      onChange: (routines) {
        _routines = routines;
        notifyListeners();
      },
      onError: (error) => _setError(error),
    );
    _service.observeMedicationPlans(
      householdID: session.household.id,
      onChange: (plans) {
        _medicationPlans = plans;
        notifyListeners();
      },
      onError: (error) => _setError(error),
    );
    _service.observeHealthRecords(
      householdID: session.household.id,
      onChange: (records) {
        _healthRecords = records;
        notifyListeners();
      },
      onError: (error) => _setError(error),
    );

    _joinRequestsSubscription?.cancel();
    _joinRequestsSubscription = _service
        .joinRequestsStream(session.household.id)
        .listen((next) {
          _joinRequests = next;
          final invitation = _activeInvitation;
          if (invitation != null &&
              next.any((request) => request.invitationId == invitation.id)) {
            _activeInvitation = null;
          }
          notifyListeners();
        }, onError: (error) => _setError(error));

    unawaited(_loadActiveInvitation(session.household.id));
    unawaited(_syncNotificationsForSession());
  }

  Future<void> _loadActiveInvitation(String householdID) async {
    try {
      final invitation = await _service.getActiveInvitation(householdID);
      if (_household?.id != householdID) return;
      _activeInvitation = invitation;
      notifyListeners();
    } catch (error) {
      _setError(error);
    }
  }

  void _watchPendingRequest(HouseholdJoinRequest request) {
    _pendingJoinSubscription?.cancel();
    _pendingJoinRequest = request;
    _invitationPreview = null;
    _pendingJoinSubscription = _service.joinRequestStream(request).listen((
      next,
    ) {
      _pendingJoinRequest = next;
      notifyListeners();
      if (next?.status == JoinRequestStatus.approved) {
        unawaited(_completeApprovedJoin());
      }
    }, onError: (error) => _setError(error));
    notifyListeners();
  }

  Future<void> _completeApprovedJoin() async {
    if (_completingApprovedJoin) return;
    _completingApprovedJoin = true;
    try {
      final session = await _service.restoreSession();
      if (session != null && _household == null) {
        _household = session.household;
        _currentCaregiver = session.caregiver;
        _observeDomain(session);
      }
    } catch (error) {
      _setError(error);
    } finally {
      _completingApprovedJoin = false;
    }
  }

  Future<void> _syncNotificationsForSession() async {
    final notifications = _notificationService;
    final household = _household;
    final caregiver = _currentCaregiver;
    if (notifications == null || household == null || caregiver == null) {
      _notificationPermission = NotificationPermissionState.unavailable;
      _notificationsEnabled = false;
      notifyListeners();
      return;
    }
    try {
      _notificationPermission = await notifications.currentPermission();
      _notificationsEnabled =
          _notificationPermission.isGranted &&
          await notifications.prepareMember(
            householdId: household.id,
            caregiverId: caregiver.id,
          );
      notifyListeners();
    } catch (error) {
      _setError(error);
    }
  }

  void _cancelSubscriptions() {
    _pendingJoinSubscription?.cancel();
    _pendingJoinSubscription = null;
    _joinRequestsSubscription?.cancel();
    _joinRequestsSubscription = null;
    _service.stopObserving();
  }

  void _setError(Object error) {
    _errorMessage = _describe(error);
    notifyListeners();
  }

  String _describe(Object error) {
    if (error is CareServiceError) return error.message;
    return error.toString();
  }

  @override
  void dispose() {
    _cancelSubscriptions();
    super.dispose();
  }
}
