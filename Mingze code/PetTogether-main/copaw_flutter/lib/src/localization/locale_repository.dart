import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_locale.dart';

abstract interface class LocaleRepository {
  Future<AppLocale> load();
  Future<void> save(AppLocale locale);
}

final localeRepositoryProvider = Provider<LocaleRepository>((ref) {
  throw StateError('LocaleRepository must be provided at the app boundary.');
});

class SharedPreferencesLocaleRepository implements LocaleRepository {
  SharedPreferencesLocaleRepository({SharedPreferencesAsync? preferences})
    : _preferences = preferences ?? SharedPreferencesAsync();

  static const _localeKey = 'copaw.language';
  final SharedPreferencesAsync _preferences;

  @override
  Future<AppLocale> load() async {
    return AppLocale.fromLanguageCode(await _preferences.getString(_localeKey));
  }

  @override
  Future<void> save(AppLocale locale) {
    return _preferences.setString(_localeKey, locale.languageCode);
  }
}

class FakeLocaleRepository implements LocaleRepository {
  FakeLocaleRepository([this.storedLocale = AppLocale.japanese]);

  AppLocale storedLocale;
  int saves = 0;

  @override
  Future<AppLocale> load() async => storedLocale;

  @override
  Future<void> save(AppLocale locale) async {
    storedLocale = locale;
    saves += 1;
  }
}
