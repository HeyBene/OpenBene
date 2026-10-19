import SwiftUI
import OpenBotNavKit

struct FollowControls: View {
    @ObservedObject var driver: PersonFollowDriver
    var title = "视觉跟随"
    var disabled = false
    var onPwm: () -> Void
    @State private var showGates = false
    @State private var showDetails = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(driver.active ? title + "中" : title).font(.headline)
                Spacer()
                Text(driver.connected ? "底盘已连接" : "底盘未连接").font(.caption)
            }
            Text(driver.status).font(.caption)
            if !driver.hasRobot {
                Text("请先在首页开启蓝牙并选中底盘，再进入采集；仍可手动采集。")
                    .font(.caption).foregroundColor(.orange)
            }
            HStack {
                Button("5秒后跟随") { driver.startFollowing() }
                    .accessibilityIdentifier("follow.start")
                    .buttonStyle(.borderedProminent).disabled(disabled || !driver.available || driver.active || driver.pending)
                Button("停车") { driver.stop() }.buttonStyle(.bordered).tint(.red).accessibilityIdentifier("follow.stop")
                Button("PWM") { onPwm() }.buttonStyle(.bordered).disabled(disabled)
                Button("更多") { driver.stop(); showGates = true }
                    .buttonStyle(.bordered).disabled(disabled)
            }.font(.caption)
            Toggle("接近人时停车", isOn: Binding(get: { driver.testOptions.stopWhenNear }, set: { value in
                var options = driver.testOptions; options.stopWhenNear = value; driver.applyTestOptions(options)
            })).font(.caption).disabled(disabled).accessibilityIdentifier("follow.proximityStop")
            if driver.testOptions.stopWhenNear {
                HStack {
                    Text(String(format: "停车距离 %.1f m", driver.testOptions.stopDistanceM)).font(.caption2)
                    Slider(value: Binding(get: { driver.testOptions.stopDistanceM }, set: { value in
                        var options = driver.testOptions; options.stopDistanceM = value; driver.applyTestOptions(options)
                    }), in: 0.5...2.0, step: 0.1).disabled(disabled)
                }
                Text(driver.scaleText).font(.caption2)
                Text(String(format: "远于 %.1f m 并稳定后继续；距离未知时禁止前进。", driver.testOptions.stopDistanceM + 0.2)).font(.caption2)
            } else { Text("近人停车已关闭，会持续向目标前进。").font(.caption).foregroundColor(.orange) }
            DisclosureGroup("检测与控车详情", isExpanded: $showDetails) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("PWM：直行 \(driver.pwm.drivePwm) · 左转 \(driver.pwm.leftTurnPwm) · 右转 \(driver.pwm.rightTurnPwm)")
                    Text(driver.detectionText)
                    Text(driver.targetText)
                    Text(driver.gateText).foregroundColor(.orange)
                    Text("指令 " + driver.frameText + " · " + driver.bleText)
                }.font(.caption2)
            }.font(.caption)
            Text("需手动开始；丢人先停、重新看到后继续。修改设置或记录节点后需重新开始。")
                .font(.caption2)
        }
        .sheet(isPresented: $showGates) { FollowGateSettings(driver: driver) }
    }
}

private struct FollowGateSettings: View {
    @ObservedObject var driver: PersonFollowDriver
    @Environment(\.dismiss) private var dismiss

    private func gate(_ title: String, _ key: WritableKeyPath<FollowTestOptions, Bool>) -> some View {
        Toggle(title, isOn: Binding(get: { driver.testOptions[keyPath: key] }, set: { enabled in
            var value = driver.testOptions; value[keyPath: key] = enabled; driver.applyTestOptions(value)
        }))
    }

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("近人停车与其他实验分开设置")) {
                    Text("距离停车默认开启，开关与米数会保存，采集和导航共用。使用人体区域的ARKit深度测距，不再用框顶位置判断。其他实验默认关闭；改设置先停车，返回后手动开始。")
                    Button("关闭其他测试门槛") {
                        var options = FollowTestOptions()
                        options.stopWhenNear = driver.testOptions.stopWhenNear
                        options.stopDistanceM = driver.testOptions.stopDistanceM
                        driver.applyTestOptions(options)
                    }
                }
                Section(header: Text("近人停车（实际深度距离）")) {
                    gate("启用距离停车", \.stopWhenNear)
                    Text(String(format: "距手机 ≤ %.1f m 时停车", driver.testOptions.stopDistanceM))
                    Slider(value: Binding(get: { driver.testOptions.stopDistanceM }, set: { margin in
                        var value = driver.testOptions; value.stopDistanceM = margin; driver.applyTestOptions(value)
                    }), in: 0.5...2.0, step: 0.1).disabled(!driver.testOptions.stopWhenNear)
                    Text("默认1米，可调0.5～2米；超过所设距离0.2米，至少3次新鲜检测并持续0.4秒后恢复前进。距手机的水平距离来自LiDAR人体区域，不含底盘尺寸。无测距支持或读数不可靠时停车等待。")
                }
                Section(header: Text("检测条件——独立测试")) {
                    gate("置信度至少0.6", \.confidenceFilter)
                    gate("必须只有一个检测框", \.requireSinglePerson)
                    Text("初次取最大框，后续按位置和重叠匹配；丢失超过0.6秒才重新选取。不是身份识别，多人交叉仍可能切换。")
                    gate("连续稳定3帧才允许输出", \.requireStableTarget)
                    gate("四边各留1.5%空隙", \.rejectEdgeBoxes)
                    gate("框位置/大小跳变时停车", \.rejectTargetJump)
                    gate("检测过期从0.6秒收紧为0.35秒", \.strictDetectionTimeout)
                }
                Section(header: Text("驱动制动——独立测试")) {
                    gate("转向100ms输出 / 250ms制动", \.pulseTurns)
                    gate("左右反向前停车2秒", \.pauseBeforeReversal)
                    Text("小偏差差速前进，目标接近画面侧边时先停车再优先转向；近人时只短时原地对准。两项实验只额外限制原地转向，航线导航的2秒阶段间隔不变。")
                }
            }.navigationTitle("跟随门槛单测")
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }.navigationViewStyle(.stack)
    }
}

struct FollowDetectionOverlay: View {
    @ObservedObject var driver: PersonFollowDriver
    var body: some View {
        GeometryReader { geometry in
            if let box = driver.overlayBox {
                Rectangle().stroke(Color.green, lineWidth: 2)
                    .frame(width: CGFloat(box.width) * geometry.size.width, height: CGFloat(box.height) * geometry.size.height)
                    .position(x: CGFloat(box.centreX) * geometry.size.width, y: CGFloat(box.centreY) * geometry.size.height)
            }
        }.allowsHitTesting(false).accessibilityHidden(true)
    }
}
