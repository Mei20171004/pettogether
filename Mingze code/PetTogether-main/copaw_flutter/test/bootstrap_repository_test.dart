import 'package:copaw_flutter/src/bootstrap/bootstrap_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('fake bootstrap repository consumes deterministic outcomes', () async {
    final repository = FakeBootstrapRepository([
      StateError('unavailable'),
      BootstrapResult.noHousehold,
    ]);

    await expectLater(repository.initialize(), throwsStateError);
    expect(await repository.initialize(), BootstrapResult.noHousehold);
    expect(repository.attempts, 2);
  });
}
