import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/sensor_data.dart';
import '../models/connection_state.dart';
import '../services/camera_service.dart';
import '../services/sensor_service.dart';
import '../services/network_service.dart';
import '../services/permission_service.dart';

class AppState extends ChangeNotifier {
  final CameraService _cameraService = CameraService();
  final SensorService _sensorService = SensorService();
  final NetworkService _networkService = NetworkService();
  final PermissionService _permissionService = PermissionService();

  ConnectionState _connectionState = ConnectionState(
    status: ConnectionStatus.disconnected,
  );
  SensorData? _latestSensorData;
  Uint8List? _latestFrame;

  bool _isStreaming = false;
  bool _cameraInitialized = false;
  int _framesSent = 0;
  int _sensorUpdatesSent = 0;

  StreamSubscription? _sensorDataSubscription;
  StreamSubscription? _connectionStateSubscription;

  // Getters
  ConnectionState get connectionState => _connectionState;
  SensorData? get latestSensorData => _latestSensorData;
  Uint8List? get latestFrame => _latestFrame;
  bool get isStreaming => _isStreaming;
  bool get cameraInitialized => _cameraInitialized;
  int get framesSent => _framesSent;
  int get sensorUpdatesSent => _sensorUpdatesSent;
  CameraService get cameraService => _cameraService;

  Future<void> initialize() async {
    await _sensorService.initialize();
    await _networkService.initialize();

    _connectionStateSubscription =
        _networkService.connectionStateStream?.listen((state) {
      _connectionState = state;
      notifyListeners();
    });
  }

  Future<Map<String, bool>> requestPermissions() async {
    return await _permissionService.requestAllPermissions();
  }

  Future<bool> initializeCamera() async {
    try {
      await _cameraService.initialize();
      _cameraInitialized = true;
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('Failed to initialize camera: $e');
      return false;
    }
  }

  Future<void> connect(String host, int port) async {
    await _networkService.connect(host, port);
  }

  Future<void> startStreaming() async {
    if (_isStreaming) return;

    try {
      // Start camera streaming
      await _cameraService.startStreaming(
        onFrame: (frame) {
          _latestFrame = frame;
          _networkService.sendVideoFrame(frame);
          _framesSent++;
          // Don't notify listeners for every frame - too expensive
        },
        quality: 75,
        targetWidth: 640,
      );

      // Start sensor listening with reduced update rate for UI
      // Send to network at 100ms, but only update UI every 300ms
      _sensorService.startListening(intervalMs: 100);

      int uiUpdateCounter = 0;
      _sensorDataSubscription =
          _sensorService.sensorDataStream?.listen((sensorData) {
        _latestSensorData = sensorData;
        _networkService.sendSensorData(sensorData);
        _sensorUpdatesSent++;

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

  Future<void> disconnect() async {
    await stopStreaming();
    await _networkService.disconnect();
  }

  @override
  void dispose() {
    _sensorDataSubscription?.cancel();
    _connectionStateSubscription?.cancel();
    _cameraService.dispose();
    _sensorService.dispose();
    _networkService.dispose();
    super.dispose();
  }
}
