import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../models/sensor_data.dart';
import '../models/connection_state.dart';

class NetworkService {
  WebSocketChannel? _channel;
  StreamController<ConnectionState>? _connectionStateController;
  Timer? _heartbeatTimer;
  Timer? _reconnectTimer;

  String? _serverUrl;
  bool _isConnecting = false;
  bool _shouldReconnect = true;
  int _reconnectAttempts = 0;
  static const int _maxReconnectAttempts = 5;
  static const Duration _reconnectDelay = Duration(seconds: 3);
  static const Duration _heartbeatInterval = Duration(seconds: 5);

  Stream<ConnectionState>? get connectionStateStream =>
      _connectionStateController?.stream;

  ConnectionStatus _currentStatus = ConnectionStatus.disconnected;

  Future<void> initialize() async {
    _connectionStateController = StreamController<ConnectionState>.broadcast();
    _updateConnectionState(ConnectionStatus.disconnected);
  }

  Future<void> connect(String host, int port) async {
    if (_isConnecting) return;

    _serverUrl = 'ws://$host:$port';
    _shouldReconnect = true;
    _reconnectAttempts = 0;

    await _attemptConnection();
  }

  Future<void> _attemptConnection() async {
    if (_serverUrl == null || _isConnecting) return;

    _isConnecting = true;
    _updateConnectionState(
      _reconnectAttempts > 0
          ? ConnectionStatus.reconnecting
          : ConnectionStatus.connecting,
      message: _reconnectAttempts > 0
          ? 'Reconnect attempt ${_reconnectAttempts + 1}/$_maxReconnectAttempts'
          : 'Connecting to server...',
    );

    try {
      _channel = WebSocketChannel.connect(Uri.parse(_serverUrl!));

      await _channel!.ready;

      _isConnecting = false;
      _reconnectAttempts = 0;
      _updateConnectionState(
        ConnectionStatus.connected,
        message: 'Connected successfully',
      );

      _startHeartbeat();
      _listenToChannel();
    } catch (e) {
      _isConnecting = false;
      _handleConnectionError('Connection failed: $e');
    }
  }

  void _listenToChannel() {
    _channel?.stream.listen(
      (data) {
        // Handle incoming messages from server
        try {
          final message = jsonDecode(data as String);
          _handleServerMessage(message);
        } catch (e) {
          // Ignore parsing errors
        }
      },
      onError: (error) {
        _handleConnectionError('Connection error: $error');
      },
      onDone: () {
        _handleConnectionError('Connection closed');
      },
      cancelOnError: false,
    );
  }

  void _handleServerMessage(Map<String, dynamic> message) {
    // Handle different message types from server
    final type = message['type'];
    switch (type) {
      case 'pong':
        // Heartbeat response
        break;
      case 'command':
        // Handle robot commands
        break;
      default:
        break;
    }
  }

  void _handleConnectionError(String message) {
    _stopHeartbeat();

    if (_shouldReconnect && _reconnectAttempts < _maxReconnectAttempts) {
      _reconnectAttempts++;
      _updateConnectionState(
        ConnectionStatus.reconnecting,
        message: message,
      );

      _reconnectTimer?.cancel();
      _reconnectTimer = Timer(_reconnectDelay, _attemptConnection);
    } else {
      _updateConnectionState(
        ConnectionStatus.error,
        message: message,
      );
    }
  }

  void _startHeartbeat() {
    _stopHeartbeat();
    _heartbeatTimer = Timer.periodic(_heartbeatInterval, (_) {
      if (_channel != null) {
        try {
          sendMessage({'type': 'ping', 'timestamp': DateTime.now().millisecondsSinceEpoch});
        } catch (e) {
          _handleConnectionError('Heartbeat failed');
        }
      }
    });
  }

  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  void sendVideoFrame(Uint8List jpegData) {
    if (_channel == null || _currentStatus != ConnectionStatus.connected) {
      return;
    }

    try {
      final base64Data = base64Encode(jpegData);
      final message = {
        'type': 'video_frame',
        'data': base64Data,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      };
      _channel!.sink.add(jsonEncode(message));
    } catch (e) {
      // Handle send error
    }
  }

  void sendSensorData(SensorData sensorData) {
    if (_channel == null || _currentStatus != ConnectionStatus.connected) {
      return;
    }

    try {
      final message = {
        'type': 'sensor_data',
        'data': sensorData.toJson(),
      };
      _channel!.sink.add(jsonEncode(message));
    } catch (e) {
      // Handle send error
    }
  }

  void sendMessage(Map<String, dynamic> message) {
    if (_channel == null || _currentStatus != ConnectionStatus.connected) {
      return;
    }

    try {
      _channel!.sink.add(jsonEncode(message));
    } catch (e) {
      // Handle send error
    }
  }

  void _updateConnectionState(ConnectionStatus status, {String? message}) {
    _currentStatus = status;
    _connectionStateController?.add(
      ConnectionState(status: status, message: message),
    );
  }

  Future<void> disconnect() async {
    _shouldReconnect = false;
    _reconnectTimer?.cancel();
    _stopHeartbeat();

    await _channel?.sink.close();
    _channel = null;

    _updateConnectionState(ConnectionStatus.disconnected);
  }

  Future<void> dispose() async {
    await disconnect();
    await _connectionStateController?.close();
    _connectionStateController = null;
  }
}
