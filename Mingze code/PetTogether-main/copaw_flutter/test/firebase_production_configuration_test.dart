import 'package:copaw_flutter/src/bootstrap/firebase_production_configuration.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('production Firebase options fail closed when incomplete', () {
    expect(
      productionFirebaseOptions(
        apiKey: '',
        appId: 'app',
        messagingSenderId: 'sender',
        projectId: 'copaw-production',
      ),
      isNull,
    );
    expect(
      productionFirebaseOptions(
        apiKey: 'key',
        appId: 'app',
        messagingSenderId: 'sender',
        projectId: 'demo-copaw',
      ),
      isNull,
    );
  });

  test('production Firebase options use an explicit non-emulator identity', () {
    final options = productionFirebaseOptions(
      apiKey: 'synthetic-key',
      appId: 'synthetic-app',
      messagingSenderId: 'synthetic-sender',
      projectId: 'synthetic-production',
    );

    expect(options?.projectId, 'synthetic-production');
    expect(options?.apiKey, 'synthetic-key');
  });
}
