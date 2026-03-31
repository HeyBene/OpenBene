import Foundation
import UIKit
import CoreVideo
import ImageIO
import UniformTypeIdentifiers

final class PreparedFrameEncoder {
    private let ciContext = CIContext()
    private let depthScale: Float = 1000.0

    func preparePayload(for record: CaptureFrameRecord) -> PreparedCaptureFramePayload? {
        guard let rgbJPEGData = encodeRGBAsJPEG(record.pixelBuffer) else {
            return nil
        }
        let depthPNGData = record.depthBuffer.flatMap { encodeDepthAsPNGData($0) }
        return PreparedCaptureFramePayload(record: record, rgbJPEGData: rgbJPEGData, depthPNGData: depthPNGData)
    }

    private func encodeRGBAsJPEG(_ pixelBuffer: CVPixelBuffer) -> Data? {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        guard let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent) else { return nil }
        return UIImage(cgImage: cgImage).jpegData(compressionQuality: 0.85)
    }

    private func encodeDepthAsPNGData(_ depthBuffer: CVPixelBuffer) -> Data? {
        CVPixelBufferLockBaseAddress(depthBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthBuffer, .readOnly) }

        let width = CVPixelBufferGetWidth(depthBuffer)
        let height = CVPixelBufferGetHeight(depthBuffer)
        guard let baseAddress = CVPixelBufferGetBaseAddress(depthBuffer) else { return nil }

        let floatPointer = baseAddress.assumingMemoryBound(to: Float.self)
        let pixelCount = width * height
        var uint16Data = [UInt16](repeating: 0, count: pixelCount)
        for i in 0..<pixelCount {
            let meters = floatPointer[i]
            if meters.isFinite && meters > 0 {
                uint16Data[i] = UInt16(min(max(meters * depthScale, 0), Float(UInt16.max)))
            }
        }

        let bytesPerRow = width * MemoryLayout<UInt16>.size
        let colorSpace = CGColorSpaceCreateDeviceGray()
        let bitmapInfo: CGBitmapInfo = [.byteOrder16Little]

        return uint16Data.withUnsafeMutableBytes { rawBuffer -> Data? in
            guard let context = CGContext(
                data: rawBuffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 16,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: bitmapInfo.rawValue
            ) else { return nil }

            guard let cgImage = context.makeImage() else { return nil }
            let mutableData = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(mutableData as CFMutableData, UTType.png.identifier as CFString, 1, nil) else { return nil }
            CGImageDestinationAddImage(destination, cgImage, nil)
            guard CGImageDestinationFinalize(destination) else { return nil }
            return mutableData as Data
        }
    }
}
