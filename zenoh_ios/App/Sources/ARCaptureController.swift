import ARKit
import AVFoundation
import CoreImage
import Foundation
import OpenBeneZenoh
import UIKit
import UniformTypeIdentifiers

/// Streams ARKit camera frames with depth, confidence and pose.
///
/// Encoding runs on its own queue: the ARSession delegate callback must return
/// quickly or ARKit throttles frame delivery, which previously capped the whole
/// pipeline at ~5 fps no matter what rate the user selected.
final class ARCaptureController: NSObject, ARSessionDelegate {
    struct Stats {
        var capturedFrames: UInt64 = 0
        var skippedBusy: UInt64 = 0
        var averageEncodeMs: Double = 0
        var measuredFPS: Double = 0
        /// Per-plane cost, so a slow sensor is visible in the app.
        var rgbMs: Double = 0
        var depthMs: Double = 0
        var confidenceMs: Double = 0
        var pixelConversionMs: Double = 0
        /// Raw ARKit delivery rate, before the target-rate gate.
        var delegateFPS: Double = 0
    }

    private let session = ARSession()
    private let delegateQueue = DispatchQueue(label: "io.openbene.ar.delegate", qos: .userInitiated)
    private let encodeQueue = DispatchQueue(label: "io.openbene.ar.encode", qos: .userInitiated)
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])
    private let onFrame: (CaptureFrame) -> Void
    private let onStatus: (String) -> Void
    private let onStats: (Stats) -> Void

    private var settings: CaptureSettings
    private let stateLock = NSLock()
    private var encoding = false
    private var frameID: UInt32 = 0
    private var lastPublished: CFTimeInterval = 0
    /// Time credit for the target-rate scheduler. ARKit delivers ~26 fps with
    /// scene depth, so a fixed "skip if early" gate halves that to 13 fps;
    /// banking credit lets 2-of-3 frames through on average instead.
    private var publishCredit: Double = 0
    private var lastDelegate: CFTimeInterval = 0
    private var stats = Stats()
    private var recentFrameTimes: [CFTimeInterval] = []
    private var recentDelegateTimes: [CFTimeInterval] = []

    init(
        settings: CaptureSettings,
        onFrame: @escaping (CaptureFrame) -> Void,
        onStatus: @escaping (String) -> Void,
        onStats: @escaping (Stats) -> Void
    ) {
        self.settings = settings
        self.onFrame = onFrame
        self.onStatus = onStatus
        self.onStats = onStats
    }

    func start() {
        let configuration = ARWorldTrackingConfiguration()
        var supportsDepth = false
        if settings.includeDepth,
           ARWorldTrackingConfiguration.supportsFrameSemantics(.smoothedSceneDepth) {
            configuration.frameSemantics.insert(.smoothedSceneDepth)
            supportsDepth = true
        } else if settings.includeDepth,
                  ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
            configuration.frameSemantics.insert(.sceneDepth)
            supportsDepth = true
        }

        session.delegateQueue = delegateQueue
        session.delegate = self
        session.run(configuration, options: [])

        let planes = [
            settings.includeRGB ? "RGB" : nil,
            supportsDepth ? "深度" : nil,
            (supportsDepth && settings.includeConfidence) ? "置信度" : nil,
            settings.includePose ? "位姿" : nil,
        ].compactMap { $0 }.joined(separator: " + ")
        onStatus("ARKit：\(planes) · 目标 \(Int(settings.fps))fps · \(Int(settings.maxWidth))px")
    }

    func stop() {
        session.pause()
        session.delegate = nil
    }

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        let now = CACurrentMediaTime()
        let interval = settings.frameInterval
        let elapsed = lastDelegate > 0 ? now - lastDelegate : interval
        lastDelegate = now
        publishCredit = min(1.5, publishCredit + max(0, elapsed) / interval)
        guard publishCredit >= 1 else { return }
        publishCredit -= 1

        stateLock.lock()
        if encoding {
            stats.skippedBusy += 1
            stateLock.unlock()
            return
        }
        encoding = true
        lastPublished = now
        recentDelegateTimes.append(now)
        if recentDelegateTimes.count > 40 { recentDelegateTimes.removeFirst() }
        frameID &+= 1
        let currentID = frameID
        let snapshotSettings = settings
        stateLock.unlock()

        // ARKit owns the buffers; retaining the ARFrame keeps them alive until
        // the encode finishes.
        encodeQueue.async { [weak self] in
            guard let self else { return }
            let started = CACurrentMediaTime()
            let result = self.makeCaptureFrame(from: frame, settings: snapshotSettings, frameID: currentID)
            if let capture = result.frame {
                self.onFrame(capture)
            }
            let elapsedMs = (CACurrentMediaTime() - started) * 1000
            self.finishEncoding(elapsedMs: elapsedMs, at: started, timing: result.timing)
        }
    }

    private func finishEncoding(elapsedMs: Double, at time: CFTimeInterval, timing: PlaneTiming) {
        stateLock.lock()
        encoding = false
        stats.capturedFrames += 1
        // Exponential moving average keeps the UI number stable.
        func blend(_ value: Double, _ sample: Double) -> Double {
            value == 0 ? sample : value * 0.8 + sample * 0.2
        }
        stats.averageEncodeMs = blend(stats.averageEncodeMs, elapsedMs)
        stats.rgbMs = blend(stats.rgbMs, timing.rgb)
        stats.depthMs = blend(stats.depthMs, timing.depth)
        stats.confidenceMs = blend(stats.confidenceMs, timing.confidence)
        stats.pixelConversionMs = blend(stats.pixelConversionMs, timing.conversion)
        recentFrameTimes.append(time)
        if recentFrameTimes.count > 30 { recentFrameTimes.removeFirst() }
        if let first = recentFrameTimes.first, let last = recentFrameTimes.last, last > first {
            stats.measuredFPS = Double(recentFrameTimes.count - 1) / (last - first)
        }
        if let first = recentDelegateTimes.first, let last = recentDelegateTimes.last, last > first {
            stats.delegateFPS = Double(recentDelegateTimes.count - 1) / (last - first)
        }
        let snapshot = stats
        stateLock.unlock()
        onStats(snapshot)
    }

    private struct PlaneTiming {
        var rgb: Double = 0
        var depth: Double = 0
        var confidence: Double = 0
        var conversion: Double = 0
    }

    private func makeCaptureFrame(
        from frame: ARFrame,
        settings: CaptureSettings,
        frameID: UInt32
    ) -> (frame: CaptureFrame?, timing: PlaneTiming) {
        var timing = PlaneTiming()
        var mark = CACurrentMediaTime()

        let camera = settings.includeRGB ? encodeCamera(frame.capturedImage, maxWidth: settings.maxWidth) : nil
        timing.rgb = (CACurrentMediaTime() - mark) * 1000

        var depthPNG: Data?
        var confidencePNG: Data?
        var depthWidth = 0
        var depthHeight = 0
        var confidenceWidth = 0
        var confidenceHeight = 0
        var depthSource = "none"

        if settings.includeDepth {
            let source = frame.smoothedSceneDepth ?? frame.sceneDepth
            if let source {
                depthSource = frame.smoothedSceneDepth == nil ? "scene_depth" : "smoothed_scene_depth"
                mark = CACurrentMediaTime()
                let converted = Self.depthMillimetres(source.depthMap)
                timing.conversion = (CACurrentMediaTime() - mark) * 1000

                mark = CACurrentMediaTime()
                depthPNG = converted.map {
                    PNGEncoder.gray16(width: $0.width, height: $0.height, values: $0.values)
                }
                timing.depth = (CACurrentMediaTime() - mark) * 1000
                depthWidth = converted?.width ?? 0
                depthHeight = converted?.height ?? 0
                if settings.includeConfidence, let confidence = source.confidenceMap {
                    mark = CACurrentMediaTime()
                    confidencePNG = encodeConfidencePNG(confidence)
                    timing.confidence = (CACurrentMediaTime() - mark) * 1000
                    confidenceWidth = CVPixelBufferGetWidth(confidence)
                    confidenceHeight = CVPixelBufferGetHeight(confidence)
                }
            }
        }

        var enabled: [String] = []
        if camera != nil { enabled.append("rgb") }
        if depthPNG != nil { enabled.append("depth") }
        if confidencePNG != nil { enabled.append("confidence") }
        if settings.includePose { enabled.append("pose") }

        let intrinsics = frame.camera.intrinsics
        let metadata = FrameMetadata(
            width: camera?.width ?? 0,
            height: camera?.height ?? 0,
            depthWidth: depthWidth,
            depthHeight: depthHeight,
            fx: Double(intrinsics.columns.0.x),
            fy: Double(intrinsics.columns.1.y),
            cx: Double(intrinsics.columns.2.x),
            cy: Double(intrinsics.columns.2.y),
            trackingState: Self.trackingStateName(frame.camera.trackingState),
            depthSource: depthSource,
            confidenceWidth: confidenceWidth,
            confidenceHeight: confidenceHeight,
            enabledPlanes: enabled
        )

        let capture = CaptureFrame(
            frameID: frameID,
            timestampNs: UInt64(Date().timeIntervalSince1970 * 1_000_000_000),
            rgbJPEG: camera?.jpeg,
            depthPNG: depthPNG,
            confidencePNG: confidencePNG,
            pose: settings.includePose ? Self.poseArray(frame.camera.transform) : nil,
            metadata: metadata
        )
        return (capture, timing)
    }

    /// JPEG straight from Core Image is much cheaper than CGImage -> UIImage.
    private func encodeCamera(_ pixelBuffer: CVPixelBuffer, maxWidth: CGFloat) -> (jpeg: Data, width: Int, height: Int)? {
        let image = CIImage(cvPixelBuffer: pixelBuffer)
        let scale = min(1, maxWidth / image.extent.width)
        let scaled = scale < 1 ? image.transformed(by: CGAffineTransform(scaleX: scale, y: scale)) : image
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let jpeg = ciContext.jpegRepresentation(
            of: scaled,
            colorSpace: colorSpace,
            options: [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: 0.6]
        ) else { return nil }
        return (jpeg, Int(scaled.extent.width.rounded()), Int(scaled.extent.height.rounded()))
    }

    /// Float32 metres -> 16-bit millimetres, matching the LiDAR pipeline.
    /// Kept separate from PNG encoding so the app can report both costs.
    private static func depthMillimetres(
        _ buffer: CVPixelBuffer
    ) -> (width: Int, height: Int, values: [UInt16])? {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }
        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        let floats = base.assumingMemoryBound(to: Float32.self)
        let count = width * height

        var millimetres = [UInt16](repeating: 0, count: count)
        millimetres.withUnsafeMutableBufferPointer { output in
            for index in 0..<count {
                let metres = floats[index]
                if metres.isFinite, metres > 0 {
                    output[index] = UInt16(min(max(metres * 1000, 0), 65_535))
                }
            }
        }
        return (width, height, millimetres)
    }

    private func encodeConfidencePNG(_ buffer: CVPixelBuffer) -> Data? {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }
        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        let pointer = base.assumingMemoryBound(to: UInt8.self)
        var values = [UInt8](repeating: 0, count: width * height)
        for row in 0..<height {
            for column in 0..<width {
                values[row * width + column] = pointer[row * bytesPerRow + column]
            }
        }
        return PNGEncoder.gray8(width: width, height: height, values: values)
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
