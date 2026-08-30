import 'package:shared_preferences/shared_preferences.dart';

abstract interface class ActiveHouseholdStore {
  Future<String?> read();
  Future<void> save(String householdId);
  Future<void> clear();
}

final class PendingHouseholdMarker {
  const PendingHouseholdMarker({
    required this.householdId,
    required this.inviteCode,
  });

  final String householdId;
  final String inviteCode;
}

abstract interface class PendingHouseholdStore {
  Future<PendingHouseholdMarker?> read();
  Future<void> save(PendingHouseholdMarker marker);
  Future<void> clear();
}

final class SharedPreferencesActiveHouseholdStore
    implements ActiveHouseholdStore {
  SharedPreferencesActiveHouseholdStore({SharedPreferencesAsync? preferences})
    : _preferences = preferences ?? SharedPreferencesAsync();

  static const _key = 'copaw.activeHouseholdID';
  final SharedPreferencesAsync _preferences;

  @override
  Future<String?> read() => _preferences.getString(_key);

  @override
  Future<void> save(String householdId) =>
      _preferences.setString(_key, householdId);

  @override
  Future<void> clear() => _preferences.remove(_key);
}

final class SharedPreferencesPendingHouseholdStore
    implements PendingHouseholdStore {
  SharedPreferencesPendingHouseholdStore({SharedPreferencesAsync? preferences})
    : _preferences = preferences ?? SharedPreferencesAsync();

  static const _householdKey = 'copaw.pendingHouseholdID';
  static const _inviteKey = 'copaw.pendingInviteCode';
  final SharedPreferencesAsync _preferences;

  @override
  Future<PendingHouseholdMarker?> read() async {
    final values = await Future.wait([
      _preferences.getString(_householdKey),
      _preferences.getString(_inviteKey),
    ]);
    final householdId = values[0];
    final inviteCode = values[1];
    if (householdId == null || inviteCode == null) return null;
    return PendingHouseholdMarker(
      householdId: householdId,
      inviteCode: inviteCode,
    );
  }

  @override
  Future<void> save(PendingHouseholdMarker marker) async {
    await _preferences.setString(_householdKey, marker.householdId);
    await _preferences.setString(_inviteKey, marker.inviteCode);
  }

  @override
  Future<void> clear() async {
    await _preferences.remove(_householdKey);
    await _preferences.remove(_inviteKey);
  }
}
