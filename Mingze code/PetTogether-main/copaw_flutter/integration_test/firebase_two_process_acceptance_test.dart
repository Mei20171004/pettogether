import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:copaw_flutter/src/bootstrap/firebase_emulator_configuration.dart';
import 'package:copaw_flutter/src/data/firebase_care_task_gateway.dart';
import 'package:copaw_flutter/src/data/firebase_care_task_mutation_gateway.dart';
import 'package:copaw_flutter/src/data/firebase_care_task_mutation_repository.dart';
import 'package:copaw_flutter/src/data/firebase_care_task_repository.dart';
import 'package:copaw_flutter/src/data/firebase_collaboration_event_gateway.dart';
import 'package:copaw_flutter/src/data/firebase_collaboration_event_repository.dart';
import 'package:copaw_flutter/src/data/firebase_handoff_gateway.dart';
import 'package:copaw_flutter/src/data/firebase_handoff_repository.dart';
import 'package:copaw_flutter/src/data/firebase_handoff_session_gateway.dart';
import 'package:copaw_flutter/src/data/firebase_handoff_session_repository.dart';
import 'package:copaw_flutter/src/data/firebase_household_data_gateway.dart';
import 'package:copaw_flutter/src/data/firebase_household_repository.dart';
import 'package:copaw_flutter/src/data/firebase_health_gateway.dart';
import 'package:copaw_flutter/src/data/firebase_health_repository.dart';
import 'package:copaw_flutter/src/data/firebase_medication_gateway.dart';
import 'package:copaw_flutter/src/data/firebase_medication_repository.dart';
import 'package:copaw_flutter/src/data/firebase_notification_center_gateway.dart';
import 'package:copaw_flutter/src/data/firebase_notification_center_repository.dart';
import 'package:copaw_flutter/src/data/firebase_task_responsibility_gateway.dart';
import 'package:copaw_flutter/src/data/firebase_task_responsibility_repository.dart';
import 'package:copaw_flutter/src/data/notification_interaction_repository.dart';
import 'package:copaw_flutter/src/data/household_data_gateway.dart';
import 'package:copaw_flutter/src/data/household_repository.dart';
import 'package:copaw_flutter/src/data/health_gateway.dart';
import 'package:copaw_flutter/src/data/health_mutation_store.dart';
import 'package:copaw_flutter/src/data/health_repository.dart';
import 'package:copaw_flutter/src/data/medication_gateway.dart';
import 'package:copaw_flutter/src/data/medication_mutation_store.dart';
import 'package:copaw_flutter/src/data/medication_repository.dart';
import 'package:copaw_flutter/src/domain/collaboration_event_models.dart';
import 'package:copaw_flutter/src/domain/handoff_models.dart';
import 'package:copaw_flutter/src/domain/health_models.dart';
import 'package:copaw_flutter/src/domain/models.dart';
import 'package:copaw_flutter/src/domain/medication_occurrence_service.dart';
import 'package:copaw_flutter/src/domain/notification_models.dart';
import 'package:copaw_flutter/src/domain/responsibility_models.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:timezone/data/latest.dart' as time_zone_data;
import 'package:timezone/timezone.dart' as time_zone;

const _role = String.fromEnvironment('COPAW_LT7_ROLE');
const _phase = String.fromEnvironment('COPAW_LT7_PHASE');
const _runId = String.fromEnvironment('COPAW_LT7_RUN_ID');
const _inviteCode = String.fromEnvironment('COPAW_LT7_INVITE_CODE');

// Static, content-free receipt contract checked before any coordinated run.
const _receiptContract = <String>[
  'checkpoint=identity',
  'checkpoint=lt2-daily waterBasis=localDayToDate',
  'checkpoint=lt4-events',
  'checkpoint=lt5-transfer',
  'checkpoint=lt5-handoff pinnedRevision=1 currentRevision=2',
  'checkpoint=lt6-inbox providerAttempts=0 deliveryCount=0 tokenCount=0',
  'checkpoint=offline-reconnect',
  'checkpoint=no-duplicates',
];

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('LT7 uses one clean persisted identity per OS process', (
    tester,
  ) async {
    _validateContract();
    await configureLocalFirebaseEmulators();
    final auth = FirebaseAuth.instance;
    final firestore = FirebaseFirestore.instance;
    final repository = FirebaseHouseholdRepository(
      gateway: FirebaseHouseholdDataGateway(auth: auth, firestore: firestore),
      inviteCodeGenerator: _FixedInviteCodeGenerator(_inviteCode),
    );

    final session = switch (_phase) {
      'bootstrap' => await _bootstrap(repository, auth),
      'reconnect' => await _reconnect(repository, auth),
      'source' || 'offline' => await _reconnect(repository, auth),
      _ => throw StateError('Unsupported LT7 phase'),
    };
    final members = await _serverConfirmedMembers(
      firestore,
      session.household.id,
    );
    expect(members.docs, hasLength(2));
    expect(
      members.docs.map((document) => document.id),
      contains(session.caregiver.id),
    );

    final protocolReceipts = switch (_phase) {
      'source' => await _runSourceProtocol(
        session: session,
        firestore: firestore,
        auth: auth,
      ),
      'offline' => await _runOfflineProtocol(
        session: session,
        firestore: firestore,
      ),
      _ => const <String>[],
    };
    final receipts = [
      _identityReceipt(session, members.docs.length),
      ...protocolReceipts,
    ];
    final receipt = receipts.join('\n');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: Semantics(
              label: 'LT7 $_role $_phase connected',
              child: Text(receipt),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text(receipt), findsOneWidget);
    for (final line in receipts) {
      debugPrint('LT7_RECEIPT $line');
    }
  });
}

Future<HouseholdSession> _bootstrap(
  FirebaseHouseholdRepository repository,
  FirebaseAuth auth,
) async {
  expect(await auth.authStateChanges().first, isNull);
  expect(await repository.restoreSession(), isNull);
  if (_role == 'A') {
    return repository.createHousehold(
      householdName: 'LT7 Home',
      petName: 'LT7 Pet',
      caregiverName: 'Caregiver A',
      timeZoneIdentifier: 'Asia/Tokyo',
    );
  }
  for (var attempt = 0; attempt < 60; attempt += 1) {
    try {
      return await repository.joinHousehold(
        inviteCode: _inviteCode,
        caregiverName: 'Caregiver B',
      );
    } on HouseholdRepositoryException catch (error) {
      if (error.code != HouseholdRepositoryErrorCode.invalidInviteCode) rethrow;
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
  }
  throw StateError('Client B could not observe the synthetic invite');
}

Future<HouseholdSession> _reconnect(
  FirebaseHouseholdRepository repository,
  FirebaseAuth auth,
) async {
  final user = await auth
      .authStateChanges()
      .firstWhere((candidate) => candidate != null)
      .timeout(const Duration(seconds: 15));
  final session = await repository.restoreSession();
  expect(session, isNotNull);
  expect(session!.caregiver.id, user!.uid);
  return session;
}

Future<List<String>> _runSourceProtocol({
  required HouseholdSession session,
  required FirebaseFirestore firestore,
  required FirebaseAuth auth,
}) async {
  final householdId = session.household.id;
  final memberJoinedAt = session.memberJoinedAt;
  final timeZoneIdentifier = session.household.timeZoneIdentifier;
  if (memberJoinedAt == null || timeZoneIdentifier == null) {
    throw StateError('LT7 source protocol requires authoritative membership');
  }
  final memberDocuments = await _serverConfirmedMembers(firestore, householdId);
  final peer = memberDocuments.docs.singleWhere(
    (document) => document.id != session.caregiver.id,
  );
  final functions = FirebaseFunctions.instanceFor(
    region: localFirebaseFunctionsRegion,
  );
  final notificationGateway = FirebaseNotificationCenterGateway(
    auth: auth,
    firestore: firestore,
    functions: functions,
  );
  final preferencesRepository = FirebaseNotificationPreferencesRepository(
    gateway: notificationGateway,
  );
  final conservative = HouseholdNotificationPreferences.conservative(
    uid: session.caregiver.id,
    householdId: householdId,
    memberJoinedAt: memberJoinedAt,
    timeZoneIdentifier: timeZoneIdentifier,
  );
  final preferenceResult = await preferencesRepository.save(
    conservative,
    clientMutationId: _mutationId('preferences-$_role'),
  );
  expect(preferenceResult.revision, 1);

  final healthRepository = FirebaseHealthRepository(
    gateway: FirebaseHealthGateway(firestore: firestore, functions: functions),
  );
  const daily = DailyHealthCheckIn(
    water: DailyHealthLevel.usual,
    appetite: DailyHealthLevel.usual,
    urination: DailyHealthLevel.usual,
    stool: DailyHealthStatus.usual,
    energy: DailyHealthLevel.usual,
    mood: DailyHealthStatus.usual,
  );
  await healthRepository.createRecord(
    householdId: householdId,
    petId: legacyPrimaryPetId,
    petName: session.household.petName,
    type: HealthRecordType.dailyCheckIn,
    recordedAt: DateTime.now().toUtc(),
    timeZoneIdentifier: timeZoneIdentifier,
    detail: null,
    weightKilograms: null,
    waterMilliliters: 120,
    dailyCheckIn: daily,
    createdById: session.caregiver.id,
    createdByName: session.caregiver.displayName,
  );
  final dailySnapshot = await healthRepository
      .observeHealth(householdId)
      .firstWhere(
        (snapshot) =>
            !snapshot.isFromCache &&
            snapshot.droppedRecordCount == 0 &&
            snapshot.records.any(
              (record) => record.type == HealthRecordType.dailyCheckIn,
            ),
      )
      .timeout(const Duration(seconds: 30));
  final dailyRecords = dailySnapshot.records
      .where((record) => record.type == HealthRecordType.dailyCheckIn)
      .toList(growable: false);
  expect(dailyRecords, hasLength(1));
  expect(dailyRecords.single.waterMilliliters, 120);
  expect(
    dailyRecords.single.waterMeasurementBasis,
    WaterMeasurementBasis.localDayToDate,
  );

  final sourceReceipts = _role == 'A'
      ? await _runSourceOwner(
          session: session,
          peerId: peer.id,
          firestore: firestore,
          functions: functions,
        )
      : await _runSourceRecipient(
          session: session,
          firestore: firestore,
          functions: functions,
          notificationGateway: notificationGateway,
          memberJoinedAt: memberJoinedAt,
        );

  await healthRepository.stopObserving();
  await preferencesRepository.stop();
  return [
    'checkpoint=lt2-daily role=$_role run=$_runId records=1 '
        'waterBasis=localDayToDate',
    ...sourceReceipts,
  ];
}

Future<List<String>> _runSourceOwner({
  required HouseholdSession session,
  required String peerId,
  required FirebaseFirestore firestore,
  required FirebaseFunctions functions,
}) async {
  final householdId = session.household.id;
  final taskRepository = FirebaseCareTaskRepository(
    gateway: FirebaseCareTaskGateway(firestore: firestore),
  );
  final mutationRepository = FirebaseCareTaskMutationRepository(
    gateway: FirebaseCareTaskMutationGateway(
      firestore: firestore,
      functions: functions,
    ),
  );
  final responsibilityRepository = FirebaseTaskResponsibilityRepository(
    gateway: FirebaseTaskResponsibilityGateway(
      firestore: firestore,
      functions: functions,
    ),
  );
  final handoffRepository = FirebaseHandoffRepository(
    gateway: FirebaseHandoffGateway(firestore: firestore),
  );
  final sessionRepository = FirebaseHandoffSessionRepository(
    gateway: FirebaseHandoffSessionGateway(
      firestore: firestore,
      functions: functions,
    ),
  );

  final taskId = await taskRepository.createOneOffTask(
    householdId: householdId,
    title: 'LT7 source $_runId',
    category: CareCategory.walking,
    dueTime: DateTime.now().toUtc(),
    priority: CarePriority.normal,
    createdById: session.caregiver.id,
    createdByName: session.caregiver.displayName,
  );
  await mutationRepository.claim(
    householdId: householdId,
    taskId: taskId,
    actorId: session.caregiver.id,
  );
  final transfer = await responsibilityRepository.requestReassign(
    householdId: householdId,
    taskId: taskId,
    targetMemberId: peerId,
    expectedTaskRevision: 1,
    clientMutationId: _mutationId('transfer-request'),
  );
  expect(transfer.transferStatus, ResponsibilityTransferStatus.pending);

  await handoffRepository.saveHandoff(
    householdId: householdId,
    expectedRevision: null,
    careInstructions: 'LT7 pinned version one',
    emergencyContactName: '',
    emergencyContactPhone: '',
    veterinaryHospitalName: '',
    veterinaryHospitalPhone: '',
    updatedById: session.caregiver.id,
    updatedByName: session.caregiver.displayName,
  );
  final offered = await sessionRepository.offer(
    householdId: householdId,
    recipientId: peerId,
    expectedHandoffRevision: 1,
    plannedStart: DateTime.now().toUtc().add(const Duration(minutes: 5)),
    plannedEnd: DateTime.now().toUtc().add(const Duration(hours: 6)),
    clientMutationId: _mutationId('handoff-offer'),
  );
  expect(offered.sessionStatus, HandoffSessionStatus.offered);
  await handoffRepository.saveHandoff(
    householdId: householdId,
    expectedRevision: 1,
    careInstructions: 'LT7 current version two',
    emergencyContactName: '',
    emergencyContactPhone: '',
    veterinaryHospitalName: '',
    veterinaryHospitalPhone: '',
    updatedById: session.caregiver.id,
    updatedByName: session.caregiver.displayName,
  );

  final acceptedTransfer = await firestore
      .collection('households')
      .doc(householdId)
      .collection('taskResponsibilityTransfers')
      .doc(transfer.transferId)
      .snapshots(includeMetadataChanges: true)
      .firstWhere(
        (snapshot) =>
            !snapshot.metadata.isFromCache &&
            !snapshot.metadata.hasPendingWrites &&
            snapshot.data()?['status'] == 'accepted',
      )
      .timeout(const Duration(seconds: 45));
  expect(acceptedTransfer.data()?['resultingTaskRevision'], 2);
  final acceptedSession = await firestore
      .collection('households')
      .doc(householdId)
      .collection('handoffSessions')
      .doc(offered.sessionId)
      .snapshots(includeMetadataChanges: true)
      .firstWhere(
        (snapshot) =>
            !snapshot.metadata.isFromCache &&
            !snapshot.metadata.hasPendingWrites &&
            snapshot.data()?['status'] == 'accepted',
      )
      .timeout(const Duration(seconds: 45));
  expect(acceptedSession.data()?['handoffRevisionSnapshot'], 1);
  var privateInboxDenied = false;
  try {
    await firestore
        .collection('users')
        .doc(peerId)
        .collection('notificationInbox')
        .limit(1)
        .get(const GetOptions(source: Source.server));
  } on FirebaseException catch (error) {
    privateInboxDenied = error.code == 'permission-denied';
  }
  expect(privateInboxDenied, isTrue);

  final retryReceipt = await _verifyRetryIdentities(
    session: session,
    firestore: firestore,
    functions: functions,
  );

  final eventReceipt = await _verifyEventsAndCursor(
    session: session,
    firestore: firestore,
    expectedSourceIds: {transfer.transferId!, offered.sessionId},
  );
  final providerReceipt = await _verifyNoProviderArtifacts(
    session: session,
    firestore: firestore,
  );
  await taskRepository.stopObserving();
  await responsibilityRepository.stopObserving();
  await handoffRepository.stopObserving();
  await sessionRepository.stopObserving();
  return [
    'checkpoint=lt5-transfer role=A run=$_runId status=accepted revision=2',
    'checkpoint=lt5-handoff role=A run=$_runId '
        'pinnedRevision=1 currentRevision=2 status=accepted',
    eventReceipt,
    providerReceipt,
    retryReceipt,
    'checkpoint=no-duplicates role=A run=$_runId sources=2 '
        'privatePeerInbox=denied',
  ];
}

Future<List<String>> _runSourceRecipient({
  required HouseholdSession session,
  required FirebaseFirestore firestore,
  required FirebaseFunctions functions,
  required FirebaseNotificationCenterGateway notificationGateway,
  required DateTime memberJoinedAt,
}) async {
  final householdId = session.household.id;
  final responsibilityRepository = FirebaseTaskResponsibilityRepository(
    gateway: FirebaseTaskResponsibilityGateway(
      firestore: firestore,
      functions: functions,
    ),
  );
  final handoffRepository = FirebaseHandoffRepository(
    gateway: FirebaseHandoffGateway(firestore: firestore),
  );
  final sessionRepository = FirebaseHandoffSessionRepository(
    gateway: FirebaseHandoffSessionGateway(
      firestore: firestore,
      functions: functions,
    ),
  );
  final transferSnapshot = await responsibilityRepository
      .observeTransfers(householdId)
      .firstWhere(
        (snapshot) =>
            !snapshot.isFromCache &&
            !snapshot.authorityMalformed &&
            snapshot.droppedTransferCount == 0 &&
            snapshot.pendingByTaskId.values.any(
              (transfer) => transfer.consentById == session.caregiver.id,
            ),
      )
      .timeout(const Duration(seconds: 45));
  final transfer = transferSnapshot.pendingByTaskId.values.singleWhere(
    (item) => item.consentById == session.caregiver.id,
  );
  final activeHandoff = await sessionRepository
      .observeActiveSession(householdId)
      .firstWhere(
        (snapshot) =>
            !snapshot.isFromCache &&
            !snapshot.authorityMalformed &&
            snapshot.droppedSessionCount == 0 &&
            snapshot.droppedVersionCount == 0 &&
            snapshot.activeSession?.recipientId == session.caregiver.id &&
            snapshot.pinnedVersion?.sourceHandoffRevision == 1,
      )
      .timeout(const Duration(seconds: 45));
  final currentHandoff = await handoffRepository
      .observeHandoff(householdId)
      .firstWhere(
        (snapshot) =>
            !snapshot.isFromCache &&
            !snapshot.hasPendingWrites &&
            snapshot.handoff?.revision == 2,
      )
      .timeout(const Duration(seconds: 45));
  expect(activeHandoff.activeSession?.handoffRevisionSnapshot, 1);
  expect(activeHandoff.pinnedVersion?.sourceHandoffRevision, 1);
  expect(currentHandoff.handoff?.revision, 2);

  final inboxRepository = FirebaseNotificationInboxRepository(
    gateway: notificationGateway,
  );
  final inboxPage = await inboxRepository
      .observeRecent(
        householdId: householdId,
        memberId: session.caregiver.id,
        memberJoinedAt: memberJoinedAt,
      )
      .firstWhere(
        (page) =>
            page.authority ==
                NotificationObservationAuthority.serverConfirmed &&
            !page.hasPendingWrites &&
            page.droppedItemCount == 0 &&
            page.items.any(
              (item) =>
                  item.status == NotificationInboxStatus.active &&
                  item.level == NotificationInboxLevel.handoffOffer,
            ),
      )
      .timeout(const Duration(seconds: 45));
  final inboxItem = inboxPage.items.singleWhere(
    (item) =>
        item.status == NotificationInboxStatus.active &&
        item.level == NotificationInboxLevel.handoffOffer,
  );
  final direct = await inboxRepository.loadByIDFromServer(
    householdId: householdId,
    memberId: session.caregiver.id,
    memberJoinedAt: memberJoinedAt,
    inboxItemId: inboxItem.id,
  );
  expect(direct.id, inboxItem.id);
  final interactionRepository = StoredNotificationInteractionRepository(
    gateway: notificationGateway,
    store: MemoryNotificationPendingRouteStore(),
  );
  final pending = await interactionRepository.persistClick(
    NotificationRoutePayload(
      householdId: householdId,
      inboxItemId: direct.id,
    ).toJson(),
  );
  expect(pending.generation, 1);
  final resolution = await interactionRepository.resolve(pending.payload);
  expect(resolution.disposition, NotificationRouteDisposition.open);
  expect(resolution.inboxItemId, direct.id);
  await inboxRepository.markRead(
    householdId,
    memberJoinedAt,
    NotificationReadCursor(createdAt: direct.createdAt, intentId: direct.id),
  );
  final cursor = await inboxRepository
      .observeReadCursor(
        householdId: householdId,
        memberId: session.caregiver.id,
        memberJoinedAt: memberJoinedAt,
      )
      .firstWhere(
        (snapshot) =>
            snapshot.authority == NotificationCursorAuthority.serverConfirmed &&
            snapshot.cursor?.intentId == direct.id,
      )
      .timeout(const Duration(seconds: 20));
  expect(cursor.cursor?.intentId, direct.id);

  await responsibilityRepository.resolveTransfer(
    householdId: householdId,
    taskId: transfer.taskId,
    action: 'acceptTransfer',
    transferId: transfer.id,
    expectedTaskRevision: transfer.taskRevisionAtProposal,
    expectedTransferRevision: transfer.revision,
    clientMutationId: _mutationId('transfer-accept'),
  );
  final handoffSession = activeHandoff.activeSession!;
  await sessionRepository.transition(
    householdId: householdId,
    action: 'accept',
    sessionId: handoffSession.id,
    expectedSessionRevision: handoffSession.revision,
    clientMutationId: _mutationId('handoff-accept'),
  );

  final eventReceipt = await _verifyEventsAndCursor(
    session: session,
    firestore: firestore,
    expectedSourceIds: {transfer.id, handoffSession.id},
  );
  final providerReceipt = await _verifyNoProviderArtifacts(
    session: session,
    firestore: firestore,
  );
  await responsibilityRepository.stopObserving();
  await handoffRepository.stopObserving();
  await sessionRepository.stopObserving();
  return [
    'checkpoint=lt5-transfer role=B run=$_runId status=accepted revision=2',
    'checkpoint=lt5-handoff role=B run=$_runId '
        'pinnedRevision=1 currentRevision=2 status=accepted',
    eventReceipt,
    'checkpoint=lt6-inbox role=B run=$_runId private=1 cursor=confirmed '
        'route=open providerAttempts=0 deliveryCount=0 tokenCount=0',
    providerReceipt,
    'checkpoint=no-duplicates role=B run=$_runId sources=2',
  ];
}

Future<String> _verifyEventsAndCursor({
  required HouseholdSession session,
  required FirebaseFirestore firestore,
  required Set<String> expectedSourceIds,
}) async {
  final repository = FirebaseCollaborationEventRepository(
    gateway: FirebaseCollaborationEventGateway(firestore: firestore),
  );
  final snapshot = await repository
      .observeRecent(session.household.id)
      .firstWhere(
        (value) =>
            !value.isFromCache &&
            value.droppedEventCount == 0 &&
            expectedSourceIds.every(
              (id) => value.events.any((event) => event.sourceId == id),
            ),
      )
      .timeout(const Duration(seconds: 45));
  final relevant = snapshot.events
      .where((event) => expectedSourceIds.contains(event.sourceId))
      .toList(growable: false);
  final identities = relevant
      .map((event) => '${event.sourceId}|${event.action.name}')
      .toList(growable: false);
  expect(identities.toSet().length, identities.length);
  relevant.sort((left, right) {
    final time = left.occurredAt.compareTo(right.occurredAt);
    return time != 0 ? time : left.id.compareTo(right.id);
  });
  final newest = relevant.last;
  await repository.markRead(
    session.household.id,
    session.caregiver.id,
    CollaborationReadCursor(occurredAt: newest.occurredAt, eventId: newest.id),
  );
  final cursor = await repository
      .observeReadCursor(session.household.id, session.caregiver.id)
      .firstWhere(
        (value) =>
            !value.isFromCache &&
            !value.hasPendingWrites &&
            value.cursor?.eventId == newest.id,
      )
      .timeout(const Duration(seconds: 20));
  expect(cursor.cursor?.eventId, newest.id);
  await repository.stopObserving();
  return 'checkpoint=lt4-events role=$_role run=$_runId sources=2 '
      'cursor=confirmed duplicates=0';
}

Future<String> _verifyNoProviderArtifacts({
  required HouseholdSession session,
  required FirebaseFirestore firestore,
}) async {
  final user = firestore.collection('users').doc(session.caregiver.id);
  final tokens = await user
      .collection('notificationTokens')
      .limit(21)
      .get(const GetOptions(source: Source.server));
  final deliveries = await user
      .collection('notificationDeliveries')
      .limit(21)
      .get(const GetOptions(source: Source.server));
  expect(tokens.docs, isEmpty);
  expect(deliveries.docs, isEmpty);
  return 'checkpoint=lt6-inbox role=$_role run=$_runId '
      'providerAttempts=0 deliveryCount=0 tokenCount=0';
}

Future<String> _verifyRetryIdentities({
  required HouseholdSession session,
  required FirebaseFirestore firestore,
  required FirebaseFunctions functions,
}) async {
  final householdId = session.household.id;
  final healthGateway = _OnceResponseLossHealthGateway(
    FirebaseHealthGateway(firestore: firestore, functions: functions),
  );
  final healthRepository = FirebaseHealthRepository(
    gateway: healthGateway,
    mutationStore: _MemoryHealthMutationStore(),
  );
  final healthRecordedAt = DateTime.now().toUtc();
  Future<void> createHealth() => healthRepository.createRecord(
    householdId: householdId,
    petId: legacyPrimaryPetId,
    petName: session.household.petName,
    type: HealthRecordType.note,
    recordedAt: healthRecordedAt,
    timeZoneIdentifier: session.household.timeZoneIdentifier!,
    detail: 'LT7 retry fixture',
    weightKilograms: null,
    createdById: session.caregiver.id,
    createdByName: session.caregiver.displayName,
  );
  final firstHealth = await _capture(createHealth());
  expect(
    firstHealth,
    isA<HealthRepositoryException>().having(
      (error) => error.code,
      'code',
      HealthRepositoryErrorCode.backendUnavailable,
    ),
  );
  await createHealth();
  expect(healthGateway.recordIds, hasLength(2));
  expect(healthGateway.recordIds.toSet(), hasLength(1));
  final healthDocument = await firestore
      .collection('households')
      .doc(householdId)
      .collection('healthRecords')
      .doc(healthGateway.recordIds.first)
      .get(const GetOptions(source: Source.server));
  expect(healthDocument.exists, isTrue);

  time_zone_data.initializeTimeZones();
  final tokyo = time_zone.getLocation('Asia/Tokyo');
  final selected = time_zone.TZDateTime.now(tokyo);
  final localDate =
      '${selected.year.toString().padLeft(4, '0')}-'
      '${selected.month.toString().padLeft(2, '0')}-'
      '${selected.day.toString().padLeft(2, '0')}';
  final medicationGateway = _OnceResponseLossMedicationGateway(
    FirebaseMedicationGateway(firestore: firestore, functions: functions),
  );
  final medicationRepository = FirebaseMedicationRepository(
    gateway: medicationGateway,
    mutationStore: _MemoryMedicationMutationStore(),
  );
  final medicationId = await medicationRepository.createPlan(
    householdId: householdId,
    petId: legacyPrimaryPetId,
    medicationName: 'LT7 medication',
    effectiveFromLocalDate: localDate,
    weekdays: [selected.weekday],
    slots: [
      MedicationPlanSlotInput(
        hour: selected.hour,
        minute: selected.minute,
        doseText: 'LT7 dose',
      ),
    ],
  );
  final medicationSnapshot = await medicationRepository
      .observeMedication(householdId)
      .firstWhere(
        (snapshot) =>
            snapshot.isServerConfirmed &&
            snapshot.medications.any((item) => item.id == medicationId),
      )
      .timeout(const Duration(seconds: 30));
  final planned = MedicationOccurrenceService().forDay(
    selectedInstant: selected,
    schedules: medicationSnapshot.schedules.where(
      (schedule) => schedule.medicationId == medicationId,
    ),
    persisted: medicationSnapshot.occurrences,
  );
  expect(planned, hasLength(1));
  Future<void> administer() => medicationRepository.administer(
    householdId: householdId,
    occurrence: planned.single,
  );
  final firstMedication = await _capture(administer());
  expect(
    firstMedication,
    isA<MedicationRepositoryException>().having(
      (error) => error.code,
      'code',
      MedicationRepositoryErrorCode.backendUnavailable,
    ),
  );
  await administer();
  expect(medicationGateway.mutationIds, hasLength(2));
  expect(medicationGateway.mutationIds.toSet(), hasLength(1));
  final occurrence = await firestore
      .collection('households')
      .doc(householdId)
      .collection('medicationOccurrences')
      .doc(planned.single.id)
      .get(const GetOptions(source: Source.server));
  expect(occurrence.exists, isTrue);
  expect(occurrence.data()?['revision'], 1);

  await healthRepository.stopObserving();
  await medicationRepository.stopObserving();
  return 'checkpoint=no-duplicates role=A run=$_runId '
      'healthRetryIdentity=stable medicationRetryIdentity=stable';
}

Future<Object?> _capture(Future<void> action) async {
  try {
    await action;
    return null;
  } on Object catch (error) {
    return error;
  }
}

Future<List<String>> _runOfflineProtocol({
  required HouseholdSession session,
  required FirebaseFirestore firestore,
}) async {
  final tasks = firestore
      .collection('households')
      .doc(session.household.id)
      .collection('tasks');
  final marker = 'LT7 offline $_runId';
  if (_role == 'A') {
    final repository = FirebaseCareTaskRepository(
      gateway: FirebaseCareTaskGateway(firestore: firestore),
    );
    await repository.createOneOffTask(
      householdId: session.household.id,
      title: marker,
      category: CareCategory.other,
      dueTime: DateTime.now().toUtc(),
      priority: CarePriority.normal,
      createdById: session.caregiver.id,
      createdByName: session.caregiver.displayName,
    );
    final server = await tasks
        .where('title', isEqualTo: marker)
        .get(const GetOptions(source: Source.server));
    expect(server.docs, hasLength(1));
    return [
      'checkpoint=offline-reconnect role=A run=$_runId sourceWrites=1',
      'checkpoint=no-duplicates role=A run=$_runId sourceWrites=1',
    ];
  }

  await tasks.get(const GetOptions(source: Source.server));
  await firestore.disableNetwork();
  debugPrint('LT7_READY_OFFLINE role=B run=$_runId');
  final cached = await tasks.get(const GetOptions(source: Source.cache));
  expect(cached.metadata.isFromCache, isTrue);
  await Future<void>.delayed(const Duration(seconds: 30));
  await firestore.enableNetwork();
  final server = await tasks
      .where('title', isEqualTo: marker)
      .snapshots(includeMetadataChanges: true)
      .firstWhere(
        (snapshot) =>
            !snapshot.metadata.isFromCache &&
            !snapshot.metadata.hasPendingWrites &&
            snapshot.docs.length == 1,
      )
      .timeout(const Duration(seconds: 30));
  expect(server.docs, hasLength(1));
  return [
    'checkpoint=offline-reconnect role=B run=$_runId '
        'cache=non-authoritative server=confirmed',
    'checkpoint=no-duplicates role=B run=$_runId sourceWrites=1',
  ];
}

String _mutationId(String label) =>
    sha256.convert(utf8.encode('lt7-mutation|$_runId|$label')).toString();

Future<QuerySnapshot<Map<String, dynamic>>> _serverConfirmedMembers(
  FirebaseFirestore firestore,
  String householdId,
) => firestore
    .collection('households')
    .doc(householdId)
    .collection('members')
    .snapshots(includeMetadataChanges: true)
    .firstWhere(
      (snapshot) =>
          !snapshot.metadata.isFromCache &&
          !snapshot.metadata.hasPendingWrites &&
          snapshot.docs.length == 2,
    )
    .timeout(const Duration(seconds: 20));

String _identityReceipt(HouseholdSession session, int memberCount) =>
    'checkpoint=identity role=$_role phase=$_phase run=$_runId '
    'uidHash=${_hash(session.caregiver.id)} '
    'householdHash=${_hash(session.household.id)} members=$memberCount';

String _hash(String value) => sha256
    .convert(utf8.encode('lt7-receipt|$_runId|$value'))
    .toString()
    .substring(0, 16);

void _validateContract() {
  if (_receiptContract.length != 8 ||
      !const {'A', 'B'}.contains(_role) ||
      !const {'bootstrap', 'reconnect', 'source', 'offline'}.contains(_phase) ||
      !RegExp(r'^[a-z0-9-]{6,40}$').hasMatch(_runId) ||
      !RegExp(r'^[A-Z0-9]{6}$').hasMatch(_inviteCode) ||
      localFirebaseAuthPort != 9199 ||
      localFirebaseFirestorePort != 8180 ||
      localFirebaseFunctionsPort != 5101) {
    throw StateError('Invalid or non-isolated LT7 acceptance contract');
  }
}

final class _FixedInviteCodeGenerator implements InviteCodeGenerator {
  const _FixedInviteCodeGenerator(this.code);

  final String code;

  @override
  String next() => code;
}

final class _MemoryHealthMutationStore implements HealthMutationStore {
  final _values = <String, String>{};

  @override
  Future<String> readOrCreate(
    String requestHash,
    String Function() createRecordId,
  ) async => _values.putIfAbsent(requestHash, createRecordId);

  @override
  Future<void> clear(String requestHash) async {
    _values.remove(requestHash);
  }
}

final class _OnceResponseLossHealthGateway implements HealthGateway {
  _OnceResponseLossHealthGateway(this._delegate);

  final HealthGateway _delegate;
  final recordIds = <String>[];
  var _lost = false;

  @override
  Stream<StoredHealthSnapshot> observeHealth(String householdId) =>
      _delegate.observeHealth(householdId);

  @override
  String newRecordId(String householdId) => _delegate.newRecordId(householdId);

  @override
  Future<void> createRecord(CreateHealthRecordCommand command) async {
    recordIds.add(command.recordId);
    await _delegate.createRecord(command);
    if (!_lost) {
      _lost = true;
      throw FirebaseException(plugin: 'cloud_functions', code: 'unavailable');
    }
  }

  @override
  Future<Map<String, Object?>> createDailyCheckIn(
    Map<String, Object?> payload,
  ) => _delegate.createDailyCheckIn(payload);
}

final class _MemoryMedicationMutationStore implements MedicationMutationStore {
  final _values = <String, String>{};

  @override
  Future<String> readOrCreate(
    String requestHash,
    String Function() createMutationId,
  ) async => _values.putIfAbsent(requestHash, createMutationId);

  @override
  Future<void> clear(String requestHash) async {
    _values.remove(requestHash);
  }
}

final class _OnceResponseLossMedicationGateway implements MedicationGateway {
  _OnceResponseLossMedicationGateway(this._delegate);

  final MedicationGateway _delegate;
  final mutationIds = <String>[];
  var _lost = false;

  @override
  Stream<MedicationGatewaySnapshot> observe(String householdId) =>
      _delegate.observe(householdId);

  @override
  Future<Map<String, Object?>> call(
    String name,
    Map<String, Object?> payload,
  ) async {
    final result = await _delegate.call(name, payload);
    if (name == 'mutateMedicationOccurrence') {
      mutationIds.add(payload['clientMutationID']! as String);
      if (!_lost) {
        _lost = true;
        throw FirebaseException(plugin: 'cloud_functions', code: 'unavailable');
      }
    }
    return result;
  }

  @override
  Future<void> stopObserving() => _delegate.stopObserving();
}
