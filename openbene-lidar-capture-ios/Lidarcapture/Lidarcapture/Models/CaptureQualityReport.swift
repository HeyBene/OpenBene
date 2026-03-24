import Foundation

enum CaptureAdvisoryLevel {
    case good
    case holdStill
    case trackingUnstable
    case movingTooFast
}

enum PoseJumpSeverity {
    case none
    case suspicious
    case severe
}

struct PoseDeltaMetrics {
    let translationMeters: Float
    let rotationDegrees: Float
    let severity: PoseJumpSeverity
}

struct CaptureQualityReport {
    let acceptedFrameCount: Int
    let trackingNormalRatio: Float
    let maxAdjacentTranslationJumpMeters: Float
    let maxAdjacentRotationJumpDegrees: Float
    let suspiciousJumpCount: Int
    let severeJumpCount: Int
    let recommendation: String
}
