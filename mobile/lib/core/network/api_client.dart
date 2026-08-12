import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/env_config.dart';
import '../../features/auth/data/auth_api.dart';
import '../../features/auth/data/auth_repository.dart';
import '../../features/auth/presentation/session_providers.dart';

/// Shared Dio instance for all authenticated feature requests
/// (applications, interviews, contacts, documents).
///
/// Mirrors webapp/src/lib/api.ts:
/// - injects the current access token as a Bearer header
/// - on 401, attempts exactly one silent refresh, then retries the
///   original request
/// - queues concurrent 401s behind a single in-flight refresh, so five
///   requests that all 401 at once don't trigger five refresh calls
/// - never intercepts /auth/* routes (see webapp's CHANGELOG v0.4.0 fix
///   for the infinite-refresh-loop bug this avoids)
///
/// Reads/writes `accessTokenProvider`/`currentUserProvider` directly,
/// never `authControllerProvider` - see session_providers.dart's doc
/// comment for why: `authControllerProvider` transitively depends on
/// this very provider (via `pushServiceProvider`, for
/// `DeviceTokensApi`'s Dio), so reading it from here - even lazily,
/// inside a callback that only runs well after everything has finished
/// building - creates a real cycle in Riverpod's dependency graph and
/// throws `CircularDependencyError` at request time. Don't reintroduce
/// a read/watch of `authControllerProvider` anywhere in this file.
final Provider<Dio> apiClientProvider = Provider<Dio>((ref) {
  final dio = Dio(
    BaseOptions(
      baseUrl: EnvConfig.apiBaseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
      contentType: 'application/json',
    ),
  );

  Future<void>? refreshInFlight;

  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) {
        final token = ref.read(accessTokenProvider);
        if (token != null) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        handler.next(options);
      },
      onError: (error, handler) async {
        final isAuthRoute = error.requestOptions.path.startsWith('/auth/');
        final alreadyRetried = error.requestOptions.extra['retried'] == true;

        if (error.response?.statusCode != 401 ||
            isAuthRoute ||
            alreadyRetried) {
          handler.next(error);
          return;
        }

        try {
          // Queue concurrent 401s behind one refresh call.
          refreshInFlight ??= _performRefresh(ref);
          await refreshInFlight;
          refreshInFlight = null;
        } on AuthException {
          refreshInFlight = null;
          // Clear the shared session state directly rather than calling
          // into AuthController - see this provider's doc comment above
          // for why. AuthController's own accessTokenProvider listener
          // (auth_controller.dart's constructor) reacts to this and
          // updates its `state` for UI/routing.
          ref.read(accessTokenProvider.notifier).state = null;
          ref.read(currentUserProvider.notifier).state = null;
          handler.next(error);
          return;
        }

        final newToken = ref.read(accessTokenProvider);
        final retryOptions = error.requestOptions
          ..headers['Authorization'] = 'Bearer $newToken'
          ..extra['retried'] = true;

        try {
          final response = await dio.fetch<dynamic>(retryOptions);
          handler.resolve(response);
        } on DioException catch (retryError) {
          handler.next(retryError);
        }
      },
    ),
  );

  if (const bool.fromEnvironment('dart.vm.product') == false) {
    dio.interceptors.add(
      LogInterceptor(requestBody: false, responseBody: false),
    );
  }

  return dio;
});

Future<void> _performRefresh(Ref ref) async {
  final repository = ref.read(authRepositoryProvider);
  final result = await repository.refreshAccessToken();
  // Write directly to the leaf providers, not through AuthController -
  // same reasoning as the rest of this file. AuthController's listener
  // picks this up and syncs its own `state` from it.
  ref.read(accessTokenProvider.notifier).state = result.accessToken;
  ref.read(currentUserProvider.notifier).state = result.user;
}
