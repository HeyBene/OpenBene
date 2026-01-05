import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import '../models/sensor_data.dart';
import '../models/connection_state.dart';

/// 控制命令回调类型
typedef CommandCallback = void Function(String command, List<double>? values);

/// WebSocket服务器服务
///
/// 手机作为WebSocket服务器，监听PC的连接
/// - 接收PC发来的控制命令
/// - 向PC发送视频帧和传感器数据
class NetworkService {
  HttpServer? _server;
  WebSocket? _client;
  StreamController<ConnectionState>? _connectionStateController;
  StreamController<Map<String, dynamic>>? _commandController;
  Timer? _heartbeatTimer;

  static const int defaultPort = 8765;
  static const Duration _heartbeatInterval = Duration(seconds: 5);

  int _port = defaultPort;
  bool _isRunning = false;
  String? _clientAddress;

  // 统计数据
  int _framesSent = 0;
  int _sensorUpdatesSent = 0;
  int _commandsReceived = 0;

  // Streams
  Stream<ConnectionState>? get connectionStateStream =>
      _connectionStateController?.stream;
  Stream<Map<String, dynamic>>? get commandStream => _commandController?.stream;

  // Getters
  ConnectionStatus _currentStatus = ConnectionStatus.disconnected;
  ConnectionStatus get currentStatus => _currentStatus;
  bool get isRunning => _isRunning;
  bool get hasClient => _client != null;
  String? get clientAddress => _clientAddress;
  int get framesSent => _framesSent;
  int get sensorUpdatesSent => _sensorUpdatesSent;
  int get commandsReceived => _commandsReceived;
  int get port => _port;

  /// 获取本机IP地址
  Future<String?> getLocalIpAddress() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLinkLocal: false,
      );
      for (var interface in interfaces) {
        for (var addr in interface.addresses) {
          // 过滤掉回环地址
          if (!addr.address.startsWith('127.')) {
            return addr.address;
          }
        }
      }
    } catch (e) {
      // 忽略错误
    }
    return null;
  }

  Future<void> initialize() async {
    _connectionStateController = StreamController<ConnectionState>.broadcast();
    _commandController = StreamController<Map<String, dynamic>>.broadcast();
    _updateConnectionState(ConnectionStatus.disconnected);
  }

  /// 启动WebSocket服务器
  Future<bool> startServer({int port = defaultPort}) async {
    if (_isRunning) return true;

    _port = port;

    try {
      _server = await HttpServer.bind('0.0.0.0', _port);
      _isRunning = true;

      _updateConnectionState(
        ConnectionStatus.connecting,
        message: 'Server started on port $_port, waiting for PC...',
      );

      _server!.transform(WebSocketTransformer()).listen(
        _handleNewClient,
        onError: (error) {
          _updateConnectionState(
            ConnectionStatus.error,
            message: 'Server error: $error',
          );
        },
        onDone: () {
          _isRunning = false;
          _updateConnectionState(ConnectionStatus.disconnected);
        },
      );

      return true;
    } catch (e) {
      _updateConnectionState(
        ConnectionStatus.error,
        message: 'Failed to start server: $e',
      );
      return false;
    }
  }

  /// 处理新的PC连接
  void _handleNewClient(WebSocket client) {
    // 只允许一个客户端连接
    if (_client != null) {
      client.close(4000, 'Another client is already connected');
      return;
    }

    _client = client;
    _clientAddress = 'PC Connected';

    _updateConnectionState(
      ConnectionStatus.connected,
      message: 'PC connected',
    );

    _startHeartbeat();

    // 监听客户端消息
    client.listen(
      (data) {
        try {
          final message = jsonDecode(data as String);
          _handleClientMessage(message);
        } catch (e) {
          // 忽略解析错误
        }
      },
      onError: (error) {
        _handleClientDisconnect('Connection error: $error');
      },
      onDone: () {
        _handleClientDisconnect('PC disconnected');
      },
      cancelOnError: false,
    );
  }

  /// 处理PC发来的消息
  void _handleClientMessage(Map<String, dynamic> message) {
    final cmd = message['cmd'];
    final type = message['type'];

    if (cmd != null) {
      // 控制命令
      _commandsReceived++;
      _commandController?.add(message);

      // 命令会通过commandStream传递给app_state处理
      // app_state负责解析val并执行USB控制
    } else if (type == 'ping') {
      // 心跳响应
      sendMessage({
        'type': 'pong',
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });
    }
  }

  /// 处理客户端断开连接
  void _handleClientDisconnect(String reason) {
    _stopHeartbeat();
    _client = null;
    _clientAddress = null;

    if (_isRunning) {
      _updateConnectionState(
        ConnectionStatus.connecting,
        message: '$reason. Waiting for PC...',
      );
    } else {
      _updateConnectionState(ConnectionStatus.disconnected);
    }
  }

  void _startHeartbeat() {
    _stopHeartbeat();
    _heartbeatTimer = Timer.periodic(_heartbeatInterval, (_) {
      if (_client != null) {
        try {
          sendMessage({
            'type': 'heartbeat',
            'timestamp': DateTime.now().millisecondsSinceEpoch,
          });
        } catch (e) {
          // 忽略心跳错误
        }
      }
    });
  }

  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  /// 发送视频帧到PC
  void sendVideoFrame(Uint8List jpegData) {
    if (_client == null || _currentStatus != ConnectionStatus.connected) {
      return;
    }

    try {
      final base64Data = base64Encode(jpegData);
      final message = {
        'type': 'video_frame',
        'data': base64Data,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      };
      _client!.add(jsonEncode(message));
      _framesSent++;
    } catch (e) {
      // 忽略发送错误
    }
  }

  /// 发送传感器数据到PC
  void sendSensorData(SensorData sensorData) {
    if (_client == null || _currentStatus != ConnectionStatus.connected) {
      return;
    }

    try {
      final message = {
        'type': 'sensor_data',
        'data': sensorData.toJson(),
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      };
      _client!.add(jsonEncode(message));
      _sensorUpdatesSent++;
    } catch (e) {
      // 忽略发送错误
    }
  }

  /// 发送通用消息到PC
  void sendMessage(Map<String, dynamic> message) {
    if (_client == null) {
      return;
    }

    try {
      _client!.add(jsonEncode(message));
    } catch (e) {
      // 忽略发送错误
    }
  }

  /// 发送状态更新到PC
  void sendStatus({
    required bool usbConnected,
    required bool cameraActive,
  }) {
    sendMessage({
      'type': 'status',
      'usb_connected': usbConnected,
      'camera_active': cameraActive,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
  }

  void _updateConnectionState(ConnectionStatus status, {String? message}) {
    _currentStatus = status;
    _connectionStateController?.add(
      ConnectionState(status: status, message: message),
    );
  }

  /// 停止服务器
  Future<void> stopServer() async {
    _isRunning = false;
    _stopHeartbeat();

    await _client?.close();
    _client = null;
    _clientAddress = null;

    await _server?.close();
    _server = null;

    _updateConnectionState(ConnectionStatus.disconnected);
  }

  /// 重置统计数据
  void resetStats() {
    _framesSent = 0;
    _sensorUpdatesSent = 0;
    _commandsReceived = 0;
  }

  Future<void> dispose() async {
    await stopServer();
    await _connectionStateController?.close();
    await _commandController?.close();
    _connectionStateController = null;
    _commandController = null;
  }
}
