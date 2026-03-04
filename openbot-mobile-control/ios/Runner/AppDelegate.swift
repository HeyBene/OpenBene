import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
    
    // MARK: - Properties
    
    private var lidarChannel: FlutterMethodChannel?
    private var lidarEventChannel: FlutterEventChannel?
    
    // MARK: - Application Lifecycle
    
    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        GeneratedPluginRegistrant.register(with: self)
        
        // Set up LiDAR capture MethodChannel
        setupLidarMethodChannel()
        
        // Set up LiDAR status EventChannel
        setupLidarEventChannel()
        
        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }
    
    // MARK: - Method Channel Setup
    
    private func setupLidarMethodChannel() {
        guard let controller = window?.rootViewController as? FlutterViewController else {
            return
        }
        
        lidarChannel = FlutterMethodChannel(
            name: "openbene/lidar_capture",
            binaryMessenger: controller.binaryMessenger
        )
        
        lidarChannel?.setMethodCallHandler { [weak self] (call, result) in
            self?.handleLidarMethodCall(call, result: result)
        }
    }
    
    private func handleLidarMethodCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let service = LidarCaptureService.shared
        
        switch call.method {
        case "startARSession":
            let error = service.startARSession()
            if let error = error {
                result(FlutterError(code: "AR_ERROR", message: error, details: nil))
            } else {
                result(nil)
            }
            
        case "stopARSession":
            service.stopARSession()
            result(nil)
            
        case "startCapture":
            guard let args = call.arguments as? [String: Any] else {
                result(FlutterError(code: "INVALID_ARGS", message: "Arguments required", details: nil))
                return
            }
            
            let datasetName = args["datasetName"] as? String
            let fps = args["fps"] as? Int ?? 10
            let includeDepth = args["includeDepth"] as? Bool ?? true
            
            let error = service.startCapture(datasetName: datasetName, fps: fps, includeDepth: includeDepth)
            if let error = error {
                result(FlutterError(code: "CAPTURE_ERROR", message: error, details: nil))
            } else {
                result(nil)
            }
            
        case "stopCapture":
            let createZip = (call.arguments as? [String: Any])?["createZip"] as? Bool ?? false
            let path = service.stopCapture(createZip: createZip)
            result(path)
            
        case "getStatus":
            let status = service.getStatus()
            let encoder = JSONEncoder()
            encoder.keyEncodingStrategy = .convertToSnakeCase
            if let data = try? encoder.encode(status),
               let json = String(data: data, encoding: .utf8) {
                result(json)
            } else {
                result(FlutterError(code: "ENCODE_ERROR", message: "Failed to encode status", details: nil))
            }
            
        case "listDatasets":
            let datasets = service.listDatasets()
            let encoder = JSONEncoder()
            encoder.keyEncodingStrategy = .convertToSnakeCase
            encoder.dateEncodingStrategy = .iso8601
            if let data = try? encoder.encode(datasets),
               let json = String(data: data, encoding: .utf8) {
                result(json)
            } else {
                result(FlutterError(code: "ENCODE_ERROR", message: "Failed to encode datasets", details: nil))
            }
            
        case "exportZip":
            guard let args = call.arguments as? [String: Any],
                  let datasetId = args["datasetId"] as? String else {
                result(FlutterError(code: "INVALID_ARGS", message: "datasetId required", details: nil))
                return
            }
            let path = service.exportZip(datasetId: datasetId)
            result(path)
            
        case "deleteDataset":
            guard let args = call.arguments as? [String: Any],
                  let datasetId = args["datasetId"] as? String else {
                result(FlutterError(code: "INVALID_ARGS", message: "datasetId required", details: nil))
                return
            }
            let message = service.deleteDataset(datasetId: datasetId)
            result(message)
            
        case "isLidarSupported":
            result(service.lidarSupported)
            
        default:
            result(FlutterMethodNotImplemented)
        }
    }
    
    // MARK: - Event Channel Setup
    
    private func setupLidarEventChannel() {
        guard let controller = window?.rootViewController as? FlutterViewController else {
            return
        }
        
        lidarEventChannel = FlutterEventChannel(
            name: "openbene/lidar_capture_events",
            binaryMessenger: controller.binaryMessenger
        )
        
        lidarEventChannel?.setStreamHandler(LidarCaptureStreamHandler())
    }
}

// MARK: - Event Channel Handler

class LidarCaptureStreamHandler: NSObject, FlutterStreamHandler {
    
    private var eventSink: FlutterEventSink?
    
    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        self.eventSink = events
        LidarCaptureService.shared.setEventSink(events)
        return nil
    }
    
    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        self.eventSink = nil
        LidarCaptureService.shared.setEventSink(nil)
        return nil
    }
}