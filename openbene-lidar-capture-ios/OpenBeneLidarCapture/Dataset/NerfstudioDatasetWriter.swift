import Foundation
import UIKit
import CoreVideo
import Accelerate
import ImageIO
import UniformTypeIdentifiers

/// Nerfstudio 数据集写入器。
/// 负责把采集到的帧落盘成 images/、depth/、transforms.json 结构。
final class NerfstudioDatasetWriter {

    private let outputDirectory: URL
    private let imagesDirectory: URL
    private let depthDirectory: URL
    private let depthAvailable: Bool

    /// 深度缩放：米 × 1000 后写入 uint16，对应毫米。
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
        // 全局内参先取第一帧，后续默认保持一致。
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

        let pixelBuffer = record.pixelBuffer
        let depthBuffer = record.depthBuffer

        writeQueue.async { [self] in
            // RGB 当前先写 JPEG，减小体积，后续如有需要可切 PNG。
            if let rgbImage = self.imageFromPixelBuffer(pixelBuffer) {
                let jpegURL = imagesDirectory.appendingPathComponent("\(frameName).jpg")
                if let jpegData = rgbImage.jpegData(compressionQuality: 0.9) {
                    try? jpegData.write(to: jpegURL)
                }
            }

            // 深度写成 16 位 PNG，单位为毫米。
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

    /// 将 float32 深度图写成 16 位 PNG。
    /// 输入单位：米；输出单位：毫米。
    private func writeDepthAsPNG(_ depthBuffer: CVPixelBuffer, to url: URL) {
        CVPixelBufferLockBaseAddress(depthBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthBuffer, .readOnly) }

        let width = CVPixelBufferGetWidth(depthBuffer)
        let height = CVPixelBufferGetHeight(depthBuffer)
        guard let baseAddress = CVPixelBufferGetBaseAddress(depthBuffer) else { return }

        let floatPointer = baseAddress.assumingMemoryBound(to: Float.self)
        let pixelCount = width * height

        var uint16Data = [UInt16](repeating: 0, count: pixelCount)
        for i in 0..<pixelCount {
            let meters = floatPointer[i]
            if meters.isFinite && meters > 0 {
                let mm = meters * depthScale
                uint16Data[i] = UInt16(min(max(mm, 0), Float(UInt16.max)))
            }
        }

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
