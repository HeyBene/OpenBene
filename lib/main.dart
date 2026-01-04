import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'services/app_state.dart';
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
    return ChangeNotifierProvider(
      create: (_) => AppState()..initialize(),
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
        final connectionStatus = appState.connectionState.status;

        if (connectionStatus == ConnectionStatus.connected) {
          return const ControlScreen();
        } else {
          return const ConnectionScreen();
        }
      },
    );
  }
}
