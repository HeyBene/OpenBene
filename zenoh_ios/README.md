# OpenBene Zenoh iOS transport

独立的 iOS / iPadOS Zenoh 数据传输 SDK 与 PC 端接收、录制工具。工程位于
`zenoh_ios/`，不修改 `openbot-mobile-control/` 或 `apps/robot_app/`，
沿用 `feature/zenoh-android-transport` 定义的 key 与二进制帧格式。

## 目录

```text
zenoh_ios/
  Package.swift                      Swift Package（iOS 16+ / macOS 13+）
  Vendor/CZenohPico.xcframework      zenoh-pico 1.1.0（EPL-2.0 OR Apache-2.0）
  Sources/
    OpenBeneZenoh/                   协议、帧编解码、有界发送队列（纯 Swift，可测）
    COpenBeneZenohBridge/            zenoh-pico 的 C 桥接（open/put/subscribe/close）
    OpenBeneZenohPico/               Swift 会话封装 PicoZenohSession
    OpenBeneZenohDemo/               命令行压测/联调工具（非 App）
  Tests/OpenBeneZenohTests/          Swift 单元测试
  pc/
    openbene_receiver/               PC 端接收 + MCAP 录制
    tests/                           协议与录制测试
  scripts/e2e.sh                     本机端到端验证脚本
```

## 数据协议

沿用 Android 分支的 key 约定，PC 一套工具可以同时服务两台手机：

| Key | 方向 | 载荷 |
| --- | --- | --- |
| `openbene/{robot_id}/cmd` | PC → 手机 | JSON 控制命令 |
| `openbene/{robot_id}/status` | 手机 → PC | JSON 在线状态（每 2 s 心跳） |
| `openbene/{robot_id}/sensors` | 手机 → PC | JSON 手机传感器 |
| `openbene/{robot_id}/telemetry` | 手机 → PC | JSON 底盘遥测 |
| `openbene/{robot_id}/video` | 手机 → PC | `ZFRM` 单张 JPEG（与 Android 完全一致） |
| `openbene/{robot_id}/frame` | 手机 → PC | `ZPKD` 多平面采集帧（iOS 主链路） |
| `openbene/{robot_id}/session` | 手机 → PC | JSON 录制起止事件 |

`ZFRM` 是 Android 原型已有的 20 字节头：

```text
magic(4)=ZFRM | version(2) | flags(2) | timestamp_ns(8) | frame_id(4) | JPEG
```

`ZPKD` 在保留同样头部语义的前提下扩展为分节容器，所有整数 little endian：

```text
magic(4)=ZPKD | version(2) | flags(2) | timestamp_ns(8) | frame_id(4) | section_count(4)
section: type(4) | length(4) | payload
  type 1 = RGB JPEG
  type 2 = depth PNG (uint16 mm)
  type 3 = confidence PNG (mono8)
  type 4 = pose float32[16]（列主序 camera-to-world）
  type 5 = metadata JSON（宽高、深度尺寸、内参、跟踪状态、深度来源）
```

未知 section 会被跳过，便于后续加字段而不破坏旧接收端。`publishLegacyVideo` 打开时，
同一帧会额外发布一份 `ZFRM` 到 `video`，供仍在使用旧链路的接收端。

## iOS 集成

Swift Package 通过本地路径加入 Xcode：

1. Xcode → File → Add Package Dependencies → Add Local… 选择 `zenoh_ios`。
2. 目标链接 `OpenBeneZenoh`（协议层）与 `OpenBeneZenohPico`（真实会话）。
3. `Info.plist` 增加本地网络用途说明，真机首次连接时允许本地网络访问。

最小用法：

```swift
import OpenBeneZenoh
import OpenBeneZenohPico

let config = ZenohTransportConfig(
    robotID: "rtr520",
    endpoint: "192.168.1.20:7447",   // 自动补成 tcp/…
    publishLegacyVideo: false
)
let transport = OpenBeneTransport(
    config: config,
    session: PicoZenohSession(endpoint: config.endpoint, mode: .client)
)
transport.onCommand = { command in
    switch command {
    case .drive(let left, let right, _, _, _): /* 交给底盘驱动 */ break
    case .stop: break
    case .unknown(let reason): print(reason)
    }
}
try transport.start()

// 每一对同步好的 RGB / 深度帧调用一次；内部有界队列，网络慢时丢帧而不会卡采集。
let frame = CaptureFrame(
    frameID: frameID,
    timestampNs: UInt64(Date().timeIntervalSince1970 * 1_000_000_000),
    rgbJPEG: jpegData,
    depthPNG: depthPNG,
    confidencePNG: confidencePNG,
    pose: poseColumnMajor,             // [Float] 16 个
    metadata: FrameMetadata(width: 1920, height: 1440, depthWidth: 256, depthHeight: 192)
)
transport.publish(frame: frame)
```

`timestampNs` 建议用墙钟时间；若传入单调时钟（如 `DispatchTime`），PC 端会自动平移到
接收时的墙钟，仅用于录制时间轴对齐。

## PC 端：实时接收与录制

要求 Python 3.10+，安装依赖：

```bash
cd zenoh_ios/pc
python3 -m venv .venv
.venv/bin/pip install -e .
```

先启动路由器（与手机端 zenoh-pico 1.1.0 匹配的版本）：

```bash
zenohd            # 默认监听 tcp/0.0.0.0:7447
```

实时预览（录制默认关闭）：

```bash
.venv/bin/openbene-recv \
  --endpoint tcp/192.168.1.20:7447 \
  --view --record-dir runs \
  --json
```

打开 `http://127.0.0.1:8080/` 就能看到 RGB 实时画面、深度、置信度、帧率、带宽、
跳号、当前帧元数据和最近收到的命令。页面上的「开始录制 / 停止录制」按钮控制是否
写 MCAP，文件落在 `--record-dir`（默认 `runs`），停止后页面仍显示上次文件路径。

需要在脚本里自动开始录制时用 `--record runs/session-01.mcap`；`--view-port` 换预览端口，
`--view-host 0.0.0.0` 允许别的设备打开页面。`--duration 60` 可限制运行时长。没有路由器时可用
`--mode peer --listen tcp/0.0.0.0:7447`，但 zenoh-python 1.1.0 的 peer gossip 存在已知崩溃，
推荐使用 `zenohd`。

录制文件是标准 MCAP，按通道分开保存：

```text
/openbene/<robot>/frame/meta        JSON  帧号、时间戳、pose、尺寸、内参、跟踪状态
/openbene/<robot>/frame/rgb         jpeg
/openbene/<robot>/frame/depth       png
/openbene/<robot>/frame/confidence  png
/openbene/<robot>/video             jpeg   Android 兼容帧
/openbene/<robot>/status|telemetry|sensors|cmd|session   json
```

旁边会写一个 `*.mcap.meta.json` 汇总（消息数、帧数、丢帧空洞、时长、通道统计），
不需要 MCAP 工具就能快速核对。用 Foxglove 或 MCAP 读取库可以直接打开 `.mcap`。

接收端统计里的 `gaps` 是 `frame_id` 跳号数量，用来发现无线链路丢帧；
`decode_errors` 统计格式非法的包。

## 联调工具

不接手机也能验证链路：`openbene-zenoh-demo` 用与 App 相同的发布路径发送合成帧。

```bash
cd zenoh_ios
swift run openbene-zenoh-demo publish --endpoint tcp/127.0.0.1:7447 --frames 30 --fps 10 --legacy-video
swift run openbene-zenoh-demo subscribe --endpoint tcp/127.0.0.1:7447 --seconds 10
swift run openbene-zenoh-demo version
```

`scripts/e2e.sh` 会自动起 `zenohd`、接收器与发布器，并校验录到的帧数。

## 安装到 iPhone（测试 App）

`App/` 是一个独立 SwiftUI 测试 App（`com.openbene.zenohdemo`），用 ARKit 采集真实
RGB、深度、置信度和位姿并经 SDK 发送；没有 LiDAR 或不想开相机时可切换到合成测试帧。

生成工程并安装到已连接设备：

```bash
cd zenoh_ios/App
xcodegen generate
xcodebuild -project OpenBeneZenohDemo.xcodeproj -scheme OpenBeneZenohDemo \
  -configuration Debug -destination 'id=<设备 UDID>' \
  -allowProvisioningUpdates -derivedDataPath /tmp/obz-dd build
xcrun devicectl device install app --device <设备 UDID> \
  /tmp/obz-dd/Build/Products/Debug-iphoneos/OpenBeneZenohDemo.app
xcrun devicectl device process launch --device <设备 UDID> com.openbene.zenohdemo
```

查看已连接设备：

```bash
xcrun devicectl list devices
xcrun xctrace list devices
```

手机与电脑连同一个 Wi-Fi 后，在电脑上运行：

```bash
bash zenoh_ios/scripts/run-pc.sh
```

脚本会启动 `zenohd` 和实时预览页（`http://127.0.0.1:8080/`），并打印电脑 IP；录制默认关闭。
把 `<电脑IP>:7447` 填进 App 的
「电脑地址」，点「连接电脑」。第一次会弹出相机与本地网络权限，都需要允许。连接成功后
App 显示已发送帧数和速率，浏览器里的画面开始刷新。需要存档时在页面上点「开始录制」，
文件写到 `zenoh_ios/runs/`。

反向验证电脑到手机：另开一个终端执行

```bash
bash zenoh_ios/scripts/send-cmd.sh drive 0.4 0.4
bash zenoh_ios/scripts/send-cmd.sh stop
```

App 的「最近命令」会显示收到的 `drive` / `stop`。

## 验证记录

- Swift：`swift test` 19 项通过（key/JSON 兼容、ZFRM 逐字节对齐 Android、ZPKD 往返、
  队列丢帧、命令分发、离线状态）。
- Python：`pytest` 11 项通过（黄金字节解析、MCAP 通道与消息体、跳号统计、坏包计数、
  预览页取图、按需开始/停止录制）。
- 本机链路：zenohd 1.1.0 + `openbene-zenoh-demo publish` → `openbene-recv`，
  12 帧 / 12 个兼容视频帧 / 65 条 MCAP 消息，`gaps=0`。

## 已知限制

- 仅支持 Apple 平台；zenoh-pico 以 xcframework 形式内置，Linux/Android 路径未包含在本工程。
- 没有 TLS、认证与访问控制，只适用于可信局域网。
- iOS 后台运行受系统限制，长时间采集需要保持前台或使用合适的后台会话。
- 当前 SDK 只做传输与录制；USB/BLE 底盘控制仍由现有 App 负责。
- `video` 兼容通道只携带 JPEG；深度、置信度和 pose 只在 `frame` 通道。
