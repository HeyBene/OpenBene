import 'dart:async';
import 'dart:convert';
import 'package:flutter_blue_plus/flutter_blue_plus.dart' as fbp;

/// BLE 蓝牙服务
///
/// 支持两种 BLE 模块：
///   1. OpenBot ESP32 原生 BLE（自定义 UUID）
///   2. HM-10 / HC-08 串口透传模块（FFE0/FFE1）
/// 命令协议与 UsbService 保持一致（c/i/l/h...）。
class BluetoothService {
  // OpenBot ESP32 firmware UUIDs
  static const String _openbotServiceUuid =
      '61653dc3-4021-4d1e-ba83-8b4eec61d613';
  static const String _openbotRxUuid =
      '06386c14-86ea-4d71-811c-48f97c58f8c9'; // Write to robot
  static const String _openbotTxUuid =
      '9bf1103b-834c-47cf-b149-c9e4bcf778a7'; // Notify from robot

  // HM-10 / HC-08 BLE module UUIDs (fallback)
  static const String _hm10ServiceSuffix = 'ffe0';
  static const String _hm10CharSuffix = 'ffe1';

  fbp.BluetoothDevice? _device;
  fbp.BluetoothCharacteristic? _characteristic;
  fbp.BluetoothCharacteristic? _notifyCharacteristic;
  StreamSubscription<fbp.BluetoothConnectionState>? _connectionSubscription;
  StreamSubscription<List<int>>? _notifySubscription;

  final StreamController<bool> _connectionController =
      StreamController<bool>.broadcast();
  final StreamController<String> _messageController =
      StreamController<String>.broadcast();

  bool _isConnected = false;

  bool get isConnected => _isConnected;
  String? get connectedDeviceName {
    final name = _device?.platformName;
    if (name == null || name.isEmpty) {
      return _device?.remoteId.str;
    }
    return name;
  }

  Stream<bool> get connectionStream => _connectionController.stream;
  Stream<String> get messageStream => _messageController.stream;

  /// 扫描附近 BLE 设备
  Stream<List<fbp.ScanResult>> scanDevices({
    Duration timeout = const Duration(seconds: 6),
  }) {
    unawaited(fbp.FlutterBluePlus.startScan(timeout: timeout));
    return fbp.FlutterBluePlus.scanResults;
  }

  Future<void> stopScan() async {
    await fbp.FlutterBluePlus.stopScan();
  }

  /// 连接到指定设备并查找串口透传特征
  Future<bool> connect(fbp.BluetoothDevice device) async {
    try {
      await disconnect();

      _device = device;
      await stopScan();
      await device.connect(timeout: const Duration(seconds: 10));

      final services = await device.discoverServices();
      _characteristic = _findTargetCharacteristic(services);
      _notifyCharacteristic = _findNotifyCharacteristic(services);
      if (_characteristic == null) {
        await device.disconnect();
        _device = null;
        return false;
      }

      await _setupNotifications();

      _connectionSubscription =
          device.connectionState.listen(_handleConnectionState);

      _isConnected = true;
      _connectionController.add(true);
      return true;
    } catch (_) {
      _isConnected = false;
      _connectionController.add(false);
      return false;
    }
  }

  fbp.BluetoothCharacteristic? _findTargetCharacteristic(
    List<fbp.BluetoothService> services,
  ) {
    // 1. 优先匹配 OpenBot ESP32 自定义 UUID
    for (final service in services) {
      final serviceId = service.uuid.str.toLowerCase();
      if (serviceId == _openbotServiceUuid) {
        for (final c in service.characteristics) {
          final cId = c.uuid.str.toLowerCase();
          if (cId == _openbotRxUuid) {
            return c; // 写入用 RX 特征
          }
        }
      }
    }

    // 2. 匹配 HM-10 / HC-08 透传模块 (FFE0/FFE1)
    for (final service in services) {
      final serviceId = service.uuid.str.toLowerCase();
      if (!serviceId.contains(_hm10ServiceSuffix)) continue;
      for (final c in service.characteristics) {
        final cId = c.uuid.str.toLowerCase();
        if (cId.contains(_hm10CharSuffix)) {
          return c;
        }
      }
    }

    // 3. 兜底：找任何可写特征
    for (final service in services) {
      for (final c in service.characteristics) {
        if (c.properties.write || c.properties.writeWithoutResponse) {
          return c;
        }
      }
    }

    return null;
  }

  fbp.BluetoothCharacteristic? _findNotifyCharacteristic(
    List<fbp.BluetoothService> services,
  ) {
    // 1. OpenBot TX notify 特征
    for (final service in services) {
      final serviceId = service.uuid.str.toLowerCase();
      if (serviceId != _openbotServiceUuid) continue;

      for (final c in service.characteristics) {
        final cId = c.uuid.str.toLowerCase();
        if (cId == _openbotTxUuid && (c.properties.notify || c.properties.indicate)) {
          return c;
        }
      }
    }

    // 2. HM-10 常见透传特征可通知
    for (final service in services) {
      final serviceId = service.uuid.str.toLowerCase();
      if (!serviceId.contains(_hm10ServiceSuffix)) continue;

      for (final c in service.characteristics) {
        final cId = c.uuid.str.toLowerCase();
        if (cId.contains(_hm10CharSuffix) && (c.properties.notify || c.properties.indicate)) {
          return c;
        }
      }
    }

    // 3. 兜底：任意可通知特征
    for (final service in services) {
      for (final c in service.characteristics) {
        if (c.properties.notify || c.properties.indicate) {
          return c;
        }
      }
    }

    return null;
  }

  Future<void> _setupNotifications() async {
    await _notifySubscription?.cancel();
    _notifySubscription = null;

    final notifyChar = _notifyCharacteristic;
    if (notifyChar == null) return;
    if (!(notifyChar.properties.notify || notifyChar.properties.indicate)) return;

    await notifyChar.setNotifyValue(true);
    _notifySubscription = notifyChar.lastValueStream.listen(_handleIncomingBytes);
  }

  void _handleIncomingBytes(List<int> bytes) {
    if (bytes.isEmpty) return;

    final text = utf8
        .decode(bytes, allowMalformed: true)
        .replaceAll('\u0000', '')
        .trim();
    if (text.isEmpty) return;

    _messageController.add(text);
  }

  void _handleConnectionState(fbp.BluetoothConnectionState state) {
    final connected = state == fbp.BluetoothConnectionState.connected;
    _isConnected = connected;
    _connectionController.add(connected);

    if (!connected) {
      _characteristic = null;
      _notifyCharacteristic = null;
      _device = null;
      unawaited(_notifySubscription?.cancel());
      _notifySubscription = null;
    }
  }

  /// 发送原始命令（自动附加换行，20 字节分包）
  Future<void> sendRaw(String command) async {
    if (_characteristic == null || !_isConnected) return;

    final message = '$command\n';
    final bytes = utf8.encode(message);
    final useWithoutResponse = _characteristic!.properties.writeWithoutResponse;

    for (int index = 0; index < bytes.length; index += 20) {
      final end = (index + 20 < bytes.length) ? index + 20 : bytes.length;
      final chunk = bytes.sublist(index, end);
      await _characteristic!.write(
        chunk,
        withoutResponse: useWithoutResponse,
      );
    }
  }

  Future<void> sendControl(int left, int right) async {
    await sendRaw('c$left,$right');
  }

  Future<void> sendControlNormalized(double left, double right) async {
    final leftInt = (left.clamp(-1.0, 1.0) * 255).round();
    final rightInt = (right.clamp(-1.0, 1.0) * 255).round();
    await sendControl(leftInt, rightInt);
  }

  Future<void> stop() async {
    await sendControl(0, 0);
  }

  Future<void> setIndicators(int left, int right) async {
    await sendRaw('i$left,$right');
  }

  Future<void> setLights(int front, int back) async {
    await sendRaw('l$front,$back');
  }

  Future<void> setHeartbeat(int intervalMs) async {
    await sendRaw('h$intervalMs');
  }

  Future<void> setSonarInterval(int intervalMs) async {
    await sendRaw('s$intervalMs');
  }

  Future<void> setVoltageInterval(int intervalMs) async {
    await sendRaw('v$intervalMs');
  }

  Future<void> setWheelInterval(int intervalMs) async {
    await sendRaw('w$intervalMs');
  }

  Future<void> requestFeatures() async {
    await sendRaw('f');
  }

  /// 连接测试：发送 feature 请求并等待返回 f... 包
  Future<String?> testConnection({
    Duration timeout = const Duration(seconds: 3),
  }) async {
    if (!_isConnected || _characteristic == null) return null;

    await sendRaw('f');
    try {
      final response = await messageStream
          .firstWhere((msg) => msg.startsWith('f'))
          .timeout(timeout);
      return response;
    } catch (_) {
      return null;
    }
  }

  Future<void> disconnect() async {
    await _connectionSubscription?.cancel();
    _connectionSubscription = null;
    await _notifySubscription?.cancel();
    _notifySubscription = null;

    try {
      await _device?.disconnect();
    } catch (_) {}

    _device = null;
    _characteristic = null;
    _notifyCharacteristic = null;
    _isConnected = false;
    _connectionController.add(false);
  }

  Future<void> dispose() async {
    await disconnect();
    await _connectionController.close();
    await _messageController.close();
  }
}
