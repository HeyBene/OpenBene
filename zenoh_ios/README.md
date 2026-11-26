# OpenBene Zenoh iOS transport

独立的 iOS / iPadOS Zenoh 数据传输 SDK 与 PC 端接收、录制工具。工程位于
`zenoh_ios/`，不修改 `openbot-mobile-control/` 或 `apps/robot_app/`，
沿用 `feature/zenoh-android-transport` 定义的 key 与二进制帧格式。

## SDK 简介

手机端的 Zenoh 传输 SDK，附带一套 PC 接收、预览和录制工具。key 与二进制帧沿用 Android
分支，所以同一个 PC 控制台能同时接 Android 手机和 iPhone。

- `OpenBeneZenoh`：纯 Swift 的协议、`ZFRM` / `ZPKD` 编解码、有界发送队列（网络慢时丢帧，不阻塞采集）。
- `COpenBeneZenohBridge` + `Vendor/CZenohPico.xcframework`：zenoh-pico 1.1.0 的 C 桥接。
- `OpenBeneZenohPico`：`PicoZenohSession`，以 client 模式连 PC 上的 router。
- 系统要求：iOS 16 及以上；Swift Package 同时支持 macOS 13+，方便在电脑上跑单元测试。
- 纯原生 Swift，不依赖 Flutter；传输只做数据面，USB/BLE 底盘控制仍由现有 App 负责。

最小接入三步：`ZenohTransportConfig` 填 `robotID` 和 `电脑IP:7447`，调用
`OpenBeneTransport.start()`，之后每对同步好的 RGB / 深度帧调一次 `publish(frame:)`；PC 下发的
命令通过 `onCommand` 分发。

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

### 一条命令启动全部

电脑端所有步骤都在同一条命令里：准备 zenohd、准备 Python 环境、启动路由器、
启动接收端、开启预览页、打开浏览器、结束时清理。

```bash
bash /Users/fandi/Desktop/OpenBene_git/zenoh_ios/scripts/run-pc.sh
```

第一次运行会自动把 zenohd 1.1.0 下载到 zenoh_ios/.tools/、创建 zenoh_ios/pc/.venv
并安装依赖，之后直接启动。运行后自动打开浏览器预览页，并在终端打印手机要填的地址：

```text
==============================================================
 OpenBene Zenoh 已在运行
==============================================================
 电脑端预览   : http://127.0.0.1:8080/
 手机填写地址 : 10.160.3.179:7447
 录制         : 默认关闭，在网页上点「开始录制」
 录制目录     : .../zenoh_ios/runs
 结束全部     : 在本终端按 Ctrl+C
==============================================================
```

按 Ctrl+C 会同时停掉接收端和路由器，并列出本次的录制文件。可选开关用环境变量：

```bash
PORT=7448 bash zenoh_ios/scripts/run-pc.sh          # 换路由器端口
VIEW_PORT=8081 bash zenoh_ios/scripts/run-pc.sh     # 换预览端口
OPEN_BROWSER=0 bash zenoh_ios/scripts/run-pc.sh     # 不自动开浏览器
DURATION=120 bash zenoh_ios/scripts/run-pc.sh       # 2 分钟后自动停止
```

预览页（http://127.0.0.1:8080/）是浅色控制台，包含：

- **RGB / 深度 / 置信度**三路实时画面，按 MJPEG 推流刷新（RGB 上限 30 fps，深度 / 置信度上限 5 fps），不再靠页面轮询；
- **传输状态**：帧率、已收帧、带宽、跳号、帧号、分辨率、跟踪状态、深度来源；
- **IMU**：加速度和陀螺仪的三轴数值与曲线、采样率、电量，超过 2 秒没有新数据会标为暂停；
- **控制小车**：速度与转向滑杆，W/A/S/D 移动、Q/E 弧线、空格停车，按住即动、松开即停；
- **录制**：开始 / 停止按钮、当前文件路径。

电脑端的按键会经 Zenoh 的 openbene/<robot>/cmd 发到手机，手机再用 BLE 驱动小车；
手机若 1.5 秒收不到新的远程指令会自动停车。录制默认关闭，文件落在 zenoh_ios/runs/。

### ARKit 模式与合成模式

两种模式走完全相同的协议、主题和帧格式，电脑端收到的结构一致，只是内容来源不同：

| | ARKit 模式 | 合成模式 |
| --- | --- | --- |
| 图像 | 真实相机画面，1280 px JPEG | 640×480 测试图（带帧号） |
| 深度 | LiDAR 深度，uint16 毫米 | 渐变假深度 |
| 置信度 | ARKit 置信度图 | 伪随机 0/1/2 |
| 位姿 | ARKit camera-to-world 矩阵 + 内参 | 单位矩阵，内参固定 |
| 元数据 | trackingState normal / limited，depthSource smoothed_scene_depth 等 | trackingState/depthSource 均为 synthetic |
| 用途 | 真实采集、录数据 | 权限受限或快速验证链路 |

录制开启后写入 MCAP 的通道：frame/meta（帧号、时间、位姿、尺寸、内参、跟踪状态）、
frame/rgb（JPEG）、frame/depth（PNG）、frame/confidence（PNG），以及 video（兼容的
JPEG 帧）、status、telemetry、sensors、cmd、session 等 JSON 通道。

### 手动分步运行

只在需要单独控制某一环时才用：

```bash
cd zenoh_ios/pc
python3 -m venv .venv && .venv/bin/pip install -e .   # 只装一次
zenoh_ios/.tools/zenohd                              # 终端 1：路由器
.venv/bin/openbene-recv --view --json                # 终端 2：接收 + 预览
.venv/bin/openbene-recv --record runs/now.mcap       # 或者一开就录制
```

--view-host 0.0.0.0 允许别的设备打开预览页，--duration 60 可限制运行时长。
没有路由器时可用 --mode peer --listen tcp/0.0.0.0:7447，但 zenoh-python 1.1.0 的
peer gossip 存在已知崩溃，推荐使用 zenohd。

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

## 在 Windows 电脑上运行

iOS App 不需要任何改动：它说的是同一套 `openbene/**` 主题和 ZPKD 帧格式。Windows 上只把
电脑端换掉即可，功能和 Mac 上一致（实时界面、键盘/滑条控制、按需录制、MCAP 存档）。

先装 Python 3.10 以上（<https://www.python.org/downloads/windows/>，安装时勾选
“Add python.exe to PATH”），然后在本仓库根目录打开 PowerShell：

```powershell
python zenoh_ios\scripts\run_pc.py
```

脚本会自己完成这些事：建虚拟环境并装 `eclipse-zenoh` / `mcap`、首次运行时下载
`zenohd` 1.1.0（x86_64 Windows 版），启动路由器和接收端，打印手机要填的地址，并用
默认浏览器打开实时界面。按 `Ctrl+C` 结束，录制文件在 `zenoh_ios\runs`。

可选环境变量与 Mac 版一致：

```powershell
$env:PORT=7447; $env:VIEW_PORT=8080; python zenoh_ios\scripts\run_pc.py
$env:DURATION=60; python zenoh_ios\scripts\run_pc.py      # 60 秒后自动停
$env:OPEN_BROWSER=0; python zenoh_ios\scripts\run_pc.py   # 不自动开浏览器
```

第一次启动时 Windows 会弹出防火墙提示，要给 `zenohd` 放行**专用网络**的 TCP 7447
入站，否则手机连不上。界面提示的地址（例如 `192.168.1.20:7447`）就是 App
「电脑地址」里要填的值，手机和电脑需在同一个 Wi-Fi。手机端界面地址填好后，点
「连接电脑」即可看到和 Mac 上一样的画面、帧率与录制按钮。

如果手机一直显示未连接，按顺序排查：Windows 防火墙是否放行 TCP 7447；手机是否在
同一网段（部分路由器会隔离客户端）；公司/学校网络是否禁止设备互访；电脑上是否还有
别的程序占用了 7447。

## 安装到 iPhone（测试 App）

`App/` 是一个独立 SwiftUI 测试 App（`com.openbene.zenohdemo`），用 ARKit 采集真实
RGB、深度、置信度和位姿并经 SDK 发送；没有 LiDAR 或不想开相机时可切换到合成测试帧。

生成工程并安装到已连接设备。日常联调请用 **Release**：Debug 的未优化编码循环会让
单帧耗时涨到几百毫秒，表现就是不论选 10 还是 15 fps，电脑端都只有 2–5 fps。

```bash
cd zenoh_ios/App
xcodegen generate
xcodebuild -project OpenBeneZenohDemo.xcodeproj -scheme OpenBeneZenohDemo \
  -configuration Release -destination 'id=<设备 UDID>' \
  -allowProvisioningUpdates -derivedDataPath /tmp/obz-dd build
xcrun devicectl device install app --device <设备 UDID> \
  /tmp/obz-dd/Build/Products/Release-iphoneos/OpenBeneZenohDemo.app
xcrun devicectl device process launch --device <设备 UDID> com.openbene.zenohdemo
```

连上电脑后，「采集设置」里会显示**实际 fps**、整帧**编码 ms**，以及 RGB / 深度换算 /
深度 PNG / 置信度 PNG 的分项耗时。启动时还会跑一次编码基准。iPhone 12 Pro 的 Release
参考值：深度 PNG 约 1–2 ms、置信度约 0.5 ms、1280 px JPEG 约 10–20 ms。若实际 fps 明显
低于设定值，先看这里哪一项占满了帧间隔；合成模式和 ARKit 模式的读数可以互相对照。

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

### App 内：连接 OpenBot 并用键盘操控

App 现在有三个区块，浅色卡片式界面：

- **电脑连接**：Zenoh 地址、机器人 ID、采集源、发送帧数与速率。
- **OpenBot 小车**：扫描并连接 BLE 设备，显示电压、声呐、左右轮转速和碰撞信号。
- **键盘操控**：屏幕上的 W/A/S/D/Q/E 方向键按住即动、松手即停，还有速度与转向滑杆和停车按钮。

接到蓝牙键盘后，点一次「启用蓝牙键盘控制」，之后 W/A/S/D（Q/E 走弧线）直接驱动小车，
空格或 X 停车。按键按住会以 10 Hz 重发指令，松开会立即发送停车；BLE 侧同时每 300 ms
发送心跳，断连或 App 退到后台时固件也会自动停车。

BLE 协议沿用 openbene_sdk：服务 61653dc3-4021-4d1e-ba83-8b4eec61d613，写入特征
06386c14-86ea-4d71-811c-48f97c58f8c9，通知特征 9bf1103b-834c-47cf-b149-c9e4bcf778a7；
指令为 c<left>,<right>\n，心跳 h300\n，遥测订阅 v/w/s。机器人遥测会同时经 Zenoh 的
telemetry 主题发给电脑，和视频帧一起落进 MCAP。

手机与电脑连接时还会把收到的远程 drive/stop 指令映射到同一套按键预设，所以电脑端
send-cmd.sh 发来的命令也能直接让小车动起来。

## 验证记录

- Swift：`swift test` 27 项通过（key/JSON 兼容、ZFRM 逐字节对齐 Android、ZPKD 往返、
  队列丢帧、命令分发、离线状态）。
- Python：`pytest` 12 项通过（黄金字节解析、MCAP 通道与消息体、跳号统计、坏包计数、
  预览页取图、按需开始/停止录制）。
- 本机链路：zenohd 1.1.0 + `openbene-zenoh-demo publish` → `openbene-recv`，
  12 帧 / 12 个兼容视频帧 / 65 条 MCAP 消息，`gaps=0`。

## 已知限制

- 仅支持 Apple 平台；zenoh-pico 以 xcframework 形式内置，Linux/Android 路径未包含在本工程。
- 没有 TLS、认证与访问控制，只适用于可信局域网。
- iOS 后台运行受系统限制，长时间采集需要保持前台或使用合适的后台会话。
- BLE 直连只实现 ESP32 固件的运动与遥测；USB 串口路径仍由现有 App 负责。
- `video` 兼容通道只携带 JPEG；深度、置信度和 pose 只在 `frame` 通道。
