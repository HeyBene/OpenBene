import Foundation
import Combine
import ARKit
import SceneKit
import OpenBotNavKit

/// Executes a locally recorded route; each leg is rotate, straight, then restore
/// the node heading. Temporary tracking loss pauses the current target.
final class ArNavigationController: ObservableObject {
    let session: AnchorARSession
    let map: RecordedMap
    private var executor: WaypointExecutor
    @Published private(set) var displayPoints: [RecordedWaypoint]
    private let link: RobotLink
    private let requiresConnection: Bool
    private let routeLayer = SCNNode()
    private var lastUiTime = -Double.infinity
    private var drawnIndex: Int?
    private let diagnostics = FollowDiagnostics(fileName: "navigation.jsonl", tag: "Navigation")
    private var healthTimer: Timer?
    private var lastFrameUptime = -Double.infinity
    private var lastLogUptime = -Double.infinity
    private var lastLoggedPhase: WaypointPhase?
    private var returnImageStability = StableAnchorAlignment()
    let followDriver: PersonFollowDriver
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
    @Published private(set) var returnMode = false
    @Published private(set) var returnNodeID: UUID
    private var lastReachedManualID: UUID?
    private var completedDistanceM = 0.0
    var returnNodes: [RecordedWaypoint] {
        (map.anchorStart == nil ? [] : [map.start]) + map.waypoints
    }
    var selectedReturnID: UUID? { returnMode ? returnNodeID : nil }
    let robotDescription: String

    init(map: RecordedMap, link: RobotLink, robotDescription: String, requiresConnection: Bool,
         pwm: NavigationPwmSettings = .defaults) {
        followDriver = PersonFollowDriver(link: requiresConnection ? link : nil, pwm: pwm)
        self.map = map
        returnNodeID = map.waypoints.last?.id ?? map.start.id
        displayPoints = map.executionPoints
        self.link = link
        self.robotDescription = robotDescription
        self.requiresConnection = requiresConnection
        self.pwm = pwm
        session = AnchorARSession(anchor: map.anchor)
        let config = Self.navigationConfig(pwm)
        executor = WaypointExecutor(map: map, link: link, config: config)
        session.onSceneReady = { [weak self] view in
            guard let self = self else { return }
            view.scene.rootNode.addChildNode(self.routeLayer)
        }
        session.onFrame = { [weak self] pose, normal, time in self?.frame(pose: pose, normal: normal, time: time) }
        session.onCameraFrame = { [weak self] frame in
            guard let self = self else { return }
            self.followDriver.scan(frame, viewportSize: self.session.sceneView?.bounds.size ?? .zero)
        }
        session.onUnavailable = { [weak self] reason in
            guard let self = self else { return }
            self.isArmed = false
            self.readyToStart = false
            self.followDriver.stop(reason: reason)
            self.lastUiTime = -Double.infinity
            self.executor.stop(reason: reason)
            self.stateText = reason
            self.diagnostics.record(["event": "sessionEnded", "reason": reason])
        }
        session.onTrackingLimited = { [weak self] reason in
            guard let self = self else { return }
            if self.followMode { self.followDriver.trackingUnavailable(reason) }
            else if self.isArmed {
                self.executor.pauseForTracking(reason: reason)
                self.isArmed = self.executor.active
            }
            self.readyToStart = false
            self.stateText = reason
            self.diagnostics.record(["event": "trackingLimited", "reason": reason,
                                     "phase": self.executor.phase.rawValue, "target": self.executor.waypointIndex])
        }
        session.onTrackedImage = { [weak self] marker, time, floor in
            self?.returnImage(marker: marker, timestamp: time, floorY: floor)
        }
        session.onImageNotTracked = { [weak self] in self?.returnImageStability.reset() }
    }

    private static func navigationConfig(_ pwm: NavigationPwmSettings) -> WaypointConfig {
        var config = pwm.waypointConfig(sonarInstalled: OpenBotBleLink.sonarInstalled)
        config.requireReturnImage = true
        return config
    }

    deinit { healthTimer?.invalidate() }

    func start() {
        session.start()
        if healthTimer == nil {
            let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in self?.healthCheck() }
            RunLoop.main.add(timer, forMode: .common); healthTimer = timer
        }
    }

    func applyPwm(_ value: NavigationPwmSettings) {
        stopDriving()
        pwm = value
        followDriver.applyPwm(value)
        executor = WaypointExecutor(map: map, link: link,
            config: Self.navigationConfig(value))
        refreshRoutePreview()
        stateText = "PWM 已更新，请在所选路线出发处重新开始。"
    }

    func arm() {
        guard !requiresConnection || link.telemetry.connected else {
            stateText = "请等待底盘蓝牙连接就绪。"
            return
        }
        if followMode {
            followDriver.startFollowing()
            return
        }
        guard map.hasCapturedRoute else {
            stateText = "此旧地图没有采集轨迹，请重新采集后执行带状路线。"
            return
        }
        do {
            try executor.start(at: session.capturePose(), returningFrom: selectedReturnID)
            returnImageStability.reset()
            displayPoints = executor.points
            completedDistanceM = executor.distanceRemainingM
            drawnIndex = nil
            isArmed = true
            diagnostics.record(["event": "start", "returning": returnMode, "target": executor.waypointIndex])
        } catch {
            executor.stop(reason: error.localizedDescription)
            stateText = error.localizedDescription
        }
    }

    func stopDriving() {
        isArmed = false
        let reason = returnMode ? "已停车；返程需在所选节点附近手动开始。" : "已停车；去程需回到锚点旁出发位置手动开始。"
        executor.stop(reason: reason)
        returnImageStability.reset()
        followDriver.stop()
        link.stop()
        stateText = reason
        diagnostics.record(["event": "manualStop", "reason": reason])
    }

    func stopEverything() {
        stopDriving()
        healthTimer?.invalidate(); healthTimer = nil
        followDriver.setEnabled(false)
        session.pause()
        link.close()
    }

    func setFollowMode(_ enabled: Bool) {
        stopDriving()
        followMode = enabled
        followDriver.setEnabled(enabled)
        routeLayer.isHidden = enabled
        followAction = enabled ? "请让跟随目标站到相机前方，再开始。" : ""
    }

    func setReturnMode(_ enabled: Bool) {
        guard !isArmed else { return }
        stopDriving()
        returnMode = enabled
        if enabled, let last = lastReachedManualID, returnNodes.contains(where: { $0.id == last }) {
            returnNodeID = last
        }
        refreshRoutePreview()
    }

    func selectReturnNode(_ id: UUID) {
        guard !isArmed else { return }
        stopDriving()
        returnNodeID = id
        refreshRoutePreview()
    }

    private func refreshRoutePreview() {
        executor = WaypointExecutor(map: map, link: link,
            config: Self.navigationConfig(pwm))
        completedDistanceM = 0
        displayPoints = (try? RouteEntryPlanner.traversal(map: map, returningFrom: selectedReturnID).points) ?? map.executionPoints
        drawnIndex = nil
        readyToStart = false
        progress = 0
        stateText = returnMode ? "返程沿原路线返回锚点旁出发位姿；请确认所选节点与车的位置一致。" : "已切换去程；请回到锚点旁出发位置。"
        guidanceText = stateText
    }

    private func frame(pose: Pose2D?, normal: Bool, time: Double) {
        lastFrameUptime = ProcessInfo.processInfo.systemUptime
        let connected = !requiresConnection || link.telemetry.connected
        if followMode {
            followDriver.observeFrame(trackingNormal: normal, timestampS: time)
            isArmed = followDriver.active || followDriver.pending
            followAction = followDriver.status
        } else if isArmed {
            // Delegate callbacks and the no-frame watchdog must share one
            // clock. AR capture timestamps precede callback uptime slightly.
            executor.tick(pose: pose, trackingNormal: normal, linkAvailable: connected, nowS: lastFrameUptime)
            if executor.phase == .alignNode, let target = executor.target, target.isAutomatic != true {
                lastReachedManualID = target.id
            }
            if executor.phase == .arrived { lastReachedManualID = executor.target?.id }
            if !executor.active { isArmed = false }
        }
        let index = executor.waypointIndex + 1
        if session.localised, drawnIndex != index {
            drawnIndex = index
            ARMapDrawing.draw(points: displayPoints, in: routeLayer,
                              session: session, activeIndex: index)
        }
        guard time - lastUiTime > 0.10 else { return }
        lastUiTime = time
        robotPose = pose
        isLocalised = session.localised
        readyToStart = connected && normal && (followMode ? followDriver.available : (map.hasCapturedRoute && isLocalised &&
            pose.map { RouteEntryPlanner.canEnter(map: map, from: $0, returningFrom: selectedReturnID) } == true))
        usedMarkers = session.localised ? [map.anchor.id] : []
        if !followMode {
            let total = completedDistanceM > 0 ? completedDistanceM : map.distanceM
            progress = completedDistanceM > 0 && total > 0 ? min(1, max(0, 1 - executor.distanceRemainingM / total)) : 0
            if executor.phase == .arrived { progress = 1 }
            guidanceText = executor.message
            if executor.phase != .idle {
                stateText = executor.message
            } else if !session.localised || !normal { stateText = session.message }
            else if !map.hasCapturedRoute { stateText = "旧地图未保存轨迹，请重新采集以生成子节点航线。" }
            else if let pose = pose {
                let start = returnMode ? returnNodes.first(where: { $0.id == returnNodeID }) ?? map.executionStart : map.executionStart
                stateText = String(format: "已定位，距%@ %.2f m。", start.name, pose.distanceTo(start.pose)) + (readyToStart ? "可从当前位置接入路线，保持手机固定。" : "请将车移到此节点附近的对应带状范围内；无需改变手机俯仰。")
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
        logNavigation(pose)
    }

    private func healthCheck() {
        guard isArmed, !followMode else { return }
        if ProcessInfo.processInfo.systemUptime - lastFrameUptime > 0.6 {
            executor.tick(pose: nil, trackingNormal: false,
                          linkAvailable: !requiresConnection || link.telemetry.connected)
            isArmed = executor.active
            stateText = executor.message; guidanceText = executor.message
            logNavigation(nil)
        }
    }

    private func returnImage(marker: Pose2D, timestamp: Double, floorY: Float) {
        guard isArmed, returnMode, !followMode, executor.isReturnTerminal,
              let current = try? session.capturePose(), current.distanceTo(map.executionStart.pose) <= 0.35 else { return }
        if executor.canVerifyReturnImage {
            returnImageStability.reset()
            executor.beginReturnImageVerification(nowS: ProcessInfo.processInfo.systemUptime)
            return // Confirmation must use frames captured after motion stops.
        }
        guard executor.phase == .verifyingImage,
              let stable = returnImageStability.observe(marker, timestampS: timestamp) else { return }
        do {
            let before = current
            let corrected = try session.applyReturnImageAlignment(marker: stable, floorY: floorY)
            executor.acceptReturnImagePose(corrected, nowS: ProcessInfo.processInfo.systemUptime)
            returnImageStability.reset(); drawnIndex = nil
            isArmed = executor.active
            diagnostics.record(["event": "returnImageCorrection", "before": [before.x, before.y, before.yawDeg],
                "corrected": [corrected.x, corrected.y, corrected.yawDeg], "count": executor.imageCorrectionCount,
                "positionError": corrected.distanceTo(map.executionStart.pose), "reason": executor.message])
        } catch {
            executor.stop(reason: error.localizedDescription); isArmed = false
            stateText = error.localizedDescription
        }
    }

    private func logNavigation(_ pose: Pose2D?) {
        guard !followMode else { return }
        let now = ProcessInfo.processInfo.systemUptime
        guard executor.phase != lastLoggedPhase || now - lastLogUptime >= 1 else { return }
        lastLogUptime = now; lastLoggedPhase = executor.phase
        var fields: [String: Any] = ["event": "state", "returning": returnMode, "phase": executor.phase.rawValue,
            "target": executor.waypointIndex, "reason": executor.message, "headingError": executor.headingErrorDeg,
            "distance": executor.distanceToTargetM, "recoveries": executor.recoveryCount,
            "turn": executor.turnDiagnostics, "drivePwm": pwm.drivePwm,
            "leftTurnPwm": pwm.leftTurnPwm, "rightTurnPwm": pwm.rightTurnPwm]
        if let ble = link as? OpenBotBleLink {
            fields["bleSubmitted"] = ble.lastControlFrame ?? "none"
            fields["bleError"] = ble.lastWriteError ?? "none"
        }
        if let pose = pose { fields["pose"] = ["x": pose.x, "y": pose.y, "yaw": pose.yawDeg] }
        diagnostics.record(fields)
    }

}
