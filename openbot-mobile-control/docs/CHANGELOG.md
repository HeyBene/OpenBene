# OpenBot Mobile Control - 更新日志 / Changelog

## v1.0.5 (2026-01-04 15:15) ⭐ 最新版本 / Latest Version

### 性能优化 / Performance Improvements
- ✅ **大幅提升滚动性能** - 传感器数据界面现在流畅丝滑
- ✅ **Significantly improved scrolling performance** - Sensor data interface now smooth and responsive
- ✅ **优化UI刷新率** - 从100ms降低到300ms，减少卡顿
- ✅ **Optimized UI refresh rate** - Reduced from 100ms to 300ms to eliminate stuttering
- ✅ **智能重绘机制** - 只在需要时更新界面组件
- ✅ **Smart repaint mechanism** - Only updates necessary UI components

### 技术改进 / Technical Improvements
- 使用 `RepaintBoundary` 隔离组件重绘 / Using RepaintBoundary to isolate widget repaints
- 使用 `Selector` 替代 `context.watch` 减少不必要的rebuild / Using Selector instead of context.watch to reduce rebuilds
- 添加 `AutomaticKeepAliveClientMixin` 保持滚动状态 / Added AutomaticKeepAliveClientMixin to preserve scroll state
- UI更新节流：仅每3次传感器更新触发1次界面刷新 / UI update throttling: Only trigger UI refresh every 3 sensor updates
- 增加ListView缓存范围 (cacheExtent: 1000) / Increased ListView cache extent

### 根本原因 / Root Cause Fixed
- 之前传感器数据每100ms更新一次UI导致频繁重建整个界面
- Previously sensor data updated UI every 100ms causing frequent full widget rebuilds
- 现在只在必要时更新，大幅减少渲染压力
- Now only updates when necessary, significantly reducing rendering overhead

### 下载 / Download
- **文件名 / Filename**: `openbot-mobile-control-v1.0.5.apk`
- **大小 / Size**: 50 MB
- **版本代码 / Version Code**: 6

---

## v1.0.4 (2026-01-04 14:58)

### 新功能 / New Features
- ✅ **传感器仪表板完全支持中英文** - 所有传感器相关文字支持语言切换
- ✅ **Sensor dashboard fully supports Chinese/English** - All sensor text supports language switching
- ✅ **优化滚动性能** - 更流畅的上下滑动体验
- ✅ **Optimized scrolling performance** - Smoother vertical scrolling experience

### 本地化元素 / Localized Elements
- 传感器数据标题 / Sensor Data title
- 加速度计 / Accelerometer
- 陀螺仪 / Gyroscope
- 电池电量 / Battery Level
- 已发送帧数 / Frames Sent
- 传感器更新 / Sensor Updates

### 性能优化 / Performance Improvements
- ✅ 使用ListView替代SingleChildScrollView提升滚动性能
- ✅ Used ListView instead of SingleChildScrollView for better scroll performance
- ✅ 添加弹性滚动物理效果 (BouncingScrollPhysics)
- ✅ Added bouncing scroll physics for iOS-like feel
- ✅ 优化组件重建减少卡顿
- ✅ Optimized widget rebuilds to reduce stuttering

### 技术改进 / Technical Improvements
- 从StatelessWidget改为StatefulWidget
- Changed from StatelessWidget to StatefulWidget
- 使用Provider监听语言变化
- Using Provider to watch language changes

### 下载 / Download
- **文件名 / Filename**: `openbot-mobile-control-v1.0.4.apk`
- **大小 / Size**: 48 MB
- **版本代码 / Version Code**: 5

---

## v1.0.3 (2026-01-04 14:44)

### 修复 / Bug Fixes
- ✅ **修复控制界面语言问题** - 控制界面现在会跟随应用语言设置
- ✅ **Fixed control screen language issue** - Control screen now follows app language setting
- ✅ **修复返回按钮黑屏问题** - 点击断开连接后正常返回连接界面
- ✅ **Fixed black screen on back button** - Properly returns to connection screen after disconnect
- ✅ 所有控制界面文字支持中英文切换
- ✅ All control screen text supports language switching

### 本地化元素 / Localized Elements
- 相机预览标题 / Camera Preview title
- 连接状态 (已连接、连接中、重新连接等) / Connection status
- 断开连接按钮提示 / Disconnect button tooltip
- 传输指示器 / Streaming indicator
- 相机初始化消息 / Camera initialization message

### 技术改进 / Technical Improvements
- 移除了不正确的Navigator.pop()调用 / Removed incorrect Navigator.pop() call
- 让AppNavigator自动处理界面切换 / Let AppNavigator handle screen transitions
- 添加状态文本本地化函数 / Added status text localization function

### 下载 / Download
- **文件名 / Filename**: `openbot-mobile-control-v1.0.3.apk`
- **大小 / Size**: 47 MB
- **版本代码 / Version Code**: 4

---

## v1.0.2 (2026-01-04 14:23)

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
