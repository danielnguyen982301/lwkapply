import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Outer Scaffold for the authenticated section of the app: a persistent
/// bottom nav bar across Applications / Interviews / Contacts /
/// Documents.
///
/// Built on go_router's StatefulShellRoute.indexedStack (see
/// router.dart), which keeps each tab's own navigation stack and scroll
/// position alive when switching tabs — switching to Interviews and
/// back to Applications doesn't reset Applications' scroll position or
/// refetch its list.
///
/// A bottom tab bar (rather than a webapp-style side menu) was a
/// deliberate choice for mobile: every section stays one tap away,
/// which matters for a tool meant to be checked daily, and today's 4
/// destinations comfortably fit a single bar with no "More" overflow
/// needed yet. Revisit this shell if a 5th+ top-level section
/// (Analytics, AI Features) gets added later.
class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: navigationShell.currentIndex,
        onDestinationSelected: (index) => navigationShell.goBranch(
          index,
          // Tapping the already-active tab resets that tab's own stack
          // back to its initial location — standard bottom-nav behavior
          // (e.g. tapping the current tab again "jumps to top").
          initialLocation: index == navigationShell.currentIndex,
        ),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.work_outline),
            selectedIcon: Icon(Icons.work),
            label: 'Applications',
          ),
          NavigationDestination(
            icon: Icon(Icons.event_outlined),
            selectedIcon: Icon(Icons.event),
            label: 'Interviews',
          ),
          NavigationDestination(
            icon: Icon(Icons.people_outline),
            selectedIcon: Icon(Icons.people),
            label: 'Contacts',
          ),
          NavigationDestination(
            icon: Icon(Icons.description_outlined),
            selectedIcon: Icon(Icons.description),
            label: 'Documents',
          ),
        ],
      ),
    );
  }
}
