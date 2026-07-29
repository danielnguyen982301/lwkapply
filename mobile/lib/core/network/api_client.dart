import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/env_config.dart';
import '../../features/auth/data/auth_api.dart';
import '../../features/auth/data/auth_repository.dart';
import '../../features/auth/presentation/auth_controller.dart';

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
final apiClientProvider = Provider<Dio>((ref) {
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
        final token = ref.read(authControllerProvider).accessToken;
        if (token != null) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        handler.next(options);
      },
      onError: (error, handler) async {
        final isAuthRoute = error.requestOptions.path.startsWith('/auth/');
        final alreadyRetried = error.requestOptions.extra['retried'] == true;

        if (error.response?.statusCode != 401 || isAuthRoute || alreadyRetried) {
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
          ref.read(authControllerProvider.notifier).forceLogout();
          handler.next(error);
          return;
        }

        final newToken = ref.read(authControllerProvider).accessToken;
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
  ref
      .read(authControllerProvider.notifier)
      .updateAfterSilentRefresh(
        accessToken: result.accessToken,
        user: result.user,
      );
}
