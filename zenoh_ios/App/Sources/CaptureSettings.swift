import CoreMotion
import Foundation
import OpenBeneZenoh

/// What the phone streams. Sent as optional sections of the frame packet, so
/// the PC can tell which planes are intentionally absent.
struct CaptureSettings: Codable, Equatable {
    var fps: Double = 10
    var includeRGB = true
    var includeDepth = true
    var includeConfidence = true
    var includePose = true
    var includeIMU = true
    /// Downscale width for the JPEG; smaller encodes are much cheaper.
    var maxWidth: Double = 1280

    // Decoding older saved settings that lack newer keys must not reset them.
    enum CodingKeys: String, CodingKey {
        case fps, includeRGB, includeDepth, includeConfidence, includePose, includeIMU, maxWidth
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        fps = try container.decodeIfPresent(Double.self, forKey: .fps) ?? 10
        includeRGB = try container.decodeIfPresent(Bool.self, forKey: .includeRGB) ?? true
        includeDepth = try container.decodeIfPresent(Bool.self, forKey: .includeDepth) ?? true
        includeConfidence = try container.decodeIfPresent(Bool.self, forKey: .includeConfidence) ?? true
        includePose = try container.decodeIfPresent(Bool.self, forKey: .includePose) ?? true
        includeIMU = try container.decodeIfPresent(Bool.self, forKey: .includeIMU) ?? true
        maxWidth = try container.decodeIfPresent(Double.self, forKey: .maxWidth) ?? 1280
    }

    var frameInterval: TimeInterval { 1.0 / max(1, min(30, fps)) }

    static let storageKey = "openbene.capture.v1"

    static func load() -> CaptureSettings {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode(CaptureSettings.self, from: data) else {
            return CaptureSettings()
        }
        return decoded
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }
}

/// Publishes IMU samples at a fixed rate while the Zenoh link is up.
final class MotionSampler {
    private let motion = CMMotionManager()
    private let queue = OperationQueue()
    private var running = false
    var onSample: ((Vector3Sample?, Vector3Sample?) -> Void)?

    func start(hertz: Double = 50) {
        guard !running, motion.isDeviceMotionAvailable else { return }
        running = true
        queue.qualityOfService = .userInitiated
        motion.deviceMotionUpdateInterval = 1.0 / hertz
        motion.startDeviceMotionUpdates(to: queue) { [weak self] data, _ in
            guard let self, let data else { return }
            let acceleration = Vector3Sample(
                x: data.userAcceleration.x,
                y: data.userAcceleration.y,
                z: data.userAcceleration.z
            )
            let rotation = Vector3Sample(
                x: data.rotationRate.x,
                y: data.rotationRate.y,
                z: data.rotationRate.z
            )
            self.onSample?(acceleration, rotation)
        }
    }

    func stop() {
        guard running else { return }
        running = false
        motion.stopDeviceMotionUpdates()
    }
}
