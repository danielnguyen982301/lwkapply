import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/applications/presentation/applications_list_screen.dart';
import '../features/auth/domain/auth_state.dart';
import '../features/auth/presentation/auth_controller.dart';
import '../features/auth/presentation/login_screen.dart';
import '../features/auth/presentation/register_screen.dart';
import '../shared/widgets/coming_soon_screen.dart';
import 'app_shell.dart';

/// Auth-aware router, mirroring webapp's `authGuard`
/// (src/router/index.ts): redirect unauthenticated visitors away from
/// protected routes, redirect authenticated visitors away from
/// guest-only routes (login, register), and show a loading state while
/// the startup session-restore check (`AuthStatus.unknown`) is in
/// flight.
///
/// The authenticated section (`/applications`, `/interviews`,
/// `/contacts`, `/documents`) is wrapped in a StatefulShellRoute so
/// AppShell can render a persistent bottom nav bar around whichever tab
/// is active — see app_shell.dart for why a bottom bar was chosen over
/// a webapp-style side menu.
final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/applications',
    refreshListenable: _AuthControllerListenable(ref),
    redirect: (context, state) {
      final authState = ref.read(authControllerProvider);
      const guestRoutes = {'/login', '/register'};
      final isGuestRoute = guestRoutes.contains(state.matchedLocation);

      if (authState.status == AuthStatus.unknown) {
        // Still restoring session on startup — don't redirect yet.
        return null;
      }
      if (!authState.isAuthenticated && !isGuestRoute) {
        return '/login';
      }
      if (authState.isAuthenticated && isGuestRoute) {
        return '/applications';
      }
      return null;
    },
    routes: [
      GoRoute(
        path: '/login',
        name: 'login',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/register',
        name: 'register',
        builder: (context, state) => const RegisterScreen(),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            AppShell(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/applications',
                name: 'applications',
                builder: (context, state) => const ApplicationsListScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/interviews',
                name: 'interviews',
                builder: (context, state) => const ComingSoonScreen(
                  title: 'Interviews',
                  icon: Icons.event_outlined,
                ),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/contacts',
                name: 'contacts',
                builder: (context, state) => const ComingSoonScreen(
                  title: 'Contacts',
                  icon: Icons.people_outline,
                ),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/documents',
                name: 'documents',
                builder: (context, state) => const ComingSoonScreen(
                  title: 'Documents',
                  icon: Icons.description_outlined,
                ),
              ),
            ],
          ),
        ],
      ),
    ],
  );
});

/// Bridges Riverpod state changes into go_router's `Listenable`-based
/// refresh mechanism, so a login/logout immediately re-runs `redirect`
/// without needing to manually call `router.refresh()` everywhere.
class _AuthControllerListenable extends ChangeNotifier {
  _AuthControllerListenable(Ref ref) {
    ref.listen(authControllerProvider, (previous, next) {
      if (previous?.status != next.status) {
        notifyListeners();
      }
    });
  }
}
