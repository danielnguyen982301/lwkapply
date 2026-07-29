import 'user.dart';

enum AuthStatus {
  /// Bootstrapping: checking secure storage for a stored refresh token.
  unknown,
  authenticating,
  authenticated,
  unauthenticated,
}

class AuthState {
  const AuthState({
    required this.status,
    this.user,
    this.accessToken,
    this.errorMessage,
  });

  const AuthState.unknown() : this(status: AuthStatus.unknown);

  const AuthState.unauthenticated({String? errorMessage})
      : this(status: AuthStatus.unauthenticated, errorMessage: errorMessage);

  const AuthState.authenticating() : this(status: AuthStatus.authenticating);

  const AuthState.authenticated({
    required User user,
    required String accessToken,
  }) : this(
          status: AuthStatus.authenticated,
          user: user,
          accessToken: accessToken,
        );

  final AuthStatus status;
  final User? user;

  /// In-memory only — never persisted. Lost on app restart by design;
  /// restored via a silent refresh call during bootstrap instead.
  final String? accessToken;

  final String? errorMessage;

  bool get isAuthenticated => status == AuthStatus.authenticated;
}
