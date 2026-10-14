# Android demo（Kotlin + ARCore + ML Kit）

手机装在 OpenBot 上，ARCore 负责定位、ML Kit 负责读二维码，`nav/` 里的状态机沿折线驱动底盘；同一套链路还保留了 OpenBot 的跟随（tracking）模式，见下面的运行时提示。

## 构建

```bash
# Android Studio：直接打开本目录
# 命令行（本机没有 wrapper 的 jar，直接用系统 Gradle）：
gradle --no-daemon :app:assembleDebug
# 换机器时可以先生成 wrapper：
# gradle wrapper && ./gradlew :app:assembleDebug
```

已在本机编译通过：Gradle 8.10.2 + AGP 8.5.0 + Kotlin 1.9.24 + JDK 17 + Android SDK 34，产物 `app/build/outputs/apk/debug/app-debug.apk`（约 63 MB）。

安装到手机：

```bash
adb install -r app/build/outputs/apk/debug/app-debug.apk
```

要求：JDK 17、Android SDK 34（build-tools 34.0.0）、AGP 8.5、Kotlin 1.9。真机需要支持 ARCore（Play Store 里的 “Google Play Services for AR”）。依赖 ARCore、ML Kit 条码扫描与 ML Kit 人脸检测，都在 app/build.gradle.kts 里，首次构建需要能访问 google()/mavenCentral()。

本机还有两个只服务于本机构建环境、已列进 .gitignore 的文件：`local.properties`（指向 Android SDK）和 `local-mirror.init.gradle`（把仓库切到 HTTP 镜像，本机只有 HTTP 代理能出网时用 `-I local-mirror.init.gradle` 传给 Gradle）。换机器构建时不需要它们。

## 代码结构

| 路径 | 作用 |
| --- | --- |
| `MainActivity.kt` | 选目的地、看路线摘要、蓝牙选 OpenBot |
| `ar/ArNavigationActivity.kt` | AR 会话、图像锚点、二维码兜底、驱动执行器 |
| `ar/MarkerGeometry.kt` | 二维码四角 → 地面四边形 → 锚点位姿（Python/Swift 同源） |
| `ar/CameraBackgroundRenderer.kt` | ARCore 相机背景渲染 |
| `ar/RouteOverlayView.kt` | 右上角俯视地图 |
| `nav/` | 地图模型、Dijkstra 路由、转向引导、位姿估计、执行状态机 |
| `nav/FollowController.kt` | 跟随控制器（与 Python/Swift 同源）：归一化目标框 + 声呐 → 左右轮速 |
| `robot/PersonBoxDetector.kt` | 跟随模式的目标框来源：ML Kit 人脸检测 |
| `robot/` | BLE 链路（openbene_sdk 协议）、mock 链路、跟踪用 RSSI 工具 |
| `assets/` | 地图 JSON 与 4 张贴纸 PNG（由 `shared/tools/sync_demo_assets.py` 同步） |

## 运行时提示

* 不接机器人时不要打开蓝牙开关，MockRobotLink 只记录控制量，用来验证导航逻辑。
* 图像锚点数据库在启动时用 assets 里的 PNG 现场构建，不需要 `arcoreimg`；如果要更稳的离线特征库见顶层 README。
* 扫码路径依赖 `MarkerGeometry.DEFAULT_CODE_QUAD_SIZE_M`（默认 0.12 m，含静区的二维码块宽）；如果实际打印/识别尺寸不同，改这一个常量即可。
* 跟随模式：AR 界面底部的 “Follow mode” 开关切过去后，机器人跟着相机里最大的人脸框走（框偏左/偏右就转，框小就前进，框大就停）。跟随不需要锚点，所以没定位也能启动；预设是 `FollowConfig.FACE_BOX`（目标框高度 0.16），现场标定后再落地。
* 跟随与定点导航共用同一条 RobotLink：切模式时会先停车并停掉执行器。声呐 35 cm 以内两种模式都会停车，但声呐默认不订阅——本仓库的 520 底盘没装超声模块，固件仍会上报拾到 trigger 脉冲产生的 1-3 cm 假距离，保护会把机器人钉在原地；开关是 `OpenBotBleLink.kt` 顶部的 `SONAR_INSTALLED`（默认 `false`）。
