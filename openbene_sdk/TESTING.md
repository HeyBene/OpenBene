# OpenBene Milestone 1 - UDP Discovery 测试指南

## 📋 已完成的功能

### Python SDK 端
- ✅ [discovery.py](openbene_sdk/src/discovery.py) - UDP 监听服务
- ✅ [test_discovery.py](openbene_sdk/examples/test_discovery.py) - 测试脚本

### Flutter App 端
- ✅ [main.dart](openbene_app/lib/main.dart) - UDP 广播发送 UI
- ✅ [pubspec.yaml](openbene_app/pubspec.yaml) - Flutter 项目配置

## 🚀 如何测试

### 步骤 1: 运行 Python 监听端 (PC)

在项目根目录下运行：

```bash
cd openbene_sdk
python examples/test_discovery.py
```

你应该看到：
```
==================================================
OpenBene Discovery Test
==================================================
Starting UDP listener on port 12345...
Make sure your OpenBene App is running and broadcasting.
Press Ctrl+C to stop.

🔍 Discovery service started on UDP port 12345
Waiting for OpenBene robots to broadcast...
```

### 步骤 2: 设置 Flutter App (手机/模拟器)

1. **安装 Flutter SDK**（如果还没有）:
   ```bash
   # 下载完成后，配置环境变量
   flutter doctor
   ```

2. **初始化 Flutter 项目**:
   ```bash
   cd openbene_app
   flutter create . --platforms android,ios
   ```
   这会创建 Android 和 iOS 必要的文件，但保留我们的 `lib/main.dart`。

3. **获取依赖**:
   ```bash
   flutter pub get
   ```

4. **连接设备并运行**:
   ```bash
   # 连接手机或启动模拟器，然后运行
   flutter run
   ```

### 步骤 3: 测试通信

1. 确保 PC 和手机在**同一局域网**内
2. 在 Flutter App 中点击 **"Start Broadcasting"** 按钮
3. 观察 Python 终端，应该每 2 秒看到：

```
✅ Discovered Bot: [OpenBene-Bot] at [192.168.1.xxx]

📱 Bot Details:
   Name: OpenBene-Bot
   IP: 192.168.1.xxx
   Type: discovery
--------------------------------------------------
```

## 🎯 预期结果

### Python 端输出示例：
```
2025-01-01 12:00:00 - __main__ - INFO - 🔍 Discovery service started on UDP port 12345
2025-01-01 12:00:00 - __main__ - INFO - Waiting for OpenBene robots to broadcast...
2025-01-01 12:00:05 - __main__ - INFO - ✅ Discovered Bot: [OpenBene-Bot] at [192.168.1.100]

📱 Bot Details:
   Name: OpenBene-Bot
   IP: 192.168.1.100
   Type: discovery
--------------------------------------------------
```

### Flutter App 界面：
- 显示设备 IP 地址
- TextField 显示 "OpenBene-Bot" (可修改)
- "Start Broadcasting" 按钮变为绿色
- 状态显示 "Broadcasting..."

## 🐛 故障排除

### 问题 1: Python 端收不到消息
- ✅ 检查防火墙是否允许 UDP 12345 端口
- ✅ 确认 PC 和手机在同一网络（不要跨子网）
- ✅ 检查手机 App 是否显示正确的 IP 地址

### 问题 2: Flutter 编译错误
```bash
# 清理并重新构建
flutter clean
flutter pub get
flutter run
```

### 问题 3: 手机无法获取 IP
- 检查手机 WiFi 连接
- 授予 App 网络权限（Android 需要在 AndroidManifest.xml 添加权限）

## 📝 协议验证

确保传输的 JSON 格式符合 [PROJECT_CONTEXT.md](../PROJECT_CONTEXT.md:31) 定义：

```json
{
  "type": "discovery",
  "name": "OpenBene-Bot",
  "ip": "192.168.1.100"
}
```

## ✅ 完成标志

当你看到以下情况时，Milestone 1 - Task 1.1 完成：
1. ✅ Python 脚本成功打印 "✅ Discovered Bot: [Name] at [IP]"
2. ✅ Flutter App 显示正确的设备 IP
3. ✅ 每 2 秒收到一次广播消息
4. ✅ Bot Name 可以在 App 中修改并反映到 Python 端

## 🎉 下一步

完成测试后，我们将进入：
- **Task 1.2**: 实现 TCP 连接和控制指令发送
- **Task 1.3**: 在 App 端实现指令接收和执行

---

**Note**: 当前实现仅用于 Milestone 1 测试，暂不包含视频流等高级功能。
