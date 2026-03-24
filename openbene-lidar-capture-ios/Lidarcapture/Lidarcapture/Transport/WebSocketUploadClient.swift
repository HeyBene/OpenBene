import Foundation
import UIKit
import CoreVideo

/// Uploads accepted capture frames to a PC receiver over WebSocket.
///
/// Protocol design:
/// - Text messages: JSON control/metadata
/// - Binary messages: image/depth payloads
///
/// Frame upload sequence:
/// 1. Text: JSON frame metadata (index, pose, intrinsics, has_depth, sizes)
/// 2. Binary: JPEG image data
/// 3. Binary: 16-bit depth PNG data (only if depth available)
final class WebSocketUploadClient: NSObject, UploadClient, ObservableObject {

    @Published var isConnected: Bool = false
    @Published var statusMessage: String = "Not connected"
    @Published var uploadedFrameCount: Int = 0

    private var webSocket: URLSessionWebSocketTask?
    private var urlSession: URLSession?
    private let uploadQueue = DispatchQueue(label: "com.openbene.upload", qos: .utility)

    override init() {
        super.init()
        urlSession = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
    }

    func connect(to url: URL) {
        disconnect()
        webSocket = urlSession?.webSocketTask(with: url)
        webSocket?.resume()
        statusMessage = "Connecting to \(url.host ?? "")..."
        listenForMessages()
    }

    func disconnect() {
        webSocket?.cancel(with: .goingAway, reason: nil)
        webSocket = nil
        DispatchQueue.main.async {
            self.isConnected = false
            self.statusMessage = "Disconnected"
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
    }

    func sendFrame(_ record: CaptureFrameRecord) {
        guard let ws = webSocket else { return }

        uploadQueue.async { [weak self] in
            guard let self = self else { return }

            let metadata = self.buildFrameMetadata(record)
            self.sendJSON(metadata, over: ws)

            if let jpegData = self.encodeRGBAsJPEG(record.pixelBuffer) {
                let msg = URLSessionWebSocketTask.Message.data(jpegData)
                ws.send(msg) { _ in }
            }

            if let depthBuf = record.depthBuffer,
               let depthData = self.encodeDepthAsPNGData(depthBuf) {
                let msg = URLSessionWebSocketTask.Message.data(depthData)
                ws.send(msg) { _ in }
            }

            DispatchQueue.main.async {
                self.uploadedFrameCount += 1
            }
        }
    }

    func sendSessionFinalized(manifest: Data, session: CaptureUploadSessionDescriptor?) {
        guard let ws = webSocket else { return }
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
        let msg = URLSessionWebSocketTask.Message.data(manifest)
        ws.send(msg) { _ in }
    }

    // MARK: - Private helpers

    private func sendJSON(_ payload: [String: Any], over webSocket: URLSessionWebSocketTask) {
        guard let jsonData = try? JSONSerialization.data(withJSONObject: payload),
              let jsonString = String(data: jsonData, encoding: .utf8) else { return }
        let msg = URLSessionWebSocketTask.Message.string(jsonString)
        webSocket.send(msg) { _ in }
    }

    private func buildFrameMetadata(_ record: CaptureFrameRecord) -> [String: Any] {
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
            "has_depth": record.depthBuffer != nil,
            "depth_width": record.depthWidth,
            "depth_height": record.depthHeight
        ]
    }

    private func encodeRGBAsJPEG(_ pixelBuffer: CVPixelBuffer) -> Data? {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext()
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return nil }
        return UIImage(cgImage: cgImage).jpegData(compressionQuality: 0.85)
    }

    private func encodeDepthAsPNGData(_ depthBuffer: CVPixelBuffer) -> Data? {
        CVPixelBufferLockBaseAddress(depthBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthBuffer, .readOnly) }

        let width = CVPixelBufferGetWidth(depthBuffer)
        let height = CVPixelBufferGetHeight(depthBuffer)
        guard let baseAddress = CVPixelBufferGetBaseAddress(depthBuffer) else { return nil }

        let floatPointer = baseAddress.assumingMemoryBound(to: Float.self)
        let pixelCount = width * height
        let depthScale: Float = 1000.0

        var uint16Data = [UInt16](repeating: 0, count: pixelCount)
        for i in 0..<pixelCount {
            let meters = floatPointer[i]
            if meters.isFinite && meters > 0 {
                uint16Data[i] = UInt16(min(max(meters * depthScale, 0), Float(UInt16.max)))
            }
        }

        let bytesPerRow = width * MemoryLayout<UInt16>.size
        let colorSpace = CGColorSpaceCreateDeviceGray()
        let bitmapInfo: CGBitmapInfo = [.byteOrder16Little]

        return uint16Data.withUnsafeMutableBytes { rawBuffer -> Data? in
            guard let context = CGContext(
                data: rawBuffer.baseAddress,
                width: width, height: height,
                bitsPerComponent: 16, bytesPerRow: bytesPerRow,
                space: colorSpace, bitmapInfo: bitmapInfo.rawValue
            ) else { return nil }

            guard let cgImage = context.makeImage() else { return nil }
            let mutableData = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(mutableData as CFMutableData, "public.png" as CFString, 1, nil) else { return nil }
            CGImageDestinationAddImage(destination, cgImage, nil)
            guard CGImageDestinationFinalize(destination) else { return nil }
            return mutableData as Data
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
                            self?.isConnected = status == "connected" || self?.isConnected == true
                            switch status {
                            case "connected":
                                self?.statusMessage = "已连接接收端"
                            case "session_started":
                                self?.statusMessage = "会话已开始上传"
                            case "session_ending":
                                let receivedFrames = payload["received_frames"] as? Int ?? 0
                                self?.statusMessage = "接收端结束会话，已收 \(receivedFrames) 帧"
                            default:
                                self?.statusMessage = status
                            }
                        }
                    }
                default:
                    break
                }
                self?.listenForMessages()
            case .failure:
                DispatchQueue.main.async {
                    self?.isConnected = false
                    self?.statusMessage = "Connection lost"
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
            self.statusMessage = "Connected"
        }
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        DispatchQueue.main.async {
            self.isConnected = false
            self.statusMessage = "Disconnected"
        }
    }
}
