/// LiDAR depth data from iPhone sensors
class LiDARData {
  final List<double> depthMap;
  final int width;
  final int height;
  final double minDepth;
  final double maxDepth;
  final DateTime timestamp;

  LiDARData({
    required this.depthMap,
    required this.width,
    required this.height,
    required this.minDepth,
    required this.maxDepth,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  Map<String, dynamic> toJson() {
    return {
      'depth_map': depthMap,
      'width': width,
      'height': height,
      'min_depth': minDepth,
      'max_depth': maxDepth,
      'timestamp': timestamp.toIso8601String(),
    };
  }

  factory LiDARData.fromJson(Map<String, dynamic> json) {
    return LiDARData(
      depthMap: (json['depth_map'] as List).map((e) => (e as num).toDouble()).toList(),
      width: json['width'],
      height: json['height'],
      minDepth: json['min_depth'].toDouble(),
      maxDepth: json['max_depth'].toDouble(),
      timestamp: DateTime.parse(json['timestamp']),
    );
  }
}
