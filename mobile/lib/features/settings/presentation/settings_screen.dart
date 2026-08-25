import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../auth/presentation/auth_controller.dart';
import '../../auth/presentation/session_providers.dart';
import 'delete_account_dialog.dart';

/// Account/settings menu — grew from a logout-only screen (see
/// CHANGELOG.md/MOBILE_SUMMARY.md for that original pass) into the
/// fuller account-settings screen planned from the start: each section
/// webapp's AccountSettingsView.vue splits into its own card
/// (ProfileSettingsCard.vue/PasswordSettingsCard.vue/
/// NotificationSettingsCard.vue/DeleteAccountDialog.vue) is a pushed
/// sub-screen here instead — mobile's own convention for anything more
/// than a couple of fields (see ApplicationFormScreen's tabs, or
/// Interviews/Contacts/Documents each being their own screen) rather
/// than one long scrolling page.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  Future<void> _confirmDeleteAccount(BuildContext context) {
    return showDialog<void>(
      context: context,
      builder: (context) => const DeleteAccountDialog(),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          if (user != null)
            ListTile(
              leading: CircleAvatar(
                backgroundImage: user.avatarUrl != null
                    ? NetworkImage(user.avatarUrl!)
                    : null,
                child: user.avatarUrl == null
                    ? const Icon(Icons.person_outline)
                    : null,
              ),
              title: Text(user.fullName),
              subtitle: Text(user.email),
              onTap: () => context.push('/settings/profile'),
            )
          else
            ListTile(
              leading: const Icon(Icons.person_outline),
              title: const Text('Profile'),
              onTap: () => context.push('/settings/profile'),
            ),
          ListTile(
            leading: const Icon(Icons.lock_outline),
            title: const Text('Change password'),
            onTap: () => context.push('/settings/password'),
          ),
          ListTile(
            leading: const Icon(Icons.notifications_outlined),
            title: const Text('Notification preferences'),
            onTap: () => context.push('/settings/notification-preferences'),
          ),
          const Divider(),
          ListTile(
            leading: Icon(Icons.delete_outline, color: theme.colorScheme.error),
            title: Text(
              'Delete account',
              style: TextStyle(color: theme.colorScheme.error),
            ),
            onTap: () => _confirmDeleteAccount(context),
          ),
          const Divider(),
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
