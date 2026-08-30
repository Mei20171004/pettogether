import 'package:cloud_functions/cloud_functions.dart';
import 'package:copaw_flutter/src/data/firebase_membership_exit_repository.dart';
import 'package:copaw_flutter/src/data/membership_exit_gateway.dart';
import 'package:copaw_flutter/src/data/membership_exit_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'true leave sends exact payload and decodes idempotent result',
    () async {
      final gateway = _FakeGateway();
      final repository = FirebaseMembershipExitRepository(gateway: gateway);

      final result = await repository.leaveHousehold(
        householdId: 'home-a',
        clientMutationId: 'leave-a',
      );

      expect(gateway.payload, {
        'householdID': 'home-a',
        'clientMutationID': 'leave-a',
      });
      expect(result.left, isTrue);
      expect(result.disabledInstallationCount, 2);
      expect(result.existing, isTrue);
    },
  );

  test('blocker code is preserved without source identifiers', () async {
    final gateway = _FakeGateway()
      ..error = FirebaseFunctionsException(
        code: 'failed-precondition',
        message: 'blocked',
        details: {'blockerCode': 'pendingTransfer'},
      );
    final repository = FirebaseMembershipExitRepository(gateway: gateway);

    await expectLater(
      repository.leaveHousehold(
        householdId: 'home-a',
        clientMutationId: 'leave-a',
      ),
      throwsA(
        isA<MembershipExitException>()
            .having(
              (error) => error.code,
              'code',
              MembershipExitErrorCode.blocked,
            )
            .having(
              (error) => error.diagnosticCode,
              'diagnosticCode',
              'pendingTransfer',
            ),
      ),
    );
  });
}

final class _FakeGateway implements MembershipExitGateway {
  Map<String, Object?>? payload;
  Object? error;

  @override
  Future<Map<String, Object?>> leaveHousehold(
    Map<String, Object?> payload,
  ) async {
    this.payload = payload;
    if (error case final caught?) throw caught;
    return {
      'householdID': payload['householdID'],
      'left': true,
      'disabledInstallationCount': 2,
      'existing': true,
    };
  }
}
