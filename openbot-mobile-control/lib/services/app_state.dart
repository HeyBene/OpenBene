import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import '../models/sensor_data.dart';
import '../models/lidar_data.dart';
import '../models/connection_state.dart';
import '../services/camera_service.dart';
import '../services/sensor_service.dart';
import '../services/network_service.dart';
import '../services/permission_service.dart';
import '../services/lidar_service.dart';


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
  final LiDARService _lidarService = LiDARService();

  ConnectionState _connectionState = ConnectionState(
    status: ConnectionStatus.disconnected,
  );
  SensorData? _latestSensorData;
  LiDARData? _latestLidarData;
  Uint8List? _latestFrame;

  bool _isStreaming = false;
  bool _cameraInitialized = false;
  bool _serverRunning = false;
  String? _localIpAddress;



  // 命令日志
  final List<CommandLog> _commandLogs = [];
  static const int _maxCommandLogs = 50;

  StreamSubscription? _sensorDataSubscription;
  StreamSubscription? _connectionStateSubscription;
  StreamSubscription? _commandSubscription;
  StreamSubscription? _lidarDataSubscription;

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



  Future<void> initialize() async {
    await _sensorService.initialize();
    await _networkService.initialize();
    
    // Initialize LiDAR service (only available on iOS 14.0+ with LiDAR)
    try {
      await _lidarService.initialize();
      debugPrint('[AppState] LiDAR service initialized');
    } catch (e) {
      debugPrint('[AppState] LiDAR not available: $e');
    }

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

    notifyListeners();
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

    notifyListeners();
    return success;
  }

  /// 停止WebSocket服务器
  Future<void> stopServer() async {
    await stopStreaming();
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
        
        // Combine sensor data with latest LiDAR data if available
        // Note: We create a new SensorData object only when LiDAR is available
        // to include the depth information in the network transmission
        if (_latestLidarData != null) {
          final combinedData = SensorData(
            accelerometer: sensorData.accelerometer,
            gyroscope: sensorData.gyroscope,
            magnetometer: sensorData.magnetometer,
            lidar: _latestLidarData,
            batteryLevel: sensorData.batteryLevel,
            voltage: sensorData.voltage,
          );
          _networkService.sendSensorData(combinedData);
        } else {
          _networkService.sendSensorData(sensorData);
        }

        // Only notify listeners every 3rd update (300ms instead of 100ms)
        uiUpdateCounter++;
        if (uiUpdateCounter >= 3) {
          uiUpdateCounter = 0;
          notifyListeners();
        }
      });

      // Start LiDAR capture if available
      if (_lidarService.isInitialized) {
        await _lidarService.startCapture();
        _lidarDataSubscription = _lidarService.lidarDataStream?.listen((lidarData) {
          _latestLidarData = lidarData;
          // LiDAR data will be included in next sensor update
        });
        debugPrint('[AppState] LiDAR capture started');
      }

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
    
    // Stop LiDAR capture
    if (_lidarService.isInitialized) {
      await _lidarService.stopCapture();
      await _lidarDataSubscription?.cancel();
      _lidarDataSubscription = null;
    }

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

  @override
  void dispose() {
    _sensorDataSubscription?.cancel();
    _connectionStateSubscription?.cancel();
    _commandSubscription?.cancel();
    _lidarDataSubscription?.cancel();
    _cameraService.dispose();
    _sensorService.dispose();
    _networkService.dispose();
    _lidarService.dispose();
    super.dispose();
  }
}
