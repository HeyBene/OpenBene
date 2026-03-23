import Foundation
import UIKit
import CoreVideo
import Accelerate
import ImageIO
import UniformTypeIdentifiers

/// Writes captured frames to a Nerfstudio-compatible dataset directory.
///
/// Output structure:
/// ```
/// session_xxx/
///   transforms.json
///   images/
///     000000.jpg
///     000001.jpg
///   depth/          (only if LiDAR available)
///     000000.png
///     000001.png
/// ```
final class NerfstudioDatasetWriter {

    private let outputDirectory: URL
    private let imagesDirectory: URL
    private let depthDirectory: URL
    private let depthAvailable: Bool

    /// Depth scale: depth_in_meters * depthScale = stored_uint16_value.
    /// Using 1000 means millimeters stored as uint16.
    private let depthScale: Float = 1000.0

    private var frames: [[String: Any]] = []
    private var globalIntrinsics: [String: Any]?

    private let writeQueue = DispatchQueue(label: "com.openbene.dataset.writer", qos: .utility)

    init(outputDirectory: URL, depthAvailable: Bool) {
        self.outputDirectory = outputDirectory
        self.imagesDirectory = outputDirectory.appendingPathComponent("images")
        self.depthDirectory = outputDirectory.appendingPathComponent("depth")
        self.depthAvailable = depthAvailable
    }

    func beginSession() {
        writeQueue.async { [self] in
            try? FileManager.default.createDirectory(at: imagesDirectory, withIntermediateDirectories: true)
            if depthAvailable {
                try? FileManager.default.createDirectory(at: depthDirectory, withIntermediateDirectories: true)
            }
        }
        frames = []
        globalIntrinsics = nil
    }

    func writeFrame(_ record: CaptureFrameRecord) {
        // Capture intrinsics from first frame
        if globalIntrinsics == nil {
            globalIntrinsics = [
                "w": record.width,
                "h": record.height,
                "fl_x": record.flX,
                "fl_y": record.flY,
                "cx": record.cx,
                "cy": record.cy
            ]
        }

        let frameName = String(format: "%06d", record.index)
        let transformMatrix = PoseTransformAdapter.arkitToNerfstudio(record.transformMatrix)

        var frameEntry: [String: Any] = [
            "file_path": "images/\(frameName).jpg",
            "transform_matrix": transformMatrix,
            "timestamp": record.timestamp
        ]

        if depthAvailable && record.depthBuffer != nil {
            frameEntry["depth_file_path"] = "depth/\(frameName).png"
        }

        frames.append(frameEntry)

        // Write image and depth on background queue
        let pixelBuffer = record.pixelBuffer
        let depthBuffer = record.depthBuffer

        writeQueue.async { [self] in
            // Write RGB as JPEG
            if let rgbImage = self.imageFromPixelBuffer(pixelBuffer) {
                let jpegURL = imagesDirectory.appendingPathComponent("\(frameName).jpg")
                if let jpegData = rgbImage.jpegData(compressionQuality: 0.9) {
                    try? jpegData.write(to: jpegURL)
                }
            }

            // Write depth as 16-bit PNG
            if let depthBuf = depthBuffer {
                let depthURL = depthDirectory.appendingPathComponent("\(frameName).png")
                self.writeDepthAsPNG(depthBuf, to: depthURL)
            }
        }
    }

    func finalizeSession() {
        writeQueue.async { [self] in
            var manifest: [String: Any] = globalIntrinsics ?? [:]
            manifest["depth_scale"] = depthScale
            manifest["depth_unit"] = "millimeters"
            manifest["coordinate_convention"] = "opengl"
            manifest["frames"] = frames

            let jsonURL = outputDirectory.appendingPathComponent("transforms.json")
            if let jsonData = try? JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys]) {
                try? jsonData.write(to: jsonURL)
            }
        }
    }

    // MARK: - Image conversion helpers

    private func imageFromPixelBuffer(_ pixelBuffer: CVPixelBuffer) -> UIImage? {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext()
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }

    /// Write a float32 depth CVPixelBuffer as a 16-bit PNG (millimeters).
    private func writeDepthAsPNG(_ depthBuffer: CVPixelBuffer, to url: URL) {
        CVPixelBufferLockBaseAddress(depthBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthBuffer, .readOnly) }

        let width = CVPixelBufferGetWidth(depthBuffer)
        let height = CVPixelBufferGetHeight(depthBuffer)
        guard let baseAddress = CVPixelBufferGetBaseAddress(depthBuffer) else { return }

        let floatPointer = baseAddress.assumingMemoryBound(to: Float.self)
        let pixelCount = width * height

        // Convert float32 meters → uint16 millimeters
        var uint16Data = [UInt16](repeating: 0, count: pixelCount)
        for i in 0..<pixelCount {
            let meters = floatPointer[i]
            if meters.isFinite && meters > 0 {
                let mm = meters * depthScale
                uint16Data[i] = UInt16(min(max(mm, 0), Float(UInt16.max)))
            }
        }

        // Create 16-bit grayscale CGImage and write as PNG
        let bytesPerRow = width * MemoryLayout<UInt16>.size
        let colorSpace = CGColorSpaceCreateDeviceGray()
        let bitmapInfo: CGBitmapInfo = [.byteOrder16Little]

        uint16Data.withUnsafeMutableBytes { rawBuffer in
            guard let context = CGContext(
                data: rawBuffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 16,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: bitmapInfo.rawValue
            ) else { return }

            guard let cgImage = context.makeImage() else { return }
            guard let destination = CGImageDestinationCreateWithURL(
                url as CFURL,
                UTType.png.identifier as CFString,
                1,
                nil
            ) else { return }
            CGImageDestinationAddImage(destination, cgImage, nil)
            CGImageDestinationFinalize(destination)
        }
    }
}
