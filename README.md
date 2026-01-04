# OpenBene - 快速开始指南

## 🎯 你现在需要做什么

### ✅ 已完成的工作
- Python SDK 完整实现（发现 + 连接 + 控制）
- 测试工具（Mock App + Mock Server）
- 完整文档

### 📋 验证 TCP 连接和控制指令

你有 **两种方式** 测试：

---

## 方式 1: 快速验证（推荐，5分钟）⭐

### 步骤 1: 一键启动测试
在项目根目录下，双击运行：
```
start_test.bat
```

这会自动打开 3 个窗口：
1. **UDP 广播器** - 模拟手机 App 发送广播
2. **TCP 服务器** - 模拟手机 App 接收控制指令
3. **控制客户端** - PC 端发送控制指令

### 步骤 2: 观察结果

**窗口 1 (UDP 广播)**:
```
Broadcasting to: 255.255.255.255:12345
[1] Sent: {'type': 'discovery', 'name': 'TestBot', 'ip': '10.x.x.x'}
```

**窗口 2 (TCP 服务器)** - 最重要！:
```
[CONNECTED] PC connected from 127.0.0.1:xxxxx

[RECEIVED] {'cmd': 'drive', 'val': [0.5, 0.5]}
[EXECUTE] DRIVE - FORWARD
         Left Motor:  +█████░░░░░  (+0.50)
         Right Motor: +█████░░░░░  (+0.50)

[RECEIVED] {'cmd': 'drive', 'val': [-0.6, 0.6]}
[EXECUTE] DRIVE - TURN LEFT
         Left Motor:  -██████░░░░  (-0.60)
         Right Motor: +██████░░░░  (+0.60)

[RECEIVED] {'cmd': 'stop'}
[EXECUTE] STOP - All motors stopped
```

**窗口 3 (控制客户端)**:
```
[1/4] Connecting to 127.0.0.1:8888...
      Connected successfully!
[2/4] Sending drive(0.5, 0.5)...
[3/4] Sending turn_left(0.6)...
[4/4] Sending stop()...

Test completed successfully!
```

### ✅ 成功标志
如果看到以上输出，说明 **Milestone 1 完全成功**！

---

## 方式 2: 手动启动（适合调试）

打开 3 个终端窗口：

### 终端 1 - UDP 广播
```bash
cd openbene_sdk
python examples/mock_app.py "MyRobot"
```

### 终端 2 - TCP 服务器
```bash
cd openbene_sdk
python examples/mock_tcp_server.py
```

### 终端 3 - 控制端
```bash
cd openbene_sdk
python examples/quick_test.py
```

---

## 🔍 详细测试指南

查看完整测试说明：
- **UDP 测试**: [QUICK_TEST.md](QUICK_TEST.md)
- **TCP 测试**: [TCP_TEST_GUIDE.md](TCP_TEST_GUIDE.md)
- **完整报告**: [MILESTONE_1_COMPLETE.md](MILESTONE_1_COMPLETE.md)

---

## 📱 Flutter App 测试（可选）

等 Flutter 安装完成后：

1. **初始化 Flutter 项目**:
```bash
cd openbene_app
flutter create . --platforms android,ios
flutter pub get
```

2. **运行 App**:
```bash
flutter run
```

3. **在 App 中点击 "Start Broadcasting"**

4. **PC 端连接**:
```bash
cd openbene_sdk
python examples/test_control.py
# 选择 1，输入手机 IP 地址
```

---

## 🎓 使用 Python SDK

### 基础示例
```python
from openbene_sdk import OpenBene

# 连接机器人
bot = OpenBene("192.168.1.100")
bot.connect()

# 控制
bot.move_forward(0.5)   # 前进
bot.turn_left(0.6)      # 左转
bot.stop()              # 停止

bot.disconnect()
```

### 自动发现
```python
from openbene_sdk import OpenBene

# 自动发现并连接
bot = OpenBene.connect_auto(timeout=10)
bot.drive(0.5, 0.5)
bot.stop()
bot.disconnect()
```

更多示例请查看 [openbene_sdk/README.md](openbene_sdk/README.md)

---

## 📊 项目文件导航

### 核心代码
- [openbene_sdk/src/discovery.py](openbene_sdk/src/discovery.py) - UDP 发现
- [openbene_sdk/src/openbene.py](openbene_sdk/src/openbene.py) - TCP 控制 ⭐
- [openbene_app/lib/main.dart](openbene_app/lib/main.dart) - Flutter App

### 测试工具
- [openbene_sdk/examples/mock_app.py](openbene_sdk/examples/mock_app.py) - Mock UDP
- [openbene_sdk/examples/mock_tcp_server.py](openbene_sdk/examples/mock_tcp_server.py) - Mock TCP ⭐
- [openbene_sdk/examples/quick_test.py](openbene_sdk/examples/quick_test.py) - 快速测试 ⭐

### 文档
- [PROJECT_CONTEXT.md](PROJECT_CONTEXT.md) - 项目规划
- [TCP_TEST_GUIDE.md](TCP_TEST_GUIDE.md) - TCP 测试指南 ⭐
- [MILESTONE_1_COMPLETE.md](MILESTONE_1_COMPLETE.md) - 完成报告 ⭐

---

## 🐛 常见问题

### "Connection refused"
- 确保 `mock_tcp_server.py` 正在运行
- 检查端口 8888 是否被占用

### "No robot found"
- 确保 `mock_app.py` 正在运行
- 检查防火墙设置（UDP 12345）

### Windows 防火墙
如需添加例外：
```powershell
# 以管理员运行
New-NetFirewallRule -DisplayName "OpenBene UDP" -Direction Inbound -Protocol UDP -LocalPort 12345 -Action Allow
New-NetFirewallRule -DisplayName "OpenBene TCP" -Direction Inbound -Protocol TCP -LocalPort 8888 -Action Allow
```

---

## 🎉 下一步

完成测试后，你可以：

1. ✅ **验证完整流程** - 确认 3 个窗口都正常工作
2. ✅ **等待 Flutter 安装** - 然后在真机测试
3. ✅ **开始开发** - 使用 Python SDK 编写控制脚本
4. ✅ **添加功能** - 实现更多控制逻辑

需要我继续实现 Flutter App 的 TCP Server 吗？这样就能在真机上测试了！
