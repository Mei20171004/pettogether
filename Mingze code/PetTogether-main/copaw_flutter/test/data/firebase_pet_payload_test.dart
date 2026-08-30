import 'package:copaw_flutter/src/data/firebase_pet_gateway.dart';
import 'package:copaw_flutter/src/data/pet_gateway.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const serverTime = _ServerTime();
  final builder = PetWritePayloadBuilder(serverTimestamp: () => serverTime);

  test('create payload stores a complete stable pet snapshot', () {
    const command = CreatePetCommand(
      householdId: 'home-a',
      petId: 'pet-a',
      name: 'Mochi',
      species: 'dog',
    );

    final payload = builder.newPet(command);
    expect(payload, {
      'id': 'pet-a',
      'name': 'Mochi',
      'species': 'dog',
      'isArchived': false,
      'createdAt': serverTime,
      'updatedAt': serverTime,
    });
    expect(identical(payload['createdAt'], payload['updatedAt']), isTrue);
  });

  test('rename only updates mutable profile fields', () {
    expect(
      builder.renamePet(
        const RenamePetCommand(
          householdId: 'home-a',
          petId: 'pet-a',
          name: 'Nori',
        ),
      ),
      {'name': 'Nori', 'updatedAt': serverTime},
    );
  });

  test(
    'legacy rename can materialize the pet and preserve Swift household compatibility',
    () {
      const command = RenamePetCommand(
        householdId: 'home-a',
        petId: 'legacy-primary',
        name: 'Nori',
      );
      final pet = builder.materializedLegacyPet(command);
      expect(pet, {
        'id': 'legacy-primary',
        'name': 'Nori',
        'species': null,
        'isArchived': false,
        'createdAt': serverTime,
        'updatedAt': serverTime,
      });
      expect(identical(pet['createdAt'], pet['updatedAt']), isTrue);
      expect(builder.renameLegacyHousehold(command), {
        'petName': 'Nori',
        'updatedAt': serverTime,
      });
    },
  );
}

final class _ServerTime {
  const _ServerTime();
}
