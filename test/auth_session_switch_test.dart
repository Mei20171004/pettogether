import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pettogether/models/health.dart';
import 'package:pettogether/models/models.dart';
import 'package:pettogether/services/mock_care_service.dart';
import 'package:pettogether/store/care_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'switching accounts clears the old household before a new restore',
    () async {
      final service = _AccountCareService();
      final store = CareStore(service);
      addTearDown(store.dispose);

      service.userId = 'alice';
      store.setAuthenticatedUser('alice');
      await store.restoreSession();
      expect(store.household?.id, 'household-alice');
      final oldObserver = service.householdObserver!;

      store.setAuthenticatedUser(null);
      expect(store.household, isNull);
      expect(store.currentCaregiver, isNull);
      expect(store.isRestoringSession, isFalse);

      service.userId = 'bob';
      service.usersWithoutHousehold.add('bob');
      store.setAuthenticatedUser('bob');
      expect(store.household, isNull);
      expect(store.isRestoringSession, isTrue);

      oldObserver(_AccountCareService.sessionFor('alice').household);
      expect(store.household, isNull);

      await store.restoreSession();
      expect(store.household, isNull);
      expect(store.isRestoringSession, isFalse);

      service.userId = 'carol';
      store.setAuthenticatedUser('carol');
      await store.restoreSession();
      expect(store.household?.id, 'household-carol');
      expect(store.currentCaregiver?.id, 'carol');
    },
  );

  test('an old account restore cannot overwrite a newer account', () async {
    final service = _AccountCareService();
    final store = CareStore(service);
    addTearDown(store.dispose);

    service.userId = 'alice';
    service.delayedAliceRestore = Completer<CareSession?>();
    store.setAuthenticatedUser('alice');
    final oldRestore = store.restoreSession();

    service.userId = 'bob';
    store.setAuthenticatedUser('bob');
    await store.restoreSession();
    expect(store.household?.id, 'household-bob');

    service.delayedAliceRestore!.complete(
      _AccountCareService.sessionFor('alice'),
    );
    await oldRestore;
    expect(store.household?.id, 'household-bob');
    expect(store.currentCaregiver?.id, 'bob');
  });
}

class _AccountCareService extends MockCareService {
  String? userId;
  final Set<String> usersWithoutHousehold = {};
  Completer<CareSession?>? delayedAliceRestore;
  void Function(Household)? householdObserver;

  static CareSession sessionFor(String userId) => CareSession(
    household: Household(
      id: 'household-$userId',
      name: '$userId family',
      inviteCode: '',
      ownerID: userId,
    ),
    caregiver: Caregiver(id: userId, displayName: userId),
  );

  @override
  Future<CareSession?> restoreSession() async {
    final currentUserId = userId;
    if (currentUserId == 'alice' && delayedAliceRestore != null) {
      return delayedAliceRestore!.future;
    }
    return currentUserId == null ||
            usersWithoutHousehold.contains(currentUserId)
        ? null
        : sessionFor(currentUserId);
  }

  @override
  void observeHousehold({
    required String householdID,
    required void Function(Household) onChange,
    required void Function(Object error) onError,
  }) {
    householdObserver = onChange;
  }

  @override
  void observeTasks({
    required String householdID,
    required void Function(List<CareTask>) onChange,
    required void Function(Object error) onError,
  }) {}

  @override
  void observeCaregivers({
    required String householdID,
    required void Function(List<Caregiver>) onChange,
    required void Function(Object error) onError,
  }) {}

  @override
  void observeRoutines({
    required String householdID,
    required void Function(List<CareRoutine>) onChange,
    required void Function(Object error) onError,
  }) {}

  @override
  void observeMedicationPlans({
    required String householdID,
    required void Function(List<MedicationPlan>) onChange,
    required void Function(Object error) onError,
  }) {}

  @override
  void observeHealthRecords({
    required String householdID,
    required void Function(List<HealthRecord>) onChange,
    required void Function(Object error) onError,
  }) {}

  @override
  Future<HouseholdInvitation?> getActiveInvitation(String householdID) async =>
      null;
}
