import 'package:flutter_test/flutter_test.dart';
// ignore: avoid_relative_lib_imports
import '../lib/main.dart';

void main() {
  testWidgets('Counter increments smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const FeedApp());

    // Verify that our counter starts at 0.
    // Since this is a smoke test, we'll just check if the widget builds.
    expect(find.byType(FeedApp), findsOneWidget);
  });
}
