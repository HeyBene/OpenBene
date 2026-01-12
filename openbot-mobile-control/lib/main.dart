import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'services/app_state.dart';
import 'services/localization_service.dart';
import 'screens/connection_screen.dart';
import 'screens/control_screen.dart';
import 'models/connection_state.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const OpenBotApp());
}

class OpenBotApp extends StatelessWidget {
  const OpenBotApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AppState()..initialize()),
        ChangeNotifierProvider(create: (_) => LocalizationService()),
      ],
      child: MaterialApp(
        title: 'OpenBot Control',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
          useMaterial3: true,
        ),
        home: const AppNavigator(),
        debugShowCheckedModeBanner: false,
      ),
    );
  }
}

class AppNavigator extends StatelessWidget {
  const AppNavigator({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, appState, child) {
        final isStreaming = appState.isStreaming;

        print('[DEBUG] AppNavigator building');
        print('[DEBUG]   isStreaming: $isStreaming');

        // 只有开始流媒体后才切换到控制页面
        if (isStreaming) {
          print('[DEBUG]   -> Showing ControlScreen');
          return const ControlScreen();
        } else {
          print('[DEBUG]   -> Showing ConnectionScreen');
          return const ConnectionScreen();
        }
      },
    );
  }
}
