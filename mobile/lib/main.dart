import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'app/router.dart';
import 'core/config/env_config.dart';
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
  // PushService.setupNotificationTapHandling's doc comment for why it
  // needs the GoRouter directly instead of a Ref/BuildContext.
  final container = ProviderContainer();
  container.read(pushServiceProvider).setupNotificationTapHandling(
        container.read(routerProvider),
      );

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const JobTrackerApp(),
    ),
  );
}
