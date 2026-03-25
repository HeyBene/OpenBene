import Foundation
import CoreVideo
import simd

/// 会话级轻量点云融合器。
///
/// 第一版目标是快速生成可上传的轻量几何 sanity-check 工件，
/// 不追求高精度地图重建或实时预览。
final class LightweightPointCloudAccumulator {
    private struct PointKey: Hashable {
        let x: Int32
        let y: Int32
        let z: Int32
    }

    private let sampleStride: Int
    private let nearDepthMeters: Float
    private let farDepthMeters: Float
    private let voxelSizeMeters: Float

    private var voxelPoints: [PointKey: SIMD3<Float>] = [:]

    init(
        sampleStride: Int = 6,
        nearDepthMeters: Float = 0.05,
        farDepthMeters: Float = 4.0,
        voxelSizeMeters: Float = 0.01
    ) {
        self.sampleStride = max(1, sampleStride)
        self.nearDepthMeters = nearDepthMeters
        self.farDepthMeters = farDepthMeters
        self.voxelSizeMeters = voxelSizeMeters
    }

    func reset() {
        voxelPoints.removeAll(keepingCapacity: true)
    }

    func ingest(_ record: CaptureFrameRecord) {
        guard let depthBuffer = record.depthBuffer else { return }

        CVPixelBufferLockBaseAddress(depthBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthBuffer, .readOnly) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(depthBuffer) else { return }
        let depthWidth = CVPixelBufferGetWidth(depthBuffer)
        let depthHeight = CVPixelBufferGetHeight(depthBuffer)
        let rowStride = CVPixelBufferGetBytesPerRow(depthBuffer) / MemoryLayout<Float32>.stride
        let depthPointer = baseAddress.assumingMemoryBound(to: Float32.self)

        let fx = record.flX * Float(depthWidth) / Float(max(record.width, 1))
        let fy = record.flY * Float(depthHeight) / Float(max(record.height, 1))
        let cx = record.cx * Float(depthWidth) / Float(max(record.width, 1))
        let cy = record.cy * Float(depthHeight) / Float(max(record.height, 1))
        let transform = record.transformMatrix

        for y in stride(from: 0, to: depthHeight, by: sampleStride) {
            let row = depthPointer.advanced(by: y * rowStride)
            for x in stride(from: 0, to: depthWidth, by: sampleStride) {
                let depthMeters = row[x]
                guard depthMeters.isFinite,
                      depthMeters >= nearDepthMeters,
                      depthMeters <= farDepthMeters else {
                    continue
                }

                let xCamera = (Float(x) - cx) / fx * depthMeters
                let yCamera = (Float(y) - cy) / fy * depthMeters
                let cameraPoint = SIMD4<Float>(xCamera, yCamera, depthMeters, 1)
                let worldPoint4 = transform * cameraPoint
                let worldPoint = SIMD3<Float>(worldPoint4.x, worldPoint4.y, worldPoint4.z)

                let key = PointKey(
                    x: Int32((worldPoint.x / voxelSizeMeters).rounded()),
                    y: Int32((worldPoint.y / voxelSizeMeters).rounded()),
                    z: Int32((worldPoint.z / voxelSizeMeters).rounded())
                )
                voxelPoints[key] = worldPoint
            }
        }
    }

    var pointCount: Int {
        voxelPoints.count
    }

    func makePLYArtifact(fileName: String = "fused_pointcloud.ply") -> CaptureSessionPointCloudArtifact? {
        guard !voxelPoints.isEmpty else { return nil }
        var data = Data()
        let header = """
        ply
        format ascii 1.0
        element vertex \(voxelPoints.count)
        property float x
        property float y
        property float z
        end_header
        """
        data.append(header.data(using: .utf8)!)
        for point in voxelPoints.values {
            data.append("\(point.x) \(point.y) \(point.z)\n".data(using: .utf8)!)
        }
        return CaptureSessionPointCloudArtifact(
            fileName: fileName,
            format: "ply_ascii_xyz",
            coordinateConvention: "arkit_world",
            pointCount: voxelPoints.count,
            data: data
        )
    }
}
