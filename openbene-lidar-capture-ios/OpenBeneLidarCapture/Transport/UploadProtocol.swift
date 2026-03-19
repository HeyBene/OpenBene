import Foundation

/// 上传客户端协议。
/// 采集层只依赖这个协议，不关心底层到底是 WebSocket 还是别的传输方式。
protocol UploadClient {
    var isConnected: Bool { get }
    func connect(to url: URL)
    func disconnect()
    func sendFrame(_ record: CaptureFrameRecord)
    func sendSessionFinalized(manifest: Data)
}
