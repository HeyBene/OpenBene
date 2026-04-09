import Foundation
import UIKit
import CoreVideo
import ImageIO
import UniformTypeIdentifiers

/// Uploads accepted capture frames to a PC receiver over WebSocket.
final class WebSocketUploadClient: NSObject, UploadClient, ObservableObject {

    @Published var isConnected: Bool = false
    @Published var statusMessage: String = "未连接"
    @Published var uploadedFrameCount: Int = 0
    @Published var supportsPointCloudUpload: Bool = false

    var onStateChanged: (() -> Void)?

    var stateSummary: CaptureUploadStateSummary {
        CaptureUploadStateSummary(
            connectionState: connectionState,
            statusMessage: statusMessage,
            pendingFrameCount: pendingFrameCount,
            uploadedFrameCount: uploadedFrameCount,
            lastReceiverOutputPath: lastReceiverOutputPath,
            lastErrorMessage: lastErrorMessage,
            supportsPointCloudUpload: supportsPointCloudUpload,
            supportsLiveLocalizationStream: supportsLiveLocalizationStream
        )
    }

    private var webSocket: URLSessionWebSocketTask?
    private var urlSession: URLSession?
    private let uploadQueue = DispatchQueue(label: "com.openbene.upload", qos: .utility)
    private var pendingFrameCount: Int = 0
    private var connectionState: CaptureUploadConnectionState = .disconnected {
        didSet { notifyStateChanged() }
    }
    private var lastReceiverOutputPath: String?
    private var lastErrorMessage: String?
    private var supportsLiveLocalizationStream: Bool = false

    override init() {
        super.init()
        urlSession = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
    }

    func connect(to url: URL) {
        disconnect()
        connectionState = .connecting
        statusMessage = "正在连接 \(url.host ?? "接收端")"
        webSocket = urlSession?.webSocketTask(with: url)
        webSocket?.resume()
        listenForMessages()
        notifyStateChanged()
    }

    func disconnect() {
        webSocket?.cancel(with: .goingAway, reason: nil)
        webSocket = nil
        DispatchQueue.main.async {
            self.pendingFrameCount = 0
            self.isConnected = false
            self.supportsPointCloudUpload = false
            self.supportsLiveLocalizationStream = false
            self.connectionState = .disconnected
            self.statusMessage = "未连接"
            self.notifyStateChanged()
        }
    }

    func startSession(_ session: CaptureUploadSessionDescriptor) {
        guard let ws = webSocket else { return }
        let payload: [String: Any] = [
            "type": "session_start",
            "session_id": session.sessionID,
            "session_name": session.sessionName,
            "session_mode": session.sessionMode.rawValue,
            "depth_enabled": session.depthEnabled,
            "started_at": session.startedAt
        ]
        sendJSON(payload, over: ws)
        DispatchQueue.main.async {
            self.connectionState = .streaming
            self.statusMessage = session.sessionMode == .localization ? "定位流已开始" : "建图会话已开始"
        }
    }

    func sendFrame(_ payload: PreparedCaptureFramePayload) {
        guard let ws = webSocket else { return }

        uploadQueue.async { [weak self] in
            guard let self else { return }

            self.incrementPendingFrames()
            let metadata = self.buildFrameMetadata(payload, transferMode: "session", includeImage: true)
            self.sendJSON(metadata, over: ws)
            if let rgbJPEGData = payload.rgbJPEGData {
                self.sendBinary(rgbJPEGData, over: ws)
            }
            if let depthPNGData = payload.depthPNGData {
                self.sendBinary(depthPNGData, over: ws)
            }
            if let confidencePNGData = payload.confidencePNGData {
                self.sendBinary(confidencePNGData, over: ws)
            }
            self.markFrameSent()
        }
    }

    func sendRealtimeFrame(_ payload: PreparedCaptureFramePayload) {
        guard let ws = webSocket else { return }

        uploadQueue.async { [weak self] in
            guard let self else { return }
            guard payload.depthPNGData != nil else { return }
            self.incrementPendingFrames()
            let metadata = self.buildFrameMetadata(payload, transferMode: "live", includeImage: false)
            self.sendJSON(metadata, over: ws)
            if let depthPNGData = payload.depthPNGData {
                self.sendBinary(depthPNGData, over: ws)
            }
            if let confidencePNGData = payload.confidencePNGData {
                self.sendBinary(confidencePNGData, over: ws)
            }
            self.markFrameSent()
        }
    }

    func sendSessionFinalized(manifest: Data, session: CaptureUploadSessionDescriptor?, pointCloud: CaptureSessionPointCloudArtifact?) {
        guard let ws = webSocket else { return }
        DispatchQueue.main.async {
            self.connectionState = .finalizing
            self.statusMessage = "正在整理并同步结果"
        }

        var control: [String: Any] = [
            "type": "session_end",
            "manifest_size": manifest.count
        ]
        if let session {
            control["session_id"] = session.sessionID
            control["session_name"] = session.sessionName
            control["session_mode"] = session.sessionMode.rawValue
        }
        sendJSON(control, over: ws)
        sendBinary(manifest, over: ws)

        guard supportsPointCloudUpload, let pointCloud else { return }
        var pointCloudControl: [String: Any] = [
            "type": "pointcloud_start",
            "file_name": pointCloud.fileName,
            "format": pointCloud.format,
            "coordinate_convention": pointCloud.coordinateConvention,
            "point_count": pointCloud.pointCount,
            "byte_count": pointCloud.data.count
        ]
        if let session {
            pointCloudControl["session_id"] = session.sessionID
        }
        sendJSON(pointCloudControl, over: ws)
        sendBinary(pointCloud.data, over: ws)
    }

    // MARK: - Private helpers

    private func notifyStateChanged() {
        DispatchQueue.main.async {
            self.objectWillChange.send()
            self.onStateChanged?()
        }
    }

    private func sendJSON(_ payload: [String: Any], over webSocket: URLSessionWebSocketTask) {
        guard let jsonData = try? JSONSerialization.data(withJSONObject: payload),
              let jsonString = String(data: jsonData, encoding: .utf8) else { return }
        let msg = URLSessionWebSocketTask.Message.string(jsonString)
        webSocket.send(msg) { [weak self] error in
            if let error {
                self?.recordSendError(error)
            }
        }
    }

    private func sendBinary(_ data: Data, over webSocket: URLSessionWebSocketTask) {
        let msg = URLSessionWebSocketTask.Message.data(data)
        webSocket.send(msg) { [weak self] error in
            if let error {
                self?.recordSendError(error)
            }
        }
    }

    private func buildFrameMetadata(
        _ payload: PreparedCaptureFramePayload,
        transferMode: String,
        includeImage: Bool
    ) -> [String: Any] {
        let record = payload.record
        let hasImage = includeImage && payload.rgbJPEGData != nil
        let hasDepth = payload.depthPNGData != nil
        let hasConfidence = payload.confidencePNGData != nil
        let transform = PoseTransformAdapter.arkitToNerfstudio(record.transformMatrix)
        return [
            "type": "frame",
            "index": record.index,
            "timestamp": record.timestamp,
            "fl_x": record.flX,
            "fl_y": record.flY,
            "cx": record.cx,
            "cy": record.cy,
            "w": record.width,
            "h": record.height,
            "transform_matrix": transform,
            "has_image": hasImage,
            "has_depth": hasDepth,
            "has_confidence": hasConfidence,
            "depth_width": hasDepth ? record.depthWidth : 0,
            "depth_height": hasDepth ? record.depthHeight : 0,
            "confidence_width": hasConfidence ? record.confidenceWidth : 0,
            "confidence_height": hasConfidence ? record.confidenceHeight : 0,
            "tracking_state": record.trackingStateRaw,
            "depth_source": record.depthSourceRaw,
            "transfer_mode": transferMode,
        ]
    }

    private func incrementPendingFrames() {
        DispatchQueue.main.async {
            self.pendingFrameCount += 1
            self.notifyStateChanged()
        }
    }

    private func markFrameSent() {
        DispatchQueue.main.async {
            self.pendingFrameCount = max(self.pendingFrameCount - 1, 0)
            self.uploadedFrameCount += 1
            self.notifyStateChanged()
        }
    }

    private func recordSendError(_ error: Error) {
        DispatchQueue.main.async {
            self.lastErrorMessage = error.localizedDescription
            self.connectionState = .failed
            self.statusMessage = "传输失败，请重试"
            self.notifyStateChanged()
        }
    }

    private func listenForMessages() {
        webSocket?.receive { [weak self] result in
            switch result {
            case .success(let message):
                switch message {
                case .string(let text):
                    if let data = text.data(using: .utf8),
                       let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let status = payload["status"] as? String {
                        DispatchQueue.main.async {
                            if let outputDir = payload["output_dir"] as? String {
                                self?.lastReceiverOutputPath = outputDir
                            }
                            if let capabilities = payload["capabilities"] as? [String] {
                                self?.supportsPointCloudUpload = capabilities.contains("pointcloud_v1")
                                self?.supportsLiveLocalizationStream = capabilities.contains("live_localization_v1")
                            }
                            self?.isConnected = status == "connected" || self?.isConnected == true
                            switch status {
                            case "connected":
                                self?.connectionState = .connected
                                self?.statusMessage = (self?.supportsPointCloudUpload == true) ? "已连接接收端（支持点云）" : "已连接接收端"
                            case "session_started":
                                self?.connectionState = .streaming
                                self?.statusMessage = "接收端已接管当前会话"
                            case "session_ending":
                                self?.connectionState = .finalizing
                                let receivedFrames = payload["received_frames"] as? Int ?? 0
                                self?.statusMessage = "接收端正在整理结果，已收 \(receivedFrames) 帧"
                            case "session_saved":
                                self?.connectionState = .connected
                                self?.statusMessage = "已同步到电脑"
                            case "pointcloud_received":
                                let receivedPoints = payload["point_count"] as? Int ?? 0
                                self?.statusMessage = "点云已上传（\(receivedPoints) 点）"
                            case "receiver_busy":
                                self?.connectionState = .failed
                                self?.statusMessage = "接收端正忙，请稍后再试"
                            default:
                                self?.statusMessage = status
                            }
                            self?.notifyStateChanged()
                        }
                    }
                default:
                    break
                }
                self?.listenForMessages()
            case .failure(let error):
                DispatchQueue.main.async {
                    self?.lastErrorMessage = error.localizedDescription
                    self?.isConnected = false
                    self?.supportsPointCloudUpload = false
                    self?.supportsLiveLocalizationStream = false
                    self?.connectionState = .failed
                    self?.statusMessage = "连接已断开"
                    self?.notifyStateChanged()
                }
            }
        }
    }
}

// MARK: - URLSessionWebSocketDelegate

extension WebSocketUploadClient: URLSessionWebSocketDelegate {
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        DispatchQueue.main.async {
            self.isConnected = true
            self.connectionState = .connected
            self.statusMessage = "已建立连接"
            self.notifyStateChanged()
        }
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        DispatchQueue.main.async {
            self.isConnected = false
            self.connectionState = .disconnected
            self.statusMessage = "已断开"
            self.notifyStateChanged()
        }
    }
}
