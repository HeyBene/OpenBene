import Foundation

/// A measured phone pose in the fixed anchor/map frame.
public struct TrajectorySample: Codable, Equatable {
    public let pose: Pose2D
    public let timestampS: Double
    public let startsSegment: Bool
    public init(pose: Pose2D, timestampS: Double, startsSegment: Bool) {
        self.pose = pose; self.timestampS = timestampS; self.startsSegment = startsSegment
    }
}

/// A full 30 Hz archive plus a bounded display window. Tracking gaps remain
/// explicit; missing motion is never filled with a straight segment.
public struct CaptureTrajectory {
    public private(set) var samples: [TrajectorySample] = []
    public private(set) var recordedSamples: [TrajectorySample] = []
    public private(set) var capacityReached = false
    public private(set) var distanceM = 0.0
    public private(set) var prunedSampleCount = 0
    public private(set) var started = false
    public let maxSamples: Int
    private let sampleIntervalS: Double
    private let minimumDistanceM: Double
    private let maximumFrameGapS: Double
    private var lastObservedTimeS: Double?
    private var segmentPending = false
    private var nextSampleTimeS = 0.0

    public init(maxSamples: Int = 5_000, sampleIntervalS: Double = 1.0 / 30.0,
                minimumDistanceM: Double = 0, maximumFrameGapS: Double = 0.6) {
        precondition(maxSamples >= 2 && sampleIntervalS.isFinite && sampleIntervalS > 0 &&
                     minimumDistanceM.isFinite && minimumDistanceM >= 0 &&
                     maximumFrameGapS.isFinite && maximumFrameGapS >= sampleIntervalS)
        self.maxSamples = maxSamples
        self.sampleIntervalS = sampleIntervalS
        self.minimumDistanceM = minimumDistanceM
        self.maximumFrameGapS = maximumFrameGapS
    }

    public mutating func reset() {
        samples.removeAll(keepingCapacity: true)
        recordedSamples.removeAll(keepingCapacity: true)
        capacityReached = false
        distanceM = 0
        prunedSampleCount = 0
        started = false
        lastObservedTimeS = nil
        segmentPending = false
    }

    @discardableResult
    public mutating func begin(pose: Pose2D, timestampS: Double) -> Bool {
        reset()
        guard valid(pose), timestampS.isFinite else { return false }
        started = true
        lastObservedTimeS = timestampS
        nextSampleTimeS = timestampS + sampleIntervalS
        let sample = TrajectorySample(pose: pose, timestampS: timestampS, startsSegment: true)
        samples.append(sample); recordedSamples.append(sample)
        return true
    }

    /// Stop connecting points across tracking loss, camera stalls or interruption.
    public mutating func breakSegment() { if started { segmentPending = true } }

    @discardableResult
    public mutating func observe(pose: Pose2D?, trackingNormal: Bool, timestampS: Double) -> Bool {
        append(pose: pose, trackingNormal: trackingNormal, timestampS: timestampS, force: false)
    }

    /// Pin the exact AR frame used by a user waypoint, even between 30 Hz samples.
    public mutating func pin(pose: Pose2D, timestampS: Double) throws -> Int {
        guard started, !capacityReached else { throw RecordingError.invalid("轨迹尚未开始或已达到30分钟上限，请保存现有地图。") }
        if let last = recordedSamples.last, last.timestampS == timestampS && last.pose == pose {
            return recordedSamples.count - 1
        }
        guard append(pose: pose, trackingNormal: true, timestampS: timestampS, force: true) else {
            throw RecordingError.invalid("无法将节点关联到有效相机轨迹，请等待稳定跟踪。")
        }
        return recordedSamples.count - 1
    }

    private mutating func append(pose: Pose2D?, trackingNormal: Bool, timestampS: Double, force: Bool) -> Bool {
        guard started else { return false }
        guard recordedSamples.count < 54_000 else { capacityReached = true; return false }
        guard trackingNormal, let pose = pose, valid(pose), timestampS.isFinite else {
            breakSegment()
            return false
        }
        if let previousTime = lastObservedTimeS {
            // Duplicate frames are harmless; backwards time invalidates continuity.
            if timestampS == previousTime && !force { return false }
            if timestampS < previousTime { breakSegment(); return false }
            if timestampS - previousTime > maximumFrameGapS { breakSegment() }
        }
        lastObservedTimeS = timestampS
        guard let previous = samples.last else { return false }
        let startsSegment = segmentPending
        if !startsSegment && !force {
            guard timestampS >= nextSampleTimeS - 1e-9,
                  previous.pose.distanceTo(pose) >= minimumDistanceM else { return false }
        }
        if startsSegment || force {
            nextSampleTimeS = timestampS + sampleIntervalS
        } else {
            let intervals = max(1, floor((timestampS - nextSampleTimeS + 1e-9) / sampleIntervalS) + 1)
            nextSampleTimeS += intervals * sampleIntervalS
        }
        if !startsSegment { distanceM += previous.pose.distanceTo(pose) }
        let sample = TrajectorySample(pose: pose, timestampS: timestampS, startsSegment: startsSegment)
        samples.append(sample); recordedSamples.append(sample)
        segmentPending = false
        if samples.count > maxSamples {
            // Evict a block so both the sampler and renderer avoid work per frame.
            let count = max(1, min(128, maxSamples / 4))
            samples.removeFirst(count)
            prunedSampleCount += count
        }
        return true
    }

    private func valid(_ pose: Pose2D) -> Bool {
        pose.x.isFinite && pose.y.isFinite && pose.yawRad.isFinite
    }
}
