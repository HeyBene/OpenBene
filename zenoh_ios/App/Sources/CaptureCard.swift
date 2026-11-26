import SwiftUI

/// Capture rate and sensor selection; changes take effect immediately.
struct CaptureCard: View {
    @ObservedObject var link: ZenohLink

    private let rates: [Double] = [5, 10, 15, 30]
    private let widths: [Double] = [640, 960, 1280]

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader(
                    title: "采集设置",
                    subtitle: "频率与传感器可随时调整",
                    icon: "slider.horizontal.3"
                )

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("帧率")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.secondaryText)
                        Spacer()
                        Text("\(Int(link.settings.fps)) fps")
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Theme.primaryText)
                    }
                    Picker("帧率", selection: Binding(
                        get: { Int(link.settings.fps) },
                        set: { link.settings.fps = Double($0) }
                    )) {
                        ForEach(rates, id: \.self) { rate in
                            Text("\(Int(rate))").tag(Int(rate))
                        }
                    }
                    .pickerStyle(.segmented)
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("画面宽度")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.secondaryText)
                        Spacer()
                        Text("\(Int(link.settings.maxWidth)) px")
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Theme.primaryText)
                    }
                    Picker("画面宽度", selection: $link.settings.maxWidth) {
                        ForEach(widths, id: \.self) { width in
                            Text("\(Int(width))").tag(width)
                        }
                    }
                    .pickerStyle(.segmented)
                    .disabled(!link.settings.includeRGB)
                }

                VStack(spacing: 2) {
                    toggleRow("RGB 画面", detail: "JPEG 主图", isOn: $link.settings.includeRGB)
                    toggleRow("深度图", detail: "LiDAR 16 位毫米", isOn: $link.settings.includeDepth)
                    toggleRow("置信度", detail: "0 / 1 / 2 三档", isOn: $link.settings.includeConfidence)
                    toggleRow("位姿", detail: "camera-to-world + 内参", isOn: $link.settings.includePose)
                    toggleRow("IMU", detail: "加速度 + 角速度 @50Hz", isOn: $link.settings.includeIMU)
                }

                Text("帧率与通信频率一致；IMU 以 50 Hz 采样、随遥测一起发送。"
                     + "预估 \(estimate) MB/s。实际 \(String(format: "%.1f", link.captureFPS)) fps，"
                     + "编码 \(String(format: "%.1f", link.encodeMs)) ms/帧。"
                     + (link.sourceFPS > 0 ? "ARKit 原始 \(String(format: "%.1f", link.sourceFPS)) fps。" : ""))
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.secondaryText)

                if !link.planeMs.isEmpty {
                    Text(planeDetail)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Theme.secondaryText)
                }

                Text("编码基准：\(link.encoderBench)")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.secondaryText)
            }
        }
    }

    private var planeDetail: String {
        let rgb = link.planeMs["rgb"] ?? 0
        let depth = link.planeMs["depth"] ?? 0
        let confidence = link.planeMs["confidence"] ?? 0
        let convert = link.planeMs["convert"] ?? 0
        return String(format: "RGB %.1f · 转换 %.1f · 深度 %.1f · 置信度 %.1f ms", rgb, convert, depth, confidence)
    }

    private var estimate: String {
        var bytesPerFrame = 0.0
        if link.settings.includeRGB {
            bytesPerFrame += 60_000 * link.settings.maxWidth / 1280
        }
        if link.settings.includeDepth { bytesPerFrame += 12_000 }
        if link.settings.includeConfidence { bytesPerFrame += 6_000 }
        if link.settings.includePose { bytesPerFrame += 100 }
        return String(format: "%.1f", bytesPerFrame * link.settings.fps / 1_000_000)
    }

    private func toggleRow(_ title: String, detail: String, isOn: Binding<Bool>) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.primaryText)
                Text(detail)
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.secondaryText)
            }
            Spacer()
            Toggle("", isOn: isOn)
                .labelsHidden()
                .tint(Theme.accent)
        }
        .padding(.vertical, 6)
    }
}
