import Foundation
import UIKit
import CoreVideo
import ImageIO
import UniformTypeIdentifiers

/// WebSocket 上传客户端。
/// 负责把已接收的帧镜像上传到 PC 端接收器。
///
/// 协议约定：
/// - 文本消息：JSON 元数据 / 控制消息
/// - 二进制消息：RGB 图像和深度图内容
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

    func sendFrame(_ record: CaptureFrameRecord) {
        guard let ws = webSocket else { return }

        uploadQueue.async { [weak self] in
            guard let self = self else { return }

            // 1. 先发一条 JSON 元数据，告诉接收端这一帧的结构信息。
            let metadata = self.buildFrameMetadata(record)
            if let jsonData = try? JSONSerialization.data(withJSONObject: metadata),
               let jsonString = String(data: jsonData, encoding: .utf8) {
                let msg = URLSessionWebSocketTask.Message.string(jsonString)
                ws.send(msg) { _ in }
            }

            // 2. 再发 RGB 图像。当前先压成 JPEG 以减小体积。
            if let jpegData = self.encodeRGBAsJPEG(record.pixelBuffer) {
                let msg = URLSessionWebSocketTask.Message.data(jpegData)
                ws.send(msg) { _ in }
            }

            // 3. 如果有深度图，再追加发送 16 位 PNG。
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

    func sendSessionFinalized(manifest: Data) {
        guard let ws = webSocket else { return }
        let control: [String: Any] = ["type": "session_end", "manifest_size": manifest.count]
        if let jsonData = try? JSONSerialization.data(withJSONObject: control),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            let msg = URLSessionWebSocketTask.Message.string(jsonString)
            ws.send(msg) { _ in }
        }
        let msg = URLSessionWebSocketTask.Message.data(manifest)
        ws.send(msg) { _ in }
    }

    // MARK: - Private helpers

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
                width: width,
                height: height,
                bitsPerComponent: 16,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: bitmapInfo.rawValue
            ) else { return nil }

            guard let cgImage = context.makeImage() else { return nil }
            let mutableData = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(
                mutableData as CFMutableData,
                UTType.png.identifier as CFString,
                1,
                nil
            ) else { return nil }
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
                    if text.contains("\"connected\"") {
                        DispatchQueue.main.async {
                            self?.isConnected = true
                            self?.statusMessage = "Connected"
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
