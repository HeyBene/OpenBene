import Flutter
import UIKit
import ARKit

/// LiDAR bridge for Flutter - provides depth sensing using ARKit
@available(iOS 14.0, *)
class LiDARBridge: NSObject, FlutterStreamHandler, ARSessionDelegate {
    private var arSession: ARSession?
    private var eventSink: FlutterEventSink?
    private var isCapturing = false
    
    private let methodChannel: FlutterMethodChannel
    private let eventChannel: FlutterEventChannel
    
    init(messenger: FlutterBinaryMessenger) {
        methodChannel = FlutterMethodChannel(name: "openbene/lidar", binaryMessenger: messenger)
        eventChannel = FlutterEventChannel(name: "openbene/lidar_stream", binaryMessenger: messenger)
        
        super.init()
        
        eventChannel.setStreamHandler(self)
        methodChannel.setMethodCallHandler(handleMethodCall)
    }
    
    // MARK: - Method Channel Handler
    
    private func handleMethodCall(call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "isLiDARAvailable":
            result(isLiDARAvailable())
            
        case "startCapture":
            startCapture(result: result)
            
        case "stopCapture":
            stopCapture(result: result)
            
        default:
            result(FlutterMethodNotImplemented)
        }
    }
    
    // MARK: - LiDAR Availability
    
    private func isLiDARAvailable() -> Bool {
        if #available(iOS 14.0, *) {
            return ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth)
        }
        return false
    }
    
    // MARK: - Capture Control
    
    private func startCapture(result: @escaping FlutterResult) {
        guard isLiDARAvailable() else {
            result(FlutterError(code: "UNAVAILABLE",
                              message: "LiDAR not available on this device",
                              details: nil))
            return
        }
        
        if isCapturing {
            result(true)
            return
        }
        
        let configuration = ARWorldTrackingConfiguration()
        
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
            configuration.frameSemantics = .sceneDepth
        }
        
        arSession = ARSession()
        arSession?.delegate = self
        arSession?.run(configuration)
        
        isCapturing = true
        result(true)
    }
    
    private func stopCapture(result: @escaping FlutterResult) {
        if !isCapturing {
            result(nil)
            return
        }
        
        arSession?.pause()
        arSession?.delegate = nil
        arSession = nil
        
        isCapturing = false
        result(nil)
    }
    
    // MARK: - FlutterStreamHandler
    
    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        self.eventSink = events
        return nil
    }
    
    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        self.eventSink = nil
        return nil
    }
    
    // MARK: - ARSessionDelegate
    
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        guard let eventSink = eventSink,
              let sceneDepth = frame.sceneDepth else {
            return
        }
        
        // Convert depth data to format Flutter can use
        let depthMap = sceneDepth.depthMap
        let width = CVPixelBufferGetWidth(depthMap)
        let height = CVPixelBufferGetHeight(depthMap)
        
        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }
        
        guard let baseAddress = CVPixelBufferGetBaseAddress(depthMap) else {
            return
        }
        
        let floatBuffer = baseAddress.assumingMemoryBound(to: Float32.self)
        let count = width * height
        
        // Find min/max depth values and convert to array
        var minDepth: Float32 = Float32.greatestFiniteMagnitude
        var maxDepth: Float32 = 0.0
        var depthArray: [Double] = []
        depthArray.reserveCapacity(count)
        
        for i in 0..<count {
            let depth = floatBuffer[i]
            if depth > 0 && depth < 100 { // Filter invalid values
                minDepth = min(minDepth, depth)
                maxDepth = max(maxDepth, depth)
            }
            depthArray.append(Double(depth))
        }
        
        // Ensure valid min/max
        if minDepth == Float32.greatestFiniteMagnitude {
            minDepth = 0.0
        }
        
        // Create data dictionary
        let data: [String: Any] = [
            "depth_map": depthArray,
            "width": width,
            "height": height,
            "min_depth": Double(minDepth),
            "max_depth": Double(maxDepth),
            "timestamp": ISO8601DateFormatter().string(from: Date())
        ]
        
        // Send to Flutter
        DispatchQueue.main.async {
            eventSink(data)
        }
    }
    
    func session(_ session: ARSession, didFailWithError error: Error) {
        print("[LiDARBridge] ARSession failed: \(error.localizedDescription)")
        eventSink?(FlutterError(code: "SESSION_ERROR",
                                message: error.localizedDescription,
                                details: nil))
    }
}
