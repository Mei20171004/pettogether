import 'package:cloud_firestore/cloud_firestore.dart';

import 'care_task_gateway.dart';
import 'household_data_gateway.dart';

final class FirebaseCareTaskGateway implements CareTaskGateway {
  FirebaseCareTaskGateway({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance,
      _payloads = OneOffTaskWritePayloadBuilder(
        serverTimestamp: FieldValue.serverTimestamp,
      );

  final FirebaseFirestore _firestore;
  final OneOffTaskWritePayloadBuilder _payloads;

  @override
  Stream<StoredCareDocuments> observeRoutines(String householdId) {
    return _firestore
        .collection('households')
        .doc(householdId)
        .collection('routines')
        .snapshots(includeMetadataChanges: true)
        .map(
          (snapshot) => StoredCareDocuments(
            documents: snapshot.docs
                .map(
                  (document) => StoredDocument(
                    id: document.id,
                    exists: true,
                    data: document.data().cast<String, Object?>(),
                  ),
                )
                .toList(growable: false),
            isServerConfirmed:
                !snapshot.metadata.isFromCache &&
                !snapshot.metadata.hasPendingWrites,
          ),
        );
  }

  @override
  Stream<StoredCareDocuments> observeTasks(String householdId) {
    return _firestore
        .collection('households')
        .doc(householdId)
        .collection('tasks')
        .snapshots(includeMetadataChanges: true)
        .map(
          (snapshot) => StoredCareDocuments(
            documents: snapshot.docs
                .map(
                  (document) => StoredDocument(
                    id: document.id,
                    exists: true,
                    data: document.data().cast<String, Object?>(),
                  ),
                )
                .toList(growable: false),
            isServerConfirmed:
                !snapshot.metadata.isFromCache &&
                !snapshot.metadata.hasPendingWrites,
          ),
        );
  }

  @override
  Future<StoredDocument> readHousehold(String householdId) async {
    final snapshot = await _firestore
        .collection('households')
        .doc(householdId)
        .get();
    return StoredDocument(
      id: snapshot.id,
      exists: snapshot.exists,
      data: snapshot.data()?.cast<String, Object?>() ?? const {},
    );
  }

  @override
  String newTaskId(String householdId) => _firestore
      .collection('households')
      .doc(householdId)
      .collection('tasks')
      .doc()
      .id;

  @override
  String newRoutineId(String householdId) => _firestore
      .collection('households')
      .doc(householdId)
      .collection('routines')
      .doc()
      .id;

  @override
  Future<void> createOneOffTask(CreateOneOffTaskCommand command) {
    return _firestore
        .collection('households')
        .doc(command.householdId)
        .collection('tasks')
        .doc(command.taskId)
        .set(_payloads.build(command));
  }

  @override
  Future<void> createRoutine(CreateRoutineCommand command) {
    return _firestore
        .collection('households')
        .doc(command.householdId)
        .collection('routines')
        .doc(command.routineId)
        .set(
          RoutineWritePayloadBuilder(
            serverTimestamp: FieldValue.serverTimestamp,
          ).build(command),
        );
  }
}

final class RoutineWritePayloadBuilder {
  const RoutineWritePayloadBuilder({required this.serverTimestamp});

  final Object Function() serverTimestamp;

  Map<String, Object?> build(CreateRoutineCommand command) => <String, Object?>{
    'id': command.routineId,
    'title': command.title,
    'category': command.category,
    'priority': command.priority,
    'hour': command.hour,
    'minute': command.minute,
    'frequency': command.frequency,
    'weekdays': command.weekdays,
    'startDate': Timestamp.fromDate(command.startDate),
    'timeZoneIdentifier': command.timeZoneIdentifier,
    'createdByID': command.createdById,
    'createdByName': command.createdByName,
    'petID': command.petId,
    'petName': command.petName,
    'isActive': true,
    'createdAt': serverTimestamp(),
  };
}

final class OneOffTaskWritePayloadBuilder {
  const OneOffTaskWritePayloadBuilder({required this.serverTimestamp});

  final Object Function() serverTimestamp;

  Map<String, Object?> build(CreateOneOffTaskCommand command) {
    final timestamp = serverTimestamp();
    return <String, Object?>{
      'id': command.taskId,
      'title': command.title,
      'category': command.category,
      'dueTime': Timestamp.fromDate(command.dueTime),
      'kind': 'oneOff',
      'priority': command.priority,
      'routineID': null,
      'petID': command.petId,
      'petName': command.petName,
      'status': 'unclaimed',
      'assignmentRequestID': null,
      'assignmentMode': null,
      'requestedByID': null,
      'requestedByName': null,
      'requestedToID': null,
      'requestedToName': null,
      'assignmentRequestedAt': null,
      'assigneeID': null,
      'assigneeName': null,
      'claimedAt': null,
      'createdByID': command.createdById,
      'createdBy': command.createdByName,
      'createdAt': timestamp,
      'completedByID': null,
      'completedBy': null,
      'completedAt': null,
      'lastCollaborationAction': 'taskCreated',
      'lastCollaborationActorID': command.createdById,
      'lastCollaborationActorName': command.createdByName,
      'lastCollaborationTargetID': null,
      'lastCollaborationTargetName': null,
      'lastCollaborationRequestID': null,
      'lastCollaborationAt': timestamp,
      'revision': 0,
    };
  }
}
