import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import 'care_task_mutation_gateway.dart';
import 'household_data_gateway.dart';

final class FirebaseCareTaskMutationGateway implements CareTaskMutationGateway {
  FirebaseCareTaskMutationGateway({
    FirebaseFirestore? firestore,
    FirebaseFunctions? functions,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _functions =
           functions ??
           FirebaseFunctions.instanceFor(region: 'asia-northeast1');

  final FirebaseFirestore _firestore;
  final FirebaseFunctions _functions;

  @override
  Future<MaterializedRoutineOccurrence> materializeRoutineOccurrence({
    required String householdId,
    required String routineId,
    required String localDate,
    required String action,
    String? recipientId,
  }) async {
    final response = await _functions
        .httpsCallable('mutateRoutineOccurrence')
        .call(<String, Object?>{
          'householdID': householdId,
          'routineID': routineId,
          'localDate': localDate,
          'action': action,
          'recipientID': recipientId,
        });
    final data = Map<String, Object?>.from(response.data as Map);
    final taskId = data['taskID'];
    final requestId = data['requestID'];
    if (taskId is! String || (requestId != null && requestId is! String)) {
      throw FirebaseFunctionsException(
        code: 'internal',
        message: 'Unexpected occurrence response.',
      );
    }
    return MaterializedRoutineOccurrence(
      taskId: taskId,
      requestId: requestId as String?,
    );
  }

  @override
  Future<void> runTaskTransaction({
    required String householdId,
    required String taskId,
    required String actorId,
    String? recipientId,
    required CareTaskMutationTransform transform,
  }) async {
    final household = _firestore.collection('households').doc(householdId);
    final taskReference = household.collection('tasks').doc(taskId);
    final actorReference = household.collection('members').doc(actorId);
    final recipientReference = recipientId == null
        ? null
        : household.collection('members').doc(recipientId);

    await _firestore.runTransaction((transaction) async {
      final task = await transaction.get(taskReference);
      final actor = await transaction.get(actorReference);
      final recipient = recipientReference == null
          ? null
          : await transaction.get(recipientReference);
      final update = transform(
        CareTaskMutationContext(
          task: _stored(task),
          actor: _stored(actor),
          recipient: recipient == null ? null : _stored(recipient),
          serverTimestamp: FieldValue.serverTimestamp(),
        ),
      );
      if (!task.exists) {
        throw FirebaseException(plugin: 'cloud_firestore', code: 'not-found');
      }
      transaction.update(taskReference, update);
    });
  }

  static StoredDocument _stored(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    return StoredDocument(
      id: snapshot.id,
      exists: snapshot.exists,
      data: snapshot.data()?.cast<String, Object?>() ?? const {},
    );
  }
}
