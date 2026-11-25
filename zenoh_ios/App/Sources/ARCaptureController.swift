import ARKit
import CoreImage
import Foundation
import ImageIO
import OpenBeneZenoh
import UIKit
import UniformTypeIdentifiers

/// Streams ARKit camera frames with depth, confidence and pose at a fixed rate.
final class ARCaptureController: NSObject, ARSessionDelegate {
    private let session = ARSession()
    private let queue = DispatchQueue(label: "io.openbene.ar.capture", qos: .userInitiated)
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])
    private let onFrame: (CaptureFrame) -> Void
    private let onStatus: (String) -> Void

    private var frameID: UInt32 = 0
    private var lastPublished: CFTimeInterval = 0
    private let minimumInterval: CFTimeInterval = 0.2 // 5 fps
    private let maxWidth: CGFloat = 1280

    init(onFrame: @escaping (CaptureFrame) -> Void, onStatus: @escaping (String) -> Void) {
        self.onFrame = onFrame
        self.onStatus = onStatus
    }

    func start() {
        let configuration = ARWorldTrackingConfiguration()
        var supportsDepth = false
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.smoothedSceneDepth) {
            configuration.frameSemantics.insert(.smoothedSceneDepth)
            supportsDepth = true
        } else if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
            configuration.frameSemantics.insert(.sceneDepth)
            supportsDepth = true
        }
        session.delegateQueue = queue
        session.delegate = self
        session.run(configuration, options: [])
        onStatus(supportsDepth
                 ? "ARKit：RGB + 深度 + 置信度 + 位姿 @5fps"
                 : "ARKit：RGB + 位姿（此设备无深度）@5fps")
    }

    func stop() {
        session.pause()
        session.delegate = nil
    }

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        let now = CACurrentMediaTime()
        guard now - lastPublished >= minimumInterval else { return }
        lastPublished = now
        guard let capture = makeCaptureFrame(from: frame) else { return }
        onFrame(capture)
    }

    private func makeCaptureFrame(from frame: ARFrame) -> CaptureFrame? {
        guard let camera = encodeCamera(frame.capturedImage) else { return nil }

        var depthPNG: Data?
        var confidencePNG: Data?
        var depthWidth = 0
        var depthHeight = 0
        var confidenceWidth = 0
        var confidenceHeight = 0
        var depthSource = "none"

        if let depth = frame.smoothedSceneDepth {
            depthSource = "smoothed_scene_depth"
            depthPNG = encodeDepthPNG(depth.depthMap)
            depthWidth = CVPixelBufferGetWidth(depth.depthMap)
            depthHeight = CVPixelBufferGetHeight(depth.depthMap)
            if let confidence = depth.confidenceMap {
                confidencePNG = encodeConfidencePNG(confidence)
                confidenceWidth = CVPixelBufferGetWidth(confidence)
                confidenceHeight = CVPixelBufferGetHeight(confidence)
            }
        } else if let depth = frame.sceneDepth {
            depthSource = "scene_depth"
            depthPNG = encodeDepthPNG(depth.depthMap)
            depthWidth = CVPixelBufferGetWidth(depth.depthMap)
            depthHeight = CVPixelBufferGetHeight(depth.depthMap)
            if let confidence = depth.confidenceMap {
                confidencePNG = encodeConfidencePNG(confidence)
                confidenceWidth = CVPixelBufferGetWidth(confidence)
                confidenceHeight = CVPixelBufferGetHeight(confidence)
            }
        }

        let intrinsics = frame.camera.intrinsics
        let metadata = FrameMetadata(
            width: camera.width,
            height: camera.height,
            depthWidth: depthWidth,
            depthHeight: depthHeight,
            fx: Double(intrinsics.columns.0.x),
            fy: Double(intrinsics.columns.1.y),
            cx: Double(intrinsics.columns.2.x),
            cy: Double(intrinsics.columns.2.y),
            trackingState: Self.trackingStateName(frame.camera.trackingState),
            depthSource: depthSource,
            confidenceWidth: confidenceWidth,
            confidenceHeight: confidenceHeight
        )

        frameID &+= 1
        return CaptureFrame(
            frameID: frameID,
            timestampNs: UInt64(Date().timeIntervalSince1970 * 1_000_000_000),
            rgbJPEG: camera.jpeg,
            depthPNG: depthPNG,
            confidencePNG: confidencePNG,
            pose: Self.poseArray(frame.camera.transform),
            metadata: metadata
        )
    }

    private func encodeCamera(_ pixelBuffer: CVPixelBuffer) -> (jpeg: Data, width: Int, height: Int)? {
        let image = CIImage(cvPixelBuffer: pixelBuffer)
        let scale = min(1, maxWidth / image.extent.width)
        let scaled = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        guard let cgImage = ciContext.createCGImage(scaled, from: scaled.extent) else { return nil }
        guard let jpeg = UIImage(cgImage: cgImage).jpegData(compressionQuality: 0.6) else { return nil }
        return (jpeg, cgImage.width, cgImage.height)
    }

    /// Float32 metres to 16-bit millimetre PNG, matching the LiDAR capture pipeline.
    private func encodeDepthPNG(_ buffer: CVPixelBuffer) -> Data? {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }
        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        let floats = base.assumingMemoryBound(to: Float32.self)
        let count = width * height

        var millimetres = [UInt16](repeating: 0, count: count)
        for index in 0..<count {
            let metres = floats[index]
            if metres.isFinite, metres > 0 {
                millimetres[index] = UInt16(min(max(metres * 1000, 0), 65_535))
            }
        }
        return millimetres.withUnsafeMutableBytes { raw -> Data? in
            guard let context = CGContext(
                data: raw.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 16,
                bytesPerRow: width * MemoryLayout<UInt16>.size,
                space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.none.rawValue | CGBitmapInfo.byteOrder16Little.rawValue
            ), let image = context.makeImage() else { return nil }
            return Self.pngData(from: image)
        }
    }

    private func encodeConfidencePNG(_ buffer: CVPixelBuffer) -> Data? {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }
        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        guard let context = CGContext(
            data: base,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ), let image = context.makeImage() else { return nil }
        return Self.pngData(from: image)
    }

    private static func pngData(from image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data as CFMutableData,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }

    private static func poseArray(_ matrix: simd_float4x4) -> [Float] {
        [
            matrix.columns.0.x, matrix.columns.0.y, matrix.columns.0.z, matrix.columns.0.w,
            matrix.columns.1.x, matrix.columns.1.y, matrix.columns.1.z, matrix.columns.1.w,
            matrix.columns.2.x, matrix.columns.2.y, matrix.columns.2.z, matrix.columns.2.w,
            matrix.columns.3.x, matrix.columns.3.y, matrix.columns.3.z, matrix.columns.3.w,
        ]
    }

    private static func trackingStateName(_ state: ARCamera.TrackingState) -> String {
        switch state {
        case .normal: return "normal"
        case .notAvailable: return "not_available"
        case .limited(let reason):
            switch reason {
            case .initializing: return "limited_initializing"
            case .excessiveMotion: return "limited_excessive_motion"
            case .insufficientFeatures: return "limited_insufficient_features"
            case .relocalizing: return "limited_relocalizing"
            @unknown default: return "limited_unknown"
            }
        }
    }
}
