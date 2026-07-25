import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'core/config/env_config.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  const environment = String.fromEnvironment(
    'ENV',
    defaultValue: 'development',
  );
  await EnvConfig.load(environment: environment);

  runApp(const ProviderScope(child: JobTrackerApp()));
}
