# OpenBene Android Zenoh transport

这是一个独立的 Android 原生实验工程，用来验证手机与 PC 之间的 Zenoh 链路。
它不修改 `openbot-mobile-control/` 或 `apps/robot_app/`，也不会接管现有 OpenBot
USB/BLE 控制逻辑。

## 当前范围

- 使用官方 `org.eclipse.zenoh:zenoh-kotlin-android:1.10.2`。
- 最低 Android SDK 30，支持 `arm64-v8a`、`x86_64` 等官方 ABI。
- 默认使用显式 PC endpoint，关闭 multicast scouting，避免依赖局域网组播。
- 订阅 `openbene/{robot_id}/cmd`，显示并解析控制命令。
- 发布 `status`、`sensors`、`telemetry`、二进制 `video`，以及和 iOS 同格式的
  `frame`（ZPKD 多平面采集帧）与 `session`（录制起止事件）。
- 提供没有 PC 时的环回测试按钮，用来验证订阅和发布链路。
- 不包含相机采集、USB 串口和 BLE 底盘控制；这些接口预留给现有 App 集成。

## Key 约定

```text
openbene/{robot_id}/cmd        PC -> phone, JSON 控制命令
openbene/{robot_id}/status     phone -> PC, JSON 在线状态
openbene/{robot_id}/sensors    phone -> PC, JSON 手机传感器
openbene/{robot_id}/telemetry  phone -> PC, JSON 底盘遥测
openbene/{robot_id}/video      phone -> PC, ZFRM 单张 JPEG（兼容旧接收端）
openbene/{robot_id}/frame      phone -> PC, ZPKD 多平面采集帧
openbene/{robot_id}/session    phone -> PC, JSON 录制起止事件
```

控制命令示例：

```json
{"version":1,"cmd":"drive","val":[0.4,0.4],"seq":1,"sent_at":1700000000000,"ttl_ms":250}
```

视频帧前 20 字节是 little-endian 头：

```text
magic(4) | version(2) | flags(2) | timestamp_ns(8) | frame_id(4) | JPEG bytes
```

`frame` 通道的 `ZPKD` 在同样头部语义上扩展为分节容器，与
`zenoh_ios/Sources/OpenBeneZenoh/FrameCodec.swift` 逐字节一致：

```text
magic(4)=ZPKD | version(2) | flags(2) | timestamp_ns(8) | frame_id(4) | section_count(4)
section: type(4) | length(4) | payload
  type 1 = RGB JPEG
  type 2 = depth PNG (uint16 mm)
  type 3 = confidence PNG (mono8)
  type 4 = pose float32[16]（列主序 camera-to-world）
  type 5 = metadata JSON（宽高、深度尺寸、内参、跟踪状态、深度来源）
```

未知 section 会被跳过，便于后续加字段。`flags` 低四位表示 RGB、深度、置信度和
位姿是否存在。iOS 侧另有 `publishLegacyVideo` 开关，打开时同一帧会额外发一份
`ZFRM` 到 `video`；Android 的 `publishCaptureFrame(frame, legacyVideo = true)`
行为相同。

因为两边 key 和二进制格式一致，`zenoh_ios/pc` 里的 `openbene-recv` 可以同时
接收 Android 和 iOS 两台手机，录制同一个 MCAP。

## 构建

要求：JDK 17、Android SDK 35、Android SDK Platform 35。Zenoh 使用预编译 JNI
库，不需要安装 Rust，也不需要自己编译 NDK。

```powershell
cd zenoh_android
.\gradlew.bat :app:assembleDebug
```

单元测试（协议、ZPKD 编解码、session 事件）：

```powershell
.\gradlew.bat :app:testDebugUnitTest
```

如果本机 Gradle 访问 Maven Central 的 TLS 握手失败，可以先把 Zenoh 的四个
artifact（`zenoh-kotlin-android`、`zenoh-kotlin`、`zenoh-flat-jni`、
`zenoh-flat-jni-android`）用 curl 下到任意本地 Maven 目录，再用
`-PopenBeneMavenRepo=<目录>` 指定，本地仓库会排在 google/mavenCentral 之前：

```powershell
.\gradlew.bat -PopenBeneMavenRepo=C:/obz-m2 :app:assembleDebug
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
    Protocol.kt           key、JSON、ZFRM 帧和 session 事件
    FrameCodec.kt         ZPKD 多平面帧编解码（与 iOS 对齐）
  app/src/test/java/io/openbene/zenoh/
    ProtocolTest.kt       纯 JVM 协议测试
    FrameCodecTest.kt     ZPKD 布局、往返、未知 section 测试
```

## 接入现有 App 的方式

1. 先把这个工程的传输代码作为独立 PoC 验证网络、ABI 和后台行为。
2. 将 `ZenohTransport.Listener.onCommand` 接到现有 App 的 USB/BLE 命令入口。
3. 将现有相机服务产生的 JPEG 字节传给 `publishVideoFrame()`；有深度和位姿时用
   `publishCaptureFrame()` 一次发全 `frame` 通道。
4. 保留 WebSocket 作为回退，不要在一个版本中直接删除旧链路。
5. iOS 已由 `zenoh_ios/` 实现同一套协议，跨端联调直接共用 PC 接收端。

## 已知限制

- 当前没有 TLS、认证和访问控制，只适合可信局域网实验。
- 当前没有真正调用电机，环回按钮只打印解析结果。
- 视频按钮发送的是 1 KB 测试负载；采集帧按钮发送一张 64×48 的合成 JPEG 加单位
  位姿，用来验证 ZPKD 链路，深度和置信度平面要等真实相机管线接入。
- App 需要保持前台；Android 长期后台运行需要前台服务和通知权限。
- 这不是正式生产依赖升级，原有 App 的 WebSocket 行为保持不变。

## 验证结果

- Kotlin：`:app:testDebugUnitTest` 14 项通过（key/endpoint、命令解析、ZFRM 头、ZPKD
  头布局、多平面往返、未知 section 跳过、截断/坏 magic 拒绝、metadata camelCase、
  session 事件）。
- 打包：`:app:assembleDebug` 通过，`app-debug.apk` 约 58 MB，含各 ABI 的 Zenoh JNI 库。
- 跨端：用 Kotlin 编出的 `ZPKD` / `ZFRM` 字节直接喂给
  `zenoh_ios/pc/openbene_receiver/protocol.py`，字段、位姿、metadata 和兼容视频
  全部解析正确，说明同一条 PC 链路能同时接 Android 和 iOS。
