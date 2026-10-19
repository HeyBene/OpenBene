#if canImport(CoreVideo)
import CoreVideo
import Foundation

/// CPU adapter for ARKit's native, unrotated scene-depth buffers. Kept free of
/// ARSession/Vision so padded rows and portrait transforms are testable on Mac.
public enum PersonDepthSampler {
    public static func distance(depthMap: CVPixelBuffer, confidenceMap: CVPixelBuffer?,
        uprightBox: PersonBox, intrinsics: NormalizedCameraIntrinsics, cameraInAr: RigidTransform) -> Double? {
        guard CVPixelBufferGetPixelFormatType(depthMap) == kCVPixelFormatType_DepthFloat32,
              let confidence = confidenceMap,
              CVPixelBufferGetPixelFormatType(confidence) == kCVPixelFormatType_OneComponent8,
              [uprightBox.centreX, uprightBox.centreY, uprightBox.width, uprightBox.height].allSatisfy({ $0.isFinite }),
              uprightBox.width > 0, uprightBox.height > 0 else { return nil }
        let width = CVPixelBufferGetWidth(depthMap), height = CVPixelBufferGetHeight(depthMap)
        guard width > 0, height > 0, CVPixelBufferGetWidth(confidence) == width,
              CVPixelBufferGetHeight(confidence) == height,
              CVPixelBufferLockBaseAddress(depthMap, .readOnly) == kCVReturnSuccess else { return nil }
        defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }
        guard CVPixelBufferLockBaseAddress(confidence, .readOnly) == kCVReturnSuccess else { return nil }
        defer { CVPixelBufferUnlockBaseAddress(confidence, .readOnly) }
        guard let depthBase = CVPixelBufferGetBaseAddress(depthMap),
              let confidenceBase = CVPixelBufferGetBaseAddress(confidence) else { return nil }
        let depthStride = CVPixelBufferGetBytesPerRow(depthMap), confidenceStride = CVPixelBufferGetBytesPerRow(confidence)
        var samples: [Double] = [], visited = Set<Int>()
        for row in 0..<9 { for column in 0..<9 {
            // Central body patch, excluding the silhouette and bottom/feet.
            let portraitX = uprightBox.centreX + (Double(column) / 8 - 0.5) * uprightBox.width * 0.4
            let portraitY = uprightBox.centreY + (Double(row) / 8 * 0.4 - 0.25) * uprightBox.height
            // Undo Vision .right, exactly as the preview-box conversion does.
            let u = portraitY, v = 1 - portraitX
            guard (0..<1).contains(u), (0..<1).contains(v) else { continue }
            let x = min(width - 1, Int(u * Double(width))), y = min(height - 1, Int(v * Double(height)))
            guard visited.insert(y * width + x).inserted else { continue }
            let level = confidenceBase.advanced(by: y * confidenceStride).assumingMemoryBound(to: UInt8.self)[x]
            guard level >= 1 else { continue } // ARConfidenceLevel medium/high
            let z = Double(depthBase.advanced(by: y * depthStride).assumingMemoryBound(to: Float.self)[x])
            if let value = PersonRangeEstimator.horizontalDistance(depthM: z,
                u: (Double(x) + 0.5) / Double(width), v: (Double(y) + 0.5) / Double(height),
                intrinsics: intrinsics, cameraInAr: cameraInAr) { samples.append(value) }
        } }
        return PersonRangeEstimator.robustDistance(samples, attempted: visited.count)
    }
}
#endif
