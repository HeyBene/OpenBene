import Foundation

/// Defines the protocol for uploading capture frames to a PC receiver.
protocol UploadClient {
    var isConnected: Bool { get }
    func connect(to url: URL)
    func disconnect()
    func sendFrame(_ record: CaptureFrameRecord)
    func sendSessionFinalized(manifest: Data)
}
