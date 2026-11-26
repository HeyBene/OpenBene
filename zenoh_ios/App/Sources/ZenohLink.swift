import ARKit
import AVFoundation
import Foundation
import OpenBeneRobot
import OpenBeneZenoh
import OpenBeneZenohPico

/// Owns the Zenoh session, the capture source and the OpenBot BLE link.
@MainActor
final class ZenohLink: ObservableObject {
    private static let endpointKey = "openbene.zenoh.endpoint"
    private static let robotKey = "openbene.zenoh.robot"

    @Published var endpoint: String {
        didSet { UserDefaults.standard.set(endpoint, forKey: Self.endpointKey) }
    }
    @Published var robotID: String {
        didSet { UserDefaults.standard.set(robotID, forKey: Self.robotKey) }
    }
    @Published var useARKit = true
    @Published var settings: CaptureSettings {
        didSet {
            settings.save()
            guard settings != oldValue else { return }
            applySettingsChange()
        }
    }

    @Published private(set) var connected = false
    @Published private(set) var statusText = "未连接"
    @Published private(set) var framesSent: UInt64 = 0
    @Published private(set) var framesDropped: UInt64 = 0
    @Published private(set) var megabytes: Double = 0
    @Published private(set) var lastCommand = "—"
    @Published private(set) var captureDetail = "—"
    @Published private(set) var linkError: String?
    @Published private(set) var captureFPS: Double = 0
    @Published private(set) var encodeMs: Double = 0
    @Published private(set) var planeMs: [String: Double] = [:]
    /// ARKit's raw frame delivery rate, useful when the source is slower than
    /// the requested rate.
    @Published private(set) var sourceFPS: Double = 0
    /// Startup timing probe; a Debug build shows much larger numbers here.
    @Published private(set) var encoderBench = "检测中…"

    let robot = OpenBotLink()
    lazy var drive = DriveController(link: robot)

    private var transport: OpenBeneTransport?
    private var capture: ARCaptureController?
    private var synthetic: SyntheticCapture?
    private var statsTimer: Timer?
    private var telemetryTimer: Timer?
    private let motion = MotionSampler()
    private var lastBytes: UInt64 = 0
    private var lastStatsAt = Date()

    init() {
        let arguments = ProcessInfo.processInfo.arguments
        func value(after flag: String) -> String? {
            guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else {
                return nil
            }
            return arguments[index + 1]
        }
        // `devicectl ... --endpoint 10.0.0.5:7447 --auto-connect` lets a test
        // run connect without tapping the screen.
        endpoint = value(after: "--endpoint")
            ?? UserDefaults.standard.string(forKey: Self.endpointKey) ?? ""
        robotID = value(after: "--robot")
            ?? UserDefaults.standard.string(forKey: Self.robotKey) ?? "rtr520"
        settings = CaptureSettings.load()
        if let fps = value(after: "--fps").flatMap(Double.init) {
            settings.fps = fps
        }
        motion.onSample = { [weak self] acceleration, rotation in
            Task { @MainActor in
                self?.pendingAcceleration = acceleration
                self?.pendingRotation = rotation
            }
        }
    }

    func connectIfRequested() {
        if ProcessInfo.processInfo.arguments.contains("--auto-connect") {
            connect()
        }
    }

    /// Console diagnostics for headless test runs (`--log-stats`).
    private func logStatsIfRequested() {
        guard ProcessInfo.processInfo.arguments.contains("--log-stats"), let transport else {
            return
        }
        let stats = transport.statistics()
        let queue = transport.queueSnapshot
        print(String(
            format: "STATS target %.0f source %.1f capture %.1f encode %.1fms sent %llu dropped %llu "
                + "pending %d errors %llu jpeg %.1f depth %.1f conf %.1f conv %.1f",
            settings.fps, sourceFPS, captureFPS, encodeMs, stats.framesSent, stats.framesDropped,
            queue.pending, stats.publishErrors,
            planeMs["rgb"] ?? 0, planeMs["depth"] ?? 0,
            planeMs["confidence"] ?? 0, planeMs["convert"] ?? 0
        ))
    }

    func runEncoderSelfCheck() {
        CaptureSelfCheck.run { [weak self] summary in
            Task { @MainActor in self?.encoderBench = summary }
        }
    }

    private var pendingAcceleration: Vector3Sample?
    private var pendingRotation: Vector3Sample?

    func connect() {
        guard !connected else { return }
        let trimmed = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            linkError = "请先填写电脑的 Zenoh 地址，例如 192.168.1.23:7447"
            return
        }

        linkError = nil
        let config = ZenohTransportConfig(robotID: robotID, endpoint: trimmed)
        let session = PicoZenohSession(endpoint: config.endpoint, mode: .client)
        let transport = OpenBeneTransport(config: config, session: session)
        transport.onCommand = { [weak self] command in
            Task { @MainActor in self?.handleRemoteCommand(command) }
        }

        do {
            try transport.start()
        } catch {
            linkError = "连接失败：\(error.localizedDescription)"
            statusText = "未连接"
            return
        }
        self.transport = transport
        connected = true
        statusText = "已连接 \(config.endpoint)（zenoh-pico \(PicoZenohSession.zenohVersion)）"
        startCapture(on: transport)
        startStats()
        startTelemetry()
        if settings.includeIMU { motion.start() }
    }

    func disconnect() {
        stopCapture()
        statsTimer?.invalidate()
        statsTimer = nil
        telemetryTimer?.invalidate()
        telemetryTimer = nil
        motion.stop()
        transport?.stop()
        transport = nil
        connected = false
        statusText = "未连接"
        captureDetail = "—"
        captureFPS = 0
        encodeMs = 0
        planeMs = [:]
        sourceFPS = 0
    }

    private func startCapture(on transport: OpenBeneTransport) {
        stopCapture()
        if useARKit, ARWorldTrackingConfiguration.isSupported {
            let controller = ARCaptureController(
                settings: settings,
                onFrame: { frame in transport.publish(frame: frame) },
                onStatus: { [weak self] detail in
                    Task { @MainActor in self?.captureDetail = detail }
                },
                onStats: { [weak self] stats in
                    Task { @MainActor in
                        self?.captureFPS = stats.measuredFPS
                        self?.encodeMs = stats.averageEncodeMs
                        self?.planeMs = [
                            "rgb": stats.rgbMs,
                            "depth": stats.depthMs,
                            "confidence": stats.confidenceMs,
                            "convert": stats.pixelConversionMs,
                        ]
                        self?.sourceFPS = stats.delegateFPS
                    }
                }
            )
            capture = controller
            controller.start()
            checkCameraPermission()
        } else {
            let generator = SyntheticCapture(
                settings: settings,
                onFrame: { frame in transport.publish(frame: frame) },
                onStats: { [weak self] elapsed in
                    Task { @MainActor in
                        self?.captureFPS = self?.settings.fps ?? 0
                        self?.encodeMs = elapsed
                    }
                }
            )
            synthetic = generator
            generator.start()
            captureDetail = "合成测试帧 640×480 @\(Int(settings.fps))fps"
        }
    }

    /// Settings changed: restart capture for the new rate/planes and toggle IMU.
    private func applySettingsChange() {
        if settings.includeIMU {
            if connected { motion.start() }
        } else {
            motion.stop()
        }
        guard connected, let transport else { return }
        startCapture(on: transport)
    }

    private func checkCameraPermission() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .denied, .restricted:
            captureDetail = "相机权限被拒绝，请到设置里允许，或切换合成测试帧"
        default:
            break
        }
    }

    private func stopCapture() {
        capture?.stop()
        capture = nil
        synthetic?.stop()
        synthetic = nil
    }

    private func startStats() {
        lastBytes = 0
        lastStatsAt = Date()
        statsTimer?.invalidate()
        statsTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshStats() }
        }
    }

    /// Periodic chassis telemetry so the PC sees the same drive state the app
    /// controls, including robot-side voltage and wheel RPM.
    private func startTelemetry() {
        telemetryTimer?.invalidate()
        telemetryTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.publishTelemetry() }
        }
    }

    private func publishTelemetry() {
        guard let transport, connected else { return }
        if settings.includeIMU {
            let acceleration = pendingAcceleration
            let rotation = pendingRotation
            pendingAcceleration = nil
            pendingRotation = nil
            if acceleration != nil || rotation != nil {
                transport.publish(
                    sensors: SensorSamples(
                        accelerometer: acceleration,
                        gyroscope: rotation,
                        batteryLevel: nil,
                        timestampMs: Int64(Date().timeIntervalSince1970 * 1000)
                    )
                )
            }
        }
        transport.publish(
            telemetry: TelemetryMessage(
                voltage: robot.voltage ?? 0,
                leftRPM: robot.leftRPM ?? 0,
                rightRPM: robot.rightRPM ?? 0,
                sonarCm: robot.sonarCm,
                timestampMs: Int64(Date().timeIntervalSince1970 * 1000)
            )
        )
    }

    private func refreshStats() {
        guard let transport else { return }
        logStatsIfRequested()
        let stats = transport.statistics()
        framesSent = stats.framesSent
        framesDropped = stats.framesDropped
        let now = Date()
        let elapsed = max(0.001, now.timeIntervalSince(lastStatsAt))
        let delta = Double(stats.bytesSent &- min(stats.bytesSent, lastBytes))
        megabytes = delta / elapsed / 1_000_000
        lastBytes = stats.bytesSent
        lastStatsAt = now
    }

    /// Commands arriving from the PC drive the same BLE path as the keyboard.
    private func handleRemoteCommand(_ command: RobotCommand) {
        switch command {
        case .drive(let left, let right, let sequence, _, _):
            lastCommand = String(format: "drive %.2f / %.2f  #%lld", left, right, sequence)
            drive.applyRemote(left: left, right: right)

        case .stop(let sequence, _):
            lastCommand = "stop #\(sequence)"
            drive.releaseAll()

        case .unknown(let reason):
            lastCommand = "无法解析：\(reason)"
        }
    }

}
