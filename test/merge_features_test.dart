// Tests for the merged Kate features: extended pet types, multi-pet task ids,
// the invitation (link/QR + approval) flow, and skip/restore occurrences.

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pettogether/models/models.dart';
import 'package:pettogether/services/mock_care_service.dart';
import 'package:pettogether/store/care_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('models', () {
    test('PetType covers all 14 species and round-trips', () {
      expect(PetType.values.length, 14);
      for (final type in PetType.values) {
        expect(PetType.fromRaw(type.rawValue), type);
      }
      expect(PetType.fromRaw('guineaPig'), PetType.guineaPig);
      expect(PetType.fromRaw('snake'), PetType.snake);
      expect(PetType.fromRaw('unknown-value'), PetType.cat);
    });

    test('CareTaskStatus round-trips including skipped', () {
      for (final status in CareTaskStatus.values) {
        expect(CareTaskStatus.fromRaw(status.rawValue), status);
      }
      expect(CareTaskStatus.fromRaw('pending'), CareTaskStatus.unclaimed);
    });

    test('CareTask petIds fall back to legacy petID', () {
      final legacy = CareTask.fromJson({
        'id': 't1',
        'title': 'Brush coat',
        'category': 'grooming',
        'dueTime': DateTime.now().millisecondsSinceEpoch,
        'kind': 'routine',
        'status': 'unclaimed',
        'createdBy': 'Alex',
        'petID': 'pet-1',
      });
      expect(legacy.effectivePetIds, ['pet-1']);

      final modern = CareTask.fromJson({
        'id': 't2',
        'title': 'Walk',
        'category': 'walking',
        'dueTime': DateTime.now().millisecondsSinceEpoch,
        'kind': 'routine',
        'status': 'skipped',
        'createdBy': 'Alex',
        'petIds': ['pet-1', 'pet-2'],
      });
      expect(modern.effectivePetIds, ['pet-1', 'pet-2']);

      final roundTrip = CareTask.fromJson(modern.toJson());
      expect(roundTrip.effectivePetIds, ['pet-1', 'pet-2']);
      expect(roundTrip.status, CareTaskStatus.skipped);
    });

    test('HouseholdInvitation deep link parses back to the id', () {
      final invitation = HouseholdInvitation(
        id: 'inv-123',
        householdId: 'hh-1',
        householdName: 'Mochi Family',
        petNames: const ['Mochi'],
        inviterName: 'Alex',
        invitedBy: 'u-1',
        status: InvitationStatus.active,
        createdAt: DateTime.now(),
        expiresAt: DateTime.now().add(const Duration(hours: 24)),
      );
      expect(invitation.deepLink, 'copaw://invite/inv-123');
      expect(invitation.isActive, isTrue);
      final parsed = Uri.parse(invitation.deepLink);
      expect(parsed.scheme, 'copaw');
      expect(parsed.host, 'invite');
      expect(parsed.pathSegments.last, 'inv-123');
    });
  });

  group('invitation flow (mock auto-approve)', () {
    test('preview PAW123 then request to join enters the household', () async {
      final store = CareStore(MockCareService());
      await store.restoreSession();
      expect(store.household, isNull);
      expect(store.pendingJoinRequest, isNull);

      await store.previewInvitation('PAW123');
      expect(store.invitationPreview, isNotNull);
      expect(store.invitationPreview!.householdName, 'Mochi Family');

      await store.requestToJoin(caregiverName: 'Bob');
      // The mock emits pending → approved; give the stream a tick.
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(store.household, isNotNull);
      expect(store.currentCaregiver?.displayName, 'Bob');
    });

    test('deep-link preview works through the store', () async {
      final store = CareStore(MockCareService());
      await store.restoreSession();
      await store.previewInvitation('copaw://invite/PAW123');
      expect(store.invitationPreview, isNotNull);
    });

    test('creating and revoking an invitation', () async {
      final store = CareStore(MockCareService());
      await store.restoreSession();
      await store.createHousehold(
        name: 'Demo Home',
        pets: [Pet(id: 'p1', name: 'Mochi', type: PetType.cat)],
        caregiverName: 'Me',
      );
      await store.createInvitation();
      expect(store.activeInvitation, isNotNull);
      expect(store.isOwner, isTrue);
      await store.revokeInvitation();
      expect(store.activeInvitation, isNull);
    });
  });

  group('skip / restore occurrences', () {
    test('skips a routine occurrence then restores it', () async {
      final store = CareStore(MockCareService());
      await store.restoreSession();
      await store.createHousehold(
        name: 'Demo Home',
        pets: [Pet(id: 'p1', name: 'Mochi', type: PetType.cat)],
        caregiverName: 'Me',
      );

      final routineTask = store.todayTasks.firstWhere(
        (t) =>
            t.kind == CareTaskKind.routine &&
            t.status == CareTaskStatus.unclaimed,
      );
      expect(await store.skipTaskOccurrence(routineTask), isTrue);
      expect(store.skippedTasks, isNotEmpty);

      final skipped = store.skippedTasks.first;
      expect(await store.restoreTaskOccurrence(skipped), isTrue);
      expect(store.skippedTasks, isEmpty);
    });
  });
}
