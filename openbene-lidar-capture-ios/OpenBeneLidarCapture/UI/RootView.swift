import SwiftUI

struct RootView: View {
    @StateObject private var captureManager = CaptureSessionManager()
    @State private var pcAddress: String = ""

    var body: some View {
        NavigationView {
            VStack(spacing: 20) {

                // 设备能力卡片
                GroupBox(label: Text("Device")) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("ARKit")
                            Spacer()
                            Text(DeviceCapabilities.isARWorldTrackingAvailable ? "OK" : "N/A")
                                .foregroundColor(DeviceCapabilities.isARWorldTrackingAvailable ? .green : .red)
                        }
                        HStack {
                            Text("LiDAR")
                            Spacer()
                            Text(DeviceCapabilities.isLiDARAvailable ? "OK" : "N/A")
                                .foregroundColor(DeviceCapabilities.isLiDARAvailable ? .green : .orange)
                        }
                        if !DeviceCapabilities.isLiDARAvailable {
                            Text("RGB-only test mode (no depth)")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                    }
                    .padding(.vertical, 4)
                }

                // 跟踪状态卡片
                GroupBox(label: Text("Tracking")) {
                    HStack {
                        Circle()
                            .fill(trackingColor)
                            .frame(width: 12, height: 12)
                        Text(captureManager.trackingStateDescription)
                        Spacer()
                    }
                    .padding(.vertical, 4)
                }

                // 采集状态卡片
                if captureManager.isCapturing {
                    GroupBox(label: Text("Capture")) {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Frames captured")
                                Spacer()
                                Text("\(captureManager.frameCount)")
                                    .monospacedDigit()
                            }
                            HStack {
                                Text("Depth")
                                Spacer()
                                Text(captureManager.depthAvailable ? "Recording" : "Skipped")
                                    .foregroundColor(captureManager.depthAvailable ? .green : .orange)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                Spacer()

                // 控制按钮
                VStack(spacing: 12) {
                    if !captureManager.isSessionRunning {
                        Button(action: { captureManager.startSession() }) {
                            Label("Start AR Session", systemImage: "arkit")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                    } else if !captureManager.isCapturing {
                        Button(action: { captureManager.startCapture() }) {
                            Label("Start Capture", systemImage: "record.circle")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)

                        Button(action: { captureManager.stopSession() }) {
                            Label("Stop AR Session", systemImage: "stop.circle")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    } else {
                        Button(action: { captureManager.stopCapture() }) {
                            Label("Stop Capture (\(captureManager.frameCount) frames)", systemImage: "stop.circle.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)
                    }
                }
            }
            .padding()
            .navigationTitle("OpenBene LiDAR")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var trackingColor: Color {
        switch captureManager.trackingState {
        case .normal:
            return .green
        case .limited:
            return .yellow
        case .notAvailable:
            return .red
        }
    }
}
