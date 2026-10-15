# OpenBene Android / Flutter 启动入口

手机 USB 连接 Mac，开启 USB 调试并允许这台电脑后，在当前目录执行：

```sh
flutter devices
flutter run -d <安卓设备ID>
```

只有一台 Android 手机时可直接 `flutter run`。本机 SDK/JDK 配置见 [上级说明](../README.md)。

启动后自动打开原生导航首页。返回 Flutter 入口后可点“打开锚点导航”重新进入。

Flutter 使用 MethodChannel 启动 Android 原生界面，ARCore、相机、节点采集、航线、PWM 与 BLE 均共用 `../app/src/main`，没有复制一套控车代码。这是可由 Flutter 编译运行的 Android 工程；原有 Swift/ARKit 工程仍单独维护。

Dart 入口支持 hot reload；修改 Kotlin/Android 代码后需停止运行并重新 `flutter run`，Dart hot reload 不会重编译原生代码。只生成包时可运行 `flutter build apk --debug --target-platform android-arm64`。

```sh
flutter analyze
flutter test
cd android
./gradlew :app:testDebugUnitTest :app:lintDebug
```

完整采集、导航与底盘架空测试流程见上级 README；未连接 ARCore 真机时只能验证构建及算法，不能验证定位和真实运动。
