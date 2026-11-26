import SwiftUI
import OpenBeneRobot

struct OpenBotCard: View {
    @ObservedObject var robot: OpenBotLink

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    SectionHeader(
                        title: "OpenBot 小车",
                        subtitle: robot.isConnected ? (robot.connectedName ?? "已连接") : robot.bluetoothStateText,
                        icon: "car.side"
                    )
                    Spacer()
                    Button {
                        if robot.isConnected {
                            robot.disconnect()
                        } else if robot.isScanning {
                            robot.stopScanning()
                        } else {
                            robot.startScanning()
                        }
                    } label: {
                        Text(robot.isConnected ? "断开" : (robot.isScanning ? "停止扫描" : "扫描"))
                            .font(.system(size: 12, weight: .semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(robot.isConnected ? Theme.softAccent : Theme.softTeal)
                            .foregroundStyle(robot.isConnected ? Theme.accent : Theme.teal)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }

                if robot.isConnected {
                    HStack(spacing: 8) {
                        MetricTile(
                            title: "电压",
                            value: robot.voltage.map { String(format: "%.1f", $0) } ?? "—",
                            unit: "V",
                            tint: Theme.teal
                        )
                        MetricTile(
                            title: "声呐",
                            value: robot.sonarCm.map(String.init) ?? "—",
                            unit: "cm",
                            tint: Theme.teal
                        )
                    }
                    HStack(spacing: 8) {
                        MetricTile(
                            title: "左轮",
                            value: robot.leftRPM.map { String(format: "%.0f", $0) } ?? "—",
                            unit: "rpm",
                            tint: Theme.accent
                        )
                        MetricTile(
                            title: "右轮",
                            value: robot.rightRPM.map { String(format: "%.0f", $0) } ?? "—",
                            unit: "rpm",
                            tint: Theme.accent
                        )
                    }
                    if let bumper = robot.bumper {
                        Text("碰撞传感器：\(bumper)")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Theme.amber)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        if robot.devices.isEmpty {
                            Text(robot.isScanning ? "正在扫描附近的 BLE 设备…" : "点右上角「扫描」查找 OpenBot")
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.secondaryText)
                        } else {
                            ForEach(robot.devices) { device in
                                HStack {
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(device.name)
                                            .font(.system(size: 13, weight: .medium))
                                            .foregroundStyle(Theme.primaryText)
                                        Text("信号 \(device.rssi) dBm")
                                            .font(.system(size: 10))
                                            .foregroundStyle(Theme.secondaryText)
                                    }
                                    Spacer()
                                    Button("连接") { robot.connect(device) }
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(Theme.accent)
                                        .buttonStyle(.plain)
                                }
                                .padding(.vertical, 6)
                                Divider().overlay(Theme.border)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                if let error = robot.lastError {
                    Text(error)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.danger)
                }
            }
        }
    }
}
