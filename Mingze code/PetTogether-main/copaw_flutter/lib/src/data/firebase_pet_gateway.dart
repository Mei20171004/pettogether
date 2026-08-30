import 'dart:math';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../domain/models.dart';
import 'household_data_gateway.dart';
import 'pet_gateway.dart';

final class FirebasePetGateway implements PetGateway {
  FirebasePetGateway({
    FirebaseFirestore? firestore,
    FirebaseFunctions? functions,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _functions =
           functions ??
           FirebaseFunctions.instanceFor(region: 'asia-northeast1'),
       _payloads = PetWritePayloadBuilder(
         serverTimestamp: FieldValue.serverTimestamp,
       );

  final FirebaseFirestore _firestore;
  final FirebaseFunctions _functions;
  final PetWritePayloadBuilder _payloads;

  @override
  Stream<StoredDocument> observeHousehold(String householdId) => _firestore
      .collection('households')
      .doc(householdId)
      .snapshots()
      .map(_stored);

  @override
  Stream<List<StoredDocument>> observePets(String householdId) => _firestore
      .collection('households')
      .doc(householdId)
      .collection('pets')
      .snapshots()
      .map((snapshot) => snapshot.docs.map(_stored).toList(growable: false));

  @override
  String newPetId(String householdId) => _firestore
      .collection('households')
      .doc(householdId)
      .collection('pets')
      .doc()
      .id;

  @override
  Future<void> createPet(CreatePetCommand command) => _firestore
      .collection('households')
      .doc(command.householdId)
      .collection('pets')
      .doc(command.petId)
      .set(_payloads.newPet(command));

  @override
  Future<void> renamePet(RenamePetCommand command) async {
    final household = _firestore
        .collection('households')
        .doc(command.householdId);
    final pet = household.collection('pets').doc(command.petId);
    if (command.petId != legacyPrimaryPetId) {
      await pet.update(_payloads.renamePet(command));
      return;
    }

    await _firestore.runTransaction((transaction) async {
      final storedPet = await transaction.get(pet);
      if (storedPet.exists) {
        transaction.update(pet, _payloads.renamePet(command));
      } else {
        transaction.set(pet, _payloads.materializedLegacyPet(command));
      }
      transaction.update(household, _payloads.renameLegacyHousehold(command));
    });
  }

  @override
  Future<void> archivePet(ArchivePetCommand command) async {
    await _functions.httpsCallable('archivePet').call(<String, Object?>{
      'householdID': command.householdId,
      'petID': command.petId,
      'clientMutationID': _mutationId(),
    });
  }

  static String _mutationId() {
    final random = Random.secure().nextInt(1 << 32).toRadixString(16);
    return '${DateTime.now().microsecondsSinceEpoch}-$random';
  }

  static StoredDocument _stored(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) => StoredDocument(
    id: snapshot.id,
    exists: snapshot.exists,
    data: snapshot.data()?.cast<String, Object?>() ?? const {},
  );
}

final class PetWritePayloadBuilder {
  const PetWritePayloadBuilder({required this.serverTimestamp});

  final Object Function() serverTimestamp;

  Map<String, Object?> newPet(CreatePetCommand command) {
    final timestamp = serverTimestamp();
    return <String, Object?>{
      'id': command.petId,
      'name': command.name,
      'species': command.species,
      'isArchived': false,
      'createdAt': timestamp,
      'updatedAt': timestamp,
    };
  }

  Map<String, Object?> renamePet(RenamePetCommand command) => <String, Object?>{
    'name': command.name,
    'updatedAt': serverTimestamp(),
  };

  Map<String, Object?> materializedLegacyPet(RenamePetCommand command) {
    final timestamp = serverTimestamp();
    return <String, Object?>{
      'id': legacyPrimaryPetId,
      'name': command.name,
      'species': null,
      'isArchived': false,
      'createdAt': timestamp,
      'updatedAt': timestamp,
    };
  }

  Map<String, Object?> renameLegacyHousehold(RenamePetCommand command) =>
      <String, Object?>{
        'petName': command.name,
        'updatedAt': serverTimestamp(),
      };
}
