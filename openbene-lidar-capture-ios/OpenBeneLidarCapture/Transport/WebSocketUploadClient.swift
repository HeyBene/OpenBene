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

    func sendFrame(_ record: CaptureFrameRecord) {
        guard let ws = webSocket else { return }

        uploadQueue.async { [weak self] in
            guard let self = self else { return }

            // 1. Send JSON metadata
            let metadata = self.buildFrameMetadata(record)
            if let jsonData = try? JSONSerialization.data(withJSONObject: metadata) {
                let msg = URLSessionWebSocketTask.Message.string(String(data: jsonData, encoding: .utf8) ?? "")
                ws.send(msg) { _ in }
            }

            // 2. Send JPEG image as binary
            if let jpegData = self.encodeRGBAsJPEG(record.pixelBuffer) {
                let msg = URLSessionWebSocketTask.Message.data(jpegData)
                ws.send(msg) { _ in }
            }

            // 3. Send depth as binary (if available)
            if let depthBuf = record.depthBuffer {
                if let depthData = self.encodeDepthAsPNGData(depthBuf) {
                    let msg = URLSessionWebSocketTask.Message.data(depthData)
                    ws.send(msg) { _ in }
                }
            }

            DispatchQueue.main.async {
                self.uploadedFrameCount += 1
            }
        }
    }

    func sendSessionFinalized(manifest: Data) {
        guard let ws = webSocket else { return }
        let control: [String: Any] = ["type": "session_end", "manifest_size": manifest.count]
        if let jsonData = try? JSONSerialization.data(withJSONObject: control) {
            let msg = URLSessionWebSocketTask.Message.string(String(data: jsonData, encoding: .utf8) ?? "")
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
