# OpenBot 原版 App 里轮速遥测（w 帧）用在哪

核对对象：官方 OpenBot 仓库快照（本机 `C:\Users\jiken\Desktop\Openbot\OpenBot-master\OpenBot-master`，含 Android `android/robot`、iOS `ios/OpenBot`、`python/`、`policy/`）。下面的行号都指该快照。

## 一句话结论

原版 App 从来没有把轮速反馈放进控制回路。tracking（跟随/自动驾驶）和点对点导航的控制量都来自相机——检测框，或者 ARCore 位姿加策略网络。轮速只出现在显示、数据记录、脚本 API 三处；唯一一次当成反馈用的是 iOS 脚本的 `stop()`：发完停车命令后一直等到遥测里出现 `w0.00,0.00` 才认为车停了。

## 轮速从哪来

1. 固件按 `w` 流上报左右轮 RPM（RTR_520 的 `TICKS_PER_REV = 209`）。
2. App 收到设备特性串后决定订阅：`vehicle/Vehicle.java:172` 的 `processVehicleConfig()`，只有看到 `:wf:` / `:wb:` 才调用 `setWheelOdometryFrequency(500)`，也就是发 `w500`。
3. 解析：`common/ControlsFragment.java:167-176` 把 `w` 的两个数交给 `vehicle.setLeftWheelRpm()` / `setRightWheelRpm()`；`Vehicle.java:235-249` 存进 `SensorReading`。
4. 命令值和实测值是两回事：`Vehicle.java:401-407` 的 `getLeftSpeed()` / `getRightSpeed()` 返回 `control * speedMultiplier`（发出去的命令），只有 `getLeftWheelRpm()` / `getRightWheelRpm()` 是实测 RPM。

## 控制回路里没有它

| 场景 | 控制来源 | 证据 |
| --- | --- | --- |
| tracking / 跟随 | TFLite 目标框 → Control | `autopilot/AutopilotFragment.java:425` `autopilot.recognizeImage(...)` → `:440-441` `vehicle.setControl(control)` |
| 点对点导航 | ARCore 位姿 + 目标 anchor → 策略网络 → Control | `pointGoalNavigation/PointGoalNavigationFragment.java:101-120`；位姿来自 `pointGoalNavigation/ArCore.java:196` `currentPose = camera.getPose()` |
| 物体导航（ObjectNav） | 检测 + 跟踪器 → Control | `objectNav/ObjectNavFragment.java:530` |
| 旧版 CameraActivity | 手柄 / 手机 / autopilot 事件 | `original/CameraActivity.java:1384-1392` |

整棵树里搜不到 `TICKS_PER_REV`、轮径、周长，也没有任何把 RPM 积分成距离的代码；同样没有"走 X 米""转到 Y 度"这类接口。

## 轮速实际被用到的四处

1. **界面显示。** `logging/LoggerFragment.java:453-460`、`robot/FreeRoamFragment.java:129-133`、`objectNav/ObjectNavFragment.java:389-393`、`autopilot/AutopilotFragment.java:313-317`、`robot/RobotInfoFragment.java:171-176`，都是把左右轮 RPM 刷到 speedInfo 标签上。iOS 的 `RobotInfoFrame.swift:625-633` 同理。
   iOS 有个坑：`AutopilotFragment.swift:166`、`PointGoalFragment.swift:475`、`ObjectTrackingFragment.swift:169` 里 `updateRpmLabel` 发的是 `control.getLeft()/getRight()`，标签写着 rpm，显示的其实是命令值。
2. **数据采集。** Android `logging/SensorService.java:204` 写 `ctrl.csv`（leftCtrl,rightCtrl，命令值），`:215` 写 `wheels.csv`（leftWheel,rightWheel，实测值）；iOS `Data/DataLogger.swift:314` 把 speedometer 写进 wheels 文件。轮速在数据集里是记录项，不参与控制。
3. **脚本 API。** Android `projects/BotFunctions.java:169-172` 的 `speedReading()` 返回左右轮 RPM 平均；同文件 `:179-187` 的 `frontWheelReading()` / `backWheelReading()` 返回的其实是"有没有装轮速传感器"的布尔量（名字容易误会）。iOS `JsEvaluator/JsEvaluator.swift:863` 和 `:882` 的 `backWheelReading()` / `frontWheelReading()` 返回实测 RPM——注意 `backWheelReading()` 的实现返回右侧值，注释却写 right front。
4. **唯一一次真反馈。** iOS `JsEvaluator/JsEvaluator.swift:528-543`（`while` 在 540 行）：脚本调用 `stop()` 后循环重发 `c0,0`，直到 `bluetooth.speedometer == "w0.00,0.00"` 才退出，也就是用编码器确认轮子真的停了。Android 侧没有对应的等待实现。

## 对我们移植的意义

- 原版 App 的"到点"从来不依赖里程：跟随看目标框的大小和位置，点对点看 ARCore 的 `computeDistance(target, current)`（`PointGoalNavigationFragment.java:101-107`，阈值 0.15 m）。我们照搬这个结构是对的。
- 这台 520 的轮速读数本身也撑不起里程（见 `../ARIndoorNav-original/HANDOVER.zh-CN.md` §3.6.1），所以 `w` 帧最多用来做"轮子在不在转""确认停住"这类开关量，不要引入里程计。

