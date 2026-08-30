// ignore_for_file: prefer_initializing_formals

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/notification_models.dart';
import 'notification_center_gateway.dart';
import 'notification_center_repository.dart';

abstract interface class NotificationPendingRouteStore {
  Future<NotificationPendingRoute?> read();
  Future<void> write(NotificationPendingRoute route);
  Future<bool> compareAndSet({
    required NotificationPendingRoute expected,
    required NotificationPendingRoute next,
  });
  Future<void> clear();
}

final class MemoryNotificationPendingRouteStore
    implements NotificationPendingRouteStore {
  NotificationPendingRoute? value;

  @override
  Future<NotificationPendingRoute?> read() async => value;

  @override
  Future<void> write(NotificationPendingRoute route) async => value = route;

  @override
  Future<bool> compareAndSet({
    required NotificationPendingRoute expected,
    required NotificationPendingRoute next,
  }) async {
    if (!_sameRoute(value, expected)) return false;
    value = next;
    return true;
  }

  @override
  Future<void> clear() async => value = null;
}

final class SharedPreferencesNotificationPendingRouteStore
    implements NotificationPendingRouteStore {
  SharedPreferencesNotificationPendingRouteStore({
    SharedPreferencesAsync? store,
  }) : _store = store ?? SharedPreferencesAsync();

  static const key = 'copaw.notification.pendingRoute.v1';
  final SharedPreferencesAsync _store;

  @override
  Future<NotificationPendingRoute?> read() async {
    final raw = await _store.getString(key);
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) throw const FormatException();
      const keys = {
        'schemaVersion',
        'destination',
        'householdID',
        'inboxItemID',
        'state',
        'generation',
      };
      if (decoded.length != keys.length ||
          !decoded.keys.every(keys.contains) ||
          decoded['schemaVersion'] != '1' ||
          decoded['destination'] != 'notificationInbox' ||
          !_id(decoded['householdID']) ||
          !_intentId(decoded['inboxItemID']) ||
          decoded['generation'] is! int ||
          (decoded['generation'] as int) <= 0) {
        throw const FormatException();
      }
      final state = _enum(
        NotificationPendingRouteState.values,
        decoded['state'],
      );
      if (state == null) throw const FormatException();
      return NotificationPendingRoute(
        payload: NotificationRoutePayload(
          householdId: decoded['householdID'] as String,
          inboxItemId: decoded['inboxItemID'] as String,
        ),
        state: state,
        generation: decoded['generation'] as int,
      );
    } on Object {
      await clear();
      throw const NotificationCenterException(
        NotificationCenterErrorCode.malformed,
      );
    }
  }

  @override
  Future<void> write(NotificationPendingRoute route) => _store.setString(
    key,
    jsonEncode({
      ...route.payload.toJson(),
      'state': route.state.name,
      'generation': route.generation,
    }),
  );

  @override
  Future<bool> compareAndSet({
    required NotificationPendingRoute expected,
    required NotificationPendingRoute next,
  }) async {
    final current = await read();
    if (!_sameRoute(current, expected)) return false;
    await write(next);
    return true;
  }

  @override
  Future<void> clear() => _store.remove(key);
}

final class StoredNotificationInteractionRepository
    implements NotificationInteractionRepository {
  StoredNotificationInteractionRepository({
    required NotificationCenterGateway gateway,
    required NotificationPendingRouteStore store,
  }) : _gateway = gateway,
       _store = store;

  final NotificationCenterGateway _gateway;
  final NotificationPendingRouteStore _store;
  int _generation = 0;
  Future<void> _pendingStoreMutation = Future<void>.value();

  @override
  Future<NotificationPendingRoute?> readPendingRoute() =>
      _serializeStore(() async {
        final stored = await _store.read();
        if (stored == null) return null;
        _generation = stored.generation > _generation
            ? stored.generation
            : _generation;
        final normalized = stored.normalizedForLaunch();
        if (normalized.state == stored.state) return normalized;
        final updated = await _store.compareAndSet(
          expected: stored,
          next: normalized,
        );
        if (updated) return normalized;
        final current = await _store.read();
        if (current != null && current.generation > _generation) {
          _generation = current.generation;
        }
        return current;
      });

  @override
  Future<NotificationPendingRoute> persistClick(Map<String, String> payload) =>
      _serializeStore(() async {
        final routePayload = decodeNotificationRoutePayload(payload);
        final current = await _store.read();
        if (current != null &&
            current.payload.householdId == routePayload.householdId &&
            current.payload.inboxItemId == routePayload.inboxItemId) {
          return current;
        }
        if (current != null && current.generation > _generation) {
          _generation = current.generation;
        }
        final route = NotificationPendingRoute(
          payload: routePayload,
          state: NotificationPendingRouteState.waitingForSession,
          generation: ++_generation,
        );
        await _store.write(route);
        return route;
      });

  @override
  Future<bool> compareAndSetPendingRoute({
    required NotificationPendingRoute expected,
    required NotificationPendingRoute next,
  }) => _serializeStore(() async {
    final current = await _store.read();
    if (!_sameRoute(current, expected)) return false;
    await _store.write(next);
    return true;
  });

  @override
  Future<void> clearPendingRoute() => _serializeStore(_store.clear);

  @override
  Future<bool> clearPendingRouteIfGeneration(int generation) =>
      _serializeStore(() async {
        final current = await _store.read();
        if (current?.generation != generation) return false;
        await _store.clear();
        return true;
      });

  @override
  Future<NotificationRouteResolution> resolve(
    NotificationRoutePayload payload,
  ) async {
    final data = await _gateway.call('resolveNotificationInboxRoute', {
      'householdID': payload.householdId,
      'inboxItemID': payload.inboxItemId,
    });
    return _decodeResolution(data, payload);
  }

  Future<T> _serializeStore<T>(Future<T> Function() mutation) {
    final result = _pendingStoreMutation.then((_) => mutation());
    _pendingStoreMutation = result.then<void>((_) {}, onError: (_) {});
    return result;
  }
}

NotificationRoutePayload decodeNotificationRoutePayload(
  Map<String, String> data,
) {
  const keys = {'schemaVersion', 'destination', 'householdID', 'inboxItemID'};
  if (data.length != keys.length ||
      !data.keys.every(keys.contains) ||
      data['schemaVersion'] != '1' ||
      data['destination'] != 'notificationInbox' ||
      !_id(data['householdID']) ||
      !_intentId(data['inboxItemID'])) {
    throw const NotificationCenterException(
      NotificationCenterErrorCode.invalidInput,
    );
  }
  return NotificationRoutePayload(
    householdId: data['householdID']!,
    inboxItemId: data['inboxItemID']!,
  );
}

bool _sameRoute(
  NotificationPendingRoute? left,
  NotificationPendingRoute right,
) =>
    left?.generation == right.generation &&
    left?.state == right.state &&
    left?.payload.householdId == right.payload.householdId &&
    left?.payload.inboxItemId == right.payload.inboxItemId;

NotificationRouteResolution _decodeResolution(
  Map<String, Object?> data,
  NotificationRoutePayload payload,
) {
  final disposition = _enum(
    NotificationRouteDisposition.values,
    data['disposition'],
  );
  final checkedAt = data['serverCheckedAt'];
  final time = checkedAt is String
      ? DateTime.tryParse(checkedAt)?.toUtc()
      : null;
  if (disposition == null ||
      data['householdID'] != payload.householdId ||
      data['inboxItemID'] != payload.inboxItemId ||
      time == null ||
      !RegExp(
        r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$',
      ).hasMatch(checkedAt as String)) {
    throw const NotificationCenterException(
      NotificationCenterErrorCode.malformed,
    );
  }
  if (disposition == NotificationRouteDisposition.open) {
    const keys = {
      'disposition',
      'householdID',
      'inboxItemID',
      'category',
      'level',
      'serverCheckedAt',
    };
    final category = _enum(NotificationInboxCategory.values, data['category']);
    final level = _enum(NotificationInboxLevel.values, data['level']);
    if (data.length != keys.length ||
        !data.keys.every(keys.contains) ||
        category == null ||
        level == null) {
      throw const NotificationCenterException(
        NotificationCenterErrorCode.malformed,
      );
    }
    return NotificationRouteResolution(
      disposition: disposition,
      householdId: payload.householdId,
      inboxItemId: payload.inboxItemId,
      serverCheckedAt: time,
      category: category,
      level: level,
    );
  }
  const keys = {
    'disposition',
    'householdID',
    'inboxItemID',
    'reason',
    'serverCheckedAt',
  };
  final reason = _enum(NotificationRouteRejectReason.values, data['reason']);
  if (data.length != keys.length ||
      !data.keys.every(keys.contains) ||
      reason == null) {
    throw const NotificationCenterException(
      NotificationCenterErrorCode.malformed,
    );
  }
  return NotificationRouteResolution(
    disposition: disposition,
    householdId: payload.householdId,
    inboxItemId: payload.inboxItemId,
    serverCheckedAt: time,
    rejectReason: reason,
  );
}

T? _enum<T extends Enum>(List<T> values, Object? name) {
  if (name is! String) return null;
  for (final value in values) {
    if (value.name == name) return value;
  }
  return null;
}

bool _id(Object? value) =>
    value is String &&
    value.isNotEmpty &&
    value.length <= 128 &&
    !value.contains('/');

bool _intentId(Object? value) =>
    value is String && RegExp(r'^[0-9a-f]{64}$').hasMatch(value);
