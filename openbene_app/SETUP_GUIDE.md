# Flutter App 完整设置和测试指南

## 🎯 已完成的工作

✅ **Flutter App 核心功能已实现**：
- TCP Server (Port 8888)
- UDP 广播 (Port 12345，每秒发送)
- 完整的 Console Log UI
- JSON 指令解析和处理
- Bot Name 配置

## 📋 设置步骤

### 步骤 1: 初始化 Flutter 项目

由于 Flutter 还未完全安装，IDE 会显示错误。**这是正常的**。

等 Flutter 安装完成后，执行以下命令：

```bash
cd openbene_app

# 初始化 Flutter 项目（创建平台文件）
flutter create . --platforms android,ios

# 获取依赖
flutter pub get
```

**重要**: `flutter create .` 会创建 Android/iOS 等平台文件，但**不会覆盖** [lib/main.dart](lib/main.dart) 和 [pubspec.yaml](pubspec.yaml)，因为它们已经存在。

### 步骤 2: 验证依赖安装

运行后检查：
```bash
flutter pub get
```

应该看到：
```
Running "flutter pub get" in openbene_app...
Resolving dependencies...
+ network_info_plus 5.0.2
...
Got dependencies!
```

### 步骤 3: 连接设备并运行

```bash
# 查看可用设备
flutter devices

# 运行 App
flutter run
```

---

## 🚀 Flutter App 功能说明

### UI 界面

1. **Device Information**
   - 显示设备 WiFi IP 地址
   - 自动检测

2. **Bot Name 输入框**
   - 默认值: "Bene"
   - 运行时不可编辑

3. **Start Robot 按钮**
   - 绿色: 点击启动
   - 红色: 点击停止

4. **Console Log**
   - 黑底终端风格
   - 自动滚动到最新消息
   - 彩色日志:
     - 绿色: 正常消息
     - 红色: 错误 (ERROR)
     - 橙色: 警告 (WARNING)
     - 青色: 控制指令 (🚗🛑)
   - Clear 按钮清空日志

5. **状态栏**
   - 显示运行状态
   - 显示监听端口

### 核心逻辑

**点击 "Start Robot" 后**:

1. **UDP 广播启动**
   - 每 1 秒发送一次
   - 格式: `{"type": "discovery", "name": "Bene", "ip": "192.168.x.x"}`
   - 端口: 12345

2. **TCP Server 启动**
   - 监听 `0.0.0.0:8888`
   - 等待 PC 连接

3. **Console Log 显示**:
   ```
   [HH:MM:SS] ========================================
   [HH:MM:SS] Starting OpenBene Robot...
   [HH:MM:SS] Bot Name: Bene
   [HH:MM:SS] IP Address: 192.168.x.x
   [HH:MM:SS] UDP broadcast started (port 12345)
   [HH:MM:SS] TCP server listening on port 8888
   [HH:MM:SS] Robot started successfully!
   [HH:MM:SS] Waiting for PC connection...
   ```

**当 PC 连接后**:
```
[HH:MM:SS] PC CONNECTED from 192.168.x.x
```

**收到控制指令**:
```
[HH:MM:SS] RECEIVED: {"cmd":"drive","val":[0.5,0.5]}
[HH:MM:SS] 🚗 Drive Command: [0.5, 0.5] - FORWARD

[HH:MM:SS] RECEIVED: {"cmd":"drive","val":[-0.6,0.6]}
[HH:MM:SS] 🚗 Drive Command: [-0.6, 0.6] - TURN LEFT

[HH:MM:SS] RECEIVED: {"cmd":"stop"}
[HH:MM:SS] 🛑 Stop Command
```

---

## 🧪 完整测试流程

### 测试 1: 手机 + PC 真机测试

#### 手机端 (Android/iOS):
1. 连接与 PC 相同的 WiFi
2. 运行 Flutter App: `flutter run`
3. 记下显示的 IP 地址 (例如: 192.168.1.100)
4. 点击 **"Start Robot"**
5. 观察 Console Log

#### PC 端:
```bash
cd openbene_sdk

# 方法 1: 手动连接
python examples/test_control.py
# 选择 1 - Manual Connection
# 输入手机 IP: 192.168.1.100

# 方法 2: 自动发现
python examples/test_control.py
# 选择 2 - Auto-Discovery
```

#### 预期结果:

**手机 Console Log**:
```
[12:34:56] PC CONNECTED from 192.168.1.50
[12:34:57] RECEIVED: {"cmd":"drive","val":[0.5,0.5]}
[12:34:57] 🚗 Drive Command: [0.5, 0.5] - FORWARD
[12:34:58] RECEIVED: {"cmd":"drive","val":[-0.6,0.6]}
[12:34:58] 🚗 Drive Command: [-0.6, 0.6] - TURN LEFT
[12:34:59] RECEIVED: {"cmd":"stop"}
[12:34:59] 🛑 Stop Command
[12:35:00] PC DISCONNECTED
```

**PC 终端**:
```
[1/5] Moving forward...
[2/5] Moving backward...
[3/5] Turning left...
[4/5] Turning right...
[5/5] Stopping...

Test completed successfully!
```

---

## 📱 Android 权限配置

如果使用 Android，需要添加网络权限。

**文件**: `openbene_app/android/app/src/main/AndroidManifest.xml`

在 `<manifest>` 标签内添加：
```xml
<uses-permission android:name="android.permission.INTERNET"/>
<uses-permission android:name="android.permission.ACCESS_WIFI_STATE"/>
<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE"/>
```

**注意**: `flutter create .` 会自动创建这个文件，之后手动添加权限。

---

## 🔧 故障排除

### 问题 1: "Target of URI doesn't exist: package:network_info_plus"

**原因**: Flutter 依赖未安装

**解决**:
```bash
cd openbene_app
flutter pub get
```

### 问题 2: App 无法获取 IP

**原因**:
- 未连接 WiFi
- 权限不足 (Android)

**解决**:
- 确保连接 WiFi
- 检查 AndroidManifest.xml 权限

### 问题 3: PC 无法连接到 App

**原因**:
- 不在同一网络
- 防火墙阻止
- IP 地址错误

**解决**:
```bash
# 在 PC 上 ping 手机
ping 192.168.1.100

# 检查端口是否监听
# 在手机上（需要 ADB）
adb shell netstat -an | grep 8888
```

### 问题 4: Console Log 不显示消息

**原因**: 可能是 Flutter 框架未完全加载

**解决**:
- 重新启动 App
- 检查 `flutter run` 输出是否有错误

---

## 📝 协议规范

### UDP 广播 (App → PC)
```json
{
  "type": "discovery",
  "name": "Bene",
  "ip": "192.168.1.100"
}
```
- Port: 12345
- 频率: 每 1 秒

### TCP 控制指令 (PC → App)
```json
{"cmd": "drive", "val": [0.5, 0.5]}
{"cmd": "stop"}
```
- Port: 8888
- 编码: UTF-8
- 结尾: `\n`

---

## 🎉 成功标志

当你看到以下情况，说明 **Flutter App 完全正常**：

1. ✅ App 启动后显示正确的 IP 地址
2. ✅ 点击 "Start Robot" 后 Console Log 显示启动消息
3. ✅ PC 运行 Python SDK 后显示 "PC CONNECTED"
4. ✅ Console Log 显示收到的控制指令
5. ✅ 🚗 和 🛑 图标正确显示

---

## 📊 下一步

完成 Flutter App 测试后：

1. **真实硬件集成**
   - 将 TODO 部分替换为真实的蓝牙/OTG 驱动代码
   - 连接 OpenBot 底盘

2. **功能扩展**
   - 添加摄像头视频流 (Milestone 2)
   - 添加 IMU 数据回传
   - 添加传感器数据

3. **优化**
   - 添加连接状态指示器
   - 添加网络质量监控
   - 添加错误重试机制

---

## 📚 相关文档

- [项目规划](../PROJECT_CONTEXT.md)
- [Python SDK 文档](../openbene_sdk/README.md)
- [Milestone 1 完整报告](../MILESTONE_1_COMPLETE.md)
- [TCP 测试指南](../TCP_TEST_GUIDE.md)
