import 'package:flutter/material.dart';

/// Placeholder for tabs whose feature screens haven't been built yet
/// (Interviews, Contacts, Documents — see MOBILE_SUMMARY.md's "Not yet
/// implemented" list). Swap each usage out for the real screen as that
/// tab's feature is built, following the same data/domain/presentation
/// folder split as `features/applications/` and `features/auth/`.
class ComingSoonScreen extends StatelessWidget {
  const ComingSoonScreen({super.key, required this.title, required this.icon});

  final String title;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 48,
                color: Theme.of(context).colorScheme.outline,
              ),
              const SizedBox(height: 12),
              Text(
                '$title coming soon',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
