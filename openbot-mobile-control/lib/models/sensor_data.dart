class SensorData {
  final AccelerometerData? accelerometer;
  final GyroscopeData? gyroscope;
  final MagnetometerData? magnetometer;
  final double? batteryLevel;
  final double? voltage;
  final DateTime timestamp;

  SensorData({
    this.accelerometer,
    this.gyroscope,
    this.magnetometer,
    this.batteryLevel,
    this.voltage,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  Map<String, dynamic> toJson() {
    return {
      'accelerometer': accelerometer?.toJson(),
      'gyroscope': gyroscope?.toJson(),
      'magnetometer': magnetometer?.toJson(),
      'battery_level': batteryLevel,
      'voltage': voltage,
      'timestamp': timestamp.toIso8601String(),
    };
  }

  factory SensorData.fromJson(Map<String, dynamic> json) {
    return SensorData(
      accelerometer: json['accelerometer'] != null
          ? AccelerometerData.fromJson(json['accelerometer'])
          : null,
      gyroscope: json['gyroscope'] != null
          ? GyroscopeData.fromJson(json['gyroscope'])
          : null,
      magnetometer: json['magnetometer'] != null
          ? MagnetometerData.fromJson(json['magnetometer'])
          : null,
      batteryLevel: json['battery_level']?.toDouble(),
      voltage: json['voltage']?.toDouble(),
      timestamp: DateTime.parse(json['timestamp']),
    );
  }
}

class AccelerometerData {
  final double x;
  final double y;
  final double z;

  AccelerometerData({
    required this.x,
    required this.y,
    required this.z,
  });

  Map<String, dynamic> toJson() {
    return {
      'x': x,
      'y': y,
      'z': z,
    };
  }

  factory AccelerometerData.fromJson(Map<String, dynamic> json) {
    return AccelerometerData(
      x: json['x'].toDouble(),
      y: json['y'].toDouble(),
      z: json['z'].toDouble(),
    );
  }
}

class GyroscopeData {
  final double x;
  final double y;
  final double z;

  GyroscopeData({
    required this.x,
    required this.y,
    required this.z,
  });

  Map<String, dynamic> toJson() {
    return {
      'x': x,
      'y': y,
      'z': z,
    };
  }

  factory GyroscopeData.fromJson(Map<String, dynamic> json) {
    return GyroscopeData(
      x: json['x'].toDouble(),
      y: json['y'].toDouble(),
      z: json['z'].toDouble(),
    );
  }
}

class MagnetometerData {
  final double x;
  final double y;
  final double z;

  MagnetometerData({
    required this.x,
    required this.y,
    required this.z,
  });

  Map<String, dynamic> toJson() {
    return {
      'x': x,
      'y': y,
      'z': z,
    };
  }

  factory MagnetometerData.fromJson(Map<String, dynamic> json) {
    return MagnetometerData(
      x: json['x'].toDouble(),
      y: json['y'].toDouble(),
      z: json['z'].toDouble(),
    );
  }
}
