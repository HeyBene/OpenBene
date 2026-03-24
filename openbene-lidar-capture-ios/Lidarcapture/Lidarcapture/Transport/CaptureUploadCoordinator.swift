import Foundation

final class CaptureUploadCoordinator: ObservableObject {
    @Published private(set) var activeSession: CaptureUploadSessionDescriptor?
    @Published private(set) var receiverURL: URL?

    private let uploadClient: UploadClient

    init(uploadClient: UploadClient) {
        self.uploadClient = uploadClient
    }

    var isConnected: Bool {
        uploadClient.isConnected
    }

    var statusMessage: String {
        uploadClient.statusMessage
    }

    func connect(to url: URL) {
        receiverURL = url
        uploadClient.connect(to: url)
    }

    func disconnect() {
        activeSession = nil
        uploadClient.disconnect()
    }

    func beginSession(sessionName: String, mode: CaptureSessionUploadMode, depthEnabled: Bool) {
        let descriptor = CaptureUploadSessionDescriptor(
            sessionID: UUID().uuidString,
            sessionName: sessionName,
            sessionMode: mode,
            depthEnabled: depthEnabled,
            startedAt: Date().timeIntervalSince1970
        )
        activeSession = descriptor
        uploadClient.startSession(descriptor)
    }

    func sendFrame(_ record: CaptureFrameRecord) {
        guard activeSession != nil else { return }
        uploadClient.sendFrame(record)
    }

    func finishSession(manifest: Data = Data()) {
        guard let activeSession else { return }
        uploadClient.sendSessionFinalized(manifest: manifest, session: activeSession)
        self.activeSession = nil
    }
}
