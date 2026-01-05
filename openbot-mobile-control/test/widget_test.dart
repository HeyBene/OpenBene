import 'package:flutter_test/flutter_test.dart';

import 'package:openbot_app/main.dart';

void main() {
  testWidgets('OpenBot app starts', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const OpenBotApp());

    // Verify that the app starts with connection screen
    expect(find.text('OpenBot Mobile Control'), findsOneWidget);
  });
}
