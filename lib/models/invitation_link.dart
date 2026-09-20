/// The single wire format used by copied, shared, scanned, and platform-opened
/// household invitations.
class InvitationLink {
  const InvitationLink({required this.invitationId, this.householdId});

  static const appScheme = 'pettogether';
  static const appHost = 'invite';

  final String invitationId;
  final String? householdId;

  Uri get appUri => Uri(
    scheme: appScheme,
    host: appHost,
    pathSegments: [invitationId],
    queryParameters: householdId == null ? null : {'household': householdId!},
  );

  /// Accepts the platform link shape or a bare invitation id pasted into the
  /// join field. Unknown schemes and malformed paths are rejected.
  static InvitationLink? tryParse(String value) {
    final trimmed = value.trim();
    if (_isValidId(trimmed) && !trimmed.contains('://')) {
      return InvitationLink(invitationId: trimmed);
    }
    final uri = Uri.tryParse(trimmed);
    return uri == null ? null : tryParseUri(uri);
  }

  static InvitationLink? tryParseUri(Uri uri) {
    late final String invitationId;
    if (uri.scheme == appScheme && uri.host == appHost) {
      if (uri.pathSegments.length != 1) return null;
      invitationId = uri.pathSegments.single;
    } else {
      return null;
    }

    final householdId = uri.queryParameters['household'];
    if (!_isValidId(invitationId) ||
        (householdId != null && !_isValidId(householdId))) {
      return null;
    }
    return InvitationLink(invitationId: invitationId, householdId: householdId);
  }

  static bool looksLikeInvitationUri(Uri uri) =>
      uri.scheme == appScheme && uri.host == appHost;

  // Firebase auto ids and this app's UUID/demo ids use this character set.
  // Keeping the accepted alphabet narrow prevents malformed URI-like text
  // from being treated as a Firestore document id.
  static bool _isValidId(String value) =>
      RegExp(r'^[A-Za-z0-9_-]{1,256}$').hasMatch(value);
}
