import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/robot_connection_mode.dart';
import '../models/robot_drive_profile.dart';
import '../services/app_state.dart';
import '../services/localization_service.dart';
import '../models/app_language.dart';
import '../widgets/bluetooth_scan_sheet.dart';

class ConnectionScreen extends StatefulWidget {
  const ConnectionScreen({super.key});

  @override
  State<ConnectionScreen> createState() => _ConnectionScreenState();
}

class _ConnectionScreenState extends State<ConnectionScreen>
    with SingleTickerProviderStateMixin {
  bool _permissionsGranted = false;
  bool _isStartingStream = false;
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeIn,
    );
    _animationController.forward();
    _initializeAndStartServer();
  }

  Future<void> _initializeAndStartServer() async {
    print('[DEBUG] Initializing and starting server...');
    final appState = context.read<AppState>();

    // 1. 请求权限
    final permissions = await appState.requestPermissions();
    if (!mounted) return;
    setState(() {
      _permissionsGranted = permissions['camera'] == true;
    });

    if (!_permissionsGranted) {
      print('[DEBUG] Camera permission not granted');
      return;
    }

    // 2. 初始化摄像头
    print('[DEBUG] Initializing camera...');
    await appState.initializeCamera();

    // 3. 自动启动服务器（等待PC连接）
    print('[DEBUG] Starting server...');
    await appState.startServer();
    print('[DEBUG] Server started, waiting for PC connection...');
  }

  Future<void> _requestPermissions() async {
    final appState = context.read<AppState>();
    final permissions = await appState.requestPermissions();

    if (!mounted) return;
    setState(() {
      _permissionsGranted = permissions['camera'] == true;
    });

    if (_permissionsGranted) {
      await appState.initializeCamera();
      if (!mounted) return;
      await appState.startServer();
    }
  }

  Future<void> _startStreaming() async {
    if (_isStartingStream) return;

    setState(() => _isStartingStream = true);

    final appState = context.read<AppState>();
    await appState.startStreaming();

    if (!mounted) return;
    setState(() => _isStartingStream = false);
  }

  Widget _buildHeader() {
    final localization = context.read<LocalizationService>();
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              colors: [
                Colors.blue.shade400,
                Colors.blue.shade700,
              ],
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.blue.withOpacity(0.3),
                blurRadius: 20,
                spreadRadius: 5,
              ),
            ],
          ),
          child: const Icon(
            Icons.smart_toy_outlined,
            size: 64,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 24),
        Text(
          localization.get('app_name'),
          style: const TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          localization.get('app_subtitle'),
          style: TextStyle(
            fontSize: 15,
            color: Colors.grey.shade600,
            fontWeight: FontWeight.w400,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildPermissionWarning() {
    final localization = context.read<LocalizationService>();
    return Card(
      elevation: 0,
      color: Colors.orange.shade50,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.orange.shade200, width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Row(
              children: [
                Icon(Icons.warning_amber_rounded,
                    color: Colors.orange.shade700, size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    localization.get('camera_permission_required'),
                    style: TextStyle(
                      color: Colors.orange.shade900,
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _requestPermissions,
                icon: const Icon(Icons.refresh_rounded),
                label: Text(localization.get('grant_permissions')),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.all(14),
                  backgroundColor: Colors.orange.shade600,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildServerInfo() {
    final appState = context.watch<AppState>();
    final isConnected = appState.hasClient;
    final isServerRunning = appState.serverRunning;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 连接状态指示器
            _buildConnectionStatus(isServerRunning, isConnected),

            const SizedBox(height: 16),

            // 小车连接状态和按钮（USB/BLE）
            _buildRobotConnectionCard(appState),

            const SizedBox(height: 24),

            // 开始流媒体按钮（只有连接成功后才可用）
            ElevatedButton.icon(
              onPressed: isConnected && !_isStartingStream ? _startStreaming : null,
              icon: _isStartingStream
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.videocam_rounded, size: 24),
              label: Text(
                _isStartingStream
                    ? 'Starting...'
                    : isConnected
                        ? 'Start Streaming'
                        : 'Waiting for PC...',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
              ),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                backgroundColor: isConnected ? Colors.green.shade600 : Colors.grey.shade400,
                foregroundColor: Colors.white,
                elevation: isConnected ? 3 : 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                disabledBackgroundColor: Colors.grey.shade300,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRobotConnectionCard(AppState appState) {
    final mode = appState.connectionMode;
    final isConnected = appState.robotConnected;
    final driveProfile = appState.driveProfile;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isConnected ? Colors.green.shade50 : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isConnected ? Colors.green.shade200 : Colors.grey.shade300,
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'OpenBot Connection',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          if (appState.supportsUsb) ...[
            SegmentedButton<RobotConnectionMode>(
              segments: const [
                ButtonSegment(
                  value: RobotConnectionMode.usb,
                  icon: Icon(Icons.usb_rounded, size: 18),
                  label: Text('USB'),
                ),
                ButtonSegment(
                  value: RobotConnectionMode.bluetooth,
                  icon: Icon(Icons.bluetooth_rounded, size: 18),
                  label: Text('Bluetooth'),
                ),
              ],
              selected: {mode},
              onSelectionChanged: (selected) {
                if (isConnected) {
                  appState.disconnectFromRobot();
                }
                appState.setConnectionMode(selected.first);
              },
            ),
            const SizedBox(height: 12),
          ] else ...[
            Row(
              children: [
                Icon(
                  Icons.bluetooth_rounded,
                  size: 16,
                  color: Colors.blue.shade600,
                ),
                const SizedBox(width: 6),
                Text(
                  'Bluetooth (BLE)',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.blue.shade700,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
          ],
          Row(
            children: [
              Icon(
                isConnected ? Icons.check_circle : Icons.circle_outlined,
                color: isConnected ? Colors.green.shade600 : Colors.grey.shade400,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  isConnected
                      ? (mode == RobotConnectionMode.usb
                          ? 'USB Connected: ${appState.robotType ?? "OpenBot"}'
                          : 'BT: ${appState.bluetoothService.connectedDeviceName ?? "Connected"}')
                      : 'Not connected',
                  style: TextStyle(
                    fontSize: 13,
                    color: isConnected ? Colors.green.shade700 : Colors.grey.shade600,
                  ),
                ),
              ),
              ElevatedButton(
                onPressed: isConnected
                    ? () => appState.disconnectFromRobot()
                    : () => _connectToRobot(appState, mode),
                style: ElevatedButton.styleFrom(
                  backgroundColor:
                      isConnected ? Colors.red.shade400 : Colors.blue.shade600,
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: Text(
                  isConnected ? 'Disconnect' : 'Connect',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          if (mode == RobotConnectionMode.bluetooth && isConnected) ...[
            const SizedBox(height: 10),
            const Text(
              'Drive Profile',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            SegmentedButton<RobotDriveProfile>(
              segments: const [
                ButtonSegment(
                  value: RobotDriveProfile.standard,
                  label: Text('Standard'),
                ),
                ButtonSegment(
                  value: RobotDriveProfile.rtr520,
                  label: Text('RTR-520 Boost'),
                ),
              ],
              selected: {driveProfile},
              onSelectionChanged: (selected) {
                appState.setDriveProfile(selected.first);
              },
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: appState.isTestingBluetooth
                      ? null
                      : () async {
                          final ok = await appState.testBluetoothConnection();
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                ok
                                    ? 'BLE test passed: robot responded.'
                                    : 'BLE test failed: no response.',
                              ),
                              backgroundColor:
                                  ok ? Colors.green.shade600 : Colors.red.shade600,
                            ),
                          );
                        },
                  icon: appState.isTestingBluetooth
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.wifi_tethering_rounded, size: 16),
                  label: Text(
                    appState.isTestingBluetooth ? 'Testing...' : 'Test BLE',
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    appState.lastBluetoothTestResult ?? 'Not tested yet',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade700,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _connectToRobot(
      AppState appState, RobotConnectionMode mode) async {
    if (mode == RobotConnectionMode.usb) {
      final success = await appState.connectToRobot();
      if (!success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'USB connection failed. Make sure cable is connected.',
            ),
            backgroundColor: Colors.red.shade600,
          ),
        );
      }
      return;
    }

    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => BluetoothScanSheet(appState: appState),
    );
  }

  Widget _buildConnectionStatus(bool isServerRunning, bool isConnected) {
    final appState = context.watch<AppState>();
    Color statusColor;
    IconData statusIcon;
    String statusText;

    if (isConnected) {
      statusColor = Colors.green.shade600;
      statusIcon = Icons.check_circle_rounded;
      statusText = 'PC Connected';
    } else if (isServerRunning) {
      statusColor = Colors.orange.shade600;
      statusIcon = Icons.sync_rounded;
      statusText = 'Waiting for PC...';
    } else {
      statusColor = Colors.grey.shade600;
      statusIcon = Icons.circle_outlined;
      statusText = 'Initializing...';
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: statusColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: statusColor.withValues(alpha: 0.3), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(statusIcon, color: statusColor, size: 32),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Connection Status',
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      statusText,
                      style: TextStyle(
                        color: statusColor,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              if (!isConnected && isServerRunning)
                SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: statusColor,
                  ),
                ),
            ],
          ),
          // 显示服务器地址信息
          if (isServerRunning && appState.localIpAddress != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.wifi, size: 16, color: Colors.grey.shade700),
                      const SizedBox(width: 8),
                      Text(
                        'Server Address',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade700,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SelectableText(
                    'ws://${appState.localIpAddress}:${appState.serverPort}',
                    style: TextStyle(
                      fontSize: 14,
                      fontFamily: 'monospace',
                      color: Colors.blue.shade800,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'IP: ${appState.localIpAddress}  Port: ${appState.serverPort}',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildConnectionGuide() {
    return Card(
      elevation: 0,
      color: Colors.blue.shade50,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.blue.shade100, width: 1),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.info_outline_rounded,
                    size: 24, color: Colors.blue.shade700),
                const SizedBox(width: 10),
                Text(
                  'Quick Setup Guide',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 17,
                    color: Colors.blue.shade900,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildGuideStep('1', 'Start the server on this phone'),
            _buildGuideStep('2', 'On PC: pip install openbene'),
            _buildGuideStep('3', 'Use the IP address above in Python'),
            _buildGuideStep('4', 'Control the robot from PC!'),
          ],
        ),
      ),
    );
  }

  Widget _buildGuideStep(String number, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: Colors.blue.shade600,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              number,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                text,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey.shade800,
                  height: 1.4,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final localization = context.watch<LocalizationService>();

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          PopupMenuButton<AppLanguage>(
            icon: const Icon(Icons.language),
            onSelected: (AppLanguage language) {
              localization.setLanguage(language);
            },
            itemBuilder: (BuildContext context) => [
              PopupMenuItem<AppLanguage>(
                value: AppLanguage.english,
                child: Row(
                  children: [
                    if (localization.currentLanguage == AppLanguage.english)
                      const Icon(Icons.check, size: 20),
                    if (localization.currentLanguage == AppLanguage.english)
                      const SizedBox(width: 8),
                    const Text('English'),
                  ],
                ),
              ),
              PopupMenuItem<AppLanguage>(
                value: AppLanguage.chinese,
                child: Row(
                  children: [
                    if (localization.currentLanguage == AppLanguage.chinese)
                      const Icon(Icons.check, size: 20),
                    if (localization.currentLanguage == AppLanguage.chinese)
                      const SizedBox(width: 8),
                    const Text('中文'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              theme.colorScheme.primary.withValues(alpha: 0.03),
              theme.colorScheme.secondary.withValues(alpha: 0.02),
            ],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: FadeTransition(
                opacity: _fadeAnimation,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildHeader(),
                    const SizedBox(height: 40),
                    if (!_permissionsGranted) ...[
                      _buildPermissionWarning(),
                      const SizedBox(height: 20),
                    ],
                    _buildServerInfo(),
                    const SizedBox(height: 20),
                    _buildConnectionGuide(),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }
}
