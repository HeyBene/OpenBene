import SwiftUI
import OpenBeneRobot

struct DrivePad: View {
    @ObservedObject var robot: OpenBotLink
    @ObservedObject var drive: DriveController
    var onEnableKeyboard: () -> Void

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader(
                    title: "键盘操控",
                    subtitle: "按住移动，松开停车 · 支持蓝牙键盘",
                    icon: "keyboard"
                )

                HStack(spacing: 8) {
                    KeyButton(key: .arcLeft, drive: drive)
                    KeyButton(key: .forward, drive: drive)
                    KeyButton(key: .arcRight, drive: drive)
                }

                HStack(spacing: 8) {
                    KeyButton(key: .turnLeft, drive: drive)
                    KeyButton(key: .reverse, drive: drive)
                    KeyButton(key: .turnRight, drive: drive)
                }

                Button {
                    drive.releaseAll()
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 13, weight: .bold))
                        Text("停车")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(Theme.danger.opacity(0.1))
                    .foregroundStyle(Theme.danger)
                    .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                }
                .buttonStyle(.plain)

                VStack(spacing: 10) {
                    slider(title: "前进速度", value: $drive.speedPercent, range: 10...100)
                    slider(title: "转向力度", value: $drive.turnPercent, range: 10...100)
                }

                HStack {
                    Text("当前指令")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.secondaryText)
                    Spacer()
                    Text(commandText)
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(drive.isDriving ? Theme.accent : Theme.secondaryText)
                }

                Button {
                    onEnableKeyboard()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "keyboard.badge.ellipsis")
                            .font(.system(size: 12, weight: .semibold))
                        Text("启用蓝牙键盘控制")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background(Theme.softAccent)
                    .foregroundStyle(Theme.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)

                if !robot.isConnected {
                    Text("先在上方连接 OpenBot，才能驱动小车。")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.amber)
                }
            }
        }
    }

    private var commandText: String {
        let command = drive.lastCommand
        return "\(command.label)  L\(command.left) R\(command.right)"
    }

    private func slider(title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(title)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.secondaryText)
                Spacer()
                Text("\(Int(value.wrappedValue))%")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(Theme.primaryText)
            }
            Slider(value: value, in: range, step: 1)
                .tint(Theme.accent)
        }
    }
}

/// A square key that fires on press and stops on release.
struct KeyButton: View {
    let key: DriveKey
    @ObservedObject var drive: DriveController

    @State private var isPressed = false

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: key.symbol)
                .font(.system(size: 17, weight: .semibold))
            Text(key.rawValue.uppercased())
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .opacity(0.65)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 54)
        .background(isPressed ? Theme.accent : Theme.card)
        .foregroundStyle(isPressed ? Color.white : Theme.primaryText)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(isPressed ? Theme.accent : Theme.border, lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard !isPressed else { return }
                    isPressed = true
                    drive.press(key)
                }
                .onEnded { _ in
                    isPressed = false
                    drive.release(key.rawValue)
                }
        )
        .accessibilityLabel(key.label)
    }
}
