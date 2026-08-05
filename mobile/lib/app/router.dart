import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/applications/presentation/application_form_screen.dart';
import '../features/applications/presentation/applications_list_screen.dart';
import '../features/auth/domain/auth_state.dart';
import '../features/auth/presentation/auth_controller.dart';
import '../features/auth/presentation/login_screen.dart';
import '../features/auth/presentation/register_screen.dart';
import '../features/contacts/presentation/contact_directory_screen.dart';
import '../features/documents/presentation/document_directory_screen.dart';
import '../features/interviews/presentation/interview_directory_screen.dart';
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
      // Create/Edit are deliberately top-level routes, not nested inside
      // the Applications branch below: pushing here covers the whole
      // screen, including AppShell's bottom nav bar, which is the
      // expected UX for a form flow (no reason to let someone flip to
      // the Interviews tab mid-edit). They still get the same
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
                // Was ComingSoonScreen — now the real cross-application
                // Interviews directory, mirroring
                // InterviewDirectoryView.vue. See
                // interview_directory_screen.dart's doc comment for what
                // deliberately differs from ContactDirectoryScreen (a
                // result filter instead of text search).
                builder: (context, state) => const InterviewDirectoryScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/contacts',
                name: 'contacts',
                // Was ComingSoonScreen — now the real cross-application
                // Contacts directory, mirroring ContactDirectoryView.vue.
                // See contact_directory_screen.dart's doc comment for
                // what deliberately differs from ApplicationsListScreen.
                builder: (context, state) => const ContactDirectoryScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/documents',
                name: 'documents',
                // Was ComingSoonScreen — now the real cross-application
                // Documents directory, mirroring
                // DocumentDirectoryView.vue. See
                // document_directory_screen.dart's doc comment for how
                // it combines ContactDirectoryScreen's search box with
                // InterviewDirectoryScreen's filter sheet (search +
                // file_type together, unlike either prior directory
                // alone).
                builder: (context, state) => const DocumentDirectoryScreen(),
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
