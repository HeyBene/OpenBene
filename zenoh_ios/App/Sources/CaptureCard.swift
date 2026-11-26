import SwiftUI

/// Capture rate and sensor selection; changes take effect immediately.
struct CaptureCard: View {
    @ObservedObject var link: ZenohLink

    private let rates: [Double] = [5, 10, 15, 30]

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

                VStack(spacing: 2) {
                    toggleRow("RGB 画面", detail: "JPEG 主图", isOn: $link.settings.includeRGB)
                    toggleRow("深度图", detail: "LiDAR 16 位毫米", isOn: $link.settings.includeDepth)
                    toggleRow("置信度", detail: "0 / 1 / 2 三档", isOn: $link.settings.includeConfidence)
                    toggleRow("位姿", detail: "camera-to-world + 内参", isOn: $link.settings.includePose)
                    toggleRow("IMU", detail: "加速度 + 角速度 @50Hz", isOn: $link.settings.includeIMU)
                }

                Text("帧率与通信频率一致；IMU 以 50 Hz 采样、随遥测一起发送。发送速率约 \(estimate) MB/s。")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.secondaryText)
            }
        }
    }

    private var estimate: String {
        var bytesPerFrame = 0.0
        if link.settings.includeRGB { bytesPerFrame += 60_000 }
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
