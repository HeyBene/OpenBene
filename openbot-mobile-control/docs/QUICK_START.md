# OpenBot Mobile Control - 快速开始 / Quick Start

## 📱 第一步：安装应用 / Step 1: Install App

### 下载APK / Download APK
从项目releases文件夹获取最新APK / Get latest APK from releases folder:
```
../releases/openbot-mobile-control-v1.0.5.apk
```

或通过HTTP服务器下载 / Or download via HTTP server:
```
http://192.168.123.75:8000/releases/
```

### 安装步骤 / Installation Steps
1. 下载APK文件 / Download APK file
2. 点击安装 / Tap to install
3. 如提示"不允许安装未知来源"，允许浏览器安装应用权限
4. If prompted "Install unknown apps", allow browser to install apps
5. 完成安装 / Complete installation

---

## 🖥️ 第二步：启动PC服务器 / Step 2: Start PC Server

### 方法1：使用测试服务器 (推荐) / Method 1: Test Server (Recommended)

```bash
cd /Users/zhangzhiyuan/Projects/my_app
python3 server/test_server.py
```

**服务器启动成功后会显示 / Server will show:**
```
============================================================
🤖 OpenBot 测试服务器
============================================================
📡 监听地址: 0.0.0.0:8765
⏰ 启动时间: 2026-01-04 14:30:00

等待手机应用连接...
```

### 方法2：使用Python SDK / Method 2: Python SDK

```bash
cd /Users/zhangzhiyuan/Projects/my_app/server/python_sdk
python3 examples/simple_example.py
```

---

## 📲 第三步：连接应用 / Step 3: Connect App

1. **打开OpenBot应用 / Open OpenBot app**

2. **选择语言 / Select Language**
   - 点击右上角语言按钮 / Tap language button in top-right
   - 选择 English 或 中文 / Choose English or Chinese

3. **授予相机权限 / Grant Camera Permission**
   - 点击"授予权限" / Tap "Grant Permissions"
   - 选择"使用时允许" / Select "While using the app"

4. **输入连接信息 / Enter Connection Info**
   - IP地址 / IP Address: `192.168.123.75`
   - 端口 / Port: `8765`

5. **点击连接 / Tap Connect**
   - 点击"连接到电脑" / Tap "Connect to PC"

---

## ✅ 验证连接成功 / Verify Connection

### 手机端 / Mobile App
应该看到 / Should see:
- 相机预览画面 / Camera preview
- 连接状态显示"已连接" / Connection status shows "Connected"
- 传感器数据实时更新 / Sensor data updating in real-time

### 电脑端 / PC Terminal
应该看到 / Should see:
```
✅ 新客户端连接: 192.168.x.xxx:xxxxx
📹 收到视频帧: 45231 bytes, 时间: 1704348600000
📊 传感器数据:
   加速度: X=0.12, Y=0.34, Z=9.81 m/s²
   陀螺仪: X=0.00, Y=0.01, Z=0.00 rad/s
   电池: 85%
💓 心跳
```

---

## 🔧 故障排除 / Troubleshooting

### 问题1：无法连接 / Issue 1: Cannot Connect

**检查清单 / Checklist:**
- [ ] 手机和电脑在同一WiFi网络 / Same WiFi network
- [ ] PC服务器正在运行 / PC server is running
- [ ] IP地址正确 / Correct IP address
- [ ] 端口8765未被占用 / Port 8765 is available

**验证服务器运行 / Verify server running:**
```bash
lsof -i :8765
```

**获取正确IP地址 / Get correct IP:**
```bash
ifconfig | grep "inet " | grep -v 127.0.0.1
```

### 问题2：相机权限警告 / Issue 2: Camera Permission Warning

**解决方法 / Solution:**
1. 点击"授予权限"按钮 / Tap "Grant Permissions" button
2. 如果仍然失败，进入系统设置 / If still fails, go to system settings:
   - 设置 → 应用 → OpenBot → 权限 → 相机 → 允许
   - Settings → Apps → OpenBot → Permissions → Camera → Allow

### 问题3：输入框无法点击 / Issue 3: Input Fields Not Clickable

**解决方法 / Solution:**
- 确保使用v1.0.5或更高版本 / Ensure using v1.0.5 or higher
- 如使用旧版本，请下载最新版并重新安装
- If using old version, download latest and reinstall

### 问题4：服务器报错 / Issue 4: Server Error

**常见错误 / Common errors:**

1. **TypeError: handle_client() missing 1 required positional argument**
   - ✅ 已在v1.0.2修复 / Fixed in v1.0.2
   - 确保test_server.py是最新版本 / Ensure test_server.py is latest

2. **ModuleNotFoundError: No module named 'websockets'**
   ```bash
   pip3 install websockets
   ```

3. **Address already in use**
   ```bash
   # 查找占用端口的进程 / Find process using port
   lsof -i :8765
   # 结束进程 / Kill process
   kill <PID>
   ```

---

## 📚 更多帮助 / More Help

- **完整文档 / Full Documentation**: README.md
- **更新日志 / Changelog**: CHANGELOG.md
- **发布说明 / Release Notes**: RELEASE_NOTES_v1.0.0.md

---

## 🎯 下一步 / Next Steps

连接成功后，你可以 / After connecting successfully:

1. **查看实时视频流 / View real-time video**
2. **监控传感器数据 / Monitor sensor data**
3. **开发自己的应用 / Develop your own apps**
   - 使用Python SDK / Use Python SDK
   - 参考examples目录 / Check examples directory

---

**祝你使用愉快！ / Enjoy using OpenBot! 🎉**
