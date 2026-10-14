# ARIndoorNav 原版交接文档（功能界定 · Mac 构建 · 测试清单）

> 范围：本文件只描述「原版 ARIndoorNav」——2021 年 Firebase 版。
> 配套代码：本目录（`New demo/ARIndoorNav-original/`），是上游仓库的**未修改快照**；除本文件与 `markers-to-print/` 外没有任何改动。
> 本轮不测试、不修改 `New demo/Android` 与 `New demo/IOS` 里的增强版 demo。
> 目标：在 Mac 上编译、安装，用 App 采集一条「唯一锚点 → 若干节点」的路线，并用同一张锚点完成导航。

以下路径均相对于本目录 `ARIndoorNav-original/`。

## 0. 结论先行

原版是一个「单锚点 + 链式相对位移」的 ARKit 概念验证 App：

- 扫一张参考图作为起点，把 AR 世界原点锁到这张图上，**整个会话只锁一次**；
- 用 App 现场采集一条由若干虚拟节点组成的路线；
- 导航时按数据里的相对位移重建这条路线，用静态的球体、箭头、连线提示方向；
- 没有中途重定位、没有回程、没有机器人控制，「到达终点」的判定在代码里被停用。

## 1. 来源与快照

| 项 | 值 |
| --- | --- |
| 上游仓库 | https://github.com/bu35/ARIndoorNav （默认分支 main） |
| 快照提交 | `d83cf7c6a6d3b1a7cfceca72b4765d4357d87d73`（"initial commit"，Bryan U `<bu35@drexel.edu>`，2021-06-13） |
| 作者署名 | README 写明 "Created by - Bryan Ung & Allie Do"，联系邮箱 bryanung18@gmail.com |
| 许可 | 上游未提供 LICENSE 文件（默认版权保留，仅供内部验证） |
| 目录 | `ARIndoorNav/`（App 源码）、`ARIndoorNav.xcodeproj`、`ARIndoorNav.xcworkspace`、`Podfile`、`server/`（NodeJS）、`resources/`（数据库导出）、新增 `markers-to-print/` |

容易混淆的两个仓库：

- `Oscheibe/ARIndoorNav`：Unity + C# + ARCore 的另一个项目（TH Köln，2019 年起），与本项目无关。
- `HeyBene/ARIndoorNav`（私人导入版）：本原版的裁剪版——去掉了 Firebase、登录注册、部分地图管理功能，并替换过参考图。验证「原版」时不要用那一份。

## 2. 系统组成与数据流

```text
 iPhone App (ARKit + SceneKit)          NodeJS (express :8080)          Firebase
 ┌───────────────────────┐  HTTP    ┌────────────────────────┐  admin  ┌────────────────────┐
 │ 扫描参考图 / AR 导航   │ ───────> │ /NavigationInstructions │ ───────> │ Realtime Database  │
 │ Create Custom Map 采集 │          │ /DestinationList        │          │  destination/...   │
 │ 本地地图存档（设备）   │ <─────── │ /UploadCustomMap 等     │ <─────── │  users/<uid>/...   │
 └───────────────────────┘          └────────────────────────┘          └────────────────────┘
        └──────────────── Firebase Auth SDK（登录/注册在 App 内直接完成）──────────────┘
```

- 除登录/注册外，App 不直接读写数据库，全部经 NodeJS 服务转发。
- 本地另有一份地图存档（`UserDefaults` + `NSKeyedArchiver`，见 `ARIndoorNav/Model/DataStoreManager.swift`）。

## 3. 功能界定（严格版）

### 3.1 参考图（锚点）：只有 2 张

| 名称 | 文件 | 注册物理宽度 | 打印要求 |
| --- | --- | --- | --- |
| `pi` | `ARIndoorNav/Assets.xcassets/ARResources.arresourcegroup/pi.arreferenceimage/pi.jpg` | 3 英寸（7.62 cm） | 按 3 英寸宽打印（见 `markers-to-print/pi.jpg`） |
| `1` | `ARIndoorNav/Assets.xcassets/ARResources.arresourcegroup/1.arreferenceimage/1.jpeg` | 5 英寸（12.7 cm） | 按 5 英寸宽打印（见 `markers-to-print/1.jpeg`） |

- 宽度来自资产目录里的 `Contents.json`：`pi.arreferenceimage/Contents.json` 写着 `{"unit": "inches", "width": 3}`，`1.arreferenceimage/Contents.json` 写着 `width: 5`。打印尺寸不对会导致定位尺度错误，甚至识别失败。
- `markers-to-print/` 的原始像素：`pi.jpg` 2245×3603、`1.jpeg` 2436×2246；按 3 英寸 / 5 英寸宽度打印相当于约 748 / 487 DPI，清晰度足够。AR 只用**宽度**定尺度，高度按长宽比自动得出，所以打印时保证宽度准确即可。
- 代码只接受这两个名字：`returnBeaconHighlightNode` 里判断 `referenceImage.name == "pi" || referenceImage.name == "1"`。
- 每个 App 会话只把**第一次**扫到的锚点作为定位原点：`session.setWorldOrigin(relativeTransform: anchor.transform)` 只执行一次（`ARSceneViewDelegate.swift:303-311`）。
- 之后再扫到锚点只显示高亮，不参与任何重新定位（`isBeaconRootNodeFound` 置位后直接跳过定位分支）。

### 3.2 采集（Create Custom Map）

入口：主界面左上菜单 → `Manage Maps` → 右上角操作按钮 → 选 `Create Custom Map` → 回到 AR 界面。

AR 界面按钮（见 `ViewController.swift`）：

| 按钮 | 作用 | 出现时机 |
| --- | --- | --- |
| `Add` | 添加节点 | 扫到锚点后出现 |
| `End` | 结束采集（标记终点） | 起点就位后与 Add 一起出现 |
| `Undo` | 撤销上一个节点 | 与 Add 一起 |
| `Save` | 命名并保存地图 | 按过 End 之后出现 |

节点语义与记录方式：

- 第一次按 `Add`：`start` 节点，位移相对**锚点节点**；
- 中间按 `Add`：`intermediate` 节点，位移相对**上一个节点**；
- 按 `End`：`destination` 节点；随后 `Save` 弹出输入框，填地图名保存。
- 每次点击时读取 `session.currentFrame.camera.transform` 的平移列，减去参考节点的位置，得到 `(x_offset, y_offset, z_offset)`（`ARSceneViewDelegate.swift:245-289`）。
- 采集时可以人持手机走，也可以把手机固定在机器人/小车上推着走；App 不区分。
- 保存结果：必写本地 `DataStore`（`UserDefaults`，立刻可用）；上传是单独的菜单动作（`Manage Maps → Upload Custom Maps`），需要登录且 Node 服务在线，会写到 `users/<uid>/destination/<name>`。

### 3.3 导航

两个入口：

1. **服务器路线**：AR 界面右上角放大镜按钮 → `SearchController` 从服务器 `/DestinationList`（数据库全局 `destination/` 表）拉取目的地；扫锚点后向 `/NavigationInstructions` 请求该目的地的节点链。
2. **本地自定义地图**：`Manage Maps` 列表里直接点选之前保存的地图，节点链直接装入会话（不经过服务器），再扫锚点开始。

扫到锚点后（`ARSceneViewDelegate.swift` 的 `setUpNavigation` / `placeNode` / `placeArrowNodes`）：

- 以锚点节点为根，把节点链按 `lastNode.transform × T(offset)` 逐级重建（白色/蓝色球体）；
- 相邻节点之间画圆柱连线；
- 每个节点上方放一个箭头，`arrow.look(at: 下一个节点)` 指向下一节点；
- 引导物是导航开始时一次性放置的静态 3D 物体，之后不随用户位置更新。

到达判定：代码里有 `checkDestinationLoop()`（`ARSceneViewDelegate.swift:419-448`），但调用处被注释掉（`ARSceneViewDelegate.swift:78` 是 `//self.checkDestinationLoop()`），全工程没有其它调用点。**因此原版实际不会提示 "Destination Reached"，也不会自动结束导航。**

### 3.4 数据模型（Firebase 字段）

`resources/ARIndoorNav-database-export.json` 的真实结构：

```json
{
  "destination": {
    "bathroom": {
      "beacon_name": "pi",
      "destination": "bathroom",
      "node_count": 3,
      "nodes": {
        "index": [
          { "type": "start",        "x_offset": 0,    "y_offset": 0.5, "z_offset": 0.2 },
          { "type": "intermediate", "x_offset": -3.3, "y_offset": 0,   "z_offset": 0 },
          { "type": "destination",  "x_offset": 0,    "y_offset": 1.3, "z_offset": 0 }
        ]
      }
    }
  },
  "destination_list": [ { "name": "Bathroom" }, { "name": "Stairs" }, { "name": "Door" } ],
  "users": { "<uid>": { "destination": { "<name>": { "...": "同一结构" } } } }
}
```

| 字段 | 含义 |
| --- | --- |
| `beacon_name` | 该路线采集时用的锚点名（`pi` 或 `1`）。**导航时不校验**（见 4.2） |
| `node_count` | 节点个数 |
| `nodes.index[i].type` | `start` / `intermediate` / `destination` |
| `nodes.index[i].(x/y/z)_offset` | 相对上一个节点的三维位移（第一个相对锚点），单位米，AR 会话世界轴 |

### 3.5 偏移量的坐标系语义（为什么不能手写）

- 采集时：世界原点已经移到锚点上；偏移量 = 点击瞬间**相机位置 − 上一节点位置**，写在 AR 会话世界轴下。
- 回放时：偏移量被当作**上一节点局部坐标系**里的平移链式应用（`node.simdTransform = lastNode.transform × T(offset)`），所有节点都挂在锚点节点之下。
- 结论：一条路线 = 锚点图片局部坐标系里的一串相对位移，不是楼面坐标。**没有采集时的锚点位姿，手工坐标对不上真实环境**；直接改 JSON 数字只有在你知道锚点真实位置与朝向时才可能正确。

### 3.6 定位来源与「是否需要轮子编码器」

- 原版的位姿只来自 ARKit 的 VIO（相机 + IMU）：锚点负责把 AR 坐标系对齐到地图（把世界原点锁到参考图上），之后每一帧的位置与朝向都由 ARKit 连续跟踪给出。
- 节点是采集时记录下来的相对位移，导航时只是把这条链贴回锚点坐标系。**原版不读底盘、不读轮速，因此不需要轮子编码器**；它连车都不需要——人拿着手机走，流程完全一样。
- 需要编码器的场合是「机器人自己开过去」：AR 在长走廊、弱纹理、快速转动、镜头被遮挡时会丢跟踪或漂移，此时轮子里程计（OpenBot 固件通过 BLE 遥测的 w 帧上报左右轮 RPM）可以短时外推位姿、维持控制闭环，等再次看到锚点再把漂移清零。轮子会打滑，轮径与轮距也有标定误差，所以它只能做短时补充，不能替代锚点。
- 结论：验证原版（人持手机，或把手机固定在车上推着走，跟着箭头走）不需要编码器；改成机器人自动驾驶（本仓库 New demo/Android、IOS 的做法）原以为能用轮速补一点，但 3.6.1 的实测说明这台 520 的轮速读数不能当里程用，所以两边都按"没有编码器"来做。

#### 3.6.1 520 底盘轮速实测（2026-10-14）

工具 `New demo/tools/openbot_ble.py`（BLE 直连 `94:E6:86:17:C3:7A`，遥测窗口 `w200`），固件 `openbot/openbot.ino` 的 RTR_520 分支（`TICKS_PER_REV = 209`、`HAS_SPEED_SENSORS_FRONT = HAS_SPEED_SENSORS_BACK = 1`、PWM 5 kHz）。

| 测试 | 命令 | 左轮 rpm（峰值 / 均值） | 右轮 rpm（峰值 / 均值） | 备注 |
| --- | --- | --- | --- | --- |
| 1 | 不发驱动，只收 15 s | 0 / 0 | 0 / 0 | 77 帧全 0 |
| 2 | `c120,0` 5 s | 518 / 197 | 0 / 0 | 未驱动的一侧恒为 0 |
| 3 | `c0,120` 5 s | 0 / 0 | 265 / 136 | 同上 |
| 4 | `c-120,-120` 5 s | -554 / -246 | -341 / -165 | |
| 5 | `c-120,-120` 10 s | -794 / -489（稳态 -721） | -722 / -483（稳态 -722） | 同一条命令比第 4 次高约 60% |
| 6 | `c-60,-60` → `c-100,-100` → `c-150,-150`（各 3 s） | 稳态 -721 → 0 → -722 | 稳态 -721 → 0 → -564 | -60（23.5% 占空比）就到"满速"；-100 段读数是 0 |

结论：

1. **读数确实来自轮子，不是命令回显。** 不发驱动时 77/77 帧为 0；只驱动一侧时另一侧恒为 0；命令取负读数取负；起步有 0 → 19 → 518 → 402 → 392 … 的收敛过程，停车后还有一帧衰减尾巴（第 5 次测试 12.02 s 发出 `c0,0`，12.12 s 仍读到 -658，12.30 s 才归零）。
2. **不能当速度或里程用。** 同一个 `c-120,-120` 两次相差 60%（第 4 次与第 5 次）；-60 与 -150 的稳态读数相同；-100 段读数是 0（原因未查明）。绝对值也对不上：按 `TICKS_PER_REV = 209` 反算，-721 rpm 相当于每路每 200 ms 约 500 个脉冲（约 2500 Hz），而固件注释给出的 530 rpm 电机经 19:1 减速后轮子只有约 28 rpm、每路约 97 个脉冲/秒；即使按"530 rpm 就是轮子转速"的宽松读法也只有约 1846 Hz，仍低于实测。它最多说明"轮子在转、朝哪边转"。
3. **左右不对称**：同一条命令下 518 对 265、-554 对 -341、-722 对 -564，开环差速会持续跑偏。
4. **统计窗口有 200 ms 级滞后**，而 -60（约 23.5% 占空比）就已经到"满速"，可用比例区很窄，低速微调的速度闭环做不了。
5. **硬件线索**：RTR_520 的右侧速度传感器引脚是 GPIO 35 / 36，ESP32 的 GPIO 34-39 是只读脚且没有内部上拉，固件里的 `pinMode(..., INPUT_PULLUP)` 在这两个脚上不生效，线路悬空就会计噪声；左侧（21 / 23）有上拉。
6. **对路线复现的意义**：与原版一致，ARIndoorNav 不读轮速、不依赖编码器；这台车上的轮速也支撑不了"靠里程复现路径"，路线复现只能靠 ARCore / VIO 加节点到点判定。要闭环就得先换成可用的编码器（或带反馈的底盘），并单独做标定。

## 4. 局限（逐条 + 依据）

1. **单锚点、无中途纠偏**：世界原点只锁第一次扫到的锚点；没有 ARWorldMap 持久化、回环检测、位姿优化。长走廊、弱纹理、光照变化造成的漂移会直接叠加到整条路线。
2. **锚点不校验**：服务器只按目的地名查询（`server/database.js` 的 `getNavigationInstructions(destination)`）；客户端组装节点时忽略 `beacon_name`（`Utils/Formatter.swift` 的 `buildNodeListWithJsonData`）；`ManageMapsController` 里读出的 `beaconName` 是死变量。用错锚点不会报错，路线会安静地整体错位。
3. **到达判定失效**：`checkDestinationLoop()` 的调用被注释（见 3.3），无任何其它调用点；不会有到达提示或结束逻辑。
4. **没有反向 / 回程**：数据库只存单方向节点链，UI 也没有返回流程。同一会话内理论可反向，但代码未实现；退出重开后必须重新扫锚点（没有锚点就无法重建坐标系）。
5. **引导物静态**：箭头/连线在导航开始时一次放置，不随位置更新，也不是罗盘。
6. **没有机器人控制**：全工程没有 CoreBluetooth/BLE/底盘代码，不输出控制指令；它只是给人看的 AR 导航。
7. **路线是链式相对位移，不是地图**：无分支、无图搜索、无任意两点间导航；每条路线只能从采集它的那个锚点、按原顺序走。
8. **强依赖自建后端**：作者原 Firebase 项目不可用；必须自建 Firebase（Auth + Realtime Database）并运行 NodeJS 服务。服务不运行时，仅本机已保存地图的采集与导航可用；搜索目的地、上传、下载不可用。
9. **上传 / 下载需要登录**：`Manage Maps` 的 Upload/Download 需要 Email/Password 账号（Firebase Auth）。
10. **换锚点 = 整条重采**：数据挂在锚点坐标系里，换一张锚点图不能沿用旧数据。
11. **采集精度靠手感**：节点误差取决于点击时刻与相机高度；作者样例里 `start` 的 `y_offset` 约 0.5（相机相对地面锚点的高度），中间节点接近 0。
12. **2021 年的工程配置**：objectVersion 51、部署目标 iOS 14、`UIRequiredDeviceCapabilities` 里带 `armv7`。本机运行没问题；若要上架 App Store 需要清理。

## 5. Mac 构建与安装

### 5.0 准备

- macOS + Xcode（含 Command Line Tools），一台支持 ARKit 的 iPhone（模拟器不能跑 ARKit）。
- CocoaPods（`brew install cocoapods` 或 `sudo gem install cocoapods`）。
- 建议 Node 18/20（可用 nvm 管理）。

### 5.1 Firebase

1. 新建 Firebase 项目 → 添加 iOS App，Bundle ID 与工程一致（默认 `com.bryanung`，可在 Xcode 的 target ARIndoorNav → General 里改）。
2. Authentication → Sign-in method → 启用 Email/Password。
3. Realtime Database → 创建数据库（先用测试模式）→ 可选：导入 `resources/ARIndoorNav-database-export.json` 得到示例路线（bathroom / door / stairs，锚点是 `pi`）。
4. 下载 `GoogleService-Info.plist`，放进 `ARIndoorNav/` 目录（与 `AppDelegate.swift` 同级，加入 target）。缺少它 App 启动即崩（`FirebaseApp.configure()`）。

### 5.2 Node 服务

```bash
cd server
# Firebase 控制台 → 项目设置 → 服务账号 → 生成新的私钥，下载后改名
# serviceAccountKey.json 放在 server/ 下
npm install express@4 firebase-admin request
node server.js        # 监听 8080
```

- `server/database.js` 里的 `databaseURL` 必须换成控制台显示的实际地址（新项目一般是 `https://<name>-default-rtdb.<region>.firebasedatabase.app`，老项目是 `https://<name>.firebaseio.com`）。

### 5.3 App

```bash
cd <本目录>
pod install
open ARIndoorNav.xcworkspace    # 用 workspace，不是 xcodeproj
```

- 把 `ARIndoorNav/Utils/Constants.swift` 顶部的 `ipaddress` 改成 Mac 的局域网 IP（手机与 Mac 必须在同一网段）。
- Xcode 里选真机 Run，首次运行同意相机权限。

### 5.4 常见问题

| 现象 | 处理 |
| --- | --- |
| `pod install` 拉不到 Firebase | 换网络/代理；或把 Podfile 里的三个 pod 改成 `FirebaseAuth` / `FirebaseDatabase`（现代 Firebase 不再需要单独声明 `Firebase/Core`） |
| CocoaPods 提示未指定 platform | 把 Podfile 第一行的注释去掉，写成 `platform :ios, '14.0'` |
| App 启动崩溃，日志提到 GoogleService-Info | 5.1 的 plist 没放或没加入 target |
| 搜索目的地报 "Failure to connect/retrieve data from server" | Node 服务没起，或 `Constants.swift` 里的 IP 不对 |
| 上传地图失败 | 未登录，或 `serviceAccountKey.json` / `databaseURL` 不对 |
| 扫不到锚点 | 打印尺寸不对（3 英寸 / 5 英寸）、光线太暗、纸面反光、距离太远 |
| `pod install` 报 "required a higher minimum deployment target" | 见 5.5：抬部署目标，或在 Podfile 里钉 Firebase 10.x |
| 模拟器 | ARKit 不可用，必须真机 |

### 5.5 2026 年首次构建的高概率阻塞点：CocoaPods 依赖解析

本工程没有 `Podfile.lock`，也没有 `Pods/` 目录，所以第一次 `pod install` 会去解析**最新**的 Firebase SDK。而工程的部署目标是 iOS 14.0（`project.pbxproj` 里 `IPHONEOS_DEPLOYMENT_TARGET = 14.0`），Firebase 11.x 起要求 iOS 13+、12.x 起要求 iOS 15+。一旦解析到 12.x，`pod install` 会直接失败：

```text
[!] CocoaPods could not find compatible versions for pod "FirebaseAuth":
  Specs satisfying the `FirebaseAuth` dependency were found, but they required a higher minimum deployment target.
```

两种处理方式，任选一种。两者都只动构建配置，不改业务代码，因此第 3 节的功能界定依然成立。

**选项 A（推荐，跟最新 SDK）**：把部署目标抬到 15.0。

```ruby
# Podfile 第一行去掉注释并改成 15.0
platform :ios, '15.0'
```

同时在 Xcode 里改 target `ARIndoorNav` → General → Minimum Deployments → 15.0（或更高）。

**选项 B（保持 iOS 14）**：在 Podfile 里钉住 Firebase 10.x，并把三个旧式 pod 换成现代名字（`Firebase/Core` 由下面两个自动带入）：

```ruby
platform :ios, '14.0'

target 'ARIndoorNav' do
  use_frameworks!
  pod 'FirebaseAuth', '~> 10.29'
  pod 'FirebaseDatabase', '~> 10.29'
end
```

两种选项下 App 代码都不用改：`Auth.auth()`、`Database.database()` 这些 API 在 10.x / 11.x / 12.x 里都还在。

如果装完 Pod 后 Xcode 报 `armv7` 或 `VALID_ARCHS` 相关错误，把 target 的 Build Settings → ARCHS 设成 `arm64`（本工程 `Info.plist` 里残留的 `armv7` 只影响上架，不影响真机运行）。

## 6. 测试清单

按顺序做，逐步记录现象（这是功能界定的现场证据）：

- **T1 账号**：启动 App → 注册/登录（Profile）。确认不登录也能进入 AR 主界面。
- **T2 采集**：`Manage Maps → 右上角 → Create Custom Map` → 对着 `pi`（3 英寸打印）扫到锚点 → `Add` 起点 → 推进 3–5 m → `Add` →（可再加 1–2 个）→ `End` → `Save` 命名。
  预期：地面出现起点球/中间球 + 连线；Save 后 `Manage Maps` 列表出现该地图。
- **T3 本地导航**：`Manage Maps` → 点选刚保存的地图 → 扫同一张 `pi` → 球/线/箭头出现 → 沿箭头走到终点。
  预期：箭头指向下一节点；**到达终点没有任何提示**（已知局限 3，不是 bug）。
- **T4 服务器路线（可选）**：Node 服务在线 + 已导入示例 JSON → AR 界面搜索按钮 → 选 `Bathroom` / `Stairs` / `Door` → 扫 `pi` → 同样出现路线。
- **T5 反向 / 重启**：到终点后退出 App 重开 → 不扫锚点直接走，确认无法定位（预期失败）；再扫 `pi` 回到起点重走，确认可以。
- **T6 锚点错配（验证局限 2）**：打印 `1`（5 英寸）→ 在没有 `1` 数据的情况下用它扫开 `pi` 的路线 → 观察路线错位且无任何报错。

## 7. 与增强版 demo 的边界

- `New demo/Android`、`New demo/IOS`：自研增强版（4 锚点纠偏、图 + Dijkstra、双向边、BLE 驱动底盘），本轮**不改动、不测试**，原样保留。
- 原版数据（链式相对位移、挂在锚点坐标系）与增强版地图 JSON（楼面坐标 + 锚点位姿）不是同一种东西，不能直接互换。
- 与官方 OpenBot App 的合并（把 AR 导航做成一个新模式）是后续议题，不在本轮范围。

## 8. 附录：关键代码位置

| 功能 | 位置 |
| --- | --- |
| 世界原点锁定 / 锚点处理 | `ARIndoorNav/Controller/ARSceneViewDelegate.swift:303-311` 与 `renderer(_:nodeFor:)` |
| 采集时记录偏移 | 同文件 `getNodeDataAndPlotBuildingNode`（`:245-289`） |
| 回放时重建节点 / 箭头 | 同文件 `setUpNavigation` / `placeNode` / `placeArrowNodes`（`:61-186`） |
| 到达判定（已注释） | 同文件 `:78`、`:419-448` |
| 节点模型 | `ARIndoorNav/Model/LocationInfo.swift`、`DataStore.swift`、`DataStoreManager.swift` |
| 服务器请求 | `ARIndoorNav/Utils/NetworkService.swift`、`ARIndoorNav/Model/NodeManager.swift` |
| 服务端查询 | `server/database.js`、`server/server.js` |
| 数据库字段示例 | `resources/ARIndoorNav-database-export.json` |

---

## 9. 本轮只读核验记录（2026-10-14）

下面的硬结论都在本目录源码上逐条复核过，核验过程没有修改任何原版代码：

| 结论 | 核验位置 |
| --- | --- |
| 只有 2 张参考图，名字必须是 `pi` / `1` | `Assets.xcassets/ARResources.arresourcegroup/Contents.json` 只列这两个；`ARSceneViewDelegate.swift:403` 做名字判断 |
| 打印宽度 3 英寸 / 5 英寸 | 两个 `.arreferenceimage/Contents.json` 的 `properties.width` |
| 世界原点只锁一次 | `ARSceneViewDelegate.swift:307` |
| 到达判定被停用 | `ARSceneViewDelegate.swift:78`（注释掉的调用）、`:419` 起 `checkDestinationLoop` 无任何调用点 |
| 忽略 `beacon_name` | `Utils/Formatter.swift` 的 `buildNodeListWithJsonData` 只用 `node_count` 与偏移量；`ManageMapsController.swift:371` 读出的 `beaconName` 不参与导航 |
| 没有机器人控制 | 全工程无 `CoreBluetooth` 命中 |
| 本地存档 = UserDefaults + NSKeyedArchiver | `Model/DataStoreManager.swift:33-61` |
| 登录不阻塞 AR 主流程 | `Auth.auth()` 只出现在 Form / Profile / ManageMaps 的登录、上传、下载分支 |

---

文档版本：2026-10-12 初版；2026-10-14 修订（补 3.6 轮子编码器结论、3.6.1 520 轮速实测、5.5 依赖解析、第 9 节核验记录）。内容基于快照 `d83cf7c6` 的逐行取证；后续若修改原版代码，请先更新本文件再动代码。

