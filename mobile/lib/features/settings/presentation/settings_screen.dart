import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/presentation/auth_controller.dart';

/// Minimal account/settings screen — currently just hosts the logout
/// action, moved here from ApplicationsListScreen's AppBar per the
/// mobile-nav planning discussion: logout belongs in Settings, not on
/// the primary workflow screen, and Settings didn't have anywhere to
/// live until this same refactor gave it a real entry point (the
/// settings icon on Applications'/Home's AppBar).
///
/// Password reset, timezone override, and notification preferences —
/// already noted elsewhere as a planned combined account/settings
/// screen (see MOBILE_SUMMARY.md) — are NOT part of this pass. This
/// screen exists so logout has a proper home now; it grows into that
/// fuller screen later rather than needing a second relocation.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.logout),
            title: const Text('Log out'),
            onTap: () => ref.read(authControllerProvider.notifier).logout(),
          ),
        ],
      ),
    );
  }
}
