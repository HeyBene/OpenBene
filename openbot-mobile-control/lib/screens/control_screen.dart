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

  // 0: 隐藏, 1: 传感器, 2: 命令日志
  int _bottomPanelMode = 0;

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
    // Streaming is already started from ConnectionScreen
  }

  Future<void> _stopStreaming() async {
    final appState = context.read<AppState>();
    await appState.stopStreaming();
    // AppNavigator will automatically switch back to ConnectionScreen
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
              onPressed: _stopStreaming,
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

              // Bottom Panel (toggleable)
              if (_bottomPanelMode != 0)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  height: 200,
                  child: _bottomPanelMode == 1
                      ? SensorDashboard(
                          sensorData: appState.latestSensorData,
                          framesSent: appState.framesSent,
                          sensorUpdatesSent: appState.sensorUpdatesSent,
                        )
                      : _buildCommandLog(appState),
                ),

              // Bottom Navigation Bar
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.1),
                      blurRadius: 8,
                      offset: const Offset(0, -2),
                    ),
                  ],
                ),
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _buildNavButton(
                          icon: Icons.fullscreen_rounded,
                          label: 'Full',
                          isSelected: _bottomPanelMode == 0,
                          onTap: () => setState(() => _bottomPanelMode = 0),
                        ),
                        _buildNavButton(
                          icon: Icons.sensors_rounded,
                          label: 'Sensors',
                          isSelected: _bottomPanelMode == 1,
                          badge: appState.sensorUpdatesSent > 0 ? '${appState.sensorUpdatesSent}' : null,
                          onTap: () => setState(() => _bottomPanelMode = 1),
                        ),
                        _buildNavButton(
                          icon: Icons.terminal_rounded,
                          label: 'Commands',
                          isSelected: _bottomPanelMode == 2,
                          badge: appState.commandsReceived > 0 ? '${appState.commandsReceived}' : null,
                          onTap: () => setState(() => _bottomPanelMode = 2),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildNavButton({
    required IconData icon,
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
    String? badge,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? Colors.blue.shade50 : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: isSelected
              ? Border.all(color: Colors.blue.shade200, width: 1.5)
              : null,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(
                  icon,
                  color: isSelected ? Colors.blue.shade700 : Colors.grey.shade600,
                  size: 24,
                ),
                if (badge != null)
                  Positioned(
                    right: -8,
                    top: -4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                      decoration: BoxDecoration(
                        color: Colors.red.shade500,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      constraints: const BoxConstraints(minWidth: 16),
                      child: Text(
                        badge,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                color: isSelected ? Colors.blue.shade700 : Colors.grey.shade600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCommandLog(AppState appState) {
    final localization = context.read<LocalizationService>();
    final commandLogs = appState.commandLogs;

    return Card(
      margin: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.terminal_rounded,
                    size: 18, color: Colors.blue.shade700),
                const SizedBox(width: 8),
                Text(
                  'Commands (${appState.commandsReceived})',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.blue.shade900,
                  ),
                ),
                const Spacer(),
                if (commandLogs.isNotEmpty)
                  GestureDetector(
                    onTap: appState.clearCommandLogs,
                    child: Icon(Icons.clear_all_rounded,
                        size: 18, color: Colors.grey.shade600),
                  ),
              ],
            ),
          ),
          Expanded(
            child: commandLogs.isEmpty
                ? Center(
                    child: Text(
                      'No commands received',
                      style: TextStyle(
                        color: Colors.grey.shade500,
                        fontSize: 12,
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    itemCount: commandLogs.length,
                    itemBuilder: (context, index) {
                      final log = commandLogs[index];
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(
                          children: [
                            Text(
                              log.formattedTime,
                              style: TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 10,
                                color: Colors.grey.shade500,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                log.displayText,
                                style: const TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 12,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
