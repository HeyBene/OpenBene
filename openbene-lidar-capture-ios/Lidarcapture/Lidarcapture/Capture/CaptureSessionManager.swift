import Foundation
import ARKit
import Combine

enum CaptureWorkflowPhase {
    case unsupported
    case idle
    case preparing
    case ready
    case capturing
    case completed
    case error
}

enum CaptureMode: String, CaseIterable {
    case manual = "Manual"
    case auto = "Auto"
}

struct CaptureSessionSummary {
    let sessionName: String
    let frameCount: Int
    let depthRecorded: Bool
    let duration: TimeInterval
    let qualityReport: CaptureQualityReport

    var qualityHint: String {
        qualityReport.recommendation
    }

    var gateTitle: String {
        qualityReport.gateDecision.title
    }

    var gateHint: String {
        qualityReport.gateDecision.actionHint
    }
}

/// Manages the ARSession lifecycle for LiDAR capture.
final class CaptureSessionManager: NSObject, ObservableObject {

    // MARK: - Published state

    @Published var trackingState: ARCamera.TrackingState = .notAvailable
    @Published var trackingStateDescription: String = "Not Available"
    @Published var isSessionRunning: Bool = false
    @Published var isCapturing: Bool = false
    @Published var frameCount: Int = 0
    @Published var depthAvailable: Bool = false
    @Published var lastSessionSummary: CaptureSessionSummary?
    @Published var lastSessionName: String?
    @Published var lastSessionDirectoryURL: URL?
    @Published var captureDuration: TimeInterval = 0
    @Published var lastErrorMessage: String?
    @Published var captureMode: CaptureMode = .manual
    @Published var lastCaptureFeedback: String = "等待开始"
    @Published var liveAdvisoryText: String = "请先启动会话"
    @Published var liveAdvisoryLevel: CaptureAdvisoryLevel = .holdStill
    @Published var pointCloudUploadStatus: String?

    // MARK: - Internal

    private let session = ARSession()
    var arSession: ARSession { session }

    private var datasetWriter: NerfstudioDatasetWriter?
    private let acceptancePolicy = FrameAcceptancePolicy()
    private let pointCloudAccumulator = LightweightPointCloudAccumulator()
    private var captureStartDate: Date?
    private var captureTimer: Timer?
    private var currentFrame: ARFrame?
    private var totalObservedFrameCount: Int = 0
    private var trackingNormalFrameCount: Int = 0
    private var previousObservedPose: simd_float4x4?
    private var maxAdjacentTranslationJumpMeters: Float = 0
    private var maxAdjacentRotationJumpDegrees: Float = 0
    private var suspiciousJumpCount: Int = 0
    private var severeJumpCount: Int = 0

    var workflowPhase: CaptureWorkflowPhase {
        if !DeviceCapabilities.isARWorldTrackingAvailable {
            return .unsupported
        }
        if lastErrorMessage != nil {
            return .error
        }
        if isCapturing {
            return .capturing
        }
        if isSessionRunning {
            switch trackingState {
            case .normal:
                return .ready
            case .limited, .notAvailable:
                return .preparing
            }
        }
        if lastSessionSummary != nil {
            return .completed
        }
        return .idle
    }

    var statusHeadline: String {
        switch workflowPhase {
        case .unsupported:
            return "设备暂不支持当前采集"
        case .idle:
            return "先启动 AR 会话"
        case .preparing:
            return "正在建立稳定跟踪"
        case .ready:
            return captureMode == .manual ? "可以手动采一张" : "可以开始自动采集"
        case .capturing:
            return captureMode == .manual ? "手动采集进行中" : "自动采集进行中"
        case .completed:
            return "本轮采集已结束"
        case .error:
            return "会话出现问题"
        }
    }

    var statusHint: String {
        switch workflowPhase {
        case .unsupported:
            return "需要支持 AR 世界跟踪的设备"
        case .idle:
            return "先启动 AR 会话，再进入采集"
        case .preparing:
            return "缓慢移动设备，让画面获取更多特征"
        case .ready:
            return captureMode == .manual ? "对准目标后按主按钮采一张" : "主按钮开始自动采集，系统会按质量策略收帧"
        case .capturing:
            return captureMode == .manual ? lastCaptureFeedback : "继续缓慢环绕目标，保持画面稳定"
        case .completed:
            return lastSessionSummary?.qualityHint ?? "请检查本次结果是否满足重建需求"
        case .error:
            return lastErrorMessage ?? "请重启会话后重试"
        }
    }

    var formattedDuration: String {
        let totalSeconds = Int(captureDuration)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    /// Callback invoked for each accepted frame (for upload / dual-write).
    var onFrameAccepted: ((CaptureFrameRecord) -> Void)?

    /// Callback invoked when a capture session starts.
    var onCaptureStarted: ((String, Bool) -> Void)?

    /// Callback invoked when a capture session ends.
    var onCaptureFinished: ((Data?, CaptureSessionPointCloudArtifact?) -> Void)?

    override init() {
        super.init()
        session.delegate = self
        depthAvailable = DeviceCapabilities.isLiDARAvailable
    }

    // MARK: - Session control

    func startSession() {
        let config = ARWorldTrackingConfiguration()
        lastErrorMessage = nil

        // Enable LiDAR depth if available
        if DeviceCapabilities.isLiDARAvailable {
            config.frameSemantics.insert(.sceneDepth)
        }

        session.run(config, options: [.resetTracking, .removeExistingAnchors])
        isSessionRunning = true
    }

    func stopSession() {
        session.pause()
        stopCaptureTimer()
        isSessionRunning = false
        isCapturing = false
        captureDuration = 0
    }

    // MARK: - Capture control

    func startCapture(sessionName: String? = nil) {
        guard isSessionRunning else {
            startSession()
            return
        }

        let name = sessionName ?? "session_\(Int(Date().timeIntervalSince1970))"

        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let sessionURL = documentsURL.appendingPathComponent("captures/\(name)")

        lastSessionDirectoryURL = sessionURL
        datasetWriter = NerfstudioDatasetWriter(outputDirectory: sessionURL, depthAvailable: depthAvailable)
        datasetWriter?.beginSession()

        lastSessionName = name
        lastSessionSummary = nil
        frameCount = 0
        captureDuration = 0
        acceptancePolicy.reset()
        pointCloudAccumulator.reset()
        pointCloudUploadStatus = nil
        resetQualityDiagnostics()
        captureStartDate = Date()
        lastCaptureFeedback = captureMode == .manual ? "对准目标后按主按钮采样" : "自动采集中"
        startCaptureTimer()
        isCapturing = true
        onCaptureStarted?(name, depthAvailable)
    }

    func stopCapture() {
        guard isCapturing else { return }
        isCapturing = false
        stopCaptureTimer()
        let manifestData = datasetWriter?.finalizeSession()
        let pointCloudArtifact = pointCloudAccumulator.makePLYArtifact()
        if let pointCloudArtifact, let sessionURL = lastSessionDirectoryURL {
            let pointCloudURL = sessionURL.appendingPathComponent(pointCloudArtifact.fileName)
            try? pointCloudArtifact.data.write(to: pointCloudURL)
        }
        datasetWriter = nil

        let duration = Date().timeIntervalSince(captureStartDate ?? Date())
        captureDuration = duration
        captureStartDate = nil
        lastCaptureFeedback = "本轮采集已结束"
        if let pointCloudArtifact {
            pointCloudUploadStatus = "已生成 \(pointCloudArtifact.pointCount) 点轻量点云"
        } else {
            pointCloudUploadStatus = "未生成点云"
        }
        onCaptureFinished?(manifestData, pointCloudArtifact)

        if let sessionName = lastSessionName {
            lastSessionSummary = CaptureSessionSummary(
                sessionName: sessionName,
                frameCount: frameCount,
                depthRecorded: depthAvailable,
                duration: duration,
                qualityReport: buildQualityReport()
            )
        }
    }

    func captureCurrentFrame() {
        guard isSessionRunning else {
            startSession()
            lastCaptureFeedback = "会话已启动，等待跟踪稳定"
            return
        }

        if !isCapturing {
            startCapture()
        }

        guard captureMode == .manual else { return }
        guard trackingState == .normal else {
            lastCaptureFeedback = "跟踪还不稳定，先移动设备再采样"
            return
        }
        guard let currentFrame else {
            lastCaptureFeedback = "还没有可用画面，请稍后再试"
            return
        }

        writeFrame(currentFrame)
        lastCaptureFeedback = "已手动采集 \(frameCount) 张"
    }

    func performPrimaryAction() {
        switch workflowPhase {
        case .idle, .unsupported, .error:
            startSession()
        case .preparing, .ready:
            if captureMode == .manual {
                captureCurrentFrame()
            } else {
                startCapture()
            }
        case .capturing:
            if captureMode == .manual {
                captureCurrentFrame()
            } else {
                stopCapture()
            }
        case .completed:
            if captureMode == .manual {
                startSession()
            } else {
                startCapture()
            }
        }
    }

    func finishCaptureSession() {
        if isCapturing {
            stopCapture()
        } else if isSessionRunning {
            stopSession()
        }
    }

    func setCaptureMode(_ mode: CaptureMode) {
        captureMode = mode
        if !isCapturing {
            lastCaptureFeedback = mode == .manual ? "当前为手动采样模式" : "当前为自动采样模式"
        }
    }

    // MARK: - Frame processing (called from ARSessionDelegate)

    private func processFrame(_ frame: ARFrame) {
        currentFrame = frame
        updateDiagnostics(with: frame)

        guard isCapturing else { return }
        guard captureMode == .auto else { return }
        guard acceptancePolicy.shouldAccept(frame: frame) else { return }

        writeFrame(frame)
    }

    private func writeFrame(_ frame: ARFrame) {
        let record = CaptureFrameRecord(frame: frame, index: frameCount, depthAvailable: depthAvailable)
        datasetWriter?.writeFrame(record)
        pointCloudAccumulator.ingest(record)
        onFrameAccepted?(record)
        frameCount += 1
    }

    private func startCaptureTimer() {
        stopCaptureTimer()
        captureTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self, let captureStartDate = self.captureStartDate else { return }
            self.captureDuration = Date().timeIntervalSince(captureStartDate)
        }
    }

    private func resetQualityDiagnostics() {
        totalObservedFrameCount = 0
        trackingNormalFrameCount = 0
        previousObservedPose = nil
        maxAdjacentTranslationJumpMeters = 0
        maxAdjacentRotationJumpDegrees = 0
        suspiciousJumpCount = 0
        severeJumpCount = 0
        liveAdvisoryText = "请先停稳，再开始采集"
        liveAdvisoryLevel = .holdStill
    }

    private func updateDiagnostics(with frame: ARFrame) {
        guard isCapturing else { return }

        totalObservedFrameCount += 1
        let tracking = frame.camera.trackingState
        if tracking == .normal {
            trackingNormalFrameCount += 1
        }

        guard let previousObservedPose else {
            self.previousObservedPose = frame.camera.transform
            updateLiveAdvisory(for: tracking, deltaMetrics: nil)
            return
        }

        let delta = Self.poseDeltaMetrics(from: previousObservedPose, to: frame.camera.transform)
        maxAdjacentTranslationJumpMeters = max(maxAdjacentTranslationJumpMeters, delta.translationMeters)
        maxAdjacentRotationJumpDegrees = max(maxAdjacentRotationJumpDegrees, delta.rotationDegrees)

        switch delta.severity {
        case .suspicious:
            suspiciousJumpCount += 1
        case .severe:
            severeJumpCount += 1
        case .none:
            break
        }

        self.previousObservedPose = frame.camera.transform
        updateLiveAdvisory(for: tracking, deltaMetrics: delta)
    }

    private func updateLiveAdvisory(for tracking: ARCamera.TrackingState, deltaMetrics: PoseDeltaMetrics?) {
        guard tracking == .normal else {
            liveAdvisoryText = "跟踪不稳定"
            liveAdvisoryLevel = .trackingUnstable
            return
        }

        if let deltaMetrics {
            switch deltaMetrics.severity {
            case .severe:
                liveAdvisoryText = "移动过快"
                liveAdvisoryLevel = .movingTooFast
                return
            case .suspicious:
                liveAdvisoryText = "请停稳"
                liveAdvisoryLevel = .holdStill
                return
            case .none:
                if deltaMetrics.translationMeters < 0.01 && deltaMetrics.rotationDegrees < 2 {
                    liveAdvisoryText = "请停稳"
                    liveAdvisoryLevel = .holdStill
                    return
                }
            }
        }

        liveAdvisoryText = "可采样"
        liveAdvisoryLevel = .good
    }

    private func buildQualityReport() -> CaptureQualityReport {
        let trackingNormalRatio = totalObservedFrameCount > 0
            ? Float(trackingNormalFrameCount) / Float(totalObservedFrameCount)
            : 0

        let gateDecision: CaptureQualityGateDecision
        let recommendation: String
        if frameCount < 20 {
            gateDecision = .retry
            recommendation = "建议补采：有效帧偏少"
        } else if trackingNormalRatio < 0.7 {
            gateDecision = .reject
            recommendation = "建议重采：跟踪稳定性不足"
        } else if severeJumpCount >= 3 {
            gateDecision = .reject
            recommendation = "建议重采：存在明显位姿跳变"
        } else if suspiciousJumpCount >= 8 {
            gateDecision = .retry
            recommendation = "建议谨慎使用：运动不够平稳"
        } else {
            gateDecision = .keep
            recommendation = "可用于基础重建验证"
        }

        return CaptureQualityReport(
            acceptedFrameCount: frameCount,
            trackingNormalRatio: trackingNormalRatio,
            maxAdjacentTranslationJumpMeters: maxAdjacentTranslationJumpMeters,
            maxAdjacentRotationJumpDegrees: maxAdjacentRotationJumpDegrees,
            suspiciousJumpCount: suspiciousJumpCount,
            severeJumpCount: severeJumpCount,
            gateDecision: gateDecision,
            recommendation: recommendation
        )
    }

    private static func poseDeltaMetrics(from previousPose: simd_float4x4, to currentPose: simd_float4x4) -> PoseDeltaMetrics {
        let previousPosition = SIMD3<Float>(previousPose.columns.3.x, previousPose.columns.3.y, previousPose.columns.3.z)
        let currentPosition = SIMD3<Float>(currentPose.columns.3.x, currentPose.columns.3.y, currentPose.columns.3.z)
        let translationMeters = simd_length(currentPosition - previousPosition)

        let previousRotation = simd_float3x3(
            SIMD3(previousPose.columns.0.x, previousPose.columns.0.y, previousPose.columns.0.z),
            SIMD3(previousPose.columns.1.x, previousPose.columns.1.y, previousPose.columns.1.z),
            SIMD3(previousPose.columns.2.x, previousPose.columns.2.y, previousPose.columns.2.z)
        )
        let currentRotation = simd_float3x3(
            SIMD3(currentPose.columns.0.x, currentPose.columns.0.y, currentPose.columns.0.z),
            SIMD3(currentPose.columns.1.x, currentPose.columns.1.y, currentPose.columns.1.z),
            SIMD3(currentPose.columns.2.x, currentPose.columns.2.y, currentPose.columns.2.z)
        )
        let relativeRotation = previousRotation.transpose * currentRotation
        let trace = relativeRotation.columns.0.x + relativeRotation.columns.1.y + relativeRotation.columns.2.z
        let cosAngle = (trace - 1.0) / 2.0
        let rotationRadians = acos(min(max(cosAngle, -1.0), 1.0))
        let rotationDegrees = rotationRadians * 180.0 / .pi

        let severity: PoseJumpSeverity
        if translationMeters > 0.15 || rotationDegrees > 20 {
            severity = .severe
        } else if translationMeters > 0.08 || rotationDegrees > 12 {
            severity = .suspicious
        } else {
            severity = .none
        }

        return PoseDeltaMetrics(
            translationMeters: translationMeters,
            rotationDegrees: rotationDegrees,
            severity: severity
        )
    }

    private func stopCaptureTimer() {
        captureTimer?.invalidate()
        captureTimer = nil
    }
}

// MARK: - ARSessionDelegate

extension CaptureSessionManager: ARSessionDelegate {

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        // Update tracking state on main thread
        let state = frame.camera.trackingState
        DispatchQueue.main.async { [weak self] in
            self?.trackingState = state
            self?.trackingStateDescription = state.displayString
        }

        processFrame(frame)
    }

    func session(_ session: ARSession, didFailWithError error: Error) {
        DispatchQueue.main.async { [weak self] in
            self?.lastErrorMessage = error.localizedDescription
            self?.trackingStateDescription = "Session Error: \(error.localizedDescription)"
        }
    }

    func sessionWasInterrupted(_ session: ARSession) {
        DispatchQueue.main.async { [weak self] in
            self?.trackingStateDescription = "Session Interrupted"
            self?.lastErrorMessage = "Session Interrupted"
        }
    }

    func sessionInterruptionEnded(_ session: ARSession) {
        DispatchQueue.main.async { [weak self] in
            self?.lastErrorMessage = nil
            self?.trackingStateDescription = "Resuming..."
        }
    }
}

// MARK: - TrackingState display helper

extension ARCamera.TrackingState {
    var displayString: String {
        switch self {
        case .notAvailable:
            return "Not Available"
        case .limited(let reason):
            switch reason {
            case .initializing:
                return "Initializing"
            case .excessiveMotion:
                return "Excessive Motion"
            case .insufficientFeatures:
                return "Insufficient Features"
            case .relocalizing:
                return "Relocalizing"
            @unknown default:
                return "Limited"
            }
        case .normal:
            return "Tracking Normal"
        }
    }
}
