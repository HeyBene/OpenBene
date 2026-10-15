# Android ARCore 移植与构建记录

日期：2026-10-15。工作分支 `codex/ios-first-build`，基于仓库提交 `0c34ed2`。改动未提交、未推送。iOS 签名、已安装的 iOS 应用及 Swift 实现未由此次 Android 移植修改。

## 本次目标

在当前 Mac 上构建 Android 版本，以已经现场测试的 iOS 采集/节点执行/PWM 调节为行为基线。按用户补充，增加可直接 `flutter run` 的入口；不要求通过手动传送 APK 测试。

Flutter 负责启动入口，通过 MethodChannel 打开 Kotlin 导航界面。相机、ARCore、节点链和 BLE 一起由原生 Android 生命周期管理。Flutter Gradle sourceSets 直接复用 `app/src/main/{java,res,assets}`，单份控车实现。Swift 工程保持独立，没有把 ARKit 用于 Android。

## 本机构建环境

- Mac arm64 / macOS 15.7.4。
- 现有 Flutter 3.29.1 / Dart 3.7.0，`/Users/fandi/Development/flutter`。
- 本次补装 JDK 21.0.12.1+1 arm64、Android command-line tools、platform-tools、SDK platform 34、build-tools 34.0.0、NDK 26.1.10909125、CMake 3.22.1。
- AGP 8.5.0、Kotlin 1.9.24、Gradle 8.7；minSdk 24、compile/targetSdk 34、Java/Kotlin target 17。保留已有依赖版本，不因 lint 的版本更新建议整体升级依赖。
- 工具最终存放 `/Users/fandi/Downloads/ARIndoorNav-main/.android-tools`，不依赖临时目录保存。`flutter config` 已设置此目录中的 SDK/JDK；`~/.gradle` 原先不存在，现链接到 `.android-tools/gradle-cache`，没有覆盖已有配置目录。
- SDK 路径记录在原生及 Flutter Android 的 `local.properties`，文件忽略提交。Gradle wrapper 的脚本/JAR 已补全，分发包 SHA-256 为 `544c35d6bd849ae8a5ed0bcea39ba677dc40f49df7d1835561582da2009b961d`。
- Gradle 和 Kotlin 依赖缓存复用；已清理本次工具安装后不再需要的下载压缩包。构建工具本身仍需保留。

## 改动及原因

| 文件 | 改动及原因 |
| --- | --- |
| `flutter/` | Flutter 可运行工程、原生启动通道、真实 Android sourceSets、平台通道测试、锁定依赖和 wrapper。连接手机可 `flutter run` 编译安装启动。 |
| `ar/ArRouteActivity.kt` | Session/图像数据库在后台准备，GL 只生产不可变帧快照，主线程更新 UI/采集/发送 BLE；避免旧代码从 GL 线程修改视图和驱动主线程链路。相机成功 resume 后才允许渲染取帧。 |
| 同上 | 只接受所选图像 FULL_TRACKING，要求图片平放地面；首次锁定后不再更新锚点，采集与复现都以完整图像姿态的逆变换计算相对位置和朝向。离开图片不触发重扫。 |
| 同上 | 保存起点、顺序节点和 yaw；复现节点朝向；真实帧时间看门狗、跟踪/连接/碰撞中断停车，切后台取消会话，设置 PWM 先取消执行。 |
| `ar/AnchorSheets.kt` / `assets/anchors/` | 增加 iOS 同款四张图，保留原图 pi/1；每次数据库只添加所选的一张图片及保存的真实宽度。 |
| `ar/CameraBackgroundRenderer.kt` | 使用直接、原生字节序 FloatBuffer，初始化第一帧 UV；跟踪受限时仍显示相机背景。 |
| `ar/DisplayRotationHelper.kt` | 显示旋转常量先换算为度，再计算相机图像旋转；视口变更标志跨线程可见。 |
| `ar/NodeOverlayView.kt` | 主线程投影并显示固定的地面节点、航线和记录朝向箭头。 |
| `model/RouteModel.kt` | 本地 JSON v2 增加每点 yaw、名称和锚点实测宽度，保留旧位置文件读取；长度不再将锚点到起点距离当作行程。 |
| `RouteStore.kt` | 用 AtomicFile 写入，失败保留旧文件；读取异常不伪装为空航线并覆盖原数据。 |
| `nav/WaypointExecutor.kt` | 对照 iOS 的分段状态机：先转向、停车、直行、停车、节点朝向；按采集顺序执行。转向阈值 3°、直行重对准 6°、节点朝向 5°、到点 0.30 m、间隔 2 s。 |
| `nav/PwmSettings.kt` / `PwmStore.kt` | 独立保存直行/左转/右转 PWM，默认 160，范围 0–255，兼容旧单转向值迁移。 |
| `nav/PwmPulseTester.kt` / `PwmActivity.kt` | 独立短时试车模块，当前界面值测试 1 s，停止/调节/断连/碰撞/切后台取消，不留延迟恢复任务。 |
| `robot/OpenBotBleLink.kt` | GATT 操作串行，订阅完成后才就绪，停车优先且不可被新非零值覆盖，心跳与最新控制合并发送；写入超时和断连暴露错误，关闭前发送零指令。超声保持 false。 |
| `robot/OpenBotProtocol.kt` | 与 iOS 一致的中点远离零取整，非有限控制值整体归零；按换行重组分片遥测，忽略未安装超声的假读数。`b0` 仍是有效碰撞编号，不能当作无碰撞。 |
| `AppState.kt` | 真 BLE 连接失败保持失败状态，禁止自动降级成 mock 后误报可以驱动。 |
| `MainActivity.kt` / layouts / strings | 中文采集、保存、应用导航、锚点及实测宽度选择、PWM 入口；扫描限时停止，离开页面停止扫描。 |
| Manifest / Gradle | 相机/蓝牙/旧系统位置权限、ARCore required、PWM Activity、Gradle wrapper 和必要测试依赖；Flutter 和原生使用同一 app ID。 |
| `app/src/test/.../NavigationTests.kt` | 针对有实际控车含义的阶段间隔、方向、零指令、丢跟踪、断连、数据保存与协议做 24 项算法测试。 |

## 编译修复记录

1. 首轮 Kotlin 编译出现 `ArRouteActivity.kt: Unresolved reference: R`。通配导入造成资源类解析问题，改为显式导入应用 `R`，后续通过。
2. Android lint 报 `MissingPermission`：BLE 设备名称访问改为显式捕获 SecurityException；权限仍在扫描前检查。
3. lint 报 `CoarseFineLocation`：补齐 Android 11 及以下 coarse 声明/请求，与 fine 保持相同 maxSdkVersion 30。
4. lint 报 `PermissionImpliesUnsupportedChromeOsHardware`：显式声明普通 camera feature 可选，同时保留 camera.ar required。
5. 原仓库只有 wrapper properties，缺脚本/JAR；已生成 Gradle 8.7 wrapper。Flutter 自带模板 wrapper 也改为同版本并固定 SHA-256，仓库不再忽略其 wrapper 文件。

## 验证记录

- 原生 `:app:testDebugUnitTest`：**24 通过，0 失败，0 跳过**。
- 原生 `:app:assembleDebug`：通过，生成 debug 签名安装包。
- 原生 `:app:lintDebug`：通过，0 errors；仍有固定竖屏、中文硬编码/格式化、本地 UI 样式、较旧依赖等 warnings，没有用 baseline 跳过错误。
- `flutter analyze`：No issues found。
- `flutter test`：**2 通过**，验证自动打开/再次进入原生导航、平台启动错误可见并可重试。
- `flutter build apk --debug --target-platform android-arm64`：通过，打包 Flutter 引擎、原生采集/导航/PWM/BLE 代码与锚点素材。初次构建自动安装 NDK/CMake，约 300 秒。
- Google 官方 `arcoreimg v1.42.0 eval-img` 实测：entrance/junction/room101/room102 均 **100**；pi、1 均 **90**。评分仅是离线特征质量，不能替代真机识别、尺寸和光照验证。工具下载自官方 `google-ar/arcore-android-sdk` 对应版本。

报告路径：原生 `app/build/reports/tests/testDebugUnitTest/index.html`、`app/build/reports/lint-results-debug.html`；Flutter 测试和 lint 在 `flutter/build/app/reports/`（运行相应 Gradle 任务后生成）。构建日志位于工作区 `.android-tools/`，不进源码仓库。

## 真机记录与遗留事项

目前未连接 Android 真机。**未验证真机权限弹窗、相机首帧时间、锚点识别/离图稳定性、实际 BLE RX/TX 和电机方向、到点距离及地面标定。** 不把模拟/单元测试写成真机测试。

用户会自行选择支持 ARCore 的手机。后续 USB 连接后直接在 `flutter/` 下 `flutter run -d <设备ID>`。验证顺序：架空单独 PWM 模块检查前进/左右/停车 → 关闭蓝牙手持采集和预览路线，离开图片检查固定 → 实际底盘采集一条短节点链并复现。

现场暂用默认直行/左转/右转 PWM=160、到点0.30m、阶段间隔2s；这是从 iOS 移植的初值，**本次没有在 Android 现场标定**，可用应用内三项设置调节。固定手机安装位置和纸张实测尺寸；相机位置与底盘中心存在安装偏移，当前与 iOS 一样未做单独外参标定。

无超声模块，s 假值不阻塞导航；各段需直线可达。w 轮速不进控制回路。AR 长距离会有漂移，暂未加入中途重定位或路径规划。后台/相机中断必须重新开会话，不自动恢复运动。

没有推送代码；push 前仍需用户确认。

最终复核：工具链移至固定目录并配置后，不额外指定 JAVA_HOME/ANDROID_HOME 直接执行 Flutter 构建成功（约24秒）。Flutter Android 内 `:app:testDebugUnitTest :app:lintDebug` 也通过，24/24 测试成功。已用 aapt 和 ZIP 检查确认启动 Activity 为 FlutterEntryActivity，安装包包含 Flutter 引擎、ARCore JNI、Dart 入口及锚点图片。固定路径下的 ADB 可正常运行，设备列表为空。

补充：仓库通用 Python 忽略规则会忽略 `lib/`，Flutter 子工程已显式允许 `lib/**` 与 `.metadata` 被版本管理，避免遗漏 Dart 入口。

## 2026-10-15：采集页黑屏真机排查

测试机 USB 标识 `1f7a7d94`，vivo V1838A（X27），Android 相机权限已授予，Google Play Services for AR 1.56.262080393 已安装。排查时 BLE 关闭，未发送电机动作。

旧页面每 33 ms 将“请识别 entrance”覆盖到初始化提示上，即使 ARCore 尚未就绪。系统 `dumpsys media.camera` 显示没有本应用打开相机。早期日志还存在 ARCore 安装服务超时，因此不能仅凭已安装 APK 判断相机会话可用。

更新诊断版并真机复现后，日志明确：

```text
ARCore availability=SUPPORTED_INSTALLED device=V1838A
ARCore requestInstall=INSTALLED
Session creation starting
com.google.ar.core.exceptions.UnavailableDeviceNotCompatibleException
    at com.google.ar.core.Session.nativeCreateSessionAndWrapperWithFeatures(...)
```

结论：当前设备/系统环境被 ARCore 运行时判定不兼容，会话创建前即失败；不是锚点未识别导致黑屏。Google 官方支持设备列表也未列出 X27/V1838A。安装服务 APK 本身不保证设备兼容，无法通过改 PWM 或强行启动普通相机获得 ARCore 位姿。

修复 `ArRouteActivity.kt`：

- 相机权限、ARCore 检查、等待安装/设备准备、创建会话、等待首帧分别显示真实状态。收到相机首帧之前不显示“请识别锚点”。等待超过20秒显示具体等待提示。
- 保留会话创建/相机更新异常，显示原始异常类型及中文处理说明，禁止失败状态采集/启动导航；错误不再瞬时 toast 后消失。
- 增加 `OpenBeneAR` 日志，记录安装返回值、创建会话、配置完成、相机 resume、首帧和原始异常栈。
- 部分 OEM 安装窗口仅返回窗口焦点时也检查准备是否完成，不跳过 ARCore 必需的安装和设备配置流程。
- 文字未变化时不重复 setText，避免持续产生 UI/accessibility 更新而妨碍页面诊断。

验证：Flutter debug 构建通过；共享24项导航回归测试通过；Android lint 0 errors。更新诊断版已在本机型上实际显示 `UnavailableDeviceNotCompatibleException`。可确认不兼容失败会清晰显示；**尚不能在这台手机上验证成功的相机预览和定位**，需换支持的设备继续测试。没有改动路线、PWM、BLE 协议或推送代码。

依据：[ARCore Session 文档](https://developers.google.com/ar/reference/java/com/google/ar/core/Session)、[ARCore 安装与设备准备要求](https://developers.google.com/ar/develop/java/enable-arcore)、[官方支持列表](https://developers.google.com/ar/devices)。

交付状态补充：诊断版安装成功并已在手机上确认会话创建的兼容性异常。随后补充更明确中文处理说明的版本也编译通过；最后一次覆盖安装被手机端取消，ADB 原始返回为 `INSTALL_FAILED_ABORTED: User rejected permissions`。未继续重试安装。当前手机保留已验证的诊断版；最终中文说明在源码和最新构建中，下次允许安装/运行后生效。


## 2026-10-15 提交授权

用户已明确授权将本次 iOS 与 Android/Flutter 改动提交并推送到 `codex/ios-first-build` 分支。本文前面“未提交/未推送”等描述记录的是当时的开发状态；本次提交范围仅为 `New demo/IOS` 与 `New demo/Android-ARIndoorNav`，最终提交与远端状态以 Git 记录为准。
