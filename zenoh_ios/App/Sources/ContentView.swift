import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var link: ZenohLink
    @Environment(\.scenePhase) private var scenePhase
    @State private var keyboardFocusToken = 0

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                header

                ZenohCard(link: link)
                OpenBotCard(robot: link.robot)
                DrivePad(robot: link.robot, drive: link.drive) {
                    keyboardFocusToken += 1
                }

                Text("提示：接上蓝牙键盘后，W / A / S / D 直接驱动小车；松开按键即停车。")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
                    .padding(.bottom, 10)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
        .background(Theme.background.ignoresSafeArea())
        .scrollDismissesKeyboard(.interactively)
        .overlay(alignment: .topLeading) {
            HardwareKeyboardView(
                onPress: { link.drive.press($0) },
                onRelease: { link.drive.release($0) },
                focusToken: keyboardFocusToken
            )
            .frame(width: 0, height: 0)
        }
        .onChange(of: scenePhase) { phase in
            if phase != .active { link.drive.releaseAll() }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("OpenBene")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.primaryText)
                Spacer()
                Text("Zenoh · BLE")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.secondaryText)
            }

            HStack(spacing: 10) {
                StatusChip(
                    title: "电脑",
                    value: link.connected ? "已连接" : "未连接",
                    tint: Theme.accent,
                    isOn: link.connected
                )
                StatusChip(
                    title: "小车",
                    value: link.robot.isConnected ? (link.robot.connectedName ?? "已连接") : "未连接",
                    tint: Theme.teal,
                    isOn: link.robot.isConnected
                )
            }
        }
        .padding(.top, 6)
    }
}

// MARK: - Zenoh / PC

struct ZenohCard: View {
    @ObservedObject var link: ZenohLink

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader(
                    title: "电脑连接",
                    subtitle: "实时上传采集数据，接收远程指令",
                    icon: "display"
                )

                VStack(spacing: 8) {
                    TextField("电脑地址，例如 192.168.1.23:7447", text: $link.endpoint)
                        .keyboardType(.numbersAndPunctuation)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textFieldStyle(.plain)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(Theme.background)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .disabled(link.connected)

                    HStack(spacing: 8) {
                        TextField("机器人 ID", text: $link.robotID)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .textFieldStyle(.plain)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(Theme.background)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .disabled(link.connected)

                        Picker("采集", selection: $link.useARKit) {
                            Text("ARKit").tag(true)
                            Text("合成").tag(false)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 128)
                        .disabled(link.connected)
                    }
                }

                Button {
                    if link.connected { link.disconnect() } else { link.connect() }
                } label: {
                    Text(link.connected ? "断开电脑" : "连接电脑")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(link.connected ? Theme.softAccent : Theme.accent)
                        .foregroundStyle(link.connected ? Theme.accent : .white)
                        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                }
                .buttonStyle(.plain)

                HStack(spacing: 8) {
                    MetricTile(title: "已发送", value: "\(link.framesSent)", unit: "帧")
                    MetricTile(title: "速率", value: String(format: "%.1f", link.megabytes), unit: "MB/s")
                    MetricTile(title: "丢弃", value: "\(link.framesDropped)", unit: "帧",
                               tint: Theme.secondaryText)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(link.captureDetail)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.secondaryText)
                    Text("最近命令：\(link.lastCommand)")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.secondaryText)
                    if let error = link.linkError {
                        Text(error)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Theme.danger)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}
