import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:copaw_flutter/src/data/firebase_pet_repository.dart';
import 'package:copaw_flutter/src/data/household_data_gateway.dart';
import 'package:copaw_flutter/src/data/pet_gateway.dart';
import 'package:copaw_flutter/src/data/pet_repository.dart';
import 'package:copaw_flutter/src/domain/legacy_firestore_codec.dart';
import 'package:copaw_flutter/src/domain/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late FakePetGateway gateway;
  late FirebasePetRepository repository;

  setUp(() {
    gateway = FakePetGateway();
    repository = FirebasePetRepository(gateway: gateway);
  });

  tearDown(() => repository.stopObserving());

  test('empty pet collection synthesizes the legacy household pet', () async {
    final events = <PetSnapshot>[];
    repository.observePets('home-a').listen(events.add);
    await _settle();
    gateway.households['home-a']!.add(_household('home-a', 'Mochi'));
    gateway.pets['home-a']!.add([]);
    await _settle();

    expect(events.single.pets, hasLength(1));
    expect(events.single.pets.single.id, legacyPrimaryPetId);
    expect(events.single.pets.single.name, 'Mochi');
    expect(events.single.pets.single.isArchived, isFalse);
    expect(events.single.pets.single.isSynthesizedLegacy, isTrue);
    expect(
      events.single.diagnostics.map((item) => item.code),
      contains(DomainDiagnosticCode.legacySynthesizedPet),
    );
  });

  test('real legacy-primary document wins without duplication', () async {
    final events = <PetSnapshot>[];
    repository.observePets('home-a').listen(events.add);
    await _settle();
    gateway.households['home-a']!.add(_household('home-a', 'Old name'));
    gateway.pets['home-a']!.add([
      _pet(legacyPrimaryPetId, 'Current name', isArchived: true),
      _pet('pet-b', 'Nori'),
    ]);
    await _settle();

    expect(events.single.pets, hasLength(2));
    expect(
      events.single.pets.where((pet) => pet.id == legacyPrimaryPetId),
      hasLength(1),
    );
    expect(
      events.single.pets
          .singleWhere((pet) => pet.id == legacyPrimaryPetId)
          .name,
      'Current name',
    );
    expect(events.single.pets.last.isArchived, isTrue);
    expect(
      events.single.diagnostics.map((item) => item.code),
      isNot(contains(DomainDiagnosticCode.legacySynthesizedPet)),
    );
  });

  test('legacy pet remains visible beside a newly added pet', () async {
    final events = <PetSnapshot>[];
    repository.observePets('home-a').listen(events.add);
    await _settle();
    gateway.households['home-a']!.add(_household('home-a', 'Mochi'));
    gateway.pets['home-a']!.add([_pet('pet-b', 'Nori')]);
    await _settle();

    expect(events.single.pets, hasLength(2));
    expect(
      events.single.pets.map((pet) => pet.id),
      containsAll([legacyPrimaryPetId, 'pet-b']),
    );
  });

  test(
    'malformed real pet is reported instead of shadowed by synthesis',
    () async {
      final events = <PetSnapshot>[];
      repository.observePets('home-a').listen(events.add);
      await _settle();
      gateway.households['home-a']!.add(_household('home-a', 'Mochi'));
      gateway.pets['home-a']!.add([
        const StoredDocument(
          id: legacyPrimaryPetId,
          exists: true,
          data: {'name': 'Broken'},
        ),
      ]);
      await _settle();

      expect(events.single.pets, isEmpty);
      expect(
        events.single.diagnostics.single.code,
        DomainDiagnosticCode.malformedData,
      );
    },
  );

  test('session replacement cancels both old listeners', () async {
    final first = <PetSnapshot>[];
    final second = <PetSnapshot>[];
    repository.observePets('home-a').listen(first.add);
    await _settle();
    repository.observePets('home-b').listen(second.add);
    await _settle();

    gateway.households['home-a']!.add(_household('home-a', 'Old'));
    gateway.pets['home-a']!.add([]);
    gateway.households['home-b']!.add(_household('home-b', 'New'));
    gateway.pets['home-b']!.add([]);
    await _settle();

    expect(first, isEmpty);
    expect(second.single.pets.single.name, 'New');
    expect(gateway.cancelled, containsAll(['h:home-a', 'p:home-a']));
  });

  test('create rename and archive normalize and preserve commands', () async {
    final id = await repository.createPet(
      householdId: 'home-a',
      name: ' Mochi ',
      species: PetSpecies.dog,
    );
    await repository.renamePet(
      householdId: 'home-a',
      petId: id,
      name: ' Nori ',
    );
    await repository.archivePet(householdId: 'home-a', petId: id);

    expect(id, 'pet-a');
    expect(gateway.created.single.name, 'Mochi');
    expect(gateway.created.single.species, 'dog');
    expect(gateway.renamed.single.name, 'Nori');
    expect(gateway.archived.single.petId, 'pet-a');
  });

  test('invalid inputs are classified before any write', () async {
    await expectLater(
      repository.createPet(householdId: 'home-a', name: ' ', species: null),
      throwsA(
        isA<PetRepositoryException>().having(
          (error) => error.code,
          'code',
          PetRepositoryErrorCode.invalidInput,
        ),
      ),
    );
    await expectLater(
      repository.renamePet(
        householdId: 'home-a',
        petId: 'bad/id',
        name: 'Nori',
      ),
      throwsA(isA<PetRepositoryException>()),
    );
    expect(gateway.created, isEmpty);
    expect(gateway.renamed, isEmpty);
  });

  test('listener and writer provider failures use stable categories', () async {
    final errors = <Object>[];
    repository.observePets('home-a').listen((_) {}, onError: errors.add);
    await _settle();
    gateway.pets['home-a']!.addError(
      FirebaseException(plugin: 'cloud_firestore', code: 'unavailable'),
    );
    await _settle();
    expect(
      (errors.single as PetRepositoryException).code,
      PetRepositoryErrorCode.network,
    );

    gateway.createError = FirebaseException(
      plugin: 'cloud_firestore',
      code: 'permission-denied',
    );
    await expectLater(
      repository.createPet(householdId: 'home-a', name: 'Mochi', species: null),
      throwsA(
        isA<PetRepositoryException>().having(
          (error) => error.code,
          'code',
          PetRepositoryErrorCode.permission,
        ),
      ),
    );
  });
}

StoredDocument _household(String id, String petName) => StoredDocument(
  id: id,
  exists: true,
  data: {
    'name': 'Home',
    'inviteCode': 'ABC234',
    'petName': petName,
    'timeZoneIdentifier': 'Asia/Tokyo',
  },
);

StoredDocument _pet(String id, String name, {bool isArchived = false}) =>
    StoredDocument(
      id: id,
      exists: true,
      data: {
        'id': id,
        'name': name,
        'species': null,
        'isArchived': isArchived,
        'createdAt': Timestamp.fromDate(DateTime.utc(2026, 8, 12)),
        'updatedAt': Timestamp.fromDate(DateTime.utc(2026, 8, 12)),
      },
    );

Future<void> _settle() => Future<void>.delayed(Duration.zero);

final class FakePetGateway implements PetGateway {
  final households = <String, StreamController<StoredDocument>>{};
  final pets = <String, StreamController<List<StoredDocument>>>{};
  final created = <CreatePetCommand>[];
  final renamed = <RenamePetCommand>[];
  final archived = <ArchivePetCommand>[];
  final cancelled = <String>[];
  Object? createError;

  @override
  Stream<StoredDocument> observeHousehold(String householdId) {
    final controller = StreamController<StoredDocument>.broadcast(
      onCancel: () => cancelled.add('h:$householdId'),
    );
    households[householdId] = controller;
    return controller.stream;
  }

  @override
  Stream<List<StoredDocument>> observePets(String householdId) {
    final controller = StreamController<List<StoredDocument>>.broadcast(
      onCancel: () => cancelled.add('p:$householdId'),
    );
    pets[householdId] = controller;
    return controller.stream;
  }

  @override
  String newPetId(String householdId) => 'pet-a';

  @override
  Future<void> createPet(CreatePetCommand command) async {
    if (createError case final Object error) throw error;
    created.add(command);
  }

  @override
  Future<void> renamePet(RenamePetCommand command) async {
    renamed.add(command);
  }

  @override
  Future<void> archivePet(ArchivePetCommand command) async {
    archived.add(command);
  }
}
