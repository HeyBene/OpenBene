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
    let depthSourceRaw: String

    // Confidence map aligned with depth (optional)
    let confidenceBuffer: CVPixelBuffer?
    let confidenceWidth: Int
    let confidenceHeight: Int

    // Tracking state for downstream frame filtering
    let trackingStateRaw: String

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
        self.trackingStateRaw = Self.trackingStateRaw(from: frame.camera.trackingState)

        self.pixelBuffer = frame.capturedImage

        if depthAvailable {
            if #available(iOS 14.0, *), let smoothedDepth = frame.smoothedSceneDepth {
                self.depthBuffer = smoothedDepth.depthMap
                self.depthWidth = CVPixelBufferGetWidth(smoothedDepth.depthMap)
                self.depthHeight = CVPixelBufferGetHeight(smoothedDepth.depthMap)
                self.depthSourceRaw = "smoothed_scene_depth"
                self.confidenceBuffer = Self.confidenceBuffer(from: smoothedDepth)
                if let confidenceBuffer {
                    self.confidenceWidth = CVPixelBufferGetWidth(confidenceBuffer)
                    self.confidenceHeight = CVPixelBufferGetHeight(confidenceBuffer)
                } else {
                    self.confidenceWidth = 0
                    self.confidenceHeight = 0
                }
            } else if let sceneDepth = frame.sceneDepth {
                self.depthBuffer = sceneDepth.depthMap
                self.depthWidth = CVPixelBufferGetWidth(sceneDepth.depthMap)
                self.depthHeight = CVPixelBufferGetHeight(sceneDepth.depthMap)
                self.depthSourceRaw = "scene_depth"
                self.confidenceBuffer = Self.confidenceBuffer(from: sceneDepth)
                if let confidenceBuffer {
                    self.confidenceWidth = CVPixelBufferGetWidth(confidenceBuffer)
                    self.confidenceHeight = CVPixelBufferGetHeight(confidenceBuffer)
                } else {
                    self.confidenceWidth = 0
                    self.confidenceHeight = 0
                }
            } else {
                self.depthBuffer = nil
                self.depthWidth = 0
                self.depthHeight = 0
                self.depthSourceRaw = "none"
                self.confidenceBuffer = nil
                self.confidenceWidth = 0
                self.confidenceHeight = 0
            }
        } else {
            self.depthBuffer = nil
            self.depthWidth = 0
            self.depthHeight = 0
            self.depthSourceRaw = "none"
            self.confidenceBuffer = nil
            self.confidenceWidth = 0
            self.confidenceHeight = 0
        }
    }

    private static func trackingStateRaw(from trackingState: ARCamera.TrackingState) -> String {
        switch trackingState {
        case .normal:
            return "normal"
        case .notAvailable:
            return "not_available"
        case .limited(let reason):
            switch reason {
            case .initializing:
                return "limited_initializing"
            case .excessiveMotion:
                return "limited_excessive_motion"
            case .insufficientFeatures:
                return "limited_insufficient_features"
            case .relocalizing:
                return "limited_relocalizing"
            @unknown default:
                return "limited_unknown"
            }
        }
    }

    private static func confidenceBuffer(from depthData: ARDepthData) -> CVPixelBuffer? {
        if #available(iOS 14.0, *) {
            return depthData.confidenceMap
        }
        return nil
    }
}
