import ARKit
import Combine
import Vision
import OpenBotNavKit

/// Shared camera detector and motion owner for navigation-follow and capture.
/// A selected BLE link is required; creating the driver never starts following.
final class PersonFollowDriver: ObservableObject {
    @Published private(set) var status = "识别后确认出发位置，再开始跟随。"
    @Published private(set) var active = false
    @Published private(set) var connected = false
    @Published private(set) var pending = false
    @Published private(set) var available = false
    @Published private(set) var frameText = "c0,0"
    @Published private(set) var scaleText = "等待人体深度距离。"
    @Published private(set) var detectionText = "等待人体检测帧。"
    @Published private(set) var targetText = "尚无检测结果"
    @Published private(set) var testOptions = FollowTestOptions()
    @Published private(set) var overlayBox: PersonBox?
    @Published private(set) var gateText = "门槛全部关闭"
    @Published private(set) var bleText = "尚未提交控车帧"
    @Published private(set) var pwm: NavigationPwmSettings
    private let link: RobotLink?
    private let engine: FollowExecutor
    private let queue = DispatchQueue(label: "com.openbene.person-follow", qos: .userInitiated)
    private var timer: Timer?
    private var enabled = false
    private var busy = false
    private var generation = 0
    private var lastScanS = -Double.infinity
    private var lastFrameS = 0.0
    private var lastFrameWallS = -Double.infinity
    private var trackingReady = false
    private var lastMotionWallS = -Double.infinity
    private let diagnostics = FollowDiagnostics()
    private let detector = YoloPersonDetector()
    private var lastLogS = -Double.infinity
    private var detectorDetails: [String: Any] = [:]
    private static let stopEnabledKey = "follow.rangeStop.v1.enabled"
    private static let stopMarginKey = "follow.rangeStop.v1.distanceM"
    private let rangeSupported = ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth)
    var hasRobot: Bool { link != nil }
    var needsStationaryPause: Bool { active || ProcessInfo.processInfo.systemUptime - lastMotionWallS < 2 }

    init(link: RobotLink?, pwm: NavigationPwmSettings) {
        self.link = link; self.pwm = pwm
        engine = FollowExecutor(link: link ?? MockRobotLink(), pwm: pwm)
        var options = FollowTestOptions()
        let settings = UserDefaults.standard
        if settings.object(forKey: Self.stopEnabledKey) != nil { options.stopWhenNear = settings.bool(forKey: Self.stopEnabledKey) }
        if settings.object(forKey: Self.stopMarginKey) != nil {
            let margin = settings.double(forKey: Self.stopMarginKey)
            if margin.isFinite, (0.5...2.0).contains(margin) { options.stopDistanceM = margin }
        }
        testOptions = options; engine.applyOptions(options)
        diagnostics.record(["event": "created", "hasRobot": link != nil, "detector": YoloPersonDetector.modelName,
                            "distanceHold": options.stopWhenNear, "enabledGates": options.enabledNames,
                            "stopDistanceM": options.stopDistanceM, "rangeSupported": rangeSupported])
    }
    deinit { timer?.invalidate() }

    func setEnabled(_ requested: Bool) {
        // Manual capture without a selected robot need not run Vision at all.
        let value = requested && link != nil
        diagnostics.record(["event": "enable", "requested": requested, "enabled": value])
        guard value != enabled else { publish(); return }
        generation += 1; enabled = value; lastScanS = -Double.infinity
        engine.clearTarget()
        timer?.invalidate(); timer = nil
        if value {
            let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in self?.watchdog() }
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        }
        publish()
    }

    func observeFrame(trackingNormal: Bool, timestampS: Double) {
        lastFrameS = timestampS
        lastFrameWallS = ProcessInfo.processInfo.systemUptime
        trackingReady = trackingNormal
        guard enabled else { return }
        engine.tick(nowS: timestampS, trackingNormal: trackingNormal, linkAvailable: link?.telemetry.connected == true)
        publish()
    }

    func scan(_ frame: ARFrame, viewportSize: CGSize) {
        guard enabled, !busy, frame.timestamp - lastScanS >= 1.0 / 15 else { return }
        busy = true; lastScanS = frame.timestamp
        let image = frame.capturedImage, time = frame.timestamp, token = generation
        guard viewportSize.width > 0, viewportSize.height > 0 else { busy = false; return }
        let transform = frame.displayTransform(for: .portrait, viewportSize: viewportSize)
        let depth = frame.sceneDepth?.depthMap, confidence = frame.sceneDepth?.confidenceMap
        let k = frame.camera.intrinsics, resolution = frame.camera.imageResolution
        let intrinsics = NormalizedCameraIntrinsics(fx: Double(k.columns.0.x) / Double(resolution.width),
            fy: Double(k.columns.1.y) / Double(resolution.height), cx: Double(k.columns.2.x) / Double(resolution.width),
            cy: Double(k.columns.2.y) / Double(resolution.height))
        let matrix = frame.camera.transform
        let camera = RigidTransform(columnMajor4x4: [matrix.columns.0, matrix.columns.1, matrix.columns.2, matrix.columns.3]
            .flatMap { [Double($0.x), Double($0.y), Double($0.z), Double($0.w)] })
        let detector = detector
        queue.async { [weak self] in
            let (boxes, resultDetails) = Self.detect(image, timestampS: time, displayTransform: transform,
                detector: detector, depth: depth, confidence: confidence, intrinsics: intrinsics, camera: camera)
            DispatchQueue.main.async { [weak self] in
                self?.receive(boxes, details: resultDetails, time: time, token: token)
            }
        }
    }

    private static func detect(_ image: CVPixelBuffer, timestampS time: Double,
                               displayTransform: CGAffineTransform, detector: YoloPersonDetector,
                               depth: CVPixelBuffer?, confidence: CVPixelBuffer?,
                               intrinsics: NormalizedCameraIntrinsics, camera: RigidTransform) -> ([PersonDetection], [String: Any]) {
        let boxes: [PersonDetection]
        var details: [String: Any] = ["frameTime": time, "depthAvailable": depth != nil, "depthConfidenceAvailable": confidence != nil]
        let began = ProcessInfo.processInfo.systemUptime
        do {
            let observations = try detector.detect(image)
            let raw: [[String: Double]] = observations.map { ["confidence": Double($0.labels.first?.confidence ?? 0),
                "x": Double($0.boundingBox.minX), "y": Double($0.boundingBox.minY),
                "width": Double($0.boundingBox.width), "height": Double($0.boundingBox.height)] }
            details["raw"] = raw
            boxes = observations.compactMap {
                // Vision .right -> upright portrait; undo that rotation, then
                // apply ARKit's actual viewport crop/rotation for the overlay
                // and steering. Depth sampling stays in native image space.
                let upright = CGRect(x: $0.boundingBox.minX, y: 1 - $0.boundingBox.maxY,
                                     width: $0.boundingBox.width, height: $0.boundingBox.height)
                let raw = CGRect(x: upright.minY, y: 1 - upright.maxX, width: upright.height, height: upright.width)
                let visible = raw.applying(displayTransform).intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
                guard !visible.isNull, visible.width > 0, visible.height > 0 else { return nil }
                let distance = depth.flatMap { PersonDepthSampler.distance(depthMap: $0, confidenceMap: confidence,
                    uprightBox: PersonBox(centreX: Double(upright.midX), centreY: Double(upright.midY),
                        width: Double(upright.width), height: Double(upright.height)),
                    intrinsics: intrinsics, cameraInAr: camera) }
                return PersonDetection(box: PersonBox(centreX: Double(visible.midX), centreY: Double(visible.midY),
                                 width: Double(visible.width), height: Double(visible.height)),
                    confidence: Double($0.labels.first?.confidence ?? 0), distanceM: distance)
            }
        } catch { boxes = []; details["error"] = error.localizedDescription }
        details["detectionRangesM"] = boxes.map { item -> Any in
            if let distance = item.distanceM { return distance }
            return NSNull()
        }
        details["processingMs"] = (ProcessInfo.processInfo.systemUptime - began) * 1000
        return (boxes, details)
    }

    private func receive(_ boxes: [PersonDetection], details: [String: Any], time: Double, token: Int) {
        busy = false
        guard enabled, generation == token else { return }
        detectorDetails = details
        let ageMs = max(0, predictedFrameTime - time) * 1000
        detectorDetails["resultAgeMs"] = ageMs
        let rawCount = (details["raw"] as? [[String: Double]])?.count ?? 0
        if let error = details["error"] as? String { detectionText = "检测错误：" + error }
        else {
            let count = boxes.filter { !testOptions.confidenceFilter || $0.confidence >= 0.6 }.count
            detectionText = String(format: "%@ %d框 · 筛选后%d框 · %.0fms · 帧龄%.0fms", YoloPersonDetector.modelName, rawCount, count,
                                   details["processingMs"] as? Double ?? 0, ageMs)
        }
        engine.observeDetections(boxes, timestampS: time)
        watchdog()
    }

    func startFollowing() {
        diagnostics.record(["event": "startRequested", "available": canRequest, "tracking": trackingReady,
                            "connected": link?.telemetry.connected == true])
        guard canRequest else { stop(reason: "请先确认出发位置、保持相机跟踪并连接底盘。"); return }
        engine.requestStart(nowS: predictedFrameTime)
        publish()
    }

    func applyTestOptions(_ value: FollowTestOptions) {
        generation += 1
        engine.applyOptions(value)
        testOptions = engine.options
        UserDefaults.standard.set(testOptions.stopWhenNear, forKey: Self.stopEnabledKey)
        UserDefaults.standard.set(testOptions.stopDistanceM, forKey: Self.stopMarginKey)
        lastScanS = -Double.infinity
        diagnostics.record(["event": "gatesChanged", "enabledGates": testOptions.enabledNames,
                            "stopDistanceM": testOptions.stopDistanceM])
        publish()
    }

    func applyPwm(_ value: NavigationPwmSettings) {
        generation += 1
        pwm = value; engine.applyPwm(value)
        publish()
    }

    func stop(reason: String = "跟随已停车；再次跟随需手动开始。") {
        if engine.active || engine.pending != nil { diagnostics.record(["event": "stop", "reason": reason]) }
        generation += 1
        engine.stop(reason: reason)
        publish()
    }

    func trackingUnavailable(_ reason: String) {
        engine.pauseForTracking(nowS: predictedFrameTime, reason: reason)
        publish()
    }

    func close() { stop(); setEnabled(false); link?.close() }

    private var predictedFrameTime: Double {
        lastFrameS + max(0, ProcessInfo.processInfo.systemUptime - lastFrameWallS)
    }
    private var canRequest: Bool {
        enabled && trackingReady && ProcessInfo.processInfo.systemUptime - lastFrameWallS <= 0.35 && link?.telemetry.connected == true
    }

    private func watchdog() {
        guard enabled else { return }
        let fresh = ProcessInfo.processInfo.systemUptime - lastFrameWallS <= 0.35
        engine.tick(nowS: predictedFrameTime, trackingNormal: fresh && trackingReady,
                    linkAvailable: link?.telemetry.connected == true)
        publish()
    }

    private func publish() {
        if active != engine.active { active = engine.active }
        let waiting = engine.pending != nil
        if pending != waiting { pending = waiting }
        let isConnected = link?.telemetry.connected == true
        if connected != isConnected { connected = isConnected }
        if available != canRequest { available = canRequest }
        let text = enabled ? engine.status : "先确认支架处出发位置；在首页选择蓝牙底盘后可跟随采集。"
        if status != text { status = text }
        let command = engine.lastCommand
        if command.left != 0 || command.right != 0 { lastMotionWallS = ProcessInfo.processInfo.systemUptime }
        let frame = String(decoding: OpenBotProtocol.ctrlCommand(left: command.left, right: command.right), as: UTF8.self).trimmingCharacters(in: .newlines)
        if frameText != frame { frameText = frame }
        let range = engine.distanceM.map { String(format: "LiDAR水平距离约 %.2f m", $0) }
            ?? (rangeSupported ? "距离未知，等待有效深度" : "本机不支持深度测距，距离停车开启时禁止前进")
        let scale = range + " · \(engine.personCount)个框"
        if scaleText != scale { scaleText = scale }
        if targetText != engine.targetState { targetText = engine.targetState }
        if overlayBox != engine.box { overlayBox = engine.box }
        let gates = testOptions.enabledNames.isEmpty ? "门槛全部关闭" : "已开：" + testOptions.enabledNames.joined(separator: "、")
        let gate = gates + " · " + engine.gateReason
        if gateText != gate { gateText = gate }
        if let ble = link as? OpenBotBleLink {
            let sent = ble.lastControlFrame ?? "尚未提交"
            let sentText = "蓝牙提交：" + sent + (ble.lastWriteError.map { " · " + $0 } ?? "")
            if bleText != sentText { bleText = sentText }
        }
        let now = ProcessInfo.processInfo.systemUptime
        if enabled, now - lastLogS >= 1 {
            lastLogS = now
            var details = detectorDetails
            details["event"] = "state"; details["status"] = engine.status
            details["tracking"] = trackingReady; details["connected"] = isConnected
            details["active"] = engine.active; details["pending"] = engine.pending ?? "none"
            details["targetState"] = engine.targetState
            details["frame"] = frame; details["motionAction"] = engine.lastCommand.action
            details["distanceHold"] = testOptions.stopWhenNear
            details["enabledGates"] = testOptions.enabledNames; details["gateReason"] = engine.gateReason
            details["stopDistanceM"] = testOptions.stopDistanceM; details["rangeSource"] = "ARKit.sceneDepth"
            details["rangeSupported"] = rangeSupported
            if let distance = engine.distanceM { details["distanceM"] = distance }
            if let box = engine.box { details["visibleBox"] = ["x": box.centreX - box.width / 2,
                "top": box.centreY - box.height / 2, "width": box.width, "height": box.height] }
            details["detector"] = YoloPersonDetector.modelName
            details["drivePwm"] = pwm.drivePwm; details["leftTurnPwm"] = pwm.leftTurnPwm; details["rightTurnPwm"] = pwm.rightTurnPwm
            if let ble = link as? OpenBotBleLink {
                details["bleSubmitted"] = ble.lastControlFrame ?? "none"
                details["bleError"] = ble.lastWriteError ?? "none"
            }
            diagnostics.record(details)
        }
    }
}
