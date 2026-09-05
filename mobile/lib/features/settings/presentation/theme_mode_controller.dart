import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/storage/shared_preferences_provider.dart';

const _prefsKey = 'theme_mode';

/// Persisted, app-lifetime theme preference (System/Light/Dark) - mirrors
/// webapp's Pinia `theme` store, adapted to Flutter's own [ThemeMode] enum
/// instead of a hand-rolled 'system'/'light'/'dark' union. Same app-lifetime,
/// non-`.autoDispose` shape as AuthController/NotificationsController: the
/// preference has to be available to MaterialApp.router's `themeMode`
/// immediately on every screen, not scoped to one pushed screen's lifetime.
///
/// Reads its initial value synchronously from an already-resolved
/// [SharedPreferences] instance (see sharedPreferencesProvider, overridden
/// in main.dart before runApp) rather than loading it inside the
/// constructor - MaterialApp needs a themeMode on its very first build,
/// before any async gap could resolve.
class ThemeModeController extends StateNotifier<ThemeMode> {
  ThemeModeController(this._prefs) : super(_readInitial(_prefs));

  final SharedPreferences _prefs;

  static ThemeMode _readInitial(SharedPreferences prefs) {
    final stored = prefs.getString(_prefsKey);
    return ThemeMode.values.firstWhere(
      (mode) => mode.name == stored,
      orElse: () => ThemeMode.system,
    );
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    state = mode;
    await _prefs.setString(_prefsKey, mode.name);
  }
}

final themeModeControllerProvider =
    StateNotifierProvider<ThemeModeController, ThemeMode>((ref) {
  return ThemeModeController(ref.watch(sharedPreferencesProvider));
});
