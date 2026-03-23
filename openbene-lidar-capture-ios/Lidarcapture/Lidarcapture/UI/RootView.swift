import SwiftUI
import ARKit
import UIKit

struct RootView: View {
    @StateObject private var captureManager = CaptureSessionManager()
    @State private var selectedStage = "Capture"
    @State private var shareURL: URL?
    @State private var isSharePresented = false

    private let stages = ["Prepare", "Capture", "Result"]

    var body: some View {
        NavigationView {
            ZStack {
                previewBackground
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    topOverlay
                    Spacer()
                    readinessBar
                    if captureManager.isCapturing {
                        liveCaptureHud
                    }
                    bottomControlPanel
                }
            }
            .navigationBarHidden(true)
        }
        .sheet(isPresented: $isSharePresented) {
            if let shareURL {
                ShareSheet(activityItems: [shareURL])
            }
        }
    }

    private var previewBackground: some View {
        ZStack {
            ARCameraPreview(session: captureManager.arSession)
                .clipShape(RoundedRectangle(cornerRadius: 30))
                .overlay {
                    RoundedRectangle(cornerRadius: 24)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                        .padding(28)
                }
                .overlay(alignment: .center) {
                    if !captureManager.isSessionRunning {
                        previewPlaceholder
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 150)
        }
    }

    private var previewPlaceholder: some View {
        VStack(spacing: 10) {
            Image(systemName: captureManager.captureMode == .manual ? "camera.aperture" : "record.circle")
                .font(.system(size: 52))
                .foregroundColor(.white.opacity(0.88))
            Text(captureManager.captureMode == .manual ? "手动采样预览" : "自动采样预览")
                .font(.headline)
                .foregroundColor(.white.opacity(0.92))
            Text(softHint)
                .font(.footnote)
                .foregroundColor(.white.opacity(0.62))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 36)
        }
        .padding(.vertical, 28)
        .padding(.horizontal, 24)
        .background(Color.black.opacity(0.38))
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    private var topOverlay: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "chevron.down")
                    .font(.headline)
                    .foregroundColor(.white.opacity(0.9))

                Spacer()

                Text("OpenBene LiDAR")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)

                Spacer()

                Text(captureManager.captureMode == .manual ? "手动" : "自动")
                    .font(.caption.weight(.bold))
                    .foregroundColor(.white.opacity(0.9))
            }

            HStack(spacing: 8) {
                compactHudPill(systemImage: trackingSymbol, text: shortTrackingLabel)
                compactHudPill(systemImage: captureManager.depthAvailable ? "cube.transparent" : "photo", text: captureManager.depthAvailable ? "LiDAR" : "RGB")
                compactHudPill(systemImage: "circle.grid.2x2.fill", text: "\(captureManager.frameCount)")
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
    }

    private var liveCaptureHud: some View {
        HStack(spacing: 12) {
            liveStat(title: "帧数", value: "\(captureManager.frameCount)")
            liveStat(title: "深度", value: captureManager.depthAvailable ? "开" : "RGB")
            liveStat(title: "时长", value: captureManager.formattedDuration)
        }
        .padding(.bottom, 14)
    }

    private var readinessBar: some View {
        VStack(spacing: 8) {
            HStack {
                Text(softStatusTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)
                Spacer()
                Text(softStatusTag)
                    .font(.caption2.weight(.bold))
                    .foregroundColor(readinessAccent)
            }

            HStack(spacing: 12) {
                readinessMetric(title: "跟踪", value: shortTrackingLabel)
                readinessMetric(title: "帧数", value: "\(captureManager.frameCount)")
                readinessMetric(title: "深度", value: captureManager.depthAvailable ? "开" : "RGB")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color.black.opacity(0.28))
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
    }

    private var bottomControlPanel: some View {
        VStack(spacing: 14) {
            if let summary = captureManager.lastSessionSummary {
                summaryCard(summary)
            }

            if let outputURL = captureManager.lastSessionDirectoryURL {
                outputLocationCard(outputURL)
            }

            Text(primaryStatusText)
                .font(.headline.weight(.semibold))
                .foregroundColor(.white)

            stageStrip
            captureModeStrip

            HStack(alignment: .center) {
                modeToggleButton(mode: .manual)

                Spacer()

                shutterButton

                Spacer()

                finishButton
            }

            Text(primaryButtonLabel)
                .font(.footnote.weight(.medium))
                .foregroundColor(.white.opacity(0.78))

            Text(captureManager.lastCaptureFeedback)
                .font(.caption)
                .foregroundColor(.white.opacity(0.62))

            DisclosureGroup {
                VStack(spacing: 10) {
                    diagnosticsRow(title: "ARKit", value: DeviceCapabilities.isARWorldTrackingAvailable ? "OK" : "N/A")
                    diagnosticsRow(title: "LiDAR", value: DeviceCapabilities.isLiDARAvailable ? "OK" : "N/A")
                    diagnosticsRow(title: "Tracking", value: captureManager.trackingStateDescription)
                    diagnosticsRow(title: "Workflow", value: workflowLabel)
                    diagnosticsRow(title: "Mode", value: captureManager.captureMode.rawValue)
                    diagnosticsRow(title: "Hint", value: captureManager.statusHint)
                }
                .padding(.top, 8)
            } label: {
                Text("诊断信息")
                    .font(.caption.weight(.medium))
                    .foregroundColor(.white.opacity(0.7))
            }
            .tint(.white)
        }
        .padding(.horizontal, 18)
        .padding(.top, 14)
        .padding(.bottom, 20)
        .background(
            LinearGradient(
                colors: [Color.black.opacity(0.25), Color.black.opacity(0.92)],
                startPoint: .top,
                endPoint: .bottom
            )
            .overlay(alignment: .top) {
                Capsule()
                    .fill(Color.white.opacity(0.16))
                    .frame(width: 42, height: 5)
                    .padding(.top, 8)
            }
        )
    }

    private var stageStrip: some View {
        HStack(spacing: 24) {
            ForEach(stages, id: \.self) { stage in
                Text(stage.uppercased())
                    .font(.caption.weight(selectedStage == stage ? .bold : .medium))
                    .foregroundColor(selectedStage == stage ? .yellow : .white.opacity(stage == "Capture" ? 0.58 : 0.34))
                    .scaleEffect(selectedStage == stage ? 1.02 : 1)
                    .onTapGesture {
                        selectedStage = stage
                    }
            }
        }
    }

    private var captureModeStrip: some View {
        HStack(spacing: 10) {
            captureModeChip(.manual)
            captureModeChip(.auto)
        }
    }

    private var shutterButton: some View {
        Button(action: {
            captureManager.performPrimaryAction()
        }) {
            ZStack {
                Circle()
                    .stroke(Color.white, lineWidth: 5)
                    .frame(width: 84, height: 84)

                Circle()
                    .fill(primaryButtonFill)
                    .frame(width: 68, height: 68)
                    .overlay {
                        if captureManager.captureMode == .manual, captureManager.isCapturing {
                            Image(systemName: "camera.fill")
                                .font(.system(size: 22, weight: .bold))
                                .foregroundColor(.black)
                        } else if captureManager.isCapturing {
                            RoundedRectangle(cornerRadius: 9)
                                .fill(Color.white)
                                .frame(width: 26, height: 26)
                        }
                    }
            }
        }
    }

    private var finishButton: some View {
        Button(action: {
            captureManager.finishCaptureSession()
        }) {
            VStack(spacing: 6) {
                Image(systemName: "stop.circle.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 42, height: 42)
                    .background(Color.white.opacity(0.10))
                    .clipShape(Circle())
                Text("结束")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.68))
            }
        }
        .disabled(!captureManager.isSessionRunning)
        .opacity(captureManager.isSessionRunning ? 1 : 0.5)
    }

    private func captureModeChip(_ mode: CaptureMode) -> some View {
        Text(mode == .manual ? "手动" : "自动")
            .font(.caption.weight(captureManager.captureMode == mode ? .bold : .medium))
            .foregroundColor(captureManager.captureMode == mode ? .black : .white.opacity(0.75))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(captureManager.captureMode == mode ? Color.yellow : Color.white.opacity(0.08))
            .clipShape(Capsule())
            .onTapGesture {
                captureManager.setCaptureMode(mode)
            }
    }

    private func modeToggleButton(mode: CaptureMode) -> some View {
        Button(action: {
            captureManager.setCaptureMode(mode)
        }) {
            VStack(spacing: 6) {
                Image(systemName: mode == .manual ? "hand.tap.fill" : "waveform.path.badge.plus")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(captureManager.captureMode == mode ? .black : .white)
                    .frame(width: 42, height: 42)
                    .background(captureManager.captureMode == mode ? Color.yellow : Color.white.opacity(0.10))
                    .clipShape(Circle())
                Text(mode == .manual ? "手动" : "自动")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.68))
            }
        }
    }

    private func summaryCard(_ summary: CaptureSessionSummary) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("最近一次")
                .font(.caption.weight(.medium))
                .foregroundColor(.white.opacity(0.65))

            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(summary.sessionName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white)
                    Text(summary.qualityHint)
                        .font(.footnote)
                        .foregroundColor(.white.opacity(0.78))
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text("\(summary.frameCount) 帧")
                    Text(summary.depthRecorded ? "深度开启" : "仅 RGB")
                    Text(format(duration: summary.duration))
                }
                .font(.caption.monospacedDigit())
                .foregroundColor(.white.opacity(0.78))
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color.white.opacity(0.08))
        )
    }

    private func outputLocationCard(_ url: URL) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("数据位置")
                .font(.caption.weight(.medium))
                .foregroundColor(.white.opacity(0.65))

            Text(url.lastPathComponent)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.white)

            Text(url.path)
                .font(.caption)
                .foregroundColor(.white.opacity(0.72))
                .lineLimit(3)

            HStack(spacing: 10) {
                Button("分享导出") {
                    shareURL = url
                    isSharePresented = true
                }
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.yellow)
                .foregroundColor(.black)
                .clipShape(Capsule())

                Text("结束后可分享到“文件”或 AirDrop")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.62))
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color.white.opacity(0.08))
        )
    }

    private func diagnosticsRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .foregroundColor(.white.opacity(0.68))
        }
        .font(.footnote)
        .foregroundColor(.white)
    }

    private func compactHudPill(systemImage: String, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.caption)
            Text(text)
                .lineLimit(1)
        }
        .font(.caption.weight(.medium))
        .foregroundColor(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color.black.opacity(0.35))
        .clipShape(Capsule())
    }

    private func liveStat(title: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption2)
                .foregroundColor(.white.opacity(0.6))
            Text(value)
                .font(.footnote.monospacedDigit())
                .foregroundColor(.white)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.35))
        .clipShape(Capsule())
    }

    private func readinessMetric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2)
                .foregroundColor(.white.opacity(0.55))
            Text(value)
                .font(.caption.weight(.semibold))
                .foregroundColor(.white)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var primaryButtonFill: Color {
        if captureManager.captureMode == .manual {
            return .white
        }
        return captureManager.isCapturing ? .red : .white
    }

    private var primaryButtonLabel: String {
        switch captureManager.workflowPhase {
        case .idle, .unsupported, .error:
            return "主按钮：启动会话"
        case .preparing, .ready:
            return captureManager.captureMode == .manual ? "主按钮：采一张" : "主按钮：开始自动采样"
        case .capturing:
            return captureManager.captureMode == .manual ? "主按钮：继续采一张 · 右侧：结束" : "主按钮：停止自动采样"
        case .completed:
            return "主按钮：开始新一轮"
        }
    }

    private var primaryStatusText: String {
        switch captureManager.workflowPhase {
        case .unsupported:
            return "当前设备暂时不适合这一路径"
        case .idle:
            return "准备开始"
        case .preparing:
            return "等待跟踪稳定"
        case .ready:
            return captureManager.captureMode == .manual ? "可以手动采样" : "可以开始自动采样"
        case .capturing:
            return captureManager.captureMode == .manual ? "手动采样中" : "自动采样中"
        case .completed:
            return "采集完成，先看结果"
        case .error:
            return "当前会话需要重新开始"
        }
    }

    private var workflowLabel: String {
        switch captureManager.workflowPhase {
        case .unsupported:
            return "受限"
        case .idle:
            return "待开始"
        case .preparing:
            return "准备中"
        case .ready:
            return "可采样"
        case .capturing:
            return "采集中"
        case .completed:
            return "已完成"
        case .error:
            return "异常"
        }
    }

    private var softStatusTitle: String {
        switch captureManager.workflowPhase {
        case .unsupported:
            return "当前设备不支持 AR 采集"
        case .idle:
            return "先启动会话，再开始采样"
        case .preparing:
            return "跟踪还在建立中"
        case .ready:
            return captureManager.captureMode == .manual ? "已就绪，可以按主按钮采样" : "已就绪，可以开始自动采样"
        case .capturing:
            return captureManager.captureMode == .manual ? "会话已开始，可继续按主按钮采样" : "自动采样已开始"
        case .completed:
            return "本轮已结束，建议先看结果"
        case .error:
            return "当前会话出错，建议重新开始"
        }
    }

    private var softStatusTag: String {
        switch captureManager.workflowPhase {
        case .unsupported:
            return "当前不可用"
        case .idle:
            return "未开始"
        case .preparing:
            return "等待稳定"
        case .ready:
            return "已就绪"
        case .capturing:
            return captureManager.captureMode == .manual ? "手动模式" : "自动模式"
        case .completed:
            return "可查看结果"
        case .error:
            return "请重试"
        }
    }

    private var softHint: String {
        switch captureManager.workflowPhase {
        case .unsupported:
            return "需要支持 AR 世界跟踪的设备"
        case .idle:
            return "先启动会话，再进入采样"
        case .preparing:
            return "缓慢移动设备，等待跟踪稳定"
        case .ready:
            return captureManager.captureMode == .manual ? "对准目标后按主按钮采一张" : "开始后系统会自动按质量策略收帧"
        case .capturing:
            return captureManager.captureMode == .manual ? captureManager.lastCaptureFeedback : "继续环绕目标，保持平稳移动"
        case .completed:
            return captureManager.lastSessionSummary?.qualityHint ?? "请检查结果是否满足重建验证"
        case .error:
            return "结束当前会话后重新开始"
        }
    }

    private var readinessAccent: Color {
        switch captureManager.workflowPhase {
        case .unsupported, .error:
            return .orange
        case .idle, .preparing:
            return .yellow
        case .ready, .completed:
            return .green
        case .capturing:
            return .orange
        }
    }

    private var shortTrackingLabel: String {
        switch captureManager.trackingState {
        case .normal:
            return "正常"
        case .limited:
            return "受限"
        case .notAvailable:
            return "不可用"
        }
    }

    private var trackingSymbol: String {
        switch captureManager.trackingState {
        case .normal:
            return "dot.radiowaves.left.and.right"
        case .limited:
            return "exclamationmark.triangle"
        case .notAvailable:
            return "xmark.octagon"
        }
    }

    private func format(duration: TimeInterval) -> String {
        let totalSeconds = Int(duration)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

private struct ARCameraPreview: UIViewRepresentable {
    let session: ARSession

    func makeUIView(context: Context) -> ARSCNView {
        let view = ARSCNView(frame: .zero)
        view.automaticallyUpdatesLighting = true
        view.rendersContinuously = true
        view.scene = SCNScene()
        view.delegate = context.coordinator
        view.session = session
        return view
    }

    func updateUIView(_ uiView: ARSCNView, context: Context) {
        if uiView.session !== session {
            uiView.session = session
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator: NSObject, ARSCNViewDelegate {}
}

private struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
