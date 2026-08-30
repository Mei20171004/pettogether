import 'package:shared_preferences/shared_preferences.dart';

abstract interface class HealthMutationStore {
  Future<String> readOrCreate(
    String requestHash,
    String Function() createRecordId,
  );
  Future<void> clear(String requestHash);
}

final class SharedPreferencesHealthMutationStore
    implements HealthMutationStore {
  SharedPreferencesHealthMutationStore({SharedPreferencesAsync? preferences})
    : _preferences = preferences ?? SharedPreferencesAsync();

  static const _prefix = 'copaw.pendingHealthMutation.';
  static final _inflight = <String, Future<String>>{};
  final SharedPreferencesAsync _preferences;

  @override
  Future<String> readOrCreate(
    String requestHash,
    String Function() createRecordId,
  ) {
    final existing = _inflight[requestHash];
    if (existing != null) return existing;
    final operation = _readOrCreate(requestHash, createRecordId);
    _inflight[requestHash] = operation;
    return operation.whenComplete(() {
      if (identical(_inflight[requestHash], operation)) {
        _inflight.remove(requestHash);
      }
    });
  }

  Future<String> _readOrCreate(
    String requestHash,
    String Function() createRecordId,
  ) async {
    final key = '$_prefix$requestHash';
    final persisted = await _preferences.getString(key);
    if (persisted != null) return persisted;
    final recordId = createRecordId();
    await _preferences.setString(key, recordId);
    return recordId;
  }

  @override
  Future<void> clear(String requestHash) =>
      _preferences.remove('$_prefix$requestHash');
}
