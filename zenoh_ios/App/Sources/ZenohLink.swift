import ARKit
import Foundation
import OpenBeneZenoh
import OpenBeneZenohPico

/// Owns the Zenoh session and the capture source for the demo app.
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

    @Published private(set) var connected = false
    @Published private(set) var statusText = "未连接"
    @Published private(set) var framesSent: UInt64 = 0
    @Published private(set) var framesDropped: UInt64 = 0
    @Published private(set) var megabytes: Double = 0
    @Published private(set) var lastCommand = "—"
    @Published private(set) var captureDetail = "—"
    @Published private(set) var linkError: String?

    private var transport: OpenBeneTransport?
    private var capture: ARCaptureController?
    private var synthetic: SyntheticCapture?
    private var statsTimer: Timer?
    private var lastBytes: UInt64 = 0
    private var lastStatsAt = Date()

    init() {
        endpoint = UserDefaults.standard.string(forKey: Self.endpointKey) ?? ""
        robotID = UserDefaults.standard.string(forKey: Self.robotKey) ?? "rtr520"
    }

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
            Task { @MainActor in self?.record(command: command) }
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
    }

    func disconnect() {
        stopCapture()
        statsTimer?.invalidate()
        statsTimer = nil
        transport?.stop()
        transport = nil
        connected = false
        statusText = "未连接"
        captureDetail = "—"
    }

    private func startCapture(on transport: OpenBeneTransport) {
        stopCapture()
        if useARKit, ARWorldTrackingConfiguration.isSupported {
            let controller = ARCaptureController(
                onFrame: { frame in transport.publish(frame: frame) },
                onStatus: { [weak self] detail in
                    Task { @MainActor in self?.captureDetail = detail }
                }
            )
            capture = controller
            controller.start()
        } else {
            let generator = SyntheticCapture(
                onFrame: { frame in transport.publish(frame: frame) }
            )
            synthetic = generator
            generator.start()
            captureDetail = "合成测试帧 640×480 @5fps"
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

    private func refreshStats() {
        guard let transport else { return }
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

    private func record(command: RobotCommand) {
        switch command {
        case .drive(let left, let right, let sequence, _, _):
            lastCommand = String(format: "drive %.2f / %.2f  #%lld", left, right, sequence)
        case .stop(let sequence, _):
            lastCommand = "stop #\(sequence)"
        case .unknown(let reason):
            lastCommand = "无法解析：\(reason)"
        }
    }
}
