# OpenBene LiDAR Capture 工作日志

## 当前目标
- 主线目标：让 iPhone 成为 OpenBene 的空间采集端，先完成 **Nerfstudio 风格数据采集与重建验证**。
- 当前阶段：**修通 iOS 工程编译，确保采集端基础链路可运行**。

## 当前结论
- 当前不优先上 ROS。
- 当前不切换到 Arvos 主线。
- 当前主线仍然是：
  1. 自研 iOS 采集端
  2. 本地写 Nerfstudio 风格数据集
  3. 后续再加上传 / 接收 / 重建 / 定位 / 导航

## 当前实现状态
### 已完成
- 已建立 standalone iOS 采集项目目录：`openbene-lidar-capture-ios/`
- 已有基础 Swift 文件：
  - `OpenBeneLidarCapture/App/OpenBeneLidarCaptureApp.swift`
  - `OpenBeneLidarCapture/UI/RootView.swift`
  - `OpenBeneLidarCapture/Capture/CaptureSessionManager.swift`
  - `OpenBeneLidarCapture/Capture/FrameAcceptancePolicy.swift`
  - `OpenBeneLidarCapture/Models/DeviceCapabilities.swift`
  - `OpenBeneLidarCapture/Models/CaptureFrameRecord.swift`
  - `OpenBeneLidarCapture/Dataset/NerfstudioDatasetWriter.swift`
  - `OpenBeneLidarCapture/Utils/PoseTransformAdapter.swift`
  - `OpenBeneLidarCapture/Transport/UploadProtocol.swift`
  - `OpenBeneLidarCapture/Transport/WebSocketUploadClient.swift`
- 已给关键 Swift 文件补充简洁中文注释
- 已推送提交：`0a3f9c9`

### 正在处理
- Xcode 命令行编译
- 校准仓库内代码目录与 Mac 本地 Xcode 工程目录之间的关系

## 重要路径说明（非常关键）

### 当前唯一有效的 iOS 源码目录

- `openbene-lidar-capture-ios/Lidarcapture/Lidarcapture/`

### 当前唯一有效的 Xcode 工程

- `openbene-lidar-capture-ios/Lidarcapture/Lidarcapture.xcodeproj`

### 当前有效的 Xcode scheme

- `Lidarcapture`

### 仓库里另一套同名功能源码目录

- `openbene-lidar-capture-ios/OpenBeneLidarCapture/`

这套目录当前**不是 Xcode 实际编译使用的主目录**。

## 对这个差异的判断

### 会不会导致同步偏差？

**会。并且已经确认存在两套并行源码。**

### 已确认事实

- `Lidarcapture.xcodeproj` 实际编译使用的是：
  - `openbene-lidar-capture-ios/Lidarcapture/Lidarcapture/...`
- 仓库中还存在另一套相似源码：
  - `openbene-lidar-capture-ios/OpenBeneLidarCapture/...`

### 当前真正的风险

不是 git 本身，而是：

- Windows 上如果继续改 `OpenBeneLidarCapture/`，Mac 上编译结果不会反映这些改动
- 会出现“已经同步但编译没变化”的假象
- 后续如果两套代码继续同时演化，理解和维护成本会迅速上升

## 当前临时规则（立即执行）

### 规则 1

当前阶段所有 iOS 编译相关修改，**只改这套目录**：

- `openbene-lidar-capture-ios/Lidarcapture/Lidarcapture/...`

### 规则 2

当前阶段暂时**不要再修改**：

- `openbene-lidar-capture-ios/OpenBeneLidarCapture/...`

### 规则 3

等编译跑通后，再单独做一次目录结构清理与统一命名。

## 当前已知编译信息

- Mac 当前仓库路径：`/Users/fandi/Desktop/OpenBene_git`
- 正确工程路径：`/Users/fandi/Desktop/OpenBene_git/openbene-lidar-capture-ios/Lidarcapture/Lidarcapture.xcodeproj`
- 正确 scheme：`Lidarcapture`
- 最近一次编译失败位置：
  - `openbene-lidar-capture-ios/Lidarcapture/Lidarcapture/Dataset/NerfstudioDatasetWriter.swift`

## 下次开始前固定流程

1. `git pull`
2. 先看本文件 `docs/WORKLOG.md`
3. 只在以下目录里修改 iOS 采集源码：
   - `openbene-lidar-capture-ios/Lidarcapture/Lidarcapture/`
4. 编译命令固定使用：
   - `xcodebuild -project openbene-lidar-capture-ios/Lidarcapture/Lidarcapture.xcodeproj -scheme Lidarcapture -destination 'generic/platform=iOS' build`
5. 不再使用 `OpenBeneLidarCapture/` 目录作为当前开发主目录

## 当前下一步

### 第一优先级

在 Mac 上直接进入真实源码目录继续修复 `NerfstudioDatasetWriter.swift` 编译错误。

### 第二优先级

等编译跑通后，规划并执行一次目录结构统一。

## 备注
- 以后提交时，不再添加 Claude co-author 信息。
- 以后代码里的注释尽量保持简洁中文，方便后续理解。
