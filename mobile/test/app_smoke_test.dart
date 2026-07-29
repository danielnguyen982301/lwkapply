import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:lwkapply_mobile/app/app.dart';
import 'package:lwkapply_mobile/features/auth/data/token_storage.dart';

/// In-memory stand-in for the real `flutter_secure_storage`-backed
/// [TokenStorage]. Widget tests have no real Keychain/Keystore behind
/// the platform channel, so exercising the real implementation here
/// would depend on how the plugin happens to fail without one — this
/// fake makes "no stored session" an explicit, deterministic test
/// condition instead.
class _FakeTokenStorage extends TokenStorage {
  _FakeTokenStorage() : super(const FlutterSecureStorage());

  String? _token;

  @override
  Future<String?> readRefreshToken() async => _token;

  @override
  Future<void> saveRefreshToken(String token) async => _token = token;

  @override
  Future<void> clear() async => _token = null;
}

void main() {
  testWidgets('Unauthenticated app boots and shows the login screen', (
    tester,
  ) async {
    // main() normally loads this from an asset; set it directly for tests.
    dotenv.testLoad(fileInput: 'API_BASE_URL=http://localhost:8000/api/v1');

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          tokenStorageProvider.overrideWithValue(_FakeTokenStorage()),
        ],
        child: const JobTrackerApp(),
      ),
    );

    // Bootstrap (tryRestoreSession) runs async on AuthController creation;
    // with no stored refresh token (the fake starts empty) it resolves to
    // unauthenticated, and the router redirects to /login.
    await tester.pumpAndSettle();

    expect(find.text('LwkApply'), findsWidgets);
    expect(find.widgetWithText(TextFormField, 'Email'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Password'), findsOneWidget);
  });
}
