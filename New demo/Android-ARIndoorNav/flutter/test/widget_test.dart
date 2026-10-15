import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openbene_arcore/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.openbene/navigation');
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });
  testWidgets('opens native navigation and allows returning to it', (tester) async {
    var calls = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'openNavigation'); calls++;
      return null;
    });
    await tester.pumpWidget(const OpenBeneApp());
    await tester.pumpAndSettle();
    expect(calls, 1);
    await tester.tap(find.text('打开锚点导航'));
    await tester.pumpAndSettle();
    expect(calls, 2);
  });
  testWidgets('shows platform launch errors and allows retry', (tester) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      throw PlatformException(code: 'launch', message: '相机启动失败');
    });
    await tester.pumpWidget(const OpenBeneApp());
    await tester.pumpAndSettle();
    expect(find.text('相机启动失败'), findsOneWidget);
    expect(find.text('打开锚点导航'), findsOneWidget);
  });
}
