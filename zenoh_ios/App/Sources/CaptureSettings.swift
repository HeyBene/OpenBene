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
