import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../settings/presentation/settings_icon_button.dart';

/// Landing screen for the "Home" tab (see app_shell.dart's doc comment
/// for why this tab exists): a card grid linking out to every
/// lower-frequency, cross-application section of the app.
/// Interviews/Contacts/Documents used to each be their own bottom-nav
/// tab; they're equal-weight cards here instead, one extra tap away in
/// exchange for the bottom nav staying at two tabs with room to grow.
///
/// Deliberately a plain StatelessWidget with no fetched state of its
/// own — this screen is just a launcher, it owns no data. Each card
/// pushes a route (see router.dart), covering the bottom nav, same as
/// tapping into an application's edit form does.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Home'),
        actions: const [SettingsIconButton()],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: GridView.count(
          crossAxisCount: 2,
          mainAxisSpacing: 16,
          crossAxisSpacing: 16,
          childAspectRatio: 1.1,
          children: [
            _HomeCard(
              icon: Icons.event_outlined,
              label: 'Interviews',
              onTap: () => context.push('/interviews'),
            ),
            _HomeCard(
              icon: Icons.people_outline,
              label: 'Contacts',
              onTap: () => context.push('/contacts'),
            ),
            _HomeCard(
              icon: Icons.description_outlined,
              label: 'Documents',
              onTap: () => context.push('/documents'),
            ),
            _HomeCard(
              icon: Icons.bar_chart_outlined,
              label: 'Analytics',
              onTap: () => context.push('/analytics'),
            ),
            _HomeCard(
              icon: Icons.auto_awesome_outlined,
              label: 'AI Tools',
              onTap: () => context.push('/ai-tools'),
            ),
          ],
        ),
      ),
    );
  }
}

class _HomeCard extends StatelessWidget {
  const _HomeCard({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 36, color: theme.colorScheme.primary),
              const SizedBox(height: 12),
              Text(label, style: theme.textTheme.titleMedium),
            ],
          ),
        ),
      ),
    );
  }
}
