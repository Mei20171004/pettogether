import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/legacy_firestore_codec.dart';
import '../domain/models.dart';

final class PetSnapshot {
  const PetSnapshot({required this.pets, this.diagnostics = const []});

  final List<Pet> pets;
  final List<DomainDiagnostic> diagnostics;
}

enum PetRepositoryErrorCode {
  invalidInput,
  network,
  permission,
  malformedData,
  backendUnavailable,
}

final class PetRepositoryException implements Exception {
  const PetRepositoryException(this.code);

  final PetRepositoryErrorCode code;

  @override
  String toString() => 'PetRepositoryException($code)';
}

abstract interface class PetRepository {
  Stream<PetSnapshot> observePets(String householdId);

  Future<String> createPet({
    required String householdId,
    required String name,
    required PetSpecies? species,
  });

  Future<void> renamePet({
    required String householdId,
    required String petId,
    required String name,
  });

  Future<void> archivePet({required String householdId, required String petId});

  Future<void> stopObserving();
}

final petRepositoryProvider = Provider<PetRepository>((ref) {
  throw StateError('PetRepository must be provided at the app boundary.');
});
