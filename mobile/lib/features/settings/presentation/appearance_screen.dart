import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'theme_mode_controller.dart';

/// Appearance / theme-mode picker. Unlike NotificationPreferencesScreen's
/// local-form-plus-Save-button shape, a tap here applies instantly (same
/// "select == save" UX as webapp's ThemeToggle.vue popover) — there's
/// nothing else on this screen to batch the change with, and no network
/// round-trip to wait on: the preference is purely local
/// (ThemeModeController, SharedPreferences-backed).
class AppearanceScreen extends ConsumerWidget {
  const AppearanceScreen({super.key});

  void _select(WidgetRef ref, ThemeMode? mode) {
    if (mode == null) return;
    ref.read(themeModeControllerProvider.notifier).setThemeMode(mode);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeControllerProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Appearance')),
      // RadioGroup (not each tile's own groupValue/onChanged, deprecated as
      // of Flutter 3.32) is the current way to share one selection across
      // several RadioListTiles.
      body: RadioGroup<ThemeMode>(
        groupValue: themeMode,
        onChanged: (mode) => _select(ref, mode),
        child: ListView(
          children: const [
            RadioListTile<ThemeMode>(
              title: Text('System default'),
              subtitle: Text('Match your device setting'),
              value: ThemeMode.system,
            ),
            RadioListTile<ThemeMode>(
              title: Text('Light'),
              value: ThemeMode.light,
            ),
            RadioListTile<ThemeMode>(
              title: Text('Dark'),
              value: ThemeMode.dark,
            ),
          ],
        ),
      ),
    );
  }
}
