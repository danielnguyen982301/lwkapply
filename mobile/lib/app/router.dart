import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/analytics/presentation/analytics_screen.dart';
import '../features/applications/presentation/application_form_screen.dart';
import '../features/applications/presentation/applications_list_screen.dart';
import '../features/auth/domain/auth_state.dart';
import '../features/auth/presentation/auth_controller.dart';
import '../features/auth/presentation/login_screen.dart';
import '../features/auth/presentation/register_screen.dart';
import '../features/contacts/presentation/contact_directory_screen.dart';
import '../features/documents/presentation/document_directory_screen.dart';
import '../features/home/presentation/home_screen.dart';
import '../features/interviews/presentation/interview_directory_screen.dart';
import '../features/settings/presentation/settings_screen.dart';
import 'app_shell.dart';

/// Auth-aware router, mirroring webapp's `authGuard`
/// (src/router/index.ts): redirect unauthenticated visitors away from
/// protected routes, redirect authenticated visitors away from
/// guest-only routes (login, register), and show a loading state while
/// the startup session-restore check (`AuthStatus.unknown`) is in
/// flight.
///
/// The authenticated section is wrapped in a StatefulShellRoute with
/// just two branches now — `/applications` and `/home` — so AppShell
/// can render a persistent bottom nav bar around whichever tab is
/// active. See app_shell.dart's doc comment for why this shrank from
/// four branches to two (Interviews/Contacts/Documents moved to Home's
/// card grid instead of each holding a tab slot), and why Applications
/// specifically kept its own tab rather than joining them there.
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
      // Create/Edit are deliberately top-level routes, not nested inside
      // the Applications branch below: pushing here covers the whole
      // screen, including AppShell's bottom nav bar, which is the
      // expected UX for a form flow (no reason to let someone flip to
      // the Home tab mid-edit). They still get the same
      // authenticated-only protection as everything else, since
      // `redirect` above only special-cases `/login`/`/register`.
      //
      // The Contacts directory below reuses this same route
      // (`application-edit`) via `context.push` when a row is tapped —
      // there's no contact-specific edit screen, only the owning
      // application's.
      GoRoute(
        path: '/applications/new',
        name: 'application-new',
        builder: (context, state) => const ApplicationFormScreen(),
      ),
      GoRoute(
        path: '/applications/:id/edit',
        name: 'application-edit',
        builder: (context, state) => ApplicationFormScreen(
          applicationId: state.pathParameters['id'],
        ),
      ),
      // Interviews/Contacts/Documents used to each be their own
      // bottom-nav branch; they're reached from cards on the Home tab
      // now instead (see home_screen.dart), so — same reasoning as the
      // Applications form routes right above — they're plain top-level
      // pushed routes, not shell branches. Pushing covers the bottom
      // nav (back navigates to Home, same as any other pushed screen),
      // and go_router's default `automaticallyImplyLeading` gives each
      // one a back button for free purely from no longer being a shell
      // root — no code change needed in the screens themselves for
      // that part.
      GoRoute(
        path: '/interviews',
        name: 'interviews',
        builder: (context, state) => const InterviewDirectoryScreen(),
      ),
      GoRoute(
        path: '/contacts',
        name: 'contacts',
        builder: (context, state) => const ContactDirectoryScreen(),
      ),
      GoRoute(
        path: '/documents',
        name: 'documents',
        builder: (context, state) => const DocumentDirectoryScreen(),
      ),
      // Also a plain top-level push, same reasoning — reached via the
      // Analytics card on the Home tab (see home_screen.dart).
      GoRoute(
        path: '/analytics',
        name: 'analytics',
        builder: (context, state) => const AnalyticsScreen(),
      ),
      // Also a plain top-level push, same reasoning. Reached via the
      // settings icon on Applications'/Home's (and ideally every
      // screen's) AppBar — see settings_screen.dart — not part of the
      // bottom nav itself.
      GoRoute(
        path: '/settings',
        name: 'settings',
        builder: (context, state) => const SettingsScreen(),
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
                path: '/home',
                name: 'home',
                builder: (context, state) => const HomeScreen(),
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
