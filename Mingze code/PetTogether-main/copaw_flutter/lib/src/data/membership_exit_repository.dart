import 'package:flutter_riverpod/flutter_riverpod.dart';

final class HouseholdLeaveResult {
  const HouseholdLeaveResult({
    required this.householdId,
    required this.left,
    required this.disabledInstallationCount,
    required this.existing,
  });

  final String householdId;
  final bool left;
  final int disabledInstallationCount;
  final bool existing;
}

enum MembershipExitErrorCode {
  invalidInput,
  permission,
  blocked,
  stale,
  notFound,
  network,
  malformedData,
  backendUnavailable,
}

final class MembershipExitException implements Exception {
  const MembershipExitException(this.code, {this.diagnosticCode});

  final MembershipExitErrorCode code;
  final String? diagnosticCode;
}

abstract interface class MembershipExitRepository {
  Future<HouseholdLeaveResult> leaveHousehold({
    required String householdId,
    required String clientMutationId,
  });
}

final membershipExitRepositoryProvider = Provider<MembershipExitRepository>((
  ref,
) {
  throw StateError(
    'MembershipExitRepository must be provided at the app boundary.',
  );
});

final class FakeMembershipExitRepository implements MembershipExitRepository {
  Object? nextError;
  final calls = <Map<String, String>>[];

  @override
  Future<HouseholdLeaveResult> leaveHousehold({
    required String householdId,
    required String clientMutationId,
  }) async {
    calls.add({
      'householdID': householdId,
      'clientMutationID': clientMutationId,
    });
    if (nextError case final error?) {
      nextError = null;
      throw error;
    }
    return HouseholdLeaveResult(
      householdId: householdId,
      left: true,
      disabledInstallationCount: 0,
      existing: false,
    );
  }
}
