import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:copaw_flutter/src/bootstrap/firebase_emulator_configuration.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

// LT7 connectivity probe and build warm-up. It proves the local build actually
// reaches the isolated Emulator before the coordinated phases start, and it
// deliberately signs in to nothing so the clean-identity precondition of the
// bootstrap phase still holds afterwards.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('local build reaches the isolated Firestore Emulator', (
    tester,
  ) async {
    debugPrint('LT7_PROBE step=start');
    await configureLocalFirebaseEmulators();
    debugPrint('LT7_PROBE step=configured firestorePort=$localFirebaseFirestorePort');
    // Unauthenticated reads are denied by Rules. Receiving that decision proves
    // the client reached the Emulator; a transport failure would time out.
    await expectLater(
      FirebaseFirestore.instance
          .doc('households/lt7-connectivity-probe')
          .get()
          .timeout(const Duration(seconds: 20)),
      throwsA(
        isA<FirebaseException>().having(
          (error) => error.code,
          'code',
          'permission-denied',
        ),
      ),
    );
    debugPrint('LT7_PROBE step=reachable');
  });
}
