import Foundation

public struct PersonDetection {
    public let box: PersonBox
    public let confidence: Double
    public let distanceM: Double?
    public init(box: PersonBox, confidence: Double, distanceM: Double? = nil) {
        self.box = box; self.confidence = confidence; self.distanceM = distanceM
    }
}

/// Optional experiments start OFF; the primary near-person stop starts ON.
public struct FollowTestOptions: Equatable, Codable {
    public var confidenceFilter = false
    public var requireSinglePerson = false
    public var requireStableTarget = false
    public var rejectEdgeBoxes = false
    public var rejectTargetJump = false
    public var strictDetectionTimeout = false
    public var pulseTurns = false
    public var pauseBeforeReversal = false
    public var stopWhenNear = true
    public var stopDistanceM = 1.0
    public init() {}
    public var enabledNames: [String] {
        [(confidenceFilter, "置信度"), (requireSinglePerson, "单人"), (requireStableTarget, "3帧"),
         (rejectEdgeBoxes, "四边"), (rejectTargetJump, "跳变"), (strictDetectionTimeout, "0.35秒"),
         (pulseTurns, "转向脉冲"), (pauseBeforeReversal, "反向等待"), (stopWhenNear, "距离停车")]
            .filter { $0.0 }.map { $0.1 }
    }
    public var valid: Bool { stopDistanceM.isFinite && (0.5...2.0).contains(stopDistanceM) }
}
