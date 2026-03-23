import Foundation
import ARKit
import CoreVideo

/// A single captured frame's data, ready for writing/uploading.
struct CaptureFrameRecord {
    let index: Int
    let timestamp: TimeInterval

    // Camera intrinsics
    let flX: Float
    let flY: Float
    let cx: Float
    let cy: Float
    let width: Int
    let height: Int

    // Camera-to-world 4x4 transform (column-major from ARKit)
    let transformMatrix: simd_float4x4

    // RGB pixel buffer
    let pixelBuffer: CVPixelBuffer

    // Depth (nil on non-LiDAR devices)
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
