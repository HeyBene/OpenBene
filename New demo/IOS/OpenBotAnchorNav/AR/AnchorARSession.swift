import ARKit
import Combine
import UIKit
import OpenBotNavKit

/// One printed image defines the persistent map frame. The same frame is used
/// while recording and when reopening a saved map in a fresh AR session.
final class AnchorARSession: NSObject, ObservableObject, ARSessionDelegate {
    let anchor: AnchorDefinition
    @Published private(set) var sceneView: ARSCNView?
    @Published private(set) var hasCameraFrame = false
    @Published private(set) var hasRenderedFrame = false
    @Published private(set) var portraitImageAspectRatio: CGFloat = 0.75
    @Published private(set) var pose: Pose2D?
    @Published private(set) var trackingNormal = false
    @Published private(set) var localised = false
    @Published private(set) var message = "请识别完整的定位标记图。"
    private var fixedFrame = FixedAnchorFrame()
    private var initialAlignment = StableAnchorAlignment()
    var mapFromAr: Pose2D? { fixedFrame.mapFromAr }
    private(set) var floorY: Float = 0
    private var latestPose: Pose2D?
    private var latestDeviceInAr: Pose2D?
    private var lastFrameDate = Date.distantPast
    private var lastUiTime = -Double.infinity
    private var frameWatchdog: Timer?
    private var started = false
    private var ended = false
    private var sessionRunning = false
    private var preparedConfiguration: ARWorldTrackingConfiguration?
    private var trackingWasNormal = false
    private let imageQueue = DispatchQueue(label: "com.openbene.anchor-image", qos: .userInitiated)
    var onSceneReady: ((ARSCNView) -> Void)?
    var onFrame: ((Pose2D?, Bool, Double) -> Void)?
    var onCameraFrame: ((ARFrame) -> Void)?
    var onUnavailable: ((String) -> Void)?
    var onTrackingLimited: ((String) -> Void)?
    var onTrackedImage: ((Pose2D, Double, Float) -> Void)?
    var onImageNotTracked: (() -> Void)?

    init(anchor: AnchorDefinition) {
        self.anchor = anchor
        super.init()
        NotificationCenter.default.addObserver(self, selector: #selector(background),
            name: UIApplication.didEnterBackgroundNotification, object: nil)
    }

    deinit { frameWatchdog?.invalidate(); NotificationCenter.default.removeObserver(self) }

    func start() {
        // onAppear and scenePhase can both fire during presentation. Run only
        // once; resetting the AR world would invalidate every captured node.
        guard !started, !ended else { return }
        started = true
        message = "正在准备相机和定位图片…"
        guard ARWorldTrackingConfiguration.isSupported else {
            message = "此设备不支持 ARKit，请使用支持 ARKit 的 iPhone。"
            return
        }
        guard AVCaptureDevice.authorizationStatus(for: .video) != .denied else {
            message = "请在系统设置中允许相机访问。"
            return
        }
        guard let url = Bundle.main.url(forResource: anchor.imageName, withExtension: "png") else {
            end("定位图片资源缺失。")
            return
        }
        let anchor = self.anchor
        // Let the cover render before creating SceneKit. PNG decoding and AR
        // reference-image preparation must not block the presentation thread.
        imageQueue.async { [weak self] in
            guard let image = UIImage(contentsOfFile: url.path)?.cgImage else {
                DispatchQueue.main.async { self?.end("定位图片资源无法读取。") }
                return
            }
            let reference = ARReferenceImage(image, orientation: .up, physicalWidth: CGFloat(anchor.sizeM))
            reference.name = anchor.id
            DispatchQueue.main.async { [weak self] in self?.run(reference) }
        }
    }

    private func run(_ reference: ARReferenceImage) {
        guard !ended else { return }
        let view = ARSCNView(frame: .zero)
        view.session.delegate = self
        view.session.delegateQueue = .main
        view.automaticallyUpdatesLighting = false
        onSceneReady?(view)
        let configuration = ARWorldTrackingConfiguration()
        configuration.worldAlignment = .gravity
        configuration.detectionImages = [reference]
        configuration.maximumNumberOfTrackedImages = 1
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
            configuration.frameSemantics.insert(.sceneDepth)
        }
        preparedConfiguration = configuration
        sceneView = view
        message = "相机视图准备中，请稍候…"
    }

    /// Start after UIKit finishes presenting and lays out a nonzero viewport.
    /// Receiving AR frames before mounting an ARSCNView does not prove that its
    /// Metal surface is actually displaying the camera image.
    func sceneBecameVisible() {
        guard !ended, !sessionRunning, let view = sceneView,
              view.window != nil, view.bounds.width > 0, view.bounds.height > 0,
              let configuration = preparedConfiguration else { return }
        sessionRunning = true
        view.isPlaying = true
        view.rendersContinuously = true
        view.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
        message = "相机启动中，请稍候…"
        lastFrameDate = Date()
        frameWatchdog = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            guard let self = self, self.trackingNormal,
                  Date().timeIntervalSince(self.lastFrameDate) > 0.6 else { return }
            self.suspendTracking("相机帧中断，已停车；等待相机跟踪恢复。")
        }
    }

    @discardableResult
    func sceneDidRender() -> Bool {
        guard !ended, hasCameraFrame, sceneView?.window != nil else { return false }
        if !hasRenderedFrame { hasRenderedFrame = true }
        return true
    }

    func pause() {
        guard started, !ended else { return }
        end("会话已暂停。请退出并重新打开，重新从锚点和起点开始。")
    }

    @objc private func background() { pause() }

    func capturePose() throws -> Pose2D {
        guard trackingNormal, localised, let latestPose = latestPose,
              Date().timeIntervalSince(lastFrameDate) < 0.5 else {
            throw RecordingError.invalid(localised && trackingNormal ? "请保持手机在支架上的斜向前下方姿态，避免镜头垂直朝地。" : "位置尚未就绪，请识别标记并等待跟踪恢复。")
        }
        return latestPose
    }

    func position(_ pose: Pose2D, aboveFloor height: Float = 0.025) -> SCNVector3? {
        guard let transform = mapFromAr else { return nil }
        let ar = transform.inverse().compose(pose)
        return SCNVector3(Float(ar.x), floorY + height, Float(-ar.y))
    }

    func applyReturnImageAlignment(marker: Pose2D, floorY: Float) throws -> Pose2D {
        guard trackingNormal, localised, let device = latestDeviceInAr,
              Date().timeIntervalSince(lastFrameDate) < 0.3,
              fixedFrame.realignForReturn(markerInAr: marker),
              let corrected = fixedFrame.pose(deviceInAr: device, trackingNormal: true) else {
            throw RecordingError.invalid("图片归位时相机位姿不可用，保持停车。")
        }
        self.floorY = floorY
        latestPose = corrected; pose = corrected
        return corrected
    }

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        guard !ended else { return }
        lastFrameDate = Date()
        if !hasCameraFrame { hasCameraFrame = true }
        let resolution = frame.camera.imageResolution
        if resolution.width > 0, resolution.height > 0 {
            let aspect = resolution.height / resolution.width
            if abs(portraitImageAspectRatio - aspect) > 0.001 { portraitImageAspectRatio = aspect }
        }
        onCameraFrame?(frame)
        let normal: Bool
        if case .normal = frame.camera.trackingState { normal = true } else { normal = false }
        if !normal {
            onImageNotTracked?()
            suspendTracking(localised ? "跟踪暂时受限，已停车。请缓慢移动手机，等待跟踪恢复。" : "请缓慢移动手机，等待相机跟踪并识别定位图片。")
            onFrame?(nil, false, frame.timestamp)
            return
        }
        if !trackingNormal { trackingNormal = true }
        trackingWasNormal = true
        if !localised { for item in frame.anchors {
            guard let image = item as? ARImageAnchor, image.isTracked,
                  image.referenceImage.name == anchor.id else { continue }
            let markerPose = MarkerGeometry.markerInAr(fromImageAnchor:
                RigidTransform(columnMajor4x4: values(image.transform)))
            if let stable = initialAlignment.observe(markerPose, timestampS: frame.timestamp) {
                fixedFrame.alignOnce(markerInAr: stable)
                floorY = image.transform.columns.3.y
                localised = true
            }
            break
        } }
        let device = MarkerGeometry.navigationDeviceInAr(cameraPose:
            RigidTransform(columnMajor4x4: values(frame.camera.transform)))
        latestDeviceInAr = device
        latestPose = device.flatMap { fixedFrame.pose(deviceInAr: $0, trackingNormal: normal) }
        let tracked = frame.anchors.compactMap { $0 as? ARImageAnchor }.first {
            $0.isTracked && $0.referenceImage.name == anchor.id
        }
        if let image = tracked {
            let marker = MarkerGeometry.markerInAr(fromImageAnchor: RigidTransform(columnMajor4x4: values(image.transform)))
            onTrackedImage?(marker, frame.timestamp, image.transform.columns.3.y)
        } else { onImageNotTracked?() }
        if frame.timestamp - lastUiTime > 0.10 {
            lastUiTime = frame.timestamp
            pose = latestPose
            if localised {
                message = latestPose == nil ? "锚点已固定；请将手机装好支架、镜头斜向前下方，保持安装姿态。" : "锚点已固定，可离开图片；无需移到图片正上方。"
            } else { message = "请识别 \(anchor.title) 的完整图片并保持稳定片刻。" }
        }
        onFrame?(latestPose, true, frame.timestamp)
    }

    func session(_ session: ARSession, didFailWithError error: Error) {
        end("AR 会话错误：" + error.localizedDescription)
    }
    func sessionWasInterrupted(_ session: ARSession) { end("会话中断，已停车。请退出并重新打开。") }
    func sessionShouldAttemptRelocalization(_ session: ARSession) -> Bool { false }

    private func suspendTracking(_ reason: String) {
        if !localised { initialAlignment.reset() }
        latestPose = nil
        if pose != nil { pose = nil }
        if trackingNormal { trackingNormal = false }
        if message != reason { message = reason }
        if trackingWasNormal {
            trackingWasNormal = false
            lastUiTime = -Double.infinity
            onTrackingLimited?(reason)
        }
    }

    private func end(_ reason: String) {
        guard !ended else { return }
        ended = true
        frameWatchdog?.invalidate()
        frameWatchdog = nil
        sceneView?.session.pause()
        suspendTracking(reason)
        onUnavailable?(reason)
        onFrame?(nil, false, ProcessInfo.processInfo.systemUptime)
    }

    private func values(_ matrix: simd_float4x4) -> [Double] {
        [matrix.columns.0, matrix.columns.1, matrix.columns.2, matrix.columns.3]
            .flatMap { [Double($0.x), Double($0.y), Double($0.z), Double($0.w)] }
    }
}

enum ARMapDrawing {
    static func draw(points: [RecordedWaypoint], in layer: SCNNode, session: AnchorARSession,
                     activeIndex: Int? = nil) {
        layer.childNodes.forEach { $0.removeFromParentNode() }
        var previous: SCNVector3?
        for (index, point) in points.enumerated() {
            guard let position = session.position(point.pose) else { continue }
            let colour: UIColor = index == activeIndex ? .systemOrange : .systemTeal
            let sphere = SCNSphere(radius: point.isAutomatic == true ? 0.025 : 0.05)
            sphere.firstMaterial?.diffuse.contents = colour
            sphere.firstMaterial?.lightingModel = .constant
            let node = SCNNode(geometry: sphere)
            node.position = position
            layer.addChildNode(node)
            if let previous = previous { layer.addChildNode(line(previous, position, colour: .systemTeal)) }
            // Every node shows its saved heading as a short arrow on the floor.
            if point.isAutomatic != true, let head = session.position(point.pose.translated(forwardM: 0.35)) {
                layer.addChildNode(line(position, head, colour: colour))
                for side in [-1.0, 1.0] {
                    let tip = point.pose.translated(forwardM: 0.25, leftM: side * 0.08)
                    if let wing = session.position(tip) { layer.addChildNode(line(head, wing, colour: colour)) }
                }
            }
            previous = position
        }
    }

    private static func line(_ start: SCNVector3, _ end: SCNVector3, colour: UIColor) -> SCNNode {
        let dx = end.x - start.x, dz = end.z - start.z
        let length = CGFloat(hypot(dx, dz))
        let box = SCNBox(width: 0.025, height: 0.006, length: max(length, 0.001), chamferRadius: 0)
        box.firstMaterial?.diffuse.contents = colour
        box.firstMaterial?.lightingModel = .constant
        let node = SCNNode(geometry: box)
        node.position = SCNVector3((start.x + end.x) / 2, start.y, (start.z + end.z) / 2)
        node.eulerAngles.y = atan2(dx, dz)
        return node
    }
}
