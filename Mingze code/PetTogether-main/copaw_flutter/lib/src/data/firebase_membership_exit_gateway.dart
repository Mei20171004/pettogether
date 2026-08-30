import 'package:cloud_functions/cloud_functions.dart';

import 'membership_exit_gateway.dart';

final class FirebaseMembershipExitGateway implements MembershipExitGateway {
  FirebaseMembershipExitGateway({FirebaseFunctions? functions})
    : _functions =
          functions ?? FirebaseFunctions.instanceFor(region: 'asia-northeast1');

  final FirebaseFunctions _functions;

  @override
  Future<Map<String, Object?>> leaveHousehold(
    Map<String, Object?> payload,
  ) async {
    final response = await _functions
        .httpsCallable('leaveHousehold')
        .call(payload);
    if (response.data is! Map) {
      throw FirebaseFunctionsException(
        code: 'internal',
        message: 'Unexpected leave household response.',
      );
    }
    return Map<String, Object?>.from(response.data as Map);
  }
}
