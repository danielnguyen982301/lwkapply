import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Outer Scaffold for the authenticated section of the app: a persistent
/// bottom nav bar across just two tabs, Applications and Home.
///
/// Built on go_router's StatefulShellRoute.indexedStack (see
/// router.dart), which keeps each tab's own navigation stack and scroll
/// position alive when switching tabs.
///
/// This shrank from the original four tabs (Applications / Interviews /
/// Contacts / Documents) down to two, per the mobile-nav planning
/// discussion (not written down elsewhere but summarized here):
/// Interviews/Contacts/Documents moved to a card grid on the Home tab
/// (see home_screen.dart) instead of each holding a dedicated tab slot,
/// since a bottom nav realistically caps out around 4-5 destinations
/// and Analytics plus a future AI-tools section both needed somewhere
/// to live too. Applications specifically kept its own tab rather than
/// also becoming a Home card — it's the single highest-frequency screen
/// in the app (the primary daily workflow, not a "check occasionally"
/// screen like the other three), so it stays one tap away rather than
/// two. Settings now lives behind an icon on individual screens'
/// AppBars (see settings_screen.dart) rather than a tab at all — logout
/// moved there from ApplicationsListScreen's AppBar in this same pass.
///
/// A bottom tab bar (rather than a webapp-style side menu) remains the
/// right call for mobile: every top-level destination stays reachable
/// in at most two taps, which matters for a tool meant to be checked
/// daily.
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
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Home',
          ),
        ],
      ),
    );
  }
}
