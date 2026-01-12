import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import '../models/sensor_data.dart';
import '../models/connection_state.dart';
import '../services/camera_service.dart';
import '../services/sensor_service.dart';
import '../services/network_service.dart';
import '../services/permission_service.dart';
import '../services/discovery_service.dart';
import '../services/usb_service.dart';

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

class AppState extends ChangeNotifier {
  final CameraService _cameraService = CameraService();
  final SensorService _sensorService = SensorService();
  final NetworkService _networkService = NetworkService();
  final PermissionService _permissionService = PermissionService();
  final DiscoveryService _discoveryService = DiscoveryService();
  final UsbService _usbService = UsbService();

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
  String? _robotType;
  Map<String, bool> _robotFeatures = {};

  // 命令日志
  final List<CommandLog> _commandLogs = [];
  static const int _maxCommandLogs = 50;

  StreamSubscription? _sensorDataSubscription;
  StreamSubscription? _connectionStateSubscription;
  StreamSubscription? _commandSubscription;
  StreamSubscription? _usbConnectionSubscription;
  StreamSubscription? _usbSensorSubscription;

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
  String? get robotType => _robotType;
  Map<String, bool> get robotFeatures => Map.unmodifiable(_robotFeatures);
  UsbService get usbService => _usbService;

  Future<void> initialize() async {
    await _sensorService.initialize();
    await _networkService.initialize();

    // 获取本机IP
    _localIpAddress = await _networkService.getLocalIpAddress();

    // 监听连接状态
    _connectionStateSubscription =
        _networkService.connectionStateStream?.listen((state) {
      _connectionState = state;
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
  }

  /// 处理Arduino传感器数据
  void _handleArduinoSensorData(Map<String, dynamic> data) {
    final type = data['type'] as String?;
    if (type == null) return;

    switch (type) {
      case 'features':
        _robotType = data['robot_type'] as String?;
        _robotFeatures = Map<String, bool>.from(data['features'] ?? {});
        notifyListeners();
        break;

      case 'voltage':
      case 'wheel':
      case 'sonar':
      case 'bumper':
        // 将Arduino传感器数据转发给PC
        _networkService.sendMessage({
          'type': 'arduino_sensor',
          'sensor_type': type,
          'data': data,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        });
        break;
    }
  }

  /// 处理PC发来的控制命令
  void _handleCommand(Map<String, dynamic> message) {
    final cmd = message['cmd'] as String?;
    if (cmd == null) return;

    List<double>? values;
    if (message['val'] != null) {
      values = (message['val'] as List)
          .map((e) => (e as num).toDouble())
          .toList();
    }

    // 记录命令
    _addCommandLog(cmd, values);

    // 将命令转发给Arduino
    _forwardCommandToArduino(cmd, values);

    notifyListeners();
  }

  /// 将PC命令转发给Arduino
  void _forwardCommandToArduino(String cmd, List<double>? values) {
    if (!_usbConnected) {
      debugPrint('[AppState] USB not connected, cannot forward command: $cmd');
      return;
    }

    switch (cmd) {
      case 'drive':
        // drive命令: values = [left, right], 范围 -1.0 到 1.0
        if (values != null && values.length >= 2) {
          _usbService.sendControlNormalized(values[0], values[1]);
        }
        break;

      case 'stop':
        _usbService.stop();
        break;

      case 'indicator':
        // indicator命令: values = [left, right], 0 或 1
        if (values != null && values.length >= 2) {
          _usbService.setIndicators(values[0].toInt(), values[1].toInt());
        }
        break;

      case 'light':
        // light命令: values = [front, back], 0-255
        if (values != null && values.length >= 2) {
          _usbService.setLights(values[0].toInt(), values[1].toInt());
        }
        break;

      case 'heartbeat':
        // heartbeat命令: values = [interval_ms]
        if (values != null && values.isNotEmpty) {
          _usbService.setHeartbeat(values[0].toInt());
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

  Future<Map<String, bool>> requestPermissions() async {
    return await _permissionService.requestAllPermissions();
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
    final success = await _usbService.connect();
    if (success) {
      // 设置心跳间隔（防止超时停止）
      await _usbService.setHeartbeat(1000);
      // 请求传感器数据
      await _usbService.setVoltageInterval(1000);
      if (_robotFeatures['wheel_front'] == true ||
          _robotFeatures['wheel_back'] == true) {
        await _usbService.setWheelInterval(100);
      }
      if (_robotFeatures['sonar'] == true) {
        await _usbService.setSonarInterval(100);
      }
    }
    return success;
  }

  /// 断开OpenBot小车连接
  Future<void> disconnectFromRobot() async {
    await _usbService.stop();
    await _usbService.disconnect();
  }

  @override
  void dispose() {
    _sensorDataSubscription?.cancel();
    _connectionStateSubscription?.cancel();
    _commandSubscription?.cancel();
    _usbConnectionSubscription?.cancel();
    _usbSensorSubscription?.cancel();
    _cameraService.dispose();
    _sensorService.dispose();
    _networkService.dispose();
    _discoveryService.dispose();
    _usbService.dispose();
    super.dispose();
  }
}
