import 'package:flutter/foundation.dart';
import '../models/app_language.dart';

class LocalizationService extends ChangeNotifier {
  AppLanguage _currentLanguage = AppLanguage.english;

  AppLanguage get currentLanguage => _currentLanguage;

  void setLanguage(AppLanguage language) {
    _currentLanguage = language;
    notifyListeners();
  }

  String translate(String key) {
    return _translations[_currentLanguage]?[key] ?? key;
  }

  String get(String key) => translate(key);

  static final Map<AppLanguage, Map<String, String>> _translations = {
    AppLanguage.english: {
      // App Title
      'app_name': 'OpenBot Mobile Control',
      'app_subtitle': 'Connect to your PC to start streaming',

      // Connection Screen
      'connection_settings': 'Connection Settings',
      'pc_ip_address': 'PC IP Address',
      'port': 'Port',
      'connect_to_pc': 'Connect to PC',
      'connecting': 'Connecting...',

      // Permission
      'camera_permission_required': 'Camera permission required',
      'grant_permissions': 'Grant Permissions',

      // Quick Setup Guide
      'quick_setup_guide': 'Quick Setup Guide',
      'step_1': 'Ensure PC and phone are on the same Wi-Fi',
      'step_2': 'Run the Python server on your PC',
      'step_3': 'Enter your PC\'s IP address above',
      'step_4': 'Tap Connect to start streaming',

      // Control Screen
      'camera_preview': 'Camera Preview',
      'sensor_data': 'Sensor Data',
      'connection_status': 'Connection Status',
      'connected': 'Connected',
      'disconnected': 'Disconnected',
      'connecting_status': 'Connecting',
      'reconnecting': 'Reconnecting',
      'error': 'Error',
      'disconnect': 'Disconnect',

      // Sensor Dashboard
      'accelerometer': 'Accelerometer',
      'gyroscope': 'Gyroscope',
      'battery_level': 'Battery Level',
      'frames_sent': 'Frames Sent',
      'sensor_updates': 'Sensor Updates',
      'streaming': 'Streaming',

      // Settings
      'settings': 'Settings',
      'language': 'Language',

      // Errors
      'invalid_host_port': 'Please enter valid host and port',
      'camera_permission_denied': 'Camera permission is required',
      'connection_failed': 'Connection failed',
    },
    AppLanguage.chinese: {
      // App Title
      'app_name': 'OpenBot 移动控制',
      'app_subtitle': '连接到您的电脑开始传输',

      // Connection Screen
      'connection_settings': '连接设置',
      'pc_ip_address': '电脑IP地址',
      'port': '端口',
      'connect_to_pc': '连接到电脑',
      'connecting': '连接中...',

      // Permission
      'camera_permission_required': '需要相机权限',
      'grant_permissions': '授予权限',

      // Quick Setup Guide
      'quick_setup_guide': '快速设置指南',
      'step_1': '确保电脑和手机在同一WiFi网络',
      'step_2': '在电脑上运行Python服务器',
      'step_3': '在上方输入您电脑的IP地址',
      'step_4': '点击连接开始传输',

      // Control Screen
      'camera_preview': '相机预览',
      'sensor_data': '传感器数据',
      'connection_status': '连接状态',
      'connected': '已连接',
      'disconnected': '未连接',
      'connecting_status': '连接中',
      'reconnecting': '重新连接中',
      'error': '错误',
      'disconnect': '断开连接',

      // Sensor Dashboard
      'accelerometer': '加速度计',
      'gyroscope': '陀螺仪',
      'battery_level': '电池电量',
      'frames_sent': '已发送帧数',
      'sensor_updates': '传感器更新',
      'streaming': '传输中',

      // Settings
      'settings': '设置',
      'language': '语言',

      // Errors
      'invalid_host_port': '请输入有效的主机和端口',
      'camera_permission_denied': '需要相机权限',
      'connection_failed': '连接失败',
    },
  };
}
