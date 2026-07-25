import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:lwkapply_mobile/app/app.dart';

void main() {
  testWidgets('App boots and shows the placeholder home screen', (
    tester,
  ) async {
    // main() normally loads this from an asset; set it directly for tests.
    dotenv.testLoad(fileInput: 'API_BASE_URL=http://localhost:8000/api/v1');

    await tester.pumpWidget(
      const ProviderScope(child: JobTrackerApp()),
    );
    await tester.pumpAndSettle();

    expect(find.text('Scaffold OK — auth screen next'), findsOneWidget);
  });
}
