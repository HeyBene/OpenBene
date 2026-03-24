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

/// Defines the protocol for uploading capture frames to a PC receiver.
protocol UploadClient {
    var isConnected: Bool { get }
    var statusMessage: String { get }
    func connect(to url: URL)
    func disconnect()
    func startSession(_ session: CaptureUploadSessionDescriptor)
    func sendFrame(_ record: CaptureFrameRecord)
    func sendSessionFinalized(manifest: Data, session: CaptureUploadSessionDescriptor?)
}
