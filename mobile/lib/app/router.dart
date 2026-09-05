import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/ai/presentation/ai_tools_screen.dart';
import '../features/ai/presentation/ats_score_detail_screen.dart';
import '../features/ai/presentation/resume_analysis_detail_screen.dart';
import '../features/analytics/presentation/analytics_screen.dart';
import '../features/applications/presentation/application_form_screen.dart';
import '../features/applications/presentation/applications_list_screen.dart';
import '../features/auth/data/deep_link_service.dart';
import '../features/auth/domain/auth_state.dart';
import '../features/auth/presentation/auth_controller.dart';
import '../features/auth/presentation/forgot_password_screen.dart';
import '../features/auth/presentation/login_screen.dart';
import '../features/auth/presentation/register_screen.dart';
import '../features/auth/presentation/reset_password_screen.dart';
import '../features/contacts/presentation/contact_directory_screen.dart';
import '../features/documents/presentation/document_directory_screen.dart';
import '../features/home/presentation/home_screen.dart';
import '../features/interviews/presentation/interview_directory_screen.dart';
import '../features/notifications/presentation/notifications_screen.dart';
import '../features/settings/presentation/appearance_screen.dart';
import '../features/settings/presentation/notification_preferences_screen.dart';
import '../features/settings/presentation/profile_screen.dart';
import '../features/settings/presentation/reset_password_request_screen.dart';
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
      // A cold-start deep link (the emailed password-reset link) wins
      // over every other redirect decision below, including the
      // still-restoring-session check right after this - main.dart
      // awaits DeepLinkService.initialize() to completion before
      // runApp(), so this already reflects the launch intent (or its
      // absence) at this very first redirect evaluation, with no
      // dependency on AuthController's async session-restore having
      // settled yet. See consumePendingLocation's doc comment for the
      // race this replaced.
      final pendingDeepLink =
          ref.read(deepLinkServiceProvider).consumePendingLocation();
      if (pendingDeepLink != null) {
        return pendingDeepLink;
      }

      final authState = ref.read(authControllerProvider);
      const guestRoutes = {
        '/login',
        '/register',
        '/forgot-password',
        '/reset-password',
      };
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
      GoRoute(
        path: '/forgot-password',
        name: 'forgot-password',
        builder: (context, state) => const ForgotPasswordScreen(),
      ),
      // `token` arrives either via DeepLinkService (the emailed link,
      // handled by AndroidManifest's intent-filter) or is absent/blank
      // if someone reaches this route some other way - ResetPasswordScreen
      // itself renders the "invalid link" state for that case rather
      // than this route redirecting, so there's one place that explains
      // it instead of a bare 404.
      GoRoute(
        path: '/reset-password',
        name: 'reset-password',
        builder: (context, state) => ResetPasswordScreen(
          token: state.uri.queryParameters['token'],
        ),
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
      // Also a plain top-level push, reached via the "AI Tools" card on
      // the Home tab. One route for the tabbed landing screen, plus two
      // detail routes it (and DocumentsPanel's "View Analysis" row
      // action) navigate into — see ai_tools_screen.dart's doc comment
      // for why this is a single `TabBar` screen rather than two
      // separate shell branches or routes the way Applications'
      // List/Board split works on web.
      GoRoute(
        path: '/ai-tools',
        name: 'ai-tools',
        builder: (context, state) => const AiToolsScreen(),
      ),
      GoRoute(
        path: '/resume-analyses/:id',
        name: 'resume-analysis-detail',
        builder: (context, state) => ResumeAnalysisDetailScreen(
          analysisId: state.pathParameters['id']!,
          // Only ever set by viewResumeAnalysisAction (DocumentsPanel's/
          // DocumentDirectoryScreen's "view analysis" row actions) — see
          // that function's doc comment for why.
          isLatest: state.uri.queryParameters['isLatest'] == 'true',
        ),
      ),
      GoRoute(
        path: '/ats-scores/:id',
        name: 'ats-score-detail',
        builder: (context, state) => AtsScoreDetailScreen(
          scoreId: state.pathParameters['id']!,
          // Only set when reached from AtsScoresTab/AiToolsScreen's "New
          // Score" flow — see AtsScoreDetailScreen's doc comment for why
          // the "View resume analysis" row is conditional.
          showAnalysisLink:
              state.uri.queryParameters['showAnalysisLink'] == 'true',
        ),
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
      GoRoute(
        path: '/settings/profile',
        name: 'settings-profile',
        builder: (context, state) => const ProfileScreen(),
      ),
      GoRoute(
        path: '/settings/password',
        name: 'settings-password',
        builder: (context, state) => const ResetPasswordRequestScreen(),
      ),
      GoRoute(
        path: '/settings/notification-preferences',
        name: 'settings-notification-preferences',
        builder: (context, state) => const NotificationPreferencesScreen(),
      ),
      GoRoute(
        path: '/settings/appearance',
        name: 'settings-appearance',
        builder: (context, state) => const AppearanceScreen(),
      ),
      // Reached via NotificationBellButton in an AppBar's actions — same
      // plain-top-level-push reasoning as every other non-shell route
      // above.
      GoRoute(
        path: '/notifications',
        name: 'notifications',
        builder: (context, state) => const NotificationsScreen(),
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
