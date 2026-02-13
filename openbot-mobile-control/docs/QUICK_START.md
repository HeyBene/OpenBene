# OpenBot Mobile Control - 快速开始 / Quick Start

> ⚠️ **重要更新**: v1.0.6 支持 UDP 自动发现，无需手动输入 IP！  
> ⚠️ **Important Update**: v1.0.6 supports UDP auto-discovery, no manual IP input needed!

---

## 📱 第一步：安装应用 / Step 1: Install App

### 下载APK / Download APK
从项目releases文件夹获取最新APK / Get latest APK from releases folder:
```
../releases/openbot-mobile-control-v1.0.6-with-discovery.apk
```

### 安装步骤 / Installation Steps
1. 下载APK文件 / Download APK file
2. 点击安装 / Tap to install
3. 如提示"不允许安装未知来源"，允许浏览器安装应用权限
4. If prompted "Install unknown apps", allow browser to install apps
5. 完成安装 / Complete installation

### 验证版本 / Verify Version
安装后打开应用，应该看到：
- ✅ "Server Address: ws://192.168.x.x:8765"
- ✅ "Waiting for PC..." 状态
- ✅ 显示手机 IP（不是输入框）

如果看到 "PC IP Address" 输入框，说明安装了错误版本！

---

## 🖥️ 第二步：安装 Python SDK / Step 2: Install Python SDK

### 安装 OpenBene SDK

```bash
# 导航到 SDK 目录
cd ../openbene_sdk

# 安装 SDK
pip install -e .
```

### 验证安装 / Verify Installation
```python
python -c "from openbene import OpenBene; print('✓ SDK installed successfully')"
```

---

## 📲 第三步：自动连接 / Step 3: Auto-Connect

### 方法 1：自动发现（推荐）/ Method 1: Auto-Discovery (Recommended)

1. **打开手机应用 / Open Mobile App**
   - 授予相机权限 / Grant camera permission
   - 看到 "Waiting for PC..." 状态 / See "Waiting for PC..." status
   - 手机自动开始广播 IP / Phone automatically broadcasts IP

2. **运行 Python 代码 / Run Python Code**
- 传感器数据实时更新 / Sensor data updating in real-time

### 电脑端 / PC Terminal
应该看到 / Should see:
```
✅ 新客户端连接: 192.168.x.xxx:xxxxx
📹 收到视频帧: 45231 bytes, 时间: 1704348600000
📊 传感器数据:

```python
from openbene import OpenBene

# 自动发现并连接
bot = OpenBene.auto_connect()
print(f"✓ 已连接到 {bot.ip}:{bot.port}")

# 测试控制
bot.forward(0.5)
import time
time.sleep(2)
bot.stop()

bot.disconnect()
```

**工作原理 / How it works:**
- 手机每2秒通过UDP广播IP（端口12345）
- PC SDK 监听UDP广播自动发现手机
- 自动连接到手机的WebSocket服务器（端口8765）

---

### 方法 2：手动连接 / Method 2: Manual Connection

如果自动发现失败（例如防火墙阻止UDP），可以手动输入IP：

```python
from openbene import OpenBene

# 手动输入手机显示的 IP
bot = OpenBene("192.168.1.15", port=8765)
bot.connect()

print("✓ 已连接")
bot.forward(0.5)
bot.stop()
bot.disconnect()
```

---

## ✅ 验证连接成功 / Verify Connection

### 手机端 / Mobile App
应该看到 / Should see:
- 相机预览画面 / Camera preview
- 连接状态显示"PC connected" / Connection status shows "PC connected"


### PC端 / PC Side
应该显示 / Should display:
```
✓ 已连接到 192.168.1.15:8765
```

---

## 🔧 故障排除 / Troubleshooting

### 问题1：自动发现失败 / Issue 1: Auto-Discovery Fails

**现象 / Symptom:**
- `OpenBene.auto_connect()` 超时

**可能原因 / Possible Causes:**
- 手机和电脑不在同一WiFi
- 防火墙阻止UDP端口12345
- WiFi有客户端隔离功能

**解决方法 / Solutions:**

**Windows:**
```powershell
# 允许 UDP 12345
netsh advfirewall firewall add rule name="OpenBene Discovery" dir=in action=allow protocol=UDP localport=12345
```

**测试UDP接收:**
```python
import socket
sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
sock.bind(('', 12345))
sock.settimeout(5)
try:
    data, addr = sock.recvfrom(1024)
    print(f'收到来自 {addr[0]} 的消息: {data.decode()}')
except:
    print('5秒内未收到广播')
```

### 问题2：手动连接失败 / Issue 2: Manual Connection Fails

**检查清单 / Checklist:**
- [ ] 手机应用显示 "Waiting for PC..." 状态
- [ ] 电脑和手机在同一网段（例如都是 192.168.1.x）
- [ ] 可以 ping 通手机：`ping 192.168.1.15`
- [ ] 防火墙允许端口 8765

### 问题3：相机权限警告 / Issue 3: Camera Permission Warning

**解决方法 / Solution:**
1. 点击"授予权限"按钮 / Tap "Grant Permissions" button
2. 如果仍然失败，进入系统设置 / If still fails, go to system settings:
   - 设置 → 应用 → OpenBot → 权限 → 相机 → 允许
   - Settings → Apps → OpenBot → Permissions → Camera → Allow

### 问题4：版本不正确 / Issue 4: Wrong Version

**现象 / Symptom:**
- 看到 "PC IP Address" 输入框

**解决方法 / Solution:**
1. 卸载当前应用
2. 从 `../releases/` 重新下载 v1.0.6
3. 重新安装
4. 确认看到 "Server Address" 界面

---

## 📚 更多帮助 / More Help

- **完整文档 / Full Documentation**: [README.md](README.md)
- **更新日志 / Changelog**: [../CHANGELOG.md](../CHANGELOG.md)
- **Python SDK 文档**: [../../openbene_sdk/README.md](../../openbene_sdk/README.md)
- **版本发布说明**: [../releases/README.md](../releases/README.md)

---

## 🎯 下一步 / Next Steps

连接成功后，你可以 / After connecting successfully:

1. **查看实时视频流 / View real-time video**
2. **监控传感器数据 / Monitor sensor data**
3. **开发自己的应用 / Develop your own apps**
   - 使用 OpenBene Python SDK
   - 参考 `openbene_sdk/examples/` 目录
   - 查看 API 文档

---

**祝你使用愉快！ / Enjoy using OpenBot! 🎉**
