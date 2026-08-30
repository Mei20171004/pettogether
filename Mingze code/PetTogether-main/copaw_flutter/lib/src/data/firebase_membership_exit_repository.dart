import 'package:cloud_functions/cloud_functions.dart';

import 'firebase_membership_exit_gateway.dart';
import 'membership_exit_gateway.dart';
import 'membership_exit_repository.dart';

final class FirebaseMembershipExitRepository
    implements MembershipExitRepository {
  FirebaseMembershipExitRepository({MembershipExitGateway? gateway})
    : _gateway = gateway ?? FirebaseMembershipExitGateway();

  static const _keys = {
    'householdID',
    'left',
    'disabledInstallationCount',
    'existing',
  };

  final MembershipExitGateway _gateway;

  @override
  Future<HouseholdLeaveResult> leaveHousehold({
    required String householdId,
    required String clientMutationId,
  }) async {
    if (!_id(householdId) || !_id(clientMutationId)) {
      throw const MembershipExitException(MembershipExitErrorCode.invalidInput);
    }
    try {
      final data = await _gateway.leaveHousehold({
        'householdID': householdId,
        'clientMutationID': clientMutationId,
      });
      if (data.length != _keys.length ||
          !data.keys.every(_keys.contains) ||
          data['householdID'] != householdId ||
          data['left'] is! bool ||
          data['disabledInstallationCount'] is! int ||
          (data['disabledInstallationCount'] as int) < 0 ||
          data['existing'] is! bool) {
        throw const MembershipExitException(
          MembershipExitErrorCode.malformedData,
        );
      }
      return HouseholdLeaveResult(
        householdId: householdId,
        left: data['left']! as bool,
        disabledInstallationCount: data['disabledInstallationCount']! as int,
        existing: data['existing']! as bool,
      );
    } on Object catch (error) {
      throw _mapped(error);
    }
  }

  static bool _id(String value) =>
      value.isNotEmpty && value.length <= 128 && !value.contains('/');

  static MembershipExitException _mapped(Object error) {
    if (error is MembershipExitException) return error;
    if (error is! FirebaseFunctionsException) {
      return const MembershipExitException(
        MembershipExitErrorCode.backendUnavailable,
      );
    }
    final details = error.details;
    final diagnosticValue = details is Map
        ? details['blockerCode'] ?? details['code'] ?? details['reason']
        : null;
    return MembershipExitException(switch (error.code) {
      'invalid-argument' => MembershipExitErrorCode.invalidInput,
      'permission-denied' ||
      'unauthenticated' => MembershipExitErrorCode.permission,
      'failed-precondition' => MembershipExitErrorCode.blocked,
      'aborted' => MembershipExitErrorCode.stale,
      'not-found' => MembershipExitErrorCode.notFound,
      'unavailable' ||
      'deadline-exceeded' ||
      'network-request-failed' => MembershipExitErrorCode.network,
      'data-loss' => MembershipExitErrorCode.malformedData,
      _ => MembershipExitErrorCode.backendUnavailable,
    }, diagnosticCode: diagnosticValue is String ? diagnosticValue : null);
  }
}
