import 'package:cloud_firestore/cloud_firestore.dart';

import 'handoff_gateway.dart';

final class FirebaseHandoffGateway implements HandoffGateway {
  FirebaseHandoffGateway({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  DocumentReference<Map<String, dynamic>> _reference(String householdId) =>
      _firestore
          .collection('households')
          .doc(householdId)
          .collection('handoff')
          .doc('current');

  @override
  Stream<StoredHandoffDocument> observeHandoff(String householdId) =>
      _reference(householdId)
          .snapshots(includeMetadataChanges: true)
          .map(
            (snapshot) => StoredHandoffDocument(
              exists: snapshot.exists,
              data: snapshot.data()?.cast<String, Object?>() ?? const {},
              isFromCache: snapshot.metadata.isFromCache,
              hasPendingWrites: snapshot.metadata.hasPendingWrites,
            ),
          );

  @override
  Future<void> saveHandoff(SaveHandoffCommand command) async {
    final reference = _reference(command.householdId);
    await _firestore.runTransaction((transaction) async {
      final stored = await transaction.get(reference);
      final data = stored.data();
      final storedRevision = data?['revision'];
      if ((data == null && command.expectedRevision != null) ||
          (data != null && storedRevision != command.expectedRevision)) {
        throw const HandoffRevisionConflict();
      }
      if (data != null &&
          data['careInstructions'] == command.careInstructions &&
          data['emergencyContactName'] == command.emergencyContactName &&
          data['emergencyContactPhone'] == command.emergencyContactPhone &&
          data['veterinaryHospitalName'] == command.veterinaryHospitalName &&
          data['veterinaryHospitalPhone'] == command.veterinaryHospitalPhone) {
        return;
      }
      transaction.set(reference, {
        'schemaVersion': 1,
        'careInstructions': command.careInstructions,
        'emergencyContactName': command.emergencyContactName,
        'emergencyContactPhone': command.emergencyContactPhone,
        'veterinaryHospitalName': command.veterinaryHospitalName,
        'veterinaryHospitalPhone': command.veterinaryHospitalPhone,
        'revision': storedRevision is int ? storedRevision + 1 : 1,
        'updatedByID': command.updatedById,
        'updatedByName': command.updatedByName,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }
}
