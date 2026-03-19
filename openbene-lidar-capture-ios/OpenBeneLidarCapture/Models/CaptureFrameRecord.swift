import Foundation
import ARKit
import CoreVideo

/// 单帧采集记录。
/// 这是本地写盘和网络上传共用的中间数据结构。
struct CaptureFrameRecord {
    let index: Int
    let timestamp: TimeInterval

    // 相机内参
    let flX: Float
    let flY: Float
    let cx: Float
    let cy: Float
    let width: Int
    let height: Int

    // 相机位姿。ARKit 给的是 camera-to-world 变换矩阵。
    let transformMatrix: simd_float4x4

    // 原始 RGB 图像缓冲区。
    let pixelBuffer: CVPixelBuffer

    // 深度图。无 LiDAR 设备时为 nil。
    let depthBuffer: CVPixelBuffer?
    let depthWidth: Int
    let depthHeight: Int

    init(frame: ARFrame, index: Int, depthAvailable: Bool) {
        self.index = index
        self.timestamp = frame.timestamp

        let intrinsics = frame.camera.intrinsics
        let imageResolution = frame.camera.imageResolution
        self.flX = intrinsics[0][0]
        self.flY = intrinsics[1][1]
        self.cx = intrinsics[2][0]
        self.cy = intrinsics[2][1]
        self.width = Int(imageResolution.width)
        self.height = Int(imageResolution.height)

        self.transformMatrix = frame.camera.transform
        self.pixelBuffer = frame.capturedImage

        // 当前先直接使用 sceneDepth，后续如果需要更平滑的数据可切到 smoothedSceneDepth。
        if depthAvailable, let sceneDepth = frame.sceneDepth {
            self.depthBuffer = sceneDepth.depthMap
            self.depthWidth = CVPixelBufferGetWidth(sceneDepth.depthMap)
            self.depthHeight = CVPixelBufferGetHeight(sceneDepth.depthMap)
        } else {
            self.depthBuffer = nil
            self.depthWidth = 0
            self.depthHeight = 0
        }
    }
}
