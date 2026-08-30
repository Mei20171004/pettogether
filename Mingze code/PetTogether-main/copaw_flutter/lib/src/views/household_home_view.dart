import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timezone/timezone.dart' as tz;

import '../app_controller.dart';
import '../data/household_repository.dart';
import '../data/household_sync_repository.dart';
import '../data/care_task_repository.dart';
import '../data/care_task_mutation_repository.dart';
import '../data/collaboration_event_repository.dart';
import '../data/pet_repository.dart';
import '../data/medication_repository.dart';
import '../data/notification_repository.dart';
import '../data/health_repository.dart';
import '../data/handoff_repository.dart';
import '../data/handoff_session_repository.dart';
import '../data/membership_exit_repository.dart';
import '../data/report_share_repository.dart';
import '../data/task_responsibility_repository.dart';
import '../domain/handoff_models.dart';
import '../domain/handoff_close_out_service.dart';
import '../domain/collaboration_event_models.dart';
import '../domain/health_models.dart';
import '../domain/legacy_firestore_codec.dart';
import '../domain/medication_models.dart';
import '../domain/medication_occurrence_service.dart';
import '../domain/models.dart';
import '../domain/routine_occurrence_service.dart';
import '../domain/report_models.dart';
import '../domain/report_service.dart';
import '../domain/responsibility_models.dart';
import '../localization/app_locale.dart';
import 'history_search_section.dart';
import 'care_coverage_section.dart';
import 'vet_visit_pack_section.dart';
import '../theme/copaw_theme.dart';
import 'notification_center_pane.dart';

class HouseholdHomeView extends ConsumerStatefulWidget {
  const HouseholdHomeView({required this.session, super.key});

  final HouseholdSession session;

  @override
  ConsumerState<HouseholdHomeView> createState() => _HouseholdHomeViewState();
}

class _HouseholdHomeViewState extends ConsumerState<HouseholdHomeView>
    with WidgetsBindingObserver {
  bool leaving = false;
  bool disconnecting = false;
  String? leaveMutationId;
  String? leaveError;
  StreamSubscription<HouseholdSyncSnapshot>? syncSubscription;
  Object? syncError;
  StreamSubscription<CareTaskSnapshot>? careSubscription;
  CareTaskSnapshot? careSnapshot;
  Object? careError;
  StreamSubscription<PetSnapshot>? petSubscription;
  PetSnapshot? petSnapshot;
  Object? petError;
  StreamSubscription<MedicationSnapshot>? medicationSubscription;
  MedicationSnapshot? medicationSnapshot;
  Object? medicationError;
  StreamSubscription<HealthSnapshot>? healthSubscription;
  HealthSnapshot? healthSnapshot;
  Object? healthError;
  StreamSubscription<HandoffSnapshot>? handoffSubscription;
  HandoffSnapshot? handoffSnapshot;
  Object? handoffError;
  StreamSubscription<HandoffSessionSnapshot>? handoffSessionSubscription;
  HandoffSessionSnapshot? handoffSessionSnapshot;
  Object? handoffSessionError;
  StreamSubscription<TaskResponsibilitySnapshot>?
  taskResponsibilitySubscription;
  TaskResponsibilitySnapshot? taskResponsibilitySnapshot;
  Object? taskResponsibilityError;
  StreamSubscription<CollaborationEventSnapshot>? collaborationSubscription;
  CollaborationEventSnapshot? collaborationSnapshot;
  Object? collaborationError;
  StreamSubscription<CollaborationReadCursorSnapshot>?
  collaborationReadSubscription;
  CollaborationReadCursorSnapshot? collaborationReadSnapshot;
  Object? collaborationReadError;
  bool collaborationMarkingRead = false;
  final List<CollaborationEvent> olderCollaborationEvents = [];
  CollaborationPageCursor? collaborationCursor;
  bool collaborationLoadingOlder = false;
  bool collaborationHasMore = false;
  bool collaborationLoadedOlderPage = false;
  int olderCollaborationDroppedEventCount = 0;
  bool olderCollaborationFromCache = false;
  bool olderCollaborationPotentiallyIncomplete = false;
  Object? collaborationPageError;
  bool medicationErrorFromAction = false;
  String? medicationActionId;
  String? todayPetFilterId;
  bool notificationReminderUnread = false;
  Timer? dayRefreshTimer;
  final pageScrollController = ScrollController();
  DateTime currentInstant = DateTime.now();
  String? scheduledTimeZone;
  late List<Caregiver> householdMembers;
  int selectedSection = 0;
  int selectedRecordSection = 0;
  DateTime selectedCalendarDate = DateTime.now();
  late final PetRepository petRepository;
  late final MedicationRepository medicationRepository;
  late final NotificationRepository notificationRepository;
  late final HealthRepository healthRepository;
  late final HandoffRepository handoffRepository;
  late final HandoffSessionRepository handoffSessionRepository;
  late final TaskResponsibilityRepository taskResponsibilityRepository;
  late final CollaborationEventRepository collaborationEventRepository;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    petRepository = ref.read(petRepositoryProvider);
    medicationRepository = ref.read(medicationRepositoryProvider);
    notificationRepository = ref.read(notificationRepositoryProvider);
    healthRepository = ref.read(healthRepositoryProvider);
    handoffRepository = ref.read(handoffRepositoryProvider);
    handoffSessionRepository = ref.read(handoffSessionRepositoryProvider);
    taskResponsibilityRepository = ref.read(
      taskResponsibilityRepositoryProvider,
    );
    collaborationEventRepository = ref.read(
      collaborationEventRepositoryProvider,
    );
    householdMembers = [widget.session.caregiver];
    _startSyncObservation();
    _startCareObservation();
    _startPetObservation();
    _startMedicationObservation();
    _startHealthObservation();
    _startHandoffObservation();
    _startHandoffSessionObservation();
    _startTaskResponsibilityObservation();
    _startCollaborationObservation();
    _startCollaborationReadObservation();
  }

  void _startSyncObservation() {
    unawaited(syncSubscription?.cancel());
    if (mounted) setState(() => syncError = null);
    syncSubscription = ref
        .read(householdSyncRepositoryProvider)
        .observeSession(
          householdId: widget.session.household.id,
          userId: widget.session.caregiver.id,
        )
        .listen(
          (snapshot) {
            if (!mounted) return;
            setState(() {
              syncError = null;
              if (snapshot.members.isNotEmpty) {
                householdMembers = snapshot.members;
              }
            });
            ref
                .read(appControllerProvider.notifier)
                .applySyncedSession(snapshot);
          },
          onError: (Object error) {
            if (mounted) setState(() => syncError = error);
          },
        );
  }

  void _startCareObservation() {
    unawaited(careSubscription?.cancel());
    if (mounted) {
      setState(() {
        careSnapshot = null;
        careError = null;
      });
    }
    careSubscription = ref
        .read(careTaskRepositoryProvider)
        .observeCare(widget.session.household.id)
        .listen(
          (snapshot) {
            if (mounted) {
              setState(() {
                careSnapshot = snapshot;
                careError = null;
              });
            }
          },
          onError: (error) {
            if (mounted) setState(() => careError = error);
          },
        );
  }

  void _startPetObservation() {
    unawaited(petSubscription?.cancel());
    if (mounted) {
      setState(() {
        petSnapshot = null;
        petError = null;
      });
    }
    petSubscription = petRepository
        .observePets(widget.session.household.id)
        .listen(
          (snapshot) {
            if (!mounted) return;
            setState(() {
              petSnapshot = snapshot;
              petError = null;
              if (!snapshot.pets.any(
                (pet) => pet.id == todayPetFilterId && !pet.isArchived,
              )) {
                todayPetFilterId = null;
              }
            });
          },
          onError: (Object error) {
            if (mounted) setState(() => petError = error);
          },
        );
  }

  void _startMedicationObservation() {
    unawaited(medicationSubscription?.cancel());
    if (mounted) {
      setState(() {
        medicationSnapshot = null;
        medicationError = null;
        medicationErrorFromAction = false;
      });
    }
    medicationSubscription = medicationRepository
        .observeMedication(widget.session.household.id)
        .listen(
          (snapshot) {
            if (!mounted) return;
            setState(() {
              medicationSnapshot = snapshot;
              medicationError = null;
              medicationErrorFromAction = false;
            });
          },
          onError: (Object error) {
            if (mounted) {
              setState(() {
                medicationError = error;
                medicationErrorFromAction = false;
              });
            }
          },
        );
  }

  void _startHealthObservation() {
    unawaited(healthSubscription?.cancel());
    if (mounted) {
      setState(() {
        healthSnapshot = null;
        healthError = null;
      });
    }
    healthSubscription = healthRepository
        .observeHealth(widget.session.household.id)
        .listen(
          (snapshot) {
            if (mounted) {
              setState(() {
                healthSnapshot = snapshot;
                healthError = null;
              });
            }
          },
          onError: (Object error) {
            if (mounted) setState(() => healthError = error);
          },
        );
  }

  void _startHandoffObservation() {
    unawaited(handoffSubscription?.cancel());
    if (mounted) {
      setState(() {
        handoffSnapshot = null;
        handoffError = null;
      });
    }
    handoffSubscription = handoffRepository
        .observeHandoff(widget.session.household.id)
        .listen(
          (snapshot) {
            if (mounted) {
              setState(() {
                handoffSnapshot = snapshot;
                handoffError = null;
              });
            }
          },
          onError: (Object error) {
            if (mounted) setState(() => handoffError = error);
          },
        );
  }

  void _startHandoffSessionObservation() {
    unawaited(handoffSessionSubscription?.cancel());
    if (mounted) {
      setState(() {
        handoffSessionSnapshot = null;
        handoffSessionError = null;
      });
    }
    handoffSessionSubscription = handoffSessionRepository
        .observeActiveSession(widget.session.household.id)
        .listen(
          (snapshot) {
            if (mounted) {
              setState(() {
                handoffSessionSnapshot = snapshot;
                handoffSessionError = null;
              });
            }
          },
          onError: (Object error) {
            if (mounted) setState(() => handoffSessionError = error);
          },
        );
  }

  void _startTaskResponsibilityObservation() {
    unawaited(taskResponsibilitySubscription?.cancel());
    if (mounted) {
      setState(() {
        taskResponsibilitySnapshot = null;
        taskResponsibilityError = null;
      });
    }
    taskResponsibilitySubscription = taskResponsibilityRepository
        .observeTransfers(widget.session.household.id)
        .listen(
          (snapshot) {
            if (mounted) {
              setState(() {
                taskResponsibilitySnapshot = snapshot;
                taskResponsibilityError = null;
              });
            }
          },
          onError: (Object error) {
            if (mounted) setState(() => taskResponsibilityError = error);
          },
        );
  }

  void _startCollaborationObservation() {
    unawaited(collaborationSubscription?.cancel());
    if (mounted) {
      setState(() {
        collaborationSnapshot = null;
        collaborationError = null;
        olderCollaborationEvents.clear();
        collaborationCursor = null;
        collaborationHasMore = false;
        collaborationLoadedOlderPage = false;
        olderCollaborationDroppedEventCount = 0;
        olderCollaborationFromCache = false;
        olderCollaborationPotentiallyIncomplete = false;
        collaborationPageError = null;
      });
    }
    collaborationSubscription = collaborationEventRepository
        .observeRecent(widget.session.household.id, limit: 20)
        .listen(
          (snapshot) {
            if (!mounted) return;
            final previousEvents = collaborationSnapshot?.events ?? const [];
            setState(() {
              final nextIds = snapshot.events.map((event) => event.id).toSet();
              final retainedIds = olderCollaborationEvents
                  .map((event) => event.id)
                  .toSet();
              olderCollaborationEvents.addAll(
                previousEvents.where(
                  (event) =>
                      !nextIds.contains(event.id) && retainedIds.add(event.id),
                ),
              );
              collaborationSnapshot = snapshot;
              collaborationError = null;
              if (!collaborationLoadedOlderPage) {
                collaborationCursor = snapshot.nextCursor;
                collaborationHasMore =
                    snapshot.hasMore && snapshot.nextCursor != null;
              }
            });
            _maybeMarkCollaborationRead();
          },
          onError: (Object error) {
            if (mounted) setState(() => collaborationError = error);
          },
        );
  }

  void _startCollaborationReadObservation() {
    unawaited(collaborationReadSubscription?.cancel());
    if (mounted) {
      setState(() {
        collaborationReadSnapshot = null;
        collaborationReadError = null;
      });
    }
    collaborationReadSubscription = collaborationEventRepository
        .observeReadCursor(
          widget.session.household.id,
          widget.session.caregiver.id,
        )
        .listen(
          (snapshot) {
            if (!mounted) return;
            setState(() {
              collaborationReadSnapshot = snapshot;
              collaborationReadError = null;
            });
            _maybeMarkCollaborationRead();
          },
          onError: (Object error) {
            if (mounted) setState(() => collaborationReadError = error);
          },
        );
  }

  Future<void> _loadOlderCollaborationEvents() async {
    final cursor = collaborationCursor;
    if (cursor == null || collaborationLoadingOlder) return;
    setState(() {
      collaborationLoadingOlder = true;
      collaborationPageError = null;
    });
    try {
      final page = await collaborationEventRepository.loadPage(
        widget.session.household.id,
        limit: 20,
        after: cursor,
      );
      if (!mounted) return;
      setState(() {
        final knownIds = {
          ...?collaborationSnapshot?.events.map((event) => event.id),
          ...olderCollaborationEvents.map((event) => event.id),
        };
        olderCollaborationEvents.addAll(
          page.events.where((event) => knownIds.add(event.id)),
        );
        collaborationLoadedOlderPage = true;
        collaborationCursor = page.nextCursor;
        collaborationHasMore = page.hasMore && page.nextCursor != null;
        olderCollaborationDroppedEventCount += page.droppedEventCount;
        olderCollaborationFromCache =
            olderCollaborationFromCache || page.isFromCache;
        olderCollaborationPotentiallyIncomplete =
            olderCollaborationPotentiallyIncomplete ||
            page.isPotentiallyIncomplete;
      });
    } on Object catch (error) {
      if (mounted) setState(() => collaborationPageError = error);
    } finally {
      if (mounted) setState(() => collaborationLoadingOlder = false);
    }
  }

  CollaborationEvent? get _newestCollaborationEvent {
    CollaborationEvent? newest;
    for (final event in [
      ...?collaborationSnapshot?.events,
      ...olderCollaborationEvents,
    ]) {
      final current = newest;
      if (current == null ||
          _compareCollaborationCursors(
                _cursorForCollaborationEvent(event),
                _cursorForCollaborationEvent(current),
              ) >
              0) {
        newest = event;
      }
    }
    return newest;
  }

  bool get _hasUnreadCollaboration {
    final readSnapshot = collaborationReadSnapshot;
    final newest = _newestCollaborationEvent;
    if (newest == null) return false;
    if (readSnapshot == null || collaborationReadError != null) return true;
    if (readSnapshot.hasPendingWrites) return true;
    final current = readSnapshot.cursor;
    return current == null ||
        _compareCollaborationCursors(
              _cursorForCollaborationEvent(newest),
              current,
            ) >
            0;
  }

  void _maybeMarkCollaborationRead() {
    final readSnapshot = collaborationReadSnapshot;
    final newest = _newestCollaborationEvent;
    if (!mounted ||
        selectedSection != 2 ||
        collaborationMarkingRead ||
        collaborationReadError != null ||
        readSnapshot == null ||
        readSnapshot.hasPendingWrites ||
        newest == null) {
      return;
    }
    final cursor = _cursorForCollaborationEvent(newest);
    final current = readSnapshot.cursor;
    if (current != null && _compareCollaborationCursors(cursor, current) <= 0) {
      return;
    }
    setState(() => collaborationMarkingRead = true);
    unawaited(_markCollaborationRead(cursor));
  }

  Future<void> _markCollaborationRead(CollaborationReadCursor cursor) async {
    try {
      await collaborationEventRepository.markRead(
        widget.session.household.id,
        widget.session.caregiver.id,
        cursor,
      );
    } on Object catch (error) {
      if (mounted) setState(() => collaborationReadError = error);
    } finally {
      if (mounted) setState(() => collaborationMarkingRead = false);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      setState(() => currentInstant = DateTime.now());
      scheduledTimeZone = null;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    dayRefreshTimer?.cancel();
    unawaited(syncSubscription?.cancel());
    unawaited(careSubscription?.cancel());
    unawaited(petSubscription?.cancel());
    unawaited(petRepository.stopObserving());
    unawaited(medicationSubscription?.cancel());
    unawaited(medicationRepository.stopObserving());
    unawaited(notificationRepository.stop());
    unawaited(healthSubscription?.cancel());
    unawaited(healthRepository.stopObserving());
    unawaited(handoffSubscription?.cancel());
    unawaited(handoffRepository.stopObserving());
    unawaited(handoffSessionSubscription?.cancel());
    unawaited(handoffSessionRepository.stopObserving());
    unawaited(taskResponsibilitySubscription?.cancel());
    unawaited(taskResponsibilityRepository.stopObserving());
    unawaited(collaborationSubscription?.cancel());
    unawaited(collaborationReadSubscription?.cancel());
    unawaited(collaborationEventRepository.stopObserving());
    pageScrollController.dispose();
    super.dispose();
  }

  void _selectSection(int value) {
    setState(() => selectedSection = value);
    if (value == 2) _maybeMarkCollaborationRead();
    _scrollToTop();
  }

  void _selectRecordSection(int value) {
    setState(() => selectedRecordSection = value);
    _scrollToTop();
  }

  void _scrollToTop() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (pageScrollController.hasClients) pageScrollController.jumpTo(0);
    });
  }

  String _collaborationErrorMessage(AppStrings strings, Object error) {
    if (error is CollaborationEventRepositoryException) {
      return switch (error.code) {
        CollaborationEventRepositoryErrorCode.network =>
          strings.updatesNetworkFailure,
        CollaborationEventRepositoryErrorCode.permission =>
          strings.updatesPermissionFailure,
        CollaborationEventRepositoryErrorCode.invalidInput =>
          strings.updatesDataFailure,
        CollaborationEventRepositoryErrorCode.backendUnavailable =>
          strings.updatesBackendFailure,
      };
    }
    if (error is FormatException) return strings.updatesDataFailure;
    return strings.updatesBackendFailure;
  }

  @override
  Widget build(BuildContext context) {
    final locale =
        ref.watch(appControllerProvider).value?.locale ?? AppLocale.japanese;
    final strings = AppStrings(locale);
    final liveSession =
        ref.watch(appControllerProvider).value?.session ?? widget.session;
    final household = liveSession.household;
    final timeZone = household.timeZoneIdentifier;
    final occurrenceService = RoutineOccurrenceService();
    final medicationOccurrenceService = MedicationOccurrenceService();
    final pets = petSnapshot?.pets ?? const <Pet>[];
    final activePets = pets
        .where((pet) => !pet.isArchived)
        .toList(growable: false);
    final todayPetIds = todayPetFilterId == null
        ? activePets.map((pet) => pet.id).toSet()
        : {todayPetFilterId!};
    final todayFilteredPet = pets
        .where((pet) => pet.id == todayPetFilterId)
        .firstOrNull;
    final selectedPet = todayFilteredPet;
    final selectedRoutines =
        careSnapshot?.routines
            .where((routine) => todayPetIds.contains(routine.petId))
            .toList(growable: false) ??
        const <CareRoutine>[];
    final selectedTasks =
        careSnapshot?.tasks
            .where((task) => todayPetIds.contains(task.petId))
            .toList(growable: false) ??
        const <CareTask>[];
    final todayRoutines =
        careSnapshot?.routines
            .where((routine) => todayPetIds.contains(routine.petId))
            .toList(growable: false) ??
        const <CareRoutine>[];
    final todayPersistedTasks =
        careSnapshot?.tasks
            .where((task) => todayPetIds.contains(task.petId))
            .toList(growable: false) ??
        const <CareTask>[];
    final todayTasks = careSnapshot == null || timeZone == null
        ? <CareTask>[]
        : occurrenceService
              .tryTasksForDay(
                selectedInstant: currentInstant,
                householdTimeZoneIdentifier: timeZone,
                routines: todayRoutines,
                persistedTasks: todayPersistedTasks,
              )
              ?.toList();
    todayTasks?.sort((left, right) => left.dueTime.compareTo(right.dueTime));
    final timeZoneInvalid = timeZone != null && todayTasks == null;
    _scheduleDayRefresh(occurrenceService, timeZone);
    final unsafeDocumentIds = careSnapshot?.diagnostics
        .where(
          (item) =>
              item.code == DomainDiagnosticCode.legacyUnsafeToMutate ||
              item.code == DomainDiagnosticCode.partialAssignmentRequest ||
              item.code == DomainDiagnosticCode.malformedData,
        )
        .map((item) => item.documentId)
        .toSet();
    final hasUnsafeCare = unsafeDocumentIds?.isNotEmpty == true;
    List<PlannedMedicationOccurrence>? medicationForToday;
    if (medicationSnapshot == null) {
      medicationForToday = const <PlannedMedicationOccurrence>[];
    } else {
      final combined = <PlannedMedicationOccurrence>[];
      var malformed = false;
      for (final pet in activePets.where(
        (pet) => todayPetIds.contains(pet.id),
      )) {
        final planned = _medicationForDay(
          medicationOccurrenceService,
          pet.id,
          currentInstant,
        );
        if (planned == null) {
          malformed = true;
          break;
        }
        combined.addAll(planned);
      }
      if (!malformed) {
        combined.sort((left, right) => left.dueAt.compareTo(right.dueAt));
        medicationForToday = combined;
      }
    }
    final todayAgenda =
        <
          ({
            DateTime dueAt,
            CareTask? task,
            PlannedMedicationOccurrence? medication,
          })
        >[];
    if (todayTasks != null && medicationForToday != null) {
      todayAgenda.addAll(
        todayTasks.map(
          (task) => (dueAt: task.dueTime, task: task, medication: null),
        ),
      );
      if (medicationSnapshot?.isServerConfirmed == true) {
        todayAgenda.addAll(
          medicationForToday.map(
            (medication) =>
                (dueAt: medication.dueAt, task: null, medication: medication),
          ),
        );
      }
      todayAgenda.sort((left, right) => left.dueAt.compareTo(right.dueAt));
    }
    return Scaffold(
      bottomNavigationBar: NavigationBar(
        selectedIndex: selectedSection,
        onDestinationSelected: _selectSection,
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.today),
            label: strings.today,
          ),
          NavigationDestination(
            icon: const Icon(Icons.calendar_month),
            label: strings.calendar,
          ),
          NavigationDestination(
            icon: Badge(
              key: const Key('updates.unreadBadge'),
              isLabelVisible:
                  _hasUnreadCollaboration || notificationReminderUnread,
              smallSize: 8,
              child: const Icon(Icons.groups_outlined),
            ),
            label: strings.updates,
          ),
          NavigationDestination(
            icon: const Icon(Icons.folder_outlined),
            label: strings.records,
          ),
          NavigationDestination(
            icon: const Icon(Icons.person),
            label: strings.profile,
          ),
        ],
      ),
      body: CopawBackground(
        child: SafeArea(
          child: SingleChildScrollView(
            key: const Key('household.home'),
            controller: pageScrollController,
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 96),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (liveSession.localPersistence ==
                    LocalSessionPersistence.unavailable) ...[
                  _WarningBanner(
                    key: const Key('household.persistenceWarning'),
                    message: strings.sessionNotSaved,
                  ),
                  const SizedBox(height: 14),
                ],
                if (syncError != null) ...[
                  _RetryWarningBanner(
                    key: const Key('household.syncError'),
                    message: _syncLoadMessage(strings),
                    retryLabel: strings.retryHousehold,
                    onRetry: _startSyncObservation,
                  ),
                  const SizedBox(height: 14),
                ],
                if (liveSession.diagnostics.any(
                  (item) =>
                      item.code == DomainDiagnosticCode.legacyNeedsTimezone,
                )) ...[
                  _WarningBanner(
                    key: const Key('household.timezoneWarning'),
                    message: strings.timezoneNeedsRepair,
                  ),
                  const SizedBox(height: 14),
                ],
                if (petError != null) ...[
                  _RetryWarningBanner(
                    key: const Key('pets.error'),
                    message: _petLoadMessage(strings),
                    retryLabel: strings.retryPets,
                    onRetry: _startPetObservation,
                  ),
                  const SizedBox(height: 14),
                ],
                _HouseholdHero(
                  household: household,
                  caregiver: liveSession.caregiver,
                  pets: pets,
                  todayPetFilterId: todayPetFilterId,
                  loadingPets: petSnapshot == null && petError == null,
                  compact: selectedSection != 0,
                  strings: strings,
                  onTodayPetChanged: (value) =>
                      setState(() => todayPetFilterId = value),
                ),
                const SizedBox(height: 18),
                if (selectedSection == 0)
                  _TodayPetCard(
                    pets: activePets,
                    itemCount:
                        (todayTasks?.length ?? 0) +
                        (medicationForToday?.length ?? 0),
                    strings: strings,
                  ),
                const SizedBox(height: 18),
                if (selectedSection == 0) ...[
                  CopawCard(
                    key: const Key('today.agenda'),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          strings.todaysCare,
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 12),
                        if (activePets.isEmpty)
                          _WarningBanner(
                            key: const Key('pets.noActive'),
                            message: strings.noActivePetHelp,
                          )
                        else if (timeZoneInvalid)
                          _WarningBanner(message: strings.timezoneNeedsRepair)
                        else if (hasUnsafeCare &&
                            todayTasks!.isEmpty &&
                            medicationForToday?.isEmpty == true)
                          _WarningBanner(
                            key: const Key('care.repairRequired'),
                            message: strings.careDataNeedsRepair,
                          )
                        else if (careSnapshot != null &&
                            medicationSnapshot != null &&
                            medicationSnapshot!.isServerConfirmed &&
                            careError == null &&
                            medicationError == null &&
                            medicationForToday != null &&
                            todayAgenda.isEmpty)
                          Text(
                            strings.noCareToday,
                            key: const Key('care.empty'),
                            style: const TextStyle(
                              color: CopawColors.purpleDark,
                            ),
                          )
                        else ...[
                          if (careError != null) ...[
                            _RetryWarningBanner(
                              key: const Key('care.error'),
                              message: _careLoadMessage(strings),
                              retryLabel: strings.retryCare,
                              retryKey: const Key('care.retry'),
                              onRetry: _startCareObservation,
                            ),
                            const SizedBox(height: 10),
                          ],
                          if (medicationError != null) ...[
                            _RetryWarningBanner(
                              key: const Key('medication.error'),
                              message: _medicationErrorMessage(
                                strings,
                                medicationError!,
                                fromAction: medicationErrorFromAction,
                              ),
                              retryLabel: strings.retryMedication,
                              onRetry: _startMedicationObservation,
                            ),
                            const SizedBox(height: 10),
                          ],
                          if ((careSnapshot == null && careError == null) ||
                              (medicationSnapshot == null &&
                                  medicationError == null))
                            const Center(child: CircularProgressIndicator())
                          else ...[
                            if (medicationSnapshot?.isServerConfirmed == false)
                              _WarningBanner(
                                key: const Key('medication.cacheWarning'),
                                message: strings.medicationNotCurrent,
                              ),
                            if (taskResponsibilityError != null ||
                                taskResponsibilitySnapshot?.isFromCache ==
                                    true ||
                                taskResponsibilitySnapshot
                                        ?.authorityMalformed ==
                                    true ||
                                (taskResponsibilitySnapshot
                                            ?.droppedTransferCount ??
                                        0) >
                                    0) ...[
                              _WarningBanner(
                                key: const Key('responsibility.notCurrent'),
                                message: strings.responsibilityNotCurrent,
                              ),
                              const SizedBox(height: 10),
                            ],
                            for (final item in todayAgenda) ...[
                              if (item.task case final task?)
                                _TaskRow(
                                  task: task,
                                  session: liveSession,
                                  members: householdMembers,
                                  pet: pets
                                      .where((pet) => pet.id == task.petId)
                                      .firstOrNull,
                                  pendingTransfer: taskResponsibilitySnapshot
                                      ?.pendingByTaskId[task.id],
                                  responsibilityCurrent:
                                      taskResponsibilitySnapshot != null &&
                                      taskResponsibilityError == null &&
                                      !taskResponsibilitySnapshot!
                                          .isFromCache &&
                                      !taskResponsibilitySnapshot!
                                          .authorityMalformed &&
                                      taskResponsibilitySnapshot!
                                              .droppedTransferCount ==
                                          0,
                                  persisted: careSnapshot!.tasks.any(
                                    (persisted) => persisted.id == task.id,
                                  ),
                                  readOnly:
                                      unsafeDocumentIds?.contains(task.id) ==
                                          true ||
                                      unsafeDocumentIds?.contains(
                                            task.routineId,
                                          ) ==
                                          true,
                                )
                              else if (item.medication case final medication?)
                                _MedicationDoseCard(
                                  occurrence: medication,
                                  pet: pets
                                      .where(
                                        (pet) => pet.id == medication.petId,
                                      )
                                      .firstOrNull,
                                  serverConfirmed:
                                      medicationSnapshot?.isServerConfirmed ==
                                      true,
                                  busy: medicationActionId == medication.id,
                                  strings: strings,
                                  timeZoneIdentifier: timeZone,
                                  onClaim: () => _medicationAction(
                                    medication,
                                    () => medicationRepository.claim(
                                      householdId: household.id,
                                      occurrence: medication,
                                    ),
                                  ),
                                  onAdminister: () => _medicationAction(
                                    medication,
                                    () => medicationRepository.administer(
                                      householdId: household.id,
                                      occurrence: medication,
                                    ),
                                  ),
                                  onSkip: () => _skipMedication(medication),
                                  onDetails: () =>
                                      _showMedicationOccurrenceDetails(
                                        medication,
                                        pets,
                                        strings,
                                      ),
                                ),
                              const SizedBox(height: 10),
                            ],
                          ],
                        ],
                        if (hasUnsafeCare) ...[
                          const SizedBox(height: 10),
                          Text(
                            strings.legacyTaskWarning,
                            key: const Key('care.legacyWarning'),
                            style: const TextStyle(
                              color: Color(0xFF8A5A00),
                              fontSize: 12,
                            ),
                          ),
                        ],
                        const SizedBox(height: 14),
                        FilledButton.icon(
                          key: const Key('care.addTask'),
                          onPressed: activePets.isEmpty
                              ? null
                              : () => _showAddTaskForToday(
                                  liveSession,
                                  activePets,
                                ),
                          icon: const Icon(Icons.add_rounded),
                          label: Text(strings.addTask),
                        ),
                      ],
                    ),
                  ),
                ],
                if (selectedSection == 3 && selectedRecordSection == 0) ...[
                  _RecordsEntryCard(
                    entryKey: const Key('records.medication.open'),
                    icon: Icons.medication_rounded,
                    title: strings.medications,
                    help: strings.medicationRecordsHelp,
                    onTap: () => _selectRecordSection(1),
                  ),
                  const SizedBox(height: 12),
                  _RecordsEntryCard(
                    entryKey: const Key('records.health.open'),
                    icon: Icons.monitor_heart_rounded,
                    title: strings.health,
                    help: strings.healthRecordsHelp,
                    onTap: () => _selectRecordSection(2),
                  ),
                  const SizedBox(height: 12),
                  _RecordsEntryCard(
                    entryKey: const Key('records.activity.open'),
                    icon: Icons.history_rounded,
                    title: strings.factualHistory,
                    help: strings.factualHistoryHelp,
                    onTap: () => _selectRecordSection(3),
                  ),
                  const SizedBox(height: 12),
                  _RecordsEntryCard(
                    entryKey: const Key('records.reports.open'),
                    icon: Icons.summarize_outlined,
                    title: strings.reports,
                    help: strings.reportsHelp,
                    onTap: () => _selectRecordSection(4),
                  ),
                  const SizedBox(height: 12),
                  _RecordsEntryCard(
                    entryKey: const Key('records.search.open'),
                    icon: Icons.search_rounded,
                    title: strings.searchHistory,
                    help: strings.searchHistoryHelp,
                    onTap: () => _selectRecordSection(5),
                  ),
                  const SizedBox(height: 12),
                  _RecordsEntryCard(
                    entryKey: const Key('records.vetPack.open'),
                    icon: Icons.local_hospital_outlined,
                    title: strings.vetVisitPack,
                    help: strings.vetVisitPackHelp,
                    onTap: () => _selectRecordSection(6),
                  ),
                  const SizedBox(height: 12),
                  _RecordsEntryCard(
                    entryKey: const Key('records.coverage.open'),
                    icon: Icons.fact_check_outlined,
                    title: strings.careCoverage,
                    help: strings.careCoverageHelp,
                    onTap: () => _selectRecordSection(7),
                  ),
                ],
                if (selectedSection == 3 && selectedRecordSection == 7) ...[
                  _RecordsBackButton(
                    strings: strings,
                    onPressed: () => _selectRecordSection(0),
                  ),
                  const SizedBox(height: 12),
                  CareCoverageSection(
                    strings: strings,
                    timeZoneIdentifier: timeZone,
                    endInstant: DateTime.now(),
                    tasks: careSnapshot?.tasks ?? const <CareTask>[],
                    medicationOccurrences:
                        medicationSnapshot?.occurrences ??
                        const <MedicationOccurrence>[],
                    healthRecords:
                        healthSnapshot?.records ?? const <HealthRecord>[],
                  ),
                ],
                if (selectedSection == 3 &&
                    selectedRecordSection == 6 &&
                    activePets.isNotEmpty) ...[
                  _RecordsBackButton(
                    strings: strings,
                    onPressed: () => _selectRecordSection(0),
                  ),
                  const SizedBox(height: 12),
                  VetVisitPackSection(
                    strings: strings,
                    pets: activePets,
                    timeZoneIdentifier: timeZone,
                    endInstant: DateTime.now(),
                    handoff: handoffSnapshot?.handoff,
                    medications:
                        medicationSnapshot?.medications ??
                        const <Medication>[],
                    medicationOccurrences:
                        medicationSnapshot?.occurrences ??
                        const <MedicationOccurrence>[],
                    healthRecords:
                        healthSnapshot?.records ?? const <HealthRecord>[],
                  ),
                ],
                if (selectedSection == 3 && selectedRecordSection == 5) ...[
                  _RecordsBackButton(
                    strings: strings,
                    onPressed: () => _selectRecordSection(0),
                  ),
                  const SizedBox(height: 12),
                  HistorySearchSection(
                    strings: strings,
                    timeZoneIdentifier: timeZone,
                    pets: activePets,
                    healthRecords:
                        healthSnapshot?.records ?? const <HealthRecord>[],
                    medicationOccurrences:
                        medicationSnapshot?.occurrences ??
                        const <MedicationOccurrence>[],
                    tasks: careSnapshot?.tasks ?? const <CareTask>[],
                  ),
                ],
                if (selectedSection == 3 && selectedRecordSection == 1) ...[
                  _RecordsBackButton(
                    strings: strings,
                    onPressed: () => _selectRecordSection(0),
                  ),
                  const SizedBox(height: 12),
                  _MedicationSection(
                    selectedPet: todayFilteredPet,
                    pets: pets,
                    snapshot: medicationSnapshot,
                    planned:
                        medicationForToday ??
                        const <PlannedMedicationOccurrence>[],
                    error: medicationForToday == null
                        ? const MedicationRepositoryException(
                            MedicationRepositoryErrorCode.malformedData,
                          )
                        : medicationError,
                    errorFromAction: medicationErrorFromAction,
                    actionId: medicationActionId,
                    strings: strings,
                    timeZoneIdentifier: timeZone,
                    showPlanManagement: true,
                    onRetry: _startMedicationObservation,
                    onAdd: activePets.isEmpty
                        ? null
                        : () => _showMedicationPlanForFilter(
                            liveSession,
                            activePets,
                          ),
                    onEdit: (medication, schedule) => _showMedicationPlan(
                      liveSession,
                      pets.firstWhere((pet) => pet.id == medication.petId),
                      medication: medication,
                      schedule: schedule,
                    ),
                    onStop: (medication) =>
                        _stopMedicationPlan(liveSession, medication),
                    onClaim: (item) => _medicationAction(
                      item,
                      () => medicationRepository.claim(
                        householdId: household.id,
                        occurrence: item,
                      ),
                    ),
                    onAdminister: (item) => _medicationAction(
                      item,
                      () => medicationRepository.administer(
                        householdId: household.id,
                        occurrence: item,
                      ),
                    ),
                    onSkip: _skipMedication,
                  ),
                ],
                if (selectedSection == 1) ...[
                  FilledButton.icon(
                    key: const Key('care.addTask'),
                    onPressed: activePets.isEmpty
                        ? null
                        : selectedPet == null
                        ? () => _showAddTaskForToday(
                            liveSession,
                            activePets,
                            initialDate: selectedCalendarDate,
                          )
                        : () => _showAddTask(
                            liveSession,
                            selectedPet,
                            initialDate: selectedCalendarDate,
                          ),
                    icon: const Icon(Icons.add_rounded),
                    label: Text(strings.addTask),
                  ),
                  const SizedBox(height: 14),
                  _CalendarCard(
                    selectedDate: selectedCalendarDate,
                    onDateChanged: (value) =>
                        setState(() => selectedCalendarDate = value),
                    routines: selectedRoutines,
                    persistedTasks: selectedTasks,
                    strings: strings,
                    timeZoneIdentifier: timeZone,
                    petName: todayFilteredPet?.name,
                    pets: activePets,
                  ),
                ],
                if (selectedSection == 3 && selectedRecordSection == 2) ...[
                  _RecordsBackButton(
                    strings: strings,
                    onPressed: () => _selectRecordSection(0),
                  ),
                  const SizedBox(height: 12),
                  _HealthCard(
                    key: ValueKey('health.$todayPetFilterId'),
                    selectedPet: todayFilteredPet,
                    pets: activePets,
                    records:
                        healthSnapshot?.records
                            .where(
                              (record) => todayPetIds.contains(record.petId),
                            )
                            .toList(growable: false) ??
                        const [],
                    loading: healthSnapshot == null && healthError == null,
                    error: healthError,
                    isFromCache: healthSnapshot?.isFromCache == true,
                    droppedRecordCount: healthSnapshot?.droppedRecordCount ?? 0,
                    strings: strings,
                    timeZoneIdentifier: timeZone,
                    onRetry: _startHealthObservation,
                    onAdd: activePets.isEmpty
                        ? null
                        : () => _showHealthForFilter(liveSession, activePets),
                    onDailyCheckIn: (pet) =>
                        _showDailyHealthCheckIn(liveSession, pet),
                  ),
                ],
                NotificationCenterPane(
                  mode: selectedSection == 2
                      ? NotificationCenterPaneMode.updates
                      : selectedSection == 4
                      ? NotificationCenterPaneMode.profile
                      : NotificationCenterPaneMode.hidden,
                  householdId: liveSession.household.id,
                  memberId: liveSession.caregiver.id,
                  memberJoinedAt: liveSession.memberJoinedAt,
                  timeZoneIdentifier: liveSession.household.timeZoneIdentifier,
                  members: householdMembers,
                  strings: strings,
                  changesUnread: _hasUnreadCollaboration,
                  onUnreadChanged: (value) {
                    if (mounted && notificationReminderUnread != value) {
                      setState(() => notificationReminderUnread = value);
                    }
                  },
                  onRouteOpened: () {
                    if (mounted) setState(() => selectedSection = 2);
                  },
                  onRouteRejected: () {
                    if (mounted) setState(() => selectedSection = 0);
                  },
                  onChangesSelected: _maybeMarkCollaborationRead,
                  changes: _UpdatesCard(
                    snapshot: collaborationSnapshot,
                    olderEvents: olderCollaborationEvents,
                    errorMessage: collaborationError == null
                        ? null
                        : _collaborationErrorMessage(
                            strings,
                            collaborationError!,
                          ),
                    pageErrorMessage: collaborationPageError == null
                        ? null
                        : _collaborationErrorMessage(
                            strings,
                            collaborationPageError!,
                          ),
                    readErrorMessage: collaborationReadError == null
                        ? null
                        : strings.updatesReadStateFailure,
                    readStatePending:
                        collaborationReadSnapshot?.hasPendingWrites == true,
                    loadingOlder: collaborationLoadingOlder,
                    hasMore: collaborationHasMore,
                    olderDroppedEventCount: olderCollaborationDroppedEventCount,
                    olderIsFromCache: olderCollaborationFromCache,
                    olderPotentiallyIncomplete:
                        olderCollaborationPotentiallyIncomplete,
                    strings: strings,
                    timeZoneIdentifier: timeZone,
                    onRetry: _startCollaborationObservation,
                    onRetryRead: _startCollaborationReadObservation,
                    onLoadOlder: _loadOlderCollaborationEvents,
                  ),
                ),
                if (selectedSection == 3 && selectedRecordSection == 3) ...[
                  _RecordsBackButton(
                    strings: strings,
                    onPressed: () => _selectRecordSection(0),
                  ),
                  const SizedBox(height: 12),
                  if ((healthSnapshot?.droppedRecordCount ?? 0) > 0) ...[
                    _WarningBanner(
                      key: const Key('activity.healthIncomplete'),
                      message: strings.healthRecordsNeedRepair(
                        healthSnapshot!.droppedRecordCount,
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  _ActivityCard(
                    tasks: selectedTasks,
                    strings: strings,
                    timeZoneIdentifier: timeZone,
                    petName: selectedPet?.name,
                    medications: _medicationHistoryForPets(todayPetIds),
                    healthRecords:
                        healthSnapshot?.records
                            .where(
                              (record) => todayPetIds.contains(record.petId),
                            )
                            .toList(growable: false) ??
                        const [],
                  ),
                ],
                if (selectedSection == 3 && selectedRecordSection == 4) ...[
                  _RecordsBackButton(
                    strings: strings,
                    onPressed: () => _selectRecordSection(0),
                  ),
                  const SizedBox(height: 18),
                  for (final reportPet in activePets.where(
                    (pet) => todayPetIds.contains(pet.id),
                  )) ...[
                    _ReportCard(
                      key: ValueKey('report.${reportPet.id}'),
                      selectedPet: reportPet,
                      careSnapshot: careSnapshot,
                      medicationSnapshot: medicationSnapshot,
                      healthSnapshot: healthSnapshot,
                      hasSourceError:
                          careError != null ||
                          medicationError != null ||
                          healthError != null ||
                          (healthSnapshot?.droppedRecordCount ?? 0) > 0,
                      endInstant: currentInstant,
                      timeZoneIdentifier: timeZone,
                      strings: strings,
                    ),
                    const SizedBox(height: 18),
                  ],
                ],
                if (selectedSection == 4) ...[
                  _HouseholdAccessCard(
                    inviteCode: household.inviteCode,
                    members: householdMembers,
                    strings: strings,
                  ),
                  const SizedBox(height: 18),
                  _LanguagePreferenceCard(strings: strings, locale: locale),
                  const SizedBox(height: 18),
                  _HandoffCard(
                    snapshot: handoffSnapshot,
                    error: handoffError,
                    strings: strings,
                    timeZoneIdentifier: timeZone,
                    onRetry: _startHandoffObservation,
                    onEdit: () => _showHandoff(liveSession),
                  ),
                  const SizedBox(height: 18),
                  _HandoffSessionCard(
                    snapshot: handoffSessionSnapshot,
                    error: handoffSessionError,
                    strings: strings,
                    session: liveSession,
                    members: householdMembers,
                    template: handoffSnapshot,
                    careSnapshot: careSnapshot,
                    medicationSnapshot: medicationSnapshot,
                    onRetry: _startHandoffSessionObservation,
                    onOffer: () => _showHandoffOffer(liveSession),
                  ),
                  const SizedBox(height: 18),
                  CopawCard(
                    child: FilledButton.icon(
                      key: const Key('profile.edit'),
                      onPressed: () => _showProfile(liveSession),
                      icon: const Icon(Icons.edit),
                      label: Text(strings.editProfile),
                    ),
                  ),
                  const SizedBox(height: 18),
                  OutlinedButton.icon(
                    key: const Key('household.disconnect'),
                    onPressed: disconnecting || leaving ? null : _disconnect,
                    icon: disconnecting
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.logout_rounded),
                    label: Text(
                      disconnecting
                          ? strings.disconnectingThisDevice
                          : strings.disconnectThisDevice,
                    ),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    key: const Key('household.leave'),
                    onPressed: disconnecting || leaving ? null : _leave,
                    icon: leaving
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.person_remove_alt_1_rounded),
                    label: Text(
                      leaving
                          ? strings.revokingHouseholdAccess
                          : strings.leaveHousehold,
                    ),
                  ),
                  if (leaveError != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      leaveError!,
                      key: const Key('household.leaveError'),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                  const SizedBox(height: 18),
                  _PetManagementCard(
                    householdId: household.id,
                    pets: pets,
                    loading: petSnapshot == null && petError == null,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _leave() async {
    final strings = AppStrings(
      ref.read(appControllerProvider).value?.locale ?? AppLocale.english,
    );
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(strings.leaveHousehold),
        content: Text(strings.leaveHouseholdConfirmation),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(strings.cancel),
          ),
          FilledButton(
            key: const Key('household.leaveConfirm'),
            onPressed: () => Navigator.pop(context, true),
            child: Text(strings.leaveHousehold),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      leaving = true;
      leaveError = null;
      leaveMutationId ??=
          'flutter-leave-'
          '${DateTime.now().microsecondsSinceEpoch.toRadixString(16)}';
    });
    try {
      await ref
          .read(appControllerProvider.notifier)
          .leaveHousehold(
            householdId: widget.session.household.id,
            clientMutationId: leaveMutationId!,
          );
      leaveMutationId = null;
    } on MembershipExitException catch (exception) {
      if (mounted) {
        setState(() => leaveError = _membershipExitMessage(strings, exception));
      }
    } on Object {
      if (mounted) setState(() => leaveError = strings.leaveRemoteFailure);
    } finally {
      if (mounted) setState(() => leaving = false);
    }
  }

  Future<void> _disconnect() async {
    final strings = AppStrings(
      ref.read(appControllerProvider).value?.locale ?? AppLocale.english,
    );
    setState(() {
      disconnecting = true;
      leaveError = null;
    });
    var notificationDisabled = false;
    try {
      await notificationRepository.disable();
      notificationDisabled = true;
      await ref.read(appControllerProvider.notifier).disconnectThisDevice();
    } on Object {
      if (mounted) {
        setState(
          () => leaveError = notificationDisabled
              ? strings.disconnectLocalSessionFailure
              : strings.disconnectNotificationFailure,
        );
      }
    } finally {
      if (mounted) setState(() => disconnecting = false);
    }
  }

  String _membershipExitMessage(
    AppStrings strings,
    MembershipExitException exception,
  ) {
    if (exception.code == MembershipExitErrorCode.blocked) {
      return switch (exception.diagnosticCode) {
        'owner' => strings.leaveBlockedOwner,
        'assignedTask' => strings.leaveBlockedAssignedTask,
        'pendingTransfer' => strings.leaveBlockedPendingTransfer,
        'activeHandoff' => strings.leaveBlockedActiveHandoff,
        _ => strings.leaveBlocked,
      };
    }
    return switch (exception.code) {
      MembershipExitErrorCode.network => strings.leaveNetworkFailure,
      MembershipExitErrorCode.permission => strings.leavePermissionFailure,
      MembershipExitErrorCode.stale => strings.leaveStaleFailure,
      _ => strings.leaveRemoteFailure,
    };
  }

  Future<void> _showHandoffOffer(HouseholdSession session) async {
    final handoff = handoffSnapshot;
    if (handoff?.handoff == null ||
        handoff!.isFromCache ||
        handoff.hasPendingWrites) {
      return;
    }
    final recipients = householdMembers
        .where((member) => member.id != session.caregiver.id)
        .toList(growable: false);
    if (recipients.isEmpty) return;
    await showDialog<void>(
      context: context,
      builder: (context) => _HandoffOfferDialog(
        strings: AppStrings(
          ref.read(appControllerProvider).value?.locale ?? AppLocale.english,
        ),
        session: session,
        recipients: recipients,
        expectedHandoffRevision: handoff.handoff!.revision,
      ),
    );
  }

  Future<void> _showAddHealth(HouseholdSession session, Pet pet) async {
    final recordedAt = DateTime.now();
    final strings = AppStrings(
      ref.read(appControllerProvider).value?.locale ?? AppLocale.english,
    );
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => _AddHealthDialog(
        strings: strings,
        onSave: (type, detail, weightKilograms, waterMilliliters) =>
            healthRepository.createRecord(
              householdId: session.household.id,
              petId: pet.id,
              petName: pet.name,
              type: type,
              recordedAt: recordedAt,
              timeZoneIdentifier: session.household.timeZoneIdentifier ?? '',
              detail: detail,
              weightKilograms: weightKilograms,
              waterMilliliters: waterMilliliters,
              createdById: session.caregiver.id,
              createdByName: session.caregiver.displayName,
            ),
      ),
    );
  }

  Future<void> _showDailyHealthCheckIn(
    HouseholdSession session,
    Pet pet,
  ) async {
    final strings = AppStrings(
      ref.read(appControllerProvider).value?.locale ?? AppLocale.english,
    );
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => _DailyHealthCheckInDialog(
        pet: pet,
        strings: strings,
        onSave: (checkIn, waterMilliliters, detail) =>
            healthRepository.createRecord(
              householdId: session.household.id,
              petId: pet.id,
              petName: pet.name,
              type: HealthRecordType.dailyCheckIn,
              recordedAt: DateTime.now(),
              timeZoneIdentifier: session.household.timeZoneIdentifier ?? '',
              detail: detail,
              weightKilograms: null,
              waterMilliliters: waterMilliliters,
              dailyCheckIn: checkIn,
              createdById: session.caregiver.id,
              createdByName: session.caregiver.displayName,
            ),
      ),
    );
  }

  Future<void> _showHealthForFilter(
    HouseholdSession session,
    List<Pet> activePets,
  ) async {
    final pet = await _choosePet(activePets);
    if (pet != null && mounted) await _showAddHealth(session, pet);
  }

  Future<void> _showHandoff(HouseholdSession session) async {
    final current = handoffSnapshot?.handoff;
    final strings = AppStrings(
      ref.read(appControllerProvider).value?.locale ?? AppLocale.english,
    );
    await showDialog<void>(
      context: context,
      builder: (context) => _HandoffDialog(
        current: current,
        strings: strings,
        onSave:
            (
              careInstructions,
              emergencyContactName,
              emergencyContactPhone,
              veterinaryHospitalName,
              veterinaryHospitalPhone,
            ) => handoffRepository.saveHandoff(
              householdId: session.household.id,
              expectedRevision: current?.revision,
              careInstructions: careInstructions,
              emergencyContactName: emergencyContactName,
              emergencyContactPhone: emergencyContactPhone,
              veterinaryHospitalName: veterinaryHospitalName,
              veterinaryHospitalPhone: veterinaryHospitalPhone,
              updatedById: session.caregiver.id,
              updatedByName: session.caregiver.displayName,
            ),
      ),
    );
  }

  Future<void> _showAddTask(
    HouseholdSession session,
    Pet pet, {
    required DateTime initialDate,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) =>
          _AddTaskSheet(session: session, pet: pet, initialDate: initialDate),
    );
  }

  Future<void> _showAddTaskForToday(
    HouseholdSession session,
    List<Pet> activePets, {
    DateTime? initialDate,
  }) async {
    final preselected = activePets
        .where((pet) => pet.id == todayPetFilterId)
        .firstOrNull;
    Pet? pet = preselected;
    pet ??= activePets.length == 1 ? activePets.single : null;
    pet ??= await showDialog<Pet>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: Text(
          AppStrings(
            ref.read(appControllerProvider).value?.locale ?? AppLocale.japanese,
          ).selectedPet,
        ),
        children: [
          for (final candidate in activePets)
            SimpleDialogOption(
              key: Key('care.petChoice.${candidate.id}'),
              onPressed: () => Navigator.pop(dialogContext, candidate),
              child: _PetIdentityPill(pet: candidate),
            ),
        ],
      ),
    );
    if (pet == null || !mounted) return;
    await _showAddTask(
      session,
      pet,
      initialDate: initialDate ?? currentInstant,
    );
  }

  Future<void> _showProfile(HouseholdSession session) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _ProfileSheet(session: session),
    );
  }

  List<PlannedMedicationOccurrence>? _medicationForDay(
    MedicationOccurrenceService service,
    String petId,
    DateTime instant,
  ) {
    try {
      return service
          .forDay(
            selectedInstant: instant,
            schedules: medicationSnapshot!.schedules.where(
              (item) => item.petId == petId,
            ),
            persisted: medicationSnapshot!.occurrences.where(
              (item) => item.petId == petId,
            ),
          )
          .toList(growable: false);
    } on Object {
      return null;
    }
  }

  List<MedicationOccurrence> _medicationHistoryForPets(Set<String> petIds) {
    final result =
        medicationSnapshot?.occurrences
            .where(
              (item) =>
                  petIds.contains(item.petId) &&
                  item.isServerConfirmed &&
                  item.outcomeStatus != MedicationOutcomeStatus.unresolved,
            )
            .toList() ??
        <MedicationOccurrence>[];
    result.sort(
      (left, right) => (right.outcomeAt ?? right.dueAt).compareTo(
        left.outcomeAt ?? left.dueAt,
      ),
    );
    return result;
  }

  Future<void> _showMedicationPlan(
    HouseholdSession session,
    Pet pet, {
    Medication? medication,
    MedicationScheduleVersion? schedule,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _MedicationPlanSheet(
        session: session,
        pet: pet,
        medication: medication,
        schedule: schedule,
      ),
    );
  }

  Future<void> _showMedicationPlanForFilter(
    HouseholdSession session,
    List<Pet> activePets,
  ) async {
    final pet = await _choosePet(activePets);
    if (pet != null && mounted) await _showMedicationPlan(session, pet);
  }

  void _showMedicationOccurrenceDetails(
    PlannedMedicationOccurrence occurrence,
    List<Pet> pets,
    AppStrings strings,
  ) {
    final snapshot = medicationSnapshot;
    final medication = snapshot?.medications
        .where((item) => item.id == occurrence.medicationId)
        .firstOrNull;
    if (snapshot == null || medication == null) return;
    _showMedicationDetails(
      context,
      medication,
      snapshot.schedules
          .where((schedule) => schedule.medicationId == medication.id)
          .toList(growable: false),
      pets.where((pet) => pet.id == medication.petId).firstOrNull,
      strings,
    );
  }

  Future<Pet?> _choosePet(List<Pet> activePets) async {
    final filtered = activePets
        .where((pet) => pet.id == todayPetFilterId)
        .firstOrNull;
    if (filtered != null || activePets.length == 1) {
      return filtered ?? activePets.single;
    }
    return showDialog<Pet>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: Text(
          AppStrings(
            ref.read(appControllerProvider).value?.locale ?? AppLocale.japanese,
          ).selectedPet,
        ),
        children: [
          for (final candidate in activePets)
            SimpleDialogOption(
              key: Key('pets.choice.${candidate.id}'),
              onPressed: () => Navigator.pop(dialogContext, candidate),
              child: _PetIdentityPill(pet: candidate),
            ),
        ],
      ),
    );
  }

  Future<void> _stopMedicationPlan(
    HouseholdSession session,
    Medication medication,
  ) async {
    final zone = session.household.timeZoneIdentifier;
    if (zone == null) return;
    final location = tz.getLocation(zone);
    final today = tz.TZDateTime.now(location);
    final tomorrow = tz.TZDateTime(
      location,
      today.year,
      today.month,
      today.day + 1,
    );
    final localDate =
        '${tomorrow.year.toString().padLeft(4, '0')}-'
        '${tomorrow.month.toString().padLeft(2, '0')}-'
        '${tomorrow.day.toString().padLeft(2, '0')}';
    try {
      await medicationRepository.stopPlan(
        householdId: session.household.id,
        medication: medication,
        effectiveUntilLocalDate: localDate,
      );
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          medicationError = error;
          medicationErrorFromAction = true;
        });
      }
    }
  }

  Future<void> _medicationAction(
    PlannedMedicationOccurrence occurrence,
    Future<void> Function() action,
  ) async {
    if (medicationSnapshot?.isServerConfirmed != true) return;
    setState(() {
      medicationActionId = occurrence.id;
      medicationError = null;
      medicationErrorFromAction = false;
    });
    try {
      await action();
    } on MedicationRepositoryException catch (error) {
      if (mounted) {
        setState(() {
          medicationError = error;
          medicationErrorFromAction = true;
        });
        if (error.code == MedicationRepositoryErrorCode.terminalConflict ||
            error.code ==
                MedicationRepositoryErrorCode.responsibilityConflict ||
            error.code == MedicationRepositoryErrorCode.stale) {
          _startMedicationObservation();
        }
      }
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          medicationError = error;
          medicationErrorFromAction = true;
        });
      }
    } finally {
      if (mounted) setState(() => medicationActionId = null);
    }
  }

  Future<void> _skipMedication(PlannedMedicationOccurrence occurrence) async {
    final result = await showDialog<_MedicationSkipInput>(
      context: context,
      builder: (context) => const _MedicationSkipDialog(),
    );
    if (result == null || !mounted) return;
    await _medicationAction(
      occurrence,
      () => medicationRepository.skip(
        householdId: widget.session.household.id,
        occurrence: occurrence,
        reasonCode: result.code,
        reasonNote: result.note,
      ),
    );
  }

  String _careLoadMessage(AppStrings strings) {
    final error = careError;
    if (error is HouseholdRepositoryException &&
        (error.code == HouseholdRepositoryErrorCode.permission ||
            error.code == HouseholdRepositoryErrorCode.authentication)) {
      return strings.carePermissionFailure;
    }
    return strings.careLoadFailure;
  }

  String _syncLoadMessage(AppStrings strings) {
    final error = syncError;
    if (error is HouseholdRepositoryException) {
      return switch (error.code) {
        HouseholdRepositoryErrorCode.network =>
          strings.householdSyncNetworkFailure,
        HouseholdRepositoryErrorCode.permission ||
        HouseholdRepositoryErrorCode.authentication =>
          strings.householdSyncPermissionFailure,
        HouseholdRepositoryErrorCode.malformedData =>
          strings.householdSyncDataFailure,
        _ => strings.householdSyncFailure,
      };
    }
    return strings.householdSyncFailure;
  }

  String _petLoadMessage(AppStrings strings) {
    final error = petError;
    if (error is PetRepositoryException) {
      return switch (error.code) {
        PetRepositoryErrorCode.permission => strings.petPermissionFailure,
        PetRepositoryErrorCode.malformedData => strings.petDataFailure,
        _ => strings.petLoadFailure,
      };
    }
    return strings.petLoadFailure;
  }

  void _scheduleDayRefresh(RoutineOccurrenceService service, String? timeZone) {
    if (timeZone == null || scheduledTimeZone == timeZone) return;
    scheduledTimeZone = timeZone;
    dayRefreshTimer?.cancel();
    final delay = service.durationUntilNextDay(
      instant: currentInstant,
      householdTimeZoneIdentifier: timeZone,
    );
    if (delay == null) return;
    dayRefreshTimer = Timer(delay, () {
      if (!mounted) return;
      setState(() => currentInstant = DateTime.now());
      scheduledTimeZone = null;
    });
  }
}

CollaborationReadCursor _cursorForCollaborationEvent(
  CollaborationEvent event,
) => CollaborationReadCursor(occurredAt: event.occurredAt, eventId: event.id);

int _compareCollaborationCursors(
  CollaborationReadCursor left,
  CollaborationReadCursor right,
) {
  final byTime = left.occurredAt.compareTo(right.occurredAt);
  return byTime != 0 ? byTime : left.eventId.compareTo(right.eventId);
}

class _HouseholdHero extends StatelessWidget {
  const _HouseholdHero({
    required this.household,
    required this.caregiver,
    required this.pets,
    required this.todayPetFilterId,
    required this.loadingPets,
    required this.compact,
    required this.strings,
    required this.onTodayPetChanged,
  });

  final Household household;
  final Caregiver caregiver;
  final List<Pet> pets;
  final String? todayPetFilterId;
  final bool loadingPets;
  final bool compact;
  final AppStrings strings;
  final ValueChanged<String?> onTodayPetChanged;

  @override
  Widget build(BuildContext context) {
    final petFilterHeight = (MediaQuery.textScalerOf(context).scale(14) + 28)
        .clamp(42.0, 76.0);
    if (compact) {
      return CopawCard(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: CopawColors.purple,
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(
                Icons.pets_rounded,
                color: Colors.white,
                size: 22,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    household.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  Text(
                    strings.signedInAs(caregiver.displayName),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: CopawColors.purpleDark,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            if (loadingPets)
              const SizedBox.square(
                key: Key('pets.loading'),
                dimension: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else if (pets.isNotEmpty)
              SizedBox(
                width: 140,
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    key: const Key('pets.selector'),
                    value: todayPetFilterId ?? '__all_pets__',
                    isExpanded: true,
                    icon: const Icon(Icons.keyboard_arrow_down_rounded),
                    items: [
                      DropdownMenuItem(
                        value: '__all_pets__',
                        child: Text(strings.allPets),
                      ),
                      ...pets
                          .where((pet) => !pet.isArchived)
                          .map(
                            (pet) => DropdownMenuItem(
                              value: pet.id,
                              child: Text(
                                pet.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                    ],
                    onChanged: (value) {
                      if (value == '__all_pets__') {
                        onTodayPetChanged(null);
                      } else {
                        onTodayPetChanged(value);
                      }
                    },
                  ),
                ),
              ),
          ],
        ),
      );
    }
    return CopawCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [CopawColors.purple, CopawColors.blue],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x33665AF2),
                      blurRadius: 18,
                      offset: Offset(0, 8),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.pets_rounded,
                  color: Colors.white,
                  size: 30,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (household.id == 'local-ui-demo') ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: CopawColors.peach,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text(
                          'LOCAL UI DEMO',
                          style: TextStyle(
                            color: Color(0xFF9A4D14),
                            fontSize: 9,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.7,
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                    ],
                    Text(
                      household.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: CopawColors.ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      strings.signedInAs(caregiver.displayName),
                      style: const TextStyle(
                        color: CopawColors.purpleDark,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (loadingPets) ...[
            const SizedBox(height: 14),
            const LinearProgressIndicator(
              key: Key('pets.loading'),
              minHeight: 3,
            ),
          ] else if (pets.isNotEmpty) ...[
            const SizedBox(height: 14),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                strings.todaysCare,
                style: const TextStyle(
                  color: CopawColors.purpleDark,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: petFilterHeight,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  _PetFilterChip(
                    key: const Key('today.petFilter.all'),
                    label: strings.allPets,
                    selected: todayPetFilterId == null,
                    onSelected: () => onTodayPetChanged(null),
                  ),
                  for (final pet in pets.where((pet) => !pet.isArchived)) ...[
                    const SizedBox(width: 8),
                    _PetFilterChip(
                      key: Key('today.petFilter.${pet.id}'),
                      label: pet.name,
                      pet: pet,
                      selected: todayPetFilterId == pet.id,
                      onSelected: () => onTodayPetChanged(pet.id),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _TodayPetCard extends StatelessWidget {
  const _TodayPetCard({
    required this.pets,
    required this.itemCount,
    required this.strings,
  });

  final List<Pet> pets;
  final int itemCount;
  final AppStrings strings;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 154),
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF756AF7), Color(0xFF5D58E8)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(28),
        boxShadow: const [
          BoxShadow(
            color: Color(0x3D665AF2),
            blurRadius: 28,
            offset: Offset(0, 14),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            right: -5,
            bottom: -24,
            child: Transform.rotate(
              angle: -0.14,
              child: Icon(
                Icons.pets_rounded,
                size: 138,
                color: Colors.white.withValues(alpha: 0.13),
              ),
            ),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      strings.todaysCare,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.72),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      strings.todayCareCount(itemCount),
                      key: const Key('household.petName'),
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                          ),
                    ),
                    const SizedBox(height: 18),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final pet in pets)
                          _PetIdentityPill(pet: pet, light: true),
                      ],
                    ),
                  ],
                ),
              ),
              if (pets.isNotEmpty) _PetAvatar(pet: pets.first, size: 68),
            ],
          ),
        ],
      ),
    );
  }
}

class _PetFilterChip extends StatelessWidget {
  const _PetFilterChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onSelected,
    this.pet,
  });

  final String label;
  final bool selected;
  final VoidCallback onSelected;
  final Pet? pet;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    label: label,
    child: ChoiceChip(
      selected: selected,
      onSelected: (_) => onSelected(),
      avatar: pet == null ? const Icon(Icons.pets_rounded, size: 17) : null,
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (pet case final pet?) ...[
            _PetAvatar(pet: pet, size: 22),
            const SizedBox(width: 6),
          ],
          Text(label),
        ],
      ),
      labelStyle: const TextStyle(fontWeight: FontWeight.w800),
      side: BorderSide.none,
      backgroundColor: CopawColors.lavender.withValues(alpha: 0.55),
      selectedColor: CopawColors.purple.withValues(alpha: 0.18),
    ),
  );
}

class _PetIdentityPill extends StatelessWidget {
  const _PetIdentityPill({required this.pet, this.light = false});

  final Pet pet;
  final bool light;

  @override
  Widget build(BuildContext context) => Semantics(
    label: pet.name,
    child: Container(
      constraints: BoxConstraints(
        maxWidth: (MediaQuery.sizeOf(context).width * 0.46).clamp(96.0, 180.0),
      ),
      padding: const EdgeInsets.fromLTRB(5, 5, 10, 5),
      decoration: BoxDecoration(
        color: light
            ? Colors.white.withValues(alpha: 0.17)
            : CopawColors.lavender.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _PetAvatar(pet: pet, size: 25),
          const SizedBox(width: 6),
          Flexible(
            fit: FlexFit.loose,
            child: Text(
              pet.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: light ? Colors.white : CopawColors.ink,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _PetAvatar extends StatelessWidget {
  const _PetAvatar({required this.pet, this.size = 38});

  final Pet pet;
  final double size;

  @override
  Widget build(BuildContext context) {
    final color = _petColor(pet);
    return Semantics(
      image: true,
      label: pet.name,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [color, color.withValues(alpha: 0.72)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(size * 0.34),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.82),
            width: 2,
          ),
        ),
        child: Center(
          child: Text(
            _petEmoji(pet.species),
            style: TextStyle(fontSize: size * 0.5, height: 1),
          ),
        ),
      ),
    );
  }
}

String _petEmoji(PetSpecies? species) => switch (species) {
  PetSpecies.dog => '🐶',
  PetSpecies.cat => '🐱',
  PetSpecies.rabbit => '🐰',
  PetSpecies.other || null => '🐾',
};

Color _petColor(Pet pet) {
  final base = switch (pet.species) {
    PetSpecies.dog => CopawColors.orange,
    PetSpecies.cat => CopawColors.rose,
    PetSpecies.rabbit => CopawColors.blue,
    PetSpecies.other || null => CopawColors.purple,
  };
  final checksum = pet.id.codeUnits.fold<int>(0, (sum, value) => sum + value);
  final tint = 0.04 + (checksum % 3) * 0.035;
  return Color.lerp(
    base,
    checksum.isEven ? Colors.white : CopawColors.ink,
    tint,
  )!;
}

class _MedicationSection extends StatelessWidget {
  const _MedicationSection({
    required this.selectedPet,
    required this.pets,
    required this.snapshot,
    required this.planned,
    required this.error,
    required this.errorFromAction,
    required this.actionId,
    required this.strings,
    required this.timeZoneIdentifier,
    required this.showPlanManagement,
    required this.onRetry,
    required this.onAdd,
    required this.onEdit,
    required this.onStop,
    required this.onClaim,
    required this.onAdminister,
    required this.onSkip,
  });

  final Pet? selectedPet;
  final List<Pet> pets;
  final MedicationSnapshot? snapshot;
  final List<PlannedMedicationOccurrence> planned;
  final Object? error;
  final bool errorFromAction;
  final String? actionId;
  final AppStrings strings;
  final String? timeZoneIdentifier;
  final bool showPlanManagement;
  final VoidCallback onRetry;
  final VoidCallback? onAdd;
  final void Function(Medication, MedicationScheduleVersion) onEdit;
  final void Function(Medication) onStop;
  final void Function(PlannedMedicationOccurrence) onClaim;
  final void Function(PlannedMedicationOccurrence) onAdminister;
  final void Function(PlannedMedicationOccurrence) onSkip;

  @override
  Widget build(BuildContext context) {
    final medications =
        snapshot?.medications
            .where(
              (item) => selectedPet == null || item.petId == selectedPet?.id,
            )
            .toList(growable: false) ??
        const <Medication>[];
    final activeMedications = medications
        .where((medication) => medication.isActive)
        .toList(growable: false);
    final pastMedications = medications
        .where((medication) => !medication.isActive)
        .toList(growable: false);
    final outcomeHistory =
        snapshot?.occurrences
            .where(
              (occurrence) =>
                  (selectedPet == null ||
                      occurrence.petId == selectedPet?.id) &&
                  occurrence.isServerConfirmed &&
                  occurrence.outcomeStatus !=
                      MedicationOutcomeStatus.unresolved,
            )
            .toList() ??
        <MedicationOccurrence>[];
    outcomeHistory.sort(
      (left, right) => (right.outcomeAt ?? right.dueAt).compareTo(
        left.outcomeAt ?? left.dueAt,
      ),
    );
    return Column(
      children: [
        const SizedBox(height: 18),
        CopawCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                showPlanManagement
                    ? strings.todaysMedication
                    : strings.medications,
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
              if (selectedPet != null) ...[
                const SizedBox(height: 4),
                Text(
                  strings.medicationForPet(selectedPet!.name),
                  style: const TextStyle(color: CopawColors.muted),
                ),
              ] else ...[
                const SizedBox(height: 4),
                Text(
                  strings.allPets,
                  style: const TextStyle(color: CopawColors.muted),
                ),
              ],
              const SizedBox(height: 12),
              if (error != null) ...[
                _RetryWarningBanner(
                  key: const Key('medication.error'),
                  message: _medicationErrorMessage(
                    strings,
                    error!,
                    fromAction: errorFromAction,
                  ),
                  retryLabel: strings.retryMedication,
                  onRetry: onRetry,
                ),
                const SizedBox(height: 12),
              ],
              if (snapshot == null && error == null)
                const Center(
                  child: CircularProgressIndicator(
                    key: Key('medication.loading'),
                  ),
                )
              else if (snapshot?.isServerConfirmed == false)
                _WarningBanner(
                  key: const Key('medication.cacheWarning'),
                  message: strings.medicationNotCurrent,
                )
              else if (planned.isEmpty)
                Text(
                  strings.noMedicationDue,
                  key: const Key('medication.empty'),
                  style: const TextStyle(color: CopawColors.muted),
                )
              else
                for (final occurrence in planned) ...[
                  _MedicationDoseCard(
                    occurrence: occurrence,
                    pet: pets
                        .where((pet) => pet.id == occurrence.petId)
                        .firstOrNull,
                    serverConfirmed: snapshot?.isServerConfirmed == true,
                    busy: actionId == occurrence.id,
                    strings: strings,
                    timeZoneIdentifier: timeZoneIdentifier,
                    onClaim: () => onClaim(occurrence),
                    onAdminister: () => onAdminister(occurrence),
                    onSkip: () => onSkip(occurrence),
                    onDetails: () {
                      final medication = medications
                          .where((item) => item.id == occurrence.medicationId)
                          .firstOrNull;
                      if (medication == null) return;
                      _showMedicationDetails(
                        context,
                        medication,
                        snapshot!.schedules
                            .where(
                              (schedule) =>
                                  schedule.medicationId == medication.id,
                            )
                            .toList(growable: false),
                        pets
                            .where((pet) => pet.id == medication.petId)
                            .firstOrNull,
                        strings,
                      );
                    },
                  ),
                  const SizedBox(height: 10),
                ],
              if (showPlanManagement) ...[
                const SizedBox(height: 12),
                FilledButton.icon(
                  key: const Key('medication.add'),
                  onPressed: onAdd,
                  icon: const Icon(Icons.add),
                  label: Text(strings.addMedication),
                ),
              ],
            ],
          ),
        ),
        if (showPlanManagement && medications.isNotEmpty) ...[
          const SizedBox(height: 18),
          CopawCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  strings.medicationArchive,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (activeMedications.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Text(
                    strings.activeMedication,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  for (final medication in activeMedications)
                    _MedicationArchiveRow(
                      medication: medication,
                      pet: pets
                          .where((pet) => pet.id == medication.petId)
                          .firstOrNull,
                      schedules: snapshot!.schedules
                          .where(
                            (schedule) =>
                                schedule.medicationId == medication.id,
                          )
                          .toList(growable: false),
                      strings: strings,
                      onOpen: () => _showMedicationDetails(
                        context,
                        medication,
                        snapshot!.schedules
                            .where(
                              (schedule) =>
                                  schedule.medicationId == medication.id,
                            )
                            .toList(growable: false),
                        pets
                            .where((pet) => pet.id == medication.petId)
                            .firstOrNull,
                        strings,
                      ),
                      onEdit: () {
                        final schedule = snapshot!.schedules
                            .where(
                              (item) =>
                                  item.medicationId == medication.id &&
                                  item.id ==
                                      medication.currentScheduleVersionId,
                            )
                            .firstOrNull;
                        if (schedule != null) onEdit(medication, schedule);
                      },
                      onStop: () => onStop(medication),
                    ),
                ],
                if (pastMedications.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  Text(
                    strings.pastMedication,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  for (final medication in pastMedications)
                    _MedicationArchiveRow(
                      medication: medication,
                      pet: pets
                          .where((pet) => pet.id == medication.petId)
                          .firstOrNull,
                      schedules: snapshot!.schedules
                          .where(
                            (schedule) =>
                                schedule.medicationId == medication.id,
                          )
                          .toList(growable: false),
                      strings: strings,
                      onOpen: () => _showMedicationDetails(
                        context,
                        medication,
                        snapshot!.schedules
                            .where(
                              (schedule) =>
                                  schedule.medicationId == medication.id,
                            )
                            .toList(growable: false),
                        pets
                            .where((pet) => pet.id == medication.petId)
                            .firstOrNull,
                        strings,
                      ),
                    ),
                ],
              ],
            ),
          ),
        ],
        if (showPlanManagement) ...[
          const SizedBox(height: 18),
          _MedicationOutcomeHistoryCard(
            occurrences: outcomeHistory,
            strings: strings,
            timeZoneIdentifier: timeZoneIdentifier,
          ),
        ],
      ],
    );
  }
}

class _MedicationOutcomeHistoryCard extends StatelessWidget {
  const _MedicationOutcomeHistoryCard({
    required this.occurrences,
    required this.strings,
    required this.timeZoneIdentifier,
  });

  final List<MedicationOccurrence> occurrences;
  final AppStrings strings;
  final String? timeZoneIdentifier;

  @override
  Widget build(BuildContext context) => CopawCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          strings.medicationOutcomeHistory,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 10),
        if (occurrences.isEmpty)
          Text(
            strings.noMedicationOutcomeHistory,
            key: const Key('medication.history.empty'),
            style: const TextStyle(color: CopawColors.muted),
          )
        else
          for (final occurrence in occurrences) ...[
            ListTile(
              key: Key('medication.history.${occurrence.id}'),
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                occurrence.outcomeStatus == MedicationOutcomeStatus.administered
                    ? Icons.check_circle_rounded
                    : Icons.remove_circle_outline_rounded,
                color:
                    occurrence.outcomeStatus ==
                        MedicationOutcomeStatus.administered
                    ? CopawColors.green
                    : CopawColors.orange,
              ),
              title: Text(
                '${occurrence.medicationNameSnapshot} · ${occurrence.doseText}',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              subtitle: Text(
                [
                  occurrence.petNameSnapshot,
                  occurrence.outcomeStatus ==
                          MedicationOutcomeStatus.administered
                      ? strings.administered
                      : strings.skipped,
                  if (occurrence.outcomeByNameSnapshot case final actor?)
                    strings.medicationRecordedBy(actor),
                  if (occurrence.skippedReasonCode case final reason?)
                    _MedicationSkipDialogState._skipLabel(strings, reason),
                  ?occurrence.skippedReasonNote,
                ].join(' · '),
              ),
              trailing: Text(
                _formatHouseholdDateTime(
                  context,
                  occurrence.outcomeAt ?? occurrence.dueAt,
                  timeZoneIdentifier,
                ),
                textAlign: TextAlign.end,
              ),
            ),
            const Divider(height: 1),
          ],
      ],
    ),
  );
}

class _MedicationArchiveRow extends StatelessWidget {
  const _MedicationArchiveRow({
    required this.medication,
    required this.pet,
    required this.schedules,
    required this.strings,
    required this.onOpen,
    this.onEdit,
    this.onStop,
  });

  final Medication medication;
  final Pet? pet;
  final List<MedicationScheduleVersion> schedules;
  final AppStrings strings;
  final VoidCallback onOpen;
  final VoidCallback? onEdit;
  final VoidCallback? onStop;

  @override
  Widget build(BuildContext context) {
    final current = schedules
        .where((schedule) => schedule.id == medication.currentScheduleVersionId)
        .firstOrNull;
    final color = pet == null ? CopawColors.purple : _petColor(pet!);
    return Container(
      key: Key('medication.archive.${medication.id}'),
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withValues(alpha: 0.16)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            type: MaterialType.transparency,
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              onTap: onOpen,
              leading: pet == null
                  ? Icon(Icons.medication_rounded, color: color)
                  : _PetAvatar(pet: pet!),
              title: Text(
                medication.displayName,
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
              subtitle: Text(
                [
                  if (pet case final pet?) pet.name,
                  if (current?.slots.firstOrNull case final slot?)
                    slot.doseText,
                  medication.isActive
                      ? strings.activePlan
                      : strings.stoppedPlan,
                ].join(' · '),
              ),
              trailing: const Icon(Icons.chevron_right_rounded),
            ),
          ),
          if (onEdit != null || onStop != null)
            Row(
              children: [
                if (onEdit != null)
                  Expanded(
                    child: OutlinedButton(
                      onPressed: onEdit,
                      child: Text(strings.editMedication),
                    ),
                  ),
                if (onEdit != null && onStop != null) const SizedBox(width: 8),
                if (onStop != null)
                  Expanded(
                    child: OutlinedButton(
                      onPressed: onStop,
                      child: Text(strings.stopMedication),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

Future<void> _showMedicationDetails(
  BuildContext context,
  Medication medication,
  List<MedicationScheduleVersion> schedules,
  Pet? pet,
  AppStrings strings,
) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  builder: (context) => _MedicationDetailSheet(
    medication: medication,
    schedules: schedules,
    pet: pet,
    strings: strings,
  ),
);

class _MedicationDetailSheet extends StatelessWidget {
  const _MedicationDetailSheet({
    required this.medication,
    required this.schedules,
    required this.pet,
    required this.strings,
  });

  final Medication medication;
  final List<MedicationScheduleVersion> schedules;
  final Pet? pet;
  final AppStrings strings;

  @override
  Widget build(BuildContext context) {
    final orderedSchedules = [...schedules]
      ..sort((left, right) => right.version.compareTo(left.version));
    final color = pet == null ? CopawColors.orange : _petColor(pet!);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              if (pet case final pet?) ...[
                _PetAvatar(pet: pet, size: 48),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      strings.medicationDetails,
                      style: const TextStyle(color: CopawColors.muted),
                    ),
                    Text(
                      medication.displayName,
                      key: const Key('medication.detail.name'),
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w900),
                    ),
                    Text(
                      medication.isActive
                          ? strings.activePlan
                          : strings.stoppedPlan,
                      style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                key: const Key('medication.detail.close'),
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Container(
            key: const Key('medication.detail.photo'),
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: color.withValues(alpha: 0.24)),
            ),
            child: Column(
              children: [
                Icon(Icons.add_a_photo_outlined, color: color, size: 34),
                const SizedBox(height: 8),
                Text(
                  strings.medicationPhoto,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                Text(strings.photoNotAdded),
                Text(
                  strings.photoSyncUnavailable,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: CopawColors.muted,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _MedicationDetailBlock(
            icon: Icons.flag_outlined,
            title: strings.medicationPurpose,
            value: medication.purpose ?? strings.notRecorded,
          ),
          _MedicationDetailBlock(
            icon: Icons.visibility_outlined,
            title: strings.medicationPossibleSideEffects,
            value: medication.possibleSideEffects ?? strings.notRecorded,
          ),
          const SizedBox(height: 8),
          Text(
            strings.scheduleHistory,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
          ),
          for (final schedule in orderedSchedules)
            Container(
              margin: const EdgeInsets.only(top: 10),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: CopawColors.cream,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: CopawColors.lavender),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${strings.effectivePeriod}: '
                    '${schedule.effectiveFromLocalDate}〜'
                    '${schedule.effectiveUntilLocalDate ?? strings.activePlan}',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  Text(
                    schedule.weekdays.map(strings.weekday).join('・'),
                    style: const TextStyle(color: CopawColors.muted),
                  ),
                  for (final slot in schedule.slots)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        [
                          TimeOfDay(
                            hour: slot.hour,
                            minute: slot.minute,
                          ).format(context),
                          slot.doseText,
                          ?slot.instructions,
                        ].join(' · '),
                      ),
                    ),
                ],
              ),
            ),
          const SizedBox(height: 14),
          Text(
            strings.medicationReferenceDisclaimer,
            style: const TextStyle(color: CopawColors.muted, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _MedicationDetailBlock extends StatelessWidget {
  const _MedicationDetailBlock({
    required this.icon,
    required this.title,
    required this.value,
  });

  final IconData icon;
  final String title;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: CopawColors.purple, size: 21),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
              Text(value, style: const TextStyle(color: CopawColors.muted)),
            ],
          ),
        ),
      ],
    ),
  );
}

String _medicationErrorMessage(
  AppStrings strings,
  Object error, {
  required bool fromAction,
}) {
  if (error is! MedicationRepositoryException) {
    return strings.medicationLoadFailure;
  }
  return switch (error.code) {
    MedicationRepositoryErrorCode.terminalConflict =>
      strings.medicationConflict,
    MedicationRepositoryErrorCode.responsibilityConflict =>
      strings.medicationResponsibilityConflict,
    MedicationRepositoryErrorCode.permission =>
      strings.medicationPermissionFailure,
    MedicationRepositoryErrorCode.malformedData =>
      strings.medicationDataFailure,
    _ =>
      fromAction
          ? strings.medicationSaveFailure
          : strings.medicationLoadFailure,
  };
}

class _MedicationDoseCard extends StatelessWidget {
  const _MedicationDoseCard({
    required this.occurrence,
    required this.pet,
    required this.serverConfirmed,
    required this.busy,
    required this.strings,
    required this.timeZoneIdentifier,
    required this.onClaim,
    required this.onAdminister,
    required this.onSkip,
    required this.onDetails,
  });

  final PlannedMedicationOccurrence occurrence;
  final Pet? pet;
  final bool serverConfirmed;
  final bool busy;
  final AppStrings strings;
  final String? timeZoneIdentifier;
  final VoidCallback onClaim;
  final VoidCallback onAdminister;
  final VoidCallback onSkip;
  final VoidCallback onDetails;

  @override
  Widget build(BuildContext context) {
    final persisted = occurrence.persisted;
    final terminal =
        occurrence.outcomeStatus != MedicationOutcomeStatus.unresolved;
    final isDue = !DateTime.now().isBefore(occurrence.dueAt);
    final due = TimeOfDay.fromDateTime(
      _toHouseholdLocal(occurrence.dueAt, timeZoneIdentifier),
    );
    final medicationColor = pet == null ? CopawColors.orange : _petColor(pet!);
    final medicationIdentity = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          occurrence.medicationNameSnapshot,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        Text(
          occurrence.petNameSnapshot,
          style: const TextStyle(color: CopawColors.muted, fontSize: 12),
        ),
      ],
    );
    final dueLabel = Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        due.format(context),
        style: const TextStyle(fontWeight: FontWeight.w800),
      ),
    );
    final medicationIcon = Container(
      width: 42,
      height: 42,
      margin: const EdgeInsets.only(right: 10),
      decoration: BoxDecoration(
        color: medicationColor,
        borderRadius: BorderRadius.circular(14),
      ),
      child: const Icon(
        Icons.medication_rounded,
        color: Colors.white,
        size: 22,
      ),
    );
    final outcomeLabel = switch (occurrence.outcomeStatus) {
      MedicationOutcomeStatus.administered => strings.administered,
      MedicationOutcomeStatus.skipped => strings.skipped,
      MedicationOutcomeStatus.unresolved =>
        DateTime.now().isAfter(occurrence.dueAt)
            ? strings.overdueMedication
            : strings.unresolvedMedication,
    };
    final semanticLabel = [
      occurrence.medicationNameSnapshot,
      occurrence.petNameSnapshot,
      due.format(context),
      occurrence.doseText,
      ?occurrence.instructions,
      outcomeLabel,
    ].join('. ');
    final largeText = MediaQuery.textScalerOf(context).scale(1) >= 2;
    return Semantics(
      key: Key('medication.semantic.${occurrence.id}'),
      container: true,
      explicitChildNodes: true,
      label: semanticLabel,
      child: Container(
        key: Key('medication.dose.${occurrence.id}'),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              medicationColor.withValues(alpha: 0.12),
              medicationColor.withValues(alpha: 0.045),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: medicationColor.withValues(alpha: 0.18)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (largeText) ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ExcludeSemantics(
                    key: Key('medication.decorativeIcon.${occurrence.id}'),
                    child: medicationIcon,
                  ),
                  Expanded(child: medicationIdentity),
                ],
              ),
              const SizedBox(height: 8),
              Align(alignment: Alignment.centerLeft, child: dueLabel),
            ] else
              Row(
                children: [
                  ExcludeSemantics(
                    key: Key('medication.decorativeIcon.${occurrence.id}'),
                    child: medicationIcon,
                  ),
                  Expanded(child: medicationIdentity),
                  dueLabel,
                ],
              ),
            const SizedBox(height: 10),
            Text(
              occurrence.doseText,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            if (occurrence.instructions case final instructions?)
              Text(
                instructions,
                style: const TextStyle(color: CopawColors.muted),
              ),
            const SizedBox(height: 8),
            Text(
              outcomeLabel,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color:
                    occurrence.outcomeStatus ==
                        MedicationOutcomeStatus.administered
                    ? Colors.green.shade700
                    : occurrence.outcomeStatus ==
                          MedicationOutcomeStatus.skipped
                    ? Colors.orange.shade800
                    : CopawColors.purpleDark,
              ),
            ),
            if (persisted?.outcomeByNameSnapshot case final actor?)
              Text(
                [
                  strings.medicationRecordedBy(actor),
                  if (persisted?.outcomeAt case final outcomeAt?)
                    _formatHouseholdDateTime(
                      context,
                      outcomeAt,
                      timeZoneIdentifier,
                    ),
                ].join(' · '),
                style: const TextStyle(color: CopawColors.muted),
              ),
            if (persisted?.skippedReasonCode case final reason?)
              Text(
                _MedicationSkipDialogState._skipLabel(strings, reason),
                style: const TextStyle(color: CopawColors.muted),
              ),
            if (persisted?.skippedReasonNote case final note?)
              Text(note, style: const TextStyle(color: CopawColors.muted)),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              key: Key('medication.details.${occurrence.id}'),
              onPressed: onDetails,
              icon: const Icon(Icons.description_outlined, size: 18),
              label: Text(strings.openMedicationDetails),
            ),
            if (!terminal) ...[
              const SizedBox(height: 10),
              if (occurrence.responsibilityStatus ==
                  MedicationResponsibilityStatus.unclaimed)
                OutlinedButton(
                  onPressed: serverConfirmed && !busy ? onClaim : null,
                  child: Text(strings.claimMedication),
                )
              else if (persisted?.responsibleByNameSnapshot case final name?)
                Text('${strings.responsible}: $name'),
              FilledButton(
                key: Key('medication.administer.${occurrence.id}'),
                onPressed: serverConfirmed && isDue && !busy
                    ? onAdminister
                    : null,
                child: busy
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(strings.recordAdministered),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                key: Key('medication.skip.${occurrence.id}'),
                onPressed: serverConfirmed && isDue && !busy ? onSkip : null,
                child: Text(strings.recordSkipped),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

final class _MedicationSkipInput {
  const _MedicationSkipInput(this.code, this.note);

  final MedicationSkipReasonCode code;
  final String? note;
}

class _MedicationSkipDialog extends StatefulWidget {
  const _MedicationSkipDialog();

  @override
  State<_MedicationSkipDialog> createState() => _MedicationSkipDialogState();
}

class _MedicationSkipDialogState extends State<_MedicationSkipDialog> {
  MedicationSkipReasonCode code = MedicationSkipReasonCode.petRefused;
  final note = TextEditingController();

  @override
  void dispose() {
    note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings(
      ProviderScope.containerOf(
            context,
          ).read(appControllerProvider).value?.locale ??
          AppLocale.english,
    );
    return AlertDialog(
      title: Text(strings.skipReason),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DropdownButtonFormField<MedicationSkipReasonCode>(
            initialValue: code,
            items: [
              for (final value in MedicationSkipReasonCode.values)
                DropdownMenuItem(
                  value: value,
                  child: Text(_skipLabel(strings, value)),
                ),
            ],
            onChanged: (value) => setState(() => code = value!),
          ),
          if (code == MedicationSkipReasonCode.other)
            TextField(
              key: const Key('medication.skipNote'),
              controller: note,
              maxLength: 200,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(labelText: strings.skipReasonNote),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(strings.cancel),
        ),
        FilledButton(
          onPressed:
              code == MedicationSkipReasonCode.other && note.text.trim().isEmpty
              ? null
              : () => Navigator.pop(
                  context,
                  _MedicationSkipInput(code, note.text.trim()),
                ),
          child: Text(strings.recordSkipped),
        ),
      ],
    );
  }

  static String _skipLabel(
    AppStrings strings,
    MedicationSkipReasonCode value,
  ) => switch (value) {
    MedicationSkipReasonCode.petRefused => strings.skipReasonPetRefused,
    MedicationSkipReasonCode.vomited => strings.skipReasonVomited,
    MedicationSkipReasonCode.unavailable => strings.skipReasonUnavailable,
    MedicationSkipReasonCode.vetInstruction => strings.skipReasonVetInstruction,
    MedicationSkipReasonCode.other => strings.skipReasonOther,
  };
}

class _MedicationPlanSheet extends ConsumerStatefulWidget {
  const _MedicationPlanSheet({
    required this.session,
    required this.pet,
    this.medication,
    this.schedule,
  });

  final HouseholdSession session;
  final Pet pet;
  final Medication? medication;
  final MedicationScheduleVersion? schedule;

  @override
  ConsumerState<_MedicationPlanSheet> createState() =>
      _MedicationPlanSheetState();
}

class _MedicationPlanSheetState extends ConsumerState<_MedicationPlanSheet> {
  late final TextEditingController name;
  late final TextEditingController purpose;
  late final TextEditingController possibleSideEffects;
  late DateTime effectiveDate;
  late Set<int> weekdays;
  late List<_DoseEditor> doses;
  bool saving = false;
  String? error;

  @override
  void initState() {
    super.initState();
    name = TextEditingController(
      text: widget.schedule?.medicationNameSnapshot ?? '',
    );
    purpose = TextEditingController(text: widget.medication?.purpose ?? '');
    possibleSideEffects = TextEditingController(
      text: widget.medication?.possibleSideEffects ?? '',
    );
    final identifier = widget.session.household.timeZoneIdentifier;
    final householdNow = identifier == null
        ? DateTime.now()
        : tz.TZDateTime.now(tz.getLocation(identifier));
    effectiveDate = DateTime(
      householdNow.year,
      householdNow.month,
      householdNow.day,
    ).add(widget.medication == null ? Duration.zero : const Duration(days: 1));
    weekdays = widget.schedule?.weekdays.toSet() ?? {1, 2, 3, 4, 5, 6, 7};
    doses =
        widget.schedule?.slots
            .map(
              (slot) => _DoseEditor(
                time: TimeOfDay(hour: slot.hour, minute: slot.minute),
                dose: slot.doseText,
                instructions: slot.instructions,
              ),
            )
            .toList() ??
        [_DoseEditor(time: const TimeOfDay(hour: 8, minute: 0))];
  }

  @override
  void dispose() {
    name.dispose();
    purpose.dispose();
    possibleSideEffects.dispose();
    for (final dose in doses) {
      dose.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings(
      ref.watch(appControllerProvider).value?.locale ?? AppLocale.english,
    );
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        20,
        20,
        MediaQuery.viewInsetsOf(context).bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.medication == null
                  ? strings.addMedication
                  : strings.editMedication,
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            Text(strings.medicationForPet(widget.pet.name)),
            const SizedBox(height: 16),
            TextField(
              key: const Key('medication.name'),
              controller: name,
              decoration: InputDecoration(labelText: strings.medicationName),
            ),
            const SizedBox(height: 10),
            TextField(
              key: const Key('medication.purpose'),
              controller: purpose,
              maxLength: 500,
              decoration: InputDecoration(labelText: strings.medicationPurpose),
            ),
            TextField(
              key: const Key('medication.sideEffects'),
              controller: possibleSideEffects,
              maxLength: 500,
              decoration: InputDecoration(
                labelText: strings.medicationPossibleSideEffects,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              children: [
                for (var day = 1; day <= 7; day += 1)
                  FilterChip(
                    label: Text(strings.weekday(day)),
                    selected: weekdays.contains(day),
                    onSelected: (selected) => setState(() {
                      if (selected) {
                        weekdays.add(day);
                      } else if (weekdays.length > 1) {
                        weekdays.remove(day);
                      }
                    }),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            for (var index = 0; index < doses.length; index += 1) ...[
              _DoseEditorView(
                editor: doses[index],
                strings: strings,
                onTime: () async {
                  final selected = await showTimePicker(
                    context: context,
                    initialTime: doses[index].time,
                  );
                  if (selected != null) {
                    setState(() => doses[index].time = selected);
                  }
                },
                onRemove: doses.length == 1
                    ? null
                    : () => setState(() => doses.removeAt(index).dispose()),
              ),
              const SizedBox(height: 10),
            ],
            TextButton.icon(
              onPressed: doses.length >= 8
                  ? null
                  : () => setState(
                      () => doses.add(
                        _DoseEditor(time: const TimeOfDay(hour: 20, minute: 0)),
                      ),
                    ),
              icon: const Icon(Icons.add),
              label: Text(strings.addDoseTime),
            ),
            if (error != null)
              Text(
                error!,
                key: const Key('medication.saveError'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            FilledButton(
              key: const Key('medication.save'),
              onPressed: saving ? null : _save,
              child: saving
                  ? const CircularProgressIndicator()
                  : Text(strings.saveMedication),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    final strings = AppStrings(
      ref.read(appControllerProvider).value?.locale ?? AppLocale.english,
    );
    setState(() {
      saving = true;
      error = null;
    });
    final date =
        '${effectiveDate.year.toString().padLeft(4, '0')}-'
        '${effectiveDate.month.toString().padLeft(2, '0')}-'
        '${effectiveDate.day.toString().padLeft(2, '0')}';
    final slots = doses
        .map(
          (dose) => MedicationPlanSlotInput(
            hour: dose.time.hour,
            minute: dose.time.minute,
            doseText: dose.dose.text,
            instructions: dose.instructions.text,
          ),
        )
        .toList();
    try {
      final repository = ref.read(medicationRepositoryProvider);
      if (widget.medication case final medication?) {
        await repository.replacePlan(
          householdId: widget.session.household.id,
          medication: medication,
          medicationName: name.text,
          purpose: purpose.text,
          possibleSideEffects: possibleSideEffects.text,
          effectiveFromLocalDate: date,
          weekdays: weekdays.toList(),
          slots: slots,
        );
      } else {
        await repository.createPlan(
          householdId: widget.session.household.id,
          petId: widget.pet.id,
          medicationName: name.text,
          purpose: purpose.text,
          possibleSideEffects: possibleSideEffects.text,
          effectiveFromLocalDate: date,
          weekdays: weekdays.toList(),
          slots: slots,
        );
      }
      if (mounted) Navigator.pop(context);
    } on Object {
      if (mounted) setState(() => error = strings.medicationSaveFailure);
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }
}

final class _DoseEditor {
  _DoseEditor({required this.time, String dose = '', String? instructions})
    : dose = TextEditingController(text: dose),
      instructions = TextEditingController(text: instructions ?? '');

  TimeOfDay time;
  final TextEditingController dose;
  final TextEditingController instructions;

  void dispose() {
    dose.dispose();
    instructions.dispose();
  }
}

class _DoseEditorView extends StatelessWidget {
  const _DoseEditorView({
    required this.editor,
    required this.strings,
    required this.onTime,
    required this.onRemove,
  });

  final _DoseEditor editor;
  final AppStrings strings;
  final VoidCallback onTime;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextButton(onPressed: onTime, child: Text(editor.time.format(context))),
        Expanded(
          child: Column(
            children: [
              TextField(
                controller: editor.dose,
                decoration: InputDecoration(labelText: strings.dose),
              ),
              TextField(
                controller: editor.instructions,
                decoration: InputDecoration(labelText: strings.instructions),
              ),
            ],
          ),
        ),
        IconButton(onPressed: onRemove, icon: const Icon(Icons.remove_circle)),
      ],
    );
  }
}

class _TaskRow extends ConsumerStatefulWidget {
  const _TaskRow({
    required this.task,
    required this.session,
    required this.readOnly,
    required this.persisted,
    required this.members,
    required this.pet,
    required this.pendingTransfer,
    required this.responsibilityCurrent,
  });

  final CareTask task;
  final HouseholdSession session;
  final bool readOnly;
  final bool persisted;
  final List<Caregiver> members;
  final Pet? pet;
  final ResponsibilityTransfer? pendingTransfer;
  final bool responsibilityCurrent;

  @override
  ConsumerState<_TaskRow> createState() => _TaskRowState();
}

class _TaskRowState extends ConsumerState<_TaskRow> {
  bool acting = false;
  String? error;
  String? retrySignature;
  String? retryMutationId;

  @override
  Widget build(BuildContext context) {
    final task = widget.task;
    final strings = AppStrings(
      ref.watch(appControllerProvider).value?.locale ?? AppLocale.english,
    );
    final categoryColor = _careCategoryColor(task.category);
    final cardColor = widget.pet == null
        ? categoryColor
        : _petColor(widget.pet!);
    final dueLabel = _formatHouseholdDateTime(
      context,
      task.dueTime,
      widget.session.household.timeZoneIdentifier,
    );
    final semanticLabel = [
      task.title,
      task.petNameSnapshot ?? widget.pet?.name ?? strings.unknownPet,
      strings.taskStatus(task.status),
      strings.taskKind(task.kind),
      strings.careCategory(task.category),
      strings.carePriority(task.priority),
      dueLabel,
      if (task.status == CareTaskStatus.claimed &&
          task.assigneeNameSnapshot != null)
        '${strings.responsible}: ${task.assigneeNameSnapshot}',
      if (task.status == CareTaskStatus.completed)
        strings.completedByAt(
          task.completedBy ??
              task.assigneeNameSnapshot ??
              strings.unknownCaregiver,
          task.completedAt == null
              ? strings.timeUnavailable
              : _formatHouseholdDateTime(
                  context,
                  task.completedAt!,
                  widget.session.household.timeZoneIdentifier,
                ),
        ),
    ].join('. ');
    return Semantics(
      key: Key('care.semantic.${task.id}'),
      container: true,
      explicitChildNodes: true,
      label: semanticLabel,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: cardColor.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: cardColor.withValues(alpha: 0.18)),
        ),
        child: ListTile(
          contentPadding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
          leading: ExcludeSemantics(
            key: Key('care.decorativeIcon.${task.id}'),
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: cardColor,
                borderRadius: BorderRadius.circular(15),
              ),
              child: Icon(
                task.priority == CarePriority.urgent
                    ? Icons.priority_high_rounded
                    : _careCategoryIcon(task.category),
                color: Colors.white,
                size: 23,
              ),
            ),
          ),
          title: ExcludeSemantics(
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    task.title,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                if (widget.pet case final pet?)
                  _PetIdentityPill(pet: pet)
                else
                  Text(
                    task.petNameSnapshot ?? strings.unknownPet,
                    style: const TextStyle(
                      color: CopawColors.purpleDark,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
              ],
            ),
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 4),
              ExcludeSemantics(
                child: Text(
                  [
                    strings.taskStatus(task.status),
                    strings.taskKind(task.kind),
                    strings.careCategory(task.category),
                    strings.carePriority(task.priority),
                  ].join(' · '),
                  style: const TextStyle(
                    color: CopawColors.muted,
                    height: 1.35,
                  ),
                ),
              ),
              const SizedBox(height: 2),
              ExcludeSemantics(
                child: Row(
                  children: [
                    const Icon(
                      Icons.schedule_rounded,
                      size: 14,
                      color: CopawColors.muted,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        dueLabel,
                        style: const TextStyle(
                          color: CopawColors.muted,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (task.status == CareTaskStatus.claimed &&
                  task.assigneeNameSnapshot != null) ...[
                const SizedBox(height: 8),
                ExcludeSemantics(
                  child: _CareStateBadge(
                    icon: Icons.person_rounded,
                    label:
                        '${strings.responsible}: ${task.assigneeNameSnapshot}',
                    color: CopawColors.purple,
                  ),
                ),
              ],
              if (widget.pendingTransfer case final transfer?) ...[
                const SizedBox(height: 8),
                ExcludeSemantics(
                  child: _CareStateBadge(
                    icon: Icons.swap_horiz_rounded,
                    label: strings.responsibilityTransferSummary(
                      transfer.responsibilityFromNameSnapshot,
                      transfer.responsibilityToNameSnapshot,
                    ),
                    color: CopawColors.orange,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  strings.responsibilityConsentPending(
                    transfer.consentByNameSnapshot,
                  ),
                  key: Key('responsibility.pending.${task.id}'),
                  style: const TextStyle(
                    color: CopawColors.purpleDark,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
              if (task.status == CareTaskStatus.completed) ...[
                const SizedBox(height: 8),
                ExcludeSemantics(
                  child: _CareStateBadge(
                    icon: Icons.check_circle_rounded,
                    label: strings.completedByAt(
                      task.completedBy ??
                          task.assigneeNameSnapshot ??
                          strings.unknownCaregiver,
                      task.completedAt == null
                          ? strings.timeUnavailable
                          : _formatHouseholdDateTime(
                              context,
                              task.completedAt!,
                              widget.session.household.timeZoneIdentifier,
                            ),
                    ),
                    color: CopawColors.green,
                  ),
                ),
              ],
              if (error != null)
                Text(
                  error!,
                  key: Key('care.actionError.${task.id}'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              if (_actions(strings).isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 8, children: _actions(strings)),
              ],
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _actions(AppStrings strings) {
    if (widget.readOnly) return const [];
    final task = widget.task;
    final actorId = widget.session.caregiver.id;
    if (task.status == CareTaskStatus.completed) return const [];
    if (task.status == CareTaskStatus.claimed) {
      if (!widget.responsibilityCurrent) return const [];
      final transfer = widget.pendingTransfer;
      if (transfer != null) {
        if (transfer.requestedById == actorId) {
          return [
            _responsibilityButton(
              key: 'cancelTransfer',
              label: strings.cancelResponsibilityTransfer,
              signature:
                  'cancel:${transfer.id}:${task.revision}:${transfer.revision}',
              action: (mutationId) => ref
                  .read(taskResponsibilityRepositoryProvider)
                  .resolveTransfer(
                    householdId: widget.session.household.id,
                    taskId: task.id,
                    action: 'cancelTransfer',
                    transferId: transfer.id,
                    expectedTaskRevision: task.revision,
                    expectedTransferRevision: transfer.revision,
                    clientMutationId: mutationId,
                  ),
            ),
          ];
        }
        if (transfer.consentById == actorId) {
          return [
            _responsibilityButton(
              key: 'acceptTransfer',
              label: strings.acceptResponsibilityTransfer,
              signature:
                  'accept:${transfer.id}:${task.revision}:${transfer.revision}',
              action: (mutationId) => ref
                  .read(taskResponsibilityRepositoryProvider)
                  .resolveTransfer(
                    householdId: widget.session.household.id,
                    taskId: task.id,
                    action: 'acceptTransfer',
                    transferId: transfer.id,
                    expectedTaskRevision: task.revision,
                    expectedTransferRevision: transfer.revision,
                    clientMutationId: mutationId,
                  ),
            ),
            _responsibilityButton(
              key: 'declineTransfer',
              label: strings.declineResponsibilityTransfer,
              signature:
                  'decline:${transfer.id}:${task.revision}:${transfer.revision}',
              action: (mutationId) => ref
                  .read(taskResponsibilityRepositoryProvider)
                  .resolveTransfer(
                    householdId: widget.session.household.id,
                    taskId: task.id,
                    action: 'declineTransfer',
                    transferId: transfer.id,
                    expectedTaskRevision: task.revision,
                    expectedTransferRevision: transfer.revision,
                    clientMutationId: mutationId,
                  ),
            ),
          ];
        }
        return const [];
      }
      if (task.assigneeId != actorId) {
        return [
          _responsibilityButton(
            key: 'requestTakeover',
            label: strings.requestResponsibilityTakeover,
            signature: 'takeover:${task.id}:${task.revision}',
            action: (mutationId) => ref
                .read(taskResponsibilityRepositoryProvider)
                .requestTakeover(
                  householdId: widget.session.household.id,
                  taskId: task.id,
                  expectedTaskRevision: task.revision,
                  clientMutationId: mutationId,
                ),
          ),
        ];
      }
      final otherMembers = widget.members
          .where((member) => member.id != actorId)
          .toList(growable: false);
      return [
        _responsibilityButton(
          key: 'complete',
          label: strings.completeTask,
          signature: 'complete:${task.id}:${task.revision}',
          action: (mutationId) => ref
              .read(taskResponsibilityRepositoryProvider)
              .complete(
                householdId: widget.session.household.id,
                taskId: task.id,
                expectedTaskRevision: task.revision,
                clientMutationId: mutationId,
              ),
        ),
        _responsibilityButton(
          key: 'release',
          label: strings.releaseResponsibility,
          signature: 'release:${task.id}:${task.revision}',
          action: (mutationId) => ref
              .read(taskResponsibilityRepositoryProvider)
              .release(
                householdId: widget.session.household.id,
                taskId: task.id,
                expectedTaskRevision: task.revision,
                clientMutationId: mutationId,
              ),
        ),
        if (otherMembers.isNotEmpty)
          PopupMenuButton<String>(
            key: Key('care.requestReassign.${task.id}'),
            enabled: !acting,
            onSelected: (recipientId) {
              final signature =
                  'reassign:${task.id}:${task.revision}:$recipientId';
              _act(
                () => ref
                    .read(taskResponsibilityRepositoryProvider)
                    .requestReassign(
                      householdId: widget.session.household.id,
                      taskId: task.id,
                      targetMemberId: recipientId,
                      expectedTaskRevision: task.revision,
                      clientMutationId: _stableMutationId(signature),
                    ),
              );
            },
            itemBuilder: (context) => otherMembers
                .map(
                  (member) => PopupMenuItem<String>(
                    value: member.id,
                    child: Text(member.displayName),
                  ),
                )
                .toList(growable: false),
            child: _TaskActionSurface(
              icon: Icons.swap_horiz_rounded,
              label: strings.requestResponsibilityReassign,
            ),
          ),
      ];
    }

    final request = task.assignmentRequest;
    if (request == null) {
      final otherMembers = widget.members
          .where((member) => member.id != actorId)
          .toList(growable: false);
      return [
        _actionButton(
          key: 'claim',
          label: strings.claimTask,
          action: () => ref
              .read(careTaskMutationRepositoryProvider)
              .claim(
                householdId: widget.session.household.id,
                taskId: task.id,
                actorId: actorId,
                taskIfMissing: widget.persisted ? null : task,
              ),
        ),
        _actionButton(
          key: 'requestOpen',
          label: strings.requestOpenTask,
          action: () => ref
              .read(careTaskMutationRepositoryProvider)
              .requestOpen(
                householdId: widget.session.household.id,
                taskId: task.id,
                actorId: actorId,
                taskIfMissing: widget.persisted ? null : task,
              ),
        ),
        if (otherMembers.isNotEmpty)
          PopupMenuButton<String>(
            key: Key('care.requestDirect.${task.id}'),
            enabled: !acting,
            onSelected: (recipientId) => _act(
              () => ref
                  .read(careTaskMutationRepositoryProvider)
                  .requestDirect(
                    householdId: widget.session.household.id,
                    taskId: task.id,
                    actorId: actorId,
                    recipientId: recipientId,
                    taskIfMissing: widget.persisted ? null : task,
                  ),
            ),
            itemBuilder: (context) => otherMembers
                .map(
                  (member) => PopupMenuItem<String>(
                    value: member.id,
                    child: Text(member.displayName),
                  ),
                )
                .toList(growable: false),
            child: _TaskActionSurface(
              icon: Icons.person_add_alt_1_rounded,
              label: strings.requestDirectTask,
            ),
          ),
      ];
    }
    if (request.requestedById == actorId) {
      return [
        _actionButton(
          key: 'claim',
          label: strings.claimTask,
          action: () => ref
              .read(careTaskMutationRepositoryProvider)
              .claim(
                householdId: widget.session.household.id,
                taskId: task.id,
                actorId: actorId,
              ),
        ),
        _actionButton(
          key: 'cancel',
          label: strings.cancelRequest,
          action: () => ref
              .read(careTaskMutationRepositoryProvider)
              .cancel(
                householdId: widget.session.household.id,
                taskId: task.id,
                actorId: actorId,
                requestId: request.id,
              ),
        ),
      ];
    }
    if (request.mode == AssignmentMode.direct &&
        request.requestedToId == actorId) {
      return [
        _actionButton(
          key: 'accept',
          label: strings.acceptTask,
          action: () => ref
              .read(careTaskMutationRepositoryProvider)
              .accept(
                householdId: widget.session.household.id,
                taskId: task.id,
                actorId: actorId,
                requestId: request.id,
              ),
        ),
        _actionButton(
          key: 'decline',
          label: strings.declineTask,
          action: () => ref
              .read(careTaskMutationRepositoryProvider)
              .decline(
                householdId: widget.session.household.id,
                taskId: task.id,
                actorId: actorId,
                requestId: request.id,
              ),
        ),
      ];
    }
    if (request.mode == AssignmentMode.open) {
      return [
        _actionButton(
          key: 'claim',
          label: strings.claimTask,
          action: () => ref
              .read(careTaskMutationRepositoryProvider)
              .claim(
                householdId: widget.session.household.id,
                taskId: task.id,
                actorId: actorId,
              ),
        ),
      ];
    }
    return const [];
  }

  Widget _actionButton({
    required String key,
    required String label,
    required Future<Object?> Function() action,
  }) {
    return OutlinedButton.icon(
      key: Key('care.$key.${widget.task.id}'),
      onPressed: acting ? null : () => _act(action),
      icon: Icon(
        key == 'complete'
            ? Icons.check_rounded
            : key == 'claim' || key == 'accept'
            ? Icons.person_rounded
            : Icons.group_rounded,
        size: 17,
      ),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 40),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
      ),
    );
  }

  Widget _responsibilityButton({
    required String key,
    required String label,
    required String signature,
    required Future<Object?> Function(String mutationId) action,
  }) => _actionButton(
    key: key,
    label: label,
    action: () => action(_stableMutationId(signature)),
  );

  String _stableMutationId(String signature) {
    if (retrySignature == signature && retryMutationId != null) {
      return retryMutationId!;
    }
    retrySignature = signature;
    retryMutationId =
        'flutter-${DateTime.now().microsecondsSinceEpoch.toRadixString(16)}-'
        '${widget.task.id.hashCode.abs().toRadixString(16)}';
    return retryMutationId!;
  }

  Future<void> _act(Future<Object?> Function() action) async {
    final strings = AppStrings(
      ref.read(appControllerProvider).value?.locale ?? AppLocale.english,
    );
    setState(() {
      acting = true;
      error = null;
    });
    var succeeded = false;
    try {
      await action();
      succeeded = true;
    } on CareTaskMutationException catch (exception) {
      if (mounted) setState(() => error = _mutationMessage(strings, exception));
    } on TaskResponsibilityException catch (exception) {
      if (mounted) {
        setState(() => error = _responsibilityMessage(strings, exception));
      }
    } on Object {
      if (mounted) setState(() => error = strings.taskActionFailure);
    } finally {
      if (mounted) {
        setState(() {
          acting = false;
          if (succeeded) {
            retrySignature = null;
            retryMutationId = null;
          }
        });
      }
    }
  }

  String _mutationMessage(
    AppStrings strings,
    CareTaskMutationException exception,
  ) {
    return switch (exception.code) {
      CareTaskMutationErrorCode.network => strings.careLoadFailure,
      CareTaskMutationErrorCode.permission => strings.taskPermissionFailure,
      CareTaskMutationErrorCode.staleRequest ||
      CareTaskMutationErrorCode.invalidTransition ||
      CareTaskMutationErrorCode.terminal ||
      CareTaskMutationErrorCode.notFound => strings.taskStaleFailure,
      CareTaskMutationErrorCode.legacyUnsafe => strings.careDataNeedsRepair,
      _ => strings.taskActionFailure,
    };
  }

  String _responsibilityMessage(
    AppStrings strings,
    TaskResponsibilityException exception,
  ) => switch (exception.code) {
    TaskResponsibilityErrorCode.network => strings.responsibilityNetworkFailure,
    TaskResponsibilityErrorCode.permission =>
      strings.responsibilityPermissionFailure,
    TaskResponsibilityErrorCode.stale ||
    TaskResponsibilityErrorCode.notFound ||
    TaskResponsibilityErrorCode.blocked => strings.responsibilityStaleFailure,
    TaskResponsibilityErrorCode.unsafeLegacy ||
    TaskResponsibilityErrorCode.malformedData => strings.careDataNeedsRepair,
    _ => strings.responsibilityFailure,
  };
}

class _CareStateBadge extends StatelessWidget {
  const _CareStateBadge({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    ),
  );
}

class _TaskActionSurface extends StatelessWidget {
  const _TaskActionSurface({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minHeight: 40),
    padding: const EdgeInsets.symmetric(horizontal: 13),
    decoration: BoxDecoration(
      border: Border.all(color: Theme.of(context).colorScheme.outline),
      borderRadius: BorderRadius.circular(13),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 17),
        const SizedBox(width: 8),
        Text(label),
        const SizedBox(width: 2),
        const Icon(Icons.arrow_drop_down_rounded, size: 18),
      ],
    ),
  );
}

Color _careCategoryColor(CareCategory category) => switch (category) {
  CareCategory.feeding => CopawColors.orange,
  CareCategory.walking => CopawColors.purple,
  CareCategory.medication => CopawColors.rose,
  CareCategory.grooming => CopawColors.blue,
  CareCategory.other => CopawColors.green,
};

IconData _careCategoryIcon(CareCategory category) => switch (category) {
  CareCategory.feeding => Icons.restaurant_rounded,
  CareCategory.walking => Icons.directions_walk_rounded,
  CareCategory.medication => Icons.medication_rounded,
  CareCategory.grooming => Icons.content_cut_rounded,
  CareCategory.other => Icons.checklist_rounded,
};

class _AddTaskSheet extends ConsumerStatefulWidget {
  const _AddTaskSheet({
    required this.session,
    required this.pet,
    required this.initialDate,
  });

  final HouseholdSession session;
  final Pet pet;
  final DateTime initialDate;

  @override
  ConsumerState<_AddTaskSheet> createState() => _AddTaskSheetState();
}

class _AddTaskSheetState extends ConsumerState<_AddTaskSheet> {
  final titleController = TextEditingController();
  CareCategory category = CareCategory.other;
  bool urgent = false;
  bool recurring = false;
  bool dailyRoutine = true;
  final selectedWeekdays = <int>{1, 2, 3, 4, 5, 6, 7};
  late DateTime selectedDate;
  late TimeOfDay selectedTime;
  bool saving = false;
  String? error;

  @override
  void initState() {
    super.initState();
    selectedDate = DateUtils.dateOnly(widget.initialDate);
    final householdNow = _toHouseholdLocal(
      DateTime.now(),
      widget.session.household.timeZoneIdentifier,
    );
    selectedTime = TimeOfDay.fromDateTime(householdNow);
  }

  @override
  void dispose() {
    titleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final locale =
        ref.watch(appControllerProvider).value?.locale ?? AppLocale.english;
    final strings = AppStrings(locale);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        20,
        20,
        MediaQuery.viewInsetsOf(context).bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              strings.addTask,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 4),
            Text(
              strings.forPet(widget.pet.name),
              key: const Key('care.selectedPet'),
              style: const TextStyle(color: CopawColors.muted),
            ),
            const SizedBox(height: 16),
            TextField(
              key: const Key('care.taskTitle'),
              controller: titleController,
              maxLength: 120,
              decoration: InputDecoration(labelText: strings.taskTitle),
            ),
            DropdownButtonFormField<CareCategory>(
              key: const Key('care.category'),
              initialValue: category,
              decoration: InputDecoration(labelText: strings.category),
              items: CareCategory.values
                  .map(
                    (value) => DropdownMenuItem(
                      value: value,
                      child: Text(strings.careCategory(value)),
                    ),
                  )
                  .toList(growable: false),
              onChanged: saving
                  ? null
                  : (value) {
                      if (value != null) setState(() => category = value);
                    },
            ),
            const SizedBox(height: 12),
            SegmentedButton<bool>(
              segments: [
                ButtonSegment(value: false, label: Text(strings.oneTime)),
                ButtonSegment(value: true, label: Text(strings.recurring)),
              ],
              selected: {recurring},
              onSelectionChanged: saving
                  ? null
                  : (value) => setState(() => recurring = value.single),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              key: const Key('care.taskDate'),
              onPressed: saving ? null : _pickDate,
              icon: const Icon(Icons.calendar_today),
              label: Text(
                '${recurring ? strings.routineStartDate : strings.scheduledDate} · '
                '${MaterialLocalizations.of(context).formatMediumDate(selectedDate)}',
              ),
            ),
            if (recurring) ...[
              const SizedBox(height: 10),
              SegmentedButton<bool>(
                segments: [
                  ButtonSegment(value: true, label: Text(strings.daily)),
                  ButtonSegment(
                    value: false,
                    label: Text(strings.selectedDays),
                  ),
                ],
                selected: {dailyRoutine},
                onSelectionChanged: saving
                    ? null
                    : (value) => setState(() => dailyRoutine = value.single),
              ),
              const SizedBox(height: 6),
              Text(
                strings.routineFrequency(
                  dailyRoutine
                      ? CareRoutineFrequency.daily
                      : CareRoutineFrequency.selectedDays,
                ),
                key: const Key('care.frequencyLabel'),
                style: const TextStyle(color: CopawColors.muted),
              ),
              if (!dailyRoutine) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: List.generate(7, (index) {
                    final appleWeekday = index + 1;
                    return FilterChip(
                      key: Key('care.weekday.$appleWeekday'),
                      label: Text(strings.weekday(appleWeekday)),
                      selected: selectedWeekdays.contains(appleWeekday),
                      onSelected: saving
                          ? null
                          : (selected) => setState(() {
                              if (selected) {
                                selectedWeekdays.add(appleWeekday);
                              } else {
                                selectedWeekdays.remove(appleWeekday);
                              }
                            }),
                    );
                  }),
                ),
              ],
            ],
            OutlinedButton.icon(
              key: Key(recurring ? 'care.routineTime' : 'care.taskTime'),
              onPressed: saving ? null : _pickTime,
              icon: const Icon(Icons.schedule),
              label: Text(
                '${strings.scheduledTime} · ${selectedTime.format(context)}',
              ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: urgent,
              onChanged: saving
                  ? null
                  : (value) => setState(() => urgent = value),
              title: Text(strings.urgent),
            ),
            if (error != null)
              Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            const SizedBox(height: 10),
            FilledButton(
              key: const Key('care.saveTask'),
              onPressed: saving ? null : () => _save(strings),
              child: Text(saving ? strings.savingTask : strings.saveTask),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickDate() async {
    final result = await showDatePicker(
      context: context,
      initialDate: selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035, 12, 31),
    );
    if (result != null && mounted) {
      setState(() => selectedDate = DateUtils.dateOnly(result));
    }
  }

  Future<void> _pickTime() async {
    final result = await showTimePicker(
      context: context,
      initialTime: selectedTime,
    );
    if (result != null && mounted) setState(() => selectedTime = result);
  }

  Future<void> _save(AppStrings strings) async {
    setState(() {
      saving = true;
      error = null;
    });
    try {
      final repository = ref.read(careTaskRepositoryProvider);
      if (repository is! PetBoundCareTaskWriter) {
        throw StateError('pet-bound writer unavailable');
      }
      final writer = repository as PetBoundCareTaskWriter;
      final timeZone = widget.session.household.timeZoneIdentifier;
      if (timeZone == null) throw StateError('timezone repair required');
      if (recurring) {
        await writer.createRoutineForPet(
          householdId: widget.session.household.id,
          petId: widget.pet.id,
          petName: widget.pet.name,
          title: titleController.text,
          category: category,
          priority: urgent ? CarePriority.urgent : CarePriority.normal,
          frequency: dailyRoutine
              ? CareRoutineFrequency.daily
              : CareRoutineFrequency.selectedDays,
          weekdays: selectedWeekdays.toList()..sort(),
          hour: selectedTime.hour,
          minute: selectedTime.minute,
          startDate: _householdInstant(
            selectedDate,
            const TimeOfDay(hour: 0, minute: 0),
            timeZone,
          ),
          timeZoneIdentifier: timeZone,
          createdById: widget.session.caregiver.id,
          createdByName: widget.session.caregiver.displayName,
        );
      } else {
        await writer.createOneOffTaskForPet(
          householdId: widget.session.household.id,
          petId: widget.pet.id,
          petName: widget.pet.name,
          title: titleController.text,
          category: category,
          dueTime: _householdInstant(selectedDate, selectedTime, timeZone),
          priority: urgent ? CarePriority.urgent : CarePriority.normal,
          createdById: widget.session.caregiver.id,
          createdByName: widget.session.caregiver.displayName,
        );
      }
      if (mounted) Navigator.of(context).pop();
    } on Object {
      if (mounted) setState(() => error = strings.taskSaveFailure);
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }
}

class _CalendarCard extends StatelessWidget {
  const _CalendarCard({
    required this.selectedDate,
    required this.onDateChanged,
    required this.routines,
    required this.persistedTasks,
    required this.strings,
    required this.timeZoneIdentifier,
    required this.petName,
    required this.pets,
  });

  final DateTime selectedDate;
  final ValueChanged<DateTime> onDateChanged;
  final List<CareRoutine> routines;
  final List<CareTask> persistedTasks;
  final AppStrings strings;
  final String? timeZoneIdentifier;
  final String? petName;
  final List<Pet> pets;

  @override
  Widget build(BuildContext context) {
    final localSelected = _toHouseholdLocal(selectedDate, timeZoneIdentifier);
    final month = DateTime(localSelected.year, localSelected.month);
    final firstGridDay = month.subtract(
      Duration(days: month.weekday - DateTime.monday),
    );
    final service = RoutineOccurrenceService();
    final tasksByDay = <DateTime, List<CareTask>>{};
    for (var offset = 0; offset < 42; offset += 1) {
      final date = DateUtils.dateOnly(firstGridDay.add(Duration(days: offset)));
      final instant = _householdCalendarInstant(date, timeZoneIdentifier);
      final tasks = timeZoneIdentifier == null
          ? const <CareTask>[]
          : service.tryTasksForDay(
                  selectedInstant: instant,
                  householdTimeZoneIdentifier: timeZoneIdentifier!,
                  routines: routines,
                  persistedTasks: persistedTasks,
                ) ??
                const <CareTask>[];
      tasksByDay[date] = tasks.toList()
        ..sort((left, right) => left.dueTime.compareTo(right.dueTime));
    }
    final selectedKey = DateUtils.dateOnly(localSelected);
    final tasks = tasksByDay[selectedKey] ?? const <CareTask>[];
    return CopawCard(
      key: const Key('calendar.card'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              IconButton(
                key: const Key('calendar.previousMonth'),
                onPressed: () => onDateChanged(
                  _householdCalendarInstant(
                    DateTime(month.year, month.month - 1, 1),
                    timeZoneIdentifier,
                  ),
                ),
                icon: const Icon(Icons.chevron_left_rounded),
              ),
              Expanded(
                child: Text(
                  MaterialLocalizations.of(context).formatMonthYear(month),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              IconButton(
                key: const Key('calendar.nextMonth'),
                onPressed: () => onDateChanged(
                  _householdCalendarInstant(
                    DateTime(month.year, month.month + 1, 1),
                    timeZoneIdentifier,
                  ),
                ),
                icon: const Icon(Icons.chevron_right_rounded),
              ),
            ],
          ),
          const SizedBox(height: 6),
          GridView.count(
            key: const Key('calendar.picker'),
            crossAxisCount: 7,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            childAspectRatio: 0.92,
            children: [
              for (final weekday in strings.calendarWeekdayHeaders.indexed)
                Center(
                  key: Key('calendar.weekday.${weekday.$1}'),
                  child: MediaQuery.withClampedTextScaling(
                    maxScaleFactor: 1,
                    child: Text(
                      weekday.$2,
                      style: const TextStyle(
                        color: CopawColors.purpleDark,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              for (var offset = 0; offset < 42; offset += 1)
                _CalendarDay(
                  date: DateUtils.dateOnly(
                    firstGridDay.add(Duration(days: offset)),
                  ),
                  inMonth:
                      firstGridDay.add(Duration(days: offset)).month ==
                      month.month,
                  selected: DateUtils.isSameDay(
                    firstGridDay.add(Duration(days: offset)),
                    selectedKey,
                  ),
                  categories:
                      tasksByDay[DateUtils.dateOnly(
                            firstGridDay.add(Duration(days: offset)),
                          )]
                          ?.map((task) => task.category)
                          .toSet() ??
                      const {},
                  onTap: () => onDateChanged(
                    _householdCalendarInstant(
                      firstGridDay.add(Duration(days: offset)),
                      timeZoneIdentifier,
                    ),
                  ),
                ),
            ],
          ),
          const Divider(height: 28),
          Text(
            MaterialLocalizations.of(context).formatFullDate(selectedKey),
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          if (tasks.isEmpty)
            Text(strings.noCareToday, key: const Key('calendar.empty'))
          else
            for (final task in tasks)
              _CalendarAgendaRow(
                task: task,
                pet: pets.where((pet) => pet.id == task.petId).firstOrNull,
                petName: petName,
                strings: strings,
                timeZoneIdentifier: timeZoneIdentifier,
              ),
        ],
      ),
    );
  }
}

DateTime _householdCalendarInstant(DateTime date, String? timeZoneIdentifier) {
  if (timeZoneIdentifier == null) {
    return DateTime(date.year, date.month, date.day, 12);
  }
  try {
    final location = tz.getLocation(timeZoneIdentifier);
    return tz.TZDateTime(location, date.year, date.month, date.day, 12).toUtc();
  } on Object {
    return DateTime(date.year, date.month, date.day, 12);
  }
}

class _CalendarDay extends StatelessWidget {
  const _CalendarDay({
    required this.date,
    required this.inMonth,
    required this.selected,
    required this.categories,
    required this.onTap,
  });

  final DateTime date;
  final bool inMonth;
  final bool selected;
  final Set<CareCategory> categories;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    key: Key(
      'calendar.day.${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}',
    ),
    onTap: onTap,
    borderRadius: BorderRadius.circular(14),
    child: Container(
      margin: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: selected ? CopawColors.purple : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
      ),
      child: MediaQuery.withClampedTextScaling(
        maxScaleFactor: 1,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '${date.day}',
              style: TextStyle(
                color: selected
                    ? Colors.white
                    : inMonth
                    ? CopawColors.ink
                    : CopawColors.muted.withValues(alpha: 0.45),
                fontWeight: selected ? FontWeight.w900 : FontWeight.w600,
              ),
            ),
            const SizedBox(height: 3),
            SizedBox(
              key: categories.isEmpty
                  ? null
                  : Key(
                      'calendar.marker.${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}',
                    ),
              height: 5,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final category in categories.take(3))
                    Container(
                      width: 4,
                      height: 4,
                      margin: const EdgeInsets.symmetric(horizontal: 1),
                      decoration: BoxDecoration(
                        color: selected
                            ? Colors.white
                            : _careCategoryColor(category),
                        shape: BoxShape.circle,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _CalendarAgendaRow extends StatelessWidget {
  const _CalendarAgendaRow({
    required this.task,
    required this.pet,
    required this.petName,
    required this.strings,
    required this.timeZoneIdentifier,
  });

  final CareTask task;
  final Pet? pet;
  final String? petName;
  final AppStrings strings;
  final String? timeZoneIdentifier;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: _careCategoryColor(task.category).withValues(alpha: 0.09),
      borderRadius: BorderRadius.circular(15),
    ),
    child: Row(
      children: [
        if (pet case final pet?)
          _PetAvatar(pet: pet, size: 34)
        else
          Icon(
            _careCategoryIcon(task.category),
            color: _careCategoryColor(task.category),
          ),
        const SizedBox(width: 10),
        SizedBox(
          width: 54,
          child: Text(
            TimeOfDay.fromDateTime(
              _toHouseholdLocal(task.dueTime, timeZoneIdentifier),
            ).format(context),
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                task.title,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              Text(
                '${task.petNameSnapshot ?? petName ?? strings.unknownPet} · ${strings.taskKind(task.kind)} · ${strings.careCategory(task.category)} · ${strings.carePriority(task.priority)} · ${strings.taskStatus(task.status)}',
                style: const TextStyle(color: CopawColors.muted, fontSize: 11),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _UpdatesCard extends StatelessWidget {
  const _UpdatesCard({
    required this.snapshot,
    required this.olderEvents,
    required this.errorMessage,
    required this.pageErrorMessage,
    required this.readErrorMessage,
    required this.readStatePending,
    required this.loadingOlder,
    required this.hasMore,
    required this.olderDroppedEventCount,
    required this.olderIsFromCache,
    required this.olderPotentiallyIncomplete,
    required this.strings,
    required this.timeZoneIdentifier,
    required this.onRetry,
    required this.onRetryRead,
    required this.onLoadOlder,
  });

  final CollaborationEventSnapshot? snapshot;
  final List<CollaborationEvent> olderEvents;
  final String? errorMessage;
  final String? pageErrorMessage;
  final String? readErrorMessage;
  final bool readStatePending;
  final bool loadingOlder;
  final bool hasMore;
  final int olderDroppedEventCount;
  final bool olderIsFromCache;
  final bool olderPotentiallyIncomplete;
  final AppStrings strings;
  final String? timeZoneIdentifier;
  final VoidCallback onRetry;
  final VoidCallback onRetryRead;
  final VoidCallback onLoadOlder;

  @override
  Widget build(BuildContext context) {
    final byId = <String, CollaborationEvent>{
      for (final event in snapshot?.events ?? const <CollaborationEvent>[])
        event.id: event,
      for (final event in olderEvents) event.id: event,
    };
    final events = byId.values.toList(growable: false)
      ..sort((left, right) {
        final byTime = right.occurredAt.compareTo(left.occurredAt);
        return byTime != 0 ? byTime : right.id.compareTo(left.id);
      });
    final droppedEventCount =
        (snapshot?.droppedEventCount ?? 0) + olderDroppedEventCount;
    final isFromCache = snapshot?.isFromCache == true || olderIsFromCache;
    final isPotentiallyIncomplete =
        snapshot?.isPotentiallyIncomplete == true || olderPotentiallyIncomplete;
    return CopawCard(
      key: const Key('updates.collaboration'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.groups_outlined, color: CopawColors.purpleDark),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  strings.updates,
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            strings.updatesScope,
            style: const TextStyle(color: CopawColors.purpleDark, height: 1.35),
          ),
          if (isPotentiallyIncomplete) ...[
            const SizedBox(height: 12),
            _WarningBanner(
              key: const Key('updates.incomplete'),
              message: strings.updatesIncomplete,
            ),
          ],
          if (isFromCache) ...[
            const SizedBox(height: 12),
            _WarningBanner(
              key: const Key('updates.cache'),
              message: strings.updatesCached,
            ),
          ],
          if (droppedEventCount > 0) ...[
            const SizedBox(height: 12),
            _WarningBanner(
              key: const Key('updates.malformed'),
              message: strings.updatesMalformed(droppedEventCount),
            ),
          ],
          if (readErrorMessage != null) ...[
            const SizedBox(height: 12),
            _RetryWarningBanner(
              key: const Key('updates.readError'),
              message: readErrorMessage!,
              retryLabel: strings.retry,
              onRetry: onRetryRead,
              retryKey: const Key('updates.readRetry'),
            ),
          ],
          if (readStatePending) ...[
            const SizedBox(height: 12),
            _WarningBanner(
              key: const Key('updates.readPending'),
              message: strings.updatesReadStatePending,
            ),
          ],
          const SizedBox(height: 14),
          if (errorMessage != null) ...[
            _RetryWarningBanner(
              key: const Key('updates.error'),
              message: errorMessage!,
              retryLabel: strings.retry,
              onRetry: onRetry,
            ),
            if (events.isNotEmpty) const SizedBox(height: 10),
          ],
          if (events.isNotEmpty)
            for (final event in events)
              _CollaborationEventRow(
                event: event,
                strings: strings,
                timeZoneIdentifier: timeZoneIdentifier,
              )
          else if (errorMessage == null && snapshot == null)
            const Center(child: CircularProgressIndicator())
          else if (errorMessage == null && droppedEventCount == 0)
            Text(
              strings.updatesNotAvailable,
              key: const Key('updates.empty'),
              style: const TextStyle(fontWeight: FontWeight.w800),
            )
          else if (errorMessage == null)
            const SizedBox.shrink(),
          if (pageErrorMessage != null) ...[
            const SizedBox(height: 10),
            _RetryWarningBanner(
              key: const Key('updates.pageError'),
              message: pageErrorMessage!,
              retryLabel: strings.retry,
              onRetry: onLoadOlder,
            ),
          ] else if (hasMore) ...[
            const SizedBox(height: 10),
            OutlinedButton.icon(
              key: const Key('updates.loadOlder'),
              onPressed: loadingOlder ? null : onLoadOlder,
              icon: loadingOlder
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.expand_more_rounded),
              label: Text(strings.loadOlderUpdates),
            ),
          ],
        ],
      ),
    );
  }
}

class _CollaborationEventRow extends StatelessWidget {
  const _CollaborationEventRow({
    required this.event,
    required this.strings,
    required this.timeZoneIdentifier,
  });

  final CollaborationEvent event;
  final AppStrings strings;
  final String? timeZoneIdentifier;

  @override
  Widget build(BuildContext context) {
    final action = strings.collaborationAction(event.action);
    final detail = strings.collaborationEventDetail(
      actor: event.actorNameSnapshot,
      pet: event.petNameSnapshot,
      target: event.targetMemberNameSnapshot,
      responsibilityFrom: event.responsibilityFromNameSnapshot,
      responsibilityTo: event.responsibilityToNameSnapshot,
      handoffCreator: event.handoffCreatorNameSnapshot,
      handoffRecipient: event.handoffRecipientNameSnapshot,
    );
    final subject = event.isHandoff
        ? strings.handoffCoverageSession
        : event.taskTitleSnapshot ?? strings.updatesDataFailure;
    final occurredAt = _formatHouseholdDateTime(
      context,
      event.occurredAt,
      timeZoneIdentifier,
    );
    return Semantics(
      label: '$action. $subject. $detail. $occurredAt',
      child: ExcludeSemantics(
        child: Container(
          key: Key('updates.event.${event.id}'),
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: CopawColors.lavender.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                _collaborationEventIcon(event.action),
                color: CopawColors.purpleDark,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      action,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subject,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      detail,
                      style: const TextStyle(
                        color: CopawColors.purpleDark,
                        height: 1.35,
                      ),
                    ),
                    Text(
                      occurredAt,
                      style: const TextStyle(
                        color: CopawColors.purpleDark,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

IconData _collaborationEventIcon(CollaborationEventAction action) =>
    switch (action) {
      CollaborationEventAction.taskCreated => Icons.add_task_rounded,
      CollaborationEventAction.taskRequested => Icons.person_add_alt_rounded,
      CollaborationEventAction.taskClaimed ||
      CollaborationEventAction.taskAccepted ||
      CollaborationEventAction.taskTakenOver => Icons.person_rounded,
      CollaborationEventAction.taskDeclined ||
      CollaborationEventAction.taskCancelled => Icons.close_rounded,
      CollaborationEventAction.taskCompleted => Icons.check_circle_rounded,
      CollaborationEventAction.taskReleased ||
      CollaborationEventAction.taskReassignRequested ||
      CollaborationEventAction.taskTakeoverRequested ||
      CollaborationEventAction.taskReassigned => Icons.swap_horiz_rounded,
      CollaborationEventAction.taskTransferDeclined ||
      CollaborationEventAction.taskTransferCancelled => Icons.close_rounded,
      CollaborationEventAction.taskTransferSuperseded => Icons.task_alt_rounded,
      CollaborationEventAction.handoffOffered => Icons.forward_to_inbox_rounded,
      CollaborationEventAction.handoffAccepted => Icons.handshake_outlined,
      CollaborationEventAction.handoffDeclined ||
      CollaborationEventAction.handoffCancelled => Icons.cancel_outlined,
      CollaborationEventAction.handoffClosed => Icons.inventory_2_outlined,
    };

class _RecordsEntryCard extends StatelessWidget {
  const _RecordsEntryCard({
    required this.entryKey,
    required this.icon,
    required this.title,
    required this.help,
    required this.onTap,
  });

  final Key entryKey;
  final IconData icon;
  final String title;
  final String help;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    key: entryKey,
    button: true,
    label: title,
    hint: help,
    child: ExcludeSemantics(
      child: CopawCard(
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Icon(icon, color: CopawColors.purpleDark),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: CopawColors.ink,
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        help,
                        style: const TextStyle(
                          color: CopawColors.purpleDark,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: CopawColors.purpleDark,
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _RecordsBackButton extends StatelessWidget {
  const _RecordsBackButton({required this.strings, required this.onPressed});

  final AppStrings strings;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerLeft,
    child: TextButton.icon(
      key: const Key('records.back'),
      onPressed: onPressed,
      icon: const Icon(Icons.arrow_back_rounded),
      label: Text(strings.backToRecords),
    ),
  );
}

class _ActivityCard extends StatelessWidget {
  const _ActivityCard({
    required this.tasks,
    required this.medications,
    required this.strings,
    required this.timeZoneIdentifier,
    required this.petName,
    required this.healthRecords,
  });

  final List<CareTask> tasks;
  final List<MedicationOccurrence> medications;
  final AppStrings strings;
  final String? timeZoneIdentifier;
  final String? petName;
  final List<HealthRecord> healthRecords;

  @override
  Widget build(BuildContext context) {
    final events = <_ActivityEvent>[
      for (final task in tasks)
        if (task.status == CareTaskStatus.completed)
          _ActivityEvent(
            id: 'care.${task.id}',
            recordedAt: task.completedAt ?? task.dueTime,
            icon: Icons.check_rounded,
            color: CopawColors.green,
            title: task.title,
            detail: [
              strings.taskKind(task.kind),
              task.petNameSnapshot ?? petName ?? strings.unknownPet,
              strings.careCategory(task.category),
              strings.carePriority(task.priority),
              strings.completedByAt(
                task.completedBy ??
                    task.assigneeNameSnapshot ??
                    strings.unknownCaregiver,
                task.completedAt == null
                    ? strings.timeUnavailable
                    : _formatHouseholdDateTime(
                        context,
                        task.completedAt!,
                        timeZoneIdentifier,
                      ),
              ),
            ].join(' · '),
          )
        else if (task.status == CareTaskStatus.claimed)
          _ActivityEvent(
            id: 'care.${task.id}',
            recordedAt: task.claimedAt ?? task.dueTime,
            icon: Icons.person_rounded,
            color: CopawColors.purple,
            title: task.title,
            detail: [
              task.petNameSnapshot ?? petName ?? strings.unknownPet,
              '${strings.responsible}: ${task.assigneeNameSnapshot ?? strings.unknownCaregiver}',
              _formatHouseholdDateTime(
                context,
                task.claimedAt ?? task.dueTime,
                timeZoneIdentifier,
              ),
            ].join(' · '),
          ),
      for (final medication in medications)
        _ActivityEvent(
          id: 'medication.${medication.id}',
          recordedAt: medication.outcomeAt ?? medication.dueAt,
          icon: medication.outcomeStatus == MedicationOutcomeStatus.administered
              ? Icons.medication_rounded
              : Icons.not_interested_rounded,
          color:
              medication.outcomeStatus == MedicationOutcomeStatus.administered
              ? CopawColors.green
              : CopawColors.orangeStrong,
          title: medication.medicationNameSnapshot,
          detail: [
            medication.doseText,
            medication.petNameSnapshot,
            medication.outcomeStatus == MedicationOutcomeStatus.administered
                ? strings.administered
                : strings.skipped,
            strings.medicationRecordedBy(
              medication.outcomeByNameSnapshot ?? strings.unknownCaregiver,
            ),
            medication.outcomeAt == null
                ? strings.timeUnavailable
                : _formatHouseholdDateTime(
                    context,
                    medication.outcomeAt!,
                    timeZoneIdentifier,
                  ),
            if (medication.skippedReasonCode case final reason?)
              _MedicationSkipDialogState._skipLabel(strings, reason),
            ?medication.skippedReasonNote,
          ].join(' · '),
        ),
      for (final record in healthRecords)
        _ActivityEvent(
          id: 'health.${record.id}',
          recordedAt: record.recordedAt,
          icon: Icons.monitor_heart_rounded,
          color: CopawColors.roseStrong,
          title: _healthTypeLabel(strings, record.type),
          detail: [
            record.petNameSnapshot,
            strings.healthRecordedBy(record.createdByNameSnapshot),
            _formatHouseholdDateTime(
              context,
              record.recordedAt,
              timeZoneIdentifier,
            ),
            ?record.detail,
            if (record.weightKilograms case final value?)
              '${value.toStringAsFixed(1)} kg',
            if (record.waterMilliliters case final value?)
              '${value.toStringAsFixed(0)} ml',
            if (record.waterMilliliters != null)
              strings.waterMeasurementLabel(record.waterMeasurementBasis),
          ].join(' · '),
        ),
    ]..sort((left, right) => right.recordedAt.compareTo(left.recordedAt));
    return CopawCard(
      key: const Key('activity.card'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            strings.activityTimeline,
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 12),
          if (events.isEmpty)
            Text(strings.noActivity, key: const Key('activity.empty'))
          else
            for (var index = 0; index < events.length; index += 1)
              _ActivityTimelineRow(
                event: events[index],
                last: index == events.length - 1,
              ),
        ],
      ),
    );
  }
}

class _ActivityEvent {
  const _ActivityEvent({
    required this.id,
    required this.recordedAt,
    required this.icon,
    required this.color,
    required this.title,
    required this.detail,
  });

  final String id;
  final DateTime recordedAt;
  final IconData icon;
  final Color color;
  final String title;
  final String detail;
}

class _ActivityTimelineRow extends StatelessWidget {
  const _ActivityTimelineRow({required this.event, required this.last});

  final _ActivityEvent event;
  final bool last;

  @override
  Widget build(BuildContext context) => Row(
    key: event.id.startsWith('medication.')
        ? Key('activity.${event.id}')
        : null,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SizedBox(
        width: 38,
        child: Column(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: event.color.withValues(alpha: 0.14),
                shape: BoxShape.circle,
              ),
              child: Icon(event.icon, color: event.color, size: 18),
            ),
            if (!last)
              Container(width: 2, height: 46, color: CopawColors.lavender),
          ],
        ),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 15),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                event.title,
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 3),
              Text(
                event.detail,
                style: const TextStyle(
                  color: CopawColors.muted,
                  fontSize: 12,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ),
    ],
  );
}

class _ReportCard extends ConsumerStatefulWidget {
  const _ReportCard({
    super.key,
    required this.selectedPet,
    required this.careSnapshot,
    required this.medicationSnapshot,
    required this.healthSnapshot,
    required this.hasSourceError,
    required this.endInstant,
    required this.timeZoneIdentifier,
    required this.strings,
  });

  final Pet? selectedPet;
  final CareTaskSnapshot? careSnapshot;
  final MedicationSnapshot? medicationSnapshot;
  final HealthSnapshot? healthSnapshot;
  final bool hasSourceError;
  final DateTime endInstant;
  final String? timeZoneIdentifier;
  final AppStrings strings;

  @override
  ConsumerState<_ReportCard> createState() => _ReportCardState();
}

class _ReportCardState extends ConsumerState<_ReportCard> {
  int rangeDays = 7;
  DateTime? customStart;
  Set<ReportSection> sections = ReportSection.values.toSet();
  bool sharing = false;
  String? shareError;

  String _sectionLabel(ReportSection section) => switch (section) {
    ReportSection.care => widget.strings.reportSectionCare,
    ReportSection.medication => widget.strings.reportSectionMedication,
    ReportSection.health => widget.strings.reportSectionHealth,
    ReportSection.water => widget.strings.reportSectionWater,
  };

  @override
  Widget build(BuildContext context) {
    final missingSource =
        widget.careSnapshot == null ||
        widget.medicationSnapshot == null ||
        widget.healthSnapshot == null;
    PetCareReport? report;
    if (!widget.hasSourceError &&
        !missingSource &&
        widget.selectedPet != null &&
        widget.timeZoneIdentifier != null) {
      try {
        report = ReportService().build(
          petId: widget.selectedPet!.id,
          petName: widget.selectedPet!.name,
          rangeDays: customStart == null ? rangeDays : null,
          startInstant: customStart,
          sections: sections,
          endInstant: widget.endInstant,
          timeZoneIdentifier: widget.timeZoneIdentifier!,
          routines: widget.careSnapshot!.routines,
          tasks: widget.careSnapshot!.tasks,
          medicationSchedules: widget.medicationSnapshot!.schedules,
          medicationOccurrences: widget.medicationSnapshot!.occurrences,
          healthRecords: widget.healthSnapshot!.records,
        );
      } on ReportBuildException {
        report = null;
      }
    }
    final notCurrent =
        widget.medicationSnapshot?.isServerConfirmed == false ||
        widget.healthSnapshot?.isFromCache == true;
    return CopawCard(
      key: const Key('report.card'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.strings.careReport,
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
          if (widget.selectedPet case final pet?) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: _PetIdentityPill(pet: pet),
            ),
          ],
          const SizedBox(height: 10),
          SegmentedButton<int>(
            key: const Key('report.range'),
            segments: [
              ButtonSegment(value: 7, label: Text(widget.strings.sevenDays)),
              ButtonSegment(value: 30, label: Text(widget.strings.thirtyDays)),
            ],
            selected: {rangeDays},
            onSelectionChanged: (value) => setState(() {
              rangeDays = value.single;
              customStart = null;
            }),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                key: const Key('report.customRange'),
                icon: const Icon(Icons.date_range_rounded, size: 18),
                label: Text(
                  customStart == null
                      ? widget.strings.reportCustomRange
                      : widget.strings.reportCustomRangeDays(
                          report?.rangeDays ?? 0,
                        ),
                ),
                onPressed: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: customStart ??
                        widget.endInstant.subtract(const Duration(days: 6)),
                    firstDate: DateTime(2020),
                    lastDate: widget.endInstant,
                  );
                  if (picked != null) setState(() => customStart = picked);
                },
              ),
              for (final section in ReportSection.values)
                FilterChip(
                  key: Key('report.section.${section.name}'),
                  label: Text(_sectionLabel(section)),
                  selected: sections.contains(section),
                  onSelected: (value) => setState(() {
                    final next = {...sections};
                    if (value) {
                      next.add(section);
                    } else if (next.length > 1) {
                      next.remove(section);
                    }
                    sections = next;
                  }),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            widget.strings.reportNonDiagnostic,
            key: const Key('report.nonDiagnostic'),
            style: const TextStyle(color: CopawColors.purpleDark),
          ),
          const SizedBox(height: 10),
          if (notCurrent) ...[
            _WarningBanner(
              key: const Key('report.notCurrent'),
              message: widget.strings.reportNotCurrent,
            ),
            const SizedBox(height: 10),
          ],
          if (widget.selectedPet == null)
            Text(widget.strings.noActivePetHelp)
          else if (missingSource && !widget.hasSourceError)
            const Center(child: CircularProgressIndicator())
          else if (widget.hasSourceError ||
              widget.timeZoneIdentifier == null ||
              report == null)
            Text(
              widget.strings.reportUnavailable,
              key: const Key('report.error'),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            )
          else ...[
            _ReportContents(report: report, strings: widget.strings),
            const SizedBox(height: 8),
            Builder(
              builder: (buttonContext) => FilledButton.icon(
                key: const Key('report.share'),
                onPressed: notCurrent || sharing
                    ? null
                    : () => _share(buttonContext, report!),
                icon: sharing
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.ios_share_rounded),
                label: Text(
                  sharing
                      ? widget.strings.sharingReport
                      : widget.strings.shareReport,
                ),
              ),
            ),
            if (shareError != null)
              Text(
                shareError!,
                key: const Key('report.shareError'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
        ],
      ),
    );
  }

  Future<void> _share(BuildContext buttonContext, PetCareReport report) async {
    final box = buttonContext.findRenderObject() as RenderBox?;
    if (box == null) {
      return;
    }
    setState(() {
      sharing = true;
      shareError = null;
    });
    try {
      await ref
          .read(reportShareRepositoryProvider)
          .sharePdf(
            report: report,
            locale: widget.strings.locale,
            sharePositionOrigin: box.localToGlobal(Offset.zero) & box.size,
          );
    } on Object {
      if (mounted) {
        setState(() => shareError = widget.strings.shareReportFailure);
      }
    } finally {
      if (mounted) {
        setState(() => sharing = false);
      }
    }
  }
}

class _ReportContents extends StatelessWidget {
  const _ReportContents({required this.report, required this.strings});

  final PetCareReport report;
  final AppStrings strings;

  @override
  Widget build(BuildContext context) {
    final careRate = report.care.planned == 0
        ? 0.0
        : report.care.completed / report.care.planned;
    final medicationRate = report.medication.planned == 0
        ? 0.0
        : report.medication.administered / report.medication.planned;
    final waterRecordCount = report.health.records
        .where((record) => record.waterMilliliters != null)
        .length;
    final careDetails = report.care.completedEvents.reversed
        .map(
          (event) => _ReportDetailItem(
            event.label,
            '${event.actorNameSnapshot} · '
            '${_formatHouseholdDateTime(context, event.recordedAt, report.timeZoneIdentifier)}',
          ),
        )
        .toList(growable: false);
    final medicationDetails = report.medication.terminalEvents.reversed
        .map(
          (event) => _ReportDetailItem(
            event.label,
            '${_reportEventLabel(strings, event.kind)} · '
            '${event.actorNameSnapshot} · '
            '${_formatHouseholdDateTime(context, event.recordedAt, report.timeZoneIdentifier)}',
          ),
        )
        .toList(growable: false);
    final healthDetails = report.health.records.reversed
        .map(
          (record) => _ReportDetailItem(
            _healthTypeLabel(strings, record.type),
            [
              _formatHouseholdDateTime(
                context,
                record.recordedAt,
                report.timeZoneIdentifier,
              ),
              if (record.weightKilograms case final value?)
                '${value.toStringAsFixed(1)} kg',
              if (record.waterMilliliters case final value?)
                '${value.toStringAsFixed(0)} ml',
              if (record.waterMilliliters != null)
                strings.waterMeasurementLabel(record.waterMeasurementBasis),
              if (record.dailyCheckIn != null)
                _dailyHealthSummary(strings, record),
              ?record.detail,
            ].join(' · '),
          ),
        )
        .toList(growable: false);
    return Column(
      key: const Key('report.contents'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          strings.reportRange(
            _formatHouseholdDate(
              context,
              report.startAt,
              report.timeZoneIdentifier,
            ),
            _formatHouseholdDate(
              context,
              report.endAt,
              report.timeZoneIdentifier,
            ),
          ),
          style: const TextStyle(color: CopawColors.purpleDark),
        ),
        const SizedBox(height: 12),
        if (MediaQuery.textScalerOf(context).scale(1) >= 2)
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _ReportMetric(
                key: const Key('report.careRate'),
                label: strings.careCompletionRate,
                value: careRate,
                color: CopawColors.purple,
                icon: Icons.task_alt_rounded,
              ),
              const SizedBox(height: 10),
              _ReportMetric(
                key: const Key('report.medicationRate'),
                label: strings.medicationAdherenceRate,
                value: medicationRate,
                color: CopawColors.orangeStrong,
                icon: Icons.medication_rounded,
              ),
            ],
          )
        else
          Row(
            children: [
              Expanded(
                child: _ReportMetric(
                  key: const Key('report.careRate'),
                  label: strings.careCompletionRate,
                  value: careRate,
                  color: CopawColors.purple,
                  icon: Icons.task_alt_rounded,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _ReportMetric(
                  key: const Key('report.medicationRate'),
                  label: strings.medicationAdherenceRate,
                  value: medicationRate,
                  color: CopawColors.orangeStrong,
                  icon: Icons.medication_rounded,
                ),
              ),
            ],
          ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: CopawColors.blue.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.local_hospital_rounded, color: CopawColors.blue),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  strings.vetReadySummary,
                  style: const TextStyle(fontSize: 12, height: 1.4),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _ReportSection(
          title: strings.careSummary,
          values: {
            strings.planned: report.care.planned,
            strings.completed: report.care.completed,
            strings.unresolved: report.care.unresolved,
          },
        ),
        _ReportSection(
          title: strings.medicationSummary,
          values: {
            strings.planned: report.medication.planned,
            strings.administered: report.medication.administered,
            strings.skipped: report.medication.skipped,
            strings.unresolved: report.medication.unresolved,
            strings.late: report.medication.late,
          },
        ),
        _ReportSection(
          title: strings.healthSummary,
          values: {strings.healthRecords: report.health.total},
        ),
        const SizedBox(height: 8),
        Text(
          strings.doctorReadableDetails,
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        Text(
          strings.capturedDataOnly,
          style: const TextStyle(color: CopawColors.purpleDark, fontSize: 12),
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(11),
          decoration: BoxDecoration(
            color: CopawColors.blue.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            key: const Key('report.waterRecords'),
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                waterRecordCount > 0
                    ? strings.recordedWaterEntries(waterRecordCount)
                    : strings.noWaterRecorded,
              ),
              for (final day in report.health.waterDays)
                Text(strings.waterDaySummary(day)),
              if (report.health.excludedWaterRecordCount > 0)
                Text(
                  strings.excludedWaterRecords(
                    report.health.excludedWaterRecordCount,
                  ),
                ),
            ],
          ),
        ),
        _ReportDetailSection(
          title: strings.exactCareHistory,
          icon: Icons.task_alt_outlined,
          items: careDetails,
          empty: strings.notRecorded,
        ),
        _ReportDetailSection(
          title: strings.exactMedicationHistory,
          icon: Icons.medication_outlined,
          items: medicationDetails,
          empty: strings.notRecorded,
        ),
        _ReportDetailSection(
          title: strings.exactHealthHistory,
          icon: Icons.medical_information_outlined,
          items: healthDetails,
          empty: strings.notRecorded,
        ),
      ],
    );
  }

  static String _reportEventLabel(AppStrings strings, ReportEventKind kind) =>
      switch (kind) {
        ReportEventKind.careCompleted => strings.completed,
        ReportEventKind.medicationAdministered => strings.administered,
        ReportEventKind.medicationSkipped => strings.skipped,
      };
}

final class _ReportDetailItem {
  const _ReportDetailItem(this.title, this.detail);

  final String title;
  final String detail;
}

class _ReportDetailSection extends StatelessWidget {
  const _ReportDetailSection({
    required this.title,
    required this.icon,
    required this.items,
    required this.empty,
  });

  final String title;
  final IconData icon;
  final List<_ReportDetailItem> items;
  final String empty;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 19, color: CopawColors.purple),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ],
        ),
        if (items.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 5),
            child: Text(
              empty,
              style: const TextStyle(color: CopawColors.purpleDark),
            ),
          )
        else
          for (final item in items)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(item.title),
              subtitle: Text(item.detail),
            ),
      ],
    ),
  );
}

class _ReportMetric extends StatelessWidget {
  const _ReportMetric({
    super.key,
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
  });

  final String label;
  final double value;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final clamped = value.clamp(0.0, 1.0);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 21),
          const SizedBox(height: 10),
          Text(
            '${(clamped * 100).round()}%',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w900,
            ),
          ),
          Text(
            label,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: clamped,
            minHeight: 5,
            color: color,
            backgroundColor: Colors.white.withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(8),
          ),
        ],
      ),
    );
  }
}

class _ReportSection extends StatelessWidget {
  const _ReportSection({required this.title, required this.values});

  final String title;
  final Map<String, int> values;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final entry in values.entries)
              Chip(label: Text('${entry.key}: ${entry.value}')),
          ],
        ),
      ],
    ),
  );
}

class _PetManagementCard extends ConsumerStatefulWidget {
  const _PetManagementCard({
    required this.householdId,
    required this.pets,
    required this.loading,
  });

  final String householdId;
  final List<Pet> pets;
  final bool loading;

  @override
  ConsumerState<_PetManagementCard> createState() => _PetManagementCardState();
}

class _PetManagementCardState extends ConsumerState<_PetManagementCard> {
  String? actingPetId;
  String? error;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings(
      ref.watch(appControllerProvider).value?.locale ?? AppLocale.english,
    );
    return CopawCard(
      key: const Key('pets.manage'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            strings.pets,
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          if (widget.loading)
            const Center(child: CircularProgressIndicator())
          else if (widget.pets.isEmpty)
            Text(strings.noPets)
          else
            for (final pet in widget.pets)
              ListTile(
                key: Key('pets.row.${pet.id}'),
                contentPadding: EdgeInsets.zero,
                leading: pet.isArchived
                    ? const Icon(Icons.archive_outlined)
                    : _PetAvatar(pet: pet),
                title: Text(
                  pet.isArchived ? strings.archivedPetName(pet.name) : pet.name,
                ),
                subtitle: Text(strings.petSpecies(pet.species)),
                trailing: pet.isArchived
                    ? null
                    : PopupMenuButton<String>(
                        key: Key('pets.actions.${pet.id}'),
                        enabled: actingPetId == null,
                        onSelected: (action) {
                          if (action == 'rename') {
                            _showEditor(pet: pet);
                          } else {
                            _archive(pet, strings);
                          }
                        },
                        itemBuilder: (context) => [
                          PopupMenuItem(
                            value: 'rename',
                            child: Text(strings.renamePet),
                          ),
                          PopupMenuItem(
                            value: 'archive',
                            child: Text(strings.archivePet),
                          ),
                        ],
                      ),
              ),
          if (error != null) ...[
            Text(
              error!,
              key: const Key('pets.actionError'),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
            const SizedBox(height: 8),
          ],
          FilledButton.icon(
            key: const Key('pets.add'),
            onPressed: actingPetId == null ? () => _showEditor() : null,
            icon: const Icon(Icons.add),
            label: Text(strings.addPet),
          ),
        ],
      ),
    );
  }

  Future<void> _showEditor({Pet? pet}) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) =>
          _PetEditorSheet(householdId: widget.householdId, pet: pet),
    );
  }

  Future<void> _archive(Pet pet, AppStrings strings) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(strings.archivePet),
        content: Text(strings.archivePetConfirmation(pet.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(strings.cancel),
          ),
          FilledButton(
            key: const Key('pets.confirmArchive'),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(strings.archivePet),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      actingPetId = pet.id;
      error = null;
    });
    try {
      await ref
          .read(petRepositoryProvider)
          .archivePet(householdId: widget.householdId, petId: pet.id);
    } on Object {
      if (mounted) setState(() => error = strings.petSaveFailure);
    } finally {
      if (mounted) setState(() => actingPetId = null);
    }
  }
}

class _PetEditorSheet extends ConsumerStatefulWidget {
  const _PetEditorSheet({required this.householdId, this.pet});

  final String householdId;
  final Pet? pet;

  @override
  ConsumerState<_PetEditorSheet> createState() => _PetEditorSheetState();
}

class _PetEditorSheetState extends ConsumerState<_PetEditorSheet> {
  late final nameController = TextEditingController(text: widget.pet?.name);
  PetSpecies? species;
  bool saving = false;
  String? error;

  @override
  void initState() {
    super.initState();
    species = widget.pet?.species;
  }

  @override
  void dispose() {
    nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings(
      ref.watch(appControllerProvider).value?.locale ?? AppLocale.english,
    );
    final editing = widget.pet != null;
    return SafeArea(
      top: false,
      child: AnimatedPadding(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                editing ? strings.renamePet : strings.addPet,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 14),
              TextField(
                key: const Key('pets.name'),
                controller: nameController,
                maxLength: 60,
                decoration: InputDecoration(labelText: strings.petName),
              ),
              if (!editing)
                DropdownButtonFormField<PetSpecies?>(
                  key: const Key('pets.species'),
                  initialValue: species,
                  decoration: InputDecoration(labelText: strings.species),
                  items: [
                    DropdownMenuItem(
                      value: null,
                      child: Text(strings.unspecified),
                    ),
                    for (final value in PetSpecies.values)
                      DropdownMenuItem(
                        value: value,
                        child: Text(strings.petSpecies(value)),
                      ),
                  ],
                  onChanged: saving
                      ? null
                      : (value) => setState(() => species = value),
                ),
              if (error != null)
                Text(
                  error!,
                  key: const Key('pets.editorError'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              const SizedBox(height: 14),
              FilledButton(
                key: const Key('pets.save'),
                onPressed: saving ? null : () => _save(strings),
                child: Text(saving ? strings.savingTask : strings.saveChanges),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _save(AppStrings strings) async {
    setState(() {
      saving = true;
      error = null;
    });
    try {
      final repository = ref.read(petRepositoryProvider);
      final pet = widget.pet;
      if (pet == null) {
        await repository.createPet(
          householdId: widget.householdId,
          name: nameController.text,
          species: species,
        );
      } else {
        await repository.renamePet(
          householdId: widget.householdId,
          petId: pet.id,
          name: nameController.text,
        );
      }
      if (mounted) Navigator.of(context).pop();
    } on Object {
      if (mounted) setState(() => error = strings.petSaveFailure);
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }
}

class _DailyHealthCheckInDialog extends StatefulWidget {
  const _DailyHealthCheckInDialog({
    required this.pet,
    required this.strings,
    required this.onSave,
  });

  final Pet pet;
  final AppStrings strings;
  final Future<void> Function(
    DailyHealthCheckIn checkIn,
    double? waterMilliliters,
    String? detail,
  )
  onSave;

  @override
  State<_DailyHealthCheckInDialog> createState() =>
      _DailyHealthCheckInDialogState();
}

class _DailyHealthCheckInDialogState extends State<_DailyHealthCheckInDialog> {
  final waterMilliliters = TextEditingController();
  final detail = TextEditingController();
  DailyHealthLevel water = DailyHealthLevel.usual;
  DailyHealthLevel appetite = DailyHealthLevel.usual;
  DailyHealthLevel urination = DailyHealthLevel.usual;
  DailyHealthStatus stool = DailyHealthStatus.usual;
  DailyHealthLevel energy = DailyHealthLevel.usual;
  DailyHealthStatus mood = DailyHealthStatus.usual;
  bool saving = false;
  String? error;

  @override
  void dispose() {
    waterMilliliters.dispose();
    detail.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.strings.dailyHealthCheckIn),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _PetIdentityPill(pet: widget.pet),
          const SizedBox(height: 8),
          Text(
            widget.strings.dailyHealthCheckInHelp,
            style: const TextStyle(color: CopawColors.muted, fontSize: 12),
          ),
          const SizedBox(height: 14),
          _DailyHealthLevelField(
            fieldKey: const Key('health.daily.waterLevel'),
            label: widget.strings.dailyHealthWater,
            value: water,
            strings: widget.strings,
            onChanged: saving ? null : (value) => setState(() => water = value),
          ),
          TextField(
            key: const Key('health.daily.waterMilliliters'),
            controller: waterMilliliters,
            enabled: !saving,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: widget.strings.dailyHealthWaterMeasured,
            ),
          ),
          _DailyHealthLevelField(
            fieldKey: const Key('health.daily.appetite'),
            label: widget.strings.dailyHealthAppetite,
            value: appetite,
            strings: widget.strings,
            onChanged: saving
                ? null
                : (value) => setState(() => appetite = value),
          ),
          _DailyHealthLevelField(
            fieldKey: const Key('health.daily.urination'),
            label: widget.strings.dailyHealthUrination,
            value: urination,
            strings: widget.strings,
            onChanged: saving
                ? null
                : (value) => setState(() => urination = value),
          ),
          _DailyHealthStatusField(
            fieldKey: const Key('health.daily.stool'),
            label: widget.strings.dailyHealthStool,
            value: stool,
            strings: widget.strings,
            onChanged: saving ? null : (value) => setState(() => stool = value),
          ),
          _DailyHealthLevelField(
            fieldKey: const Key('health.daily.energy'),
            label: widget.strings.dailyHealthEnergy,
            value: energy,
            strings: widget.strings,
            onChanged: saving
                ? null
                : (value) => setState(() => energy = value),
          ),
          _DailyHealthStatusField(
            fieldKey: const Key('health.daily.mood'),
            label: widget.strings.dailyHealthMood,
            value: mood,
            strings: widget.strings,
            onChanged: saving ? null : (value) => setState(() => mood = value),
          ),
          TextField(
            key: const Key('health.daily.detail'),
            controller: detail,
            enabled: !saving,
            maxLength: 500,
            decoration: InputDecoration(
              labelText: widget.strings.dailyHealthNotes,
            ),
          ),
          _HealthPhotoAffordance(
            key: const Key('health.daily.photoAffordance'),
            strings: widget.strings,
          ),
          if (error != null)
            Text(
              error!,
              key: const Key('health.daily.error'),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: saving ? null : () => Navigator.pop(context),
        child: Text(widget.strings.cancel),
      ),
      FilledButton(
        key: const Key('health.daily.save'),
        onPressed: saving ? null : _save,
        child: Text(widget.strings.saveDailyHealthCheckIn),
      ),
    ],
  );

  Future<void> _save() async {
    final waterText = waterMilliliters.text.trim();
    final measuredWater = waterText.isEmpty ? null : double.tryParse(waterText);
    if (waterText.isNotEmpty && measuredWater == null) {
      setState(() => error = widget.strings.healthInvalidInput);
      return;
    }
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await widget.onSave(
        DailyHealthCheckIn(
          water: water,
          appetite: appetite,
          urination: urination,
          stool: stool,
          energy: energy,
          mood: mood,
        ),
        measuredWater,
        detail.text.trim().isEmpty ? null : detail.text.trim(),
      );
      if (mounted) Navigator.pop(context);
    } on Object catch (caught) {
      if (mounted) {
        setState(() {
          saving = false;
          error = _healthErrorMessage(widget.strings, caught, fromAction: true);
        });
      }
    }
  }
}

class _DailyHealthLevelField extends StatelessWidget {
  const _DailyHealthLevelField({
    required this.fieldKey,
    required this.label,
    required this.value,
    required this.strings,
    required this.onChanged,
  });

  final Key fieldKey;
  final String label;
  final DailyHealthLevel value;
  final AppStrings strings;
  final ValueChanged<DailyHealthLevel>? onChanged;

  @override
  Widget build(BuildContext context) =>
      DropdownButtonFormField<DailyHealthLevel>(
        key: fieldKey,
        initialValue: value,
        decoration: InputDecoration(labelText: label),
        items: DailyHealthLevel.values
            .map(
              (item) => DropdownMenuItem(
                value: item,
                child: Text(_dailyHealthLevelLabel(strings, item)),
              ),
            )
            .toList(growable: false),
        onChanged: onChanged == null
            ? null
            : (next) {
                if (next != null) onChanged!(next);
              },
      );
}

class _DailyHealthStatusField extends StatelessWidget {
  const _DailyHealthStatusField({
    required this.fieldKey,
    required this.label,
    required this.value,
    required this.strings,
    required this.onChanged,
  });

  final Key fieldKey;
  final String label;
  final DailyHealthStatus value;
  final AppStrings strings;
  final ValueChanged<DailyHealthStatus>? onChanged;

  @override
  Widget build(BuildContext context) =>
      DropdownButtonFormField<DailyHealthStatus>(
        key: fieldKey,
        initialValue: value,
        decoration: InputDecoration(labelText: label),
        items: DailyHealthStatus.values
            .map(
              (item) => DropdownMenuItem(
                value: item,
                child: Text(_dailyHealthStatusLabel(strings, item)),
              ),
            )
            .toList(growable: false),
        onChanged: onChanged == null
            ? null
            : (next) {
                if (next != null) onChanged!(next);
              },
      );
}

class _HealthPhotoAffordance extends StatelessWidget {
  const _HealthPhotoAffordance({super.key, required this.strings});

  final AppStrings strings;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(top: 8),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: CopawColors.blue.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: CopawColors.blue.withValues(alpha: 0.2)),
    ),
    child: Row(
      children: [
        const Icon(Icons.add_a_photo_outlined, color: CopawColors.blue),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                strings.healthPhoto,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              Text(
                strings.healthPhotoAffordance,
                style: const TextStyle(color: CopawColors.muted, fontSize: 12),
              ),
              Text(
                strings.photoSyncUnavailable,
                style: const TextStyle(color: CopawColors.muted, fontSize: 11),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _AddHealthDialog extends StatefulWidget {
  const _AddHealthDialog({required this.strings, required this.onSave});

  final AppStrings strings;
  final Future<void> Function(
    HealthRecordType type,
    String detail,
    double? weightKilograms,
    double? waterMilliliters,
  )
  onSave;

  @override
  State<_AddHealthDialog> createState() => _AddHealthDialogState();
}

class _AddHealthDialogState extends State<_AddHealthDialog> {
  final detail = TextEditingController();
  final weight = TextEditingController();
  final water = TextEditingController();
  HealthRecordType type = HealthRecordType.note;
  bool saving = false;
  String? error;

  @override
  void dispose() {
    detail.dispose();
    weight.dispose();
    water.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.strings.addHealthRecord),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DropdownButtonFormField<HealthRecordType>(
            key: const Key('health.type'),
            initialValue: type,
            items: HealthRecordType.values
                .where((value) => value != HealthRecordType.dailyCheckIn)
                .map(
                  (value) => DropdownMenuItem(
                    value: value,
                    child: Text(_healthTypeLabel(widget.strings, value)),
                  ),
                )
                .toList(growable: false),
            onChanged: saving
                ? null
                : (value) => setState(() => type = value ?? type),
          ),
          const SizedBox(height: 12),
          if (type == HealthRecordType.weight)
            TextField(
              key: const Key('health.weight'),
              controller: weight,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: widget.strings.weightKilograms,
              ),
            ),
          if (type == HealthRecordType.waterIntake)
            TextField(
              key: const Key('health.water'),
              controller: water,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: widget.strings.waterMilliliters,
              ),
            ),
          TextField(
            key: const Key('health.detail'),
            controller: detail,
            maxLength: 500,
            decoration: InputDecoration(
              labelText: switch (type) {
                HealthRecordType.weight || HealthRecordType.waterIntake =>
                  widget.strings.healthNoteOptional,
                HealthRecordType.visit => widget.strings.healthVisitDetail,
                _ => widget.strings.healthDetail,
              },
            ),
          ),
          Container(
            key: const Key('health.photoAffordance'),
            margin: const EdgeInsets.only(top: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: CopawColors.blue.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: CopawColors.blue.withValues(alpha: 0.2),
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.add_a_photo_outlined, color: CopawColors.blue),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.strings.healthPhoto,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      Text(
                        widget.strings.healthPhotoAffordance,
                        style: const TextStyle(
                          color: CopawColors.muted,
                          fontSize: 12,
                        ),
                      ),
                      Text(
                        widget.strings.photoSyncUnavailable,
                        style: const TextStyle(
                          color: CopawColors.muted,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (error != null)
            Text(
              error!,
              key: const Key('health.saveError'),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: saving ? null : () => Navigator.pop(context),
        child: Text(widget.strings.cancel),
      ),
      FilledButton(
        key: const Key('health.save'),
        onPressed: saving ? null : _save,
        child: Text(widget.strings.saveHealthRecord),
      ),
    ],
  );

  Future<void> _save() async {
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await widget.onSave(
        type,
        detail.text,
        type == HealthRecordType.weight ? double.tryParse(weight.text) : null,
        type == HealthRecordType.waterIntake
            ? double.tryParse(water.text)
            : null,
      );
      if (mounted) Navigator.pop(context);
    } on Object catch (caught) {
      if (mounted) {
        setState(() {
          saving = false;
          error = _healthErrorMessage(widget.strings, caught, fromAction: true);
        });
      }
    }
  }
}

class _DailyHealthPetRow extends StatelessWidget {
  const _DailyHealthPetRow({
    required this.pet,
    required this.record,
    required this.strings,
    required this.onStart,
  });

  final Pet pet;
  final HealthRecord? record;
  final AppStrings strings;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) => Container(
    key: Key('health.daily.pet.${pet.id}'),
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.82),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            _PetAvatar(pet: pet),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                record == null
                    ? strings.dailyHealthMissing(pet.name)
                    : strings.dailyHealthCompleted(pet.name),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            if (record != null)
              const Icon(Icons.check_circle_rounded, color: CopawColors.green),
          ],
        ),
        if (record == null) ...[
          const SizedBox(height: 8),
          OutlinedButton(
            key: Key('health.daily.start.${pet.id}'),
            onPressed: onStart,
            child: Text(strings.startDailyHealthCheckIn),
          ),
        ],
      ],
    ),
  );
}

bool _sameLocalDay(
  DateTime first,
  DateTime second,
  String? timeZoneIdentifier,
) {
  final firstLocal = _toHouseholdLocal(first, timeZoneIdentifier);
  final secondLocal = _toHouseholdLocal(second, timeZoneIdentifier);
  return firstLocal.year == secondLocal.year &&
      firstLocal.month == secondLocal.month &&
      firstLocal.day == secondLocal.day;
}

bool _healthRecordIsOnLocalDay(
  HealthRecord record,
  DateTime instant,
  String? timeZoneIdentifier,
) {
  final recordedLocalDate = record.recordedLocalDate;
  if (recordedLocalDate == null) {
    return _sameLocalDay(record.recordedAt, instant, timeZoneIdentifier);
  }
  final local = _toHouseholdLocal(instant, timeZoneIdentifier);
  final currentLocalDate =
      '${local.year.toString().padLeft(4, '0')}-'
      '${local.month.toString().padLeft(2, '0')}-'
      '${local.day.toString().padLeft(2, '0')}';
  return recordedLocalDate == currentLocalDate;
}

class _HealthCard extends StatefulWidget {
  const _HealthCard({
    super.key,
    required this.selectedPet,
    required this.pets,
    required this.records,
    required this.loading,
    required this.error,
    required this.isFromCache,
    required this.droppedRecordCount,
    required this.strings,
    required this.timeZoneIdentifier,
    required this.onRetry,
    required this.onAdd,
    required this.onDailyCheckIn,
  });

  final Pet? selectedPet;
  final List<Pet> pets;
  final List<HealthRecord> records;
  final bool loading;
  final Object? error;
  final bool isFromCache;
  final int droppedRecordCount;
  final AppStrings strings;
  final String? timeZoneIdentifier;
  final VoidCallback onRetry;
  final VoidCallback? onAdd;
  final ValueChanged<Pet> onDailyCheckIn;

  @override
  State<_HealthCard> createState() => _HealthCardState();
}

class _HealthCardState extends State<_HealthCard> {
  HealthRecordType? filter;

  @override
  Widget build(BuildContext context) {
    final weights =
        widget.records
            .where((record) => record.weightKilograms != null)
            .toList(growable: false)
          ..sort((left, right) => right.recordedAt.compareTo(left.recordedAt));
    final records = filter == null
        ? widget.records
        : widget.records.where((record) => record.type == filter).toList();
    final waterRecordCount = widget.records
        .where((record) => record.waterMilliliters != null)
        .length;
    final visitCount = widget.records
        .where((record) => record.type == HealthRecordType.visit)
        .length;
    final now = DateTime.now();
    final pets = widget.selectedPet == null
        ? widget.pets
        : widget.pets
              .where((pet) => pet.id == widget.selectedPet!.id)
              .toList(growable: false);
    return CopawCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.strings.healthTimeline,
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            widget.strings.healthNonDiagnostic,
            style: const TextStyle(color: CopawColors.muted, fontSize: 12),
          ),
          if (widget.droppedRecordCount > 0) ...[
            const SizedBox(height: 10),
            _WarningBanner(
              key: const Key('health.incomplete'),
              message: widget.strings.healthRecordsNeedRepair(
                widget.droppedRecordCount,
              ),
            ),
          ],
          const SizedBox(height: 12),
          Container(
            key: const Key('health.daily.card'),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: CopawColors.green.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: CopawColors.green.withValues(alpha: 0.18),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  widget.strings.dailyHealthCheckIn,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 2),
                Text(
                  widget.strings.dailyHealthCheckInHelp,
                  style: const TextStyle(
                    color: CopawColors.muted,
                    fontSize: 12,
                  ),
                ),
                for (final pet in pets) ...[
                  const SizedBox(height: 10),
                  _DailyHealthPetRow(
                    pet: pet,
                    record: widget.records
                        .where(
                          (record) =>
                              record.petId == pet.id &&
                              record.type == HealthRecordType.dailyCheckIn &&
                              _healthRecordIsOnLocalDay(
                                record,
                                now,
                                widget.timeZoneIdentifier,
                              ),
                        )
                        .firstOrNull,
                    strings: widget.strings,
                    onStart: () => widget.onDailyCheckIn(pet),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              Chip(
                avatar: const Icon(Icons.folder_copy_outlined, size: 17),
                label: Text(
                  '${widget.strings.healthRecords}: ${widget.records.length}',
                ),
              ),
              if (waterRecordCount > 0)
                Chip(
                  avatar: const Icon(Icons.water_drop_outlined, size: 17),
                  label: Text(
                    widget.strings.recordedWaterEntries(waterRecordCount),
                  ),
                ),
              if (visitCount > 0)
                Chip(
                  avatar: const Icon(Icons.local_hospital_outlined, size: 17),
                  label: Text('${widget.strings.healthVisit}: $visitCount'),
                ),
            ],
          ),
          if (widget.isFromCache) ...[
            const SizedBox(height: 8),
            Text(
              widget.strings.healthNotCurrent,
              key: const Key('health.cached'),
              style: const TextStyle(color: Color(0xFF8A5A00)),
            ),
          ],
          const SizedBox(height: 12),
          if (widget.selectedPet != null && weights.isNotEmpty) ...[
            Text(
              widget.strings.healthWeightTrend(
                weights.first.weightKilograms!,
                weights.length < 2
                    ? null
                    : weights.first.weightKilograms! -
                          weights[1].weightKilograms!,
              ),
              key: const Key('health.weightTrend'),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
          ],
          DropdownButtonFormField<HealthRecordType?>(
            key: const Key('health.filter'),
            initialValue: filter,
            items: [
              DropdownMenuItem(
                value: null,
                child: Text(widget.strings.allHealthRecords),
              ),
              ...HealthRecordType.values.map(
                (value) => DropdownMenuItem(
                  value: value,
                  child: Text(_healthTypeLabel(widget.strings, value)),
                ),
              ),
            ],
            onChanged: (value) => setState(() => filter = value),
          ),
          const SizedBox(height: 12),
          if (widget.loading)
            const Center(child: CircularProgressIndicator())
          else if (widget.error != null) ...[
            Text(
              _healthErrorMessage(
                widget.strings,
                widget.error!,
                fromAction: false,
              ),
              key: const Key('health.error'),
            ),
            OutlinedButton(
              key: const Key('health.retry'),
              onPressed: widget.onRetry,
              child: Text(widget.strings.retryHealth),
            ),
          ] else if (records.isEmpty)
            Text(widget.strings.noHealthRecords, key: const Key('health.empty'))
          else
            for (final record in records) ...[
              ListTile(
                key: Key('health.record.${record.id}'),
                contentPadding: EdgeInsets.zero,
                leading: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: CopawColors.roseStrong.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Icon(
                    _healthTypeIcon(record.type),
                    color: CopawColors.roseStrong,
                    size: 21,
                  ),
                ),
                title: Text(_healthTypeLabel(widget.strings, record.type)),
                subtitle: Text(
                  [
                    record.petNameSnapshot,
                    if (record.type == HealthRecordType.dailyCheckIn)
                      _formatHouseholdDateTime(
                        context,
                        record.recordedAt,
                        widget.timeZoneIdentifier,
                      ),
                    if (record.weightKilograms case final value?)
                      '${value.toStringAsFixed(1)} kg',
                    if (record.waterMilliliters case final value?)
                      '${value.toStringAsFixed(0)} ml',
                    if (record.waterMilliliters != null)
                      widget.strings.waterMeasurementLabel(
                        record.waterMeasurementBasis,
                      ),
                    if (record.dailyCheckIn != null)
                      _dailyHealthSummary(widget.strings, record),
                    ?record.detail,
                    widget.strings.healthRecordedBy(
                      record.createdByNameSnapshot,
                    ),
                  ].join(' · '),
                ),
                trailing: record.type == HealthRecordType.dailyCheckIn
                    ? null
                    : Text(
                        _formatHouseholdDateTime(
                          context,
                          record.recordedAt,
                          widget.timeZoneIdentifier,
                        ),
                        textAlign: TextAlign.end,
                      ),
              ),
              const Divider(height: 1),
            ],
          const SizedBox(height: 12),
          FilledButton.icon(
            key: const Key('health.add'),
            onPressed: widget.onAdd,
            icon: const Icon(Icons.add_rounded),
            label: Text(widget.strings.addHealthRecord),
          ),
        ],
      ),
    );
  }
}

String _healthTypeLabel(AppStrings strings, HealthRecordType type) =>
    switch (type) {
      HealthRecordType.dailyCheckIn => strings.dailyHealthCheckIn,
      HealthRecordType.weight => strings.healthWeight,
      HealthRecordType.waterIntake => strings.healthWater,
      HealthRecordType.appetite => strings.healthAppetite,
      HealthRecordType.energy => strings.healthEnergy,
      HealthRecordType.mood => strings.healthMood,
      HealthRecordType.stoolObservation => strings.healthStool,
      HealthRecordType.symptom => strings.healthSymptom,
      HealthRecordType.visit => strings.healthVisit,
      HealthRecordType.vaccine => strings.healthVaccine,
      HealthRecordType.note => strings.healthNote,
    };

IconData _healthTypeIcon(HealthRecordType type) => switch (type) {
  HealthRecordType.dailyCheckIn => Icons.fact_check_outlined,
  HealthRecordType.weight => Icons.monitor_weight_outlined,
  HealthRecordType.waterIntake => Icons.water_drop_outlined,
  HealthRecordType.appetite => Icons.restaurant_outlined,
  HealthRecordType.energy => Icons.bolt_outlined,
  HealthRecordType.mood => Icons.mood_outlined,
  HealthRecordType.stoolObservation => Icons.visibility_outlined,
  HealthRecordType.symptom => Icons.healing_outlined,
  HealthRecordType.visit => Icons.local_hospital_outlined,
  HealthRecordType.vaccine => Icons.vaccines_outlined,
  HealthRecordType.note => Icons.description_outlined,
};

String _dailyHealthLevelLabel(AppStrings strings, DailyHealthLevel value) =>
    switch (value) {
      DailyHealthLevel.lessThanUsual => strings.dailyHealthLess,
      DailyHealthLevel.usual => strings.dailyHealthUsual,
      DailyHealthLevel.moreThanUsual => strings.dailyHealthMore,
      DailyHealthLevel.notObserved => strings.dailyHealthNotObserved,
    };

String _dailyHealthStatusLabel(AppStrings strings, DailyHealthStatus value) =>
    switch (value) {
      DailyHealthStatus.usual => strings.dailyHealthUsual,
      DailyHealthStatus.changed => strings.dailyHealthChanged,
      DailyHealthStatus.notObserved => strings.dailyHealthNotObserved,
    };

String _dailyHealthSummary(AppStrings strings, HealthRecord record) {
  final checkIn = record.dailyCheckIn;
  if (checkIn == null) return '';
  return [
    '${strings.dailyHealthWater}: ${_dailyHealthLevelLabel(strings, checkIn.water)}',
    '${strings.dailyHealthAppetite}: ${_dailyHealthLevelLabel(strings, checkIn.appetite)}',
    '${strings.dailyHealthUrination}: ${_dailyHealthLevelLabel(strings, checkIn.urination)}',
    '${strings.dailyHealthStool}: ${_dailyHealthStatusLabel(strings, checkIn.stool)}',
    '${strings.dailyHealthEnergy}: ${_dailyHealthLevelLabel(strings, checkIn.energy)}',
    '${strings.dailyHealthMood}: ${_dailyHealthStatusLabel(strings, checkIn.mood)}',
  ].join(' · ');
}

String _healthErrorMessage(
  AppStrings strings,
  Object error, {
  required bool fromAction,
}) {
  if (error is! HealthRepositoryException) {
    return fromAction ? strings.healthSaveFailure : strings.healthLoadFailure;
  }
  return switch (error.code) {
    HealthRepositoryErrorCode.invalidInput => strings.healthInvalidInput,
    HealthRepositoryErrorCode.network => strings.healthNetworkFailure,
    HealthRepositoryErrorCode.permission => strings.healthPermissionFailure,
    HealthRepositoryErrorCode.malformedData => strings.healthDataFailure,
    HealthRepositoryErrorCode.conflict => strings.healthConflict,
    HealthRepositoryErrorCode.backendUnavailable =>
      fromAction ? strings.healthSaveFailure : strings.healthLoadFailure,
  };
}

class _HandoffCard extends StatelessWidget {
  const _HandoffCard({
    required this.snapshot,
    required this.error,
    required this.strings,
    required this.timeZoneIdentifier,
    required this.onRetry,
    required this.onEdit,
  });

  final HandoffSnapshot? snapshot;
  final Object? error;
  final AppStrings strings;
  final String? timeZoneIdentifier;
  final VoidCallback onRetry;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final handoff = snapshot?.handoff;
    return CopawCard(
      key: const Key('handoff.card'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            strings.householdHandoff,
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
          Text(
            strings.currentHandoffTemplate,
            style: const TextStyle(color: CopawColors.purpleDark),
          ),
          const SizedBox(height: 10),
          if (snapshot == null && error == null)
            const Center(child: CircularProgressIndicator())
          else if (error != null) ...[
            Text(
              strings.handoffLoadFailure,
              key: const Key('handoff.error'),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              key: const Key('handoff.retry'),
              onPressed: onRetry,
              child: Text(strings.retryHandoff),
            ),
          ] else if (handoff == null)
            Text(strings.handoffEmpty, key: const Key('handoff.empty'))
          else ...[
            if (snapshot!.isFromCache || snapshot!.hasPendingWrites) ...[
              _WarningBanner(
                key: const Key('handoff.notCurrent'),
                message: strings.handoffNotCurrent,
              ),
              const SizedBox(height: 10),
            ],
            _handoffLine(
              context,
              strings.careInstructions,
              handoff.careInstructions,
            ),
            _handoffLine(
              context,
              strings.emergencyContactName,
              handoff.emergencyContactName,
            ),
            _handoffLine(
              context,
              strings.emergencyContactPhone,
              handoff.emergencyContactPhone,
            ),
            _handoffLine(
              context,
              strings.veterinaryHospitalName,
              handoff.veterinaryHospitalName,
            ),
            _handoffLine(
              context,
              strings.veterinaryHospitalPhone,
              handoff.veterinaryHospitalPhone,
            ),
            const SizedBox(height: 6),
            Text(
              '${strings.handoffUpdatedBy(handoff.updatedByNameSnapshot)} · '
              '${_formatHouseholdDateTime(context, handoff.updatedAt, timeZoneIdentifier)}',
              style: const TextStyle(
                color: CopawColors.purpleDark,
                fontSize: 12,
              ),
            ),
          ],
          if (error == null) ...[
            const SizedBox(height: 12),
            FilledButton.icon(
              key: const Key('handoff.edit'),
              onPressed: onEdit,
              icon: const Icon(Icons.assignment_outlined),
              label: Text(strings.editHandoff),
            ),
          ],
        ],
      ),
    );
  }

  static Widget _handoffLine(
    BuildContext context,
    String label,
    String value,
  ) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: CopawColors.purpleDark)),
        Text(value.isEmpty ? '—' : value),
      ],
    ),
  );
}

class _HandoffSessionCard extends ConsumerStatefulWidget {
  const _HandoffSessionCard({
    required this.snapshot,
    required this.error,
    required this.strings,
    required this.session,
    required this.members,
    required this.template,
    required this.careSnapshot,
    required this.medicationSnapshot,
    required this.onRetry,
    required this.onOffer,
  });

  final HandoffSessionSnapshot? snapshot;
  final Object? error;
  final AppStrings strings;
  final HouseholdSession session;
  final List<Caregiver> members;
  final HandoffSnapshot? template;
  final CareTaskSnapshot? careSnapshot;
  final MedicationSnapshot? medicationSnapshot;
  final VoidCallback onRetry;
  final VoidCallback onOffer;

  @override
  ConsumerState<_HandoffSessionCard> createState() =>
      _HandoffSessionCardState();
}

class _HandoffSessionCardState extends ConsumerState<_HandoffSessionCard> {
  bool acting = false;
  String? actionError;
  String? retrySignature;
  String? retryMutationId;

  @override
  Widget build(BuildContext context) {
    final active = widget.snapshot?.activeSession;
    final pinned = widget.snapshot?.pinnedVersion;
    final authoritySafe =
        widget.snapshot != null &&
        widget.error == null &&
        !widget.snapshot!.isFromCache &&
        !widget.snapshot!.authorityMalformed &&
        widget.snapshot!.droppedSessionCount == 0 &&
        widget.snapshot!.droppedVersionCount == 0 &&
        (active == null || pinned != null);
    final templateSafe =
        widget.template?.handoff != null &&
        widget.template?.isFromCache == false &&
        widget.template?.hasPendingWrites == false &&
        widget.session.household.timeZoneIdentifier != null;
    HandoffCloseOutCounts? closeOutCounts;
    if (authoritySafe &&
        active != null &&
        pinned != null &&
        widget.careSnapshot?.isServerConfirmed == true &&
        widget.careSnapshot!.diagnostics.isEmpty &&
        widget.medicationSnapshot?.isServerConfirmed == true) {
      try {
        closeOutCounts = const HandoffCloseOutService().build(
          start: active.plannedStartAt,
          end: active.plannedEndAt,
          householdTimeZoneIdentifier: active.timeZoneIdentifierSnapshot,
          routines: widget.careSnapshot!.routines,
          tasks: widget.careSnapshot!.tasks,
          medicationSchedules: widget.medicationSnapshot!.schedules,
          medicationOccurrences: widget.medicationSnapshot!.occurrences,
        );
      } on HandoffCloseOutBuildException {
        closeOutCounts = null;
      }
    }
    return CopawCard(
      key: const Key('handoff.session.card'),
      child: Semantics(
        container: true,
        label: widget.strings.handoffCoverageSession,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.strings.handoffCoverageSession,
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text(
              widget.strings.handoffTemplateSessionHelp,
              style: const TextStyle(color: CopawColors.purpleDark),
            ),
            const SizedBox(height: 10),
            if (widget.error != null) ...[
              _RetryWarningBanner(
                key: const Key('handoff.session.error'),
                message: widget.strings.handoffSessionLoadFailure,
                retryLabel: widget.strings.retry,
                onRetry: widget.onRetry,
              ),
            ] else if (widget.snapshot == null)
              const Center(child: CircularProgressIndicator())
            else ...[
              if (!authoritySafe) ...[
                _WarningBanner(
                  key: const Key('handoff.session.notCurrent'),
                  message: widget.strings.handoffSessionNotCurrent,
                ),
                const SizedBox(height: 10),
              ],
              if (active == null)
                Text(
                  widget.strings.noActiveHandoffSession,
                  key: const Key('handoff.session.empty'),
                )
              else ...[
                Text(
                  widget.strings.handoffSessionStatus(active.status),
                  key: const Key('handoff.session.status'),
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 4),
                Text(
                  widget.strings.handoffSessionParticipants(
                    active.creatorNameSnapshot,
                    active.recipientNameSnapshot,
                  ),
                ),
                Text(
                  widget.strings.handoffSessionWindow(
                    _formatHouseholdDateTime(
                      context,
                      active.plannedStartAt,
                      active.timeZoneIdentifierSnapshot,
                    ),
                    _formatHouseholdDateTime(
                      context,
                      active.plannedEndAt,
                      active.timeZoneIdentifierSnapshot,
                    ),
                  ),
                ),
                Text(
                  widget.strings.handoffSessionTemplateRevision(
                    active.handoffRevisionSnapshot,
                  ),
                  style: const TextStyle(color: CopawColors.muted),
                ),
                if (pinned != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    widget.strings.handoffPinnedTemplate(
                      pinned.sourceHandoffRevision,
                    ),
                    key: const Key('handoff.session.pinnedVersion'),
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 6),
                  _HandoffCard._handoffLine(
                    context,
                    widget.strings.careInstructions,
                    pinned.careInstructions,
                  ),
                  _HandoffCard._handoffLine(
                    context,
                    widget.strings.emergencyContactName,
                    pinned.emergencyContactName,
                  ),
                  _HandoffCard._handoffLine(
                    context,
                    widget.strings.emergencyContactPhone,
                    pinned.emergencyContactPhone,
                  ),
                  _HandoffCard._handoffLine(
                    context,
                    widget.strings.veterinaryHospitalName,
                    pinned.veterinaryHospitalName,
                  ),
                  _HandoffCard._handoffLine(
                    context,
                    widget.strings.veterinaryHospitalPhone,
                    pinned.veterinaryHospitalPhone,
                  ),
                  const SizedBox(height: 4),
                  if (closeOutCounts != null) ...[
                    Text(
                      widget.strings.handoffCoverageCounts,
                      key: const Key('handoff.session.sourceCounts'),
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    Text(
                      widget.strings.handoffCareSourceCounts(
                        closeOutCounts.care.planned,
                        closeOutCounts.care.completed,
                        closeOutCounts.care.unresolved,
                      ),
                    ),
                    Text(
                      widget.strings.handoffMedicationSourceCounts(
                        closeOutCounts.medication.planned,
                        closeOutCounts.medication.administered,
                        closeOutCounts.medication.skipped,
                        closeOutCounts.medication.unresolved,
                      ),
                    ),
                  ] else
                    Text(
                      widget.strings.handoffCoverageCountsUnavailable,
                      key: const Key('handoff.session.sourceCountsUnavailable'),
                      style: const TextStyle(color: CopawColors.muted),
                    ),
                ],
              ],
            ],
            if (actionError != null) ...[
              const SizedBox(height: 8),
              Text(
                actionError!,
                key: const Key('handoff.session.actionError'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            if (authoritySafe && active == null && templateSafe) ...[
              const SizedBox(height: 12),
              FilledButton.icon(
                key: const Key('handoff.session.offer'),
                onPressed: acting || widget.members.length < 2
                    ? null
                    : widget.onOffer,
                icon: const Icon(Icons.forward_to_inbox_rounded),
                label: Text(widget.strings.offerHandoffSession),
              ),
            ],
            if (authoritySafe && active != null) ...[
              const SizedBox(height: 12),
              Wrap(spacing: 8, runSpacing: 8, children: _actions(active)),
            ],
          ],
        ),
      ),
    );
  }

  List<Widget> _actions(HandoffSession session) {
    final actorId = widget.session.caregiver.id;
    final owner = widget.session.household.ownerId == actorId;
    if (session.status == HandoffSessionStatus.offered) {
      if (session.recipientId == actorId) {
        return [
          _button('accept', widget.strings.acceptHandoffSession, session),
          _button('decline', widget.strings.declineHandoffSession, session),
        ];
      }
      if (session.creatorId == actorId || owner) {
        return [
          _button(
            'cancel',
            owner && session.creatorId != actorId
                ? widget.strings.recoverHandoffSession
                : widget.strings.cancelHandoffSession,
            session,
          ),
        ];
      }
    }
    if (session.status == HandoffSessionStatus.accepted &&
        (session.creatorId == actorId ||
            session.recipientId == actorId ||
            owner)) {
      return [
        _button(
          'close',
          owner &&
                  session.creatorId != actorId &&
                  session.recipientId != actorId
              ? widget.strings.recoverHandoffSession
              : widget.strings.closeHandoffSession,
          session,
        ),
      ];
    }
    return const [];
  }

  Widget _button(String action, String label, HandoffSession session) =>
      OutlinedButton(
        key: Key('handoff.session.$action'),
        onPressed: acting ? null : () => _transition(action, session),
        child: Text(label),
      );

  Future<void> _transition(String action, HandoffSession session) async {
    final signature = '$action:${session.id}:${session.revision}';
    if (retrySignature != signature || retryMutationId == null) {
      retrySignature = signature;
      retryMutationId =
          'flutter-handoff-'
          '${DateTime.now().microsecondsSinceEpoch.toRadixString(16)}';
    }
    setState(() {
      acting = true;
      actionError = null;
    });
    try {
      await ref
          .read(handoffSessionRepositoryProvider)
          .transition(
            householdId: widget.session.household.id,
            action: action,
            sessionId: session.id,
            expectedSessionRevision: session.revision,
            clientMutationId: retryMutationId!,
          );
      retrySignature = null;
      retryMutationId = null;
    } on HandoffSessionException catch (exception) {
      if (mounted) {
        setState(
          () => actionError = switch (exception.code) {
            HandoffSessionErrorCode.network =>
              widget.strings.handoffSessionNetworkFailure,
            HandoffSessionErrorCode.permission =>
              widget.strings.handoffSessionPermissionFailure,
            HandoffSessionErrorCode.stale ||
            HandoffSessionErrorCode.blocked ||
            HandoffSessionErrorCode.notFound =>
              widget.strings.handoffSessionStaleFailure,
            _ => widget.strings.handoffSessionActionFailure,
          },
        );
      }
    } on Object {
      if (mounted) {
        setState(
          () => actionError = widget.strings.handoffSessionActionFailure,
        );
      }
    } finally {
      if (mounted) setState(() => acting = false);
    }
  }
}

class _HandoffOfferDialog extends ConsumerStatefulWidget {
  const _HandoffOfferDialog({
    required this.strings,
    required this.session,
    required this.recipients,
    required this.expectedHandoffRevision,
  });

  final AppStrings strings;
  final HouseholdSession session;
  final List<Caregiver> recipients;
  final int expectedHandoffRevision;

  @override
  ConsumerState<_HandoffOfferDialog> createState() =>
      _HandoffOfferDialogState();
}

class _HandoffOfferDialogState extends ConsumerState<_HandoffOfferDialog> {
  late String recipientId = widget.recipients.first.id;
  late final tz.Location householdLocation = tz.getLocation(
    widget.session.household.timeZoneIdentifier!,
  );
  late DateTime start = tz.TZDateTime.now(
    householdLocation,
  ).add(const Duration(hours: 1)).toUtc();
  late DateTime end = start.add(const Duration(days: 1));
  String? retrySignature;
  String? retryMutationId;
  bool saving = false;
  String? error;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.strings.offerHandoffSession),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.strings.handoffOfferConsentHelp),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            key: const Key('handoff.offer.recipient'),
            initialValue: recipientId,
            decoration: InputDecoration(
              labelText: widget.strings.handoffRecipient,
            ),
            items: widget.recipients
                .map(
                  (member) => DropdownMenuItem(
                    value: member.id,
                    child: Text(member.displayName),
                  ),
                )
                .toList(growable: false),
            onChanged: saving
                ? null
                : (value) => setState(() => recipientId = value!),
          ),
          ListTile(
            key: const Key('handoff.offer.start'),
            contentPadding: EdgeInsets.zero,
            title: Text(widget.strings.handoffPlannedStart),
            subtitle: Text(
              _formatHouseholdDateTime(
                context,
                start,
                widget.session.household.timeZoneIdentifier,
              ),
            ),
            trailing: const Icon(Icons.edit_calendar_rounded),
            onTap: saving ? null : () => _pick(start, isStart: true),
          ),
          ListTile(
            key: const Key('handoff.offer.end'),
            contentPadding: EdgeInsets.zero,
            title: Text(widget.strings.handoffPlannedEnd),
            subtitle: Text(
              _formatHouseholdDateTime(
                context,
                end,
                widget.session.household.timeZoneIdentifier,
              ),
            ),
            trailing: const Icon(Icons.edit_calendar_rounded),
            onTap: saving ? null : () => _pick(end, isStart: false),
          ),
          if (error != null)
            Text(
              error!,
              key: const Key('handoff.offer.error'),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: saving ? null : () => Navigator.pop(context),
        child: Text(widget.strings.cancel),
      ),
      FilledButton(
        key: const Key('handoff.offer.save'),
        onPressed: saving ? null : _offer,
        child: Text(widget.strings.offerHandoffSession),
      ),
    ],
  );

  Future<void> _pick(DateTime current, {required bool isStart}) async {
    final householdCurrent = tz.TZDateTime.from(current, householdLocation);
    final householdNow = tz.TZDateTime.now(householdLocation);
    final date = await showDatePicker(
      context: context,
      initialDate: householdCurrent,
      firstDate: DateTime(
        householdNow.year,
        householdNow.month,
        householdNow.day,
      ),
      lastDate: DateTime(
        householdNow.year,
        householdNow.month,
        householdNow.day,
      ).add(const Duration(days: 30)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(householdCurrent),
    );
    if (time == null || !mounted) return;
    final selected = tz.TZDateTime(
      householdLocation,
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    ).toUtc();
    setState(() {
      if (isStart) {
        start = selected;
        if (!start.isBefore(end)) end = start.add(const Duration(days: 1));
      } else {
        end = selected;
      }
    });
  }

  Future<void> _offer() async {
    if (!start.isBefore(end) ||
        end.difference(start) > const Duration(days: 30)) {
      setState(() => error = widget.strings.handoffWindowInvalid);
      return;
    }
    final signature = [
      recipientId,
      widget.expectedHandoffRevision,
      start.toUtc().millisecondsSinceEpoch,
      end.toUtc().millisecondsSinceEpoch,
    ].join(':');
    if (retrySignature != signature || retryMutationId == null) {
      retrySignature = signature;
      retryMutationId =
          'flutter-handoff-offer-'
          '${DateTime.now().microsecondsSinceEpoch.toRadixString(16)}';
    }
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await ref
          .read(handoffSessionRepositoryProvider)
          .offer(
            householdId: widget.session.household.id,
            recipientId: recipientId,
            expectedHandoffRevision: widget.expectedHandoffRevision,
            plannedStart: start,
            plannedEnd: end,
            clientMutationId: retryMutationId!,
          );
      retrySignature = null;
      retryMutationId = null;
      if (mounted) Navigator.pop(context);
    } on HandoffSessionException catch (exception) {
      if (mounted) {
        setState(
          () => error = switch (exception.code) {
            HandoffSessionErrorCode.network =>
              widget.strings.handoffSessionNetworkFailure,
            HandoffSessionErrorCode.permission =>
              widget.strings.handoffSessionPermissionFailure,
            HandoffSessionErrorCode.stale || HandoffSessionErrorCode.blocked =>
              widget.strings.handoffSessionStaleFailure,
            _ => widget.strings.handoffSessionActionFailure,
          },
        );
      }
    } on Object {
      if (mounted) {
        setState(() => error = widget.strings.handoffSessionActionFailure);
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }
}

class _HandoffDialog extends StatefulWidget {
  const _HandoffDialog({
    required this.current,
    required this.strings,
    required this.onSave,
  });

  final HouseholdHandoff? current;
  final AppStrings strings;
  final Future<void> Function(
    String careInstructions,
    String emergencyContactName,
    String emergencyContactPhone,
    String veterinaryHospitalName,
    String veterinaryHospitalPhone,
  )
  onSave;

  @override
  State<_HandoffDialog> createState() => _HandoffDialogState();
}

class _HandoffDialogState extends State<_HandoffDialog> {
  late final careController = TextEditingController(
    text: widget.current?.careInstructions,
  );
  late final contactNameController = TextEditingController(
    text: widget.current?.emergencyContactName,
  );
  late final contactPhoneController = TextEditingController(
    text: widget.current?.emergencyContactPhone,
  );
  late final hospitalNameController = TextEditingController(
    text: widget.current?.veterinaryHospitalName,
  );
  late final hospitalPhoneController = TextEditingController(
    text: widget.current?.veterinaryHospitalPhone,
  );
  bool saving = false;
  String? error;

  @override
  void dispose() {
    careController.dispose();
    contactNameController.dispose();
    contactPhoneController.dispose();
    hospitalNameController.dispose();
    hospitalPhoneController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.strings.householdHandoff),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            key: const Key('handoff.careInstructions'),
            controller: careController,
            maxLength: 1000,
            maxLines: 4,
            decoration: InputDecoration(
              labelText: widget.strings.careInstructions,
            ),
          ),
          TextField(
            key: const Key('handoff.contactName'),
            controller: contactNameController,
            maxLength: 80,
            decoration: InputDecoration(
              labelText: widget.strings.emergencyContactName,
            ),
          ),
          TextField(
            key: const Key('handoff.contactPhone'),
            controller: contactPhoneController,
            maxLength: 40,
            keyboardType: TextInputType.phone,
            decoration: InputDecoration(
              labelText: widget.strings.emergencyContactPhone,
            ),
          ),
          TextField(
            key: const Key('handoff.hospitalName'),
            controller: hospitalNameController,
            maxLength: 100,
            decoration: InputDecoration(
              labelText: widget.strings.veterinaryHospitalName,
            ),
          ),
          TextField(
            key: const Key('handoff.hospitalPhone'),
            controller: hospitalPhoneController,
            maxLength: 40,
            keyboardType: TextInputType.phone,
            decoration: InputDecoration(
              labelText: widget.strings.veterinaryHospitalPhone,
            ),
          ),
          if (error != null)
            Text(
              error!,
              key: const Key('handoff.saveError'),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: saving ? null : () => Navigator.of(context).pop(),
        child: Text(widget.strings.cancel),
      ),
      FilledButton(
        key: const Key('handoff.save'),
        onPressed: saving ? null : _save,
        child: Text(
          saving ? widget.strings.savingTask : widget.strings.saveHandoff,
        ),
      ),
    ],
  );

  Future<void> _save() async {
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await widget.onSave(
        careController.text,
        contactNameController.text,
        contactPhoneController.text,
        hospitalNameController.text,
        hospitalPhoneController.text,
      );
      if (mounted) Navigator.of(context).pop();
    } on Object catch (caught) {
      if (mounted) {
        setState(() {
          error =
              caught is HandoffRepositoryException &&
                  caught.code == HandoffRepositoryErrorCode.conflict
              ? widget.strings.handoffConflict
              : widget.strings.handoffSaveFailure;
        });
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }
}

class _HouseholdAccessCard extends StatelessWidget {
  const _HouseholdAccessCard({
    required this.inviteCode,
    required this.members,
    required this.strings,
  });

  final String inviteCode;
  final List<Caregiver> members;
  final AppStrings strings;

  @override
  Widget build(BuildContext context) => CopawCard(
    key: const Key('profile.householdAccess'),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.group_rounded, color: CopawColors.purple),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                strings.householdAccess,
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Text(
          strings.inviteCode,
          style: const TextStyle(color: CopawColors.purpleDark),
        ),
        const SizedBox(height: 3),
        SelectableText(
          inviteCode,
          key: const Key('household.inviteCode'),
          style: const TextStyle(
            color: CopawColors.purpleDark,
            fontSize: 24,
            fontWeight: FontWeight.w900,
            letterSpacing: 4,
          ),
        ),
        const SizedBox(height: 13),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final member in members)
              Chip(
                avatar: CircleAvatar(
                  backgroundColor: CopawColors.lavender,
                  child: Text(
                    member.displayName.characters.firstOrNull?.toUpperCase() ??
                        '?',
                    style: const TextStyle(
                      color: CopawColors.purpleDark,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                label: Text(member.displayName),
              ),
          ],
        ),
      ],
    ),
  );
}

class _LanguagePreferenceCard extends ConsumerWidget {
  const _LanguagePreferenceCard({required this.strings, required this.locale});

  final AppStrings strings;
  final AppLocale locale;

  @override
  Widget build(BuildContext context, WidgetRef ref) => CopawCard(
    key: const Key('profile.languageCard'),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Icon(Icons.translate_rounded, color: CopawColors.blue),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                strings.languagePreference,
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        SegmentedButton<AppLocale>(
          key: const Key('profile.language'),
          direction: MediaQuery.textScalerOf(context).scale(1) >= 2
              ? Axis.vertical
              : Axis.horizontal,
          segments: const [
            ButtonSegment(value: AppLocale.japanese, label: Text('日本語')),
            ButtonSegment(value: AppLocale.english, label: Text('English')),
          ],
          selected: {locale},
          onSelectionChanged: (value) =>
              ref.read(appControllerProvider.notifier).setLocale(value.single),
        ),
      ],
    ),
  );
}

class _ProfileSheet extends ConsumerStatefulWidget {
  const _ProfileSheet({required this.session});

  final HouseholdSession session;

  @override
  ConsumerState<_ProfileSheet> createState() => _ProfileSheetState();
}

class _ProfileSheetState extends ConsumerState<_ProfileSheet> {
  late final householdController = TextEditingController(
    text: widget.session.household.name,
  );
  late final petController = TextEditingController(
    text: widget.session.household.petName,
  );
  late final caregiverController = TextEditingController(
    text: widget.session.caregiver.displayName,
  );
  bool saving = false;
  String? error;

  @override
  void dispose() {
    householdController.dispose();
    petController.dispose();
    caregiverController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings(
      ref.watch(appControllerProvider).value?.locale ?? AppLocale.english,
    );
    return SafeArea(
      top: false,
      child: AnimatedPadding(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                key: const Key('profile.householdName'),
                controller: householdController,
                decoration: InputDecoration(labelText: strings.householdName),
              ),
              TextField(
                key: const Key('profile.petName'),
                controller: petController,
                decoration: InputDecoration(labelText: strings.petName),
              ),
              TextField(
                key: const Key('profile.caregiverName'),
                controller: caregiverController,
                decoration: InputDecoration(labelText: strings.caregiverName),
              ),
              if (error != null)
                Text(
                  error!,
                  key: const Key('profile.error'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              const SizedBox(height: 14),
              FilledButton(
                key: const Key('profile.save'),
                onPressed: saving ? null : () => _save(strings),
                child: Text(strings.saveChanges),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                key: const Key('profile.cancel'),
                onPressed: saving ? null : () => Navigator.of(context).pop(),
                child: Text(strings.cancel),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _save(AppStrings strings) async {
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await ref
          .read(householdSyncRepositoryProvider)
          .updateProfile(
            householdId: widget.session.household.id,
            userId: widget.session.caregiver.id,
            householdName: householdController.text,
            petName: petController.text,
            caregiverName: caregiverController.text,
          );
      if (mounted) Navigator.of(context).pop();
    } on Object {
      if (mounted) setState(() => error = strings.profileSaveFailure);
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }
}

class _WarningBanner extends StatelessWidget {
  const _WarningBanner({required this.message, super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF4D6),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, color: Color(0xFF8A5A00)),
          const SizedBox(width: 10),
          Expanded(child: Text(message)),
        ],
      ),
    );
  }
}

class _RetryWarningBanner extends StatelessWidget {
  const _RetryWarningBanner({
    required this.message,
    required this.retryLabel,
    required this.onRetry,
    this.retryKey = const Key('household.syncRetry'),
    super.key,
  });

  final String message;
  final String retryLabel;
  final VoidCallback onRetry;
  final Key retryKey;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF4D6),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.sync_problem_rounded, color: Color(0xFF8A5A00)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(message),
                const SizedBox(height: 8),
                OutlinedButton(
                  key: retryKey,
                  onPressed: onRetry,
                  child: Text(retryLabel),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

DateTime _toHouseholdLocal(DateTime instant, String? timeZoneIdentifier) {
  if (timeZoneIdentifier == null) return instant.toLocal();
  try {
    return tz.TZDateTime.from(instant, tz.getLocation(timeZoneIdentifier));
  } on tz.LocationNotFoundException {
    return instant.toLocal();
  }
}

DateTime _householdInstant(
  DateTime date,
  TimeOfDay time,
  String timeZoneIdentifier,
) {
  final location = tz.getLocation(timeZoneIdentifier);
  return tz.TZDateTime(
    location,
    date.year,
    date.month,
    date.day,
    time.hour,
    time.minute,
  ).toUtc();
}

String _formatHouseholdDateTime(
  BuildContext context,
  DateTime instant,
  String? timeZoneIdentifier,
) {
  final local = _toHouseholdLocal(instant, timeZoneIdentifier);
  final material = MaterialLocalizations.of(context);
  final date = material.formatMediumDate(local);
  final time = material.formatTimeOfDay(TimeOfDay.fromDateTime(local));
  return '$date · $time';
}

String _formatHouseholdDate(
  BuildContext context,
  DateTime instant,
  String? timeZoneIdentifier,
) => MaterialLocalizations.of(
  context,
).formatMediumDate(_toHouseholdLocal(instant, timeZoneIdentifier));
