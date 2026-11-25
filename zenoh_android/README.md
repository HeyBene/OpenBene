# OpenBene Android Zenoh transport

这是一个独立的 Android 原生实验工程，用来验证手机与 PC 之间的 Zenoh 链路。
它不修改 `openbot-mobile-control/` 或 `apps/robot_app/`，也不会接管现有 OpenBot
USB/BLE 控制逻辑。

## 当前范围

- 使用官方 `org.eclipse.zenoh:zenoh-kotlin-android:1.10.2`。
- 最低 Android SDK 30，支持 `arm64-v8a`、`x86_64` 等官方 ABI。
- 默认使用显式 PC endpoint，关闭 multicast scouting，避免依赖局域网组播。
- 订阅 `openbene/{robot_id}/cmd`，显示并解析控制命令。
- 发布 `status`、`sensors`、`telemetry` 和二进制 `video`。
- 提供没有 PC 时的环回测试按钮，用来验证订阅和发布链路。
- 不包含相机采集、USB 串口和 BLE 底盘控制；这些接口预留给现有 App 集成。

## Key 约定

```text
openbene/{robot_id}/cmd        PC -> phone, JSON 控制命令
openbene/{robot_id}/status     phone -> PC, JSON 在线状态
openbene/{robot_id}/sensors    phone -> PC, JSON 手机传感器
openbene/{robot_id}/telemetry  phone -> PC, JSON 底盘遥测
openbene/{robot_id}/video      phone -> PC, 二进制视频帧
```

控制命令示例：

```json
{"version":1,"cmd":"drive","val":[0.4,0.4],"seq":1,"sent_at":1700000000000,"ttl_ms":250}
```

视频帧前 20 字节是 little-endian 头：

```text
magic(4) | version(2) | flags(2) | timestamp_ns(8) | frame_id(4) | JPEG bytes
```

## 构建

要求：JDK 17、Android SDK 35、Android SDK Platform 35。Zenoh 使用预编译 JNI
库，不需要安装 Rust，也不需要自己编译 NDK。

```powershell
cd zenoh_android
.\gradlew.bat :app:assembleDebug
```

APK 输出在 `app/build/outputs/apk/debug/app-debug.apk`。

如果本机没有 `local.properties`，脚本或 Android Studio 会自动使用
`ANDROID_HOME`；也可以手工写入：

```properties
sdk.dir=C\:\\Users\\jiken\\AppData\\Local\\Android\\Sdk
```

## 在 PC 上准备对端

PC 可以运行 Zenoh router，也可以作为 peer 监听 TCP。示例：

```bash
zenohd
```

默认 router 通常监听 `tcp/0.0.0.0:7447`。手机端填写：

```text
tcp/<PC 的局域网 IP>:7447
```

也可以在 PC 上用 `z_sub` 查看手机发布的状态：

```bash
z_sub -k 'openbene/**'
```

用 `z_pub` 发送控制命令：

```bash
z_pub -k 'openbene/rtr520/cmd' -v '{"version":1,"cmd":"stop","seq":1,"sent_at":1700000000000}'
```

## 结构

```text
zenoh_android/
  app/src/main/java/io/openbene/zenoh/
    MainActivity.kt       独立测试界面
    ZenohTransport.kt     Zenoh session、发布、订阅和心跳
    Protocol.kt           key、JSON 和二进制帧协议
  app/src/test/java/io/openbene/zenoh/
    ProtocolTest.kt       纯 JVM 协议测试
```

## 接入现有 App 的方式

1. 先把这个工程的传输代码作为独立 PoC 验证网络、ABI 和后台行为。
2. 将 `ZenohTransport.Listener.onCommand` 接到现有 App 的 USB/BLE 命令入口。
3. 将现有相机服务产生的 JPEG 字节传给 `publishVideoFrame()`。
4. 保留 WebSocket 作为回退，不要在一个版本中直接删除旧链路。
5. iOS 需要单独验证本地网络权限、组播权限和后台限制。

## 已知限制

- 当前没有 TLS、认证和访问控制，只适合可信局域网实验。
- 当前没有真正调用电机，环回按钮只打印解析结果。
- 视频按钮发送的是 1 KB 测试二进制负载，不包含相机编码。
- App 需要保持前台；Android 长期后台运行需要前台服务和通知权限。
- 这不是正式生产依赖升级，原有 App 的 WebSocket 行为保持不变。
