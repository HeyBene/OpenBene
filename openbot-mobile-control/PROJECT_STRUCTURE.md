# OpenBot Mobile Control - 项目结构 / Project Structure

## 📁 目录组织 / Directory Organization

```
my_app/
├── 📱 lib/                          # Flutter应用源代码 / Flutter app source
│   ├── models/                     # 数据模型 / Data models
│   │   ├── app_language.dart      # 语言设置 / Language settings
│   │   ├── connection_state.dart  # 连接状态 / Connection state
│   │   └── sensor_data.dart       # 传感器数据 / Sensor data
│   ├── screens/                    # 界面屏幕 / UI screens
│   │   ├── connection_screen.dart # 连接界面 / Connection screen
│   │   └── control_screen.dart    # 控制界面 / Control screen
│   ├── services/                   # 业务逻辑服务 / Services
│   │   ├── app_state.dart         # 应用状态管理 / App state
│   │   ├── camera_service.dart    # 相机服务 / Camera service
│   │   ├── localization_service.dart # 本地化服务 / Localization
│   │   ├── network_service.dart   # 网络服务 / Network service
│   │   ├── permission_service.dart # 权限服务 / Permission service
│   │   └── sensor_service.dart    # 传感器服务 / Sensor service
│   ├── widgets/                    # 可复用组件 / Reusable widgets
│   │   └── sensor_dashboard.dart  # 传感器仪表板 / Sensor dashboard
│   └── main.dart                   # 应用入口 / App entry point
│
├── 🖥️ server/                       # 服务器端组件 / Server components
│   ├── test_server.py             # WebSocket测试服务器 / Test server
│   ├── python_sdk/                # Python SDK
│   │   ├── openbot_sdk/          # SDK源码 / SDK source
│   │   ├── examples/             # 示例代码 / Examples
│   │   ├── requirements.txt      # Python依赖 / Dependencies
│   │   └── setup.py              # 安装配置 / Setup config
│   └── README.md                  # 服务器文档 / Server docs
│
├── 📚 docs/                         # 项目文档 / Documentation
│   ├── README.md                  # 详细文档 / Detailed docs
│   ├── CHANGELOG.md               # 更新日志 / Changelog
│   ├── QUICK_START.md             # 快速开始 / Quick start
│   └── RELEASE_NOTES_v1.0.0.md    # 发布说明 / Release notes
│
├── 📦 releases/                     # 发布文件 / Release files
│   ├── openbot-mobile-control-v1.0.5.apk
│   └── README.md                  # 版本说明 / Version info
│
├── 🤖 android/                      # Android平台代码 / Android code
├── 🍎 ios/                          # iOS平台代码 / iOS code
├── 🪟 windows/                      # Windows平台代码 / Windows code
├── 🐧 linux/                        # Linux平台代码 / Linux code
├── 🖥️ macos/                        # macOS平台代码 / macOS code
├── 🌐 web/                          # Web平台代码 / Web code
├── 🧪 test/                         # 单元测试 / Unit tests
│
├── README.md                       # 项目简介 / Project intro
├── pubspec.yaml                    # Flutter依赖配置 / Dependencies
└── .gitignore                      # Git忽略文件 / Git ignore
```

## 📋 核心文件说明 / Core Files

### 应用代码 / Application Code
- **lib/main.dart**: 应用入口，设置Provider和路由 / App entry, setup providers
- **lib/services/app_state.dart**: 核心状态管理 / Core state management
- **lib/services/network_service.dart**: WebSocket通信 / WebSocket communication
- **lib/widgets/sensor_dashboard.dart**: 传感器数据显示 / Sensor data display

### 服务器端 / Server Side
- **server/test_server.py**: 接收视频和传感器数据的测试服务器 / Test server for data
- **server/python_sdk/**: Python集成SDK / Python integration SDK

### 文档 / Documentation
- **README.md**: 项目概览和快速链接 / Project overview
- **docs/README.md**: 完整使用文档 / Complete documentation
- **docs/QUICK_START.md**: 5分钟快速开始 / 5-minute quick start
- **docs/CHANGELOG.md**: 版本更新历史 / Version history

### 构建配置 / Build Configuration
- **pubspec.yaml**: Flutter包依赖 / Flutter dependencies
- **android/app/build.gradle.kts**: Android构建配置 / Android build config

## 🔄 开发工作流 / Development Workflow

### 1. 修改代码 / Edit Code
```bash
# 编辑Flutter代码
code lib/
```

### 2. 测试运行 / Test Run
```bash
# 连接设备运行
flutter run
```

### 3. 构建发布 / Build Release
```bash
# 构建APK
flutter build apk --release
# 移动到releases文件夹
cp build/app/outputs/flutter-apk/app-release.apk releases/openbot-mobile-control-vX.X.X.apk
```

### 4. 更新文档 / Update Docs
```bash
# 更新CHANGELOG
code docs/CHANGELOG.md
# 更新版本号
code android/app/build.gradle.kts
```

### 5. 启动服务器测试 / Start Server Test
```bash
# 启动测试服务器
python3 server/test_server.py
```

## 📊 代码组织原则 / Code Organization

### lib/ - Flutter代码 / Flutter Code
- **models/**: 纯数据类，无业务逻辑 / Data classes only
- **services/**: 业务逻辑和外部交互 / Business logic
- **screens/**: 完整的页面UI / Full page UIs
- **widgets/**: 可复用的UI组件 / Reusable components

### server/ - 服务器代码 / Server Code
- **test_server.py**: 独立的测试服务器 / Standalone test server
- **python_sdk/**: 可分发的Python包 / Distributable Python package

### docs/ - 文档 / Documentation
- **README.md**: 面向用户的详细文档 / User-facing docs
- **CHANGELOG.md**: 开发者和用户都需要 / For developers and users
- **QUICK_START.md**: 新用户5分钟上手 / 5-min guide for new users

## 🎯 设计理念 / Design Philosophy

1. **清晰分离** / Clear Separation
   - 应用代码、服务器代码、文档、发布物分开
   - Separate app, server, docs, and releases

2. **易于导航** / Easy Navigation
   - 根目录简洁，功能性文件夹组织清晰
   - Clean root, organized functional folders

3. **自包含文档** / Self-Documenting
   - 每个主要文件夹都有README说明
   - Each major folder has README

4. **版本可追溯** / Version Traceable
   - releases/文件夹保存所有版本APK
   - All APK versions in releases/

---

**文件整理完成时间 / Organized**: 2026-01-04
