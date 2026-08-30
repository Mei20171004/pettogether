import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../domain/models.dart';
import 'household_data_gateway.dart';

final class FirebaseHouseholdDataGateway implements HouseholdDataGateway {
  FirebaseHouseholdDataGateway({
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
  }) : _auth = auth ?? FirebaseAuth.instance,
       _firestore = firestore ?? FirebaseFirestore.instance,
       _payloads = HouseholdWritePayloadBuilder(
         serverTimestamp: FieldValue.serverTimestamp,
       );

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;
  final HouseholdWritePayloadBuilder _payloads;

  @override
  Future<String> ensureAnonymousUserId() async {
    final currentUser = _auth.currentUser;
    if (currentUser != null) {
      return currentUser.uid;
    }
    return (await _auth.signInAnonymously()).user!.uid;
  }

  @override
  String newHouseholdId() => _firestore.collection('households').doc().id;

  @override
  Future<void> createHouseholdAtomically(CreateHouseholdCommand command) async {
    final household = _firestore
        .collection('households')
        .doc(command.householdId);
    final member = household.collection('members').doc(command.ownerId);
    final firstPet = household.collection('pets').doc(legacyPrimaryPetId);
    final invite = _firestore.collection('inviteCodes').doc(command.inviteCode);

    await _firestore.runTransaction((transaction) async {
      if ((await transaction.get(invite)).exists) {
        throw const InviteCodeCollision();
      }

      transaction.set(household, _payloads.newHousehold(command));
      transaction.set(member, _payloads.newOwnerMember(command));
      transaction.set(firstPet, _payloads.newFirstPet(command));
      transaction.set(invite, _payloads.newInvite(command));
    });
  }

  @override
  Future<JoinHouseholdResult> joinHouseholdAtomically(
    JoinHouseholdCommand command,
  ) async {
    final invite = _firestore.collection('inviteCodes').doc(command.inviteCode);
    return _firestore.runTransaction((transaction) async {
      final inviteSnapshot = await transaction.get(invite);
      final inviteData = inviteSnapshot.data();
      final householdId = inviteData?['householdID'];
      if (!inviteSnapshot.exists ||
          inviteData?['active'] == false ||
          householdId is! String) {
        throw const InvalidInvite();
      }

      final household = _firestore.collection('households').doc(householdId);
      final member = household.collection('members').doc(command.userId);
      final memberSnapshot = await transaction.get(member);

      if (memberSnapshot.exists) {
        transaction.update(member, _payloads.returningMember(command));
      } else {
        transaction.set(member, _payloads.newJoiningMember(command));
      }

      return JoinHouseholdResult(
        householdId: householdId,
        returningMember: memberSnapshot.exists,
      );
    });
  }

  @override
  Future<StoredDocument> readHousehold(String householdId) async {
    return _stored(
      await _firestore.collection('households').doc(householdId).get(),
    );
  }

  @override
  Future<StoredDocument> readMember(String householdId, String userId) async {
    return _stored(
      await _firestore
          .collection('households')
          .doc(householdId)
          .collection('members')
          .doc(userId)
          .get(),
    );
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

/// Complete legacy Rules-approved writer payloads for household/session writes.
///
/// These deliberately do not use the read-oriented domain codec encoders.
final class HouseholdWritePayloadBuilder {
  const HouseholdWritePayloadBuilder({required this.serverTimestamp});

  final Object Function() serverTimestamp;

  Map<String, Object?> newHousehold(CreateHouseholdCommand command) =>
      <String, Object?>{
        'id': command.householdId,
        'name': command.householdName,
        'petName': command.petName,
        'inviteCode': command.inviteCode,
        'timeZoneIdentifier': command.timeZoneIdentifier,
        'ownerID': command.ownerId,
        'createdAt': serverTimestamp(),
      };

  Map<String, Object?> newOwnerMember(CreateHouseholdCommand command) =>
      <String, Object?>{
        'id': command.ownerId,
        'displayName': command.caregiverName,
        'inviteCode': command.inviteCode,
        'joinedAt': serverTimestamp(),
      };

  Map<String, Object?> newFirstPet(CreateHouseholdCommand command) {
    final timestamp = serverTimestamp();
    return <String, Object?>{
      'id': legacyPrimaryPetId,
      'name': command.petName,
      'species': null,
      'isArchived': false,
      'createdAt': timestamp,
      'updatedAt': timestamp,
    };
  }

  Map<String, Object?> newInvite(CreateHouseholdCommand command) =>
      <String, Object?>{
        'householdID': command.householdId,
        'createdBy': command.ownerId,
        'createdAt': serverTimestamp(),
        'active': true,
      };

  Map<String, Object?> newJoiningMember(JoinHouseholdCommand command) =>
      <String, Object?>{
        'id': command.userId,
        'displayName': command.caregiverName,
        'inviteCode': command.inviteCode,
        'joinedAt': serverTimestamp(),
      };

  Map<String, Object?> returningMember(JoinHouseholdCommand command) =>
      <String, Object?>{
        'displayName': command.caregiverName,
        'updatedAt': serverTimestamp(),
      };
}
