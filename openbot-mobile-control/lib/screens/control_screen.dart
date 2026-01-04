import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:camera/camera.dart';
import '../services/app_state.dart';
import '../services/localization_service.dart';
import '../models/connection_state.dart';
import '../widgets/sensor_dashboard.dart';

class ControlScreen extends StatefulWidget {
  const ControlScreen({super.key});

  @override
  State<ControlScreen> createState() => _ControlScreenState();
}

class _ControlScreenState extends State<ControlScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.7, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _startStreaming();
  }

  Future<void> _startStreaming() async {
    final appState = context.read<AppState>();
    await appState.startStreaming();
  }

  Future<void> _disconnect() async {
    final appState = context.read<AppState>();
    await appState.disconnect();
    // Don't use Navigator.pop() - let AppNavigator handle the transition
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  String _getStatusText(BuildContext context, ConnectionStatus status) {
    final localization = context.read<LocalizationService>();
    switch (status) {
      case ConnectionStatus.connected:
        return localization.get('connected');
      case ConnectionStatus.connecting:
        return localization.get('connecting_status');
      case ConnectionStatus.reconnecting:
        return localization.get('reconnecting');
      case ConnectionStatus.error:
        return localization.get('error');
      case ConnectionStatus.disconnected:
        return localization.get('disconnected');
    }
  }

  Widget _buildStatusIndicator(BuildContext context, ConnectionStatus status) {
    final statusText = _getStatusText(context, status);
    Color statusColor;
    IconData statusIcon;
    bool shouldPulse = false;

    switch (status) {
      case ConnectionStatus.connected:
        statusColor = Colors.green.shade600;
        statusIcon = Icons.check_circle_rounded;
        break;
      case ConnectionStatus.connecting:
      case ConnectionStatus.reconnecting:
        statusColor = Colors.orange.shade600;
        statusIcon = Icons.sync_rounded;
        shouldPulse = true;
        break;
      case ConnectionStatus.error:
        statusColor = Colors.red.shade600;
        statusIcon = Icons.error_rounded;
        break;
      default:
        statusColor = Colors.grey.shade600;
        statusIcon = Icons.circle;
    }

    final Widget indicator = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: statusColor.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: statusColor.withValues(alpha: 0.4),
          width: 1.5,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(statusIcon, color: statusColor, size: 18),
          const SizedBox(width: 6),
          Text(
            statusText,
            style: TextStyle(
              color: statusColor,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );

    if (shouldPulse) {
      return AnimatedBuilder(
        animation: _pulseAnimation,
        builder: (context, child) {
          return Opacity(
            opacity: _pulseAnimation.value,
            child: child,
          );
        },
        child: indicator,
      );
    }

    return indicator;
  }

  @override
  Widget build(BuildContext context) {
    final localization = context.read<LocalizationService>();

    return Scaffold(
      appBar: AppBar(
        title: Text(
          localization.get('camera_preview'),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.blue.shade700,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          Consumer<AppState>(
            builder: (context, appState, child) {
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8.0),
                child: _buildStatusIndicator(
                  context,
                  appState.connectionState.status,
                ),
              );
            },
          ),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: IconButton(
              icon: const Icon(Icons.logout_rounded),
              onPressed: _disconnect,
              tooltip: localization.get('disconnect'),
              color: Colors.white,
            ),
          ),
        ],
      ),
      body: Consumer<AppState>(
        builder: (context, appState, child) {
          return Column(
            children: [
              // Camera Preview Section
              Expanded(
                flex: 3,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.black,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.3),
                        blurRadius: 10,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Stack(
                    children: [
                      // Camera Preview
                      if (appState.cameraInitialized &&
                          appState.cameraService.controller != null)
                        Center(
                          child: CameraPreview(
                              appState.cameraService.controller!),
                        )
                      else
                        Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              CircularProgressIndicator(
                                color: Colors.blue.shade400,
                                strokeWidth: 3,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                localization.get('connecting_status'),
                                style: TextStyle(
                                  color: Colors.grey.shade400,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        ),
                      // Recording Indicator
                      if (appState.connectionState.status ==
                          ConnectionStatus.connected)
                        Positioned(
                          top: 16,
                          left: 16,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.red.shade600,
                              borderRadius: BorderRadius.circular(20),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.red.withValues(alpha: 0.4),
                                  blurRadius: 8,
                                  spreadRadius: 2,
                                ),
                              ],
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                AnimatedBuilder(
                                  animation: _pulseAnimation,
                                  builder: (context, child) {
                                    return Opacity(
                                      opacity: _pulseAnimation.value,
                                      child: Container(
                                        width: 8,
                                        height: 8,
                                        decoration: const BoxDecoration(
                                          color: Colors.white,
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                    );
                                  },
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  localization.get('streaming'),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),

              // Sensor Dashboard Section
              Expanded(
                flex: 2,
                child: SensorDashboard(
                  sensorData: appState.latestSensorData,
                  framesSent: appState.framesSent,
                  sensorUpdatesSent: appState.sensorUpdatesSent,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
