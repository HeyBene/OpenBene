# iOS demo（Swift + ARKit + Vision + CoreBluetooth）

手机装在 OpenBot 上，ARKit 图像锚点负责定位、Vision 负责读二维码，执行器通过 CoreBluetooth 驱动底盘。导航内核是一个独立的 SwiftPM target，可以脱离 App 测试，跟随（tracking）控制器也在里面。

## 构建

```bash
brew install xcodegen
cd IOS && xcodegen generate && open OpenBotAnchorNav.xcodeproj
```

选择真机运行（ARKit 需要真机）。也可以用 `cd IOS && swift test` 只跑算法测试。

`project.yml` 里 `OpenBotNavKit` 是一个 framework target，App 与单元测试 target 都链接它（测试用 `@testable import OpenBotNavKit`），`swift test` 走的是同一份源码。iOS 部分还没有在 macOS/Xcode 上编译过，第一次构建请留意报错。

## 代码结构

| 路径 | 作用 |
| --- | --- |
| `OpenBotNavKit/Sources/OpenBotNavKit/Nav` | 地图模型、Dijkstra、引导、位姿估计、执行状态机（与 Python/Kotlin 同源） |
| `OpenBotNavKit/Sources/OpenBotNavKit/Nav/FollowController.swift` | 跟随控制器（与 Python/Kotlin 同源）：归一化目标框 + 声呐 → 左右轮速 |
| `OpenBotNavKit/Sources/OpenBotNavKit/Robot` | BLE 协议编解码、Mock 链路、模拟机器人 |
| `OpenBotNavKit/Sources/OpenBotNavKit/Geometry` | `MarkerGeometry.swift`：二维码四角 → 锚点位姿 |
| `OpenBotNavKit/Tests` | `swift test` 用的测试（路由距离、引导文案、位姿、锚点数学、跟随控制器、仿真跑完全程） |
| `OpenBotAnchorNav/App` | 目的地选择与状态 |
| `OpenBotAnchorNav/AR` | AR 会话控制器、AR 视图、俯视地图 |
| `OpenBotAnchorNav/Robot` | CoreBluetooth 链路 |
| `OpenBotAnchorNav/Resources` | 地图 JSON 与贴纸 PNG（由 `shared/tools/sync_demo_assets.py` 同步） |

## 运行时提示

* 参考图像在运行时从 PNG 现场创建（`ARReferenceImage(cgImage:orientation:physicalWidth:)`），物理宽度取地图里的 `size_m`。
* `ArNavigationController` 在同一帧里同时尝试图像锚点与二维码：图像锚点优先，二维码作为冷启动/兜底，两者都走同一个 `ArObservation`。
* 会话中断（来电、切后台）会立刻停车。
* 跟随模式：底部 Route / Follow 分段控件切到 Follow 后，目标框来自 Vision 的 `VNDetectHumanRectanglesRequest`（系统自带，无需打包模型），与二维码扫描共用同一帧相机图像。跟随不需要锚点与定位，切换时会先停车；预设是默认的 `FollowConfig`（目标框高度 0.55），现场标定后再落地。
