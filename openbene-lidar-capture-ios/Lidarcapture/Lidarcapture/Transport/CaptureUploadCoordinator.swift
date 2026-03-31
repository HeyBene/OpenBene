import Foundation

final class CaptureUploadCoordinator: ObservableObject {
    @Published private(set) var activeSession: CaptureUploadSessionDescriptor?
    @Published private(set) var receiverURL: URL?
    @Published private(set) var stateSummary: CaptureUploadStateSummary

    private let uploadClient: UploadClient
    private var lastRealtimeFrameSentAt: TimeInterval = 0
    private let realtimeSendInterval: TimeInterval = 0.25

    init(uploadClient: UploadClient) {
        self.uploadClient = uploadClient
        self.stateSummary = uploadClient.stateSummary
        uploadClient.onStateChanged = { [weak self] in
            self?.refreshStateSummary()
        }
    }

    var isConnected: Bool {
        uploadClient.isConnected
    }

    var statusMessage: String {
        stateSummary.statusMessage
    }

    var supportsPointCloudUpload: Bool {
        stateSummary.supportsPointCloudUpload
    }

    var supportsLiveLocalizationStream: Bool {
        stateSummary.supportsLiveLocalizationStream
    }

    func connect(to url: URL) {
        receiverURL = url
        uploadClient.connect(to: url)
        refreshStateSummary()
    }

    func disconnect() {
        activeSession = nil
        uploadClient.disconnect()
        refreshStateSummary()
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
        lastRealtimeFrameSentAt = 0
        uploadClient.startSession(descriptor)
        refreshStateSummary()
    }

    func sendPreparedFrame(_ payload: PreparedCaptureFramePayload, mode: CaptureSessionUploadMode) {
        guard activeSession != nil else { return }
        if mode == .localization {
            let now = payload.record.timestamp
            guard now - lastRealtimeFrameSentAt >= realtimeSendInterval else { return }
            lastRealtimeFrameSentAt = now
            uploadClient.sendRealtimeFrame(payload.record)
        } else {
            uploadClient.sendFrame(payload)
        }
        refreshStateSummary()
    }

    func finishSession(manifest: Data = Data(), pointCloud: CaptureSessionPointCloudArtifact? = nil) {
        guard let activeSession else { return }
        uploadClient.sendSessionFinalized(manifest: manifest, session: activeSession, pointCloud: pointCloud)
        self.activeSession = nil
        refreshStateSummary()
    }

    private func refreshStateSummary() {
        DispatchQueue.main.async {
            self.stateSummary = self.uploadClient.stateSummary
        }
    }
}
