import 'household_data_gateway.dart';

final class CreatePetCommand {
  const CreatePetCommand({
    required this.householdId,
    required this.petId,
    required this.name,
    required this.species,
  });

  final String householdId;
  final String petId;
  final String name;
  final String? species;
}

final class RenamePetCommand {
  const RenamePetCommand({
    required this.householdId,
    required this.petId,
    required this.name,
  });

  final String householdId;
  final String petId;
  final String name;
}

final class ArchivePetCommand {
  const ArchivePetCommand({required this.householdId, required this.petId});

  final String householdId;
  final String petId;
}

abstract interface class PetGateway {
  Stream<StoredDocument> observeHousehold(String householdId);
  Stream<List<StoredDocument>> observePets(String householdId);
  String newPetId(String householdId);
  Future<void> createPet(CreatePetCommand command);
  Future<void> renamePet(RenamePetCommand command);
  Future<void> archivePet(ArchivePetCommand command);
}
