import Foundation

enum CaptureSessionUploadMode: String {
    case mapping
    case localization
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

/// Defines the protocol for uploading capture frames to a PC receiver.
protocol UploadClient {
    var isConnected: Bool { get }
    var statusMessage: String { get }
    var supportsPointCloudUpload: Bool { get }
    func connect(to url: URL)
    func disconnect()
    func startSession(_ session: CaptureUploadSessionDescriptor)
    func sendFrame(_ record: CaptureFrameRecord)
    func sendSessionFinalized(manifest: Data, session: CaptureUploadSessionDescriptor?, pointCloud: CaptureSessionPointCloudArtifact?)
}
