import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The shared, app-wide [SharedPreferences] instance, for small local UI
/// preferences (currently just theme mode - see
/// features/settings/presentation/theme_mode_controller.dart). Loading it
/// is async, but most consumers (MaterialApp's themeMode included) need a
/// value on their very first build, so this is overridden with an
/// already-resolved instance in main.dart before runApp rather than
/// fetched lazily here - throwing by default makes a missing override
/// fail loudly instead of silently losing the persisted preference.
final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError(
    'sharedPreferencesProvider must be overridden in main.dart, with an '
    'already-resolved SharedPreferences.getInstance(), before runApp.',
  );
});
