import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';

/// Capture status model
class CaptureStatus {
  final bool isCapturing;
  final int frameCount;
  final String trackingState;
  final bool lidarSupported;
  final String? datasetName;
  final String? error;

  CaptureStatus({
    required this.isCapturing,
    required this.frameCount,
    required this.trackingState,
    required this.lidarSupported,
    this.datasetName,
    this.error,
  });

  factory CaptureStatus.fromJson(Map<String, dynamic> json) {
    return CaptureStatus(
      isCapturing: json['is_capturing'] ?? false,
      frameCount: json['frame_count'] ?? 0,
      trackingState: json['tracking_state'] ?? 'Unknown',
      lidarSupported: json['lidar_supported'] ?? false,
      datasetName: json['dataset_name'],
      error: json['error'],
    );
  }

  Map<String, dynamic> toJson() => {
    return {
      'is_capturing': isCapturing,
      'frame_count': frameCount,
      'tracking_state': trackingState,
      'lidar_supported': lidarSupported,
      'dataset_name': datasetName,
      'error': error,
    };
  }
}

/// Dataset info model
class DatasetInfo {
  final String id;
  final String name;
  final DateTime createdAt;
  final int frameCount;
  final bool hasDepth;
  final String path;
  final int sizeBytes;

  DatasetInfo({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.frameCount,
    required this.hasDepth,
    required this.path,
    required this.sizeBytes,
  });

  factory DatasetInfo.fromJson(Map<String, dynamic> json) {
    return DatasetInfo(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      createdAt: json['created_at'] != null 
          ? DateTime.fromMillisecondsSinceEpoch(json['created_at'])
          : DateTime.now(),
      frameCount: json['frame_count'] ?? 0,
      hasDepth: json['has_depth'] ?? false,
      path: json['path'] ?? '',
      sizeBytes: json['size_bytes'] ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
    return {
      'id': id,
      'name': name,
      'created_at': createdAt.millisecondsSinceEpoch,
      'frame_count': frameCount,
      'has_depth': hasDepth,
      'path': path,
      'size_bytes': sizeBytes,
    };
  }
}

/// Flutter service for LiDAR capture functionality
/// Provides high-level API to communicate with iOS native code
class LidarCaptureFlutterService extends ChangeNotifier {
  static const MethodChannel _channel = MethodChannel('openbene/lidar_capture');
  static const EventChannel _eventChannel = EventChannel('openbene/lidar_capture_events');

  StreamSubscription? _statusSubscription;
  CaptureStatus? _currentStatus;
  bool _isCapturing = false;

  LidarCaptureFlutterService() {
    _statusSubscription = _eventChannel.receiveBroadcastStream().listen(
      (event) {
        if (event is String) {
          _currentStatus = _parseStatus(event);
          notifyListeners();
        }
      },
      onError: (error) {
        debugPrint('[LidarCaptureFlutterService] Event channel error: $error');
      },
      onDone: () {
        debugPrint('[LidarCaptureFlutterService] Event channel closed');
      },
    );
  }

  /// Initialize the service
  Future<void> initialize() async {
    // Listen to status updates
    _statusSubscription = _eventChannel.receiveBroadcastStream().listen(
      (event) {
        if (event is String) {
          _currentStatus = _parseStatus(event);
          notifyListeners();
        }
      },
      onError: (error) {
        debugPrint('[LidarCaptureFlutterService] Event channel error: $error');
      },
      onDone: () {
        debugPrint('[LidarCaptureFlutterService] Event channel closed');
      },
    );
  }

  /// Start AR session
  Future<bool> startARSession() async {
    try {
      await _channel.invokeMethod('startARSession');
      return true;
    } catch (e) {
      debugPrint('[LidarCaptureFlutterService] startARSession error: $e');
      _currentStatus = CaptureStatus(
        isCapturing: false,
        frameCount: 0,
        trackingState: 'Error',
        lidarSupported: false,
        error: e.toString(),
      );
      notifyListeners();
      return false;
    }
  }

  /// Stop AR session
  Future<void> stopARSession() async {
    try {
      await _channel.invokeMethod('stopARSession');
    } catch (e) {
      debugPrint('[LidarCaptureFlutterService] stopARSession error: $e');
    }
  }

  /// Start capturing
  /// [datasetName] Optional name for the dataset (auto-generated if null)
  /// [fps] Target FPS (default 10, clamped 1-30)
  /// [includeDepth] Whether to capture depth data (default true)
  Future<bool> startCapture({
    String? datasetName,
    int fps = 10,
    bool includeDepth = true,
  }) async {
    if (_isCapturing) return false;

    try {
      _isCapturing = true;
      _currentStatus = CaptureStatus(
        isCapturing: true,
        datasetName: datasetName ?? 'lidar_${DateTime.now().millisecondsSinceEpoch}',
        frameCount: 0,
        trackingState: 'Starting...',
        lidarSupported: true,
      );
      notifyListeners();

      final result = await _channel.invokeMethod('startCapture', {
        'datasetName': datasetName,
        'fps': fps,
        'includeDepth': includeDepth,
      });

      if (result is String && result.startsWith('Error')) {
        debugPrint('[LidarCaptureFlutterService] startCapture error: $result');
        _isCapturing = false;
        _currentStatus = CaptureStatus(
          isCapturing: false,
          frameCount: 0,
          trackingState: 'Error',
          lidarSupported: true,
          error: result,
        );
        notifyListeners();
        return false;
      }

      _currentStatus = _currentStatus?.copyWith(trackingState: 'Capturing...') ?? CaptureStatus(
        isCapturing: true,
        frameCount: 0,
        trackingState: 'Capturing...',
        lidarSupported: true,
      );
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('[LidarCaptureFlutterService] startCapture error: $e');
      _isCapturing = false;
      _currentStatus = CaptureStatus(
        isCapturing: false,
        frameCount: 0,
        trackingState: 'Error',
        lidarSupported: true,
        error: e.toString(),
      );
      notifyListeners();
      return false;
    }
  }

  /// Stop capturing
  /// [createZip] Whether to create a ZIP archive (default false)
  Future<String> stopCapture({bool createZip = false}) async {
    if (!_isCapturing) return 'No capture in progress';

    try {
      _isCapturing = false;
      final result = await _channel.invokeMethod('stopCapture', {'createZip': createZip});

      if (result is String) {
        _currentStatus = CaptureStatus(
          isCapturing: false,
          frameCount: 0,
          trackingState: 'Idle',
          lidarSupported: true,
          datasetName: null,
          error: null,
        );
        notifyListeners();
        return result;
      }
    } catch (e) {
      debugPrint('[LidarCaptureFlutterService] stopCapture error: $e');
      return 'Error: ${e.toString()}';
    }
    return 'Unknown result';
  }

  /// Get current status
  Future<CaptureStatus?> getCurrentStatus() async {
    try {
      final result = await _channel.invokeMethod('getStatus');

      if (result is String) {
        final status = _parseStatus(result);
        _currentStatus = status;
        notifyListeners();
        return status;
      }
    } catch (e) {
      debugPrint('[LidarCaptureFlutterService] getStatus error: $e');
    }
    return null;
  }

  /// List available datasets
  Future<List<DatasetInfo>> listDatasets() async {
    try {
      final result = await _channel.invokeMethod('listDatasets');

      if (result is String) {
        final List<dynamic> jsonList = jsonDecode(result);
        final datasets = jsonList.map((json) {
          return DatasetInfo.fromJson(json);
        }).toList();
        return datasets;
      }
      return [];
    } catch (e) {
      debugPrint('[LidarCaptureFlutterService] listDatasets error: $e');
      return [];
    }
  }

  /// Export dataset as ZIP
  Future<String?> exportZip(String datasetId) async {
    try {
      final result = await _channel.invokeMethod('exportZip', {'datasetId': datasetId});
      return result as String?;
    } catch (e) {
      debugPrint('[LidarCaptureFlutterService] exportZip error: $e');
      return null;
    }
  }

  /// Delete dataset
  Future<String?> deleteDataset(String datasetId) async {
    try {
      final result = await _channel.invokeMethod('deleteDataset', {'datasetId': datasetId});
      return result as String?;
    } catch (e) {
      debugPrint('[LidarCaptureFlutterService] deleteDataset error: $e');
      return null;
    }
  }

  /// Check if device supports LiDAR
  bool get isLidarSupported => _currentStatus?.lidarSupported ?? false;

  /// Get current status
  CaptureStatus? get status => _currentStatus;

  /// Check if currently capturing
  bool get isCapturing => _isCapturing;

  /// Parse status JSON string
  CaptureStatus? _parseStatus(String jsonString) {
    try {
      final Map<String, dynamic> data = jsonDecode(jsonString);
      return CaptureStatus.fromJson(data);
    } catch (e) {
      debugPrint('[LidarCaptureFlutterService] parseStatus error: $e');
      return null;
    }
  }

  /// Dispose
  void disposeService() {
    _statusSubscription?.cancel();
  }
}

/// Extension for CaptureStatus copyWith
extension CaptureStatusExtension on CaptureStatus {
  CaptureStatus copyWith({
    bool? isCapturing,
    int? frameCount,
    String? trackingState,
    bool? lidarSupported,
    String? datasetName,
    String? error,
  }) {
    return CaptureStatus(
      isCapturing: isCapturing ?? this.isCapturing,
      frameCount: frameCount ?? this.frameCount,
      trackingState: trackingState ?? this.trackingState,
      lidarSupported: lidarSupported ?? this.lidarSupported,
      datasetName: datasetName ?? this.datasetName,
      error: error ?? this.error,
    );
  }
}