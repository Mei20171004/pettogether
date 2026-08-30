import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_timezone/flutter_timezone.dart';

abstract interface class LocalTimeZoneRepository {
  Future<String> loadIdentifier();
}

final localTimeZoneRepositoryProvider = Provider<LocalTimeZoneRepository>(
  (ref) => const DeviceLocalTimeZoneRepository(),
);

final class DeviceLocalTimeZoneRepository implements LocalTimeZoneRepository {
  const DeviceLocalTimeZoneRepository();

  @override
  Future<String> loadIdentifier() async {
    final timezone = await FlutterTimezone.getLocalTimezone();
    return timezone.identifier;
  }
}
