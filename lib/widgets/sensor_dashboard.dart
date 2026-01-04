import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/sensor_data.dart';
import '../services/localization_service.dart';

class SensorDashboard extends StatefulWidget {
  final SensorData? sensorData;
  final int framesSent;
  final int sensorUpdatesSent;

  const SensorDashboard({
    super.key,
    this.sensorData,
    required this.framesSent,
    required this.sensorUpdatesSent,
  });

  @override
  State<SensorDashboard> createState() => _SensorDashboardState();
}

class _SensorDashboardState extends State<SensorDashboard> {
  @override
  Widget build(BuildContext context) {
    final localization = context.watch<LocalizationService>();

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.blue.shade50.withValues(alpha: 0.3),
            Colors.purple.shade50.withValues(alpha: 0.3),
          ],
        ),
      ),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          physics: const BouncingScrollPhysics(),
          children: [
            _buildHeader(localization),
            const SizedBox(height: 24),
            _buildStatsRow(localization),
            const SizedBox(height: 20),
            if (widget.sensorData != null) ...[
              _buildSensorSection(
                localization.get('accelerometer'),
                widget.sensorData!.accelerometer,
                Icons.speed_rounded,
                Colors.blue,
                'm/s²',
              ),
              const SizedBox(height: 16),
              _buildSensorSection(
                localization.get('gyroscope'),
                widget.sensorData!.gyroscope,
                Icons.sync_rounded,
                Colors.purple,
                'rad/s',
              ),
              const SizedBox(height: 16),
              _buildBatterySection(widget.sensorData!.batteryLevel, localization),
            ] else
              _buildNoDataCard(localization),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(LocalizationService localization) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.blue.shade400, Colors.blue.shade600],
            ),
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.blue.withValues(alpha: 0.3),
                blurRadius: 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: const Icon(
            Icons.analytics_rounded,
            color: Colors.white,
            size: 28,
          ),
        ),
        const SizedBox(width: 16),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              localization.get('sensor_data'),
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Real-time monitoring',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade600,
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildStatsRow(LocalizationService localization) {
    return Row(
      children: [
        Expanded(
          child: _buildStatCard(
            localization.get('frames_sent'),
            widget.framesSent.toString(),
            Icons.videocam_rounded,
            Colors.blue,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _buildStatCard(
            localization.get('sensor_updates'),
            widget.sensorUpdatesSent.toString(),
            Icons.sensors_rounded,
            Colors.green,
          ),
        ),
      ],
    );
  }

  Widget _buildStatCard(
    String label,
    String value,
    IconData icon,
    Color color,
  ) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.white,
              color.withValues(alpha: 0.05),
            ],
          ),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 28),
            ),
            const SizedBox(height: 12),
            Text(
              value,
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: color,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey.shade700,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSensorSection(
    String title,
    dynamic data,
    IconData icon,
    Color color,
    String unit,
  ) {
    if (data == null) return const SizedBox.shrink();

    String xValue = '0.00';
    String yValue = '0.00';
    String zValue = '0.00';

    if (data is AccelerometerData) {
      xValue = data.x.toStringAsFixed(2);
      yValue = data.y.toStringAsFixed(2);
      zValue = data.z.toStringAsFixed(2);
    } else if (data is GyroscopeData) {
      xValue = data.x.toStringAsFixed(2);
      yValue = data.y.toStringAsFixed(2);
      zValue = data.z.toStringAsFixed(2);
    }

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: color, size: 24),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'Unit: $unit',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: _buildAxisCard('X', xValue, Colors.red.shade400, unit),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildAxisCard('Y', yValue, Colors.green.shade400, unit),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildAxisCard('Z', zValue, Colors.blue.shade400, unit),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAxisCard(String axis, String value, Color color, String unit) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: color.withValues(alpha: 0.3),
          width: 1.5,
        ),
      ),
      child: Column(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            alignment: Alignment.center,
            child: Text(
              axis,
              style: const TextStyle(
                fontSize: 16,
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            unit,
            style: TextStyle(
              fontSize: 10,
              color: Colors.grey.shade600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBatterySection(double? batteryLevel, LocalizationService localization) {
    if (batteryLevel == null) return const SizedBox.shrink();

    final batteryPercent = (batteryLevel * 100).toInt();
    Color batteryColor;
    IconData batteryIcon;

    if (batteryPercent > 80) {
      batteryColor = Colors.green.shade600;
      batteryIcon = Icons.battery_full_rounded;
    } else if (batteryPercent > 50) {
      batteryColor = Colors.green.shade500;
      batteryIcon = Icons.battery_5_bar_rounded;
    } else if (batteryPercent > 20) {
      batteryColor = Colors.orange.shade600;
      batteryIcon = Icons.battery_3_bar_rounded;
    } else {
      batteryColor = Colors.red.shade600;
      batteryIcon = Icons.battery_1_bar_rounded;
    }

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.white,
              batteryColor.withValues(alpha: 0.05),
            ],
          ),
        ),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: batteryColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    batteryIcon,
                    color: batteryColor,
                    size: 32,
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      localization.get('battery_level'),
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'Device power status',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                Text(
                  '$batteryPercent%',
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: batteryColor,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                height: 12,
                child: LinearProgressIndicator(
                  value: batteryLevel,
                  backgroundColor: Colors.grey.shade200,
                  valueColor: AlwaysStoppedAnimation<Color>(batteryColor),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNoDataCard(LocalizationService localization) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey.shade300, width: 1.5),
      ),
      child: Container(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.sensors_off_rounded,
                size: 64,
                color: Colors.grey.shade400,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              localization.get('connecting_status'),
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey.shade600,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              localization.get('app_subtitle'),
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey.shade500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
