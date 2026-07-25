import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Typed access to environment config, loaded from the bundled `.env.*`
/// asset selected at build/run time via `--dart-define=ENV=development`.
///
/// Mirrors the webapp's env-variable pattern (src/lib/api.ts base URL):
/// one source of truth per environment, no hardcoded URLs in feature code.
class EnvConfig {
  EnvConfig._();

  static Future<void> load({required String environment}) async {
    await dotenv.load(fileName: '.env.$environment');
  }

  static String get apiBaseUrl {
    final url = dotenv.env['API_BASE_URL'];
    if (url == null || url.isEmpty) {
      throw StateError(
        'API_BASE_URL is not set. Did you call EnvConfig.load()?',
      );
    }
    return url;
  }
}
