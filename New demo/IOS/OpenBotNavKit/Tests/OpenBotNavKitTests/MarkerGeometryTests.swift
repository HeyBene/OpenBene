import XCTest
@testable import OpenBotNavKit

/// Round trip tests for the monocular marker pose, mirroring
/// shared/navcore/tests/test_marker_math.py: a synthetic pinhole camera looks at
/// a printed sheet lying on the floor, and the estimator has to recover the pose
/// that generated the corner pixels.
final class MarkerGeometryTests: XCTestCase {

    private let intrinsics = CameraIntrinsics(fx: 1420, fy: 1420, cx: 960, cy: 720, width: 1920, height: 1440)

    private func scene(
        cameraHeightM: Double = 0.40,
        cameraPitchDeg: Double = -35.0,
        cameraYawDeg: Double = 0.0,
        sheetDistanceM: Double = 1.2,
        sheetYawDeg: Double = 90.0,
        sheetSizeM: Double = 0.12
    ) -> (camera: RigidTransform, sheet: Pose2D, pixels: [[Double]]) {
        let camera = RigidTransform.fromYawPitchRoll(
            position: (0, cameraHeightM, 0),
            yawDeg: cameraYawDeg,
            pitchDeg: cameraPitchDeg
        )
        let sheet = Pose2D(x: 0, y: sheetDistanceM, yawRad: sheetYawDeg * Double.pi / 180.0)
        let corners = MarkerGeometry.sheetCornersWorld(sheet: sheet, sizeM: sheetSizeM)
        guard let pixels = MarkerGeometry.projectCorners(corners, intrinsics: intrinsics, cameraPose: camera) else {
            XCTFail("the scene does not project")
            return (camera, sheet, [])
        }
        return (camera, sheet, pixels)
    }

    private func assertPose(_ recovered: Pose2D?, closeTo expected: Pose2D, yawToleranceDeg: Double = 1.5, positionToleranceM: Double = 0.02) {
        guard let recovered = recovered else {
            XCTFail("the estimator returned no pose")
            return
        }
        XCTAssertLessThan(recovered.distanceTo(expected), positionToleranceM)
        XCTAssertLessThan(abs(wrapDeg(recovered.yawDeg - expected.yawDeg)), yawToleranceDeg)
    }

    func testKnownFloorExactRoundTrip() {
        let (camera, sheet, pixels) = scene()
        let recovered = MarkerGeometry.markerPose(
            fromQuad: pixels,
            intrinsics: intrinsics,
            cameraPose: camera,
            floorY: 0.0,
            centreOffsetAlongYM: 0.0
        )
        assertPose(recovered, closeTo: sheet)
    }

    func testFloorHeightSolvedFromThePrintedSize() {
        for height in [0.30, 0.40, 0.55] {
            for distance in [0.8, 1.2, 1.8] {
                let (camera, sheet, pixels) = scene(cameraHeightM: height, sheetDistanceM: distance)
                let recovered = MarkerGeometry.markerPose(
                    fromQuad: pixels,
                    intrinsics: intrinsics,
                    cameraPose: camera,
                    quadSizeM: 0.12,
                    assumedHeightM: 0.40,
                    centreOffsetAlongYM: 0.0
                )
                assertPose(recovered, closeTo: sheet)
            }
        }
    }

    func testSolvedHeightMatchesTheScene() {
        let (camera, _, pixels) = scene(cameraHeightM: 0.55, sheetDistanceM: 1.5)
        let height = MarkerGeometry.solveCameraHeight(
            corners: pixels,
            intrinsics: intrinsics,
            cameraPose: camera,
            quadSizeM: 0.12
        )
        XCTAssertNotNil(height)
        XCTAssertEqual(height ?? 0, 0.55, accuracy: 0.01)
    }

    func testSheetRotationIsRecovered() {
        for yaw in [-90.0, -45.0, 0.0, 30.0, 90.0] {
            let (camera, sheet, pixels) = scene(sheetYawDeg: yaw)
            let recovered = MarkerGeometry.markerPose(
                fromQuad: pixels,
                intrinsics: intrinsics,
                cameraPose: camera,
                floorY: 0.0,
                centreOffsetAlongYM: 0.0
            )
            assertPose(recovered, closeTo: sheet, yawToleranceDeg: 3.0)
        }
    }

    func testYawGateFallsBackToTheDeviceHeadingForACornerOrderError() {
        let (camera, _, pixels) = scene()
        let rotated = [pixels[1], pixels[2], pixels[3], pixels[0]]
        let deviceYaw = MarkerGeometry.deviceInAr(cameraPose: camera).yawRad
        let recovered = MarkerGeometry.markerPose(
            fromQuad: rotated,
            intrinsics: intrinsics,
            cameraPose: camera,
            floorY: 0.0,
            centreOffsetAlongYM: 0.0,
            deviceYawRad: deviceYaw
        )
        XCTAssertNotNil(recovered)
        XCTAssertEqual(recovered?.yawRad ?? 0, deviceYaw, accuracy: 1e-9)
    }

    func testUnorderedCornersUseTheDeviceHeading() {
        let (camera, _, pixels) = scene()
        let device = MarkerGeometry.deviceInAr(cameraPose: camera)
        let recovered = MarkerGeometry.markerPose(
            fromQuad: pixels,
            intrinsics: intrinsics,
            cameraPose: camera,
            floorY: 0.0,
            centreOffsetAlongYM: 0.0,
            ordered: false,
            deviceYawRad: device.yawRad
        )
        XCTAssertEqual(recovered?.yawRad ?? 0, device.yawRad, accuracy: 1e-9)
        XCTAssertEqual(recovered?.y ?? 0, device.y, accuracy: 1e-6)
    }

    func testDevicePoseKeepsPitchOutOfTheHeading() {
        for yaw in [-40.0, 0.0, 25.0] {
            let (camera, _, _) = scene(cameraYawDeg: yaw, cameraPitchDeg: -30.0)
            let planar = MarkerGeometry.deviceInAr(cameraPose: camera)
            XCTAssertEqual(planar.x, 0.0, accuracy: 1e-9)
            XCTAssertEqual(planar.y, 0.0, accuracy: 1e-9)
            XCTAssertEqual(planar.yawDeg, 90.0 + yaw, accuracy: 1e-9)
        }
    }

    func testImageAnchorPoseUsesThePrintedArrow() {
        // The sheet pose in the AR frame, 1.2 m ahead of the camera, arrow along -z.
        let anchor = RigidTransform(
            x: 0, y: 0, z: -1.2,
            rotation: [1, 0, 0, 0, 1, 0, 0, 0, 1]
        )
        let planar = MarkerGeometry.markerInAr(fromImageAnchor: anchor)
        XCTAssertEqual(planar.x, 0.0, accuracy: 1e-9)
        XCTAssertEqual(planar.y, 1.2, accuracy: 1e-9)
        XCTAssertEqual(planar.yawDeg, 90.0, accuracy: 1e-9)
    }
}
