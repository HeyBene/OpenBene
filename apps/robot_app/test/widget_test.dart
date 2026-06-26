import 'package:flutter_test/flutter_test.dart';

import 'package:robot_app/app/robot_app.dart';

void main() {
  testWidgets('Robot app shows setup screen', (WidgetTester tester) async {
    await tester.pumpWidget(const RobotApp());

    expect(find.text('Robot App'), findsWidgets);
    expect(find.text('Enter Robot Camera'), findsOneWidget);
  });
}
