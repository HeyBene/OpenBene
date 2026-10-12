import Foundation

/// Pinhole intrinsics of one camera image, in pixels.
public struct CameraIntrinsics: Equatable {
    public var fx: Double
    public var fy: Double
    public var cx: Double
    public var cy: Double
    public var width: Int
    public var height: Int

    public init(fx: Double, fy: Double, cx: Double, cy: Double, width: Int, height: Int) {
        self.fx = fx
        self.fy = fy
        self.cx = cx
        self.cy = cy
        self.width = width
        self.height = height
    }

    /// Fallback when the AR session cannot report the real intrinsics.
    public static func fromHorizontalFov(width: Int, height: Int, hfovDeg: Double = 60.0) -> CameraIntrinsics {
        let focal = 0.5 * Double(width) / tan(hfovDeg * Double.pi / 180.0 * 0.5)
        return CameraIntrinsics(
            fx: focal,
            fy: focal,
            cx: 0.5 * Double(width),
            cy: 0.5 * Double(height),
            width: width,
            height: height
        )
    }
}

/// A camera pose in the AR world, kept independent of ARKit so the geometry can
/// be reasoned about (and unit tested) on its own. `rotation` is row major 3x3.
public struct RigidTransform {
    public var x: Double
    public var y: Double
    public var z: Double
    public var rotation: [Double]

    public init(x: Double, y: Double, z: Double, rotation: [Double]) {
        self.x = x
        self.y = y
        self.z = z
        self.rotation = rotation
    }

    public static let identity = RigidTransform(
        x: 0, y: 0, z: 0,
        rotation: [1, 0, 0, 0, 1, 0, 0, 0, 1]
    )

    /// Build from a column major 4x4 matrix, the layout ARKit uses.
    public init(columnMajor4x4 m: [Double]) {
        self.x = m[12]
        self.y = m[13]
        self.z = m[14]
        self.rotation = [
            m[0], m[4], m[8],
            m[1], m[5], m[9],
            m[2], m[6], m[10],
        ]
    }

    /// R = Ry(yaw) * Rx(pitch) * Rz(roll), used by the tests and the simulator.
    public static func fromYawPitchRoll(
        position: (Double, Double, Double),
        yawDeg: Double = 0.0,
        pitchDeg: Double = 0.0,
        rollDeg: Double = 0.0
    ) -> RigidTransform {
        let yaw = yawDeg * Double.pi / 180.0
        let pitch = pitchDeg * Double.pi / 180.0
        let roll = rollDeg * Double.pi / 180.0
        let cy = cos(yaw), sy = sin(yaw)
        let cp = cos(pitch), sp = sin(pitch)
        let cr = cos(roll), sr = sin(roll)

        let ry: [Double] = [cy, 0, sy, 0, 1, 0, -sy, 0, cy]
        let rx: [Double] = [1, 0, 0, 0, cp, -sp, 0, sp, cp]
        let rz: [Double] = [cr, -sr, 0, sr, cr, 0, 0, 0, 1]
        return RigidTransform(
            x: position.0,
            y: position.1,
            z: position.2,
            rotation: mat3Mul(mat3Mul(ry, rx), rz)
        )
    }

    public func rotate(_ vector: [Double]) -> [Double] {
        [
            rotation[0] * vector[0] + rotation[1] * vector[1] + rotation[2] * vector[2],
            rotation[3] * vector[0] + rotation[4] * vector[1] + rotation[5] * vector[2],
            rotation[6] * vector[0] + rotation[7] * vector[1] + rotation[8] * vector[2],
        ]
    }

    public func transformPoint(_ point: [Double]) -> [Double] {
        let rotated = rotate(point)
        return [rotated[0] + x, rotated[1] + y, rotated[2] + z]
    }

    public var position: [Double] { [x, y, z] }
}

public func mat3Mul(_ left: [Double], _ right: [Double]) -> [Double] {
    var out = [Double](repeating: 0.0, count: 9)
    for row in 0..<3 {
        for column in 0..<3 {
            var total = 0.0
            for k in 0..<3 {
                total += left[row * 3 + k] * right[k * 3 + column]
            }
            out[row * 3 + column] = total
        }
    }
    return out
}

/// Marker pose from camera pixels. Port of shared/navcore/openbene_nav/marker_math.py,
/// which is covered by the Python round trip tests; keep the two in step.
///
/// The image anchor gives an exact marker pose on its own. This is the fallback
/// used when only a QR detection is available: corner pixels become camera rays,
/// the rays are rotated into the AR world and cut the floor plane, and the
/// resulting quad gives the marker centre and the direction of the printed
/// arrow. The planar frame is x = world x, y = -world z, which keeps rotations
/// about the gravity axis as plain 2D rotations.
public enum MarkerGeometry {
    public static let defaultCodeQuadSizeM = 0.12
    public static let defaultCameraHeightM = 0.40
    public static let codeCentreOffsetAlongYM = -0.0033
    public static let defaultYawGateDeg = 60.0

    public static func pixelRay(_ intrinsics: CameraIntrinsics, u: Double, v: Double) -> [Double] {
        let dx = (u - intrinsics.cx) / intrinsics.fx
        let dy = -(v - intrinsics.cy) / intrinsics.fy
        let length = (dx * dx + dy * dy + 1.0).squareRoot()
        return [dx / length, dy / length, -1.0 / length]
    }

    public static func intersectFloor(origin: [Double], direction: [Double], floorY: Double) -> [Double]? {
        if direction[1] > -1e-3 { return nil }
        let distance = (floorY - origin[1]) / direction[1]
        if distance <= 0.0 { return nil }
        return [
            origin[0] + distance * direction[0],
            origin[1] + distance * direction[1],
            origin[2] + distance * direction[2],
        ]
    }

    public static func quadOnFloor(
        corners: [[Double]],
        intrinsics: CameraIntrinsics,
        cameraPose: RigidTransform,
        floorY: Double
    ) -> [[Double]]? {
        var quad: [[Double]] = []
        for corner in corners {
            let ray = cameraPose.rotate(pixelRay(intrinsics, u: corner[0], v: corner[1]))
            guard let hit = intersectFloor(origin: cameraPose.position, direction: ray, floorY: floorY) else {
                return nil
            }
            quad.append(hit)
        }
        return quad
    }

    public static func meanEdgeLength(_ quad: [[Double]]) -> Double {
        guard quad.count >= 2 else { return 0.0 }
        var total = 0.0
        for index in 0..<quad.count {
            let first = quad[index]
            let second = quad[(index + 1) % quad.count]
            total += distance(first, second)
        }
        return total / Double(quad.count)
    }

    /// Heading of a world direction in the AR plane frame (x = world x, y = -world z).
    public static func planarYaw(ofDirection direction: [Double]) -> Double {
        atan2(-direction[2], direction[0])
    }

    public static func planarPose(ofPoint position: [Double], yawRad: Double) -> Pose2D {
        Pose2D(x: position[0], y: -position[2], yawRad: wrapRad(yawRad))
    }

    /// Planar pose of the camera: position plus the heading of its view axis.
    public static func deviceInAr(cameraPose: RigidTransform) -> Pose2D {
        let forward = cameraPose.rotate([0, 0, -1])
        let horizontal = (forward[0] * forward[0] + forward[2] * forward[2]).squareRoot()
        let yaw = horizontal < 1e-6 ? 0.0 : planarYaw(ofDirection: [forward[0], 0, forward[2]])
        return planarPose(ofPoint: cameraPose.position, yawRad: yaw)
    }

    /// Planar pose of an ARKit image anchor: the tracked sheet reports its centre
    /// with the print in the anchor's local X-Z plane, +X across the print from
    /// left to right, +Y as the sheet normal and +Z from the top edge to the
    /// bottom edge, so the printed arrow (the image +y axis) is the local -Z axis.
    public static func markerInAr(fromImageAnchor anchor: RigidTransform) -> Pose2D {
        let arrow = anchor.rotate([0, 0, -1])
        let horizontal = (arrow[0] * arrow[0] + arrow[2] * arrow[2]).squareRoot()
        let yaw = horizontal < 1e-6 ? 0.0 : planarYaw(ofDirection: [arrow[0], 0, arrow[2]])
        return planarPose(ofPoint: anchor.position, yawRad: yaw)
    }

    /// Camera height above the floor, solved from the printed size of the code:
    /// intersecting the corner rays with a plane at a guessed height scales the
    /// quad linearly, so one measurement corrects the guess.
    public static func solveCameraHeight(
        corners: [[Double]],
        intrinsics: CameraIntrinsics,
        cameraPose: RigidTransform,
        quadSizeM: Double,
        assumedHeightM: Double = defaultCameraHeightM,
        iterations: Int = 3
    ) -> Double? {
        var height = assumedHeightM
        for _ in 0..<max(1, iterations) {
            guard let quad = quadOnFloor(
                corners: corners,
                intrinsics: intrinsics,
                cameraPose: cameraPose,
                floorY: cameraPose.y - height
            ) else { return nil }
            let measured = meanEdgeLength(quad)
            if measured <= 1e-6 { return nil }
            height *= quadSizeM / measured
            if height <= 0.02 || height > 3.0 { return nil }
        }
        return height
    }

    /// Marker pose in the AR plane frame from four detected corner pixels.
    ///
    /// - Parameters:
    ///   - corners: clockwise from the code's own top left corner, which is how
    ///     ML Kit reports it. Vision corner order is not trusted as much, so the
    ///     yaw gate below catches an unexpected order and falls back to the
    ///     device heading.
    ///   - floorY: floor height in the AR world, when a plane is available.
    ///   - ordered: false when the corner order cannot be trusted; the heading
    ///     then comes from `deviceYawRad`, which is sound because the executor
    ///     turns the robot to face the marker before it scans.
    public static func markerPose(
        fromQuad corners: [[Double]],
        intrinsics: CameraIntrinsics,
        cameraPose: RigidTransform,
        floorY: Double? = nil,
        quadSizeM: Double = defaultCodeQuadSizeM,
        assumedHeightM: Double = defaultCameraHeightM,
        centreOffsetAlongYM: Double = codeCentreOffsetAlongYM,
        ordered: Bool = true,
        deviceYawRad: Double? = nil,
        yawGateDeg: Double = defaultYawGateDeg
    ) -> Pose2D? {
        guard corners.count == 4 else { return nil }

        let resolvedFloorY: Double
        if let floorY = floorY {
            resolvedFloorY = floorY
        } else {
            let solved = solveCameraHeight(
                corners: corners,
                intrinsics: intrinsics,
                cameraPose: cameraPose,
                quadSizeM: quadSizeM,
                assumedHeightM: assumedHeightM
            )
            resolvedFloorY = cameraPose.y - (solved ?? assumedHeightM)
        }

        guard let quad = quadOnFloor(
            corners: corners,
            intrinsics: intrinsics,
            cameraPose: cameraPose,
            floorY: resolvedFloorY
        ) else { return nil }

        var centre = [0.0, 0.0, 0.0]
        for point in quad {
            centre[0] += point[0] / 4.0
            centre[1] += point[1] / 4.0
            centre[2] += point[2] / 4.0
        }

        let yaw: Double
        if ordered {
            let topMid = midpoint(quad[0], quad[1])
            let bottomMid = midpoint(quad[3], quad[2])
            let upX = topMid[0] - bottomMid[0]
            let upZ = topMid[2] - bottomMid[2]
            if (upX * upX + upZ * upZ).squareRoot() < 1e-6 { return nil }
            let quadYaw = planarYaw(ofDirection: [upX, 0, upZ])
            if let deviceYaw = deviceYawRad, abs(wrapRad(quadYaw - deviceYaw)) > yawGateDeg * Double.pi / 180.0 {
                yaw = deviceYaw
            } else {
                yaw = quadYaw
            }
        } else {
            guard let deviceYaw = deviceYawRad else { return nil }
            yaw = deviceYaw
        }

        let shifted = [
            centre[0] + centreOffsetAlongYM * cos(yaw),
            centre[1],
            centre[2] - centreOffsetAlongYM * sin(yaw),
        ]
        return planarPose(ofPoint: shifted, yawRad: yaw)
    }

    // ------------------------------------------------------- test scene helpers

    public static func projectPoint(_ intrinsics: CameraIntrinsics, cameraPoint: [Double]) -> (Double, Double)? {
        let depth = -cameraPoint[2]
        if depth <= 1e-6 { return nil }
        return (
            intrinsics.cx + intrinsics.fx * cameraPoint[0] / depth,
            intrinsics.cy - intrinsics.fy * cameraPoint[1] / depth
        )
    }

    public static func projectCorners(
        _ cornersWorld: [[Double]],
        intrinsics: CameraIntrinsics,
        cameraPose: RigidTransform
    ) -> [[Double]]? {
        var pixels: [[Double]] = []
        for point in cornersWorld {
            let delta = [point[0] - cameraPose.x, point[1] - cameraPose.y, point[2] - cameraPose.z]
            // inverse rotation: multiply by R^T
            let r = cameraPose.rotation
            let cameraPoint = [
                r[0] * delta[0] + r[3] * delta[1] + r[6] * delta[2],
                r[1] * delta[0] + r[4] * delta[1] + r[7] * delta[2],
                r[2] * delta[0] + r[5] * delta[1] + r[8] * delta[2],
            ]
            guard let pixel = projectPoint(intrinsics, cameraPoint: cameraPoint) else { return nil }
            pixels.append([pixel.0, pixel.1])
        }
        return pixels
    }

    /// The four corners of a floor sheet, in the world frame of the tests: world
    /// x = planar x, world z = -planar y, floor at y = 0. Corner order is the
    /// code order: top-left, top-right, bottom-right, bottom-left.
    public static func sheetCornersWorld(sheet: Pose2D, sizeM: Double) -> [[Double]] {
        let half = sizeM * 0.5
        let cosY = cos(sheet.yawRad)
        let sinY = sin(sheet.yawRad)
        let local: [(Double, Double)] = [(-half, half), (half, half), (half, -half), (-half, -half)]
        return local.map { point in
            let planarX = sheet.x + sinY * point.0 + cosY * point.1
            let planarY = sheet.y - cosY * point.0 + sinY * point.1
            return [planarX, 0.0, -planarY]
        }
    }

    private static func midpoint(_ first: [Double], _ second: [Double]) -> [Double] {
        [(first[0] + second[0]) * 0.5, (first[1] + second[1]) * 0.5, (first[2] + second[2]) * 0.5]
    }

    private static func distance(_ first: [Double], _ second: [Double]) -> Double {
        let dx = first[0] - second[0]
        let dy = first[1] - second[1]
        let dz = first[2] - second[2]
        return (dx * dx + dy * dy + dz * dz).squareRoot()
    }
}
