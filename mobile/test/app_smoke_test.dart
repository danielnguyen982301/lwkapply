import 'package:flutter_form_builder/flutter_form_builder.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lwkapply_mobile/app/app.dart';
import 'package:lwkapply_mobile/core/storage/shared_preferences_provider.dart';
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

    // Same reasoning as _FakeTokenStorage above - widget tests have no real
    // platform channel behind shared_preferences either, so seed an
    // in-memory instance via the plugin's own testing hook rather than
    // hitting a real store.
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          tokenStorageProvider.overrideWithValue(_FakeTokenStorage()),
          sharedPreferencesProvider.overrideWithValue(prefs),
        ],
        child: const JobTrackerApp(),
      ),
    );

    // Bootstrap (tryRestoreSession) runs async on AuthController creation;
    // with no stored refresh token (the fake starts empty) it resolves to
    // unauthenticated, and the router redirects to /login.
    await tester.pumpAndSettle();

    expect(find.text('LwkApply'), findsWidgets);
    expect(find.widgetWithText(FormBuilderTextField, 'Email'), findsOneWidget);
    expect(
      find.widgetWithText(FormBuilderTextField, 'Password'),
      findsOneWidget,
    );
  });
}
