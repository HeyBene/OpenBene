import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'services/app_state.dart';
import 'services/localization_service.dart';
import 'screens/connection_screen.dart';
import 'screens/control_screen.dart';
import 'models/connection_state.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Catch unhandled Flutter framework errors (e.g. widget build failures).
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    debugPrint('[FlutterError] ${details.exceptionAsString()}');
  };

  // Catch unhandled async exceptions that escape all zones (prevents crash
  // from fire-and-forget Futures throwing after the first frame).
  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('[PlatformError] $error\n$stack');
    return true; // handled – do not abort the isolate
  };

  runApp(const OpenBotApp());
}

class OpenBotApp extends StatelessWidget {
  const OpenBotApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) {
          final state = AppState();
          // initialize() is async; use catchError so any failure is logged
          // rather than becoming an unhandled Future that aborts the isolate.
          state.initialize().catchError((Object e, StackTrace st) {
            debugPrint('[AppState] initialize() error: $e\n$st');
          });
          return state;
        }),
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
