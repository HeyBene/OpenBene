import CoreImage
import CoreVideo
import Foundation
import OpenBeneZenoh
import UIKit

/// Startup self check: measures the two encode steps that dominate a frame.
/// Results are printed to the device console so `devicectl --console` can read
/// them without connecting the phone to the PC.
enum CaptureSelfCheck {
    static func run(onResult: @escaping (String) -> Void = { print($0) }) {
        DispatchQueue.global(qos: .utility).async {
            let w = 256, h = 192, count = w * h
            let millimetres = (0..<count).map { UInt16(300 + ($0 % 700)) }
            let iterations = 20
            var bytes = 0
            var start = CACurrentMediaTime()
            for _ in 0..<iterations {
                bytes = PNGEncoder.gray16(width: w, height: h, values: millimetres).count
            }
            let depthMs = (CACurrentMediaTime() - start) * 1000 / Double(iterations)

            let confidence = [UInt8](repeating: 2, count: count)
            start = CACurrentMediaTime()
            for _ in 0..<iterations {
                bytes += PNGEncoder.gray8(width: w, height: h, values: confidence).count
            }
            let confidenceMs = (CACurrentMediaTime() - start) * 1000 / Double(iterations)

            let jpegMs = measureJPEG(width: 1280, height: 960)
            let jpeg640 = measureJPEG(width: 640, height: 480)
            let summary = String(
                format: "深度PNG %.1f ms · 置信度 %.1f ms · JPEG1280 %.1f ms · JPEG640 %.1f ms",
                depthMs, confidenceMs, jpegMs, jpeg640
            )
            print("SELFCHECK " + summary + " bytes=\(bytes)")
            onResult(summary)
        }
    }

    private static func measureJPEG(width: Int, height: Int) -> Double {
        var pixelBuffer: CVPixelBuffer?
        let attributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:],
        ]
        guard CVPixelBufferCreate(kCFAllocatorDefault, width, height,
                                  kCVPixelFormatType_32BGRA, attributes as CFDictionary,
                                  &pixelBuffer) == kCVReturnSuccess,
              let buffer = pixelBuffer else { return -1 }

        CVPixelBufferLockBaseAddress(buffer, [])
        if let base = CVPixelBufferGetBaseAddress(buffer) {
            let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
            for row in 0..<height {
                let pointer = base.assumingMemoryBound(to: UInt8.self) + row * bytesPerRow
                for column in 0..<(width * 4) {
                    pointer[column] = UInt8((column &* 3 &+ row) & 0xFF)
                }
            }
        }
        CVPixelBufferUnlockBaseAddress(buffer, [])

        let context = CIContext(options: [.useSoftwareRenderer: false])
        let image = CIImage(cvPixelBuffer: buffer)
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let iterations = 8
        let start = CACurrentMediaTime()
        for _ in 0..<iterations {
            _ = context.jpegRepresentation(
                of: image,
                colorSpace: colorSpace,
                options: [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: 0.6]
            )
        }
        return (CACurrentMediaTime() - start) * 1000 / Double(iterations)
    }
}
