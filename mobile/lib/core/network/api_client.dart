import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/env_config.dart';

/// Riverpod provider for the shared Dio instance.
///
/// Deliberately minimal for now: base URL + timeouts only.
/// Bearer-token injection and refresh-on-401 interceptors (the mobile
/// equivalent of webapp/src/lib/api.ts's interceptor stack) are added once
/// the token-storage strategy is decided — see auth feature notes.
final apiClientProvider = Provider<Dio>((ref) {
  final dio = Dio(
    BaseOptions(
      baseUrl: EnvConfig.apiBaseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
      contentType: 'application/json',
    ),
  );

  // TODO(auth): add interceptor for bearer-token injection
  // TODO(auth): add queued refresh-on-401 interceptor
  // TODO(auth): exclude /auth/* routes from refresh-retry (see webapp's
  //             infinite-loop bug fix in CHANGELOG.md v0.4.0 — same trap
  //             applies here)

  if (const bool.fromEnvironment('dart.vm.product') == false) {
    dio.interceptors.add(
      LogInterceptor(requestBody: false, responseBody: false),
    );
  }

  return dio;
});
