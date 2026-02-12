import 'dart:async';
import 'package:flutter/services.dart';
import '../models/lidar_data.dart';

/// LiDAR service for iOS ARKit depth sensing
///
/// Provides access to LiDAR depth data from iPhone 12 Pro and newer devices
class LiDARService {
  static const MethodChannel _channel = MethodChannel('openbene/lidar');
  static const EventChannel _eventChannel = EventChannel('openbene/lidar_stream');

  StreamController<LiDARData>? _lidarDataController;
  StreamSubscription? _eventSubscription;
  bool _isInitialized = false;
  bool _isCapturing = false;

  /// Stream of LiDAR data
  Stream<LiDARData>? get lidarDataStream => _lidarDataController?.stream;

  /// Whether the service is initialized
  bool get isInitialized => _isInitialized;

  /// Whether LiDAR is currently capturing
  bool get isCapturing => _isCapturing;

  /// Initialize the LiDAR service
  Future<bool> initialize() async {
    if (_isInitialized) return true;

    try {
      // Check if LiDAR is available on this device
      final available = await _channel.invokeMethod('isLiDARAvailable');
      if (!available) {
        print('[LiDARService] LiDAR not available on this device');
        return false;
      }

      // Only create stream controller if LiDAR is available
      _lidarDataController = StreamController<LiDARData>.broadcast();
      
      _isInitialized = true;
      print('[LiDARService] Initialized successfully');
      return true;
    } catch (e) {
      print('[LiDARService] Initialization error: $e');
      return false;
    }
  }

  /// Start capturing LiDAR depth data
  Future<bool> startCapture() async {
    if (!_isInitialized) {
      print('[LiDARService] Not initialized');
      return false;
    }

    if (_isCapturing) return true;

    try {
      // Start the ARSession
      await _channel.invokeMethod('startCapture');

      // Listen to depth data stream
      _eventSubscription = _eventChannel.receiveBroadcastStream().listen(
        (data) {
          try {
            final lidarData = LiDARData.fromJson(Map<String, dynamic>.from(data));
            _lidarDataController?.add(lidarData);
          } catch (e) {
            print('[LiDARService] Error parsing LiDAR data: $e');
          }
        },
        onError: (error) {
          print('[LiDARService] Stream error: $error');
        },
      );

      _isCapturing = true;
      print('[LiDARService] Started capturing');
      return true;
    } catch (e) {
      print('[LiDARService] Start capture error: $e');
      return false;
    }
  }

  /// Stop capturing LiDAR depth data
  Future<void> stopCapture() async {
    if (!_isCapturing) return;

    try {
      await _channel.invokeMethod('stopCapture');
      await _eventSubscription?.cancel();
      _eventSubscription = null;
      _isCapturing = false;
      print('[LiDARService] Stopped capturing');
    } catch (e) {
      print('[LiDARService] Stop capture error: $e');
    }
  }

  /// Clean up resources
  Future<void> dispose() async {
    await stopCapture();
    await _lidarDataController?.close();
    _lidarDataController = null;
    _isInitialized = false;
  }
}
