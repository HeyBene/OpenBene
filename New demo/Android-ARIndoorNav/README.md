# OpenBene AR Indoor Nav（Android · 对标原版 ARIndoorNav）

这是 `New demo/Android`（增强版）的**减法副本**：只保留原版 ARIndoorNav 的那一套模型 —— **一张参考图锚点 + 一条现场采集的节点链 + 复现这条链**，并保留 OpenBot 的 BLE 驱动链路。两个工程并存、互不影响：

| 工程 | 用途 |
| --- | --- |
| `New demo/Android` | 增强版：导入楼层地图 JSON，选房间、Dijkstra 规划、沿折线行驶、途中多锚点纠偏 |
| `New demo/Android-ARIndoorNav`（本工程） | 对标原版：不导入任何地图，App 内采集节点链，之后复现这条链 |

本工程删掉了楼层地图文件、Dijkstra 路由、转向指引、多锚点重定位、二维码（ML Kit 条码）解码与 4 张 OpenBene 贴纸；锚点改为原版 ARIndoorNav 的**两张参考图**（`pi`、`1`）。

---

## 1. 与原版 ARIndoorNav 的对应关系

| 原版 ARIndoorNav（iOS + ARKit + Firebase） | 本工程（Kotlin + ARCore） | 是否等价 |
| --- | --- | --- |
| `Assets.xcassets/ARResources` 里 2 张参考图 `pi`（3 in 宽）、`1`（5 in 宽） | `assets/anchors/pi.jpg`、`assets/anchors/1.jpeg`，宽度写死在 `AnchorSheets.ALL` | 等价（必须按同宽度打印，见 §5） |
| 每个 AR 会话把**第一张**扫到的参考图设为世界原点（`session.setWorldOrigin`） | 把第一张 `AugmentedImage` 的 `centerPose` 记为锚点帧，之后不再改 | 等价：单锚点，一次会话只锚一次 |
| `Create Custom Map`：扫锚点 → `Add` 起点 → `Add` 中间点 → `End` 终点 → `Save` | 同一套按钮与顺序（`Add` / `Undo` / `End` / `Save`） | 等价 |
| 节点只存 `x_offset/y_offset/z_offset`（相对上一节点；第一个节点相对参考图） | 同样的三个量、同样的语义、同样的 JSON 键名 | 等价 |
| 导航时按偏移累加逐个重建节点，放球体 + 连线 + 箭头 | 同样按偏移累加，画球体 + 连线 + 箭头（用相机矩阵投影到 2D 画布） | 等价 |
| 路线存在 Firebase Realtime Database + 自建 Node 服务 | 存在 App 私有目录 `files/routes.json`，**JSON 结构与原版数据库一致** | 存储不同、格式相同（原版导出可直接拷入） |
| 账号/登录/改密/下载地图等 Firebase Auth 界面 | 无 | 本工程不需要 |
| 只有 start / intermediate / destination 三种节点 | 同样三种 | 等价 |
| 没有：中途重定位、多锚点纠偏、回环、ARWorldMap / Cloud Anchor、反向路线、地图规划 | 同样没有 | 等价（都是"单锚点 + VIO 连续跟踪"） |
| 到达判定被注释掉（`ARSceneViewDelegate.swift` 里的 `//self.checkDestinationLoop()`） | 补了"到点停车"（0.30 m） | **差异**：否则底盘不会停 |
| 不驱动任何底盘（纯视觉指引） | 保留 OpenBot BLE 驱动层，可沿节点链行驶 | **差异**：这一层是 OpenBot 集成，不属于原版 |

结论：本工程复刻的是原版的**路线模型与操作流程**；底盘驱动与跟随模式来自 OpenBot 基线（`New demo/Android` 已有），不属于原版 ARIndoorNav 的功能。

## 2. 代码结构

| 路径 | 作用 |
| --- | --- |
| `MainActivity.kt` | 路线列表、新建采集、进入导航/跟随、蓝牙选 OpenBot |
| `RouteStore.kt` | 读写 `files/routes.json`（原版数据库 schema） |
| `AppState.kt` | BLE 选择与 `RobotLink` 构造（没选设备就用 mock 链路） |
| `model/RouteModel.kt` | `RouteNode` / `StoredRoute` / `RouteCodec`（原版 JSON 的编码解码） |
| `ar/ArRouteActivity.kt` | AR 会话、锚点锁定、采集、复现、驱动、跟随 |
| `ar/AnchorSheets.kt` | 两张参考图与物理宽度，运行时构造 `AugmentedImageDatabase` |
| `ar/ArMath.kt` | 4×4 矩阵乘法、点投影、平面位姿（x、−z、yaw） |
| `ar/NodeOverlayView.kt` | 球体 + 连线 + 箭头的投影绘制 |
| `ar/CameraBackgroundRenderer.kt`、`ar/DisplayRotationHelper.kt` | ARCore 相机背景与旋转（来自增强版） |
| `nav/NodeDriver.kt` | 朝当前节点行驶的控制器（先原地转向，再差速前进；声呐 35 cm 停车） |
| `nav/FollowController.kt`、`robot/PersonBoxDetector.kt` | 跟随模式（来自增强版；检测器多传了显示旋转，跟随的左右方向才和画面对齐） |
| `robot/OpenBotProtocol.kt`、`robot/OpenBotBleLink.kt`、`robot/RobotLink.kt` | ESP32 BLE 协议与链路 |

## 3. 算法：锚点帧与节点链

**锚点帧。** 扫到参考图后取 `centerPose` 作为这一会话的参考坐标系；采集时把相机位姿换算到锚点帧：

```text
camera_in_anchor = centerPose⁻¹ · cameraPose
offset_i         = camera_in_anchor.translation − position_(i−1)     // position_(-1) = 0
position_i       = position_(i−1) + offset_i
```

第一个节点的参考点是参考图本身，所以它的偏移就是当时相机相对纸面的三维位置，y 分量约等于相机高度 0.4–0.5 m —— 和原版示例数据里 `start` 的 `y_offset = 0.5` 是同一件事。原版用 ARKit 的 `setWorldOrigin(relativeTransform: anchor.transform)` 做了同一件事，两种实现结果一致。

**复现。** 重新扫到同一张参考图后：

```text
node_anchor = Σ offset_0..i
node_world  = centerPose · node_anchor
```

节点之间按**直线段**连接，每段中点画一个指向下一节点的箭头。节点不是锚点，不能被重新识别；离开参考图之后只有 VIO 连续跟踪，没有任何重定位。

**尺度。** ARCore 用参考图的**物理宽度**确定尺度（`pi` = 3 in = 0.0762 m，`1` = 5 in = 0.127 m，见 `AnchorSheets.ALL`）。打印宽度与代码不一致时，整条链会整体缩放错位 —— 这不是漂移，先查打印尺寸。

**驱动用的平面。** 行驶只看水平量：`x = ARCore world x`、`y = −ARCore world z`、`yaw` 绕重力轴；航向误差大于 15° 先原地转，然后按 `steerGain × 误差` 做差速。声呐 35 cm 内停车、50 cm 以上恢复，到点阈值 0.30 m。

## 4. 操作流程

**采集（Create custom map）**

1. 把手机固定在底盘上，镜头朝前下方约 30–45°；把机器人放在参考图旁边（能扫到纸面）。
2. 点 `Create custom map` → 对准参考图，顶部状态变成 `Anchor locked: pi`（或 `1`）。没锁到之前 `Add` 是灰的。
3. 把机器人推到路线起点 → 点 `Add`（这是 `start`，白色球）。
4. 沿路线推着机器人走，到每个关键位置点 `Add`（蓝色球，中间点）。
5. 到终点 → 点 `End`（终点节点）→ 点 `Save`，输入名字（例如 `door`）。点错了可以 `Undo` 回退一步。

**导航（Navigate）**

1. 主界面点对应路线的 `Navigate`。
2. 把机器人放回参考图附近，对准纸面等 `Anchor locked`。
3. 球体、连线、箭头出现（这就是原版显示的东西）。不开 BLE 时点 `Start driving` 只做**干跑**：界面显示左右轮命令（mock 链路），底盘不动。
4. 要真跑：主界面先打开蓝牙开关 → `Scan for OpenBot` → 选中设备（名字含 `OpenBot` / `RTR_520`）→ 再进 `Navigate` → 锁定锚点后点 `Start driving`。

## 5. 打印锚点图（现场准备）

两张图都在 `../ARIndoorNav-original/markers-to-print/`（与原版 App 里的参考图是同一张文件）：

| 文件 | 内容 | 打印宽度 |
| --- | --- | --- |
| `pi.jpg` | 树莓派 Raspberry Pi 3 Model B 包装盒封面照片（element14 版） | **整张图宽 3 in（76.2 mm）** |
| `1.jpeg` | 织物上手写黑色数字 `1` 的照片 | **整张图宽 5 in（127 mm）** |

两张都是"照片级"纹理，特征点足够，ARCore 检测一般可用；关键是**整张图的宽度**（不是图中某个局部）按上表打印，并且平整贴在地面、避免反光。

## 6. 构建

本机（Windows，Gradle 8.10.2 + AGP 8.5.0 + Kotlin 1.9.24 + JDK 17 + Android SDK 34）已实际编译通过：

```bash
cd Android-ARIndoorNav
gradle --no-daemon :app:assembleDebug          # Android Studio 也可以直接打开本目录
adb install -r app/build/outputs/apk/debug/app-debug.apk
```

产物 `app/build/outputs/apk/debug/app-debug.apk` 约 48 MB（增强版约 63 MB）。本机没有连接 Android 设备，所以只验证到"编译通过 + 打包成功"，**装机运行仍需现场验证**。

本机另有两个只服务本地构建、已列进 `.gitignore` 的文件：`local.properties`（指向 Android SDK）与 `local-mirror.init.gradle`（把仓库切到本地 HTTP 镜像）。仓库里没有 wrapper 的 jar，换机器可以 `gradle wrapper` 先生成。

## 7. 现场测试清单

| 编号 | 步骤 | 期望 |
| --- | --- | --- |
| T1 | 按 §5 打印并铺好锚点图 | 尺寸正确、平整、不反光 |
| T2 | 采集一条 2–3 个节点的短路线 | 状态显示 `Anchor locked`，球体出现在正确位置，`Undo` 能回退 |
| T3 | `adb shell run-as com.openbene.arindoornav cat files/routes.json` | 看到与原版同构的 JSON（`beacon_name` / `node_count` / `nodes.index[].x_offset`） |
| T4 | 主界面进入该路线，干跑（不开 BLE） | 锁定锚点后出现球体 + 连线 + 箭头；`Start driving` 只更新界面上的轮速 |
| T5 | 打开 BLE、连上 RTR_520，再进导航 | 机器人朝当前节点行驶，到点后目标切到下一节点，最后一个节点停下 |
| T6 | 采完一条路线后重新进入同一条路线（新会话） | 只要再扫到同一张参考图，节点链与上一次重合 |
| T7 | 反向走 | 同一次会话内 ARCore 还在跟踪，可以按箭头人工走回去；**没有自动反向路线**，想做反向导航就对着同一张图从另一端起再采一条 |

## 8. 已知限制（必须知道）

* **只有单锚点 + VIO。** 离开参考图后没有中途重定位、没有多锚点纠偏、没有回环、没有 ARWorldMap / Cloud Anchor；长走廊、纹理少、光照变化、镜头遮挡都会漂移。
* **驱动是开环的。** ARCore 只给出"该转多少度、还差多少米"，底盘实际执行了多少并不知道；本工程既不读轮速做里程，也不做速度闭环。原版里这一层并不存在，本工程也没有解决它。
* **没有反馈回路，走偏不会自动纠正。** 只剩到点判定一个保护：声呐默认不发。
* **声呐默认关闭。** 本仓库的 520 底盘没装超声模块，固件仍会 ping：echo 引脚悬空、拾到 trigger 脉冲后上报 1-3 cm，35 cm 阈值会把它读成"墙"，机器人就一直不动。`OpenBotBleLink.enableTelemetry()` 里的 `s` 订阅由文件顶部的 `SONAR_INSTALLED = false` 控制，装上模块后改这一个常量即可恢复避障。
* **轮速不能当里程。** 实测这台 520 的 `w` 帧不随 PWM 变化（-60 与 -150 读数相同）、同一条命令两次相差 60%、中间还有一段读数是 0，最多只能看"轮子在不在转"。数据与结论见 `../ARIndoorNav-original/HANDOVER.zh-CN.md` §3.6.1；本工程的驱动本来也不读它。
* **节点不是地图点。** 它们不能被重新识别，也没有环境特征；换一张参考图或换个纸面朝向，同一条链就对不上了。
* **节点间是直线。** 采集时的转弯路径不会被记录成形状（原版同样只有点）。
* **参考图必须与代码里的物理宽度一致**，否则整条链比例错位。
* **ARCore 检测需要纸面在画面里足够大**；手机装得太低、太斜或地面强烈反光时可能长时间检测不到锚点。
* 到点阈值（0.30 m）、巡航速度（0.30）、转向增益（1.6）都在 `nav/NodeDriver.kt` 的 `DriverConfig` 里，现场按底盘手感调整。

## 9. 与增强版的分工

如果你的目标是"给定楼层地图，选房间，自动规划路线过去"，用 `New demo/Android`（增强版）。本工程只服务另一个目标：**不导入地图，现场走一遍，之后复现这条路**。两者共用同一套 BLE 协议与跟随控制器，可以同时安装（包名不同：`com.openbene.arindoornav` 与 `com.openbene.anchornav`）。

