import 'package:flutter_test/flutter_test.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import 'package:pettogether/views/pro_view.dart';

void main() {
  Package package(String productId) => Package(
    'fixture',
    PackageType.custom,
    StoreProduct(productId, 'Fixture', 'Fixture', 300, '¥300', 'JPY'),
    const PresentedOfferingContext('default', null, null),
  );

  for (final suffix in ['', ':monthly-autorenewing']) {
    test('add-on packages match their own feature with suffix "$suffix"', () {
      final ai = package('pettogether_ai_monthly$suffix');
      final pets = package('pettogether_multi_pet_monthly$suffix');
      expect(ProFeature.ai.matches(ai), isTrue);
      expect(ProFeature.multiPet.matches(pets), isTrue);
      expect(ProFeature.ai.matches(pets), isFalse);
      expect(ProFeature.multiPet.matches(ai), isFalse);
      expect(ProFeature.health.matches(ai), isFalse);
      expect(ProFeature.health.matches(pets), isFalse);
    });
  }

  test('Pro accepts both plans and excludes unrelated subscriptions', () {
    for (final id in [
      'pettogether_pro_monthly',
      'pettogether_pro_yearly',
      'pettogether_pro_monthly:monthly-autorenewing',
      'pettogether_pro_yearly:annual-autorenewing',
    ]) {
      expect(ProFeature.health.matches(package(id)), isTrue);
    }
    for (final feature in ProFeature.values) {
      expect(feature.matches(package('other_subscription:monthly')), isFalse);
    }
  });
}
