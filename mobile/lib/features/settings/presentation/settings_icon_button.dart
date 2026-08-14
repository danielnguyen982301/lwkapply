import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Shared "open Settings" AppBar action — same icon, tooltip, and route
/// on every top-level screen (see the mobile-nav planning discussion).
///
/// Extracted to one place rather than left as five duplicated inline
/// `IconButton`s: each screen still has to add it to its own
/// `AppBar.actions` (there's no single shared chrome to hoist this
/// into instead — see the explanation in the conversation this came
/// from: AppShell only wraps the Applications/Home branches, and
/// Interviews/Contacts/Documents are pushed routes entirely outside
/// that shell, so they can't inherit anything AppShell renders even in
/// principle). But every screen can reference this one widget instead
/// of copy-pasting the IconButton — change the icon, tooltip, or target
/// route once, here, rather than in five places.
class SettingsIconButton extends StatelessWidget {
  const SettingsIconButton({super.key});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.settings_outlined),
      tooltip: 'Settings',
      onPressed: () => context.push('/settings'),
    );
  }
}
