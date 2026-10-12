import Foundation
import Combine
import ARKit
import SceneKit
import Vision
import UIKit

/// The AR half of the iOS demo: the phone rides on the OpenBot, ARKit keeps the
/// pose, the printed sheets re-localise it and the route executor drives the
/// robot to the selected room.
///
/// Marker fixes come from two sources, in order of accuracy:
///
/// 1. ARKit image anchors, using reference images built at run time from the
///    same PNG sheets that are printed and taped to the floor;
/// 2. the QR payload of the same sheet, decoded with Vision, where the corner
///    pixels are turned into a floor quad by `MarkerGeometry`.
final class ArNavigationController: NSObject, ObservableObject, ARSessionDelegate {

    @Published private(set) var stateText = "starting the AR session"
    @Published private(set) var detailText = ""
    @Published private(set) var guidanceText = ""
    @Published private(set) var isLocalised = false
    @Published private(set) var isArmed = false
    @Published private(set) var robotPose: Pose2D?
    @Published private(set) var usedMarkers: [String] = []
    @Published private(set) var progress: Double = 0.0
    @Published private(set) var robotDescription: String
    @Published private(set) var followMode = false
    @Published private(set) var followAction = ""

    let sceneView = ARSCNView(frame: .zero)

    private let map: MapData
    private let route: Route
    private let steps: [GuidanceStep]
    private let estimator: PoseEstimator
    private let executor: RouteExecutor
    private let link: RobotLink

    private let routeLayer = SCNNode()
    private let targetNode = SCNNode()
    private let targetBeam = SCNNode()
    private let visionQueue = DispatchQueue(label: "com.openbene.anchornav.qr")

    private var lastFrameTime = 0.0
    private var lastQrTime = -10.0
    private var lastFollowScanTime = -10.0
    private var lastUiTime = -10.0
    private var lastRouteBuildTime = -10.0
    private var lastLegIndex = -1
    private var knownFloorY: Double?
    private var qrBusy = false
    private var pendingDetection: QrDetection?
    private var lastStatus: ExecutorStatus?
    private let followConfig = FollowConfig()
    private var followBox: PersonBox?
    private var followBoxTime = -10.0
    private var followBusy = false
    private var pendingFollowBox: (box: PersonBox, time: Double)?
    private var lastFollowCommand: FollowCommand?

    private struct QrDetection {
        let payload: String
        let corners: [[Double]]
        let intrinsics: CameraIntrinsics
        let cameraPose: RigidTransform
        let deviceInAr: Pose2D
        let timestampS: Double
    }

    init(map: MapData, route: Route, steps: [GuidanceStep], link: RobotLink, robotDescription: String) {
        self.map = map
        self.route = route
        self.steps = steps
        self.link = link
        self.robotDescription = robotDescription
        self.estimator = PoseEstimator(mapData: map)
        self.executor = RouteExecutor(mapData: map, estimator: estimator, link: link)
        super.init()

        sceneView.automaticallyUpdatesLighting = false
        sceneView.session.delegate = self
        sceneView.scene.rootNode.addChildNode(routeLayer)
        sceneView.scene.rootNode.addChildNode(targetNode)
        sceneView.scene.rootNode.addChildNode(targetBeam)
        buildTargetNodes()
        guidanceText = steps.first?.message ?? ""
    }

    // ------------------------------------------------------------- life cycle

    func start() {
        guard ARWorldTrackingConfiguration.isSupported else {
            stateText = "this device does not support ARKit world tracking"
            return
        }
        let configuration = ARWorldTrackingConfiguration()
        configuration.worldAlignment = .gravity
        configuration.planeDetection = [.horizontal]
        configuration.maximumNumberOfTrackedImages = 4
        configuration.detectionImages = referenceImages()
        sceneView.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
        stateText = "look at the entrance marker"
    }

    func arm() {
        if followMode {
            isArmed = true
            stateText = "follow mode: the robot drives towards the person in front of it"
            return
        }
        guard estimator.aligned else { return }
        do {
            try executor.start(route, startLocationId: DemoSession.startLocationId)
            isArmed = true
            stateText = "driving"
        } catch {
            stateText = "cannot start the route: \(error)"
        }
    }

    func stopEverything() {
        isArmed = false
        executor.stop()
        link.stop()
        sceneView.session.pause()
    }

    /// Switches between route navigation and the OpenBot tracking behaviour.
    /// Follow mode needs no map, no marker and no localisation: the camera box
    /// alone drives the robot.
    func setFollowMode(_ enabled: Bool) {
        followMode = enabled
        isArmed = false
        executor.stop()
        link.stop()
        lastFollowCommand = nil
        pendingFollowBox = nil
        followBox = nil
        followAction = enabled
            ? "follow mode: put the operator in front of the camera, then tap Start driving"
            : ""
        stateText = enabled ? "follow mode" : "look at the entrance marker"
        routeLayer.isHidden = enabled
        targetNode.isHidden = enabled
        targetBeam.isHidden = enabled
    }

    private func referenceImages() -> Set<ARReferenceImage> {
        var images = Set<ARReferenceImage>()
        for marker in map.markers {
            guard let url = Bundle.main.url(forResource: marker.arImage, withExtension: "png"),
                  let image = UIImage(contentsOfFile: url.path),
                  let cgImage = image.cgImage
            else { continue }
            let reference = ARReferenceImage(cgImage, orientation: .up, physicalWidth: CGFloat(marker.sizeM))
            reference.name = marker.id
            images.insert(reference)
        }
        return images
    }

    // ------------------------------------------------------------ AR delegate

    func session(_ session: ARSession, didFailWithError error: Error) {
        stateText = "AR session failed: \(error.localizedDescription)"
        link.stop()
    }

    func sessionWasInterrupted(_ session: ARSession) {
        stateText = "AR session interrupted, robot stopped"
        link.stop()
    }

    func sessionInterruptionEnded(_ session: ARSession) {
        stateText = "AR session resumed"
    }

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        let now = frame.timestamp
        let dt = lastFrameTime <= 0 ? 0.0 : min(0.5, max(0.0, now - lastFrameTime))
        lastFrameTime = now

        var trackingIsNormal = false
        if case .normal = frame.camera.trackingState { trackingIsNormal = true }
        if !trackingIsNormal && !followMode {
            // The pose is not usable this frame: hold the wheels until it recovers.
            // Follow mode only needs the camera image, so it keeps running.
            link.stop()
            return
        }

        if followMode {
            updateFollow(frame: frame, nowS: now)
            publishUi(now: now)
            return
        }

        let cameraPose = RigidTransform(columnMajor4x4: floats(frame.camera.transform))
        let devicePose = MarkerGeometry.deviceInAr(cameraPose: cameraPose)

        updateFloorHeight(frame: frame)

        var fix: (id: String, marker: Pose2D, device: Pose2D)?
        let expected = executor.expectedMarkerId
        for anchor in frame.anchors {
            guard let imageAnchor = anchor as? ARImageAnchor, imageAnchor.isTracked else { continue }
            guard let name = imageAnchor.referenceImage.name, let marker = try? map.marker(name) else { continue }
            if let expected = expected, expected != marker.id, let current = fix, current.id == expected { continue }
            let markerPose = MarkerGeometry.markerInAr(
                fromImageAnchor: RigidTransform(columnMajor4x4: floats(imageAnchor.transform))
            )
            if fix == nil || marker.id == expected {
                fix = (marker.id, markerPose, devicePose)
            }
            knownFloorY = Double(imageAnchor.transform.columns.3.y)
        }

        if let detection = pendingDetection {
            pendingDetection = nil
            if let marker = map.markerForPayload(detection.payload) {
                let markerPose = MarkerGeometry.markerPose(
                    fromQuad: detection.corners,
                    intrinsics: detection.intrinsics,
                    cameraPose: detection.cameraPose,
                    floorY: knownFloorY,
                    ordered: true,
                    deviceYawRad: detection.deviceInAr.yawRad
                )
                if let markerPose = markerPose, fix == nil || marker.id == expected {
                    fix = (marker.id, markerPose, detection.deviceInAr)
                }
            }
        }

        if let fix = fix {
            applyFix(markerId: fix.id, markerPose: fix.marker, devicePose: fix.device, nowS: now)
        }

        if now - lastQrTime > 0.25 {
            lastQrTime = now
            scanQr(frame: frame, cameraPose: cameraPose, devicePose: devicePose, nowS: now)
        }

        if isArmed {
            let status = executor.tick(nowS: now, dtS: dt)
            lastStatus = status
            if status.state == .arrived || status.state == .failed {
                isArmed = false
            }
        }

        updateSceneNodes(now: now)
        publishUi(now: now)
    }

    // -------------------------------------------------------------- nav logic

    private func applyFix(markerId: String, markerPose: Pose2D, devicePose: Pose2D, nowS: Double) {
        let observation = ArObservation(
            markerId: markerId,
            markerInAr: markerPose,
            deviceInAr: devicePose,
            timestampS: nowS
        )
        guard fixIsPlausible(observation) else { return }
        try? estimator.align(observation)
        executor.noteMarker(markerId)
        if !usedMarkers.contains(markerId) { usedMarkers.append(markerId) }
    }

    /// Reject a fix that would teleport the robot; the QR estimate can be rough.
    private func fixIsPlausible(_ observation: ArObservation) -> Bool {
        guard let transform = estimator.mapFromAr, let current = estimator.pose else { return true }
        let predicted = transform.compose(observation.deviceInAr)
        return current.distanceTo(predicted) <= 3.0
    }

    private func updateFloorHeight(frame: ARFrame) {
        if knownFloorY != nil { return }
        for anchor in frame.anchors {
            guard let plane = anchor as? ARPlaneAnchor, plane.alignment == .horizontal else { continue }
            knownFloorY = Double(plane.transform.columns.3.y)
            return
        }
    }

    // ------------------------------------------------------------- follow mode

    private func updateFollow(frame: ARFrame, nowS: Double) {
        if let pending = pendingFollowBox {
            pendingFollowBox = nil
            followBox = pending.box
            followBoxTime = pending.time
        }
        if nowS - lastFollowScanTime > 0.10 {
            lastFollowScanTime = nowS
            scanFollowTarget(frame: frame, nowS: nowS)
        }
        if isArmed {
            tickFollow(nowS: nowS)
        }
    }

    /// One wheel command per frame, exactly like follow.py does it.
    private func tickFollow(nowS: Double) {
        let ageS = nowS - followBoxTime
        let box = ageS <= FollowController.boxTtlS ? followBox : nil
        let command = FollowController.followCommand(
            box: box,
            config: followConfig,
            sonarCm: link.telemetry.sonarCm,
            secondsSinceSeen: ageS
        )
        lastFollowCommand = command
        followAction = command.action
        if command.left == 0.0 && command.right == 0.0 {
            link.stop()
        } else {
            link.drive(left: command.left, right: command.right)
        }
    }

    /// The person box comes from Vision's human rectangle detector, which needs
    /// no bundled model and runs on the same camera image the QR scanner uses.
    private func scanFollowTarget(frame: ARFrame, nowS: Double) {
        guard !followBusy else { return }
        followBusy = true
        let pixelBuffer = frame.capturedImage
        let width = Double(frame.camera.imageResolution.width)
        let height = Double(frame.camera.imageResolution.height)

        let request = VNDetectHumanRectanglesRequest { [weak self] request, error in
            guard let self = self else { return }
            defer { DispatchQueue.main.async { self.followBusy = false } }
            if let error = error {
                print("human rectangle detection failed: \(error)")
                return
            }
            guard let results = request.results as? [VNHumanObservation], !results.isEmpty else { return }
            let best = results.max {
                $0.boundingBox.width * $0.boundingBox.height < $1.boundingBox.width * $1.boundingBox.height
            }
            guard let observation = best else { return }
            let bounds = observation.boundingBox
            let box = FollowController.boxFromPixels(
                leftPx: Double(bounds.minX) * width,
                topPx: (1.0 - Double(bounds.maxY)) * height,
                rightPx: Double(bounds.maxX) * width,
                bottomPx: (1.0 - Double(bounds.minY)) * height,
                frameWidth: width,
                frameHeight: height
            )
            DispatchQueue.main.async { self.pendingFollowBox = (box, nowS) }
        }

        visionQueue.async {
            let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
            do {
                try handler.perform([request])
            } catch {
                print("human rectangle request failed: \(error)")
            }
        }
    }

    // ------------------------------------------------------------- QR fallback

    private func scanQr(frame: ARFrame, cameraPose: RigidTransform, devicePose: Pose2D, nowS: Double) {
        guard !qrBusy else { return }
        qrBusy = true
        let pixelBuffer = frame.capturedImage
        let intrinsics = cameraIntrinsics(frame: frame)
        let width = Int(frame.camera.imageResolution.width)
        let height = Int(frame.camera.imageResolution.height)

        let request = VNDetectBarcodesRequest { [weak self] request, error in
            guard let self = self else { return }
            defer { DispatchQueue.main.async { self.qrBusy = false } }
            if let error = error {
                print("barcode detection failed: \(error)")
                return
            }
            guard let results = request.results as? [VNBarcodeObservation] else { return }
            for observation in results {
                guard let payload = observation.payloadStringValue else { continue }
                let corners = [observation.topLeft, observation.topRight, observation.bottomRight, observation.bottomLeft]
                    .map { point -> [Double] in
                        [Double(point.x) * Double(width), (1.0 - Double(point.y)) * Double(height)]
                    }
                let detection = QrDetection(
                    payload: payload,
                    corners: corners,
                    intrinsics: intrinsics,
                    cameraPose: cameraPose,
                    deviceInAr: devicePose,
                    timestampS: nowS
                )
                DispatchQueue.main.async { self.pendingDetection = detection }
                break
            }
        }
        request.symbologies = [.qr]

        visionQueue.async {
            let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
            do {
                try handler.perform([request])
            } catch {
                print("vision request failed: \(error)")
            }
        }
    }

    private func cameraIntrinsics(frame: ARFrame) -> CameraIntrinsics {
        let intrinsics = frame.camera.intrinsics
        return CameraIntrinsics(
            fx: Double(intrinsics.columns.0.x),
            fy: Double(intrinsics.columns.1.y),
            cx: Double(intrinsics.columns.2.x),
            cy: Double(intrinsics.columns.2.y),
            width: Int(frame.camera.imageResolution.width),
            height: Int(frame.camera.imageResolution.height)
        )
    }

    // ------------------------------------------------------------- AR overlay

    private func buildTargetNodes() {
        let ring = SCNTorus(ringRadius: 0.22, pipeRadius: 0.012)
        ring.firstMaterial?.diffuse.contents = UIColor.systemTeal
        ring.firstMaterial?.lightingModel = .constant
        targetNode.geometry = ring

        let beam = SCNCylinder(radius: 0.012, height: 1.2)
        beam.firstMaterial?.diffuse.contents = UIColor.systemTeal.withAlphaComponent(0.5)
        beam.firstMaterial?.lightingModel = .constant
        targetBeam.geometry = beam
    }

    private func arPosition(ofMapPose pose: Pose2D) -> SCNVector3? {
        guard let transform = estimator.mapFromAr else { return nil }
        let ar = transform.inverse().compose(pose)
        return SCNVector3(Float(ar.x), 0.02, Float(-ar.y))
    }

    private func updateSceneNodes(now: Double) {
        let status = executor.status()
        let visible = estimator.mapFromAr != nil
        targetNode.isHidden = !visible || status.target == nil
        targetBeam.isHidden = targetNode.isHidden

        if let target = status.target, let position = arPosition(ofMapPose: target) {
            targetNode.position = position
            targetBeam.position = SCNVector3(position.x, position.y + 0.6, position.z)
        }

        let legChanged = status.legIndex != lastLegIndex
        if legChanged || now - lastRouteBuildTime > 1.0 {
            lastLegIndex = status.legIndex
            lastRouteBuildTime = now
            rebuildRouteLine(from: status.legIndex)
        }
    }

    private func rebuildRouteLine(from legIndex: Int) {
        routeLayer.childNodes.forEach { $0.removeFromParentNode() }
        guard estimator.mapFromAr != nil else { return }
        let legs = Array(route.legs.enumerated()).filter { $0.offset >= legIndex }
        for (_, leg) in legs {
            var previous: SCNVector3?
            for point in leg.path {
                guard let position = arPosition(ofMapPose: point) else { continue }
                if let start = previous {
                    routeLayer.addChildNode(segmentNode(from: start, to: position))
                }
                previous = position
            }
        }
    }

    private func segmentNode(from start: SCNVector3, to end: SCNVector3) -> SCNNode {
        let dx = end.x - start.x
        let dz = end.z - start.z
        let length = CGFloat((dx * dx + dz * dz).squareRoot())
        let box = SCNBox(width: 0.03, height: 0.004, length: max(length, 0.001), chamferRadius: 0)
        box.firstMaterial?.diffuse.contents = UIColor.systemTeal.withAlphaComponent(0.65)
        box.firstMaterial?.lightingModel = .constant
        let node = SCNNode(geometry: box)
        node.position = SCNVector3((start.x + end.x) * 0.5, start.y, (start.z + end.z) * 0.5)
        node.eulerAngles = SCNVector3(0, atan2(dx, dz), 0)
        return node
    }

    // --------------------------------------------------------------- publishing

    private func publishUi(now: Double) {
        guard now - lastUiTime >= 0.12 else { return }
        lastUiTime = now

        let status = lastStatus ?? executor.status()
        isLocalised = estimator.aligned
        robotPose = estimator.pose
        progress = route.totalDistanceM > 0
            ? min(1.0, max(0.0, (route.totalDistanceM - status.distanceRemainingM) / route.totalDistanceM))
            : 0.0

        let poseText: String
        if let pose = estimator.pose {
            poseText = String(format: "x %.2f m  y %.2f m  yaw %.0f deg", pose.x, pose.y, pose.yawDeg)
        } else {
            poseText = "not localised yet"
        }

        let fixText = estimator.aligned
            ? String(format: "last marker %@, %d AR fixes", estimator.lastMarkerId ?? "-", estimator.arUpdates)
            : "waiting for a marker fix"

        let distanceText = String(
            format: "remaining %.1f m, to waypoint %.1f m, drift %.1f m",
            status.distanceRemainingM,
            status.distanceToTargetM,
            status.driftM
        )

        var robotLine = "robot: " + robotDescription
        if let sonar = link.telemetry.sonarCm {
            robotLine += String(format: ", sonar %.0f cm", sonar)
        }
        if link.telemetry.bumper != nil {
            robotLine += "  BUMPER!"
        }

        if followMode {
            let action = lastFollowCommand?.action ?? "put the operator in front of the camera"
            stateText = "follow mode: " + action
            detailText = poseText + "\n" + "follow mode: no marker localisation, the camera box drives the robot"
                + "\n" + robotLine
            guidanceText = action
            return
        }

        let headline: String
        switch status.state {
        case .arrived, .failed, .blocked, .driving, .scanning, .needAnchor:
            headline = status.state.rawValue + ": " + status.message
        case .idle:
            headline = estimator.aligned ? "localised. Tap Start driving." : "waiting for a marker fix"
        }

        stateText = headline
        detailText = poseText + "\n" + fixText + "\n" + distanceText + "\n" + robotLine
        guidanceText = currentGuidance(status.distanceRemainingM)
    }

    private func currentGuidance(_ remainingM: Double) -> String {
        let travelled = max(0.0, route.totalDistanceM - remainingM)
        var cumulative = 0.0
        for step in steps {
            cumulative += step.distanceM
            if cumulative >= travelled { return step.message }
        }
        return steps.last?.message ?? ""
    }

    private func floats(_ matrix: simd_float4x4) -> [Double] {
        let columns = [matrix.columns.0, matrix.columns.1, matrix.columns.2, matrix.columns.3]
        return columns.flatMap { [Double($0.x), Double($0.y), Double($0.z), Double($0.w)] }
    }
}
