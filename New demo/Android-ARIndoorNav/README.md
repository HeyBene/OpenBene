# OpenBene Android 锚点导航（ARCore）

以当前 iOS 版的现场采集和节点执行逻辑为基础：单张地面图像锚点 → 采集起点和有朝向的节点链 → 本机保存 → 再次识别同一锚点 → 按采集顺序复现位置与朝向。

没有预设地图、地图导入、路径规划、自动反向路线、中途重设锚点或云端存储。旧的跟随模式保留，和节点导航分开。

## 在当前 Mac 上用 Flutter 运行

已经安装并验证 Flutter 3.29.1、Dart 3.7.0、JDK 21、Android SDK 34、Gradle 8.7。JDK/SDK 位于工作区根目录 `.android-tools`，已通过 `flutter config` 指向该位置。请保留这个目录。`~/.gradle` 链接到其中的构建缓存，避免重复下载。

1. 安卓手机开启开发者选项与 USB 调试，用数据线连接 Mac，在手机上允许这台 Mac 调试。
2. 进入 Flutter 工程：

```sh
cd "/Users/fandi/Downloads/ARIndoorNav-main/OpenBene/New demo/Android-ARIndoorNav/flutter"
flutter devices
flutter run -d <安卓设备ID>
```

只有一台安卓设备时可直接 `flutter run`。如编辑器已打开，重开终端或编辑器可刷新 SDK 配置。不需要配置 Apple Team 或 Firebase。

应用启动后会自动打开导航首页。Flutter 入口通过 MethodChannel 打开原生 Kotlin 界面；ARCore、相机、地图采集、导航和 BLE 共用 `app/src/main` 的实现。Dart 页面可 hot reload；修改 Kotlin/Android 后需停止再运行 `flutter run`。

若只需生成调试包：

```sh
flutter build apk --debug --target-platform android-arm64
```

输出为 `flutter/build/app/outputs/flutter-apk/app-debug.apk`，不需要手动管理 APK 才能真机调试。`flutter run` 会按连接的设备编译、安装和启动。

## 换一台 Mac

安装 Flutter、JDK 17 或 21、Android SDK 命令行工具或 Android Studio；安装 `platform-tools`、`platforms;android-34`、`build-tools;34.0.0`。Flutter 构建还会使用 NDK `26.1.10909125` 和 CMake `3.22.1`（首次构建可自动安装）。

```sh
flutter config --android-sdk <SDK绝对路径> --jdk-dir <JDK的Contents/Home绝对路径>
flutter doctor --android-licenses
cd flutter
flutter pub get
flutter run -d <安卓设备ID>
```

`local.properties`、SDK、JDK、缓存和构建产物均不提交到仓库。Gradle wrapper 脚本及 JAR 已补全并锁定 Gradle 8.7 的分发 SHA-256。

## 真机使用顺序

需要支持 ARCore 的 Android 7.0/API 24 或以上设备，并安装 Google Play Services for AR。应用内会请求相机及蓝牙权限；Android 11 及以下还需位置权限和系统定位开关用于 BLE 搜索。

### 1. 先测试底盘

首页打开蓝牙驱动开关，扫描并选择底盘，再进入“PWM 调节与测试”。首次测试将车轮架空，确认前进、左右转向及停车方向。

- 直行、左转、右转三个 PWM 独立设置，范围 `0..255`，默认均为 **160**。
- 滑块及 ±1 按钮调节；“保存并应用”保存至本机。
- 三个测试按钮用当前界面值运行 **1 秒**，随后自动停车。修改数值、手动停车、离开页面、切到后台、断连或碰撞也会结束测试。
- 页面显示连接、电压（底盘有回读时）、最近发送的控制帧和链路错误。
- 根目录旧跟随模式仍使用原跟随参数；这三个设置作用于节点导航和短时 PWM 测试。

### 2. 采集航线

1. 将一张参考图片打印并平放地面，保持不动。素材在 `app/src/main/assets/anchors/`，包含 iOS 同款 entrance/junction/room101/room102 图片和原版 pi/1 图片。
2. 首页“开始采集新航线”，选择对应图片，填写**完整图片实测宽度**（厘米；不要只量内部二维码）。四张 iOS 图默认 20 cm；pi 默认 7.62 cm，1 默认 12.7 cm，按实际打印尺寸修改。
3. 首次对准整张图片，等待“锚点已固定”。此后可以离开图片，节点使用同一 ARCore 空间坐标。
4. 固定手机在底盘上的安装位置。移动到起点并朝向所需方向，点“采集起点”。依次移动到每个节点，朝向需要记录的方向后点“采集节点”。记录的是相机的位置和朝向，采集与导航应使用同一安装方式。
5. 可撤销上一个点。“终点”可标记最后一个节点；至少起点加一个节点即可直接“保存”，末点自动成为终点。起点、节点、白色航线和青色节点朝向箭头显示在相机画面上。
6. 输入名称保存。航线位于应用私有目录 `files/routes.json`，没有上传服务器；卸载应用会删除本地数据。

### 3. 应用导航

1. 首页选择保存的航线，点“应用导航”。本次只识别采集时选择的同一张图片，并使用保存的实际宽度。
2. 等待锚点固定，随后将机器人放回采集起点 **30 cm** 内，点击“开始执行”。不需要持续看见二维码。
3. 执行顺序：

```text
原地转向下一节点的连线方向（误差 ≤3°）
  → 停车 2 秒
  → 差速直行，到点距离 ≤0.30 m
  → 停车 2 秒
  → 转到该节点采集的朝向（误差 ≤5°）
  → 若还有节点，停车 2 秒，再对准下一段并继续
  → 最后一个节点完成朝向后停车结束
```

直行时保留轻微差速修正；方向偏差超过 6° 会先停车 2 秒，再重新原地对准。设置 PWM 会先停车，保存后回起点手动重新开始。航线各段需事先确认直线可达。

跟踪暂时受限、相机超过 0.6 秒无新帧、蓝牙断开或碰撞会结束当前执行，不自动恢复动力。正常离开二维码不会重新锁定或要求重扫；切到后台会结束本次会话，需要退出 AR 页再打开并重新识别起始锚点。

## 控制协议与参数

- BLE 服务 `61653dc3-4021-4d1e-ba83-8b4eec61d613`，RX `06386c14-86ea-4d71-811c-48f97c58f8c9`，TX `9bf1103b-834c-47cf-b149-c9e4bcf778a7`。
- 控制帧 `c<left>,<right>\n`，每轮范围 `-255..255`，停车 `c0,0\n`。160 左转为 `c-160,160\n`，160 右转为 `c160,-160\n`，直行为 `c160,160\n`。
- 直行差速增益 `1.6`；归一化值经固件协议换算，四舍五入采用中点远离零；最终限幅到 ±255。
- 非零控制写入间隔至少 40 ms，心跳每 250 ms 发送 `h750\n`。GATT 写入及通知订阅串行，停车优先，关闭连接前先尝试发送零指令并保留 250 ms 链路。
- `w` 轮速遥测仅解析显示/诊断，**不用于位姿、到点或运动控制**。位置和朝向只来自 ARCore。
- `OpenBotBleLink.SONAR_INSTALLED = false`，不订阅或使用 `s` 假距离，没有超声避障。

## 验证

```sh
cd flutter
flutter analyze
flutter test
```

共享 Kotlin 算法及 Android lint（直接调用 Gradle 需先设置 JDK）：

```sh
export JAVA_HOME="/Users/fandi/Downloads/ARIndoorNav-main/.android-tools/jdk-21.0.12.1+1/Contents/Home"
cd android
./gradlew :app:testDebugUnitTest :app:lintDebug
```

也可在原生工程根目录单独运行 `./gradlew :app:testDebugUnitTest :app:assembleDebug :app:lintDebug`。原生与 Flutter 构建使用相同应用 ID `com.openbene.arindoornav`。

构建与测试记录、未完成的真机验证见 [NOTES.md](NOTES.md)。ARCore 设备与识别原理可查 [Google 官方设备列表](https://developers.google.com/ar/devices)、[Augmented Images](https://developers.google.com/ar/develop/augmented-images)；Flutter 原生桥接使用[官方 Platform Channels](https://docs.flutter.dev/platform-integration/platform-channels)。

## 采集页没有相机画面

只有收到相机首帧后才会显示“请识别锚点”；此前页面会显示权限、服务安装/设备准备、会话创建、等待首帧等真实状态。失败时会保留中文说明和原始异常，点击返回退出。

若显示 `UnavailableDeviceNotCompatibleException`，说明当前设备/系统环境被 ARCore 判定不兼容。能安装 Google Play Services for AR 并不代表设备受支持；请核对官方支持列表并换兼容设备。已连接的 vivo X27/V1838A 真机已复现此错误，无法用这台手机完成 ARCore 采集。排查日志可用 `adb logcat -s OpenBeneAR:V` 获取；不要通过跳过 ARCore 设备准备流程绕过错误。
