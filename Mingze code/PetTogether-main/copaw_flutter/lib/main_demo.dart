import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'src/app.dart';
import 'src/bootstrap/bootstrap_repository.dart';
import 'src/data/care_task_mutation_repository.dart';
import 'src/data/care_task_repository.dart';
import 'src/data/collaboration_event_repository.dart';
import 'src/data/handoff_repository.dart';
import 'src/data/handoff_session_repository.dart';
import 'src/data/health_repository.dart';
import 'src/data/household_repository.dart';
import 'src/data/household_sync_repository.dart';
import 'src/data/local_timezone_repository.dart';
import 'src/data/medication_repository.dart';
import 'src/data/membership_exit_repository.dart';
import 'src/data/notification_repository.dart';
import 'src/data/notification_center_repository.dart';
import 'src/data/pet_repository.dart';
import 'src/data/report_share_repository.dart';
import 'src/data/task_responsibility_repository.dart';
import 'src/domain/handoff_models.dart';
import 'src/domain/collaboration_event_models.dart';
import 'src/domain/health_models.dart';
import 'src/domain/medication_models.dart';
import 'src/domain/models.dart';
import 'src/domain/notification_models.dart';
import 'src/domain/report_models.dart';
import 'src/localization/app_locale.dart';
import 'src/localization/locale_repository.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final now = DateTime.now();
  final session = _demoSession;

  runApp(
    ProviderScope(
      overrides: [
        bootstrapRepositoryProvider.overrideWithValue(
          FakeBootstrapRepository(),
        ),
        localeRepositoryProvider.overrideWithValue(FakeLocaleRepository()),
        householdRepositoryProvider.overrideWithValue(
          _DemoHouseholdRepository(session),
        ),
        localTimeZoneRepositoryProvider.overrideWithValue(
          const _DemoTimeZoneRepository(),
        ),
        householdSyncRepositoryProvider.overrideWithValue(
          _DemoHouseholdSyncRepository(session),
        ),
        careTaskRepositoryProvider.overrideWithValue(
          _DemoCareTaskRepository(now),
        ),
        careTaskMutationRepositoryProvider.overrideWithValue(
          const _DemoCareTaskMutationRepository(),
        ),
        collaborationEventRepositoryProvider.overrideWithValue(
          FakeCollaborationEventRepository(
            events: _demoCollaborationEvents(now),
          ),
        ),
        petRepositoryProvider.overrideWithValue(const _DemoPetRepository()),
        medicationRepositoryProvider.overrideWithValue(
          _DemoMedicationRepository(now),
        ),
        notificationRepositoryProvider.overrideWithValue(
          const _DemoNotificationRepository(),
        ),
        notificationDeviceRepositoryProvider.overrideWithValue(
          const LegacyNotificationDeviceRepository(
            _DemoNotificationRepository(),
          ),
        ),
        notificationPreferencesRepositoryProvider.overrideWithValue(
          FakeNotificationPreferencesRepository(
            const NotificationPreferencesSnapshot(
              preferences: null,
              authority: NotificationPreferenceAuthority.missingDefaults,
            ),
          ),
        ),
        notificationInboxRepositoryProvider.overrideWithValue(
          FakeNotificationInboxRepository(),
        ),
        notificationDeliveryEvidenceRepositoryProvider.overrideWithValue(
          FakeNotificationDeliveryEvidenceRepository(
            const NotificationProviderEvidenceSnapshot(
              evidence: NotificationProviderEvidence
                  .notVerifiedForCurrentInstallation,
              authority: NotificationObservationAuthority.serverConfirmed,
              updatedAt: null,
              attemptCount: 0,
            ),
          ),
        ),
        notificationInteractionRepositoryProvider.overrideWithValue(
          FakeNotificationInteractionRepository(),
        ),
        healthRepositoryProvider.overrideWithValue(_DemoHealthRepository(now)),
        handoffRepositoryProvider.overrideWithValue(
          _DemoHandoffRepository(now),
        ),
        handoffSessionRepositoryProvider.overrideWithValue(
          FakeHandoffSessionRepository(),
        ),
        taskResponsibilityRepositoryProvider.overrideWithValue(
          FakeTaskResponsibilityRepository(),
        ),
        membershipExitRepositoryProvider.overrideWithValue(
          FakeMembershipExitRepository(),
        ),
        reportShareRepositoryProvider.overrideWithValue(
          const _DemoReportShareRepository(),
        ),
      ],
      child: const CopawApp(),
    ),
  );
}

final _demoSession = HouseholdSession(
  household: Household(
    id: 'local-ui-demo',
    name: 'Mochi Home',
    inviteCode: 'LOCAL0',
    petName: 'Mochi',
    timeZoneIdentifier: 'Asia/Tokyo',
  ),
  caregiver: Caregiver(id: 'demo-alex', displayName: 'Alex'),
  memberJoinedAt: DateTime.utc(2026, 8, 1),
);

const _demoPets = [
  Pet(
    id: 'pet-mochi',
    name: 'Mochi',
    species: PetSpecies.dog,
    isArchived: false,
    createdAt: null,
    updatedAt: null,
  ),
  Pet(
    id: 'pet-luna',
    name: 'Luna',
    species: PetSpecies.rabbit,
    isArchived: false,
    createdAt: null,
    updatedAt: null,
  ),
];

List<CollaborationEvent> _demoCollaborationEvents(DateTime now) => [
  CollaborationEvent(
    id: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    sourceId: 'demo-task-walk',
    sourceRevision: 2,
    action: CollaborationEventAction.taskAccepted,
    actorId: 'demo-maya',
    actorNameSnapshot: 'Maya',
    targetMemberId: 'demo-alex',
    targetMemberNameSnapshot: 'Alex',
    requestId: 'demo-request-walk',
    assignmentMode: 'direct',
    petId: 'pet-mochi',
    petNameSnapshot: 'Mochi',
    taskTitleSnapshot: '夕方のお散歩',
    taskCategorySnapshot: 'walking',
    taskPrioritySnapshot: 'normal',
    taskDueTime: now.add(const Duration(hours: 2)),
    stateAfter: CollaborationTaskState.claimed,
    occurredAt: now.subtract(const Duration(minutes: 12)),
    recordedAt: now.subtract(const Duration(minutes: 12)),
  ),
  CollaborationEvent(
    id: 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
    sourceId: 'demo-task-water',
    sourceRevision: 1,
    action: CollaborationEventAction.taskRequested,
    actorId: 'demo-alex',
    actorNameSnapshot: 'Alex',
    targetMemberId: null,
    targetMemberNameSnapshot: null,
    requestId: 'demo-request-water',
    assignmentMode: 'open',
    petId: 'pet-luna',
    petNameSnapshot: 'Luna',
    taskTitleSnapshot: '飲み水を交換',
    taskCategorySnapshot: 'other',
    taskPrioritySnapshot: 'normal',
    taskDueTime: now.add(const Duration(hours: 1)),
    stateAfter: CollaborationTaskState.unclaimed,
    occurredAt: now.subtract(const Duration(minutes: 35)),
    recordedAt: now.subtract(const Duration(minutes: 35)),
  ),
];

final class _DemoHouseholdRepository implements HouseholdRepository {
  const _DemoHouseholdRepository(this.session);

  final HouseholdSession session;

  @override
  Future<HouseholdSession?> restoreSession() async => session;

  @override
  Future<HouseholdSession> createHousehold({
    required String householdName,
    required String petName,
    required String caregiverName,
    required String timeZoneIdentifier,
  }) async => session;

  @override
  Future<HouseholdSession> joinHousehold({
    required String inviteCode,
    required String caregiverName,
  }) async => session;

  @override
  Future<void> leaveHousehold() async {}
}

final class _DemoHouseholdSyncRepository implements HouseholdSyncRepository {
  const _DemoHouseholdSyncRepository(this.session);

  final HouseholdSession session;

  @override
  Stream<HouseholdSyncSnapshot> observeSession({
    required String householdId,
    required String userId,
  }) => Stream.value(
    HouseholdSyncSnapshot(
      household: session.household,
      caregiver: session.caregiver,
      members: const [
        Caregiver(id: 'demo-alex', displayName: 'Alex'),
        Caregiver(id: 'demo-maya', displayName: 'Maya'),
      ],
    ),
  );

  @override
  Future<void> updateProfile({
    required String householdId,
    required String userId,
    required String householdName,
    required String petName,
    required String caregiverName,
  }) async {}

  @override
  Future<void> stopObserving() async {}
}

final class _DemoCareTaskRepository
    implements CareTaskRepository, PetBoundCareTaskWriter {
  _DemoCareTaskRepository(DateTime now)
    : snapshot = CareTaskSnapshot(
        routines: [
          CareRoutine(
            id: 'demo-routine-breakfast',
            title: '朝ごはん',
            category: CareCategory.feeding,
            priority: CarePriority.normal,
            frequency: CareRoutineFrequency.daily,
            weekdays: const [1, 2, 3, 4, 5, 6, 7],
            hour: now.hour,
            minute: now.minute,
            startDate: DateTime(2020),
            timeZoneIdentifier: 'Asia/Tokyo',
            createdById: 'demo-alex',
            createdByNameSnapshot: 'Alex',
            isActive: true,
            petId: 'pet-mochi',
            petNameSnapshot: 'Mochi',
          ),
        ],
        tasks: [
          CareTask(
            id: 'demo-walk',
            title: '夕方のお散歩',
            category: CareCategory.walking,
            dueTime: now.add(const Duration(hours: 2)),
            kind: CareTaskKind.oneOff,
            priority: CarePriority.normal,
            routineId: null,
            status: CareTaskStatus.unclaimed,
            assignmentRequest: null,
            assigneeId: null,
            assigneeNameSnapshot: null,
            claimedAt: null,
            createdById: 'demo-alex',
            createdBy: 'Alex',
            createdAt: now.subtract(const Duration(hours: 2)),
            completedById: null,
            completedBy: null,
            completedAt: null,
            revision: 0,
            petId: 'pet-mochi',
            petNameSnapshot: 'Mochi',
          ),
          CareTask(
            id: 'demo-litter',
            title: 'トイレ掃除',
            category: CareCategory.other,
            dueTime: now.subtract(const Duration(hours: 3)),
            kind: CareTaskKind.oneOff,
            priority: CarePriority.normal,
            routineId: null,
            status: CareTaskStatus.completed,
            assignmentRequest: null,
            assigneeId: 'demo-maya',
            assigneeNameSnapshot: 'Maya',
            claimedAt: now.subtract(const Duration(hours: 4)),
            createdById: 'demo-alex',
            createdBy: 'Alex',
            createdAt: now.subtract(const Duration(days: 1)),
            completedById: 'demo-maya',
            completedBy: 'Maya',
            completedAt: now.subtract(const Duration(hours: 2)),
            revision: 2,
            petId: 'pet-luna',
            petNameSnapshot: 'Luna',
          ),
        ],
      );

  final CareTaskSnapshot snapshot;

  @override
  Stream<CareTaskSnapshot> observeCare(String householdId) =>
      Stream.value(snapshot);

  @override
  Future<String> createOneOffTask({
    required String householdId,
    required String title,
    required CareCategory category,
    required DateTime dueTime,
    required CarePriority priority,
    required String createdById,
    required String createdByName,
  }) async => 'demo-created-task';

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
  }) => createOneOffTask(
    householdId: householdId,
    title: title,
    category: category,
    dueTime: dueTime,
    priority: priority,
    createdById: createdById,
    createdByName: createdByName,
  );

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
  }) async => 'demo-created-routine';

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
  }) => createRoutine(
    householdId: householdId,
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

  @override
  Future<void> stopObserving() async {}
}

final class _DemoCareTaskMutationRepository
    implements CareTaskMutationRepository {
  const _DemoCareTaskMutationRepository();

  @override
  Future<void> claim({
    required String householdId,
    required String taskId,
    required String actorId,
    CareTask? taskIfMissing,
  }) async {}

  @override
  Future<String> requestDirect({
    required String householdId,
    required String taskId,
    required String actorId,
    required String recipientId,
    CareTask? taskIfMissing,
  }) async => 'demo-request';

  @override
  Future<String> requestOpen({
    required String householdId,
    required String taskId,
    required String actorId,
    CareTask? taskIfMissing,
  }) async => 'demo-request';

  @override
  Future<void> accept({
    required String householdId,
    required String taskId,
    required String actorId,
    required String requestId,
  }) async {}

  @override
  Future<void> decline({
    required String householdId,
    required String taskId,
    required String actorId,
    required String requestId,
  }) async {}

  @override
  Future<void> cancel({
    required String householdId,
    required String taskId,
    required String actorId,
    required String requestId,
  }) async {}

  @override
  Future<void> complete({
    required String householdId,
    required String taskId,
    required String actorId,
  }) async {}
}

final class _DemoPetRepository implements PetRepository {
  const _DemoPetRepository();

  @override
  Stream<PetSnapshot> observePets(String householdId) =>
      Stream.value(const PetSnapshot(pets: _demoPets));

  @override
  Future<String> createPet({
    required String householdId,
    required String name,
    required PetSpecies? species,
  }) async => 'demo-pet';

  @override
  Future<void> renamePet({
    required String householdId,
    required String petId,
    required String name,
  }) async {}

  @override
  Future<void> archivePet({
    required String householdId,
    required String petId,
  }) async {}

  @override
  Future<void> stopObserving() async {}
}

final class _DemoMedicationRepository implements MedicationRepository {
  _DemoMedicationRepository(DateTime now)
    : snapshot = MedicationSnapshot(
        medications: const [
          Medication(
            id: 'demo-medication',
            petId: 'pet-mochi',
            displayName: 'ハートケア錠',
            purpose: '獣医師の処方内容に基づく心臓ケアの記録',
            possibleSideEffects: '食欲や元気の変化を観察し、気になる場合は動物病院へ連絡',
            isActive: true,
            currentScheduleVersion: 1,
            currentScheduleVersionId: 'v000001',
            revision: 0,
          ),
          Medication(
            id: 'demo-luna-medication',
            petId: 'pet-luna',
            displayName: 'モイスチャー点眼液',
            purpose: '左目の乾燥ケアとして処方された点眼記録',
            possibleSideEffects: '赤みや強い違和感が続く場合は動物病院へ連絡',
            isActive: true,
            currentScheduleVersion: 1,
            currentScheduleVersionId: 'v000001',
            revision: 0,
          ),
          Medication(
            id: 'demo-past-medication',
            petId: 'pet-mochi',
            displayName: '抗菌薬（治療終了）',
            purpose: '過去の皮膚治療で処方された記録',
            possibleSideEffects: '治療期間中の体調変化は記録なし',
            isActive: false,
            currentScheduleVersion: 1,
            currentScheduleVersionId: 'v000001',
            revision: 1,
          ),
        ],
        schedules: [
          MedicationScheduleVersion(
            id: 'v000001',
            medicationId: 'demo-medication',
            version: 1,
            petId: 'pet-mochi',
            petNameSnapshot: 'Mochi',
            medicationNameSnapshot: 'ハートケア錠',
            weekdays: const [1, 2, 3, 4, 5, 6, 7],
            slots: [
              MedicationSlot(
                slotId: 'daily',
                hour: now.hour,
                minute: now.minute,
                doseText: '1錠',
                instructions: '食事と一緒に与える',
              ),
            ],
            timeZoneIdentifier: 'Asia/Tokyo',
            effectiveFromLocalDate: '2020-01-01',
            effectiveUntilLocalDate: null,
          ),
          MedicationScheduleVersion(
            id: 'v000001',
            medicationId: 'demo-luna-medication',
            version: 1,
            petId: 'pet-luna',
            petNameSnapshot: 'Luna',
            medicationNameSnapshot: 'モイスチャー点眼液',
            weekdays: const [1, 2, 3, 4, 5, 6, 7],
            slots: [
              MedicationSlot(
                slotId: 'evening',
                hour: (now.hour + 1) % 24,
                minute: now.minute,
                doseText: '1滴',
                instructions: '左目に点眼する',
              ),
            ],
            timeZoneIdentifier: 'Asia/Tokyo',
            effectiveFromLocalDate: '2020-01-01',
            effectiveUntilLocalDate: null,
          ),
          MedicationScheduleVersion(
            id: 'v000001',
            medicationId: 'demo-past-medication',
            version: 1,
            petId: 'pet-mochi',
            petNameSnapshot: 'Mochi',
            medicationNameSnapshot: '抗菌薬（治療終了）',
            weekdays: const [1, 2, 3, 4, 5, 6, 7],
            slots: const [
              MedicationSlot(
                slotId: '0800',
                hour: 8,
                minute: 0,
                doseText: '1錠',
                instructions: '7日間、朝食後に与える',
              ),
            ],
            timeZoneIdentifier: 'Asia/Tokyo',
            effectiveFromLocalDate: '2026-07-20',
            effectiveUntilLocalDate: '2026-07-27',
          ),
        ],
        occurrences: [
          MedicationOccurrence(
            id: 'demo-medication-history',
            medicationId: 'demo-medication',
            scheduleVersionId: 'v000001',
            scheduleVersion: 1,
            slotId: 'daily',
            localDate: 'recent-demo-day',
            dueAt: now.subtract(const Duration(days: 1)),
            petId: 'pet-mochi',
            petNameSnapshot: 'Mochi',
            medicationNameSnapshot: 'ハートケア錠',
            doseText: '1錠',
            instructions: '食事と一緒に与える',
            responsibilityStatus: MedicationResponsibilityStatus.claimed,
            responsibleById: 'demo-maya',
            responsibleByNameSnapshot: 'Maya',
            claimedAt: now.subtract(const Duration(days: 1, minutes: 5)),
            outcomeStatus: MedicationOutcomeStatus.administered,
            outcomeById: 'demo-maya',
            outcomeByNameSnapshot: 'Maya',
            outcomeAt: now.subtract(const Duration(days: 1)),
            skippedReasonCode: null,
            skippedReasonNote: null,
            revision: 2,
            isServerConfirmed: true,
          ),
        ],
        isServerConfirmed: true,
      );

  final MedicationSnapshot snapshot;

  @override
  Stream<MedicationSnapshot> observeMedication(String householdId) =>
      Stream.value(snapshot);

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
  }) async => 'demo-medication';

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
  }) async {}

  @override
  Future<void> stopPlan({
    required String householdId,
    required Medication medication,
    required String effectiveUntilLocalDate,
  }) async {}

  @override
  Future<void> claim({
    required String householdId,
    required PlannedMedicationOccurrence occurrence,
  }) async {}

  @override
  Future<void> administer({
    required String householdId,
    required PlannedMedicationOccurrence occurrence,
  }) async {}

  @override
  Future<void> skip({
    required String householdId,
    required PlannedMedicationOccurrence occurrence,
    required MedicationSkipReasonCode reasonCode,
    String? reasonNote,
  }) async {}

  @override
  Future<void> stopObserving() async {}
}

final class _DemoNotificationRepository implements NotificationRepository {
  const _DemoNotificationRepository();

  @override
  Future<NotificationPermissionStatus> configure(String householdId) async =>
      NotificationPermissionStatus.authorized;

  @override
  Future<NotificationPermissionStatus> requestPermission(
    String householdId,
  ) async => NotificationPermissionStatus.authorized;

  @override
  Future<void> openSettings() async {}

  @override
  Future<void> disable() async {}

  @override
  Future<void> stop() async {}
}

final class _DemoHealthRepository implements HealthRepository {
  _DemoHealthRepository(DateTime now)
    : snapshot = HealthSnapshot([
        HealthRecord(
          id: 'demo-luna-daily',
          petId: 'pet-luna',
          petNameSnapshot: 'Luna',
          type: HealthRecordType.dailyCheckIn,
          recordedAt: now.subtract(const Duration(minutes: 20)),
          detail: '朝は落ち着いて過ごしている。',
          weightKilograms: null,
          waterMilliliters: 180,
          dailyCheckIn: const DailyHealthCheckIn(
            water: DailyHealthLevel.usual,
            appetite: DailyHealthLevel.usual,
            urination: DailyHealthLevel.usual,
            stool: DailyHealthStatus.usual,
            energy: DailyHealthLevel.usual,
            mood: DailyHealthStatus.usual,
          ),
          createdById: 'demo-alex',
          createdByNameSnapshot: 'Alex',
          createdAt: now.subtract(const Duration(minutes: 20)),
        ),
        HealthRecord(
          id: 'demo-weight',
          petId: 'pet-mochi',
          petNameSnapshot: 'Mochi',
          type: HealthRecordType.weight,
          recordedAt: now.subtract(const Duration(days: 7)),
          detail: null,
          weightKilograms: 8.4,
          createdById: 'demo-alex',
          createdByNameSnapshot: 'Alex',
          createdAt: now.subtract(const Duration(days: 7)),
        ),
        HealthRecord(
          id: 'demo-note',
          petId: 'pet-mochi',
          petNameSnapshot: 'Mochi',
          type: HealthRecordType.note,
          recordedAt: now.subtract(const Duration(days: 1)),
          detail: '元気に遊び、食欲も普段どおり。',
          weightKilograms: null,
          createdById: 'demo-maya',
          createdByNameSnapshot: 'Maya',
          createdAt: now.subtract(const Duration(days: 1)),
        ),
        HealthRecord(
          id: 'demo-luna-appetite',
          petId: 'pet-luna',
          petNameSnapshot: 'Luna',
          type: HealthRecordType.appetite,
          recordedAt: now.subtract(const Duration(hours: 4)),
          detail: '朝ごはんを完食し、飲水も普段どおり。',
          weightKilograms: null,
          createdById: 'demo-alex',
          createdByNameSnapshot: 'Alex',
          createdAt: now.subtract(const Duration(hours: 4)),
        ),
        HealthRecord(
          id: 'demo-water',
          petId: 'pet-mochi',
          petNameSnapshot: 'Mochi',
          type: HealthRecordType.waterIntake,
          recordedAt: now.subtract(const Duration(hours: 6)),
          detail: '朝から夕方までの合計',
          weightKilograms: null,
          waterMilliliters: 420,
          createdById: 'demo-alex',
          createdByNameSnapshot: 'Alex',
          createdAt: now.subtract(const Duration(hours: 6)),
        ),
        HealthRecord(
          id: 'demo-visit',
          petId: 'pet-luna',
          petNameSnapshot: 'Luna',
          type: HealthRecordType.visit,
          recordedAt: now.subtract(const Duration(days: 3)),
          detail: '左目を診察。点眼液を処方。1日1回、赤みが続く場合は再診。',
          weightKilograms: null,
          createdById: 'demo-maya',
          createdByNameSnapshot: 'Maya',
          createdAt: now.subtract(const Duration(days: 3)),
        ),
      ]);

  final HealthSnapshot snapshot;

  @override
  Stream<HealthSnapshot> observeHealth(String householdId) =>
      Stream.value(snapshot);

  @override
  Future<void> createRecord({
    required String householdId,
    required String petId,
    required String petName,
    required HealthRecordType type,
    required DateTime recordedAt,
    required String timeZoneIdentifier,
    required String? detail,
    required double? weightKilograms,
    double? waterMilliliters,
    DailyHealthCheckIn? dailyCheckIn,
    required String createdById,
    required String createdByName,
  }) async {}

  @override
  Future<void> stopObserving() async {}
}

final class _DemoHandoffRepository implements HandoffRepository {
  _DemoHandoffRepository(DateTime now)
    : snapshot = HandoffSnapshot(
        handoff: HouseholdHandoff(
          careInstructions: '食事は8時と18時。夕食後に短い散歩をする。',
          emergencyContactName: 'Maya',
          emergencyContactPhone: '000-0000-0000',
          veterinaryHospitalName: 'CoPaw動物病院',
          veterinaryHospitalPhone: '000-0000-0000',
          revision: 1,
          updatedById: 'demo-maya',
          updatedByNameSnapshot: 'Maya',
          updatedAt: now.subtract(const Duration(hours: 3)),
        ),
        isFromCache: false,
        hasPendingWrites: false,
      );

  final HandoffSnapshot snapshot;

  @override
  Stream<HandoffSnapshot> observeHandoff(String householdId) =>
      Stream.value(snapshot);

  @override
  Future<void> saveHandoff({
    required String householdId,
    required int? expectedRevision,
    required String careInstructions,
    required String emergencyContactName,
    required String emergencyContactPhone,
    required String veterinaryHospitalName,
    required String veterinaryHospitalPhone,
    required String updatedById,
    required String updatedByName,
  }) async {}

  @override
  Future<void> stopObserving() async {}
}

final class _DemoReportShareRepository implements ReportShareRepository {
  const _DemoReportShareRepository();

  @override
  Future<void> sharePdf({
    required PetCareReport report,
    required AppLocale locale,
    required Rect sharePositionOrigin,
  }) async {}
}

final class _DemoTimeZoneRepository implements LocalTimeZoneRepository {
  const _DemoTimeZoneRepository();

  @override
  Future<String> loadIdentifier() async => 'Asia/Tokyo';
}
