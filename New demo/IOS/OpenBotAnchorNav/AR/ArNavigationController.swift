import Foundation
import Combine
import ARKit
import SceneKit
import Vision
import OpenBotNavKit

/// Executes a locally recorded route; each leg is rotate, straight, then restore
/// the node heading. Tracking loss or a BLE disconnect requires an explicit restart.
final class ArNavigationController: ObservableObject {
    let session: AnchorARSession
    let map: RecordedMap
    private var executor: WaypointExecutor
    private let link: RobotLink
    private let requiresConnection: Bool
    private let routeLayer = SCNNode()
    private var lastUiTime = -Double.infinity
    private var drawnIndex: Int?
    private var lastPersonScan = -Double.infinity
    private var personBox: PersonBox?
    private var personTime = -Double.infinity
    private var personBusy = false
    private let visionQueue = DispatchQueue(label: "com.openbene.follow")
    private let followConfig = FollowConfig()
    private var visionGeneration = 0
    private var mock: MockRobotLink? { link as? MockRobotLink }

    @Published private(set) var stateText = "请先识别地图使用的锚点。"
    @Published private(set) var detailText = ""
    @Published private(set) var guidanceText = ""
    @Published private(set) var robotPose: Pose2D?
    @Published private(set) var isLocalised = false
    @Published private(set) var isArmed = false
    @Published private(set) var readyToStart = false
    @Published private(set) var progress = 0.0
    @Published private(set) var usedMarkers: [String] = []
    @Published private(set) var followMode = false
    @Published private(set) var followAction = ""
    @Published private(set) var pwm: NavigationPwmSettings
    let robotDescription: String

    init(map: RecordedMap, link: RobotLink, robotDescription: String, requiresConnection: Bool,
         pwm: NavigationPwmSettings = .defaults) {
        self.map = map
        self.link = link
        self.robotDescription = robotDescription
        self.requiresConnection = requiresConnection
        self.pwm = pwm
        session = AnchorARSession(anchor: map.anchor)
        let config = pwm.waypointConfig(sonarInstalled: OpenBotBleLink.sonarInstalled)
        executor = WaypointExecutor(map: map, link: link, config: config)
        session.onSceneReady = { [weak self] view in
            guard let self = self else { return }
            view.scene.rootNode.addChildNode(self.routeLayer)
        }
        session.onFrame = { [weak self] pose, normal, time in self?.frame(pose: pose, normal: normal, time: time) }
        session.onCameraFrame = { [weak self] frame in self?.scanPerson(frame) }
        session.onUnavailable = { [weak self] reason in
            guard let self = self else { return }
            self.isArmed = false
            self.readyToStart = false
            self.visionGeneration += 1
            self.personBox = nil
            self.lastUiTime = -Double.infinity
            self.executor.stop(reason: reason)
            self.stateText = reason
        }
    }

    func start() { session.start() }

    func applyPwm(_ value: NavigationPwmSettings) {
        stopDriving()
        pwm = value
        executor = WaypointExecutor(map: map, link: link,
            config: value.waypointConfig(sonarInstalled: OpenBotBleLink.sonarInstalled))
        stateText = "PWM 已更新，请回到起点后重新开始。"
    }

    func arm() {
        guard !requiresConnection || link.telemetry.connected else {
            stateText = "请等待底盘蓝牙连接就绪。"
            return
        }
        if followMode {
            isArmed = true
            return
        }
        do {
            try executor.start(at: session.capturePose())
            isArmed = true
        } catch { stateText = error.localizedDescription }
    }

    func stopDriving() {
        isArmed = false
        executor.stop()
        link.stop()
        stateText = "已停车；重新执行航线需回到起点。"
    }

    func stopEverything() {
        stopDriving()
        session.pause()
        link.close()
    }

    func setFollowMode(_ enabled: Bool) {
        stopDriving()
        followMode = enabled
        visionGeneration += 1
        personBox = nil
        personTime = -Double.infinity
        routeLayer.isHidden = enabled
        followAction = enabled ? "请让跟随目标站到相机前方，再开始。" : ""
    }

    private func frame(pose: Pose2D?, normal: Bool, time: Double) {
        let connected = !requiresConnection || link.telemetry.connected
        if isArmed {
            if followMode {
                if connected { tickFollow(time) } else { stopDriving(); stateText = "蓝牙已断开。" }
            } else {
                executor.tick(pose: pose, trackingNormal: normal, linkAvailable: connected, nowS: time)
                if !executor.active { isArmed = false }
            }
        }
        let index = executor.waypointIndex + 1
        if session.localised, drawnIndex != index {
            drawnIndex = index
            ARMapDrawing.draw(points: [map.start] + map.waypoints, in: routeLayer,
                              session: session, activeIndex: index)
        }
        guard time - lastUiTime > 0.10 else { return }
        lastUiTime = time
        robotPose = pose
        isLocalised = session.localised
        readyToStart = connected && normal && (followMode || (isLocalised &&
            (pose?.distanceTo(map.start.pose) ?? .infinity) <= executor.config.startToleranceM))
        usedMarkers = session.localised ? [map.anchor.id] : []
        if !followMode {
            progress = map.distanceM > 0 ? min(1, max(0, 1 - executor.distanceRemainingM / map.distanceM)) : 0
            if executor.phase == .arrived { progress = 1 }
            guidanceText = executor.message
            if executor.active || (executor.phase != .idle && executor.phase != .interrupted) {
                stateText = executor.message
            } else if !session.localised || !normal { stateText = session.message }
            else if let pose = pose {
                stateText = String(format: "已定位，距采集起点 %.2f m。", pose.distanceTo(map.start.pose))
            }
        } else {
            guidanceText = followAction
            stateText = isArmed ? "正在跟随" : "跟随模式，等待开始。"
        }
        let poseText = pose.map { String(format: "x %.2f · y %.2f m · 朝向 %.1f°", $0.x, $0.y, $0.yawDeg) } ?? "位置尚未就绪"
        let wheels = mock.map { String(format: "\n轮速指令 %.2f / %.2f", $0.lastLeft, $0.lastRight) }
            ?? String(format: "\n轮速遥测 %.1f / %.1f（仅显示）", link.telemetry.rpmLeft, link.telemetry.rpmRight)
        var controlText = ""
        if let ble = link as? OpenBotBleLink {
            if let command = ble.lastControlFrame, let sentAt = ble.lastControlWriteTime {
                controlText = String(format: "\n最近提交蓝牙：%@（%.1f 秒前）", command, Date().timeIntervalSince(sentAt))
            } else { controlText = "\n尚未提交控车帧" }
            if let error = ble.lastWriteError { controlText += "\n蓝牙写入错误：" + error }
        }
        detailText = poseText + "\n" + robotDescription + (connected ? "" : "（未连接）") + wheels + controlText
    }

    private func tickFollow(_ time: Double) {
        let age = time - personTime
        let command = FollowController.followCommand(box: age <= FollowController.boxTtlS ? personBox : nil,
            config: followConfig, sonarCm: OpenBotBleLink.sonarInstalled ? link.telemetry.sonarCm : nil, secondsSinceSeen: age)
        followAction = command.action
        if command.left == 0 && command.right == 0 { link.stop() }
        else { link.drive(left: command.left, right: command.right) }
    }

    private func scanPerson(_ frame: ARFrame) {
        guard followMode, !personBusy, frame.timestamp - lastPersonScan > 0.15 else { return }
        personBusy = true
        lastPersonScan = frame.timestamp
        let image = frame.capturedImage
        let time = frame.timestamp
        let generation = visionGeneration
        visionQueue.async { [weak self] in
            let request = VNDetectHumanRectanglesRequest()
            try? VNImageRequestHandler(cvPixelBuffer: image, orientation: .right, options: [:]).perform([request])
            let best = request.results?.max { $0.boundingBox.width * $0.boundingBox.height < $1.boundingBox.width * $1.boundingBox.height }
            let box = best.map { observation in
                FollowController.boxFromPixels(leftPx: Double(observation.boundingBox.minX),
                    topPx: 1 - Double(observation.boundingBox.maxY),
                    rightPx: Double(observation.boundingBox.maxX),
                    bottomPx: 1 - Double(observation.boundingBox.minY), frameWidth: 1, frameHeight: 1)
            }
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.personBusy = false
                guard self.visionGeneration == generation, self.followMode else { return }
                self.personBox = box
                self.personTime = time
            }
        }
    }
}
