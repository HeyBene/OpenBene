# OpenBot Mobile Control - APK 发布版本 / Releases

## ⚠️ 重要提示 / Important Notice

**请只下载这个文件夹中的 APK 文件！**  
**Only download APK files from this folder!**

如果从其他地方下载，可能会得到错误的版本，导致无法正常使用。  
If downloaded from elsewhere, you may get wrong version that won't work.

---

## 📱 最新版本 / Latest Version

### **Version 1.0.6** - 2026-02-13

#### ✨ 新功能 / New Features
- ✅ **UDP 自动发现** - PC 端可以自动找到手机，无需手动输入 IP
- ✅ **UDP Auto-Discovery** - PC can automatically find phone without manual IP input
- ✅ 手机每 2 秒广播一次 IP 地址（UDP 端口 12345）
- ✅ Phone broadcasts IP every 2 seconds (UDP port 12345)

#### 📥 下载 / Download
**文件名 / Filename:** `openbot-mobile-control-v1.0.6-with-discovery.apk`  
**大小 / Size:** ~48 MB  
**版本代码 / Version Code:** 7

[**⬇️ 点击下载 / Click to Download**](openbot-mobile-control-v1.0.6-with-discovery.apk)

---

## ✅ 如何验证版本正确 / How to Verify Correct Version

安装 APK 后，打开应用，你应该看到：

### **正确的界面 ✅ Correct UI**

```
┌─────────────────────────────────┐
│  OpenBot Mobile Control         │
│                                 │
│  Connection Status              │
│  ⭕ Waiting for PC...           │
│                                 │
│  Server Address                 │
│  📡 ws://192.168.1.15:8765     │
│  IP: 192.168.1.15  Port: 8765  │
│                                 │
│  OpenBot Connection             │
│  🔌 Not connected               │
│  [Connect to OpenBot]           │
│                                 │
│  Quick Setup Guide              │
│  1. Start the server on phone  │
│  2. On PC: pip install openbene│
│  3. Use IP address above        │
│  4. Control the robot!          │
└─────────────────────────────────┘
```

**关键特征：**
- ✅ 显示 "**Server Address**"（不是 "Connection Settings"）
- ✅ 显示 "**Waiting for PC...**" 状态
- ✅ 显示**手机的 IP 地址**（不是输入框）
- ✅ 有 "Connect to OpenBot" 按钮（USB 连接）

### **错误的界面 ❌ Wrong UI**

如果你看到：
- ❌ "**Connection Settings**" 标题
- ❌ "**PC IP Address**" **输入框**
- ❌ "Enter your PC's IP address above" 提示
- ❌ "Connect to PC" 按钮

**这说明你安装了错误的版本！**  
**This means you installed the wrong version!**

**解决方法 / Solution:**
1. 卸载当前应用
2. 重新从此文件夹下载并安装
3. 确认界面符合"正确的界面"描述

---

## 🚀 使用方法 / How to Use

### **方法 1：自动发现（推荐）/ Auto-Discovery (Recommended)**

**手机端 / Phone:**
1. 安装并打开 APK
2. 授予相机权限
3. 看到 "Waiting for PC..." 状态即表示服务器已启动
4. 记下显示的 IP 地址（备用）

**电脑端 / PC:**
```python
from openbene import OpenBene

# 自动发现并连接（无需输入 IP）
bot = OpenBene.auto_connect()

print(f"✓ 已连接到 {bot.ip}:{bot.port}")

# 控制小车
bot.forward(0.5)
import time
time.sleep(2)
bot.stop()

bot.disconnect()
```

**工作原理 / How it works:**
1. 手机每 2 秒通过 UDP 广播自己的 IP（端口 12345）
2. PC 的 Python SDK 监听 UDP 广播
3. 收到广播后自动连接到手机的 WebSocket 服务器（端口 8765）

### **方法 2：手动输入 IP / Manual IP Input**

如果自动发现失败（例如防火墙阻止 UDP），可以手动输入：

```python
from openbene import OpenBene

# 手动输入手机的 IP 地址
bot = OpenBene("192.168.1.15", port=8765)
bot.connect()

print("✓ 已连接")
bot.forward(0.5)
```

---

## 🔧 故障排除 / Troubleshooting

### 问题 1：自动发现找不到手机
**现象:** `OpenBene.auto_connect()` 超时失败

**可能原因：**
1. 手机和电脑不在同一 WiFi 网络
2. 防火墙阻止了 UDP 端口 12345
3. WiFi 有客户端隔离功能

**解决方法：**
```powershell
# Windows: 允许 UDP 12345
netsh advfirewall firewall add rule name="OpenBene Discovery" dir=in action=allow protocol=UDP localport=12345

# 检查是否能收到广播
python -c "
import socket, json
sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
sock.bind(('', 12345))
sock.settimeout(5)
try:
    data, addr = sock.recvfrom(1024)
    print(f'收到来自 {addr[0]} 的消息: {data.decode()}')
except:
    print('5秒内未收到任何广播')
"
```

### 问题 2：手机 IP 是 100.x.x.x
**现象:** 手机显示的 IP 不是 192.168.x.x 格式

**原因:** 手机使用的是移动数据，不是 WiFi

**解决方法:**
1. 在手机设置中连接到 WiFi
2. 确认 IP 地址变为 192.168.x.x 或 10.x.x.x
3. 重启应用

### 问题 3：连接超时
**现象:** 手动输入 IP 后连接失败

**检查清单:**
- [ ] 手机应用显示 "Waiting for PC..." 状态
- [ ] 电脑和手机在同一网段（例如都是 192.168.1.x）
- [ ] 可以 ping 通手机：`ping 192.168.1.15`
- [ ] 防火墙允许端口 8765

---

## 📖 相关文档 / Related Documentation

- [快速开始指南 / Quick Start](../docs/QUICK_START.md)
- [完整文档 / Full Documentation](../docs/README.md)
- [更新日志 / Changelog](../CHANGELOG.md)
- [Python SDK 文档](../../openbene_sdk/README.md)

---

## 🆘 需要帮助？ / Need Help?

如果遇到问题：
1. 检查 [故障排除](#-故障排除--troubleshooting) 部分
2. 查看完整文档
3. 在 GitHub 提交 Issue

**重要提醒：** 请务必说明你使用的 APK 版本和看到的界面截图！
