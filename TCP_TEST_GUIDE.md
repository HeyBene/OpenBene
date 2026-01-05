# TCP 连接 + 控制指令验证指南

## 🎯 验证目标

测试完整的控制链路：**发现 → 连接 → 控制**

---

## ✅ 方案 1: 纯 Python 模拟（推荐立即测试）

### 步骤说明

需要打开 **3 个终端窗口**，分别运行：

#### 终端 1️⃣ - UDP 广播器（模拟手机 App 广播）
```bash
cd openbene_sdk
python examples/mock_app.py "MyRobot"
```

**预期输出**:
```
============================================================
Mock Flutter App - UDP Broadcast Simulator
============================================================
Bot Name: MyRobot
Local IP: 192.168.x.x
Broadcasting to: 255.255.255.255:12345
Press Ctrl+C to stop.

[1] Sent: {'type': 'discovery', 'name': 'MyRobot', 'ip': '192.168.x.x'}
[2] Sent: {'type': 'discovery', 'name': 'MyRobot', 'ip': '192.168.x.x'}
...
```

---

#### 终端 2️⃣ - TCP Server（模拟手机 App 接收指令）
```bash
cd openbene_sdk
python examples/mock_tcp_server.py
```

**预期输出**:
```
============================================================
Mock Robot TCP Server
============================================================
Listening on 0.0.0.0:8888
Waiting for PC connection...
Press Ctrl+C to stop.
```

等待连接后会显示：
```
[CONNECTED] PC connected from 127.0.0.1:xxxxx
--------------------------------------------------
```

---

#### 终端 3️⃣ - 控制端（PC 发送指令）

**选项 A: 快速测试**
```bash
cd openbene_sdk
python examples/quick_test.py
```

**预期输出**:
```
============================================================
Quick Control Test
============================================================

[1/4] Connecting to 127.0.0.1:8888...
      Connected successfully!

[2/4] Sending drive(0.5, 0.5)...

[3/4] Sending turn_left(0.6)...

[4/4] Sending stop()...

Test completed successfully!
Disconnected.
```

**同时，终端 2 (TCP Server) 会显示**:
```
[RECEIVED] {'cmd': 'drive', 'val': [0.5, 0.5]}
[EXECUTE] DRIVE - FORWARD
         Left Motor:  +█████░░░░░  (+0.50)
         Right Motor: +█████░░░░░  (+0.50)
--------------------------------------------------

[RECEIVED] {'cmd': 'drive', 'val': [-0.6, 0.6]}
[EXECUTE] DRIVE - TURN LEFT
         Left Motor:  -██████░░░░  (-0.60)
         Right Motor: +██████░░░░  (+0.60)
--------------------------------------------------

[RECEIVED] {'cmd': 'stop'}
[EXECUTE] STOP - All motors stopped
         Left Motor:  +░░░░░░░░░░  (+0.00)
         Right Motor: +░░░░░░░░░░  (+0.00)
--------------------------------------------------
```

---

**选项 B: 完整测试套件**
```bash
cd openbene_sdk
python examples/test_control.py
```

然后选择测试模式：
```
Select test mode:
  1 - Manual Connection Test
  2 - Auto-Discovery Test
  3 - Context Manager Test
  4 - Interactive Control Mode
  0 - Run All Tests
```

**推荐选择**: `1` (手动连接测试)，输入 IP 时按 Enter 使用默认 `127.0.0.1`

---

**选项 C: 交互式控制**
```bash
cd openbene_sdk
python examples/test_control.py
# 选择 4 - Interactive Control Mode
```

然后可以用键盘控制：
```
Commands:
  w - Forward
  s - Backward
  a - Turn Left
  d - Turn Right
  x - Stop
  q - Quit
```

---

## 🎯 成功标准

### ✅ 验证点 1: 连接建立
- 终端 3 显示 "Connected successfully!"
- 终端 2 显示 "[CONNECTED] PC connected from..."

### ✅ 验证点 2: 指令发送
- 终端 3 显示发送的指令日志
- 终端 2 显示接收的 JSON 指令

### ✅ 验证点 3: 指令解析
- 终端 2 正确解析 `drive` 和 `stop` 指令
- 显示可视化的马达状态（进度条）

### ✅ 验证点 4: 协议符合
发送的 JSON 格式正确：
```json
{"cmd": "drive", "val": [0.5, 0.5]}
{"cmd": "stop"}
```

---

## 📋 方案 2: Flutter App 真机测试（Flutter 安装后）

### 前提条件
- Flutter SDK 已安装
- 手机已连接（USB 或无线调试）
- 手机和 PC 在同一 WiFi

### 步骤

#### 1. 手机端 - 安装并运行 App
```bash
cd openbene_app
flutter create . --platforms android,ios
flutter pub get
flutter run
```

在 App 中：
1. 点击 "Start Broadcasting"
2. 查看设备 IP 地址（例如 192.168.1.100）

#### 2. PC 端 - 运行控制脚本
```bash
cd openbene_sdk
python examples/test_control.py
# 选择 1 - Manual Connection Test
# 输入手机 IP: 192.168.1.100
```

#### 3. 观察结果
- PC 终端显示连接成功
- 手机 App 显示 "Connected"
- 手机 App 显示收到的控制指令

---

## 🔧 故障排除

### 问题 1: "Connection timeout"
**原因**: TCP Server 未运行或端口被占用

**解决**:
```bash
# 检查 8888 端口是否被占用
netstat -an | findstr "8888"

# 确保 mock_tcp_server.py 正在运行
```

### 问题 2: "No robot found"
**原因**: UDP 广播未运行

**解决**:
```bash
# 确保 mock_app.py 正在运行
# 检查防火墙是否阻止 UDP 12345
```

### 问题 3: "Connection refused"
**原因**: IP 地址错误或网络不通

**解决**:
```bash
# 如果用 localhost 测试，确保使用 127.0.0.1
# 如果跨设备测试，确保在同一网络并能 ping 通
ping 192.168.1.100
```

---

## 📝 API 使用示例

### 基础用法
```python
from openbene_sdk import OpenBene

# 创建连接
bot = OpenBene("192.168.1.100")
bot.connect()

# 控制
bot.drive(0.5, 0.5)    # 前进 50% 速度
bot.turn_left(0.6)     # 左转 60% 速度
bot.stop()             # 停止

# 断开
bot.disconnect()
```

### 上下文管理器
```python
with OpenBene("192.168.1.100") as bot:
    bot.move_forward(0.7)
    time.sleep(2)
    bot.stop()
# 自动断开连接
```

### 自动发现（需要 UDP 广播）
```python
from openbene_sdk import OpenBene

# 自动发现并连接第一个机器人
bot = OpenBene.connect_auto(timeout=10)
bot.drive(0.5, 0.5)
bot.stop()
bot.disconnect()
```

---

## 🎉 测试完成标志

当你看到以下情况，说明 **Task 1.2 + 1.3 完成**：

- ✅ PC 成功连接到 TCP Server (8888)
- ✅ 发送 drive 指令，Server 正确解析并显示
- ✅ 发送 stop 指令，Server 正确响应
- ✅ JSON 格式符合协议规范
- ✅ 连接可正常断开和重连

---

## 📊 下一步

完成验证后，可以进入：
- **Flutter App 完整实现**: 添加 TCP Server 到 Flutter App
- **真实硬件测试**: 在真实机器人上测试控制
- **SDK 优化**: 添加重连、心跳等高级功能
