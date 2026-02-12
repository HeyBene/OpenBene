import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  private var lidarBridge: Any?
  
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    
    // Initialize LiDAR bridge if available (iOS 14.0+)
    if #available(iOS 14.0, *) {
      let controller = window?.rootViewController as! FlutterViewController
      lidarBridge = LiDARBridge(messenger: controller.binaryMessenger)
    }
    
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
