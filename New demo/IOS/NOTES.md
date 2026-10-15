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
