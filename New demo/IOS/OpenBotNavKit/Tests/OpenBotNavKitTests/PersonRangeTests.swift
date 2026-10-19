import XCTest
@testable import OpenBotNavKit
#if canImport(CoreVideo)
import CoreVideo
#endif

final class PersonRangeTests: XCTestCase {
    private let k = NormalizedCameraIntrinsics(fx: 0.8, fy: 0.8, cx: 0.5, cy: 0.5)

    func testPitchCorrectedHorizontalRangeDoesNotDependOnCameraHeightOrMapPosition() throws {
        for pitch in [-20.0, -45, -65] {
            let camera = RigidTransform.fromYawPitchRoll(position: (10, 0.5, -20), yawDeg: 75, pitchDeg: pitch)
            let depth = 2 / cos(pitch * .pi / 180)
            let distance = try XCTUnwrap(PersonRangeEstimator.horizontalDistance(depthM: depth, u: 0.5, v: 0.5,
                intrinsics: k, cameraInAr: camera))
            XCTAssertEqual(distance, 2, accuracy: 1e-9)
        }
    }

    func testMedianRejectsOutliersAndMixedBodyBackgroundPatchIsUnknown() {
        XCTAssertEqual(PersonRangeEstimator.robustDistance(Array(repeating: 1.4, count: 70) + [0.1, 7, 8], attempted: 81), 1.4)
        XCTAssertNil(PersonRangeEstimator.robustDistance(Array(repeating: 1, count: 40) + Array(repeating: 4, count: 40), attempted: 81))
        XCTAssertNil(PersonRangeEstimator.robustDistance(Array(repeating: 2, count: 11), attempted: 20))
        XCTAssertNil(PersonRangeEstimator.robustDistance(Array(repeating: 2, count: 15), attempted: 81))
    }

    func testInvalidDepthOrCalibrationCannotProduceAValidRange() {
        for z in [Double.nan, .infinity, -1, 0, 20] {
            XCTAssertNil(PersonRangeEstimator.horizontalDistance(depthM: z, u: 0.5, v: 0.5, intrinsics: k, cameraInAr: .identity))
        }
        XCTAssertNil(PersonRangeEstimator.horizontalDistance(depthM: 2, u: 0.5, v: 0.5,
            intrinsics: NormalizedCameraIntrinsics(fx: 0, fy: 1, cx: 0.5, cy: 0.5), cameraInAr: .identity))
    }

    #if canImport(CoreVideo)
    private func buffers(camera: RigidTransform = .identity, confidenceValue: UInt8 = 2,
                         patch: (Double, Double) -> Bool = { _, _ in true }) throws -> (CVPixelBuffer, CVPixelBuffer) {
        var depth: CVPixelBuffer?, confidence: CVPixelBuffer?
        let attributes = [kCVPixelBufferBytesPerRowAlignmentKey as String: 128] as CFDictionary
        XCTAssertEqual(CVPixelBufferCreate(nil, 97, 63, kCVPixelFormatType_DepthFloat32, attributes, &depth), kCVReturnSuccess)
        XCTAssertEqual(CVPixelBufferCreate(nil, 97, 63, kCVPixelFormatType_OneComponent8, attributes, &confidence), kCVReturnSuccess)
        let d = try XCTUnwrap(depth), c = try XCTUnwrap(confidence)
        CVPixelBufferLockBaseAddress(d, []); CVPixelBufferLockBaseAddress(c, [])
        defer { CVPixelBufferUnlockBaseAddress(d, []); CVPixelBufferUnlockBaseAddress(c, []) }
        for y in 0..<63 { for x in 0..<97 {
            let u = (Double(x) + 0.5) / 97, v = (Double(y) + 0.5) / 63
            let ray = camera.rotate([(u - 0.5) / 0.8, -(v - 0.5) / 0.8, -1])
            let z = Float(2 / hypot(ray[0], ray[2]))
            CVPixelBufferGetBaseAddress(d)!.advanced(by: y * CVPixelBufferGetBytesPerRow(d)).assumingMemoryBound(to: Float.self)[x] = z
            CVPixelBufferGetBaseAddress(c)!.advanced(by: y * CVPixelBufferGetBytesPerRow(c)).assumingMemoryBound(to: UInt8.self)[x] = patch(u, v) ? confidenceValue : 0
        } }
        return (d, c)
    }

    func testNativeDepthBuffersRespectPortraitRotationAndPaddedRows() throws {
        let (d, c) = try buffers { u, v in (0.1...0.4).contains(u) && (0.6...0.8).contains(v) }
        XCTAssertGreaterThan(CVPixelBufferGetBytesPerRow(d), 97 * 4)
        XCTAssertGreaterThan(CVPixelBufferGetBytesPerRow(c), 97)
        let distance = try XCTUnwrap(PersonDepthSampler.distance(depthMap: d, confidenceMap: c,
            uprightBox: PersonBox(centreX: 0.3, centreY: 0.25, width: 0.3, height: 0.4), intrinsics: k, cameraInAr: .identity))
        XCTAssertEqual(distance, 2, accuracy: 1e-5)
    }

    func testPitchedCameraUsesGravityAndMissingConfidenceHolds() throws {
        let camera = RigidTransform.fromYawPitchRoll(position: (2, 0.4, 3), yawDeg: 40, pitchDeg: -45, rollDeg: 90)
        let (d, c) = try buffers(camera: camera)
        let box = PersonBox(centreX: 0.5, centreY: 0.4, width: 0.3, height: 0.5)
        let distance = try XCTUnwrap(PersonDepthSampler.distance(depthMap: d, confidenceMap: c,
            uprightBox: box, intrinsics: k, cameraInAr: camera))
        XCTAssertEqual(distance, 2, accuracy: 1e-5)
        XCTAssertNil(PersonDepthSampler.distance(depthMap: d, confidenceMap: nil, uprightBox: box, intrinsics: k, cameraInAr: camera))
        let (lowD, lowC) = try buffers(confidenceValue: 0)
        XCTAssertNil(PersonDepthSampler.distance(depthMap: lowD, confidenceMap: lowC, uprightBox: box, intrinsics: k, cameraInAr: .identity))
    }
    #endif
}
