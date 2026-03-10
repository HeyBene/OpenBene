import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:battery_plus/battery_plus.dart';
import '../models/sensor_data.dart';

class SensorService {
  StreamSubscription<AccelerometerEvent>? _accelerometerSubscription;
  StreamSubscription<GyroscopeEvent>? _gyroscopeSubscription;
  StreamSubscription<MagnetometerEvent>? _magnetometerSubscription;

  final Battery _battery = Battery();

  AccelerometerData? _lastAccelerometer;
  GyroscopeData? _lastGyroscope;
  MagnetometerData? _lastMagnetometer;
  double? _lastBatteryLevel;
  double? _lastVoltage;

  Timer? _sensorTimer;
  StreamController<SensorData>? _sensorDataController;

  Stream<SensorData>? get sensorDataStream => _sensorDataController?.stream;

  Future<void> initialize() async {
    _sensorDataController = StreamController<SensorData>.broadcast();

    // battery_plus can throw PlatformException on first call on some devices.
    try {
      _lastBatteryLevel = (await _battery.batteryLevel) / 100.0;
      _battery.onBatteryStateChanged.listen((BatteryState state) async {
        try {
          _lastBatteryLevel = (await _battery.batteryLevel) / 100.0;
        } catch (_) {}
      });
    } catch (e) {
      debugPrint('[SensorService] Battery init failed: $e');
      _lastBatteryLevel = 0.0;
    }
  }

  void startListening({int intervalMs = 100}) {
    // Listen to accelerometer
    _accelerometerSubscription = accelerometerEventStream().listen(
      (AccelerometerEvent event) {
        _lastAccelerometer = AccelerometerData(
          x: event.x,
          y: event.y,
          z: event.z,
        );
      },
    );

    // Listen to gyroscope
    _gyroscopeSubscription = gyroscopeEventStream().listen(
      (GyroscopeEvent event) {
        _lastGyroscope = GyroscopeData(
          x: event.x,
          y: event.y,
          z: event.z,
        );
      },
    );

    // Listen to magnetometer
    _magnetometerSubscription = magnetometerEventStream().listen(
      (MagnetometerEvent event) {
        _lastMagnetometer = MagnetometerData(
          x: event.x,
          y: event.y,
          z: event.z,
        );
      },
    );

    // Start periodic sensor data emission
    _sensorTimer = Timer.periodic(
      Duration(milliseconds: intervalMs),
      (_) => _emitSensorData(),
    );
  }

  void _emitSensorData() {
    final sensorData = SensorData(
      accelerometer: _lastAccelerometer,
      gyroscope: _lastGyroscope,
      magnetometer: _lastMagnetometer,
      batteryLevel: _lastBatteryLevel,
      voltage: _lastVoltage,
    );

    _sensorDataController?.add(sensorData);
  }

  SensorData getCurrentData() {
    return SensorData(
      accelerometer: _lastAccelerometer,
      gyroscope: _lastGyroscope,
      magnetometer: _lastMagnetometer,
      batteryLevel: _lastBatteryLevel,
      voltage: _lastVoltage,
    );
  }

  void updateVoltage(double voltage) {
    _lastVoltage = voltage;
  }

  Future<void> stopListening() async {
    await _accelerometerSubscription?.cancel();
    await _gyroscopeSubscription?.cancel();
    await _magnetometerSubscription?.cancel();
    _sensorTimer?.cancel();

    _accelerometerSubscription = null;
    _gyroscopeSubscription = null;
    _magnetometerSubscription = null;
    _sensorTimer = null;
  }

  Future<void> dispose() async {
    await stopListening();
    await _sensorDataController?.close();
    _sensorDataController = null;
  }
}
