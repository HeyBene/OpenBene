# OpenBot Mobile Control - 更新日志 / Changelog

## v1.0.2 (2026-01-04 14:23) ⭐ 最新版本 / Latest Version

### 新功能 / New Features
- ✅ **中英文语言切换** - 点击右上角语言按钮切换界面语言
- ✅ **Chinese/English Language Switching** - Toggle UI language via top-right button
- ✅ 所有界面文字支持双语 / All UI text supports both languages
- ✅ 语言偏好在应用会话期间保持 / Language preference persists during session

### 修复 / Bug Fixes
- ✅ 修复WebSocket服务器错误 (handle_client缺少path参数)
- ✅ Fixed WebSocket server TypeError (handle_client missing path argument)
- ✅ 更新test_server.py以兼容websockets 15.0
- ✅ Updated test_server.py for websockets 15.0 compatibility

### 技术改进 / Technical Improvements
- 新增本地化服务系统 / Added localization service system
- 支持English和中文两种语言 / Supports English and Chinese
- MultiProvider架构 / MultiProvider architecture

### 下载 / Download
- **文件名 / Filename**: `openbot-mobile-control-v1.0.2.apk`
- **大小 / Size**: 47 MB
- **版本代码 / Version Code**: 3

---

## v1.0.1 (2026-01-04 13:57)

### 修复 / Bug Fixes
- ✅ 修复输入框无法点击输入的问题
- ✅ Fixed input fields not responding to touch
- ✅ 修复Android 13+上存储权限导致的权限检查失败
- ✅ Fixed permission check failure on Android 13+ due to deprecated storage permission
- ✅ 简化权限请求，只请求必需的相机权限
- ✅ Simplified permission requests to only require camera permission

### 技术改进 / Technical Improvements
- 移除输入框对权限的依赖 / Removed permission dependency from input fields
- 只检查相机权限，不再检查存储权限 / Only check camera permission
- 版本代码 / Version Code: 2

### 下载 / Download
- **文件名 / Filename**: `openbot-mobile-control-v1.0.1.apk`
- **大小 / Size**: 47 MB

---

## v1.0.0 (2026-01-04 11:25) 🎉 初始发布 / Initial Release

### 功能特性 / Features
- ✅ 实时视频流传输 / Real-time video streaming
- ✅ 传感器数据传输 / Sensor data transmission
  - 加速度计 / Accelerometer
  - 陀螺仪 / Gyroscope
  - 电池电量 / Battery level
- ✅ WebSocket通信协议 / WebSocket communication protocol
- ✅ 自动重连机制 (最多5次) / Automatic reconnection (up to 5 attempts)
- ✅ 心跳检测 / Heartbeat mechanism
- ✅ 现代化UI设计 / Modern UI design
- ✅ Python SDK支持 / Python SDK support

### 已知问题 / Known Issues (已在后续版本修复 / Fixed in later versions)
- ❌ 输入框在未授予权限时无法点击 (v1.0.1已修复)
- ❌ Input fields disabled without permission (Fixed in v1.0.1)
- ❌ Android 13+存储权限检查失败 (v1.0.1已修复)
- ❌ Storage permission check fails on Android 13+ (Fixed in v1.0.1)

### 下载 / Download
- **文件名 / Filename**: `openbot-mobile-control-v1.0.0.apk`
- **大小 / Size**: 47 MB
- **版本代码 / Version Code**: 1

---

## 系统要求 / System Requirements

### 移动设备 / Mobile Device
- Android 5.0 (Lollipop) 或更高 / or higher
- 相机支持 / Camera support
- WiFi功能 / WiFi capability
- 至少100MB可用存储空间 / Minimum 100MB free storage

### 电脑 / PC
- Python 3.7 或更高 / or higher
- 网络连接 / Network connectivity
- 任何操作系统 (Windows, macOS, Linux) / Any OS

---

## 下载链接 / Download Links

通过电脑浏览器访问 / Visit from PC browser:
```
http://192.168.123.75:8000
```

可用版本 / Available versions:
- openbot-mobile-control-v1.0.2.apk (推荐 / Recommended)
- openbot-mobile-control-v1.0.1.apk
- openbot-mobile-control-v1.0.0.apk
