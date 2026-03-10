import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// UDP广播发现服务
///
/// 定期发送UDP广播消息，让PC可以自动发现手机
class DiscoveryService {
  RawDatagramSocket? _socket;
  Timer? _broadcastTimer;
  bool _isRunning = false;

  static const int broadcastPort = 12345;
  static const Duration _broadcastInterval = Duration(seconds: 2);

  String _deviceName = 'OpenBene Robot';
  int _wsPort = 8765;

  bool get isRunning => _isRunning;

  /// 启动广播服务
  Future<bool> startBroadcast({
    required String deviceName,
    required int wsPort,
  }) async {
    if (_isRunning) return true;

    _deviceName = deviceName;
    _wsPort = wsPort;

    try {
      // 创建UDP socket
      _socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      _socket!.broadcastEnabled = true;
      _isRunning = true;

      // 立即发送一次
      await _sendBroadcast();

      // 定期发送广播
      _broadcastTimer = Timer.periodic(_broadcastInterval, (_) {
        _sendBroadcast();
      });

      return true;
    } catch (e) {
      _isRunning = false;
      return false;
    }
  }

  /// 发送广播消息
  Future<void> _sendBroadcast() async {
    if (_socket == null) return;

    try {
      final localIp = await _getLocalIpAddress();
      if (localIp == null) return;

      final message = jsonEncode({
        'type': 'discovery',
        'name': _deviceName,
        'ip': localIp,
        'port': _wsPort,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });

      final data = utf8.encode(message);

      // iOS blocks packets to 255.255.255.255 (sandbox restriction).
      // Only use the subnet-specific broadcast address which works on both
      // iOS and Android (e.g. 192.168.1.255, 192.168.43.255 for hotspot).
      final parts = localIp.split('.');
      if (parts.length == 4) {
        final subnetBroadcast = '${parts[0]}.${parts[1]}.${parts[2]}.255';
        _socket!.send(
          data,
          InternetAddress(subnetBroadcast),
          broadcastPort,
        );
      }
    } catch (e) {
      // 忽略发送错误
    }
  }

  /// 获取本机IP地址
  Future<String?> _getLocalIpAddress() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLinkLocal: false,
      );
      for (var interface in interfaces) {
        for (var addr in interface.addresses) {
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

  /// 停止广播服务
  void stopBroadcast() {
    _broadcastTimer?.cancel();
    _broadcastTimer = null;
    _socket?.close();
    _socket = null;
    _isRunning = false;
  }

  void dispose() {
    stopBroadcast();
  }
}
