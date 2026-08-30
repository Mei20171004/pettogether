import 'package:cloud_firestore/cloud_firestore.dart';

import 'household_data_gateway.dart';
import 'household_sync_gateway.dart';

final class FirebaseHouseholdSyncGateway implements HouseholdSyncGateway {
  FirebaseHouseholdSyncGateway({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance,
      _payloads = ProfileWritePayloadBuilder(
        serverTimestamp: FieldValue.serverTimestamp,
      );

  final FirebaseFirestore _firestore;
  final ProfileWritePayloadBuilder _payloads;

  @override
  Stream<StoredDocument> observeHousehold(String householdId) {
    return _firestore
        .collection('households')
        .doc(householdId)
        .snapshots()
        .map(_stored);
  }

  @override
  Stream<StoredDocument> observeMember(String householdId, String userId) {
    return _firestore
        .collection('households')
        .doc(householdId)
        .collection('members')
        .doc(userId)
        .snapshots()
        .map(_stored);
  }

  @override
  Stream<List<StoredDocument>> observeMembers(String householdId) {
    return _firestore
        .collection('households')
        .doc(householdId)
        .collection('members')
        .snapshots()
        .map((snapshot) => snapshot.docs.map(_stored).toList(growable: false));
  }

  @override
  Future<void> updateProfileAtomically(UpdateProfileCommand command) async {
    final household = _firestore
        .collection('households')
        .doc(command.householdId);
    final member = household.collection('members').doc(command.userId);
    final batch = _firestore.batch();
    batch.update(household, _payloads.household(command));
    batch.update(member, _payloads.member(command));
    await batch.commit();
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

final class ProfileWritePayloadBuilder {
  const ProfileWritePayloadBuilder({required this.serverTimestamp});

  final Object Function() serverTimestamp;

  Map<String, Object?> household(UpdateProfileCommand command) =>
      <String, Object?>{
        'name': command.householdName,
        'petName': command.petName,
        'updatedAt': serverTimestamp(),
      };

  Map<String, Object?> member(UpdateProfileCommand command) =>
      <String, Object?>{
        'displayName': command.caregiverName,
        'updatedAt': serverTimestamp(),
      };
}
