abstract interface class MembershipExitGateway {
  Future<Map<String, Object?>> leaveHousehold(Map<String, Object?> payload);
}
