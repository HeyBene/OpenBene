# OpenBene LiDAR Capture 工作日志

## 当前目标
- 主线目标：让 iPhone 成为 OpenBene 的空间采集端，先完成 **Nerfstudio 风格数据采集与重建验证**。
- 当前阶段：**采集端基础链路已跑通，正在把无线传输链和重建验证链同时稳定下来**。

## 当前交接结论（Windows 接手前必看）
- iOS 真机采集链已跑通：可以稳定导出 `images/`、`depth/`、`transforms.json`，并已在 Mac 上完成 AirDrop 后的 Nerfstudio 读取、训练、点云 sanity check、以及一次成功的渲染出图链打通。
- 无线 WebSocket 链已完成一次完整成功闭环：iPhone -> receiver -> `images/ + depth/ + transforms.json + fused_pointcloud.ply`。说明基础无线数据链已经打通，但仍建议在 Windows 端至少再连续验证 2~3 轮稳定性后，再完全依赖无线流作为训练输入。
- 新增了第一版“会话结束后上传轻量融合点云”的 side-channel：不会破坏现有逐帧 RGB/depth/manifest 上传协议，只在 receiver 声明支持 `pointcloud_v1` 时，额外上传 `fused_pointcloud.ply`。
- 现在推荐的机器分工是：**Mac 负责 iPhone app 与真机采集验证；Windows RTX 5060 负责 Nerfstudio 正式训练与后续建图/定位研究。**

## 已踩过的关键坑（请避免重复）
- 只改真实源码目录：`openbene-lidar-capture-ios/Lidarcapture/Lidarcapture/`。仓库里的 `openbene-lidar-capture-ios/OpenBeneLidarCapture/` 不是当前 Xcode 实际使用的源码目录。
- Nerfstudio 在当前环境下训练很慢，Mac M4 只能做小规模 sanity check，不建议作为正式长训主力机。
- `ns-render` 在当前 Python / PyTorch 2.6 环境下，直接读取 Nerfstudio checkpoint 会被 `torch.load(weights_only=True)` 的默认安全策略拦住；需要显式以受信任本地 checkpoint 的方式关闭 `weights_only` 才能渲染成功。
- 早期 session 里出现过 `images/depth/transforms` 数量不一致的问题；当前已知一份更健康的样本是 `session_1774409566`，它的 pose 统计明显更稳定，适合作为 Windows 端继续训练验证的起点。
- 点云 sanity check 很有用，但它是**辅助诊断层**，不是最终地图真相；主数据资产仍然是 `RGB + depth + pose + intrinsics`。

## Windows 端下一步建议
1. `git pull`
2. 继续以 `openbene-lidar-capture-ios/Lidarcapture/Lidarcapture/` 为唯一 iOS 源码目录
3. 先复现/确认无线 receiver 连续多轮稳定接收
4. 以 `session_1774409566` 为基线数据集，在 RTX 5060 上继续正式训练与新视角/更长步数验证
5. 如继续扩展无线点云链，优先保持“session-end pointcloud side-channel”方案，不要先改成逐帧点云流

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

## Windows 新机器交接 SOP（WSL2 Ubuntu + ROS2 Humble）

适用场景：把项目交给另一台 Windows 电脑，后续在该机器上继续完成 ROS2 bridge、回放验证和后续建图/定位研究。

### 目标机器角色
- Windows 主机：代码托管、数据落盘、必要时运行 receiver
- WSL2 Ubuntu：ROS2 Humble 与 Python bridge 主要运行环境
- iPhone：继续作为采集端

### 推荐最小安装项
1. Windows 11
2. Git for Windows
3. WSL2 + Ubuntu 22.04
4. Python 3.10（Ubuntu 内）
5. ROS2 Humble（Ubuntu 内）

### 交接后的目录建议
- Windows 仓库根目录：按接手人习惯放置，但建议避免中文路径
- WSL2 内仓库路径：建议重新 clone 到 Linux 文件系统，例如：`~/OpenBene_git`
- 会话数据目录建议单独保留，例如：`~/openbene_sessions/`

不要把 ROS2 主运行环境长期放在 `/mnt/c/...` 下，避免 Python/文件监听/IO 性能与权限问题。

### 首次交接后的最小流程
1. 在 Windows 安装 Git 并完成仓库拉取
2. 在 WSL2 Ubuntu 22.04 中安装 ROS2 Humble
3. 在 WSL2 中重新 clone 本仓库
4. 在 WSL2 中安装 `openbene_sdk` 所需 Python 依赖
5. 用一份已知健康 session 先跑 replay bridge
6. 确认 `ros2 topic list`、`ros2 topic echo /openbene/camera/pose` 正常

### 已知推荐基线数据
- `session_1774409566`

它适合作为 Windows/WSL2 新机器上的第一份 replay 验证数据，用于先确认 bridge/ROS2 topic 是否正常，再继续做更复杂实验。

### 本次交接建议优先补充/核对的内容
- 安装与依赖：见 `docs/ROS2_BRIDGE_V1.md`
- ROS2 bridge 入口：`openbene_sdk/src/openbene/session_ros2_bridge.py`
- live bridge scaffold：`openbene_sdk/src/openbene/live_ros2_bridge.py`

### 交接时必须口头确认的事项
- 当前主线仍然是“先 session replay，再 live bridge”，不是直接切到整套实时 ROS2 在线系统
- iOS 真正有效源码目录仍然只有：`openbene-lidar-capture-ios/Lidarcapture/Lidarcapture/`
- `captured_data/`、`outputs/` 这类目录更像实验/产物目录，不默认作为长期源码资产提交

## 备注
- 以后提交时，不再添加 Claude co-author 信息。
- 以后代码里的注释尽量保持简洁中文，方便后续理解。
