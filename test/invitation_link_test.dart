import 'package:flutter_test/flutter_test.dart';

import 'package:pettogether/models/invitation_link.dart';
import 'package:pettogether/models/models.dart';
import 'package:pettogether/services/care_service.dart';

void main() {
  test('generated links carry the real invitation and household ids', () {
    final invitation = HouseholdInvitation(
      id: 'firebase-invitation-123',
      householdId: 'firebase-household-456',
      householdName: 'Mochi Family',
      petNames: const ['Mochi'],
      inviterName: 'Sam',
      invitedBy: 'firebase-user-789',
      status: InvitationStatus.active,
      createdAt: DateTime(2026, 9, 20),
      expiresAt: DateTime(2026, 9, 21),
    );

    final appLink = InvitationLink.tryParse(invitation.deepLink)!;
    expect(appLink.invitationId, invitation.id);
    expect(appLink.householdId, invitation.householdId);
  });

  test('parser accepts app links and bare invitation values', () {
    expect(
      InvitationLink.tryParse(
        'pettogether://invite/invite-1?household=household-1',
      )?.invitationId,
      'invite-1',
    );
    expect(InvitationLink.tryParse('PAW123')?.invitationId, 'PAW123');
  });

  test('parser rejects malformed paths, ids, and foreign hosts', () {
    expect(InvitationLink.tryParse('pettogether://invite'), isNull);
    expect(InvitationLink.tryParse('pettogether://invite/a/b'), isNull);
    expect(InvitationLink.tryParse('pettogether:invite-1'), isNull);
    expect(
      InvitationLink.tryParse('https://example.com/invite/invite-1'),
      isNull,
    );
    expect(
      InvitationLink.tryParse(
        'pettogether://invite/invite-1?household=bad%20id',
      ),
      isNull,
    );
  });

  test('invitation failures retain distinct actionable categories', () {
    final messages = {
      for (final type in const [
        CareServiceErrorType.invalidInvitationLink,
        CareServiceErrorType.invitationExpired,
        CareServiceErrorType.permissionDenied,
        CareServiceErrorType.networkUnavailable,
      ])
        CareServiceError(type).message,
    };

    expect(messages, hasLength(4));
    expect(messages.any((message) => message.contains('expired')), isTrue);
    expect(messages.any((message) => message.contains('permission')), isTrue);
    expect(messages.any((message) => message.contains('offline')), isTrue);
  });
}
