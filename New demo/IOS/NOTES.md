# iOS 构建与导航修复记录

## 2026-10-15 左转、右转独立 PWM 设置

用户确认上一版测试成功，因左右转向动力不同，要求分别设置转向 PWM。本节是当前行为。

- `NavigationPwmSettings.swift`：将单一 turnPwm 拆成 leftTurnPwm / rightTurnPwm，连同 drivePwm 均为 0～255。继续读取原有 UserDefaults 键；自定义解码兼容旧格式，原转向值分别作为左转和右转初值，保留原直行值。保存时写三个独立字段；损坏或缺失一侧的新格式仍使用原有异常回退逻辑。
- `WaypointExecutor.swift`：依据方向误差符号分别选 leftTurnSpeed 或 rightTurnSpeed。覆盖初始对准、偏航后原地转向及到点朝向调整，保留所有阶段间两秒停车。
- `PwmPulseTester.swift`：左转测试发送 c-L,L，右转测试发送 cR,-R，各自使用对应设置；一秒自动停止和断连/手动停止行为保留。
- `PwmSettingsView.swift`、`ArNavigationView.swift`：新增独立的“原地左转 PWM”“原地右转 PWM”控件，首页/导航摘要显示三项设置。调节先停止测试，保存后手动重启导航，仍只作用于节点航线导航。
- `PwmSettingsTests.swift`：用不同的左右值验证短时测试及导航实际帧；新增旧格式迁移与分别保存，以及到点后左右朝向分别选择正确 PWM 的测试。界面测试改为三项分别调整、保存并重启读取。
- 本轮日志 `/private/tmp/OpenBene-direction-pwm-tests.log`、`/private/tmp/OpenBene-direction-pwm-build.log`、`/private/tmp/OpenBene-direction-pwm-ui.log`。真实左右转向的合适 PWM 仍由用户现场确认。
- SwiftPM 76 项通过，0 失败；模拟器界面测试 1 项通过，三项可分别保存并在重启后读回，已检查截图；真机签名构建通过。原有两秒阶段间隔、一秒测试时长、停车及 BLE 协议保持不变。
- 已更新安装到当前 iPhone 12 Pro 并启动成功，未卸载 App。记录 `/private/tmp/OpenBene-direction-pwm-install.json`、`/private/tmp/OpenBene-direction-pwm-launch.json`。未推送仓库。

## 2026-10-15 新增本机 PWM 调节与短时测试面板

用户明确要求可自行调节发送的 PWM，适应电量和地面差异。本次新增参数设置与手动测试入口，扩展范围仅为该需求；原有节点采集/执行、BLE 协议和动作间两秒停顿保留。

- `NavigationPwmSettings.swift`：分别存储直行和转向整数 PWM，0～255，默认 160。`NavigationPwmStore` 保存至本机 UserDefaults，读取损坏/超范围值时恢复默认。通过 waypointConfig 将已保存值转换成导航命令，保留两秒间隔及 sonarInstalled=false。
- `PwmPulseTester.swift`：显式按钮触发前进、左转、右转；每次最多一秒，持续 tick 保持指令，到时或断连/碰撞即零输出。手动停止后旧 tick 不会重启运动；不使用轮速闭环，也不订阅超声。
- `OpenBotAnchorNav/Robot/PwmSettingsView.swift`：SwiftUI 滑块及步进器分别设置两项 PWM；提供一秒测试、停车、最近控车帧、电压和连接状态。修改数值先停当前测试，保存前只用于本次测试；保存后才用于导航。本机保存值重启可读回。退出或 app inactive 时停车，首页测试面板关闭时释放 BLE 连接。未连接底盘时禁用测试按钮，不要求地图或 AR 定位。
- `DemoSession.swift`、`RootView.swift`：持有设置模型，首页新增 PWM 面板，导航请求携带保存的参数快照。只有首页开启 BLE 并选中底盘，测试面板才创建真实链接；打开面板或保存本身不启动电机。
- `ArNavigationView.swift`、`ArNavigationController.swift`：显示当前直行/转向设置，导航内调节先停车并取消等待；保存后使用新配置重建执行器，需回起点手动重新开始。此入口不提供手动测试，避免导航和测试同时争用连接。
- `PwmSettingsTests.swift`：新增六项测试覆盖保存并重载、异常值回退、自定义参数实际生成导航帧、三种一秒测试输出及自动停止、停止/断连/碰撞后不重启、未连接不运动。`CapturePresentationTests.swift` 新增界面保存/重启持久化测试，并验证没有底盘时测试禁用。
- 算法测试 74 项通过，0 失败；真机签名构建通过。重新生成工程时已保存并恢复原有签名设置。日志 `/private/tmp/OpenBene-pwm-panel-swift-test.log`、`/private/tmp/OpenBene-pwm-panel-build.log`。模拟器 UI 测试 1 项通过，验证两项独立修改、保存、重启后保留、未连接测试禁用；结果 `/private/tmp/OpenBene-pwm-panel-ui-fixed.xcresult`。初次测试使用了不匹配的 SwiftUI 步进器标识，修正为实际标识后通过。已导出截图并检查面板布局。
- 实物的一秒测试、合适 PWM 与不同电量/地面的表现仍需用户架空后现场测量；没有自动驱动真实车辆进行验证。
- 已更新安装到当前 iPhone 12 Pro 并启动成功，保留本地地图与原签名设置。记录 `/private/tmp/OpenBene-pwm-panel-install.json`、`/private/tmp/OpenBene-pwm-panel-launch.json`。未推送仓库。

## 2026-10-15 PWM 160，动作切换停车等待 2 秒

本节为此前固定 PWM 160 版本的历史记录。

- `WaypointExecutor.swift`：转向与直行基础输出改为 160/255，原地转向 c-160,160 或相反，无偏航直行 c160,160，差速微调单轮约 133～187；停车保持 c0,0。对准容差 3°、纠偏阈值 6°、节点朝向容差 5°、到点半径 0.30 m 均保留。
- 新增 waiting 状态和 stagePauseS=2.0：对准后先停车等 2 秒再直行；直行到点后等 2 秒再调节点朝向；节点朝向完成后等 2 秒再转下一段。直行偏航需转向、节点转向后位置超出范围需重新对准，也经过两秒停车间隔。最后节点完成时立即停车结束。
- 等待采用 AR 帧单调时钟截止时间，不使用阻塞 sleep 或延时启动电机的异步回调。等待每帧保持零输出；定位、连接、碰撞与声呐（当前仍禁用）检查继续执行。手动停车或异常会清除待执行阶段；等待结束后依据当时位姿重新检查动作，避免执行过期的直行命令。
- `ArNavigationController.swift` 传入 AR 帧时间；`ArNavigationView.swift` 显示动作间停车两秒的执行顺序；`README.md` 更新使用说明。
- `WaypointExecutorTests.swift` 既有测试改用可控时间验证转向/直行之间的两秒零输出与 PWM 160，完整多节点仿真保留默认等待。新增下一段两秒间隔、等待中定位/连接/手动停止取消动作及重新开始完整计时、等待后重新检查位姿的测试。
- 验证日志：`/private/tmp/OpenBene-160-pause-swift-test.log`、`/private/tmp/OpenBene-160-pause-build.log`。真实底盘的转向过冲、停车距离与阶段切换仍待用户复测。
- SwiftPM 68 项测试通过，0 失败；真机签名构建通过。BLE 协议、心跳、轮速用途及 sonarInstalled=false 均保留。
- 已更新安装到当前连接的 iPhone 12 Pro 并启动成功。记录 `/private/tmp/OpenBene-160-pause-install.json`、`/private/tmp/OpenBene-160-pause-launch.json`。未卸载 App，未推送仓库。

## 2026-10-15 按用户要求将导航 PWM 从 140 提高到 180

本节为 PWM 180 版本的历史记录。

- `WaypointExecutor.swift`：直行基础与原地转向输出均由 140/255 改为 180/255。原地转向 c-180,180 或 c180,-180，无偏航直行 c180,180；接近节点仍保持基础 PWM，停车 c0,0。现有小角度差速微调下，单轮约 150～210。
- `WaypointExecutorTests.swift` 同步实际 PWM 断言；`README.md` 更新当前参数。BLE 协议、轮速用途及无超声模块配置保持原样。
- 本轮测试及构建日志：`/private/tmp/OpenBene-180-swift-test.log`、`/private/tmp/OpenBene-180-build.log`。实车效果由用户继续验证，尚未标记为完成底盘标定。
- SwiftPM 65 项测试通过，0 失败；真机签名构建通过。对准容差仍为 3°，节点朝向容差 5°、到点距离 0.30 m，均未改动。
- PWM 180 版本已更新安装到当前 iPhone 12 Pro 并启动成功。记录 `/private/tmp/OpenBene-180-install.json`、`/private/tmp/OpenBene-180-launch.json`。未卸载 App，未推送仓库。

## 2026-10-15 按用户要求将导航 PWM 提高到约 140

本节为 PWM 140 版本的历史记录，下文的 46 / 31～64 及 2° 是更早版本。

- `WaypointExecutor.swift`：转向和直行基础归一化命令均改为 140/255，实际编码为 PWM 140。接近节点保持该基础输出，去掉此前最低降至 PWM 31 的距离减速；到达 0.30 m 范围仍停车。小角度差速增益不变，6° 内单轮约 117～163。原地转向为 c-140,140 或 c140,-140，正向无偏航直行为 c140,140，停车为 c0,0。
- 提高转向输出后，多节点仿真在原 2° 对准容差下出现来回转向，误差约 2.6° 无法进入直行阶段。将直行前对准容差从 2° 放宽为 3°；方向修正阈值仍 6°，节点记录朝向容差仍 5°。这是本轮必要的参数修正，尚非实车标定结论。
- `WaypointExecutorTests.swift`：在既有到点/朝向测试中补充远处、靠近到点边界仍为 PWM 140、转向 ±140 的断言，并继续验证到点零输出。
- `README.md` 同步最新参数。本次仅调整节点航线导航，未改 BLE 协议、轮速用途、声呐开关、既有跟随算法或未使用的旧 RouteExecutor。
- 修正对准容差后 SwiftPM 65 项测试通过，0 失败；真机签名构建通过。验证日志：`/private/tmp/OpenBene-140-swift-test.log`、`/private/tmp/OpenBene-140-build.log`。实车是否能启动、转向是否过冲，由用户继续架空测试后再确认。
- PWM 140 版本已更新安装到当前连接的 iPhone 12 Pro 并启动成功，未卸载 App。记录 `/private/tmp/OpenBene-140-install.json`、`/private/tmp/OpenBene-140-launch.json`。没有推送仓库。

## 2026-10-15 现场反馈与显示修复

用户确认：离开二维码后航线固定，已不再报“前方有障碍”。采集页首次进入仍黑/白屏，切屏回来可显示。这次继续修复显示时序，未修改导航速度参数。

- `RootView.swift`：设置锚点与采集改为同一个全屏页面内部切换，消除 sheet 关闭后再打开另一个 cover、且依赖另一个可选状态决定内容的时序风险。导航改为 item presentation，一次携带地图、连接及真实/预览模式，移除缺少连接时静默创建 MockRobotLink 的回退。
- `AnchorARSession.swift`、`ArNavigationView.swift`：准备好参考图像后，等 UIKit 的 viewDidAppear、窗口挂载和有效尺寸布局完成才运行 AR 会话。明确开启连续渲染；同时收到相机帧和 SceneKit 实际绘制回调后才撤去启动提示，避免把“相机有数据”误当成“相机已显示”。首次启动仍不重置已固定的地图坐标。
- `OpenBotBleLink.swift`、`ArNavigationController.swift`：导航页显示最近提交给 CoreBluetooth 的 c 帧、时间及可回报的写入错误，供排查电机不动；提交写入不等于底盘应用层已确认收到。根据 RX 特征属性选择写入方式，并检查非响应写入的缓冲可用状态；保持原有协议与 PWM。
- `OpenBotAnchorNavUITests/CapturePresentationTests.swift`、`project.yml`：增加首次/重复进入采集页的 UI 回归，以及只用于真机的首帧实际渲染检查。算法测试目标补 GENERATE_INFOPLIST_FILE，修复真机签名测试时缺少 Info.plist 的构建错误。生成工程前后保留已有签名设置。

验证：App 真机签名构建通过。iOS 18.3 模拟器界面测试通过：首次和重复进入均显示采集控件，无需切屏；真机相机渲染用例在模拟器明确跳过。截图已导出并检查，模拟器画面显示不支持 ARKit 提示及采集控件，不代表真机摄像头验证通过。结果包 `/private/tmp/OpenBene-1015-ui-tests.xcresult`；构建日志 `/private/tmp/OpenBene-1015-signed-build.log`。

真机自动 UI 测试：修复 Info.plist 后已编译，但测试 Runner 安装失败，原因为免费签名 App 数量达到 3 个。没有删除任何现有 App 来腾名额。完整错误及记录 `/private/tmp/OpenBene-1015-device-ui-fixed.log`。主 App 更新安装不需新增 App 名额；采集页是否彻底消除黑屏仍需用户现场复测。本轮未修改算法层，既有 65 项算法测试结果见下文。

主 App 已通过 devicectl 更新安装并启动成功，仍为原 Bundle ID，未卸载现有 App；安装及启动记录 `/private/tmp/OpenBene-1015-install.json`、`/private/tmp/OpenBene-1015-launch.json`。

用户进一步确认：点击开始执行后显示“转向”，可听到电机声但底盘不转。这支持启动 PWM 不足的判断，目前没有电机启动阈值的实测值，未擅自调高输出。

| 阶段 | 当前归一化输出 | App 提交的 PWM（满量程 255） |
| --- | --- | --- |
| 原地转向 | 左右轮 ±0.18，方向相反 | 左 -46 / 右 +46，或左 +46 / 右 -46 |
| 对准后直行 | 基础速度 min(0.25, max(0.12, 距离m × 0.3)) | 无偏航时左右各 31～64 |
| 直行微调 | steer = 1.6 × 方向误差rad；左右分别乘 1-steer / 1+steer | 6° 内差速修正，单轮约 25～74；超过 6° 停车回原地转向 |
| 停车 | 0 / 0 | c0,0 |

控制链：AR 相机位姿 → 首次锚点固定的地图坐标 → WaypointExecutor 的目标距离/方向误差 → 归一化左右轮命令 → 乘 255 四舍五入 → c<left>,<right>\\n → BLE RX。转向至连线误差 ≤2° 后前进；距节点 ≤0.30 m 后停车，转到所记录朝向误差 ≤5°；进入下一节点，末节点完成后停车。轮速 w 仍不参与控制。手机须固定在底盘上，采集/执行保持同样安装方向。

转向 46 与近点直行 31 是此前偏保守且未标定的默认值。下一次标定需在架空状态确定左右轮正反向的实际启动 PWM，再据此修改参数；当前不能把这些默认值描述为已适配 520 底盘。

日期：2026-10-14。OpenBene 基线 `0c34ed2`，本地分支 `codex/ios-first-build`。修改尚未提交或推送；推送前须征求用户同意。

## 构建步骤

仓库位于 `/Users/fandi/Downloads/ARIndoorNav-main/OpenBene`，稀疏检出 `New demo/IOS` 和 `New demo/ARIndoorNav-original`。上游参考位于 `/private/tmp/OpenBot-reference`，提交 `216ecb018ebe26cfae68f15ed42397493d5861c6`；临时目录替代 `~/ref/OpenBot`，避免修改工作区外的用户目录。

```sh
cd "/Users/fandi/Downloads/ARIndoorNav-main/OpenBene/New demo/IOS"
swift test
xcodegen generate
open OpenBotAnchorNav.xcodeproj
```

XcodeGen 2.46、Xcode 26.3，Swift 5.9，iOS 最低 15.0。Xcode 工程被 gitignore 排除，新检出必须生成工程。在 Signing 中选择自己的 Team；Bundle ID 默认为 `com.openbene.anchornav`。本次重新生成前备份已有签名设置，生成后恢复并核验一致。没有修改用户配置的 Team 或 Bundle ID。

```sh
# 算法与 iOS 测试目标编译，不依赖签名
xcodebuild -project OpenBotAnchorNav.xcodeproj -scheme OpenBotAnchorNav \
  -configuration Debug -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO build-for-testing

# 已配置签名的真机 App 构建
xcodebuild -project OpenBotAnchorNav.xcodeproj -scheme OpenBotAnchorNav \
  -configuration Debug -destination 'generic/platform=iOS' build
```

## 本次故障与修复

用户现场报告：采集启动长时间黑屏；导航只在看见二维码时显示识别；扫描二维码会报前方障碍；离开图片后航线漂移并要求重新扫码。

代码确认：原 `AnchorARSession` 在控制器初始化时创建 ARSCNView，在主线程读取图片和准备 ARReferenceImage；`onAppear` 与 scenePhase 可重复重置会话。每个看见图片的 AR 帧都重写地图变换，跟踪受限时又删除变换。导航每 0.3 秒销毁并重画整条航线。BLE 即使不订阅超声，也会解析收到的 `s` 帧并触发避障。另有 BLE 分包数据提前解析、CRLF 字符分隔不可靠，以及只发送一次心跳的问题。

| 文件（相对 IOS） | 改动及原因 |
| --- | --- |
| `OpenBotAnchorNav/AR/AnchorARSession.swift` | 延后创建相机视图，后台解码定位图片和准备参考图像，启动显示进度；会话只初始化一次。首次正常跟踪下识别图片后固定地图变换与地面高度；离开图片继续使用相机位姿，再次看见图片不重新校准。暂时受限保留空间航线并停车。真正中断/后台结束本次会话，要求退出重新进入，避免把旧采集坐标接到重置后的世界中。减少重复发布 UI 状态。 |
| `OpenBotNavKit/Sources/OpenBotNavKit/Nav/FixedAnchorFrame.swift` | 提取单次锚点对齐数学，供相机采集和导航共用并验证。 |
| `OpenBotAnchorNav/AR/MapRecordingView.swift` | 相机准备好后挂载场景；采集点改变时才重绘。inactive 状态不结束会话，避免相机权限提示使初始化中断；background 才结束。 |
| `OpenBotAnchorNav/AR/ArNavigationController.swift` | 场景延后挂载，首次定位/目标节点改变时才绘制航线；跟踪受限不删除航线。已识别状态与当前可用位姿分开。导航和原有跟随都按未安装超声配置运行；轮速遥测仅显示。 |
| `OpenBotAnchorNav/AR/ArNavigationView.swift` | 共用相机准备进度视图，后台停车；不会通过重复 start 重置锚点。 |
| `OpenBotNavKit/Sources/OpenBotNavKit/Nav/WaypointExecutor.swift` | 声呐检查默认关闭。到点容差从上一版实际代码的 0.20 m 调为用户要求的 0.30 m；小角度差速修正，大角度停车后原地转向。保持顺序采集、节点记录朝向和最终停车。跟踪受限时提示等待恢复并回起点，不再误要求反复扫码。 |
| `OpenBotAnchorNav/Robot/OpenBotBleLink.swift` | `sonarInstalled` 保持 false，忽略未安装模块的超声帧。使用完整行遥测缓冲。按上游每 250 ms 发送 h750，断连/关闭取消心跳；停车仍绕过普通控车限频，退出先发送 c0,0 再断链。 |
| `OpenBotNavKit/Sources/OpenBotNavKit/Robot/OpenBotProtocol.swift` | 不改变 UUID、帧编码与 PWM 范围。新增接收缓冲正确处理拆包、多帧和 CRLF；以字节 LF 分隔，避免 Swift 将 CRLF 当一个 Character 导致整行无法解析。 |
| `OpenBotNavKit/Sources/OpenBotNavKit/Nav/RouteExecutor.swift` | 删除读取 w 帧并积分位姿的控制路径。此旧执行器不用于当前采集导航，但同样不能把不可信轮速放入控制回路。 |
| `OpenBotNavKit/Sources/OpenBotNavKit/Nav/RecordedMap.swift` | 直接用采集顺序构造显示航线，移除调用 Dijkstra 的步骤；没有路径规划或反向路线。 |
| `OpenBotAnchorNav/App/RootView.swift`、`DemoSession.swift` | 按此次行为边界移除地图导入入口及应用层导入操作；现场采集、本地保存、导出备份和删除仍可用。 |
| `OpenBotNavKit/Tests/OpenBotNavKitTests/FixedAnchorFrameTests.swift` | 回归：离开标记后的相机位姿、重复识别不移动坐标、跟踪受限保留地图变换。 |
| `OpenBotNavKit/Tests/OpenBotNavKitTests/TelemetryStreamTests.swift` | 回归：BLE 分包与多行、CRLF、无模块时丢弃 1–3 cm 假距离。 |
| `OpenBotNavKit/Tests/OpenBotNavKitTests/WaypointExecutorTests.swift` | 增加无效超声/极端轮速不改变导航的测试、差速修正方向测试；保留多节点位置和朝向完成测试。 |
| `OpenBotNavKit/Tests/OpenBotNavKitTests/ExecutorTests.swift` | 仿真持续提供相机位姿，替代轮速积分；增加轮速不改变旧执行器位姿的测试。 |
| `README.md`、`NOTES.md` | 更新当前使用步骤、参数、验证证据与现场待测事项。 |

## 此前首次构建和现场采集改动

这些修改已在本地工作树中，尚未提交，本次保留：

- `Pose2D.swift`：修正角度归一化错误，原实现错误增加 180°/π，导致朝向和坐标变换异常；`PoseTests.swift`、`MarkerGeometryTests.swift` 补充回归和修正断言/参数顺序。
- `Router.swift`：补齐抛错的 nil-coalescing 表达式所需 `try`，修复 Swift 编译错误。当前 App 的采集路线不调用路由器。
- App 使用算法层的 Swift 文件补充 `import OpenBotNavKit`，修复模块类型不可见错误。
- `project.yml`：去除会覆写 Info.plist 的空 `info.properties` 配置；`Info.plist` 保留相机、蓝牙、定位用途说明以及本地文件访问设置。
- `RecordedMap.swift`、`RecordedMapStore.swift`、`MapRecordingView.swift`、`RootView.swift`、`DemoSession.swift`、`MapOverlayCanvas.swift`：现场采集起点及有序节点的位置/朝向，本机 JSON 持久化，显示航线和朝向箭头。
- 删除 App 资源中的 `demo_floor.json`；测试夹具仍保留，不作为用户地图加载。
- BLE 修复首次 poweredOn 后搜索/连接、RX 发现后才宣布可连接、停车命令不受普通控车限频影响。

## 与上游 OpenBot 对照

先读取了 `../docs/openbot-wheel-telemetry.md`。上游最新 Android 路径已迁到 `org/openbot/app/robot/`，与用户给出的旧快照路径不同。

| 核对项 | 上游证据（所拉取提交中的行号） | 本工程处理 |
| --- | --- | --- |
| 连续相机位姿 | Android `pointGoalNavigation/ArCore.java:196`：camera.getPose()；iOS PointGoalFragment 的相机 presentation.simdPosition | 首次锚点固定后，每帧用 ARFrame.camera.transform；无需图片持续可见。 |
| 到点 | Android `PointGoalNavigationFragment.java:117` 前后 goalDistance < 0.15；iOS `PointGoalFragment.swift:377` distanceThreshold = 0.15 | 用 AR 平面距离，0.30 m，待现场标定；轮速不参与。 |
| 控车来源 | Android 同文件 recognizeImage → vehicle.setControl；iOS `PointGoalFragment.swift:345–357` 策略网络结果 | 保留本工程节点执行状态机，未引入模型或新导航功能；只修正参数与错误。 |
| 帧和左右轮顺序 | Android `Vehicle.java:415–429`，iOS `PointGoalFragment.swift:467–475` | 保持 c<left>,<right>\n；归一化命令乘 255，范围 -255..255。 |
| 轮速 | Android `ControlsFragment.java:193` 解析并存储 RPM；iOS `BluetoothDataController.swift:189` 存储 speedometer | 仅遥测展示，w 不进入任一执行器的控制回路。PoseEstimator 中的旧轮速积分数学方法仅保留为未接入控制的算法兼容代码。 |
| 心跳及停车 | Android `Vehicle.java:448–459` 每 250 ms 发 h750；固件 `openbot.ino:1002` 超时清零控制，`:1386` h 帧刷新计时；iOS `BluetoothDataController.swift:230` 附近 stopRobot 发 c0,0 | 同样周期性心跳，停止先发零控制；不等待不可信的 w0,0。 |
| 差速方向 | OpenBene `NodeDriver.kt`：正方向误差 left 减速/right 加速，大误差左负右正 | 保持同样符号与 steerGain 1.6；机械接线方向仍需架空检查。 |

BLE UUID 保持原样：服务 `61653dc3-4021-4d1e-ba83-8b4eec61d613`，RX `06386c14-86ea-4d71-811c-48f97c58f8c9`，TX `9bf1103b-834c-47cf-b149-c9e4bcf778a7`。遥测 v/w/s/b/f 编码保持不变，无超声模块时不订阅/不应用 s 帧。碰撞 b 事件及定位丢失停车保留。

Python 参考仅运行基线仿真：`run_demo.py --destination 'Room 101' --quiet` 返回 ARRIVED，仿真耗时 49.7 s，距目标 0.44 m。它使用旧预设图和旧执行流程，只作为参考验证，不代表这版 iOS 或真实底盘的精度。

## 当前参数（尚未现场标定）

| 参数 | 当前值 |
| --- | --- |
| 起点允许距离 | 0.30 m |
| 节点到点距离 | 0.30 m（此次从 0.20 m 改回 0.30 m；上游为 0.15 m） |
| 开始直行方向容差 | 2° |
| 偏航重新原地转向阈值 | 6° |
| 节点记录朝向容差 | 5° |
| 直行命令上限 | 0.25，约 PWM 64；接近节点降低至最低 0.12，约 PWM 31 |
| 原地转向 | 0.18，约 PWM 46，左右轮相反 |
| 小角度差速增益 | 1.6 / rad |
| 普通 BLE 控车最小间隔 | 40 ms；停车绕过此限制 |
| 心跳 | 每 250 ms 发 h750，固件超时 750 ms |
| 相机帧中断停止 | 0.6 s |
| 超声模块 | sonarInstalled = false |

按照此前确认的需求，每个节点先完成所记录的朝向，再转向下一段；最后节点的位置和朝向完成后结束。相邻采集点之间假定直线可达。

## 自动验证与真机记录

- 修复前 SwiftPM：57 项通过。
- 修复后 SwiftPM：65 项通过，0 失败。新增 8 项覆盖以上故障。完整日志 `/private/tmp/OpenBene-swift-test.log`。
- iOS App 不带签名构建通过；iOS 测试目标 `build-for-testing` 通过。编译测试目标不等于在 iPhone 执行 XCTest。日志 `/private/tmp/OpenBene-xcode-build.log`、`/private/tmp/OpenBene-xcode-tests-build.log`。
- 最终版本使用原有签名设置构建通过，日志 `/private/tmp/OpenBene-signed-build.log`。没有剩余 Swift 编译错误；构建有 AppIntents 元数据跳过提示，本工程没有使用 AppIntents。
- 检测到已连接 iPhone 12 Pro，原已安装相同 Bundle ID 的 Anchor Nav；通过 devicectl 更新安装并启动，未卸载 App，也未更改地图 JSON 格式。安装/启动日志 `/private/tmp/OpenBene-install.log`、`/private/tmp/OpenBene-launch.log`。
- 实物验证待用户执行：首次上机先架空，确认正向前进、左/右原地转向、节点切换停止与“停车”按钮；再落地。关闭蓝牙预览时采集一条节点链，应用后识别一次锚点，再走离二维码，检查节点/航线是否固定；无需持续面向二维码，不应再报无模块的超声障碍。
- 尚未获得修复版的现场启动耗时、稳定性、方向、到点误差数据；没有把仿真结果当作真机实测，参数未标记为已校准。

## 遗留事项

1. 仍需在真实场景复测黑屏耗时、定位稳定性与底盘方向；安装启动成功不能证明相机识别或控车已现场通过。
2. 单张图像只用于启动时固定地图，没有中途重新校准、地图导入、路径规划或反向路线。AR 长距离漂移仍受环境纹理、光照、手机运动和图像识别误差影响。
3. 手机位置/朝向作为机器人位姿。采集与执行应保持相同安装方向和位置；转向时相机与底盘转轴偏置会影响到点误差。此次未增加外参标定功能。
4. 超声模块未安装；若以后安装，只改 sonarInstalled 并验证读数。若关闭 App 避障后底盘仍自行停住，还需核对实车固件内部超声保护，当前仅确认上游固件心跳逻辑，未修改底盘固件。
5. 跟踪受限或断连后不会自动继续行驶；恢复跟踪并回起点后手动重启本条链。会话中断/切后台后退出重进并识别锚点。原有跟随算法保留，此次没有扩展跟随功能。


## 2026-10-15 提交授权

用户已明确授权将本次 iOS 与 Android/Flutter 改动提交并推送到 `codex/ios-first-build` 分支。本文前面“未提交/未推送”等描述记录的是当时的开发状态；本次提交范围仅为 `New demo/IOS` 与 `New demo/Android-ARIndoorNav`，最终提交与远端状态以 Git 记录为准。

## 2026-10-15：采集阶段显示手机 VIO 轨迹

用户确认只显示手机轨迹，在 iOS 采集页实现。本次不接入 ROS2、原始 IMU 积分或底盘中心外参；使用现有 ARKit 相机位姿，经既有 FixedAnchorFrame 转到锚点地图平面，绘制地面投影。

- 新增 `OpenBotNavKit/.../Nav/CaptureTrajectory.swift`：点击采集起点后开始；约10Hz、水平距离至少4cm采样；记录时间戳、位置朝向和分段标记。跟踪受限、不可用回调、相机帧间隔超过0.6s或时间倒退时断开连续性，恢复后不跨缺失区间补线。只统计有效连续段的距离。最多5000显示点，分批移除旧点，累计距离保留。
- 新增 `OpenBotAnchorNav/AR/PhoneTrajectoryDrawing.swift`：紫色4cm宽地面轨迹和当前位置/方向箭头，与青色节点链区分。以每128段一个网格批量绘制，追加时只更新末批；历史裁剪时重建保留部分，避免每帧重建整条轨迹或创建数千独立节点。
- 修改 `MapRecordingView.swift`：接入现有 `onFrame` / `onUnavailable`，增加轨迹距离、点数、暂停状态与图例。添加/撤销普通节点不会改写实际轨迹；撤销起点会重置轨迹。位置和朝向由现有相机会话提供。
- 新增11项 `CaptureTrajectoryTests`：自动连续采集、采样频率和移动阈值、原地转动、跟踪丢失/恢复断段、相机帧中断、静止时新帧、重复/倒退时间、无效值、历史内存限制、重新采集隔离。
- SwiftPM：87项通过，0失败；日志 `/private/tmp/openbene-ios-trajectory-tests.log`。
- 真机签名构建：通过，保留本机原有 Team；日志 `/private/tmp/openbene-ios-trajectory-build.log`。XcodeGen 已生成包含新文件的工程，签名设置仅保留在忽略提交的本机工程中。
- 地图JSON格式与节点导航/PWM参数未改。轨迹为本次采集显示数据，关闭采集后不持久保存，也不替代节点导航路径。显示仍保留ARKit自身误差，不表示轨迹经过全局建图优化。
- 待真机移动测试：识别标记并采集起点，走L形/弧线检查实际轨迹，不添加节点也应延伸；原地转动不增加距离；遮挡相机后恢复不补直线；普通节点撤销不清空轨迹，撤销起点后清空。使用相机位置，无底盘中心补偿。没有推送此次新增改动。

安装结果：已通过 devicectl 将功能版更新安装到连接的 iPhone 12 Pro，保留原应用数据；安装结果 `/private/tmp/openbene-trajectory-install.json`。尝试执行现有真机相机预览UI测试时，测试 Runner 被系统拒绝安装：免费开发者签名已安装3个App（原ARIndoorNav、另一验证App、Anchor Nav），达到设备额度。此次UI测试**未实际运行**，不能算通过；未卸载任何其他应用。测试日志 `/private/tmp/openbene-ios-trajectory-camera-test.log`。功能App的签名构建和覆盖安装均成功，轨迹的实际空间显示、颜色和移动效果由用户随后实测。

## 2026-10-16：30Hz轨迹归档与30cm带状空间子节点路线

本节覆盖前面历史记录中的“仅显示、不保存轨迹”“相邻人工节点直接连线”和0.30m到点参数。用户已实测上一版采集轨迹基本正常；本次依其新需求加入基于实测轨迹的局部子节点规划，仅改iOS目录，未推送。

### 行为与文件改动

- `CaptureTrajectory.swift`：默认目标30Hz，取消4cm移动门槛；静止时仍记录位姿/朝向。用相机时间戳和固定采样时间格避免60Hz帧间微小抖动降成20Hz，不从缺失帧插值。完整归档最多54000点，显示仍仅保留5000点；显示裁剪不会删除存盘历史。达到上限明确提示、停止追加，不再允许采集新节点，已有节点可保存。点击人工节点会钉住所用AR帧，精确关联采样索引。
- `PhoneTrajectoryDrawing.swift`：轨迹与手机箭头最高30Hz更新，继续采用批量地面网格；文字状态约10Hz刷新。
- `MapRecordingView.swift`：锚点首次识别后，当手机移到锚点中心上方、水平距离10cm内时开始归档。这一实测手机位置保存为“锚点处起始位置”，避免从未采集的位置虚构第一段。沿实际路线走到人工起点，点击记录，再采集各节点；保存包含锚点处→人工起点→依次各人工节点。撤销普通节点不删轨迹，撤销人工起点会清空，需重新经过锚点。规划在后台基于不可变快照完成，显示生成进度，防止主线程长时间阻塞。
- `TrajectoryCorridor.swift`：带状空间为实测二维折线各段半径15cm的胶囊体并集，含圆接转角/端点。候选点先按5mm误差简化；极复杂段逐步放宽到最多30mm，限制512候选点，仍超限时提示增加人工节点分段。简化误差按每个原始顶点到相应简化弦的距离约束；连续原始折线和弦的双向距离不超过该误差。规划检查半宽使用15cm减简化误差、再减4cm控制余量，接受的弦因此仍位于原始30cm带内。
- 连线检查采用解析的线段/矩形及端圆交集，合并各胶囊体在线段参数上的覆盖区间，要求覆盖整段[0,1]，不是只检查端点或固定间隔采样。每对人工节点独立建立按时间排序的可见性DAG；动态规划优先最少直线段数，同数量取更短路线。最优性只针对这些有序实测候选点，未声称任意连续空间中的全局最少子节点。
- `CapturedRoute.swift`、`RecordedMap.swift`、`RecordedMapStore.swift`：v2 JSON保存完整轨迹、人工节点采样索引、锚点处执行起始位姿、各段简化中心线/生成子节点索引与参数。重载会校验连续性、索引、节点一致性、简化误差和每条弦的覆盖。文件上限由2MB提高到32MB，复制保留轨迹/方案。完整原始轨迹不交给导航绘图，只将生成的有序子节点折线交给AR和俯视地图。
- `WaypointExecutor.swift`：v2路线执行自动子节点与人工节点。自动子节点到点后停车2秒，转向下一段，不恢复采集时手机朝向；人工节点仍恢复记录朝向。各阶段2秒间隔、左右独立PWM、BLE帧和仅显示轮速不变。v2到点容差固定为**0.03m**，起始距离容差**0.10m**；旧0.30m会在30cm宽路线的拐角提前转向，不能沿用。每帧检查当前手机位置到当前目标的整条直线仍被保守带覆盖，超出就停车并要求回起点手动重启。跟踪丢失/断连/碰撞仍立即停车。
- `ArNavigationController.swift`、`AnchorARSession.swift`、`RootView.swift`：导航绘制/执行同一份生成折线，自动子节点小圆点不画采集朝向箭头；文案说明锚点处启动和重新采集要求。v1旧地图保留、可预览，但缺少完整轨迹，禁止以未经规划的人工节点直线驱动，提示重新采集。没有Android改动；Android当前不支持此v2格式。

### 验证与现场边界

- SwiftPM：107项测试通过，0失败。新测试覆盖30Hz采样、帧时间抖动、精确钉住人工节点帧、完整归档不随显示裁剪、54000点上限、超过2MB文件重载、直线无冗余子节点、墙角/连续弯道整段覆盖、0.2mm未覆盖缝隙、与穷举对照最少直线段数、人工顺序与朝向、锚点到起点分段、定位中断拒绝规划、保存/重载/副本、坏索引与穿角方案拒绝、自动子节点2秒停车、偏离带停车和模拟底盘完整走完L形路线。日志 `/private/tmp/OpenBene-corridor-tests.log`。
- XcodeGen重新生成工程并保留本机既有Team。真机签名App构建通过；仅有未使用AppIntents的元数据跳过提示。日志 `/private/tmp/OpenBene-corridor-build.log`。本次未重跑此前因免费签名额外App数限制而无法安装Runner的UI测试，未卸载用户任何应用。
- 设备探测：当前Mac列出的iPhone 12 Pro状态为unavailable，尚不能安装本次修订版。已询问用户连接并解锁；连接可用后可直接覆盖更新，保留本机地图/PWM设置。旧地图不会自动获得从未保存过的轨迹。
- 待现场验证：重新采集带墙角的L形或S形路线，确认30Hz显示、重开后子节点折线保持拐角、不出现紫色原始轨迹；先预览、再按既有架空流程确认转向/停车，最后落地验证3cm到点容差与底盘惯性。没有将仿真结果当作真机测量。
- 带状空间约束的是手机VIO中心线，不代表测出了实际墙面，也不包含底盘外形/转动扫掠体积。采集时需留足车身空间；AR漂移、相机相对转轴偏置和真实制动距离仍会影响实际表现。本次没有引入ROS2、额外IMU积分、全局路径搜索或中途重定位。

### 2026-10-16：确认完整采集并安装测试版

用户确认完整采集“锚点→起点→各节点”，与当前实现一致。重新连接并解锁后，已确认测试iPhone 12 Pro通过USB连接、开发者模式启用。通过devicectl覆盖安装本次已构建的App（com.openbene.anchornav）并成功启动，没有卸载旧应用；既有地图和PWM设置保留。安装结果 `/private/tmp/OpenBene-corridor-install.json`，启动结果 `/private/tmp/OpenBene-corridor-launch.json`。此前unavailable为当时连接状态，现已恢复。新路线的实际采集/移动/控车效果仍待用户测试；未推送。

## 2026-10-16：用户反馈初始位置偏差、转向绕圈及左右抖动的诊断

用户报告生成航线看起来正常，但执行时初始定位有偏差，反复转向、偶发转一圈及高频左右抖动；询问从锚点附近任意扫描位置对齐并接入路线的可行性。本轮核对源码并用已构建的真实NavKit做离线复现，未对底盘发送命令，没有替换控制版本。手机具体安装姿态和相机相对底盘转轴的位置已询问，现场根因仍需结合该信息或日志确认。

- 现有FixedAnchorFrame计算markerInAr.inverse().compose(deviceInAr)，本已支持在不重合位置识别固定图片，得到手机相对图片的当前位置。它不会把扫描位置当作地图原点。现有执行入口另要求距采集执行起始位置10cm内，并直接使用原首目标；未生成当前位置的初始接入路线。
- AnchorARSession首次isTracked图像帧立即锁定坐标系，缺少首次观测稳定性确认；之后不再用图片更新。这是可能的初始对齐误差来源，尚不能单凭用户现象断定当次确实发生。图片尺寸、方向和安装姿态需保持约定。
- 确认的控制机制问题：rotate(error)始终发送所设方向的全幅PWM；误差变号立即改向，2秒间隔只应用于状态切换。向现有执行器输入t=0/0.04/0.08秒、航向误差对应+8/-8/+8度，可实际得到PWM160,-160 → -160,160 → 160,-160，phase均为alignLine，没有反向制动/等待。真实延迟和惯性可能触发这种抖动。
- 确认的朝向退化条件：deviceInAr使用相机光轴[0,0,-1]的水平投影当作车头朝向，投影极小时直接返回0。现有几何函数在pitch=-89/-90/-91度时返回yaw=90/0/-90度，跨垂直姿态能产生180度跳变。若手机近乎平放、后摄像头朝地，则此算法不能稳定代表车头；若斜向前安装则需另核查实际误差。
- 确认的转轴不一致风险：v2容差收紧到3cm，节点朝向调整中距点超过4cm会回到位置调整。相机偏离转轴10cm时，原地转90度相机移动约14.1cm。将这一位姿变化输入真实执行器，alignNode会转回waiting/alignLine，形成重复找点/转向的条件。上一版没有做相机到底盘中心的转换，因此仅收紧位置容差不完整。
- 近目标敏感性：目标仅5cm远时，横向位置偏差±2cm能把方位误差变为约∓21.8度；这远大于当前3度直行准入阈值。短接入段或密集近邻节点会放大噪声。
- 可行修正方向：启动阶段多帧稳定确认固定图片→用真实当前位置表达地图位姿→仅在原采集带内生成到采集执行起点或首段的接入路线，保留人工节点顺序→统一底盘中心/车头坐标及相机外参→带制动、稳定判定和反向等待的转向控制→无改善/超时停车。行驶开始后保持锚点坐标固定。当前位置在既有采集带外时，单张图片不能证明额外连接区域无障碍，不能无条件接入。

离线诊断源码和结果：`/private/tmp/OpenBene-turn-diagnosis/main.swift`、`/private/tmp/OpenBene-turn-diagnosis/result.txt`。以上为数学/控制代码复现，不是实车日志或现场测量。此次未推送。

## 2026-10-16：支架处确认出发、首段接入与转向制动修复

用户说明实际流程：手持垂直扫描图片→移动到支架并斜向下固定、设置出发处→取下手机手持采集节点；执行时为点亮开始按钮还需要移动并改变俯仰，之后才固定随车行驶。这说明此前把图片中心10cm范围当作出发条件强迫了安装姿态变化，扫描与车辆路线起点的语义应拆开。已询问相机相对底盘转轴的前后/左右水平偏移；本节尚未取得尺寸，不宣称已完成底盘中心外参校准。

- `MapRecordingView.swift`：取消接近图片中心10cm自动归档。识别图片后先安装支架，显式点击“确认支架处出发位置”再开始30Hz归档，然后采集人工起点和节点。保存的v2 `anchorStart`是这个实测出发位姿，不再强制与图片中心重合；`CapturedRoute.swift`去掉相应10cm校验，仍保留索引0和其余完整轨迹/方案校验。原地图保留；建议用正确支架流程重新采集，以排除手持扫描/装架移动被纳入旧路线的影响。
- 新增 `StableAnchorAlignment.swift`：首次图像观测需位置变化≤2.5cm、方向差≤3°、至少12帧且持续0.5秒，使用位置均值和圆周方向均值；间断或异常重启确认。完成后仍仅锁定一次，不引入行驶中重定位。`AnchorARSession.swift`采用此初始确认。
- `MarkerGeometry.navigationDeviceInAr`：相机光轴水平投影小于0.25时不提供控车位姿，避免镜头垂直朝地下的朝向退化/180°翻转。仍可在这种姿态识别并锁定图片，待斜向前下方装架后再记录或执行。界面明确提示，不用伪造0°车头。该门槛约对应光轴俯仰超过75.5°，不是扫描图片的距离或高度限制。
- 新增 `RouteEntryPlanner.swift`：允许原出发位置附近75cm内、原首段保守带内的实际位姿接入；在首段简化中心线候选点上生成最少直线段的接入链，整条线段需位于既有规划半宽（15cm减简化误差及4cm余量）。保留首个人工终点以及所有后续人工节点，不跳到后段，不假设带外地面可通行。临时接入方案只属于本次执行，不改写JSON。原出发处10cm启动限制已移除；带外仍需移动整台车回到已采集首段，而非俯仰手机“凑”启动条件。
- 新增 `SettledTurnController.swift`，用于v2航线：沿用用户分别保存的左/右PWM力度，按误差大小采用40/100/200ms短脉冲，脉冲间制动至少250ms；误差进入容差后停车稳定350ms，保持阶段有2°滞回。方向误差变号先停车至少2秒再反向。每次转向有8秒无改善、45秒总时限、累计转动270°和快速大角度跳变保护，触发后停车提示。保留各导航阶段2秒间隔。
- `WaypointExecutor.swift`：首段使用上述接入方案；同次对线转向锁定目标航向，避免相机绕偏心转动时持续追逐变化的目标方位。短脉冲额外安排主队列到期停车，缺少新相机帧时也不能延长到原0.6秒跟踪看门狗；带代号取消防止旧回调干扰重启后的直行。人工节点转向期间不立即回到找位置阶段；完成稳定角度判断后若相机位置偏差超过4cm，明确停车报告支架偏心/采集姿态，不宣称位置已到达，也不重复找点转向。尚未取得外参，因此这是终止失稳循环的保护，不是完成外参补偿。
- `ArNavigationController.swift`、`ArNavigationView.swift`、`MapOverlayCanvas.swift`：AR与俯视图同步显示本次接入折线；开始按钮按首段带内条件启用，提示保持支架俯仰不变；停车原因不再被“已定位”文字立刻覆盖。`RootView.swift`、README同步采集与启动流程。
- 编译修复：俯视图初稿直接在App构造NavKit的`NavLocation`，Xcode报 `initializer is inaccessible due to 'internal' protection level`。改为在绘图层使用名称/位置元组，不更改内核公开接口。
- SwiftPM：124项通过，0失败。新增17项稳定定位/接入/制动测试，包括真实Mock链路输出、反向零输出与2秒等待、稳定保持、角度跨±180°、无改善/跳变停止、偏心相机不再反复进入找点、相机不再来帧时到期停车、已取消旧定时器不干扰新直行，以及带40ms指令延迟/180ms惯性的一次正向和一次反向转动仿真。后者为模型验证，非实车参数或标定结果。原L形完整执行和30cm带状空间测试继续通过。日志 `/private/tmp/OpenBene-turn-fix-tests.log`。
- PWM数值、BLE协议、轮速仅显示、无超声模块配置保持原样。原v1地图仍仅预览，新的制动控制接入可执行的v2路线。未修改Android或原版快照，未推送。


### 用户确认：原地角度匹配不引入支架尺寸标定

用户回复偏移尺寸不清楚，并指出此前慢速调整角度只需角度匹配，无需这些参数。按此澄清，将到点与节点转向彻底分阶段：3cm位置判定发生在直行结束时，随后停车2秒、只用稳定角度闭环完成节点朝向；不会在转向中或角度对准后再次因相机绕固定转轴的位移进入找位置阶段，也不以4cm再次拒绝完成。不要求用户测支架偏移；没有新增外参设置或假定支架尺寸。此前本节“朝向完成后超过4cm停车”的过渡实现已被这一行为替代。带状空间、跟踪、蓝牙、碰撞保护仍保留。

增加跨阶段位置进展保护：当前目标30秒没有至少1cm新的距离改善就停车，计时不会随转向/等待/直行切换而重置，避免每次角度都收敛、但短段位置始终无法前进的循环。单个节点推进后重新计时。新增回归测试，完整SwiftPM数量为125项；偏心相机回归现在要求正常完成角度判定并结束，不重复找点。3cm表示转向前的相机到点判定，没有宣称转向后相机还处于同一个3cm圆内。用户手持采集与支架执行应保持车头方向定义一致，优先保持手机装架、手推底盘采集。


最终按用户“只要角度匹配”的要求，节点原地转向不再用相机当前点到目标的连线判定打断角度调整。带状空间的整段连线检查移到每帧直行阶段、等待结束准备恢复直行时，确保转完后使用真实当前位置、符合原带约束才发前进命令；定位/蓝牙/碰撞等停车保护在所有阶段继续生效。新增较大相机旋转位移仍正常完成节点朝向、但不得从带外直接进入下一直行段的回归测试。最终SwiftPM为126项。未假设支架尺寸，也不将相机位置强制吸附到采集点。

最终交付验证：126项SwiftPM测试通过，0失败；真机签名构建通过（仅未使用AppIntents的元数据跳过提示）。已于本次会话通过devicectl将最终版覆盖安装到连接的iPhone 12 Pro并成功启动，保留原地图与PWM设置。最终安装/启动记录 `/private/tmp/OpenBene-turn-fix-install.json`、`/private/tmp/OpenBene-turn-fix-launch.json`，构建记录 `/private/tmp/OpenBene-turn-fix-build.log`。没有执行真实底盘运动；仍需用户按新采集流程架空检查转向/停车，再落地验证，未将仿真当作实车效果。此次未推送。

## 2026-10-16：用户确认航线测试通过；同步跟随PWM并加入跟随采集

用户反馈“导航测试通过”。这是用户现场功能反馈，未提供到点误差/角度误差等测量数据，没有把它记为厘米级精度标定。随后用户发现tracking动力不足，询问是否同步PWM、会否碰到被跟随者，并明确要求把追踪加入采集以替代手推底盘。本节为此新增授权范围；不改已经通过测试的节点执行器。

### 查明的问题

- 原导航页跟随单独使用`FollowConfig()`，转向0.22约PWM56、前进最高0.28约PWM71，接近时再降输出，未读取用户保存的160等导航PWM，容易低于底盘起动能力。
- 原跟随右偏目标发左负右正，与已验证的航线/测试台右转符号相反，小角度差速符号也相反。本次修正iOS内核并更新对应测试；未改Android或Python参考。
- 原跟随在检查距离前先转向，过近而不居中的人仍会触发旋转；Vision请求默认还只检测上半身，不能与全身框的比例阈值混用。Apple说明`upperBodyOnly`默认true，本次显式设置false。来源 https://developer.apple.com/documentation/vision/vndetecthumanrectanglesrequest/upperbodyonly 。
- 当前底盘无超声模块，原跟随只有框大小的相对远近信号，没有可靠的实际距离，更没有不碰撞保证。本次没有假装将框比例换算为可靠米数，也没有开启悬空超声或加入LiDAR。

### 实现与文件

- `FollowController.swift`：修正右转/左转和差速方向，过近先停车；无效人体框不输出运动。新增可选独立左右转值和最低前进比例参数，保留原构造兼容。`NavigationPwmSettings.followConfig`将当前已保存的直行、左转、右转同步传给跟随，前进输出不再按接近比例削弱到电机带不动的值。
- 新增 `FollowExecutor.swift`：需显式开始的单人跟随状态机；默认5秒准备时间，倒计时结束需有3个连续有效新鲜全身检测，否则取消。多人、人体被裁切、检测跳变等情况停车；无目标立即零输出，超过0.35秒无有效检测取消跟随，之后目标出现不自动重启。靠近或进入保持范围先停车，即使目标偏离中心也不继续转向靠近。跟踪/蓝牙/碰撞异常和手动停车取消动作。
- 同一个状态机支持5秒停车设定当前人体大小为本次保持参考，限定有效比例12%至65%；默认40%，属于相对视觉尺度而非米数，不持久写入地图。设定后不会自动开始跟随。
- 跟随保留所设PWM幅度：远处居中按完整基础PWM前进，转向100ms输出/250ms制动；接近保持范围时120ms前进/280ms停车。需要反向纠偏时先停车至少2秒。借短时控制降低平均速度，避免重新回到低PWM带不动的问题。小角度差速单轮会围绕基础值变化，编码范围仍为-255..255。
- 新增 `PersonFollowDriver.swift`：导航/采集共用Vision检测、状态机与BLE命令出口。相机像素按App固定竖屏方向`.right`解释，使用全身请求、置信度≥0.6的检测，不再每帧挑最大人物切换。主队列50ms看门狗在没有新AR帧/人体结果时也会停车。后台Vision结果按代号丢弃，不会在退出/停车/PWM更改后重新发旧命令。未选择实际机器人时跟随禁用，也不运行Vision，手动采集保持可用。
- 新增 `FollowControls.swift`：两页共用开始倒计时、停车、相对保持距离、PWM入口，显示计算指令。明确提示仅单人、全身可见、无防碰撞测距。
- `ArNavigationController.swift` / `ArNavigationView.swift`：用上述共享实现替换旧独立tracking代码；导航PWM参数同时更新跟随，打开参数面板先停车，切模式/退出取消跟随与倒计时。原航线状态机保持不变。
- `RootView.swift` / `MapRecordingView.swift`：从首页已选底盘创建采集用BLE链接；确认支架处出发后才允许跟随采集，30Hz VIO归档/带状规划不变。跟随实际手机轨迹，未把人的位置当节点。采集起点/节点先停止跟随；若刚在运动则用非阻塞2秒等待后获取最新停稳位姿。等待期间按钮禁用；切后台/退出会取消待记录任务，防止迟到回调。撤销、保存、设置PWM、退出和达到轨迹容量上限也停车，不自动续跑。
- 前台暂时失活会停车，但只有进入后台才终止AR会话，避免相机/蓝牙权限弹窗导致初始AR准备被永久结束。`PwmSettingsView.swift`和README同步说明PWM共享范围与新流程。

### 验证及真实边界

- SwiftPM：144项通过，0失败。18项新增覆盖保存PWM的实际c帧、左右独立转向符号、接近时保留PWM但分段停车、过近优先于转向、保持范围内停车、准备时间、行人走入画面、丢失/过期/多人/裁切/跳变停止、跟踪/断连/碰撞取消、无模块虚假声呐和w轮速隔离、相对尺度设定不启动车辆、取消后不自启动、PWM修改先停车和反向2秒零输出。原航线、30Hz采样及带状空间测试继续通过。日志 `/private/tmp/OpenBene-follow-capture-tests.log`。
- 真机签名构建初次通过；XcodeGen已包含新文件，保留本机Team。仅有AppIntents未使用的元数据跳过提示。日志 `/private/tmp/OpenBene-follow-capture-build.log`。构建成功不表示已验证真人跟随距离或碰撞性能。
- 视觉人体框有身高、俯仰、遮挡、误检、目标身份不确定和延迟影响，不能保证不碰到人或其他障碍；没有可信测距硬件，未声称主动避障或安全认证。原始s帧不启用，w轮速不参与控制。
- 待用户架空验证前进/左右转向/停车、丢失和多人时停车；再落地用固定支架验证全身可见、保持参考、目标停止、节点记录先停2秒和完整采集→规划→导航流程。没有替用户发出实车运动命令，未将算法测试当作实车测试。
- 本次只改iOS与其内核/测试/文档；未推送。

最终交付：144项算法测试通过、最终真机签名构建通过。已通过devicectl覆盖安装并成功启动在连接的iPhone 12 Pro，保留原地图和保存的PWM；没有执行真实底盘运动。最终安装和启动结果 `/private/tmp/OpenBene-follow-capture-install.json`、`/private/tmp/OpenBene-follow-capture-launch.json`。真实跟随可见范围、停止距离与采集交互仍需用户现场复测。未推送。

## 2026-10-19：跟随复现日志、恢复上半身检测及沿原路线返程

用户要求排查tracking无响应、从节点返程至锚点，并询问返程后图片校正可行性（明确“先不做”）。此前不实现反向路线的范围限制已由本次明确返程要求更新；没有加入任意路径规划或中途重定位。

### 读取到的真实记录与检测差异

- 首次读取旧版App的Documents，仅有地图，没有人体检测日志；实时syslog约20秒只有CoreMotion运行信息，不能据此判断是否识别成功。新增诊断版于本机12:02安装并启动，随后用户手动复现。中间设备连接曾超时，12:07恢复后安装了含返程的中间版，12:08通过devicectl成功拉取诊断文件 `/private/tmp/OpenBene-follow-device.jsonl`，共84行、74个状态快照，源文件为App的`Documents/Diagnostics/follow.jsonl`。
- 日志第一次进入跟随时`hasRobot=false`，因此未运行检测；后来用户连接底盘，`hasRobot=true`、AR与BLE正常。全身检测确实识别到过单人，置信度多次0.82～0.88，典型推理10～16ms、帧龄约12～16ms；此次没有证据显示350ms过期是主要原因，也没有证据显示Vision报错或模型完全不工作。
- 本机12:06:06及12:06:08记录计算和最近提交BLE均为`c128,142`，12:06:10为`c125,145`；不是从未发出非零指令。最近提交不代表底盘轮子真的转动，没有从遥测推导车辆运动。1Hz快照不是完整逐帧控车记录。
- 随后人体高度34%～45%进入上一版默认40%参考的保持范围，记录`已达到保持距离，停车等待`；进一步贴边时终止跟随。12:06:31的全身框`y≈0.4081,h≈0.5921`，顶端达到约1.0002，被新加的1.5%边界判定拒绝。其后即使重新出现有效框，也必须手动重启，不会自动恢复。
- 对照HEAD的旧`ArNavigationController.scanPerson`：同为Apple `VNDetectHumanRectanglesRequest`，默认上半身；每150ms尝试一次，取最大框，没有显式0.6置信度筛选、连续3帧或贴边检查，有效期0.6秒，`FollowConfig.targetHeight=0.55`。上一版改为全身、参考0.40，增加≥0.6、单人连续3帧、1.5%边界、0.35秒有效期等。不是替换成自定义模型，但检测范围与准入条件改变了。Xcode本地SDK头文件注明revision 2支持全身，默认`upperBodyOnly=YES`；本机Vision查询default/current revision均为2，显式指定revision 2本身不是已证实的故障修复。

### 跟随修复与诊断文件

- `PersonFollowDriver.swift`恢复旧tracking的上半身范围（`upperBodyOnly=true`），保留显式revision 2；初始化`FollowExecutor`时传入匹配的0.55参考，避免混用全身0.40。该参考仍可用“设定距离”覆盖，不作为米数。保留保存PWM共享、正确转向符号、多人/过期/贴边停止和手动重启，没有为了复现放宽置信度或取消停车。
- `FollowExecutor.swift`允许注入检测尺度参考；启动失败显示未检出/贴边/稳定帧不足/有效帧龄，保持停车显示实际框高与阈值。App上半身默认保持停车门槛为46.75%（55%×0.85），不再是全身版34%。内核通用构造默认0.40兼容原有测试和调用，App明确传0.55。
- 新增`FollowDiagnostics.swift`，共用导航/采集检测链写本地JSONL与syslog，记录原始框和置信度、检测错误与耗时/帧龄、AR/BLE状态、当前PWM、计算c帧、最近提交BLE帧与停车状态；每秒状态快照，启动/停止有事件。不保存照片或视频。约2MB轮转并保留上一份。退出或后续重试仍可读取，不再吞掉所有Vision错误而只显示0人。
- `FollowControls.swift`显示上半身原始/筛选后人数、耗时、帧龄和框稳定/贴边原因，说明文字改成上半身检测。新增诊断代码首次构建遇到Swift闭包类型推断超时，拆成`detect`/`receive`函数后编译通过。

### 返程实现

- `RouteEntryPlanner.swift`新增反向遍历指定人工节点之前的路线前缀，保留所有原子节点、人工节点及原带状空间编号；不改存储JSON。反向首段也可从节点75cm内的实际位姿在原保守带内最少直线段接入，完整连线校验不变，不能穿墙直达锚点。旧地图若缺`anchorStart`则不开放返程，需完整重新采集。
- `WaypointExecutor.swift`复用同一执行状态机与原始带状走廊，返程使用反向顺序，但仍先原地转向、停车2秒、向前直行、人工点转到记录朝向。没有反转BLE前进符号或用w帧进入控制。终点是采集时确认的锚点旁支架位置与朝向，不能误写为纸张中心。
- `ArNavigationController.swift`/`ArNavigationView.swift`提供去程/返程选择、人工返程出发节点选择、倒序AR/俯视图预览；保留最近到达的人工节点作为默认选择。只在停车状态切换方向与节点，点击“开始返程”才运动，去程完成后不自动返回。停止原因不被定位提示覆盖，切路线清理前一执行的进度与状态。
- 返程依赖同一AR会话的连续VIO；后台/会话终止后不能从远处节点凭空恢复坐标。回锚点后可设计停车→稳定识别原图片→重算坐标对齐→按记录出发位姿调整，但此次明确未实现图片重识别、漂移校正或二次位置修正。当前返程恢复的位姿仍有VIO累计漂移，位置确认和朝向确认按既有分阶段规则执行，不宣称无误差重合。

### 验证

- 新增`ReturnRouteTests.swift`7项，覆盖反向前缀/走廊编号、从中间节点返回不包含后段、邻近真实位姿接入保留墙角与人工点、带外/错误节点/缺轨迹拒绝、从每个人工节点返回出发位姿的底盘仿真、先转向与2秒停稳后向前、跟踪失效立即停止且不自恢复。
- `FollowExecutorTests.swift`新增2项，覆盖可区分的启动失败原因与上半身0.55参考下按保存PWM输出/保持停车。测试是算法与仿真，不等价于上半身实车跟随或实车返程已通过。
- 最终算法测试、签名构建及设备更新结果见本节末尾。没有通过工具启动车辆运动，用户诊断操作产生的非零帧不属于自动工具控车。改动仅在`New demo/IOS`，未推送。

最终交付：153项SwiftPM测试通过，0失败（`/private/tmp/OpenBene-return-tests.log`）；真机签名构建通过（`/private/tmp/OpenBene-return-build.log`），仅未使用AppIntents的元数据跳过提示。最终恢复上半身检测/55%参考并含返程的App已于本机12:12通过devicectl覆盖安装并成功启动在iPhone 12 Pro，保留地图及已保存PWM。安装/启动记录为`/private/tmp/OpenBene-return-install.json`、`/private/tmp/OpenBene-return-launch.json`。`git diff --check`通过，未改iOS之外文件。真实日志确认的是此前全身版的检测与控车提交；恢复上半身后的真人跟随、实际制动距离、实车返程仍待用户测试。此次未推送。

## 2026-10-19 后续：关闭跟随门槛做基线，移除距离设定，上边界单项实验

用户反馈仍无驱动，明确要求暂时关闭制动门槛、逐项测试，取消距离设定，提出以上半身即将超出上边缘作为停车标准；下半身识别只询问、不修改。按此更新实现；此前全身/上半身比例设定与强制过滤的行为由本节取代，不影响已通过现场测试的节点导航与返程逻辑。

### 最新实机证据

通过devicectl读取`Documents/Diagnostics/follow.jsonl`到`/private/tmp/OpenBene-follow-latest.jsonl`。用户这轮13:41～13:43（北京时间）的三次开始，前两次分别因贴边、多人条件在准备结束后拒绝启动；第三次记录过前进、左转和转向间歇制动，随后超过0.35秒无有效检测而终止。典型Vision推理仍约12～14ms；没有把未识别/多人误检归为PWM问题。末次13:48创建页面但没有enable=true事件，不据此声称模型运行过。

该手机日志明确保存直行PWM135、左转172、右转172，低于仓库默认160的直行值。本次保留用户已保存参数并在跟随卡片直接显示，不强制改写。发送c帧只代表提交控制，不是轮子转动证据。

### 代码变动与控制逻辑

- 新增`FollowTestOptions.swift`：9项独立开关全部默认false，页面内生效，不持久化为日常运行设置。包括置信度≥0.6、单人、连续3帧、四边1.5%空隙、跳变、0.35秒严格过期、转向脉冲、左右反向前2秒等待、上边界停车。没有一键全开。更改任何开关或阈值先停、清除旧检测并取消旧异步结果，需手动重新开始。`PersonDetection`把真实置信度带入可单独测试的内核。
- `FollowExecutor.swift`移除人体大小参考、设定距离/校准任务、宽度停车、接近时120ms前进/280ms制动。默认一个有效框即允许跟随，多框取最大有效框，与原tracking选择方式一致，可能切换目标，不宣称身份追踪。基线按保存PWM连续输出，不因为框高/宽或原始贴边条件制动。保留5秒明确准备时间，不测距离、不记录比例；结束时必须有有效新鲜目标，否则取消，不在稍后突然启动。
- 默认无有效目标立刻零输出，超过0.6秒取消跟随；只有单独开启严格过期才收紧到0.35秒。手动停止、无效数值、相机/AR跟踪不可用、BLE失联、碰撞事件、后台等原有停车仍生效，不取消通信心跳，也不让车失去目标盲开。此基础失效停车不属于被关闭的新增视觉/制动门槛。
- `FollowController.followCommand`新增`maintainVisualScale`参数，默认true保留原通用算法调用；当前App跟随明确传false，绕过所有人体框大小保持判断，并使用完整基础PWM。其他调用/旧算法回归保留，不修改Android。
- 上边界独立实验默认关闭：开启后以可见相机画面中上半身框顶距离上缘≤5%为停车条件，可调0～20%。触发即结束本次跟随，无论原来直行还是转向；移开并手动开始后才恢复，不自动跟着下一帧继续。不存在米数换算，没有保证该图像位置始终随靠近单调变化，安装俯仰/弯腰/遮挡等仍需现场逐项验证，不作为防碰撞保证。
- `PersonFollowDriver.swift`维持Apple Vision revision 2上半身检测。检测框通过撤销Vision `.right`方向后应用`ARFrame.displayTransform(.portrait, viewportSize:)`并裁到可见画面；引擎转向、上边界条件、绿色框共用显示坐标。记录原始框/置信度和实际可见框，避免相机图像与屏幕裁切导致门槛含义不一致。采集/导航控制器传实际SceneView尺寸，VIO的30Hz轨迹采样不改。
- `FollowControls.swift`删除“设定距离”，新增“门槛单测”表单、逐项开关和上边缘阈值滑块。导航与采集预览增加同一`FollowDetectionOverlay`绿色目标框/红色停车线。卡片显示保存PWM、计算c帧、最近提交BLE帧、启用门槛与阻塞原因。原节点采集动作仍先停车2秒再记录，这与被关闭的跟随转向/接近制动不同。
- 下半身没有实现：现用人体矩形请求仅有上半身/全身开关。Apple人体姿态API提供髋、膝、踝关键点，可作为另一个下半身跟踪方案，但仅见腿时能否稳定识别需另验；没有把裁剪全身框当作已实现的腿部检测。文档依据：Apple `VNDetectHumanRectanglesRequest.upperBodyOnly`及`VNHumanBodyPoseObservation.JointName`。

### 验证与交付

- 重写21项`FollowExecutorTests`覆盖默认无门槛下单帧/近大框连续前进、保存的独立左右PWM连续转向、5秒只作准备、过时启动取消、置信度/单人/3帧/四边/跳变/严格过期/转向脉冲/反向等待各自单独开启的效果、上边界优先于前进/转向且不自恢复、阈值可调且不依赖框高、更改配置/PWM停车、无目标立即零输出、相机/断连/碰撞/无效数据仍停车、假声呐及w轮速隔离。替换了原距离设定/保持等已移除行为的测试，没有保留与当前需求冲突的断言。
- **154项SwiftPM测试通过、0失败**，包含原轨迹、带状路线、转向稳定与返程回归；日志`/private/tmp/OpenBene-tracking-gates-tests.log`。真机签名构建通过，只有未使用AppIntents的元数据提示；日志`/private/tmp/OpenBene-tracking-gates-build.log`。XcodeGen更新包含新源文件并保留Team。
- 最终版已于北京时间14:08安装到iPhone12Pro并成功启动，保留原地图及PWM。设备记录`/private/tmp/OpenBene-tracking-gates-install.json`、`/private/tmp/OpenBene-tracking-gates-launch.json`。没有通过工具启动车辆。用户需先架空测默认连续输出，再只开一个条件验证；绿色框与本人对齐、真实电机动作、真实上边界触发效果仍待现场验证。
- 改动限于`New demo/IOS`；`git diff --check`通过。未推送。

## 2026-10-19 后续：跟随停后继续、转向滞回、VIO临时中断自动恢复

用户现场反馈tracking已能驱动且会在前方停车，但目标再移动后不续跟、转弯表现不佳；返程转向有时失去位置，手动再次开始后可继续，希望自动恢复。本节更新此前“视觉临时停车后必须手动重启”的行为，保留手动停车与失联等明确取消操作。

### 现场证据和结论边界

- 读取实际`Documents/Diagnostics/follow.jsonl`到`/private/tmp/OpenBene-follow-resume-device.jsonl`。这轮日志出现大量`超过0.60秒无有效目标，已停车；请重新开始`，代码也确实把此条件设为`active=false`，所以之后新人体框不能恢复输出。
- 这批记录的`enabledGates=[]`，没有上边界开关的触发记录；不能把用户说“在人前方停止”直接归因于上边界实验。日志可确认的是检测丢失后的永久终止，不能证明实际停车距离。
- 日志实际提交过`c172,-172`与`c-172,172`，因此不能说此前根本没发转弯指令。PWM仍为直行135、左/右172，不擅自提高。旧居中条件10%以内只给小幅差速，可能不足以明显转弯；临时目标丢失与AR受限还会结束跟随。本次修正这两条软件路径，不声称已测出底盘机械转向能力。
- 此前没有导航执行阶段日志，尚不能根据用户一句“丢失位置”确认是AR受限、朝向跳变还是不收敛超时。本次覆盖可恢复的临时AR受限/朝向跳变，增加导航日志用于进一步区分；没有把所有转向失败一律自动重启。

### 跟随控制

- `FollowExecutor.swift`：无目标/过期即刻零输出，但保留当前跟随授权，继续等新鲜有效人体；新人体可见后按最新位置恢复，无需再点开始。不朝最后看到的方向盲转搜索。可选单人、四边、跳变条件触发也改为暂停；这些条件仍各自独立且默认关闭。
- 上边界停车改为禁止向前平移、允许原地转向对准人物。框顶≤所设阈值进入保持；远离上边缘到阈值+3%才自动恢复前进，避免停车线附近抖动。默认5%时释放位置为>8%。没有恢复按人体大小设距离，也没有加入测距/下半身模型。
- 横向偏离中心超过6%进入原地转向，回到2.5%内才释放为直行，使用所保存的左/右PWM；中间区域保持已有转向状态，避免原10%门槛下只靠微小差速而不明显转弯，或在一个边界反复切换。近上边缘时只发送对转两轮，不混入前进。
- AR短暂受限时停车保留跟随状态，正常跟踪持续0.5秒后再用新鲜人体继续，最长等15秒；启动准备期间相机不可用仍取消启动。BLE断开、碰撞、手动停车、退出、后台、会话结束、改PWM或门槛等仍取消，不自动恢复。
- `FollowControls.swift`同步等待恢复/自动继续、上边界释放差和近时仅转向的说明。

### 节点导航与返程恢复

- `WaypointExecutor.swift`新增`recovering`阶段（仅完整v2路线），暂停时保留当前目标及走廊编号，取消旧转向脉冲定时器并清空旧航向误差状态。不会重新从所选返程人工节点跑一遍，也不会跳过当前子节点。
- 相机跟踪暂时受限、没有有效位姿时先停车等待；恢复位姿需在停车前位置30cm/朝向45°以内，且在0.5秒窗口内位置变化≤3cm、角度变化≤3°、至少6帧、相邻帧间隔≤0.2秒。稳定用窗口首帧为参考，不能由每帧小变化累积成明显漂移后仍判稳定。超出连续性范围时保持零输出等待，不能把不同AR世界坐标强行接到原地图。
- 确认后停车2秒，再从最新位姿重算当前线段方向；若暂停前已处于人工节点朝向阶段，则继续该阶段，不因相机绕车轴位移重新找位置。直行前仍完整检查连线在原带内。暂停时间从跨阶段位置进展计时中扣除，没有无限重置位置进展条件。
- 最长等待15秒，同一目标最多3次自动恢复；超过后明确停车要求现场检查。`SettledTurnController.poseJumpDetected`区分朝向瞬跳与一般转向失败：瞬跳进入有界恢复等待，8秒无改善/45秒不收敛/累计270°/PWM为0仍终止，不自动无限旋转。v1内核兼容路径仍不自动恢复，App本来就不允许v1驱动。
- `AnchorARSession.swift`把临时`onTrackingLimited`与会话结束`onUnavailable`分开；没有新建AR会话、重扫图片或移动地图坐标。`ArNavigationController.swift`不再在临时受限时清除isArmed，使用独立健康检查在完全缺帧时也执行暂停/超时；AR回调与健康检查统一用主机单调uptime计时，避免相机采集时间略早于回调时间导致刚暂停就被误判时钟倒退。真正会话结束仍永久停止。
- `MapRecordingView.swift`允许跟随在临时受限后恢复，但原始VIO采集照旧断段、不跨缺失轨迹补直线。节点记录的停车2秒、地图规划和存储格式不变。
- `FollowDiagnostics.swift`复用数字轮转日志实现，新增App `Documents/Diagnostics/navigation.jsonl`，记录去/返程、执行阶段、目标索引、位姿、角度/距离误差、恢复次数与原因；跟随日志保留。没有保存图像。

### 验证

- **166项SwiftPM测试通过，0失败**，日志`/private/tmp/OpenBene-auto-resume-tests.log`。跟随新增/更新了丢人后自动继续、上边界保持与释放滞回、近时仅转向、转向更早进入且居中后释放、相机临时受限确认后继续、手动停止不再恢复等回归。
- 导航新增/更新同一返程目标恢复、恢复确认期间不动、离散帧/缓慢漂移不通过稳定窗口、大幅坐标变化不自动接入、15秒超时、最多3次恢复、手动/断连取消、人工节点朝向阶段保留、瞬时角度跳变后重算实时方向、恢复后仍拒绝带外直行等测试。
- 完整返程底盘仿真分别在航线转向、直行、人工点朝向时插入0.4秒VIO中断；无需再次start即可最终到达原出发位置/朝向，持续在原15cm半宽带内。这是算法与仿真结果，尚不是恢复版实车效果。
- 真机签名构建通过，日志`/private/tmp/OpenBene-auto-resume-build.log`；没有增加框架或更改BLE协议。代码只在`New demo/IOS`，未推送。最终设备安装/启动结果补记如下。

最终交付：统一回调/健康检查时钟的最终版已于北京时间14:43覆盖安装、14:44成功启动在连接的iPhone12Pro，保留地图与PWM；记录`/private/tmp/OpenBene-auto-resume-install.json`、`/private/tmp/OpenBene-auto-resume-launch.json`。166项算法测试与签名构建通过；`git diff --check`通过，未修改iOS以外文件。没有通过工具执行真实底盘运动。恢复后的真实跟随转弯、停车再继续与返程恢复仍需用户现场测试；此次未推送。

## 2026-10-19 后续：YOLO跟随、连续差速及返程末端图片归位

用户现场反馈跟随持续左右摇摆，提出对照OpenBot的YOLO Object Tracking；返程路线已基本通过，但希望末段转向时重识别图片，纠正到原采集出发位姿。本节替代上一节的6%进入/2.5%退出的原地转向跟随规则，并仅在返程末端加入用户此次明确要求的图片归位。普通去程/返程中途不重定位。

### 对照与模型

- 读取官方OpenBot上游`ob-f/OpenBot`提交`97d93d74fb4ea23e457b7ac82ce1f23e0bac9294`，参考快照在`/private/tmp/OpenBot-reference`。iOS `Controllers/ObjectTracking/ObjectTrackingFragment.swift`的`updateTarget`以人体水平中心误差调节左右轮差速；`Detector.swift`支持YOLOv4/v5。成熟检测器解决找框的一部分问题，不能替代目标关联、控制增益、惯性和安装方向的验证。本机原先偏离即用完整转向PWM左右反转，本身可能过冲。
- 新增`YoloPersonDetector.swift`和`Resources/Models`：iOS16+使用Ultralytics官方iOS发布中的YOLO11n，int8/NMS，384×640；iOS15兼容路径使用Apple模型目录的YOLOv3 Tiny。保持部署目标iOS15，没有改BLE协议或引入第三方运行时。`project.yml`显式链接CoreML。两套原始模型随App离线附带，来源、SHA-256、嵌入许可及Ultralytics AGPL-3.0全文见模型目录，未训练或修改权重。YOLO11n的MLProgram最低iOS16，运行时按系统版本选模型；先前模型预编译有最低系统版本提示，最终增量签名构建无该警告，仅未使用AppIntents的提示。
- `PersonFollowDriver.swift`把原`VNDetectHumanRectanglesRequest`上半身请求替换为后台串行CoreML/Vision `person`检测，复用AR相机，每150ms尝试一次，延续原可见预览坐标变换。模型NMS阈值置信度0.25/IoU0.45；0.6置信度仍是可独立开启的实验。加载/输出格式错误明确显示，不静默回退为旧检测器。诊断记录实际模型名、框/置信度、耗时和帧龄，不保存照片。

### 跟随控制

- 新增`PersonTargetTracker.swift`：初次选最大框，后续按IoU与中心距离匹配已有目标，丢失0.6秒才允许重新选取；不是生物身份识别，多人交叉仍可能误匹配。对水平中心采用0.18秒时间常数平滑；框顶、宽高保持本帧值，不延迟上边界停车信号。
- `FollowExecutor.swift`使用`ObjectFollowSteering`连续前进差速：中心±4%内直行，归一化转向需求`2*(centerX-0.5)`，变化速度限制2/s。内侧轮`drivePWM*(1-|steer|)`，外侧轮从直行PWM渐变到该方向保存的转向PWM，两轮非负；不再远处一偏就满PWM反向原地转。沿用手机已保存的直行135/左转172/右转172，不重置。
- 仅在用户独立开启上边界停车且触发保持时禁止前进；偏离中心约6%以上允许完整转向PWM原地短脉冲120ms/400ms周期，转向需求反号先制动，居中保持零输出。此为近人静止对准的固有节奏，远处仍连续弧线。可选100ms/350ms脉冲与2秒反向等待只进一步约束原地转向。所有可选实验新页面仍默认关闭；丢目标/AR暂时受限停车后恢复、手动取消和断连等规则保持。
- `FollowControls.swift`更新人体框、几何匹配和弧线/近处短时对准说明。由上半身框变成人体框后，已有上边界阈值应按实际安装姿态重测，不代表实际测距或避障。

### 图片归位的坐标与实际运动

- `AnchorARSession.swift`持续提供仍被ARKit实际跟踪的目标图像观测。`FixedAnchorFrame.realignForReturn`是明确的末端重对齐入口；普通`alignOnce`规则不变。`ArNavigationController.swift`只在返程最后目标、VIO估计距原出发位姿≤35cm且执行已授权时接受它。
- 转向/末段看见图像立即零输出，丢弃触发停车的那一帧，再收集至少12帧、持续0.5秒、位置/朝向满足现有稳定窗口的后续观测；期间丢图重置窗口。稳定后计算`T_map_camera = inverse(T_AR_marker_fresh) * T_AR_camera`，保存的`anchorStart`及节点坐标不变。地图到AR的显示变换同步重绘，未重启AR会话。这个操作纠正当前位姿估计，不把车辆实际位置假定为目标。
- 新坐标下分别计算当前相机到保存支架出发位置的距离、朝向残差。≤5cm且≤5°才宣布返程完成；否则误差在30cm内才按“停2秒→对准连线→直行→停2秒→恢复保存朝向”实际微调。该末端阶段允许半径30cm圆内的局部接近，不受旧漂移轨迹的中心线约束；需要用户保证锚点旁这一区域可直线通行，不是根据图像推断障碍物。
- 移动微调期间冻结本次图片重对齐，避免连续更新造成反馈跳变；最终朝向完成后必须重新识图复核，兼顾相机绕未知底盘转轴发生的位置变化。最多3次物理微调，第四次观测只能确认到达或报告残差并停车；不保证未知支架偏移下的底盘中心精度。
- 未见图片时，围绕保存朝向依次−25°、+25°、回零小角度扫描，段间停2秒；单次稳定确认5秒未完成则重新寻找，末端归位总时限90秒。超30cm、扫描结束无稳定图像、修正不收敛、底盘/定位故障均明确停车，不误报完成。`WaypointExecutor.swift`新增等待图片/稳定识图状态，仍用独立到期停车和短脉冲转向。临时VIO恢复后返回等待图片，不跳过复核。
- `ArNavigationView.swift`和README更新返程说明，`navigation.jsonl`新增`returnImageCorrection`记录旧估计、新估计、残差和纠正次数。地图JSON格式、30Hz采集、声呐关闭、w轮速仅显示均未改变。

### 验证与现场待测

- **180项SwiftPM测试通过，0失败**，日志`/private/tmp/OpenBene-yolo-homing-tests.log`。新增5项关联/水平平滑/非负差速/近处仅转向及带80ms观测延迟、噪声、180ms轮惯性和轮差的跟随闭环仿真；新增9项图片坐标、末段限定、静止确认、物理归位、不得连续复用移动观测、30cm边界、时间/次数限制与最终复核测试。12cm VIO偏差的闭环仿真通过实际移动而非直接赋目标位姿归位，最终位置≤5cm/朝向≤5°；这不是实车测量。
- 使用官方Ultralytics `bus.jpg`实际执行两套CoreML/Vision模型，YOLO11n得到5个人体框、YOLOv3 Tiny得到3个。Mac上YOLO11n冷加载约673ms/热推理2.6ms，Tiny约294ms/4.7ms；它们仅是本机功能检查，不能当作iPhone速度或检测准确率。日志`/private/tmp/OpenBene-yolo-inference-check.log`、`/private/tmp/OpenBene-yolo15-inference-check.log`。沙箱内单独读取Tiny元数据时CoreML加载受限，改为允许CoreML系统服务的本机执行后成功；不是App模型加载错误。
- XcodeGen生成并保留本机Team后，真机签名构建通过：`/private/tmp/OpenBene-yolo-homing-build.log`。已检查App同时包含`yolo11n.mlmodelc`与`YOLOv3TinyInt8LUT.mlmodelc`。北京时间15:47已覆盖安装到当前iPhone12Pro，安装记录`/private/tmp/OpenBene-yolo-homing-install.json`，保留地图与PWM。没有工具启动车辆。
- 现场尚需测试人体框与真人对齐、当前安装姿态的上边界停车、连续转弯是否仍摆动、丢人后恢复、返程末段识图/真实归位误差，以及支架偏心情况下能否在3次微调内收敛。签名构建与仿真不替代这些现场结果。改动仅在`New demo/IOS`，`git diff --check`通过，未推送。

交付补记：15:48已成功启动iPhone上的最终测试版，记录`/private/tmp/OpenBene-yolo-homing-launch.json`。没有通过工具点击跟随或返程，也没有发送运动指令。

## 2026-10-19 后续：默认近人停车、采集入口可见性和转向保护计数修复

用户确认YOLO识别与转弯改善，但会继续靠近人；采集页未找到跟随入口；去程/返程均出现“转向未收敛”中断。本节只修正这三项，不更改PWM、地图格式、BLE协议或普通路线行为。

### 手机日志证据

- 从连接的iPhone复制`Documents/Diagnostics`至`/private/tmp/OpenBene-follow-turn-report`。189条YOLO跟随状态全部为`enabledGates=[]`，上边界停车未启用。37条已授权跟随记录的人体框顶≤5%，仍有`c135,135`或其他正向差速指令；15:56:45的框顶约0.21%，保存PWM为直行135/左右172。之前把近人停车放在默认关闭的单测条件中，不能满足当前需要自动停在人前的用途。
- 去程16:00:03（目标1）、返程16:01:56（目标0）、去程16:08:53（目标3）分别在本轮连续转向约13/16/24秒时触发合并的“转向未能收敛”分支，剩余误差约5.40°/12.80°/3.33°。代码只有45秒或270°两条进入该消息的条件，因此这三次提前终止触发的是累计角度条件；旧实现将每帧相邻yaw差的绝对值累加，正常VIO细抖动也会耗尽270°限制，日志并不能证明实际车身转过270°。
- 返程16:03:05另一次触发“8秒未接近目标”：16:02:57已到10.8°，随后记录约41°朝向变化、误差增至53.1°，再降到44.98°、34.77°、22.57°、13.30°、12.41°，但未刷新历史最小10.8°，仍被误判无进展。朝向变化可能来自车体/支架运动或VIO修正，现有每秒一次日志不足以区分，不直接归因为电机或模型问题。

### 文件与行为

- `FollowTestOptions.swift`将近人停车默认设为开启；其他实验仍关闭。`PersonFollowDriver.swift`本机保存近人停车开关与停车线百分比，采集和导航页共用；初始化日志记录实际设置，不再硬写空条件。当前手机此前没有这两个偏好键，因此第一次更新按开启/5%使用。不重置135/172/172。
- `FollowExecutor.swift`保持框顶到停车线即禁止前进。释放新增至少3次新鲜有效检测、持续0.4秒，且框顶远离停车线3%；单帧反复使用不会放行，贴回释放带或丢目标清除确认。靠近时仍只允许原有短时原地对准，无前进分量。停止原因明确为“近人停车，禁止前进”。这仍是用户之前选择的图像边界法，受安装俯仰和姿态影响，不是距离传感器或绝对防撞保证。
- `FollowControls.swift`把近人停车开关及0～20%停车线滑块移到主卡片，数值越大停车线越下、越早触发；改动设置先停，需重新开始。诊断默认折叠，**更多→关闭其他测试门槛**保留近人停车设置。无底盘时显示返回首页连接的明确说明。启动仍需手动点“5秒后跟随”，没有自动运动。
- `MapRecordingView.swift`把**跟随采集**卡片移至控制区最上方；控制区按可用屏幕高度限高、支持滚动，节点名称限制一行，避免新增诊断文本挤掉按钮。仍需首页开启蓝牙/选底盘，识图并确认支架出发位置；确认只启用检测，不启动车辆。采集起点/节点前停车2秒，之后需手动再次跟随。
- `SettledTurnController.swift`累计角度改为相对上次计数点≥3°的净变化，忽略小幅往返噪声，同时保留真实大幅旋转270°限制。误差比当前进展参考恶化8°时更新参考、不刷新计时，之后重新改善超过1°才算进展；不要求击败整个转向的历史最小误差。真实8秒无进展、45秒总时限、朝向突跳和反向停车等保护保留；失败文本区分45秒、有效270°和无进展，并显示剩余角度。
- `WaypointExecutor.swift`保存最近转向诊断快照，停止重置控制器后仍可读取；`ArNavigationController.swift`日志新增本轮耗时、无进展时间、有效累计转动、脉冲剩余时间、PWM和最近实际提交BLE帧，便于下一次定位根因。没有自动取消保护后强行继续，也没有重新开始当前整条路线。

### 验证与交付

- **186项SwiftPM测试通过，0失败**，`/private/tmp/OpenBene-near-stop-turn-tests.log`。新增贴顶实际框的默认停车、单帧/边界抖动不能恢复前进、带60Hz±0.4°噪声的大角度转向、扰动后局部重新接近、真实大幅往返270°保护与有进展时仍受45秒限制的6项回归；相关旧基线测试显式关闭近人停车以独立验证其他实验。
- 真机签名构建通过，`/private/tmp/OpenBene-near-stop-turn-build.log`，仅未使用AppIntents元数据提示。16:24～16:25覆盖安装并于16:25成功启动连接的iPhone12Pro；`/private/tmp/OpenBene-near-stop-turn-install.json`、`/private/tmp/OpenBene-near-stop-turn-launch.json`。未通过工具点击运动按钮。
- 修正已有`CapturePresentationTests`中过时的“采集起点”初始断言，改为确认支架出发位置，并检查跟随/停车可见、尚未就绪不能启动。iPhone16模拟器（iOS18.3）连续两次采集页展示UI测试通过；结果`/private/tmp/OpenBene-near-stop-layout.xcresult`，日志`/private/tmp/OpenBene-near-stop-layout.log`，截图`/private/tmp/OpenBene-near-stop-layout-attachments`。已查看截图，按钮与默认开启的近人停车开关均可见。这是界面验证，模拟器不支持ARKit，不能验证相机/真实底盘效果。
- README同步默认停车、保存设置、采集入口和新转向判定。`git diff --check`通过，改动仅`New demo/IOS`，未推送。实际停止位置、支架俯仰影响以及去程/返程的真实转向收敛仍需用户现场复测。

## 2026-10-19 后续：实际距离停车、直角跟随与完整相机画幅

用户在采集模式确认支架位置、采集起点后跟随，反馈人直角转弯时容易出画，开启近人停车时人在远处仍不前进。随后用户选择默认约1米，并询问超广角能否改善视野；暂时无法配合现场测距测试。本节取代图像上边界停车法，不改变去/返程路径、PWM、节点采集或BLE协议。

### 实际证据及原因

- 读取当前iPhone `Documents/Diagnostics`至`/private/tmp/OpenBene-follow-corner-report`。16:53:04人体框高约46.5%、框顶约0.13%，16:53:12框高约47.4%、框顶约0.33%，仍触发上边界保持；下俯摄像头可能在远处就裁掉头部，框顶位置不能作为可靠距离。因此不是继续调小百分比，而是移除该方法。
- 16:53:34、35的目标已接近左边界，仍发送`c52,160`、`c38,164`前进弧线，随后检测丢失；16:53:42接近右边界时仍发送`c162,46`，下一秒丢人。当前低转向强度、150ms检测间隔及中心平滑可能使急转弯跟不上。日志模型推理约10～14ms，未发现模型推理长时间卡顿的证据；一秒一次日志不能重建人/车的完整相对运动。
- 原检测虽然使用完整AR相机图，但经`displayTransform`后会裁掉可见竖屏以外的框；原预览是满屏竖向填充，对4:3传感器横向画面有明显裁切。因此人可能仍在原图中，却已不在控制使用的可见区域。

### 距离测量与停车

- `AnchorARSession.swift`仅在设备支持时开启`.sceneDepth`；未使用旧声呐假值、未读取w轮速入环，也未另开相机。Apple主文档依据：[ARDepthData](https://developer.apple.com/documentation/arkit/ardepthdata)、[sceneDepth](https://developer.apple.com/documentation/arkit/arframe/scenedepth)。深度为相机平面Z、单位米，与同帧原相机图对应；部署目标仍iOS15。
- 新增`PersonRange.swift`、`PersonDepthSampler.swift`：对YOLO人体框中央40%宽、从框顶25%～65%高的区域取最多9×9网格，撤销Vision `.right`方向后按原图坐标读取深度；使用实际CVPixelBuffer行距，去重像素、过滤低置信度、无效/超范围读数。至少12个有效样本、有效比例≥40%，IQR≤max(0.25m,中位数20%)才接受中位数，混杂人体/背景时返回未知。
- 使用相机内参反投影`[(u-cx)/fx*z, -(v-cy)/fy*z, -z]`，乘同帧AR相机旋转，再取世界X/Z水平长度，消除安装俯仰与竖直高度对距离的直接影响。距离相对手机而非底盘外缘；这不是普通导航的障碍物规划。
- `PersonDetection`新增可选距离；`PersonTargetTracker`暴露本帧实际匹配原框；`FollowExecutor`严格采用该匹配框的距离，避免取到另一个更大人的读数。无新鲜有效距离时禁止前进，明确显示“距离未知”，不复用上一帧远距离、不回退到框顶/框高估距。关闭距离停车仍是用户明确的连续输出实验。
- 用户选定默认1米停车，>1.2米、至少3次新鲜有效测量且持续0.4秒再前进；范围可调0.5～2米。保持期间仅允许既有短时原地对准，没有前进分量。新米数与启用设置用`follow.rangeStop.v1.*`保存；旧图像停车线、此前为绕过误停而关闭的开关不迁移为米数，首次使用新方法为开启/1米。未重置现有PWM或地图。
- `PersonFollowDriver.swift`复用同帧深度/置信度/相机内参与旋转；UI和日志显示实际距离、支持情况、是否有深度/置信度、每个框的测距、控制动作。`FollowControls.swift`改为米数滑块，删除红色停车线，保留主界面开关、其他单测及手动5秒开始，不新增人体大小标定。

### 直角跟随

- 检测尝试频率从约6.7Hz提高到最高15Hz；后台串行、最多一个任务，不保留整队ARFrames。水平平滑时间常数由0.18秒改0.10秒，估计水平速度，给转向0.10秒短前馈；检测模型、权重和类别不变。
- `ObjectFollowSteering`小偏差保持原弧线差速；当前偏离中心>22%，或>18%且正向侧边移动、预计0.12秒后>24%时，先制动80ms再优先原地转向。使用对应方向保存的完整PWM，180ms输出/至少120ms制动；回中心±10%先停200ms再前进，越过中心需要反向时停300ms，避免大角度仍向前冲及高频反转。近人保持仍为120ms/400ms原地对准。可选其他脉冲/反向门槛只额外限制这些动作。
- 仅在目标仍新鲜可见时转向；实际无检测立刻零输出，不盲转找已经在墙后的人。用户/模型/安装/底盘动态仍可能导致丢失，未宣称任意速度90°转弯都可成功。

### 超广角核实与完整画幅

- Debug `OpenBotAnchorNavApp.swift`启动仅查询硬件与AR世界跟踪支持格式，写`Documents/Diagnostics/camera.jsonl`，不会启动相机或车辆。实际读取到`/private/tmp/OpenBene-phone-camera-capabilities.jsonl`：当前iPhone12Pro有广角和超广角，`sceneDepthSupported=true`，但所有`ARWorldTrackingConfiguration.supportedVideoFormats`均为`AVCaptureDeviceTypeBuiltInWideAngleCamera`，没有超广角可选。这不等于所有设备/未来系统都不支持；当前不能用普通相机0.5×切换方式替代AR会话。[Apple格式选择API](https://developer.apple.com/documentation/arkit/arconfiguration/videoformat-swift.class/capturedevicetype)。
- 硬件默认格式FOV约70.29°/107.80°，仅用于确认硬件差异，未当成当前AR相机或屏幕实际FOV。`minZoom=1`，未用数字变焦伪装超广角，也未尝试同时开启另一相机抢占AR资源。
- `AnchorARSession.swift`从实际帧分辨率发布旋转后的图像宽高比；`ArSessionView`按完整图像适配宽高，允许上下黑边，不把图像放大裁成整块长竖屏。`MapRecordingView`与导航页把绿色框叠加移入该相机视口，检测传入真实SceneView尺寸；因此原有`displayTransform`、转向和深度坐标仍一致，能保留此前被手机长屏裁掉的两侧。VIO会话、锚点和保存地图不变，未切到真正超广角。

### 验证、安装及未验证内容

- **195项SwiftPM测试通过、0失败**，日志`/private/tmp/OpenBene-depth-corner-tests.log`。新增/迁移真实距离及远处贴顶不误停、未知读数不复用、匹配人的距离、侧边优先转向/实际丢失即停；测试真实CVPixelBuffer的填充行距、方向、俯仰/滚转补偿、置信度和混杂背景。
- 左右90°步行折线路径仿真通过：水平视野38°、80ms检测延迟、180ms轮惯性、15Hz检测，人物按0.6m/s在0.7秒后直角转弯；模型完全出视野时实际返回空检测，没有把画外目标夹成假框。该参数组中两侧均触发原地优先转向，没有完全丢失目标，不发送负向平移。另保留带噪声/轮差的原跟随闭环测试。仿真并非实车结果。
- 深度/转弯签名构建`/private/tmp/OpenBene-depth-corner-build.log`通过，17:17覆盖安装、17:18成功启动；记录`/private/tmp/OpenBene-depth-corner-{install,launch}.json`。对应采集UI连续展示测试通过，结果`/private/tmp/OpenBene-depth-corner-layout.xcresult`。
- 完整画幅和能力诊断最终版签名构建`/private/tmp/OpenBene-full-frame-build.log`通过，17:25覆盖安装并成功启动；`/private/tmp/OpenBene-full-frame-{install,launch}.json`。再次采集页UI测试通过，`/private/tmp/OpenBene-full-frame-layout.xcresult`。仅AppIntents未使用的元数据提示，没有新增构建错误。没有通过工具发送车辆运动命令。
- 17:20读取的新版本跟随日志尚无实际深度状态；用户明确回复暂时无法测试，因此**实际LiDAR人体距离、真实近人停车位置、急转弯改善和完整画幅AR显示仍待现场验证**。已验证的是能力列表、算法/缓冲区与仿真、UI、构建/安装，不能声称实车通过。保留当前地图与PWM，README更新；`git diff --check`通过，范围仅`New demo/IOS`，未推送。
