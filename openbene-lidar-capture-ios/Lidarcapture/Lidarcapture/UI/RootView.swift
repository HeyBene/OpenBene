import SwiftUI
import ARKit
import UIKit

struct RootView: View {
    @StateObject private var captureManager = CaptureSessionManager()
    @StateObject private var uploadCoordinator = CaptureUploadCoordinator(uploadClient: WebSocketUploadClient())
    @AppStorage("capture.receiverURL") private var receiverURLString = "ws://127.0.0.1:8765"
    @AppStorage("capture.sessionMode") private var sessionModeRawValue = CaptureSessionUploadMode.mapping.rawValue
    @State private var shareURL: URL?
    @State private var isSharePresented = false
    @State private var isConnectionConfigExpanded = false
    @State private var receiverValidationMessage: String?


    var body: some View {
        NavigationView {
            ZStack {
                previewBackground
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    topOverlay
                    Spacer()
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
        .onAppear {
            connectToConfiguredReceiver()
            captureManager.onFrameAccepted = { record in
                uploadCoordinator.sendFrame(record)
            }
            captureManager.onCaptureStarted = { sessionName, depthEnabled in
                uploadCoordinator.beginSession(
                    sessionName: sessionName,
                    mode: currentSessionMode,
                    depthEnabled: depthEnabled
                )
            }
            captureManager.onCaptureFinished = { manifest, pointCloud in
                uploadCoordinator.finishSession(manifest: manifest ?? Data(), pointCloud: pointCloud)
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

    private var currentSessionMode: CaptureSessionUploadMode {
        CaptureSessionUploadMode(rawValue: sessionModeRawValue) ?? .mapping
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

                Text(currentSessionMode == .mapping ? "建图" : "定位")
                    .font(.caption.weight(.bold))
                    .foregroundColor(.yellow)
            }

            HStack(spacing: 8) {
                compactHudPill(systemImage: trackingSymbol, text: shortTrackingLabel)
                compactHudPill(systemImage: captureManager.depthAvailable ? "cube.transparent" : "photo", text: captureManager.depthAvailable ? "LiDAR" : "RGB")
                compactHudPill(systemImage: uploadCoordinator.isConnected ? "antenna.radiowaves.left.and.right" : "wifi.slash", text: uploadCoordinator.isConnected ? "已连接" : "未连接")
                compactHudPill(systemImage: uploadCoordinator.supportsPointCloudUpload ? "point.3.connected.trianglepath.dotted" : "point.3.filled.connected.trianglepath.dotted", text: uploadCoordinator.supportsPointCloudUpload ? "点云" : "无点云")
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
    }

    private var liveCaptureHud: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                liveStat(title: "帧数", value: "\(captureManager.frameCount)")
                liveStat(title: "深度", value: captureManager.depthAvailable ? "开" : "RGB")
                liveStat(title: "时长", value: captureManager.formattedDuration)
            }

            qualityAdvisoryPill
        }
        .padding(.bottom, 14)
    }



    private var bottomControlPanel: some View {
        VStack(spacing: 14) {
            if let summary = captureManager.lastSessionSummary {
                summaryCard(summary)
            }

            if let outputURL = captureManager.lastSessionDirectoryURL {
                outputLocationCard(outputURL, summary: captureManager.lastSessionSummary)
            }

            Text(primaryStatusText)
                .font(.headline.weight(.semibold))
                .foregroundColor(.white)

            Text(softStatusTitle)
                .font(.caption)
                .foregroundColor(.white.opacity(0.7))
                .multilineTextAlignment(.center)

            modeAndSessionStrip

            HStack(alignment: .center) {
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

            connectionCard

            DisclosureGroup {
                VStack(spacing: 10) {
                    diagnosticsRow(title: "ARKit", value: DeviceCapabilities.isARWorldTrackingAvailable ? "OK" : "N/A")
                    diagnosticsRow(title: "LiDAR", value: DeviceCapabilities.isLiDARAvailable ? "OK" : "N/A")
                    diagnosticsRow(title: "Tracking", value: captureManager.trackingStateDescription)
                    diagnosticsRow(title: "Advisory", value: captureManager.liveAdvisoryText)
                    diagnosticsRow(title: "Workflow", value: workflowLabel)
                    diagnosticsRow(title: "Session", value: currentSessionMode == .mapping ? "建图" : "定位")
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

    private var modeAndSessionStrip: some View {
        HStack(spacing: 10) {
            sessionModeChip(.mapping, title: "建图")
            sessionModeChip(.localization, title: "定位")
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

    private func sessionModeChip(_ mode: CaptureSessionUploadMode, title: String) -> some View {
        Text(title)
            .font(.caption.weight(currentSessionMode == mode ? .bold : .medium))
            .foregroundColor(currentSessionMode == mode ? .black : .white.opacity(0.75))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(currentSessionMode == mode ? Color.green : Color.white.opacity(0.08))
            .clipShape(Capsule())
            .onTapGesture {
                sessionModeRawValue = mode.rawValue
            }
    }


    private var connectionCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isConnectionConfigExpanded.toggle()
                }
            }) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("实时连接")
                            .font(.caption.weight(.medium))
                            .foregroundColor(.white.opacity(0.65))
                        Text(uploadCoordinator.statusMessage)
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.white)
                        if let receiverURL = uploadCoordinator.receiverURL {
                            Text(receiverURL.absoluteString)
                                .font(.caption2.monospaced())
                                .foregroundColor(.white.opacity(0.62))
                                .lineLimit(1)
                        }
                    }
                    Spacer()
                    Text(uploadCoordinator.isConnected ? "在线" : "离线")
                        .font(.caption.weight(.bold))
                        .foregroundColor(uploadCoordinator.isConnected ? .green : .orange)
                    Image(systemName: isConnectionConfigExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.bold))
                        .foregroundColor(.white.opacity(0.7))
                }
            }

            if isConnectionConfigExpanded {
                VStack(alignment: .leading, spacing: 10) {
                    if let receiverValidationMessage {
                        Text(receiverValidationMessage)
                            .font(.caption)
                            .foregroundColor(.orange)
                    }

                    TextField("ws://192.168.x.x:8765", text: $receiverURLString)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.caption.monospaced())
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(Color.white.opacity(0.08))
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))

                    Text("先在 PC 上启动 receiver，再连接同一 Wi‑Fi 下的 ws://<PC-IP>:8765")
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.62))

                    if let receiverURL = uploadCoordinator.receiverURL {
                        Text("当前目标：\(receiverURL.absoluteString)")
                            .font(.caption2.monospaced())
                            .foregroundColor(.white.opacity(0.72))
                            .lineLimit(2)
                    }

                    HStack(spacing: 10) {
                        Button(uploadCoordinator.isConnected ? "重新连接" : "连接") {
                            connectToConfiguredReceiver()
                        }
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.yellow)
                        .foregroundColor(.black)
                        .clipShape(Capsule())

                        Button("断开") {
                            uploadCoordinator.disconnect()
                        }
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.white.opacity(0.12))
                        .foregroundColor(.white)
                        .clipShape(Capsule())
                    }
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color.white.opacity(0.08))
        )
    }

    private var qualityAdvisoryPill: some View {
        Text(captureManager.liveAdvisoryText)
            .font(.caption.weight(.semibold))
            .foregroundColor(advisoryForeground)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(advisoryBackground)
            .clipShape(Capsule())
    }

    private func summaryCard(_ summary: CaptureSessionSummary) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("最近一次")
                .font(.caption.weight(.medium))
                .foregroundColor(.white.opacity(0.65))

            qualityGateBanner(summary)

            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(summary.sessionName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white)
                    Text(summary.qualityHint)
                        .font(.footnote)
                        .foregroundColor(.white.opacity(0.78))
                    if let pointCloudStatus = captureManager.pointCloudUploadStatus {
                        Text(pointCloudStatus)
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.62))
                    }
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

            qualityReportGrid(summary.qualityReport)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color.white.opacity(0.08))
        )
    }

    private func qualityGateBanner(_ summary: CaptureSessionSummary) -> some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(summary.gateTitle)
                    .font(.caption.weight(.bold))
                    .foregroundColor(qualityGateForeground(summary.qualityReport.gateDecision))
                Text(summary.gateHint)
                    .font(.caption2)
                    .foregroundColor(qualityGateForeground(summary.qualityReport.gateDecision).opacity(0.85))
            }

            Spacer()

            Text(gateBadgeText(summary.qualityReport.gateDecision))
                .font(.caption2.weight(.bold))
                .foregroundColor(qualityGateForeground(summary.qualityReport.gateDecision))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(qualityGateForeground(summary.qualityReport.gateDecision).opacity(0.16))
                .clipShape(Capsule())
        }
        .padding(12)
        .background(qualityGateBackground(summary.qualityReport.gateDecision))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func qualityReportGrid(_ report: CaptureQualityReport) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                qualityMetric(title: "正常跟踪", value: String(format: "%.0f%%", report.trackingNormalRatio * 100))
                qualityMetric(title: "平移", value: String(format: "%.2fm", report.maxAdjacentTranslationJumpMeters))
                qualityMetric(title: "旋转", value: String(format: "%.1f°", report.maxAdjacentRotationJumpDegrees))
            }

            HStack(spacing: 10) {
                qualityMetric(title: "可疑", value: "\(report.suspiciousJumpCount)")
                qualityMetric(title: "严重", value: "\(report.severeJumpCount)")
                qualityMetric(title: "有效帧", value: "\(report.acceptedFrameCount)")
            }

            Text(report.recommendation)
                .font(.caption.weight(.semibold))
                .foregroundColor(.white)

            Text(report.gateDecision.actionHint)
                .font(.caption2)
                .foregroundColor(.white.opacity(0.72))
        }
    }

    private func qualityMetric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2)
                .foregroundColor(.white.opacity(0.55))
            Text(value)
                .font(.caption.weight(.semibold))
                .foregroundColor(.white)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func outputLocationCard(_ url: URL, summary: CaptureSessionSummary?) -> some View {
        let pointCloudURL = url.appendingPathComponent("fused_pointcloud.ply")
        let pointCloudExists = FileManager.default.fileExists(atPath: pointCloudURL.path)

        return VStack(alignment: .leading, spacing: 8) {
            Text("数据位置")
                .font(.caption.weight(.medium))
                .foregroundColor(.white.opacity(0.65))

            Text(url.lastPathComponent)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.white)

            if let summary {
                Text("\(summary.gateTitle) · \(summary.qualityReport.recommendation)")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.78))
            }

            Text(pointCloudExists ? "点云文件：fused_pointcloud.ply" : "点云文件：未生成")
                .font(.caption2.monospaced())
                .foregroundColor(.white.opacity(0.62))

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

                Text("可导出到“文件”或 AirDrop")
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

    private var advisoryForeground: Color {
        switch captureManager.liveAdvisoryLevel {
        case .good:
            return .black
        case .holdStill:
            return .black
        case .trackingUnstable, .movingTooFast:
            return .white
        }
    }

    private var advisoryBackground: Color {
        switch captureManager.liveAdvisoryLevel {
        case .good:
            return .green
        case .holdStill:
            return .yellow
        case .trackingUnstable:
            return .orange
        case .movingTooFast:
            return .red
        }
    }

    private func qualityGateBackground(_ decision: CaptureQualityGateDecision) -> Color {
        switch decision {
        case .keep:
            return Color.green.opacity(0.18)
        case .retry:
            return Color.yellow.opacity(0.18)
        case .reject:
            return Color.red.opacity(0.2)
        }
    }

    private func qualityGateForeground(_ decision: CaptureQualityGateDecision) -> Color {
        switch decision {
        case .keep:
            return Color.green
        case .retry:
            return Color.yellow
        case .reject:
            return Color.red
        }
    }

    private func gateBadgeText(_ decision: CaptureQualityGateDecision) -> String {
        switch decision {
        case .keep:
            return "KEEP"
        case .retry:
            return "RETRY"
        case .reject:
            return "REJECT"
        }
    }

    private var primaryButtonFill: Color {
        if captureManager.captureMode == .manual {
            return .white
        }
        return captureManager.isCapturing ? .red : .white
    }

    private var primaryButtonLabel: String {
        if currentSessionMode == .localization {
            switch captureManager.workflowPhase {
            case .idle, .unsupported, .error:
                return "主按钮：启动定位会话"
            case .preparing, .ready:
                return captureManager.captureMode == .manual ? "主按钮：发送一帧定位样本" : "主按钮：开始连续发送定位流"
            case .capturing:
                return captureManager.captureMode == .manual ? "主按钮：继续发送定位样本 · 右侧：结束" : "主按钮：停止连续定位流"
            case .completed:
                return "主按钮：开始新的定位会话"
            }
        }
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
        if currentSessionMode == .localization {
            if uploadCoordinator.isConnected {
                return "定位模式已就绪"
            }
            return "定位模式等待连接接收端"
        }
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
        if currentSessionMode == .localization {
            return uploadCoordinator.isConnected ? "定位流将发送到当前接收端" : "先连接接收端，再开始定位流"
        }
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
        if currentSessionMode == .localization {
            return uploadCoordinator.isConnected ? "定位就绪" : "等待连接"
        }
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
        if currentSessionMode == .localization {
            return "连接后将持续发送定位流到 PC，后续用于地图内重定位"
        }
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
        if currentSessionMode == .localization {
            return uploadCoordinator.isConnected ? .blue : .yellow
        }
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

    private func connectToConfiguredReceiver() {
        let trimmed = receiverURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              let scheme = url.scheme,
              scheme == "ws" || scheme == "wss",
              url.host != nil else {
            receiverValidationMessage = "地址格式应为 ws://主机:端口"
            return
        }
        receiverValidationMessage = nil
        uploadCoordinator.connect(to: url)
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
