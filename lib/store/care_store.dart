import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/care_catalog.dart';
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
  Set<String> get mutatingTaskIDs => _mutatingTaskIDs;

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
        uri.scheme == 'copaw' &&
        uri.host == 'invite' &&
        uri.pathSegments.isNotEmpty) {
      return uri.pathSegments.last;
    }
    return value;
  }

  Future<void> handleInvitationLink(Uri uri) async {
    if (uri.scheme != 'copaw' || uri.host != 'invite') return;
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

  Future<bool> skipTaskOccurrence(CareTask task) {
    final household = _household;
    final caregiver = _currentCaregiver;
    if (household == null || caregiver == null) {
      return Future.value(false);
    }
    return _performTaskMutation(task.id, () => _service.skipTaskOccurrence(
          task,
          household.id,
          caregiver,
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
  }) async {
    final household = _household;
    final currentCaregiver = _currentCaregiver;
    if (household == null || currentCaregiver == null || _isSavingTask) {
      return false;
    }

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
            petID: petID,
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
            petID: petID,
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
