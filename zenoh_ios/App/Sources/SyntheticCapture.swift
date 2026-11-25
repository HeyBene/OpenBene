import Foundation
import OpenBeneZenoh
import UIKit

/// Emits synthetic frames so the transport can be tested without ARKit
/// (simulator, permission denied, or a device without depth).
final class SyntheticCapture {
    private let onFrame: (CaptureFrame) -> Void
    private var timer: Timer?
    private var frameID: UInt32 = 0
    private let depthWidth = 256
    private let depthHeight = 192

    init(onFrame: @escaping (CaptureFrame) -> Void) {
        self.onFrame = onFrame
    }

    func start() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
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
        let renderer = UIGraphicsImageRenderer(size: size)
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

        let frame = CaptureFrame(
            frameID: frameID,
            timestampNs: UInt64(Date().timeIntervalSince1970 * 1_000_000_000),
            rgbJPEG: jpeg,
            depthPNG: Self.depthPNG(width: depthWidth, height: depthHeight, frameID: frameID),
            confidencePNG: Self.confidencePNG(width: depthWidth, height: depthHeight),
            pose: [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1],
            metadata: FrameMetadata(
                width: Int(size.width),
                height: Int(size.height),
                depthWidth: depthWidth,
                depthHeight: depthHeight,
                fx: 520, fy: 520, cx: 320, cy: 240,
                trackingState: "synthetic",
                depthSource: "synthetic",
                confidenceWidth: depthWidth,
                confidenceHeight: depthHeight
            )
        )
        onFrame(frame)
    }

    private static func depthPNG(width: Int, height: Int, frameID: UInt32) -> Data? {
        var values = [UInt16](repeating: 0, count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                values[y * width + x] = UInt16(500 + ((x &* 3 &+ y &* 5 &+ Int(frameID)) % 900))
            }
        }
        return values.withUnsafeMutableBytes { raw -> Data? in
            guard let context = CGContext(
                data: raw.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 16,
                bytesPerRow: width * MemoryLayout<UInt16>.size,
                space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.none.rawValue
            ), let image = context.makeImage() else { return nil }
            let data = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(
                data as CFMutableData, "public.png" as CFString, 1, nil
            ) else { return nil }
            CGImageDestinationAddImage(destination, image, nil)
            return CGImageDestinationFinalize(destination) ? data as Data : nil
        }
    }

    private static func confidencePNG(width: Int, height: Int) -> Data? {
        var bytes = [UInt8](repeating: 1, count: width * height)
        for index in bytes.indices { bytes[index] = UInt8(index % 3) }
        return bytes.withUnsafeMutableBytes { raw -> Data? in
            guard let context = CGContext(
                data: raw.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width,
                space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.none.rawValue
            ), let image = context.makeImage() else { return nil }
            let data = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(
                data as CFMutableData, "public.png" as CFString, 1, nil
            ) else { return nil }
            CGImageDestinationAddImage(destination, image, nil)
            return CGImageDestinationFinalize(destination) ? data as Data : nil
        }
    }
}
