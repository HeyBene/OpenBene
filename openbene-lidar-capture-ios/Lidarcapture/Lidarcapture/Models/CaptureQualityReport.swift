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

enum CaptureQualityGateDecision {
    case keep
    case retry
    case reject

    var title: String {
        switch self {
        case .keep:
            return "建议保留"
        case .retry:
            return "建议补采"
        case .reject:
            return "建议重采"
        }
    }

    var actionHint: String {
        switch self {
        case .keep:
            return "可进入上传/建图下游"
        case .retry:
            return "可保留参考，但建议补更多覆盖"
        case .reject:
            return "不建议直接进入下游"
        }
    }
}

struct CaptureQualityReport {
    let acceptedFrameCount: Int
    let trackingNormalRatio: Float
    let maxAdjacentTranslationJumpMeters: Float
    let maxAdjacentRotationJumpDegrees: Float
    let suspiciousJumpCount: Int
    let severeJumpCount: Int
    let gateDecision: CaptureQualityGateDecision
    let recommendation: String
}
