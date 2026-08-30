import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import 'health_gateway.dart';

final class FirebaseHealthGateway implements HealthGateway {
  FirebaseHealthGateway({
    FirebaseFirestore? firestore,
    FirebaseFunctions? functions,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _functions =
           functions ??
           FirebaseFunctions.instanceFor(region: 'asia-northeast1');

  final FirebaseFirestore _firestore;
  final FirebaseFunctions _functions;

  @override
  Stream<StoredHealthSnapshot> observeHealth(String householdId) => _firestore
      .collection('households')
      .doc(householdId)
      .collection('healthRecords')
      .orderBy('recordedAt', descending: true)
      .snapshots(includeMetadataChanges: true)
      .map(
        (snapshot) => StoredHealthSnapshot(
          isFromCache: snapshot.metadata.isFromCache,
          documents: snapshot.docs
              .map(
                (document) => StoredHealthDocument(
                  id: document.id,
                  data: document.data().cast<String, Object?>(),
                  hasPendingWrites: document.metadata.hasPendingWrites,
                ),
              )
              .toList(growable: false),
        ),
      );

  @override
  String newRecordId(String householdId) => _firestore
      .collection('households')
      .doc(householdId)
      .collection('healthRecords')
      .doc()
      .id;

  @override
  Future<void> createRecord(CreateHealthRecordCommand command) async {
    await _functions.httpsCallable('createHealthRecord').call({
      'householdID': command.householdId,
      'petID': command.petId,
      'type': command.type,
      'recordedAtMilliseconds': command.recordedAt.millisecondsSinceEpoch,
      'detail': command.detail,
      'weightKilograms': command.weightKilograms,
      'waterMilliliters': command.waterMilliliters?.round(),
      'clientMutationID': command.recordId,
    });
  }

  @override
  Future<Map<String, Object?>> createDailyCheckIn(
    Map<String, Object?> payload,
  ) async {
    final result = await _functions
        .httpsCallable('createDailyHealthCheckIn')
        .call(payload);
    if (result.data is! Map) {
      throw FirebaseFunctionsException(
        code: 'internal',
        message: 'Unexpected daily health response.',
      );
    }
    return Map<String, Object?>.from(result.data as Map);
  }
}
