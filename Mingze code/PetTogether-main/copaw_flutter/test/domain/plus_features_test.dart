import 'package:copaw_flutter/src/domain/plus_features.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every Plus feature is available to every household today', () {
    const access = PlusFeatureAccess();

    for (final feature in PlusFeature.values) {
      expect(access.isAvailable(feature), isTrue, reason: feature.name);
    }
    expect(access.availableFeatures, PlusFeature.values.toSet());
  });
}
