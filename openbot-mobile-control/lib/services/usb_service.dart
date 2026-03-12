import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:usb_serial/usb_serial.dart';

// usb_serial has no iOS implementation — any call to its platform channel on
// iOS throws MissingPluginException and crashes the app.  Guard every method
// with this getter so UsbService becomes a no-op on iOS/macOS/web.
bool get _usbSupported =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux);

/// OpenBot USB Serial Service
///
/// Handles communication with Arduino via USB Serial
/// Implements OpenBot protocol for motor control and sensor data
class UsbService {
  UsbPort? _port;
  StreamSubscription<Uint8List>? _subscription;

  // Connection state
  bool _isConnected = false;
  String? _deviceName;

  // 行缓冲区：USB 串口数据可能多条消息共一个 chunk 到达
  String _lineBuffer = '';

  // Data streams
  final StreamController<Map<String, dynamic>> _sensorDataController =
      StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<bool> _connectionStateController =
      StreamController<bool>.broadcast();

  // Getters
  bool get isConnected => _isConnected;
  String? get deviceName => _deviceName;
  Stream<Map<String, dynamic>> get sensorDataStream =>
      _sensorDataController.stream;
  Stream<bool> get connectionStateStream => _connectionStateController.stream;

  // OpenBot features (discovered from device)
  Map<String, bool> _features = {};
  Map<String, bool> get features => _features;

  // Voltage thresholds
  double? _voltageMin;
  double? _voltageLow;
  double? _voltageMax;

  /// List available USB devices
  Future<List<UsbDevice>> listDevices() async {
    if (!_usbSupported) return [];
    return await UsbSerial.listDevices();
  }

  /// Connect to a USB device
  Future<bool> connect({UsbDevice? device}) async {
    if (!_usbSupported) return false;
    try {
      // Get list of devices if none specified
      List<UsbDevice> devices = await UsbSerial.listDevices();

      if (devices.isEmpty) {
        print('[UsbService] No USB devices found');
        return false;
      }

      // Use specified device or first available
      UsbDevice targetDevice = device ?? devices.first;
      _deviceName = targetDevice.productName ?? 'Unknown Device';

      print('[UsbService] Connecting to: $_deviceName');

      // Open connection
      _port = await targetDevice.create();
      if (_port == null) {
        print('[UsbService] Failed to create port');
        return false;
      }

      bool openResult = await _port!.open();
      if (!openResult) {
        print('[UsbService] Failed to open port');
        return false;
      }

      // Configure serial parameters (matching Arduino)
      await _port!.setDTR(true);
      await _port!.setRTS(true);
      await _port!.setPortParameters(
        115200,
        UsbPort.DATABITS_8,
        UsbPort.STOPBITS_1,
        UsbPort.PARITY_NONE,
      );

      // Set up data reception
      _subscription = _port!.inputStream!.listen(_onDataReceived);

      _isConnected = true;
      _connectionStateController.add(true);

      print('[UsbService] Connected successfully');

      // Request feature list from OpenBot
      await Future.delayed(const Duration(milliseconds: 500));
      await requestFeatures();

      return true;
    } catch (e) {
      print('[UsbService] Connection error: $e');
      _isConnected = false;
      _connectionStateController.add(false);
      return false;
    }
  }

  /// Disconnect from USB device
  Future<void> disconnect() async {
    _subscription?.cancel();
    _subscription = null;

    await _port?.close();
    _port = null;

    _isConnected = false;
    _deviceName = null;
    _lineBuffer = '';
    _connectionStateController.add(false);

    print('[UsbService] Disconnected');
  }

  /// Handle incoming data from Arduino
  /// 正确处理多行拼接和断帧：累积到缓冲区，按 \n 切割后逐行解析
  void _onDataReceived(Uint8List data) {
    try {
      _lineBuffer += utf8.decode(data, allowMalformed: true);
      final lines = _lineBuffer.split('\n');
      // 最后一个元素可能是不完整的行，留在缓冲区
      _lineBuffer = lines.last;
      for (int i = 0; i < lines.length - 1; i++) {
        final line = lines[i].replaceAll('\r', '').trim();
        if (line.isNotEmpty) _parseMessage(line);
      }
    } catch (e) {
      print('[UsbService] Parse error: $e');
      _lineBuffer = ''; // 解析失败时清空缓冲区避免污染
    }
  }

  /// Parse OpenBot protocol message
  void _parseMessage(String message) {
    if (message.isEmpty) return;

    String header = message[0];
    String body = message.length > 1 ? message.substring(1) : '';

    switch (header) {
      case 'f': // Feature list
        _parseFeatures(body);
        break;

      case 'v': // Voltage reading
        if (body.startsWith('min:')) {
          _voltageMin = double.tryParse(body.substring(4));
        } else if (body.startsWith('low:')) {
          _voltageLow = double.tryParse(body.substring(4));
        } else if (body.startsWith('max:')) {
          _voltageMax = double.tryParse(body.substring(4));
        } else {
          double? voltage = double.tryParse(body);
          if (voltage != null) {
            _sensorDataController.add({
              'type': 'voltage',
              'value': voltage,
              'min': _voltageMin,
              'low': _voltageLow,
              'max': _voltageMax,
            });
          }
        }
        break;

      case 'w': // Wheel odometry
        List<String> parts = body.split(',');
        if (parts.length == 2) {
          double? leftRpm = double.tryParse(parts[0]);
          double? rightRpm = double.tryParse(parts[1]);
          if (leftRpm != null && rightRpm != null) {
            _sensorDataController.add({
              'type': 'wheel',
              'left_rpm': leftRpm,
              'right_rpm': rightRpm,
            });
          }
        }
        break;

      case 's': // Sonar distance
        double? distance = double.tryParse(body);
        if (distance != null) {
          _sensorDataController.add({
            'type': 'sonar',
            'distance': distance,
          });
        }
        break;

      case 'b': // Bumper event
        _sensorDataController.add({
          'type': 'bumper',
          'id': body,
        });
        break;

      case 'r': // Ready signal
        print('[UsbService] Arduino ready');
        break;

      default:
        print('[UsbService] Unknown message: $message');
    }
  }

  /// Parse feature list from OpenBot
  void _parseFeatures(String body) {
    // Format: "RTR_TT:v:i:s:b:wf:wb:lf:lb:ls:"
    List<String> parts = body.split(':');
    if (parts.isEmpty) return;

    String robotType = parts[0];
    print('[UsbService] Robot type: $robotType');

    _features = {
      'voltage': parts.contains('v'),
      'indicators': parts.contains('i'),
      'sonar': parts.contains('s'),
      'bumper': parts.contains('b'),
      'wheel_front': parts.contains('wf'),
      'wheel_back': parts.contains('wb'),
      'wheel_middle': parts.contains('wm'),
      'leds_front': parts.contains('lf'),
      'leds_back': parts.contains('lb'),
      'leds_status': parts.contains('ls'),
    };

    _sensorDataController.add({
      'type': 'features',
      'robot_type': robotType,
      'features': _features,
    });

    print('[UsbService] Features: $_features');
  }

  /// Send raw command to Arduino
  Future<void> sendRaw(String command) async {
    if (!_usbSupported || !_isConnected || _port == null) return;

    try {
      await _port!.write(Uint8List.fromList(utf8.encode('$command\n')));
    } catch (e) {
      print('[UsbService] Send error: $e');
    }
  }

  // ==================== Control Commands ====================

  /// Send motor control command
  /// left/right: -255 to 255
  Future<void> sendControl(int left, int right) async {
    await sendRaw('c$left,$right');
  }

  /// Send motor control (normalized -1.0 to 1.0)
  Future<void> sendControlNormalized(double left, double right) async {
    int leftInt = (left.clamp(-1.0, 1.0) * 255).round();
    int rightInt = (right.clamp(-1.0, 1.0) * 255).round();
    await sendControl(leftInt, rightInt);
  }

  /// Stop motors
  Future<void> stop() async {
    await sendControl(0, 0);
  }

  /// Set indicator lights
  Future<void> setIndicators(int left, int right) async {
    await sendRaw('i$left,$right');
  }

  /// Set LED brightness
  Future<void> setLights(int front, int back) async {
    await sendRaw('l$front,$back');
  }

  /// Set heartbeat interval (ms)
  Future<void> setHeartbeat(int intervalMs) async {
    await sendRaw('h$intervalMs');
  }

  /// Set sonar interval (ms)
  Future<void> setSonarInterval(int intervalMs) async {
    await sendRaw('s$intervalMs');
  }

  /// Set voltage interval (ms)
  Future<void> setVoltageInterval(int intervalMs) async {
    await sendRaw('v$intervalMs');
  }

  /// Set wheel odometry interval (ms)
  Future<void> setWheelInterval(int intervalMs) async {
    await sendRaw('w$intervalMs');
  }

  /// Request feature list
  Future<void> requestFeatures() async {
    await sendRaw('f');
  }

  /// Set notification LED state
  Future<void> setNotificationLed(String led, int state) async {
    // led: 'y' (yellow), 'g' (green), 'b' (blue)
    await sendRaw('n$led,$state');
  }

  /// Dispose resources
  void dispose() {
    _subscription?.cancel();
    _subscription = null;
    _port?.close();
    _port = null;
    _isConnected = false;
    _deviceName = null;
    _sensorDataController.close();
    _connectionStateController.close();
  }
}
