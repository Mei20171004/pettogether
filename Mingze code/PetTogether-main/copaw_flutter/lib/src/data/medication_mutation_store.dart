import 'package:shared_preferences/shared_preferences.dart';

abstract interface class MedicationMutationStore {
  Future<String> readOrCreate(
    String requestHash,
    String Function() createMutationId,
  );
  Future<void> clear(String requestHash);
}

final class SharedPreferencesMedicationMutationStore
    implements MedicationMutationStore {
  SharedPreferencesMedicationMutationStore({
    SharedPreferencesAsync? preferences,
  }) : _preferences = preferences ?? SharedPreferencesAsync();

  static const _prefix = 'copaw.pendingMedicationMutation.';
  static final _inflight = <String, Future<String>>{};
  final SharedPreferencesAsync _preferences;

  @override
  Future<String> readOrCreate(
    String requestHash,
    String Function() createMutationId,
  ) {
    final existing = _inflight[requestHash];
    if (existing != null) return existing;
    final operation = _readOrCreate(requestHash, createMutationId);
    _inflight[requestHash] = operation;
    return operation.whenComplete(() {
      if (identical(_inflight[requestHash], operation)) {
        _inflight.remove(requestHash);
      }
    });
  }

  Future<String> _readOrCreate(
    String requestHash,
    String Function() createMutationId,
  ) async {
    final key = '$_prefix$requestHash';
    final persisted = await _preferences.getString(key);
    if (persisted != null) return persisted;
    final mutationId = createMutationId();
    await _preferences.setString(key, mutationId);
    return mutationId;
  }

  @override
  Future<void> clear(String requestHash) =>
      _preferences.remove('$_prefix$requestHash');
}
