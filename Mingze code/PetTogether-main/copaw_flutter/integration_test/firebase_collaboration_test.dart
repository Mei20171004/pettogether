import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:copaw_flutter/src/data/active_household_store.dart';
import 'package:copaw_flutter/src/data/care_task_mutation_gateway.dart';
import 'package:copaw_flutter/src/data/care_task_mutation_repository.dart';
import 'package:copaw_flutter/src/data/firebase_care_task_gateway.dart';
import 'package:copaw_flutter/src/data/firebase_care_task_mutation_gateway.dart';
import 'package:copaw_flutter/src/data/firebase_care_task_mutation_repository.dart';
import 'package:copaw_flutter/src/data/firebase_care_task_repository.dart';
import 'package:copaw_flutter/src/data/firebase_collaboration_event_gateway.dart';
import 'package:copaw_flutter/src/data/firebase_collaboration_event_repository.dart';
import 'package:copaw_flutter/src/data/firebase_household_data_gateway.dart';
import 'package:copaw_flutter/src/data/firebase_household_repository.dart';
import 'package:copaw_flutter/src/data/firebase_health_repository.dart';
import 'package:copaw_flutter/src/data/firebase_health_gateway.dart';
import 'package:copaw_flutter/src/data/firebase_handoff_repository.dart';
import 'package:copaw_flutter/src/data/firebase_handoff_gateway.dart';
import 'package:copaw_flutter/src/data/handoff_repository.dart';
import 'package:copaw_flutter/src/data/firebase_medication_gateway.dart';
import 'package:copaw_flutter/src/data/firebase_medication_repository.dart';
import 'package:copaw_flutter/src/data/household_data_gateway.dart';
import 'package:copaw_flutter/src/data/medication_repository.dart';
import 'package:copaw_flutter/src/domain/medication_models.dart';
import 'package:copaw_flutter/src/domain/health_models.dart';
import 'package:copaw_flutter/src/domain/collaboration_event_models.dart';
import 'package:copaw_flutter/src/domain/medication_occurrence_service.dart';
import 'package:copaw_flutter/src/domain/models.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:timezone/data/latest.dart' as time_zone_data;
import 'package:timezone/timezone.dart' as time_zone;

const _demoOptions = FirebaseOptions(
  apiKey: 'AIzaSyAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
  appId: '1:1234567890:android:demo',
  messagingSenderId: '1234567890',
  projectId: 'demo-copaw',
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'real Dart Firebase SDK creates, joins, claims, and completes through Rules',
    (tester) async {
      final originalFlutterError = FlutterError.onError;
      FlutterError.onError = (details) {
        final exception = details.exception;
        if (exception is MissingPluginException &&
            exception.toString().contains('firebase_firestore/transaction') &&
            exception.toString().contains('method cancel')) {
          return;
        }
        originalFlutterError?.call(details);
      };
      addTearDown(() => FlutterError.onError = originalFlutterError);

      await Firebase.initializeApp(options: _demoOptions);
      final auth = FirebaseAuth.instance;
      final firestore = FirebaseFirestore.instance;
      final emulatorHost = Platform.isAndroid ? '10.0.2.2' : '127.0.0.1';
      await auth.useAuthEmulator(emulatorHost, 9099);
      firestore.useFirestoreEmulator(emulatorHost, 8080);
      firestore.settings = const Settings(persistenceEnabled: false);
      final functions = FirebaseFunctions.instanceFor(
        region: 'asia-northeast1',
      );
      functions.useFunctionsEmulator(emulatorHost, 5001);
      await auth.signInAnonymously();

      final ownerRepository = FirebaseHouseholdRepository(
        gateway: FirebaseHouseholdDataGateway(auth: auth, firestore: firestore),
        activeHouseholdStore: _MemoryActiveHouseholdStore(),
        pendingHouseholdStore: _MemoryPendingHouseholdStore(),
        inviteCodeGenerator: _FixedInviteCodeGenerator('ABC234'),
      );
      final owner = await ownerRepository.createHousehold(
        householdName: 'Emulator Home',
        petName: 'Mochi',
        caregiverName: 'Owner',
        timeZoneIdentifier: 'Asia/Tokyo',
      );
      expect(owner.household.inviteCode, 'ABC234');
      final firstPet = await firestore
          .collection('households')
          .doc(owner.household.id)
          .collection('pets')
          .doc(legacyPrimaryPetId)
          .get();
      expect(firstPet.data()?['name'], 'Mochi');
      expect(firstPet.data()?['isArchived'], false);

      await auth.signOut();
      final joinerRepository = FirebaseHouseholdRepository(
        gateway: FirebaseHouseholdDataGateway(auth: auth, firestore: firestore),
        activeHouseholdStore: _MemoryActiveHouseholdStore(),
        pendingHouseholdStore: _MemoryPendingHouseholdStore(),
      );
      final joiner = await joinerRepository.joinHousehold(
        inviteCode: owner.household.inviteCode,
        caregiverName: 'Joiner',
      );
      expect(joiner.household.id, owner.household.id);
      expect(joiner.caregiver.id, isNot(owner.caregiver.id));

      final secondApp = await Firebase.initializeApp(
        name: 'second-caregiver',
        options: _demoOptions,
      );
      final secondAuth = FirebaseAuth.instanceFor(app: secondApp);
      final secondFirestore = FirebaseFirestore.instanceFor(app: secondApp);
      final secondFunctions = FirebaseFunctions.instanceFor(
        app: secondApp,
        region: 'asia-northeast1',
      )..useFunctionsEmulator(emulatorHost, 5001);
      await secondAuth.useAuthEmulator(emulatorHost, 9099);
      secondFirestore.useFirestoreEmulator(emulatorHost, 8080);
      secondFirestore.settings = const Settings(persistenceEnabled: false);
      final secondRepository = FirebaseHouseholdRepository(
        gateway: FirebaseHouseholdDataGateway(
          auth: secondAuth,
          firestore: secondFirestore,
        ),
        activeHouseholdStore: _MemoryActiveHouseholdStore(),
        pendingHouseholdStore: _MemoryPendingHouseholdStore(),
      );
      final secondCaregiver = await secondRepository.joinHousehold(
        inviteCode: owner.household.inviteCode,
        caregiverName: 'Second',
      );

      final taskRepository = FirebaseCareTaskRepository(
        gateway: FirebaseCareTaskGateway(firestore: firestore),
      );
      time_zone_data.initializeTimeZones();
      final tokyo = time_zone.getLocation('Asia/Tokyo');
      final selectedDay = time_zone.TZDateTime.now(tokyo);
      final localDate =
          '${selectedDay.year.toString().padLeft(4, '0')}-'
          '${selectedDay.month.toString().padLeft(2, '0')}-'
          '${selectedDay.day.toString().padLeft(2, '0')}';
      final routineId = await taskRepository.createRoutine(
        householdId: owner.household.id,
        title: 'Morning meal',
        category: CareCategory.feeding,
        priority: CarePriority.normal,
        frequency: CareRoutineFrequency.daily,
        weekdays: const [1, 2, 3, 4, 5, 6, 7],
        hour: 8,
        minute: 0,
        startDate: selectedDay.toUtc(),
        timeZoneIdentifier: 'Asia/Tokyo',
        createdById: joiner.caregiver.id,
        createdByName: joiner.caregiver.displayName,
      );
      try {
        await functions.httpsCallable('mutateRoutineOccurrence').call({
          'householdID': owner.household.id,
          'routineID': routineId,
          'localDate': 'not-a-date',
          'action': 'claim',
        });
        fail('The callable must reject a non-canonical local date.');
      } on FirebaseFunctionsException catch (error) {
        if (error.code != 'invalid-argument') {
          fail(
            'Functions emulator error: code=${error.code}, '
            'message=${error.message}, details=${error.details}',
          );
        }
      }
      final mutationRepository = FirebaseCareTaskMutationRepository(
        gateway: FirebaseCareTaskMutationGateway(
          firestore: firestore,
          functions: functions,
        ),
        idGenerator: _FixedMutationIdGenerator(),
      );
      final virtualOccurrence = CareTask(
        id: '${routineId}_$localDate',
        title: 'Morning meal',
        category: CareCategory.feeding,
        dueTime: time_zone.TZDateTime(
          tokyo,
          selectedDay.year,
          selectedDay.month,
          selectedDay.day,
          8,
        ).toUtc(),
        kind: CareTaskKind.routine,
        priority: CarePriority.normal,
        routineId: routineId,
        status: CareTaskStatus.unclaimed,
        assignmentRequest: null,
        assigneeId: null,
        assigneeNameSnapshot: null,
        claimedAt: null,
        createdById: joiner.caregiver.id,
        createdBy: joiner.caregiver.displayName,
        createdAt: DateTime.now().toUtc(),
        completedById: null,
        completedBy: null,
        completedAt: null,
        revision: 0,
        petId: legacyPrimaryPetId,
        petNameSnapshot: 'Mochi',
      );
      await mutationRepository.claim(
        householdId: owner.household.id,
        taskId: virtualOccurrence.id,
        actorId: joiner.caregiver.id,
        taskIfMissing: virtualOccurrence,
      );
      final materializedOccurrence = await firestore
          .collection('households')
          .doc(owner.household.id)
          .collection('tasks')
          .doc(virtualOccurrence.id)
          .get();
      expect(materializedOccurrence.data()?['kind'], 'routine');
      expect(materializedOccurrence.data()?['revision'], 1);
      expect(materializedOccurrence.data()?['petID'], legacyPrimaryPetId);
      expect(materializedOccurrence.data()?['petName'], 'Mochi');

      final taskId = await taskRepository.createOneOffTask(
        householdId: owner.household.id,
        title: 'Evening walk',
        category: CareCategory.walking,
        dueTime: DateTime.now().toUtc(),
        priority: CarePriority.normal,
        createdById: joiner.caregiver.id,
        createdByName: joiner.caregiver.displayName,
      );

      await mutationRepository.claim(
        householdId: owner.household.id,
        taskId: taskId,
        actorId: joiner.caregiver.id,
      );
      var task = await firestore
          .collection('households')
          .doc(owner.household.id)
          .collection('tasks')
          .doc(taskId)
          .get();
      expect(task.data()?['status'], 'claimed');
      expect(task.data()?['assigneeID'], joiner.caregiver.id);
      expect(task.data()?['revision'], 1);
      expect(task.data()?['claimedAt'], isA<Timestamp>());

      final firstCollaborationRepository = FirebaseCollaborationEventRepository(
        gateway: FirebaseCollaborationEventGateway(firestore: firestore),
      );
      final secondCollaborationRepository =
          FirebaseCollaborationEventRepository(
            gateway: FirebaseCollaborationEventGateway(
              firestore: secondFirestore,
            ),
          );
      final firstUpdatesConvergence = firstCollaborationRepository
          .observeRecent(owner.household.id)
          .firstWhere(
            (snapshot) => snapshot.events.any(
              (event) =>
                  event.sourceId == taskId &&
                  event.action == CollaborationEventAction.taskCompleted,
            ),
          )
          .timeout(const Duration(seconds: 10));
      final secondUpdatesConvergence = secondCollaborationRepository
          .observeRecent(owner.household.id)
          .firstWhere(
            (snapshot) => snapshot.events.any(
              (event) =>
                  event.sourceId == taskId &&
                  event.action == CollaborationEventAction.taskCompleted,
            ),
          )
          .timeout(const Duration(seconds: 10));
      await mutationRepository.complete(
        householdId: owner.household.id,
        taskId: taskId,
        actorId: joiner.caregiver.id,
      );
      task = await firestore
          .collection('households')
          .doc(owner.household.id)
          .collection('tasks')
          .doc(taskId)
          .get();
      expect(task.data()?['status'], 'completed');
      expect(task.data()?['completedByID'], joiner.caregiver.id);
      expect(task.data()?['revision'], 2);
      expect(task.data()?['completedAt'], isA<Timestamp>());
      expect(task.data()?['petID'], legacyPrimaryPetId);
      expect(task.data()?['petName'], 'Mochi');

      final updateSnapshots = await Future.wait([
        firstUpdatesConvergence,
        secondUpdatesConvergence,
      ]);
      for (final snapshot in updateSnapshots) {
        expect(snapshot.isPotentiallyIncomplete, true);
        expect(
          snapshot.events
              .where((event) => event.sourceId == taskId)
              .map((event) => event.action),
          containsAll([
            CollaborationEventAction.taskCreated,
            CollaborationEventAction.taskClaimed,
            CollaborationEventAction.taskCompleted,
          ]),
        );
      }
      final completedEvent = updateSnapshots.first.events.singleWhere(
        (event) =>
            event.sourceId == taskId &&
            event.action == CollaborationEventAction.taskCompleted,
      );
      final claimedEvent = updateSnapshots.first.events.singleWhere(
        (event) =>
            event.sourceId == taskId &&
            event.action == CollaborationEventAction.taskClaimed,
      );
      final completedCursor = CollaborationReadCursor(
        occurredAt: completedEvent.occurredAt,
        eventId: completedEvent.id,
      );
      final claimedCursor = CollaborationReadCursor(
        occurredAt: claimedEvent.occurredAt,
        eventId: claimedEvent.id,
      );
      final firstReadConvergence = firstCollaborationRepository
          .observeReadCursor(owner.household.id, joiner.caregiver.id)
          .firstWhere(
            (snapshot) => snapshot.cursor?.eventId == completedEvent.id,
          )
          .timeout(const Duration(seconds: 10));
      expect(
        (await secondCollaborationRepository
                .observeReadCursor(
                  owner.household.id,
                  secondCaregiver.caregiver.id,
                )
                .first)
            .cursor,
        isNull,
      );
      await firstCollaborationRepository.markRead(
        owner.household.id,
        joiner.caregiver.id,
        completedCursor,
      );
      expect((await firstReadConvergence).cursor?.eventId, completedEvent.id);
      final secondReadConvergence = secondCollaborationRepository
          .observeReadCursor(owner.household.id, secondCaregiver.caregiver.id)
          .firstWhere((snapshot) => snapshot.cursor?.eventId == claimedEvent.id)
          .timeout(const Duration(seconds: 10));
      await secondCollaborationRepository.markRead(
        owner.household.id,
        secondCaregiver.caregiver.id,
        claimedCursor,
      );
      expect((await secondReadConvergence).cursor?.eventId, claimedEvent.id);

      final conflictTaskId = await taskRepository.createOneOffTask(
        householdId: owner.household.id,
        title: 'Concurrent walk',
        category: CareCategory.walking,
        dueTime: DateTime.now().toUtc(),
        priority: CarePriority.normal,
        createdById: joiner.caregiver.id,
        createdByName: joiner.caregiver.displayName,
      );
      final secondMutationRepository = FirebaseCareTaskMutationRepository(
        gateway: FirebaseCareTaskMutationGateway(
          firestore: secondFirestore,
          functions: FirebaseFunctions.instanceFor(
            app: secondApp,
            region: 'asia-northeast1',
          )..useFunctionsEmulator(emulatorHost, 5001),
        ),
      );
      final secondTaskRepository = FirebaseCareTaskRepository(
        gateway: FirebaseCareTaskGateway(firestore: secondFirestore),
      );
      final firstClientConvergence = taskRepository
          .observeCare(owner.household.id)
          .firstWhere(
            (snapshot) => snapshot.tasks.any(
              (task) =>
                  task.id == conflictTaskId &&
                  task.status == CareTaskStatus.claimed,
            ),
          )
          .timeout(const Duration(seconds: 10));
      final secondClientConvergence = secondTaskRepository
          .observeCare(owner.household.id)
          .firstWhere(
            (snapshot) => snapshot.tasks.any(
              (task) =>
                  task.id == conflictTaskId &&
                  task.status == CareTaskStatus.claimed,
            ),
          )
          .timeout(const Duration(seconds: 10));
      final conflictResults = await Future.wait([
        _captureMutation(
          mutationRepository.claim(
            householdId: owner.household.id,
            taskId: conflictTaskId,
            actorId: joiner.caregiver.id,
          ),
        ),
        _captureMutation(
          secondMutationRepository.claim(
            householdId: owner.household.id,
            taskId: conflictTaskId,
            actorId: secondCaregiver.caregiver.id,
          ),
        ),
      ]);
      expect(conflictResults.where((result) => result == null), hasLength(1));
      expect(
        conflictResults.whereType<CareTaskMutationException>().single.code,
        CareTaskMutationErrorCode.permission,
      );
      final conflictTask = await firestore
          .collection('households')
          .doc(owner.household.id)
          .collection('tasks')
          .doc(conflictTaskId)
          .get();
      expect(conflictTask.data()?['revision'], 1);
      expect(
        conflictTask.data()?['assigneeID'],
        anyOf(joiner.caregiver.id, secondCaregiver.caregiver.id),
      );
      final convergedSnapshots = await Future.wait([
        firstClientConvergence,
        secondClientConvergence,
      ]);
      final winningAssignee = conflictTask.data()?['assigneeID'];
      for (final snapshot in convergedSnapshots) {
        final convergedTask = snapshot.tasks.singleWhere(
          (task) => task.id == conflictTaskId,
        );
        expect(convergedTask.revision, 1);
        expect(convergedTask.assigneeId, winningAssignee);
      }

      final medicationRepository = FirebaseMedicationRepository(
        gateway: FirebaseMedicationGateway(
          firestore: firestore,
          functions: functions,
        ),
      );
      final secondMedicationRepository = FirebaseMedicationRepository(
        gateway: FirebaseMedicationGateway(
          firestore: secondFirestore,
          functions: FirebaseFunctions.instanceFor(
            app: secondApp,
            region: 'asia-northeast1',
          )..useFunctionsEmulator(emulatorHost, 5001),
        ),
      );
      final medicationId = await medicationRepository.createPlan(
        householdId: owner.household.id,
        petId: legacyPrimaryPetId,
        medicationName: 'Tablet A',
        effectiveFromLocalDate: localDate,
        weekdays: const [1, 2, 3, 4, 5, 6, 7],
        slots: const [
          MedicationPlanSlotInput(hour: 0, minute: 0, doseText: '1 tablet'),
        ],
      );
      final initialMedication = await medicationRepository
          .observeMedication(owner.household.id)
          .firstWhere(
            (snapshot) =>
                snapshot.isServerConfirmed &&
                snapshot.medications.any((item) => item.id == medicationId),
          )
          .timeout(const Duration(seconds: 10));
      final planned = MedicationOccurrenceService().forDay(
        selectedInstant: selectedDay,
        schedules: initialMedication.schedules.where(
          (item) => item.medicationId == medicationId,
        ),
        persisted: initialMedication.occurrences,
      );
      expect(planned, hasLength(1));
      final dose = planned.single;
      final firstMedicationConvergence = medicationRepository
          .observeMedication(owner.household.id)
          .firstWhere(
            (snapshot) => snapshot.occurrences.any(
              (item) =>
                  item.id == dose.id &&
                  item.isServerConfirmed &&
                  item.outcomeStatus != MedicationOutcomeStatus.unresolved,
            ),
          )
          .timeout(const Duration(seconds: 10));
      final secondMedicationConvergence = secondMedicationRepository
          .observeMedication(owner.household.id)
          .firstWhere(
            (snapshot) => snapshot.occurrences.any(
              (item) =>
                  item.id == dose.id &&
                  item.isServerConfirmed &&
                  item.outcomeStatus != MedicationOutcomeStatus.unresolved,
            ),
          )
          .timeout(const Duration(seconds: 10));
      final medicationConflict = await Future.wait([
        _captureMedicationMutation(
          medicationRepository.administer(
            householdId: owner.household.id,
            occurrence: dose,
          ),
        ),
        _captureMedicationMutation(
          secondMedicationRepository.skip(
            householdId: owner.household.id,
            occurrence: dose,
            reasonCode: MedicationSkipReasonCode.petRefused,
          ),
        ),
      ]);
      expect(
        medicationConflict.where((result) => result == null),
        hasLength(1),
      );
      expect(
        medicationConflict
            .whereType<MedicationRepositoryException>()
            .single
            .code,
        MedicationRepositoryErrorCode.terminalConflict,
      );
      final medicationSnapshots = await Future.wait([
        firstMedicationConvergence,
        secondMedicationConvergence,
      ]);
      final winner = medicationSnapshots.first.occurrences.singleWhere(
        (item) => item.id == dose.id,
      );
      for (final snapshot in medicationSnapshots) {
        final converged = snapshot.occurrences.singleWhere(
          (item) => item.id == dose.id,
        );
        expect(converged.outcomeStatus, winner.outcomeStatus);
        expect(converged.outcomeById, winner.outcomeById);
        expect(converged.outcomeAt, winner.outcomeAt);
        expect(converged.revision, 1);
      }

      final medication = medicationSnapshots.first.medications.singleWhere(
        (item) => item.id == medicationId,
      );
      final tomorrow = time_zone.TZDateTime(
        tokyo,
        selectedDay.year,
        selectedDay.month,
        selectedDay.day + 1,
      );
      final tomorrowDate =
          '${tomorrow.year.toString().padLeft(4, '0')}-'
          '${tomorrow.month.toString().padLeft(2, '0')}-'
          '${tomorrow.day.toString().padLeft(2, '0')}';
      await medicationRepository.replacePlan(
        householdId: owner.household.id,
        medication: medication,
        medicationName: 'Tablet B',
        effectiveFromLocalDate: tomorrowDate,
        weekdays: const [1, 2, 3, 4, 5, 6, 7],
        slots: const [
          MedicationPlanSlotInput(hour: 9, minute: 30, doseText: '2 tablets'),
        ],
      );
      final historical = await firestore
          .collection('households')
          .doc(owner.household.id)
          .collection('medicationOccurrences')
          .doc(dose.id)
          .get();
      expect(historical.data()?['medicationName'], 'Tablet A');
      expect(historical.data()?['doseText'], '1 tablet');
      expect(historical.data()?['outcomeStatus'], winner.outcomeStatus.name);

      final healthRepository = FirebaseHealthRepository(
        gateway: FirebaseHealthGateway(
          firestore: firestore,
          functions: functions,
        ),
      );
      final secondHealthRepository = FirebaseHealthRepository(
        gateway: FirebaseHealthGateway(
          firestore: secondFirestore,
          functions: secondFunctions,
        ),
      );
      final handoffRepository = FirebaseHandoffRepository(
        gateway: FirebaseHandoffGateway(firestore: firestore),
      );
      final secondHandoffRepository = FirebaseHandoffRepository(
        gateway: FirebaseHandoffGateway(firestore: secondFirestore),
      );
      final firstHandoffConvergence = handoffRepository
          .observeHandoff(owner.household.id)
          .firstWhere((snapshot) => snapshot.handoff?.revision == 2)
          .timeout(const Duration(seconds: 10));
      final secondHandoffConvergence = secondHandoffRepository
          .observeHandoff(owner.household.id)
          .firstWhere((snapshot) => snapshot.handoff?.revision == 2)
          .timeout(const Duration(seconds: 10));
      await handoffRepository.saveHandoff(
        householdId: owner.household.id,
        expectedRevision: null,
        careInstructions: 'Dinner at 18:00',
        emergencyContactName: 'Joiner',
        emergencyContactPhone: '090-0000-0000',
        veterinaryHospitalName: 'Central Animal Hospital',
        veterinaryHospitalPhone: '03-0000-0000',
        updatedById: joiner.caregiver.id,
        updatedByName: joiner.caregiver.displayName,
      );
      await secondHandoffRepository.saveHandoff(
        householdId: owner.household.id,
        expectedRevision: 1,
        careInstructions: 'Dinner at 18:30',
        emergencyContactName: 'Second',
        emergencyContactPhone: '090-1111-1111',
        veterinaryHospitalName: 'Central Animal Hospital',
        veterinaryHospitalPhone: '03-0000-0000',
        updatedById: secondCaregiver.caregiver.id,
        updatedByName: secondCaregiver.caregiver.displayName,
      );
      final staleHandoff = await _captureHandoffMutation(
        handoffRepository.saveHandoff(
          householdId: owner.household.id,
          expectedRevision: 1,
          careInstructions: 'Stale overwrite',
          emergencyContactName: 'Joiner',
          emergencyContactPhone: '',
          veterinaryHospitalName: '',
          veterinaryHospitalPhone: '',
          updatedById: joiner.caregiver.id,
          updatedByName: joiner.caregiver.displayName,
        ),
      );
      expect(
        staleHandoff,
        isA<HandoffRepositoryException>().having(
          (error) => error.code,
          'code',
          HandoffRepositoryErrorCode.conflict,
        ),
      );
      for (final snapshot in await Future.wait([
        firstHandoffConvergence,
        secondHandoffConvergence,
      ])) {
        expect(snapshot.handoff?.careInstructions, 'Dinner at 18:30');
        expect(snapshot.handoff?.updatedById, secondCaregiver.caregiver.id);
        expect(snapshot.handoff?.revision, 2);
      }
      final firstHealthConvergence = healthRepository
          .observeHealth(owner.household.id)
          .firstWhere((snapshot) => snapshot.records.length == 2)
          .timeout(const Duration(seconds: 10));
      final secondHealthConvergence = secondHealthRepository
          .observeHealth(owner.household.id)
          .firstWhere((snapshot) => snapshot.records.length == 2)
          .timeout(const Duration(seconds: 10));
      await firestore
          .collection('households')
          .doc(owner.household.id)
          .collection('pets')
          .doc('pet-nori')
          .set({
            'id': 'pet-nori',
            'name': 'Nori',
            'species': 'cat',
            'isArchived': false,
            'createdAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          });
      await healthRepository.createRecord(
        householdId: owner.household.id,
        petId: legacyPrimaryPetId,
        petName: 'Mochi',
        type: HealthRecordType.weight,
        recordedAt: DateTime.now().toUtc(),
        timeZoneIdentifier: owner.household.timeZoneIdentifier!,
        detail: 'Routine measurement',
        weightKilograms: 4.2,
        createdById: joiner.caregiver.id,
        createdByName: joiner.caregiver.displayName,
      );
      await secondHealthRepository.createRecord(
        householdId: owner.household.id,
        petId: 'pet-nori',
        petName: 'Nori',
        type: HealthRecordType.note,
        recordedAt: DateTime.now().toUtc(),
        timeZoneIdentifier: owner.household.timeZoneIdentifier!,
        detail: 'Nori observation',
        weightKilograms: null,
        createdById: secondCaregiver.caregiver.id,
        createdByName: secondCaregiver.caregiver.displayName,
      );
      final healthSnapshots = await Future.wait([
        firstHealthConvergence,
        secondHealthConvergence,
      ]);
      for (final snapshot in healthSnapshots) {
        final mochi = snapshot.records.singleWhere(
          (record) => record.petId == legacyPrimaryPetId,
        );
        final nori = snapshot.records.singleWhere(
          (record) => record.petId == 'pet-nori',
        );
        expect(mochi.petNameSnapshot, 'Mochi');
        expect(mochi.type, HealthRecordType.weight);
        expect(mochi.weightKilograms, 4.2);
        expect(nori.petNameSnapshot, 'Nori');
        expect(nori.type, HealthRecordType.note);
        expect(nori.detail, 'Nori observation');
        expect(mochi.createdById, joiner.caregiver.id);
        expect(nori.createdById, secondCaregiver.caregiver.id);
        expect(mochi.createdAt, isA<DateTime>());
      }

      final firstDailyConvergence = healthRepository
          .observeHealth(owner.household.id)
          .firstWhere((snapshot) => snapshot.records.length == 3)
          .timeout(const Duration(seconds: 10));
      final secondDailyConvergence = secondHealthRepository
          .observeHealth(owner.household.id)
          .firstWhere((snapshot) => snapshot.records.length == 3)
          .timeout(const Duration(seconds: 10));
      const daily = DailyHealthCheckIn(
        water: DailyHealthLevel.usual,
        appetite: DailyHealthLevel.usual,
        urination: DailyHealthLevel.usual,
        stool: DailyHealthStatus.usual,
        energy: DailyHealthLevel.usual,
        mood: DailyHealthStatus.usual,
      );
      await Future.wait([
        healthRepository.createRecord(
          householdId: owner.household.id,
          petId: legacyPrimaryPetId,
          petName: 'Mochi',
          type: HealthRecordType.dailyCheckIn,
          recordedAt: DateTime.now().toUtc(),
          timeZoneIdentifier: owner.household.timeZoneIdentifier!,
          detail: 'Shared daily fixture',
          weightKilograms: null,
          waterMilliliters: 120,
          dailyCheckIn: daily,
          createdById: joiner.caregiver.id,
          createdByName: joiner.caregiver.displayName,
        ),
        secondHealthRepository.createRecord(
          householdId: owner.household.id,
          petId: legacyPrimaryPetId,
          petName: 'Mochi',
          type: HealthRecordType.dailyCheckIn,
          recordedAt: DateTime.now().toUtc(),
          timeZoneIdentifier: owner.household.timeZoneIdentifier!,
          detail: 'Shared daily fixture',
          weightKilograms: null,
          waterMilliliters: 120,
          dailyCheckIn: daily,
          createdById: secondCaregiver.caregiver.id,
          createdByName: secondCaregiver.caregiver.displayName,
        ),
      ]);
      for (final snapshot in await Future.wait([
        firstDailyConvergence,
        secondDailyConvergence,
      ])) {
        final dailyRecords = snapshot.records
            .where((record) => record.type == HealthRecordType.dailyCheckIn)
            .toList(growable: false);
        expect(dailyRecords, hasLength(1));
        expect(dailyRecords.single.recordedLocalDate, isNotNull);
        expect(
          dailyRecords.single.waterMeasurementBasis,
          WaterMeasurementBasis.localDayToDate,
        );
      }

      await taskRepository.stopObserving();
      await secondTaskRepository.stopObserving();
      await medicationRepository.stopObserving();
      await secondMedicationRepository.stopObserving();
      await healthRepository.stopObserving();
      await secondHealthRepository.stopObserving();
      await handoffRepository.stopObserving();
      await secondHandoffRepository.stopObserving();
      await firstCollaborationRepository.stopObserving();
      await secondCollaborationRepository.stopObserving();
      await secondApp.delete();
    },
  );
}

Future<Object?> _captureMutation(Future<void> action) async {
  try {
    await action;
    return null;
  } on Object catch (error) {
    return error;
  }
}

Future<Object?> _captureMedicationMutation(Future<void> action) async {
  try {
    await action;
    return null;
  } on Object catch (error) {
    return error;
  }
}

Future<Object?> _captureHandoffMutation(Future<void> action) async {
  try {
    await action;
    return null;
  } on Object catch (error) {
    return error;
  }
}

final class _MemoryActiveHouseholdStore implements ActiveHouseholdStore {
  String? value;

  @override
  Future<void> clear() async => value = null;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> save(String householdId) async => value = householdId;
}

final class _MemoryPendingHouseholdStore implements PendingHouseholdStore {
  PendingHouseholdMarker? value;

  @override
  Future<void> clear() async => value = null;

  @override
  Future<PendingHouseholdMarker?> read() async => value;

  @override
  Future<void> save(PendingHouseholdMarker marker) async => value = marker;
}

final class _FixedInviteCodeGenerator implements InviteCodeGenerator {
  const _FixedInviteCodeGenerator(this.value);

  final String value;

  @override
  String next() => value;
}

final class _FixedMutationIdGenerator implements MutationIdGenerator {
  @override
  String next() => 'request-emulator';
}
