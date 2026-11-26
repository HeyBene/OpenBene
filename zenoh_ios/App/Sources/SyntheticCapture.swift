import Foundation
import OpenBeneZenoh
import UIKit

/// Emits synthetic frames so the transport can be tested without ARKit
/// (simulator, permission denied, or a device without depth).
final class SyntheticCapture {
    var settings: CaptureSettings
    private let onFrame: (CaptureFrame) -> Void
    private var timer: Timer?
    private var frameID: UInt32 = 0
    private let depthWidth = 256
    private let depthHeight = 192

    init(settings: CaptureSettings, onFrame: @escaping (CaptureFrame) -> Void) {
        self.settings = settings
        self.onFrame = onFrame
    }

    func start() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: settings.frameInterval, repeats: true) { [weak self] _ in
            self?.emit()
        }
        emit()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func emit() {
        frameID &+= 1
        let size = CGSize(width: 640, height: 480)
        // Scale 1 keeps the encoded image at 640x480 instead of the screen's
        // 3x scale, which previously mismatched the frame metadata.
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let image = renderer.image { context in
            UIColor(red: 0.08, green: 0.12, blue: 0.18, alpha: 1).setFill()
            context.fill(CGRect(origin: .zero, size: size))
            UIColor(red: 0.2, green: 0.8, blue: 0.6, alpha: 1).setFill()
            context.fill(CGRect(x: 40, y: 220, width: 60 + CGFloat(frameID % 400), height: 40))
            let text = "OpenBene Zenoh #\(frameID)"
            text.draw(
                at: CGPoint(x: 40, y: 60),
                withAttributes: [.font: UIFont.monospacedSystemFont(ofSize: 22, weight: .semibold),
                                 .foregroundColor: UIColor.white]
            )
        }
        guard let jpeg = image.jpegData(compressionQuality: 0.6) else { return }

        var enabled: [String] = []
        if settings.includeRGB { enabled.append("rgb") }
        if settings.includeDepth { enabled.append("depth") }
        if settings.includeConfidence { enabled.append("confidence") }
        if settings.includePose { enabled.append("pose") }

        let frame = CaptureFrame(
            frameID: frameID,
            timestampNs: UInt64(Date().timeIntervalSince1970 * 1_000_000_000),
            rgbJPEG: settings.includeRGB ? jpeg : nil,
            depthPNG: settings.includeDepth
                ? Self.depthPNG(width: depthWidth, height: depthHeight, frameID: frameID)
                : nil,
            confidencePNG: settings.includeConfidence
                ? Self.confidencePNG(width: depthWidth, height: depthHeight)
                : nil,
            pose: settings.includePose ? [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1] : nil,
            metadata: FrameMetadata(
                width: settings.includeRGB ? Int(size.width) : 0,
                height: settings.includeRGB ? Int(size.height) : 0,
                depthWidth: settings.includeDepth ? depthWidth : 0,
                depthHeight: settings.includeDepth ? depthHeight : 0,
                fx: 520, fy: 520, cx: 320, cy: 240,
                trackingState: "synthetic",
                depthSource: "synthetic",
                confidenceWidth: settings.includeConfidence ? depthWidth : 0,
                confidenceHeight: settings.includeConfidence ? depthHeight : 0,
                enabledPlanes: enabled
            )
        )
        onFrame(frame)
    }

    private static func depthPNG(width: Int, height: Int, frameID: UInt32) -> Data? {
        var values = [UInt16](repeating: 0, count: width * height)
        let seed = Int(frameID) * 7
        for y in 0..<height {
            for x in 0..<width {
                // Wide spread (0.3 m .. 4.0 m) so the PC colour ramp is visible.
                let pattern: Int = (x &* 31) &+ (y &* 53) &+ seed
                values[y * width + x] = UInt16(300 + pattern % 3700)
            }
        }
        return PNGEncoder.gray16(width: width, height: height, values: values)
    }

    private static func confidencePNG(width: Int, height: Int) -> Data? {
        var bytes = [UInt8](repeating: 1, count: width * height)
        // Distinct bands so all three confidence levels are visible.
        for index in bytes.indices {
            bytes[index] = UInt8((index / 7 + index / (width * 3)) % 3)
        }
        return PNGEncoder.gray8(width: width, height: height, values: bytes)
    }
}
