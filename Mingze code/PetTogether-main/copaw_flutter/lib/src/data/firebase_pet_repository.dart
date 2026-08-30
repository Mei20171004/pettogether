import 'dart:async';

import 'package:firebase_core/firebase_core.dart';

import '../domain/legacy_firestore_codec.dart';
import '../domain/models.dart';
import 'firebase_pet_gateway.dart';
import 'household_data_gateway.dart';
import 'pet_gateway.dart';
import 'pet_repository.dart';

final class FirebasePetRepository implements PetRepository {
  FirebasePetRepository({PetGateway? gateway})
    : _gateway = gateway ?? FirebasePetGateway();

  final PetGateway _gateway;
  final LegacyFirestoreCodec _codec = const LegacyFirestoreCodec();
  StreamSubscription<StoredDocument>? _householdSubscription;
  StreamSubscription<List<StoredDocument>>? _petSubscription;
  StreamController<PetSnapshot>? _controller;
  int _generation = 0;

  @override
  Stream<PetSnapshot> observePets(String householdId) {
    final controller = StreamController<PetSnapshot>();
    unawaited(_replaceObservation(householdId, controller));
    return controller.stream;
  }

  Future<void> _replaceObservation(
    String householdId,
    StreamController<PetSnapshot> controller,
  ) async {
    await stopObserving();
    final generation = ++_generation;
    _controller = controller;
    StoredDocument? householdDocument;
    List<StoredDocument>? petDocuments;

    void emitIfReady() {
      if (generation != _generation || controller.isClosed) return;
      final household = householdDocument;
      final documents = petDocuments;
      if (household == null || documents == null) return;

      final pets = <Pet>[];
      final diagnostics = <DomainDiagnostic>[];
      final hasStoredLegacyPet = documents.any(
        (document) => document.id == legacyPrimaryPetId,
      );
      for (final document in documents) {
        final result = _codec.decodePet(document.id, document.data);
        diagnostics.addAll(result.diagnostics);
        if (result.value case final Pet value) pets.add(value);
      }
      if (!hasStoredLegacyPet) {
        final result = _codec.decodeHousehold(household.id, household.data);
        diagnostics.addAll(result.diagnostics);
        final decodedHousehold = result.value;
        if (household.exists && decodedHousehold != null) {
          pets.add(
            Pet(
              id: legacyPrimaryPetId,
              name: decodedHousehold.petName,
              species: null,
              isArchived: false,
              createdAt: null,
              updatedAt: null,
            ),
          );
          diagnostics.add(
            DomainDiagnostic(
              code: DomainDiagnosticCode.legacySynthesizedPet,
              documentId: legacyPrimaryPetId,
              field: 'petName',
              message:
                  'Legacy household pet remains readable until a pet document is created.',
            ),
          );
        }
      }
      pets.sort((left, right) {
        final archived = left.isArchived == right.isArchived
            ? 0
            : left.isArchived
            ? 1
            : -1;
        if (archived != 0) return archived;
        final name = left.name.toLowerCase().compareTo(
          right.name.toLowerCase(),
        );
        return name != 0 ? name : left.id.compareTo(right.id);
      });
      controller.add(
        PetSnapshot(
          pets: List.unmodifiable(pets),
          diagnostics: List.unmodifiable(diagnostics),
        ),
      );
    }

    void addError(Object error) {
      if (generation == _generation && !controller.isClosed) {
        controller.addError(_mapped(error));
      }
    }

    _householdSubscription = _gateway.observeHousehold(householdId).listen((
      document,
    ) {
      if (generation != _generation) return;
      householdDocument = document;
      emitIfReady();
    }, onError: addError);
    _petSubscription = _gateway.observePets(householdId).listen((documents) {
      if (generation != _generation) return;
      petDocuments = documents;
      emitIfReady();
    }, onError: addError);
  }

  @override
  Future<String> createPet({
    required String householdId,
    required String name,
    required PetSpecies? species,
  }) async {
    final normalizedName = name.trim();
    if (!_validHouseholdId(householdId) || !_validName(normalizedName)) {
      throw const PetRepositoryException(PetRepositoryErrorCode.invalidInput);
    }
    final petId = _gateway.newPetId(householdId);
    if (!_validPetId(petId)) {
      throw const PetRepositoryException(
        PetRepositoryErrorCode.backendUnavailable,
      );
    }
    try {
      await _gateway.createPet(
        CreatePetCommand(
          householdId: householdId,
          petId: petId,
          name: normalizedName,
          species: species?.name,
        ),
      );
      return petId;
    } on Object catch (error) {
      throw _mapped(error);
    }
  }

  @override
  Future<void> renamePet({
    required String householdId,
    required String petId,
    required String name,
  }) async {
    final normalizedName = name.trim();
    if (!_validHouseholdId(householdId) ||
        !_validPetId(petId) ||
        !_validName(normalizedName)) {
      throw const PetRepositoryException(PetRepositoryErrorCode.invalidInput);
    }
    try {
      await _gateway.renamePet(
        RenamePetCommand(
          householdId: householdId,
          petId: petId,
          name: normalizedName,
        ),
      );
    } on Object catch (error) {
      throw _mapped(error);
    }
  }

  @override
  Future<void> archivePet({
    required String householdId,
    required String petId,
  }) async {
    if (!_validHouseholdId(householdId) || !_validPetId(petId)) {
      throw const PetRepositoryException(PetRepositoryErrorCode.invalidInput);
    }
    try {
      await _gateway.archivePet(
        ArchivePetCommand(householdId: householdId, petId: petId),
      );
    } on Object catch (error) {
      throw _mapped(error);
    }
  }

  @override
  Future<void> stopObserving() async {
    _generation += 1;
    final household = _householdSubscription;
    final pets = _petSubscription;
    final controller = _controller;
    _householdSubscription = null;
    _petSubscription = null;
    _controller = null;
    await household?.cancel();
    await pets?.cancel();
    await controller?.close();
  }

  static bool _validHouseholdId(String value) =>
      value.isNotEmpty && value.length <= 128 && !value.contains('/');

  static bool _validPetId(String value) =>
      value.isNotEmpty && value.length <= 128 && !value.contains('/');

  static bool _validName(String value) =>
      value.isNotEmpty && value.length <= 60;

  static PetRepositoryException _mapped(Object error) {
    if (error is PetRepositoryException) return error;
    if (error is FirebaseException) {
      return PetRepositoryException(switch (error.code) {
        'network-request-failed' ||
        'unavailable' => PetRepositoryErrorCode.network,
        'permission-denied' => PetRepositoryErrorCode.permission,
        _ => PetRepositoryErrorCode.backendUnavailable,
      });
    }
    return const PetRepositoryException(
      PetRepositoryErrorCode.backendUnavailable,
    );
  }
}
