import Foundation
import UIKit
import CoreVideo
import ImageIO
import UniformTypeIdentifiers

final class PreparedFrameEncoder {
    private let ciContext = CIContext()
    private let depthScale: Float = 1000.0

    func preparePayload(for record: CaptureFrameRecord) -> PreparedCaptureFramePayload? {
        let rgbJPEGData = encodeRGBAsJPEG(record.pixelBuffer)
        let depthPNGData = record.depthBuffer.flatMap { encodeDepthAsPNGData($0) }
        let confidencePNGData = record.confidenceBuffer.flatMap { encodeConfidenceAsPNGData($0) }
        if rgbJPEGData == nil && depthPNGData == nil && confidencePNGData == nil {
            return nil
        }
        return PreparedCaptureFramePayload(
            record: record,
            rgbJPEGData: rgbJPEGData,
            depthPNGData: depthPNGData,
            confidencePNGData: confidencePNGData
        )
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

    private func encodeConfidenceAsPNGData(_ confidenceBuffer: CVPixelBuffer) -> Data? {
        CVPixelBufferLockBaseAddress(confidenceBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(confidenceBuffer, .readOnly) }

        let width = CVPixelBufferGetWidth(confidenceBuffer)
        let height = CVPixelBufferGetHeight(confidenceBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(confidenceBuffer)
        guard let baseAddress = CVPixelBufferGetBaseAddress(confidenceBuffer) else { return nil }

        let pixelFormat = CVPixelBufferGetPixelFormatType(confidenceBuffer)
        var grayscale = [UInt8](repeating: 0, count: width * height)

        if pixelFormat == kCVPixelFormatType_OneComponent8 {
            for row in 0..<height {
                let rowStart = baseAddress.advanced(by: row * bytesPerRow)
                let source = rowStart.assumingMemoryBound(to: UInt8.self)
                for col in 0..<width {
                    grayscale[row * width + col] = source[col]
                }
            }
        } else if pixelFormat == kCVPixelFormatType_OneComponent16 {
            for row in 0..<height {
                let rowStart = baseAddress.advanced(by: row * bytesPerRow)
                let source = rowStart.assumingMemoryBound(to: UInt16.self)
                for col in 0..<width {
                    let value = source[col]
                    grayscale[row * width + col] = UInt8(min(value, UInt16(UInt8.max)))
                }
            }
        } else {
            // Fallback for unexpected confidence formats: use the first byte per pixel.
            for row in 0..<height {
                let rowStart = baseAddress.advanced(by: row * bytesPerRow)
                let source = rowStart.assumingMemoryBound(to: UInt8.self)
                for col in 0..<width {
                    grayscale[row * width + col] = source[col]
                }
            }
        }

        let outBytesPerRow = width * MemoryLayout<UInt8>.size
        let colorSpace = CGColorSpaceCreateDeviceGray()
        let bitmapInfo = CGImageAlphaInfo.none.rawValue

        return grayscale.withUnsafeMutableBytes { rawBuffer -> Data? in
            guard let context = CGContext(
                data: rawBuffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: outBytesPerRow,
                space: colorSpace,
                bitmapInfo: bitmapInfo
            ) else { return nil }

            guard let cgImage = context.makeImage() else { return nil }
            let mutableData = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(
                mutableData as CFMutableData,
                UTType.png.identifier as CFString,
                1,
                nil
            ) else { return nil }
            CGImageDestinationAddImage(destination, cgImage, nil)
            guard CGImageDestinationFinalize(destination) else { return nil }
            return mutableData as Data
        }
    }
}
