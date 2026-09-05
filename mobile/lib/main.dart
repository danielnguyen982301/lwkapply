import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app/app.dart';
import 'app/router.dart';
import 'core/config/env_config.dart';
import 'core/storage/shared_preferences_provider.dart';
import 'features/auth/data/deep_link_service.dart';
import 'features/notifications/data/push_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  const environment = String.fromEnvironment(
    'ENV',
    defaultValue: 'development',
  );
  await EnvConfig.load(environment: environment);

  // Firebase init + the background-message handler registration must
  // both happen before runApp, regardless of auth state - actual
  // permission request / token registration with the backend only
  // happens once a user is authenticated (see AuthController, which
  // calls PushService.registerCurrentDevice() after login/register/a
  // successful silent restore).
  await Firebase.initializeApp();
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

  // Built explicitly (rather than letting ProviderScope create one
  // implicitly) so tap-to-deep-link can read the same routerProvider
  // instance from outside the widget tree - see
  // PushService.initialize's doc comment for why it needs the GoRouter
  // directly instead of a Ref/BuildContext. Awaited before runApp so the
  // local-notifications plugin (which PushService.initialize sets up)
  // is ready before any foreground message could plausibly arrive.
  // Loaded before the container is built, not inside
  // ThemeModeController's constructor - MaterialApp.router's `themeMode`
  // needs a value on its very first build (see sharedPreferencesProvider's
  // doc comment), and Riverpod providers can't await inside a synchronous
  // build.
  final prefs = await SharedPreferences.getInstance();

  final container = ProviderContainer(
    overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
  );
  final router = container.read(routerProvider);
  await container.read(pushServiceProvider).initialize(router);
  await container.read(deepLinkServiceProvider).initialize(router);

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const JobTrackerApp(),
    ),
  );
}
