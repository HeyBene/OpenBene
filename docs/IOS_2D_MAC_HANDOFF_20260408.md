# OpenBene iOS App 2D Handoff

本文件只给 Mac 端 iOS AI。

目标很明确:

1. 默认只做 2D，不考虑 3D。
2. 采集端必须把真正对 2D ROS2 有用的数据采出来并传出去。
3. 实时 `localization` 模式尽量不发 RGB，只发 depth 主线。

我这边会负责 `openbene_ros2/` 和 PC 侧兼容；你只改 iOS App。

## 1. 只改这些目录

- `openbene-lidar-capture-ios/Lidarcapture/Lidarcapture/`

重点文件:

- `Models/CaptureFrameRecord.swift`
- `Capture/CaptureSessionManager.swift`
- `Transport/UploadProtocol.swift`
- `Transport/PreparedFrameEncoder.swift`
- `Transport/WebSocketUploadClient.swift`
- `Transport/CaptureUploadCoordinator.swift`
- `Dataset/NerfstudioDatasetWriter.swift`

不要修改:

- `openbene_ros2/`
- `openbene_sdk/`
- Python receiver / ROS2 协议解析代码

## 2. 当前已确认的问题

当前实时 2D 主线是错位的:

- App 的 `localization` 实时上传现在走 `sendRealtimeFrame()`
- 但 `sendRealtimeFrame()` 现在只发 RGB JPEG
- ROS2 实时 2D 这边真正用的是 depth，不需要 RGB

所以必须改成:

- `mapping` 会话上传: 可以继续发 RGB + depth
- `localization` 实时上传: 优先发 depth，可选 confidence，不发 RGB

## 3. 需要达到的最终行为

### 3.1 每帧记录的数据

每个 `CaptureFrameRecord` 至少要包含:

- `timestamp`
- 相机内参 `fl_x / fl_y / cx / cy / w / h`
- `transformMatrix`
- `trackingState`
- `depthSource`
- `depthBuffer`
- `confidenceBuffer` 可选
- `depthWidth / depthHeight`
- `confidenceWidth / confidenceHeight`
- `pixelBuffer` 可保留，但 2D 实时链路不一定上传

### 3.2 深度来源

默认优先级:

1. `frame.smoothedSceneDepth`
2. `frame.sceneDepth`

也就是说:

- 能拿到 `smoothedSceneDepth` 就优先用它
- 拿不到时再 fallback 到 `sceneDepth`
- 需要把最终使用的是哪一种写进 record 和 manifest

建议字段:

- `depthSourceRaw: String`

建议取值:

- `smoothed_scene_depth`
- `scene_depth`
- `none`

### 3.3 confidence map

如果 ARKit 当前深度对象能提供 `confidenceMap`，就一起记录:

- 写入 `CaptureFrameRecord`
- 离线会话写到磁盘
- 实时 `localization` 模式一起上传

建议:

- confidence 以单通道 PNG 保存
- 保持原始离散值，不要自己重新归一化成花哨格式
- 如果是 8-bit 单通道，就按 8-bit PNG 存

### 3.4 tracking state

每帧必须记录 `trackingState`。

不要只存 UI 文本，单独存一个稳定字段，供后端过滤。

建议字段:

- `trackingStateRaw: String`

建议值:

- `normal`
- `not_available`
- `limited_initializing`
- `limited_excessive_motion`
- `limited_insufficient_features`
- `limited_relocalizing`
- `limited_unknown`

## 4. 按文件的具体修改要求

### 4.1 `Models/CaptureFrameRecord.swift`

当前问题:

- 只有 `sceneDepth.depthMap`
- 没有 confidence
- 没有 tracking state
- 没有 depth source

必须修改为:

1. 初始化时优先取 `frame.smoothedSceneDepth ?? frame.sceneDepth`
2. 记录本帧实际使用的深度来源
3. 记录 `frame.camera.trackingState`
4. 如果深度对象提供 `confidenceMap`，把它也存下来
5. 增加对应宽高字段

建议新增字段:

- `trackingStateRaw: String`
- `depthSourceRaw: String`
- `confidenceBuffer: CVPixelBuffer?`
- `confidenceWidth: Int`
- `confidenceHeight: Int`

另外建议在这个文件里新增一个静态 helper，把 `ARCamera.TrackingState` 转成稳定字符串，避免多个地方重复写。

### 4.2 `Capture/CaptureSessionManager.swift`

目标:

- session 配置时就尽量启用更适合 2D 的深度语义
- `CaptureFrameRecord` 新字段自动进入后续链路

需要做:

1. 在 `startSession()` 里，LiDAR 可用时优先启用 `smoothedSceneDepth` 语义；如果工程版本限制，至少保证后续取值时优先用 `frame.smoothedSceneDepth`
2. 现有 `writeFrame()` 不需要大改，但要确认它创建的 `CaptureFrameRecord` 已经带上新字段
3. UI 可选增强:
   - 当前帧 tracking state
   - 当前 depth source
   - 是否有 confidence

UI 增强不是强制项，数据正确性是强制项。

### 4.3 `Transport/UploadProtocol.swift`

当前问题:

- `PreparedCaptureFramePayload` 只有 RGB 和 depth
- 不支持 confidence
- `sendRealtimeFrame()` 只接受 `CaptureFrameRecord`，不够表达“是否发 RGB”

建议改成:

- `rgbJPEGData: Data?`
- `depthPNGData: Data?`
- `confidencePNGData: Data?`

并允许 payload 表达:

- 会话上传可以有 RGB
- 实时 2D 上传没有 RGB 也合法

如果需要，可以把 `sendRealtimeFrame` 改成直接接收 `PreparedCaptureFramePayload`，而不是只收 `CaptureFrameRecord`。

推荐新签名:

- `func sendRealtimeFrame(_ payload: PreparedCaptureFramePayload)`

### 4.4 `Transport/PreparedFrameEncoder.swift`

必须补齐三种编码:

1. RGB -> JPEG
2. depth -> 16-bit PNG
3. confidence -> 单通道 PNG

要求:

- `preparePayload(for:)` 返回的新 payload 必须包含 `confidencePNGData`
- depth 继续保持毫米制 16-bit PNG
- confidence 不要做视觉化着色，直接单通道保存

建议新增:

- `encodeConfidenceAsPNGData(_ confidenceBuffer: CVPixelBuffer) -> Data?`

### 4.5 `Transport/WebSocketUploadClient.swift`

这是最关键的改动点。

#### A. 会话上传 `sendFrame(_:)`

保留兼容行为，但增加 metadata 字段:

- `has_image`
- `has_depth`
- `has_confidence`
- `tracking_state`
- `depth_source`
- `confidence_width`
- `confidence_height`

当前 `buildFrameMetadata()` 只有 `has_depth`，不够。

二进制发送顺序建议固定为:

1. image，如果 `has_image == true`
2. depth，如果 `has_depth == true`
3. confidence，如果 `has_confidence == true`

#### B. 实时上传 `sendRealtimeFrame(_:)`

必须改成服务于 2D `localization`:

- 不发 RGB
- 发 depth
- 如果有 confidence，再发 confidence
- metadata 里明确 `has_image = false`

也就是说实时 2D metadata 至少要带:

- `type: "frame"`
- `transfer_mode: "live"`
- `index`
- `timestamp`
- `fl_x / fl_y / cx / cy / w / h`
- `transform_matrix`
- `has_image: false`
- `has_depth: true/false`
- `has_confidence: true/false`
- `depth_width`
- `depth_height`
- `confidence_width`
- `confidence_height`
- `tracking_state`
- `depth_source`

要求:

- `localization` 模式下，不再临时现场把 RGB 编码出来再上传
- 如果当前帧没有 depth，就直接跳过，不要发一帧空 live frame

#### C. 兼容性要求

不要删除已有字段:

- `type`
- `index`
- `timestamp`
- `fl_x / fl_y / cx / cy / w / h`
- `transform_matrix`
- `transfer_mode`

只是在此基础上新增字段。

### 4.6 `Transport/CaptureUploadCoordinator.swift`

这里要保证 `localization` 模式真的走 2D depth-only 实时链路。

当前逻辑:

- localization 模式节流后调用 `uploadClient.sendRealtimeFrame(payload.record)`

建议改成:

- 直接把 `PreparedCaptureFramePayload` 传给 `sendRealtimeFrame`
- `sendRealtimeFrame` 使用已经编码好的 depth/confidence
- 不要在实时路径再次重复编码 RGB

仍然保留当前节流逻辑即可。

### 4.7 `Dataset/NerfstudioDatasetWriter.swift`

当前问题:

- 只写 `images/` 和 `depth/`
- `transforms.json` 没有 tracking state / depth source / confidence path

必须改成:

#### A. 目录结构

在有 confidence 时增加:

- `confidence/`

#### B. 每帧写盘

每帧除了现有:

- `images/000000.jpg`
- `depth/000000.png`

还要支持:

- `confidence/000000.png`

#### C. `transforms.json` 中每帧新增字段

建议新增:

- `tracking_state`
- `depth_source`
- `confidence_file_path`

如果愿意更完整，也可以加:

- `confidence_width`
- `confidence_height`

#### D. 是否保留 RGB

离线 session 先不要取消 RGB。

原因:

- 现在 PC/已有数据集工具还依赖传统 `images/ + depth/ + transforms.json`
- 这一步先只把实时 2D 去 RGB，不要把离线格式一起推翻

## 5. 推荐的 metadata 契约

请严格按下面字段发，PC 侧我来适配:

```json
{
  "type": "frame",
  "index": 12,
  "timestamp": 123456.789,
  "fl_x": 1000.0,
  "fl_y": 1000.0,
  "cx": 320.0,
  "cy": 240.0,
  "w": 1920,
  "h": 1440,
  "transform_matrix": [[...], [...], [...], [...]],
  "transfer_mode": "live",
  "has_image": false,
  "has_depth": true,
  "has_confidence": true,
  "depth_width": 256,
  "depth_height": 192,
  "confidence_width": 256,
  "confidence_height": 192,
  "tracking_state": "normal",
  "depth_source": "smoothed_scene_depth"
}
```

二进制顺序:

1. `image` 仅当 `has_image == true`
2. `depth` 仅当 `has_depth == true`
3. `confidence` 仅当 `has_confidence == true`

## 6. 真机测试要求

Mac 端 AI 改完后，至少做下面 4 个测试:

### 测试 1: mapping 会话导出

确认能稳定生成:

- `images/`
- `depth/`
- `confidence/` 如果有
- `transforms.json`

并检查 `transforms.json` 每帧新增字段是否真实存在。

### 测试 2: localization 实时上传

确认实时模式下:

- PC 端仍能收到帧
- App 不再发送 RGB
- 深度帧持续发送
- confidence 有则发送

### 测试 3: tracking state 变化

在以下场景分别抓几帧，确认写出的 `tracking_state` 正确:

- 正常稳定
- 快速移动
- 特征不足
- relocalizing

### 测试 4: smoothed depth 生效

确认实际发送/保存的不是老的 `sceneDepth` 优先路径，而是:

- 能拿到 `smoothedSceneDepth` 时优先使用它
- fallback 才使用 `sceneDepth`

## 7. 交付时必须反馈给我什么

每次提交后，请给我下面这些结果:

1. 改了哪些 Swift 文件
2. `localization` 模式是否已经不发 RGB
3. metadata 实际新增了哪些字段
4. `transforms.json` 实际新增了哪些字段
5. 是否确认拿到了 `smoothedSceneDepth`
6. 是否确认拿到了 `confidenceMap`
7. 真机测试里哪一种 tracking state 被实际记录到了
8. 如果有阻塞，是 API 拿不到，还是编码/上传出了问题

## 8. 可以直接发给 Mac 端 AI 的指令

```text
你只负责修改 openbene-lidar-capture-ios/，不要改 Python、ROS2、receiver。

当前目标是 2D，不考虑 3D。

请按下面要求修改 iOS App:

1. CaptureFrameRecord:
   - 优先使用 frame.smoothedSceneDepth，fallback 到 frame.sceneDepth
   - 增加 tracking_state
   - 增加 depth_source
   - 增加 confidenceBuffer / confidenceWidth / confidenceHeight

2. PreparedFrameEncoder:
   - 保留 RGB JPEG 编码
   - 保留 depth 16-bit PNG 编码
   - 新增 confidence 单通道 PNG 编码

3. UploadProtocol:
   - PreparedCaptureFramePayload 改为可同时表达 rgb/depth/confidence，其中 rgb 可为空
   - sendRealtimeFrame 改为接收 PreparedCaptureFramePayload

4. WebSocketUploadClient:
   - frame metadata 新增:
     has_image, has_depth, has_confidence, tracking_state, depth_source,
     confidence_width, confidence_height
   - session 上传允许 image/depth/confidence
   - localization 实时上传改为 depth-only，可选 confidence，不发 RGB
   - 二进制顺序固定为 image -> depth -> confidence（存在才发）

5. CaptureUploadCoordinator:
   - localization 模式直接把 PreparedCaptureFramePayload 传给 sendRealtimeFrame

6. NerfstudioDatasetWriter:
   - 有 confidence 时新增 confidence/ 目录
   - 写 confidence PNG
   - transforms.json 每帧新增 tracking_state、depth_source、confidence_file_path

请只改 iOS 工程，并在完成后反馈:
- 改了哪些文件
- localization 是否已不发 RGB
- 是否拿到了 smoothedSceneDepth
- 是否拿到了 confidenceMap
- transforms.json 的新增字段
- 一次真机测试结果
```
