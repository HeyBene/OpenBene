import SceneKit
import UIKit
import OpenBotNavKit

/// Purple floor ribbon, batched into small meshes instead of one node per frame.
/// All positions pass through the same anchor/map transform as captured nodes.
final class PhoneTrajectoryDrawing {
    let root = SCNNode()
    private let cursor = SCNNode()
    private var chunk = SCNNode()
    private var vertices: [SCNVector3] = []
    private let material = SCNMaterial()
    private var lastCursorTimeS = -Double.infinity
    private let verticesPerChunk = 128 * 6

    init() {
        material.diffuse.contents = UIColor.systemPurple
        material.lightingModel = .constant
        material.isDoubleSided = true
        root.name = "capture.phone-trajectory"
        let arrow = [SCNVector3(0.16, 0, 0), SCNVector3(-0.08, 0, 0.075), SCNVector3(-0.08, 0, -0.075)]
        cursor.geometry = mesh(arrow)
        cursor.name = "capture.phone-position"
        cursor.isHidden = true
        root.addChildNode(cursor)
        root.addChildNode(chunk)
    }

    func reset() {
        root.childNodes.filter { $0 !== cursor }.forEach { $0.removeFromParentNode() }
        vertices.removeAll(keepingCapacity: true)
        chunk = SCNNode()
        root.addChildNode(chunk)
        cursor.isHidden = true
        lastCursorTimeS = -Double.infinity
    }

    func hideCursor() {
        cursor.isHidden = true
        lastCursorTimeS = -Double.infinity
    }

    func showPhone(at pose: Pose2D, timestampS: Double, session: AnchorARSession) {
        guard timestampS - lastCursorTimeS >= 1.0 / 30.0 - 1e-9 || cursor.isHidden,
              let position = session.position(pose, aboveFloor: 0.04),
              let forward = session.position(pose.translated(forwardM: 0.2), aboveFloor: 0.04) else { return }
        lastCursorTimeS = timestampS
        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0
        cursor.position = position
        cursor.eulerAngles.y = atan2(-(forward.z - position.z), forward.x - position.x)
        cursor.isHidden = false
        SCNTransaction.commit()
    }

    func append(from: Pose2D, to: Pose2D, session: AnchorARSession) {
        guard let a = session.position(from, aboveFloor: 0.015),
              let b = session.position(to, aboveFloor: 0.015) else { return }
        let dx = b.x - a.x, dz = b.z - a.z
        let length = hypot(dx, dz)
        guard length > 1e-6 else { return }
        if vertices.count >= verticesPerChunk {
            vertices.removeAll(keepingCapacity: true)
            chunk = SCNNode()
            root.addChildNode(chunk)
        }
        let ox = -dz / length * 0.02, oz = dx / length * 0.02
        let aLeft = SCNVector3(a.x + ox, a.y, a.z + oz)
        let aRight = SCNVector3(a.x - ox, a.y, a.z - oz)
        let bLeft = SCNVector3(b.x + ox, b.y, b.z + oz)
        let bRight = SCNVector3(b.x - ox, b.y, b.z - oz)
        vertices.append(contentsOf: [aLeft, aRight, bLeft, bLeft, aRight, bRight])
        chunk.geometry = mesh(vertices)
    }

    func rebuild(_ samples: [TrajectorySample], session: AnchorARSession) {
        reset()
        for pair in zip(samples, samples.dropFirst()) where !pair.1.startsSegment {
            append(from: pair.0.pose, to: pair.1.pose, session: session)
        }
    }

    private func mesh(_ vertices: [SCNVector3]) -> SCNGeometry {
        let element = SCNGeometryElement(indices: Array(0..<Int32(vertices.count)), primitiveType: .triangles)
        let geometry = SCNGeometry(sources: [SCNGeometrySource(vertices: vertices)], elements: [element])
        geometry.materials = [material]
        return geometry
    }
}
