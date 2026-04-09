import Foundation

enum CaptureSessionUploadMode: String {
    case mapping
    case localization
}

enum CaptureUploadConnectionState {
    case disconnected
    case discovering
    case connecting
    case connected
    case streaming
    case finalizing
    case failed
}

struct CaptureUploadStateSummary {
    let connectionState: CaptureUploadConnectionState
    let statusMessage: String
    let pendingFrameCount: Int
    let uploadedFrameCount: Int
    let lastReceiverOutputPath: String?
    let lastErrorMessage: String?
    let supportsPointCloudUpload: Bool
    let supportsLiveLocalizationStream: Bool
}

struct CaptureUploadSessionDescriptor {
    let sessionID: String
    let sessionName: String
    let sessionMode: CaptureSessionUploadMode
    let depthEnabled: Bool
    let startedAt: TimeInterval
}

struct CaptureSessionPointCloudArtifact {
    let fileName: String
    let format: String
    let coordinateConvention: String
    let pointCount: Int
    let data: Data
}

struct PreparedCaptureFramePayload {
    let record: CaptureFrameRecord
    let rgbJPEGData: Data?
    let depthPNGData: Data?
    let confidencePNGData: Data?
}

/// Defines the protocol for uploading capture frames to a PC receiver.
protocol UploadClient: AnyObject {
    var isConnected: Bool { get }
    var statusMessage: String { get }
    var supportsPointCloudUpload: Bool { get }
    var stateSummary: CaptureUploadStateSummary { get }
    var onStateChanged: (() -> Void)? { get set }
    func connect(to url: URL)
    func disconnect()
    func startSession(_ session: CaptureUploadSessionDescriptor)
    func sendFrame(_ payload: PreparedCaptureFramePayload)
    func sendRealtimeFrame(_ payload: PreparedCaptureFramePayload)
    func sendSessionFinalized(manifest: Data, session: CaptureUploadSessionDescriptor?, pointCloud: CaptureSessionPointCloudArtifact?)
}
