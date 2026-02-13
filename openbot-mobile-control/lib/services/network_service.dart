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

  // UDP 广播相关属性
  RawDatagramSocket? _udpSocket;
  Timer? _broadcastTimer;
  static const int discoveryPort = 12345;

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
    return await _getLocalIpAddress();
  }

  /// 获取本机IP地址（内部方法）
  Future<String?> _getLocalIpAddress() async {
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

      // 启动 UDP 广播
      print('[NetworkService] Starting UDP broadcast for auto-discovery...');
      await _startUdpBroadcast();

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
    print('[NetworkService] New client connecting...');

    // 只允许一个客户端连接
    if (_client != null) {
      print('[NetworkService] Rejecting: another client already connected');
      client.close(4000, 'Another client is already connected');
      return;
    }

    _client = client;
    _clientAddress = 'PC Connected';

    print('[NetworkService] Client connected! Updating state...');

    _updateConnectionState(
      ConnectionStatus.connected,
      message: 'PC connected',
    );

    _startHeartbeat();
    print('[NetworkService] Heartbeat started');

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

    // 停止 UDP 广播
    print('[NetworkService] Stopping UDP broadcast...');
    _stopUdpBroadcast();

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

  /// 启动 UDP 广播，用于自动发现
  /// 每 2 秒向局域网广播手机的 IP 和端口
  Future<void> _startUdpBroadcast() async {
    try {
      // 创建 UDP socket，绑定到任意可用端口
      _udpSocket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      _udpSocket!.broadcastEnabled = true;

      // 获取本地 IP 地址
      final localIp = await _getLocalIpAddress();
      if (localIp == null) {
        print('[NetworkService][UDP] Cannot get local IP, broadcast disabled');
        return;
      }

      print('[NetworkService][UDP] Starting UDP broadcast');
      print('[NetworkService][UDP] Broadcasting on port $discoveryPort');
      print('[NetworkService][UDP] Local IP: $localIp, WebSocket port: $_port');

      // 每 2 秒广播一次
      _broadcastTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
        // 构造发现消息（JSON 格式）
        final message = jsonEncode({
          'type': 'discovery',      // 消息类型
          'name': 'OpenBot',        // 设备名称
          'ip': localIp,            // 手机 IP
          'port': _port,            // WebSocket 端口（8765）
        });

        try {
          // 发送 UDP 广播到 255.255.255.255:12345
          final bytes = Uint8List.fromList(utf8.encode(message));
          _udpSocket?.send(
            bytes,
            InternetAddress('255.255.255.255'),  // 广播地址
            discoveryPort,                        // 目标端口 12345
          );
          
          print('[NetworkService][UDP] Broadcast sent: $message');
        } catch (e) {
          print('[NetworkService][UDP] Broadcast send error: $e');
        }
      });

      print('[NetworkService][UDP] UDP broadcast started successfully');
    } catch (e) {
      print('[NetworkService][UDP] Failed to start UDP broadcast: $e');
    }
  }

  /// 停止 UDP 广播
  void _stopUdpBroadcast() {
    _broadcastTimer?.cancel();
    _broadcastTimer = null;
    
    _udpSocket?.close();
    _udpSocket = null;
    
    print('[NetworkService][UDP] UDP broadcast stopped');
  }

  Future<void> dispose() async {
    await stopServer();
    await _connectionStateController?.close();
    await _commandController?.close();
    _connectionStateController = null;
    _commandController = null;
  }
}
