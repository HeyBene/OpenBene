import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' hide ConnectionState;
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../models/sensor_data.dart';
import '../models/connection_state.dart';
import '../models/robot_connection_mode.dart';
import '../models/robot_drive_profile.dart';
import '../services/camera_service.dart';
import '../services/sensor_service.dart';
import '../services/network_service.dart';
import '../services/permission_service.dart';
import '../services/discovery_service.dart';
import '../services/usb_service.dart';
import '../services/bluetooth_service.dart' as ble;

/// 控制命令记录
class CommandLog {
  final DateTime timestamp;
  final String command;
  final List<double>? values;

  CommandLog({
    required this.timestamp,
    required this.command,
    this.values,
  });

  String get formattedTime {
    return '${timestamp.hour.toString().padLeft(2, '0')}:'
        '${timestamp.minute.toString().padLeft(2, '0')}:'
        '${timestamp.second.toString().padLeft(2, '0')}';
  }

  String get displayText {
    if (values != null && values!.isNotEmpty) {
      return '$command(${values!.map((v) => v.toStringAsFixed(2)).join(', ')})';
    }
    return '$command()';
  }
}

class AppState extends ChangeNotifier with WidgetsBindingObserver {
  bool _disposed = false;
  final CameraService _cameraService = CameraService();
  final SensorService _sensorService = SensorService();
  final NetworkService _networkService = NetworkService();
  final PermissionService _permissionService = PermissionService();
  final DiscoveryService _discoveryService = DiscoveryService();
  final UsbService _usbService = UsbService();
  final ble.BluetoothService _bluetoothService = ble.BluetoothService();

  ConnectionState _connectionState = ConnectionState(
    status: ConnectionStatus.disconnected,
  );
  SensorData? _latestSensorData;
  Uint8List? _latestFrame;

  bool _isStreaming = false;
  bool _cameraInitialized = false;
  bool _serverRunning = false;
  String? _localIpAddress;

  // USB/Arduino 连接状态
  bool _usbConnected = false;
  RobotConnectionMode _connectionMode =
      (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS)
          ? RobotConnectionMode.bluetooth
          : RobotConnectionMode.usb;
  String? _robotType;
  Map<String, bool> _robotFeatures = {};
  RobotDriveProfile _driveProfile = RobotDriveProfile.standard;
  bool _isTestingBluetooth = false;
  String? _lastBluetoothTestResult;

  // 命令日志
  final List<CommandLog> _commandLogs = [];
  static const int _maxCommandLogs = 50;

  StreamSubscription? _sensorDataSubscription;
  StreamSubscription? _connectionStateSubscription;
  StreamSubscription? _commandSubscription;
  StreamSubscription? _usbConnectionSubscription;
  StreamSubscription? _usbSensorSubscription;
  StreamSubscription? _bluetoothConnectionSubscription;
  StreamSubscription? _bluetoothMessageSubscription;
  // 定期心跳计时器：每 500ms 向小车发送一次心跳，防止固件 1000ms 超时归零
  Timer? _heartbeatTimer;

  /// Guard: never call notifyListeners() after dispose().
  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  // Getters
  ConnectionState get connectionState => _connectionState;
  SensorData? get latestSensorData => _latestSensorData;
  Uint8List? get latestFrame => _latestFrame;
  bool get isStreaming => _isStreaming;
  bool get cameraInitialized => _cameraInitialized;
  bool get serverRunning => _serverRunning;
  String? get localIpAddress => _localIpAddress;
  int get framesSent => _networkService.framesSent;
  int get sensorUpdatesSent => _networkService.sensorUpdatesSent;
  int get commandsReceived => _networkService.commandsReceived;
  int get serverPort => _networkService.port;
  bool get hasClient => _networkService.hasClient;
  List<CommandLog> get commandLogs => List.unmodifiable(_commandLogs);
  CameraService get cameraService => _cameraService;
  NetworkService get networkService => _networkService;

  // USB/Arduino getters
  bool get usbConnected => _usbConnected;
  RobotConnectionMode get connectionMode => _connectionMode;
  bool get supportsUsb =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  ble.BluetoothService get bluetoothService => _bluetoothService;
  bool get robotConnected => _connectionMode == RobotConnectionMode.usb
      ? _usbConnected
      : _bluetoothService.isConnected;
  String? get robotType => _robotType;
  Map<String, bool> get robotFeatures => Map.unmodifiable(_robotFeatures);
  UsbService get usbService => _usbService;
  RobotDriveProfile get driveProfile => _driveProfile;
  bool get isTestingBluetooth => _isTestingBluetooth;
  String? get lastBluetoothTestResult => _lastBluetoothTestResult;

  void setConnectionMode(RobotConnectionMode mode) {
    if (mode == RobotConnectionMode.usb && !supportsUsb) return;
    if (_connectionMode == mode) return;

    _connectionMode = mode;
    notifyListeners();
  }

  void setDriveProfile(RobotDriveProfile profile) {
    if (_driveProfile == profile) return;
    _driveProfile = profile;
    notifyListeners();
  }

  List<double> _applyDriveCompensation(double left, double right) {
    final (gain, minStart) = switch (_driveProfile) {
      RobotDriveProfile.standard => (1.0, 0.0),
      RobotDriveProfile.rtr520 => (1.2, 0.22),
    };

    return [
      _compensateSingle(left, gain: gain, minStart: minStart),
      _compensateSingle(right, gain: gain, minStart: minStart),
    ];
  }

  double _compensateSingle(
    double value, {
    required double gain,
    required double minStart,
  }) {
    final signed = value.clamp(-1.0, 1.0);
    final absValue = signed.abs();
    if (absValue < 0.02) return 0.0;

    final normalized = (minStart + (1.0 - minStart) * absValue) * gain;
    final clamped = normalized.clamp(0.0, 1.0);
    return signed.sign * clamped;
  }

  Future<void> initialize() async {
    WidgetsBinding.instance.addObserver(this);
    await _sensorService.initialize();
    await _networkService.initialize();

    // 获取本机IP
    _localIpAddress = await _networkService.getLocalIpAddress();

    // 监听连接状态
    _connectionStateSubscription =
        _networkService.connectionStateStream?.listen((state) {
      _connectionState = state;
      // Sync _serverRunning with the actual socket state.
      // On iOS the socket can be killed while backgrounded; NetworkService
      // sets _isRunning=false via onDone, but AppState._serverRunning was
      // never updated — causing the UI to claim the server is running while
      // the port is dead and the PC gets "connection refused".
      if (!_networkService.isRunning && _serverRunning) {
        _serverRunning = false;
        // Race-condition fix: onDone sometimes fires *after* the
        // AppLifecycle.resumed event, so _restartServerOnResume() already
        // ran with isRunning==true and skipped the restart.  Retry here
        // whenever the socket dies while the app is in the foreground.
        final lifecycle = WidgetsBinding.instance.lifecycleState;
        if (lifecycle == AppLifecycleState.resumed) {
          unawaited(_restartServerOnResume());
        }
      }
      notifyListeners();
    });

    // 监听PC发来的命令
    _commandSubscription =
        _networkService.commandStream?.listen(_handleCommand);

    // 监听USB连接状态
    _usbConnectionSubscription =
        _usbService.connectionStateStream.listen((connected) {
      _usbConnected = connected;
      notifyListeners();
    });

    // 监听Arduino传感器数据
    _usbSensorSubscription =
        _usbService.sensorDataStream.listen(_handleArduinoSensorData);

    _bluetoothConnectionSubscription =
        _bluetoothService.connectionStream.listen((_) {
      notifyListeners();
    });

    // 监听 BLE 传感器原始数据（ESP32 → App）
    _bluetoothMessageSubscription =
        _bluetoothService.messageStream.listen(_handleBluetoothMessage);
  }

  /// 建Robot心跳定时器：每 500ms 重置固件心跳计时
  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (!robotConnected) {
        _stopHeartbeat();
        return;
      }
      if (_connectionMode == RobotConnectionMode.usb) {
        _usbService.setHeartbeat(1000);
      } else {
        _bluetoothService.setHeartbeat(1000);
      }
    });
  }

  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  /// 解析 BLE 原始字符串并路由到 _handleArduinoSensorData
  ///
  /// ESP32 通过 BLE TX 特征发送的行格式（与 sendData() 一致）：
  ///   f<type>:<caps>   特征包，例如 "fRTR_520:v:i:s:b:wf:wb:"
  ///   v<val>           电压，例如 "v11.54"
  ///   w<l>,<r>         车速 RPM，例如 "w120.5,118.3"
  ///   s<dist>          声呐距离，例如 "s45"
  ///   b<id>            保险杠碰撞，例如 "blf"
  void _handleBluetoothMessage(String raw) {
    if (raw.isEmpty) return;
    final header = raw[0];
    final body = raw.length > 1 ? raw.substring(1) : '';

    switch (header) {
      case 'f':
        // 特征包：fRTR_520:v:i:s:b:wf:wb:lf:lb:ls:
        final colonIdx = body.indexOf(':');
        final robotType =
            colonIdx != -1 ? body.substring(0, colonIdx) : body;
        final capStr =
            colonIdx != -1 ? body.substring(colonIdx + 1) : '';
        final caps = capStr
            .split(':')
            .where((s) => s.isNotEmpty)
            .toList();
        final featMap = {for (final c in caps) c: true};
        _handleArduinoSensorData({
          'type': 'features',
          'robot_type': robotType,
          'features': featMap,
        });

      case 'v':
        final voltage = double.tryParse(body);
        if (voltage != null) {
          _handleArduinoSensorData({
            'type': 'voltage',
            'value': voltage,
          });
        }

      case 'w':
        final parts = body.split(',');
        if (parts.length >= 2) {
          _handleArduinoSensorData({
            'type': 'wheel',
            'left': double.tryParse(parts[0]) ?? 0.0,
            'right': double.tryParse(parts[1]) ?? 0.0,
          });
        }

      case 's':
        final dist = int.tryParse(body);
        if (dist != null) {
          _handleArduinoSensorData({
            'type': 'sonar',
            'distance': dist,
          });
        }

      case 'b':
        _handleArduinoSensorData({
          'type': 'bumper',
          'collision_id': body,
        });

      default:
        debugPrint('[BLE] 未知消息: $raw');
    }
  }

  /// 处理传感器数据（USB 和 BLE 共用）
  void _handleArduinoSensorData(Map<String, dynamic> data) {
    final type = data['type'] as String?;
    if (type == null) return;

    switch (type) {
      case 'features':
        _robotType = data['robot_type'] as String?;
        _robotFeatures = Map<String, bool>.from(data['features'] ?? {});
        // 根据车型自动设置驱动档
        _autoSetDriveProfile(_robotType);
        notifyListeners();

      case 'voltage':
      case 'wheel':
      case 'sonar':
      case 'bumper':
        // 将传感器数据转发给PC
        _networkService.sendMessage({
          'type': 'arduino_sensor',
          'sensor_type': type,
          'data': data,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        });
    }
  }

  /// 根据固件上报的车型自动选择合适的驱动档，并设置传感器上报间隔
  ///
  /// RTR_520：520 电机静摩擦更大，需要 gain=1.2 / minStart=22%
  /// 其余（TT、DIY 等）：使用标准档
  void _autoSetDriveProfile(String? robotType) {
    final target = (robotType == 'RTR_520')
        ? RobotDriveProfile.rtr520
        : RobotDriveProfile.standard;
    if (_driveProfile != target) {
      _driveProfile = target;
      debugPrint('[AppState] 驱动档自动切换 → $target（车型=$robotType）');
    }
    // 收到特征包后设置各传感器间隔（USB 连接时 _robotFeatures 已更新）
    if (_connectionMode == RobotConnectionMode.usb) {
      if (_robotFeatures['wheel_front'] == true ||
          _robotFeatures['wheel_back'] == true) {
        _usbService.setWheelInterval(200);
      }
      if (_robotFeatures['sonar'] == true) {
        _usbService.setSonarInterval(500);
      }
    }
  }

  /// 处理PC发来的控制命令
  void _handleCommand(Map<String, dynamic> message) {
    final cmd = message['cmd'] as String?;
    if (cmd == null) return;

    List<double>? values;
    if (message['val'] != null) {
      values =
          (message['val'] as List).map((e) => (e as num).toDouble()).toList();
    }

    // 记录命令
    _addCommandLog(cmd, values);

    // 将命令转发给小车（USB/BLE）
    _forwardCommandToRobot(cmd, values);

    notifyListeners();
  }

  /// 将PC命令转发给小车（USB/BLE）
  void _forwardCommandToRobot(String cmd, List<double>? values) {
    if (!robotConnected) {
      debugPrint(
          '[AppState] Robot not connected, cannot forward command: $cmd');
      return;
    }

    switch (cmd) {
      case 'drive':
        // drive命令: values = [left, right], 范围 -1.0 到 1.0
        if (values != null && values.length >= 2) {
          final compensated = _applyDriveCompensation(values[0], values[1]);
          if (_connectionMode == RobotConnectionMode.usb) {
            _usbService.sendControlNormalized(compensated[0], compensated[1]);
          } else {
            _bluetoothService.sendControlNormalized(
              compensated[0],
              compensated[1],
            );
          }
        }
        break;

      case 'stop':
        if (_connectionMode == RobotConnectionMode.usb) {
          _usbService.stop();
        } else {
          _bluetoothService.stop();
        }
        break;

      case 'indicator':
        // indicator命令: values = [left, right], 0 或 1
        if (values != null && values.length >= 2) {
          if (_connectionMode == RobotConnectionMode.usb) {
            _usbService.setIndicators(values[0].toInt(), values[1].toInt());
          } else {
            _bluetoothService.setIndicators(
                values[0].toInt(), values[1].toInt());
          }
        }
        break;

      case 'light':
        // light命令: values = [front, back], 0-255
        if (values != null && values.length >= 2) {
          if (_connectionMode == RobotConnectionMode.usb) {
            _usbService.setLights(values[0].toInt(), values[1].toInt());
          } else {
            _bluetoothService.setLights(values[0].toInt(), values[1].toInt());
          }
        }
        break;

      case 'heartbeat':
        // heartbeat命令: values = [interval_ms]
        if (values != null && values.isNotEmpty) {
          if (_connectionMode == RobotConnectionMode.usb) {
            _usbService.setHeartbeat(values[0].toInt());
          } else {
            _bluetoothService.setHeartbeat(values[0].toInt());
          }
        }
        break;

      default:
        debugPrint('[AppState] Unknown command: $cmd');
    }
  }

  void _addCommandLog(String command, List<double>? values) {
    _commandLogs.insert(
      0,
      CommandLog(
        timestamp: DateTime.now(),
        command: command,
        values: values,
      ),
    );

    // 限制日志数量
    if (_commandLogs.length > _maxCommandLogs) {
      _commandLogs.removeLast();
    }
  }

  Future<Map<String, dynamic>> requestPermissions() async {
    return await _permissionService.requestAllPermissions();
  }

  Future<bool> openPermissionSettings() async {
    return await _permissionService.openSettings();
  }

  Future<bool> initializeCamera() async {
    try {
      print('[DEBUG] initializeCamera() called');
      await _cameraService.initialize();
      print('[DEBUG] Camera service initialized successfully');
      _cameraInitialized = true;
      notifyListeners();
      return true;
    } catch (e) {
      print('[DEBUG] Camera initialization FAILED: $e');
      debugPrint('Failed to initialize camera: $e');
      return false;
    }
  }

  /// 启动WebSocket服务器
  Future<bool> startServer({int port = 8765}) async {
    final success = await _networkService.startServer(port: port);
    _serverRunning = success;

    // 启动UDP广播发现服务
    if (success) {
      await _discoveryService.startBroadcast(
        deviceName: 'OpenBene Robot',
        wsPort: port,
      );
    }

    notifyListeners();
    return success;
  }

  /// 停止WebSocket服务器
  Future<void> stopServer() async {
    await stopStreaming();
    _discoveryService.stopBroadcast();
    await _networkService.stopServer();
    _serverRunning = false;
    notifyListeners();
  }

  Future<void> startStreaming() async {
    if (_isStreaming) return;
    if (!_serverRunning) return;

    try {
      // Start camera streaming
      await _cameraService.startStreaming(
        onFrame: (frame) {
          final frameData = frame as Uint8List;
          _latestFrame = frameData;
          _networkService.sendVideoFrame(frameData);
          // Don't notify listeners for every frame - too expensive
        },
        quality: 75,
        targetWidth: 640,
      );

      // Start sensor listening with reduced update rate for UI
      _sensorService.startListening(intervalMs: 100);

      int uiUpdateCounter = 0;
      _sensorDataSubscription =
          _sensorService.sensorDataStream?.listen((sensorData) {
        _latestSensorData = sensorData;
        _networkService.sendSensorData(sensorData);

        // Only notify listeners every 3rd update (300ms instead of 100ms)
        uiUpdateCounter++;
        if (uiUpdateCounter >= 3) {
          uiUpdateCounter = 0;
          notifyListeners();
        }
      });

      _isStreaming = true;
      notifyListeners();
    } catch (e) {
      debugPrint('Failed to start streaming: $e');
    }
  }

  Future<void> stopStreaming() async {
    if (!_isStreaming) return;

    await _cameraService.stopStreaming();
    await _sensorService.stopListening();
    await _sensorDataSubscription?.cancel();
    _sensorDataSubscription = null;

    _isStreaming = false;
    notifyListeners();
  }

  /// 清除命令日志
  void clearCommandLogs() {
    _commandLogs.clear();
    notifyListeners();
  }

  /// 重置统计数据
  void resetStats() {
    _networkService.resetStats();
    notifyListeners();
  }

  /// 连接到OpenBot小车（USB）
  Future<bool> connectToRobot() async {
    if (_connectionMode != RobotConnectionMode.usb) {
      return false;
    }

    final success = await _usbService.connect();
    if (success) {
      // 启动心跳计时器（每 500ms 发一次，防止固件 1000ms 超时）
      _startHeartbeat();
      // 开启电压上报——其他传感器间隔在收到特征包后由 _onFeaturesReceived 设置
      await _usbService.setVoltageInterval(1000);
    }
    return success;
  }

  /// 连接到OpenBot小车（BLE）
  Future<bool> connectToRobotWithBluetooth(BluetoothDevice device) async {
    final success = await _bluetoothService.connect(device);
    if (success) {
      // 启动心跳计时器
      _startHeartbeat();
      _lastBluetoothTestResult = null;
      // 连接后请求特征包，触发车型检测和驱动档自动切换
      await Future.delayed(const Duration(milliseconds: 300));
      await _bluetoothService.requestFeatures();
      notifyListeners();
    }
    return success;
  }

  /// BLE连接链路测试：发送 f 包并等待 f... 返回
  Future<bool> testBluetoothConnection() async {
    if (_connectionMode != RobotConnectionMode.bluetooth ||
        !_bluetoothService.isConnected) {
      _lastBluetoothTestResult = 'Bluetooth is not connected';
      notifyListeners();
      return false;
    }

    _isTestingBluetooth = true;
    _lastBluetoothTestResult = null;
    notifyListeners();

    final response = await _bluetoothService.testConnection();
    _isTestingBluetooth = false;

    if (response == null) {
      _lastBluetoothTestResult = 'No response from robot (timeout)';
      notifyListeners();
      return false;
    }

    _lastBluetoothTestResult = 'OK: $response';
    notifyListeners();
    return true;
  }

  /// 断开OpenBot小车连接
  Future<void> disconnectFromRobot() async {
    _stopHeartbeat();
    if (_connectionMode == RobotConnectionMode.usb) {
      await _usbService.stop();
      await _usbService.disconnect();
    } else {
      await _bluetoothService.stop();
      await _bluetoothService.disconnect();
      _lastBluetoothTestResult = null;
    }
    // 断连后清除车型信息，下次连接重新检测
    _robotType = null;
    _robotFeatures = {};
    notifyListeners();
  }

  /// iOS front/background lifecycle: release camera & network when suspended,
  /// reinitialize when resumed to prevent AVFoundation / socket crashes.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      // Stop streaming flag immediately so AppNavigator switches to
      // ConnectionScreen BEFORE the camera is disposed asynchronously.
      final wasStreamingOrInitialized = _isStreaming || _cameraInitialized;
      if (wasStreamingOrInitialized) {
        _isStreaming = false;
        _cameraInitialized = false;
        notifyListeners();
        unawaited(_cameraService.dispose());
      }
    } else if (state == AppLifecycleState.resumed) {
      // Only restart if the server socket actually died while backgrounded.
      // Unconditional restart caused a 300-500 ms gap on every screen-unlock
      // which made the PC's WebSocket handshake time out even though TCP was
      // accepted.
      if (!_networkService.isRunning) {
        unawaited(_restartServerOnResume());
      } else {
        notifyListeners();
      }
    }
  }

  /// Stop and restart the WebSocket server + UDP discovery broadcast.
  /// Called every time the app resumes from background on iOS to ensure the
  /// server socket is alive (iOS may have silently killed it).
  Future<void> _restartServerOnResume() async {
    // Tear down whatever state the socket is in (running, limbo, or dead).
    _discoveryService.stopBroadcast();
    await _networkService.stopServer();
    _serverRunning = false;

    // Refresh local IP — it may have changed if the user switched networks.
    _localIpAddress = await _networkService.getLocalIpAddress();

    // Restart server.
    final success = await _networkService.startServer(port: 8765);
    _serverRunning = success;
    if (success) {
      await _discoveryService.startBroadcast(
        deviceName: 'OpenBene Robot',
        wsPort: 8765,
      );
    }

    // Camera re-init is handled by ConnectionScreen's own lifecycle observer.
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _sensorDataSubscription?.cancel();
    _connectionStateSubscription?.cancel();
    _commandSubscription?.cancel();
    _usbConnectionSubscription?.cancel();
    _usbSensorSubscription?.cancel();
    _bluetoothConnectionSubscription?.cancel();
    _bluetoothMessageSubscription?.cancel();
    _stopHeartbeat();
    _cameraService.dispose();
    _sensorService.dispose();
    _networkService.dispose();
    _discoveryService.dispose();
    _usbService.dispose();
    unawaited(_bluetoothService.dispose());
    super.dispose();
  }
}
