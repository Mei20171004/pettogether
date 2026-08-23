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
/// icons for most species, so emoji are clearer here).
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
    case PetType.fish:
      return '🐟';
    case PetType.hamster:
      return '🐹';
    case PetType.guineaPig:
      return '🐭';
    case PetType.ferret:
      return '🦡';
    case PetType.turtle:
      return '🐢';
    case PetType.reptile:
      return '🦎';
    case PetType.amphibian:
      return '🐸';
    case PetType.horse:
      return '🐴';
    case PetType.other:
      return '🐾';
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
    PetType.fish => L10n.text(language, 'Fish', '魚', '鱼', '물고기'),
    PetType.hamster => L10n.text(language, 'Hamster', 'ハムスター', '仓鼠', '햄스터'),
    PetType.guineaPig => L10n.text(language, 'Guinea pig', 'モルモット', '豚鼠', '기니피그'),
    PetType.ferret => L10n.text(language, 'Ferret', 'フェレット', '雪貂', '페럿'),
    PetType.turtle => L10n.text(language, 'Turtle', 'カメ', '乌龟', '거북이'),
    PetType.reptile => L10n.text(language, 'Reptile', '爬虫類', '爬行动物', '파충류'),
    PetType.amphibian => L10n.text(language, 'Amphibian', '両生類', '两栖动物', '양서류'),
    PetType.horse => L10n.text(language, 'Horse', '馬', '马', '말'),
    PetType.other => L10n.text(language, 'Other', 'その他', '其他', '기타'),
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
    case PetType.fish:
      return PawColors.blue;
    case PetType.hamster:
      return PawColors.peach;
    case PetType.guineaPig:
      return PawColors.yellow;
    case PetType.ferret:
      return PawColors.rose;
    case PetType.turtle:
      return PawColors.green;
    case PetType.reptile:
      return PawColors.green;
    case PetType.amphibian:
      return PawColors.blue;
    case PetType.horse:
      return PawColors.rose;
    case PetType.other:
      return PawColors.muted;
  }
}
