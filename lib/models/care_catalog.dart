import 'dart:math';

import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../theme/app_theme.dart';
import 'models.dart';

/// Species tags: which pet types each built-in care module applies to.
/// A null value means the module is general (applies to every pet type).
final Map<CareCategory, Set<PetType>?> _speciesTags = {
  CareCategory.feeding: null,
  CareCategory.walking: null,
  CareCategory.medication: null,
  CareCategory.grooming: null,
  CareCategory.hospital: null,
  CareCategory.deworming: null,
  CareCategory.nailTrim: null,
  CareCategory.water: null,
  CareCategory.other: null,
  CareCategory.catLitter: {PetType.cat},
  CareCategory.newFood: {PetType.cat},
  CareCategory.peePad: {PetType.cat, PetType.dog, PetType.rabbit},
  CareCategory.dogBath: {PetType.dog},
  CareCategory.dogTraining: {PetType.dog},
  CareCategory.birdCage: {PetType.bird},
  CareCategory.birdFeather: {PetType.bird},
  CareCategory.rabbitHay: {PetType.rabbit},
  CareCategory.rabbitBedding: {PetType.rabbit},
  CareCategory.snakeFeed: {PetType.snake},
  CareCategory.snakeShed: {PetType.snake},
  CareCategory.snakeTerrarium: {PetType.snake},
};

/// Built-in care modules relevant to [petType] (general + species-specific),
/// ordered so the most everyday modules come first.
List<CareCategory> categoriesForPetType(PetType petType) {
  return CareCategory.builtIns
      .where((c) => _speciesTags[c]?.contains(petType) ?? true)
      .toList();
}

const _customIdAlphabet = 'abcdefghijklmnopqrstuvwxyz0123456789';

/// Generates a short, collision-resistant id for a user-created care module.
String generateCustomCategoryId() {
  final random = Random();
  final buffer = StringBuffer('cus_');
  for (var i = 0; i < 8; i++) {
    buffer.write(_customIdAlphabet[random.nextInt(_customIdAlphabet.length)]);
  }
  return buffer.toString();
}

/// A user-friendly emoji per pet type (the Material icon set has no distinct
/// icons for cat/dog/bird/rabbit/snake, so emoji are clearer here).
String petTypeEmoji(PetType type) {
  switch (type) {
    case PetType.cat:
      return '🐱';
    case PetType.dog:
      return '🐶';
    case PetType.bird:
      return '🐦';
    case PetType.rabbit:
      return '🐰';
    case PetType.snake:
      return '🐍';
  }
}

/// Localized pet type name.
String petTypeName(AppLanguage language, PetType type) {
  return switch (type) {
    PetType.cat => L10n.text(language, 'Cat', '猫', '猫', '고양이'),
    PetType.dog => L10n.text(language, 'Dog', '犬', '狗', '개'),
    PetType.bird => L10n.text(language, 'Bird', '鳥', '鸟', '새'),
    PetType.rabbit => L10n.text(language, 'Rabbit', 'うさぎ', '兔子', '토끼'),
    PetType.snake => L10n.text(language, 'Snake', 'ヘビ', '蛇', '뱀'),
  };
}

Color petTypeAccent(PetType type) {
  switch (type) {
    case PetType.cat:
      return PawColors.purple;
    case PetType.dog:
      return PawColors.blue;
    case PetType.bird:
      return PawColors.yellow;
    case PetType.rabbit:
      return PawColors.peach;
    case PetType.snake:
      return PawColors.green;
  }
}
