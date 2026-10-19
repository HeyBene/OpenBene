import SwiftUI
import Combine
import OpenBotNavKit

final class PwmSettingsModel: ObservableObject {
    @Published private(set) var current: NavigationPwmSettings
    private let store = NavigationPwmStore()
    init() { current = store.load() }
    func save(_ value: NavigationPwmSettings) throws {
        try store.save(value)
        current = value
    }
}

private final class PwmBenchController: ObservableObject {
    @Published private(set) var connected = false
    @Published private(set) var active = false
    @Published private(set) var status = "未进行测试。"
    @Published private(set) var frame = "c0,0"
    @Published private(set) var voltage: Double?
    private let link: RobotLink?
    private let tester: PwmPulseTester?
    private var timer: Timer?

    init(linkFactory: () -> RobotLink?) {
        link = linkFactory()
        tester = link.map { PwmPulseTester(link: $0) }
        if link != nil { status = "正在连接底盘…" }
        NotificationCenter.default.addObserver(self, selector: #selector(stop),
            name: UIApplication.willResignActiveNotification, object: nil)
    }
    deinit { timer?.invalidate(); NotificationCenter.default.removeObserver(self) }

    func open() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func run(_ action: PwmTestAction, settings: NavigationPwmSettings) {
        guard let tester = tester,
              tester.start(action, settings: settings, nowS: ProcessInfo.processInfo.systemUptime) else {
            status = "底盘未就绪，请检查连接和碰撞状态。"
            return
        }
        active = true
        frame = tester.lastFrame
        status = "测试中，1 秒后自动停车。"
    }

    @objc func stop() {
        tester?.stop()
        active = false
        frame = "c0,0"
        status = "已停车。"
    }

    func close() {
        stop()
        timer?.invalidate(); timer = nil
        link?.close()
    }

    private func tick() {
        tester?.tick(nowS: ProcessInfo.processInfo.systemUptime)
        let isConnected = link?.telemetry.connected ?? false
        if connected != isConnected { connected = isConnected }
        if active, tester?.active != true {
            active = false
            status = isConnected ? "本次测试已停止。" : "蓝牙断开，测试已停止。"
        }
        let latest = (link as? OpenBotBleLink)?.lastControlFrame ?? tester?.lastFrame ?? "c0,0"
        if frame != latest { frame = latest }
        if voltage != link?.telemetry.voltage { voltage = link?.telemetry.voltage }
        if let error = (link as? OpenBotBleLink)?.lastWriteError { status = "蓝牙写入错误：" + error }
    }
}

struct PwmSettingsView: View {
    @ObservedObject var settings: PwmSettingsModel
    @StateObject private var bench: PwmBenchController
    @State private var draft: NavigationPwmSettings
    @State private var saveMessage = ""
    @Environment(\.presentationMode) private var presentationMode
    private let allowsTesting: Bool
    private let onApply: (NavigationPwmSettings) -> Void

    init(settings: PwmSettingsModel, allowsTesting: Bool = false,
         linkFactory: @escaping () -> RobotLink? = { nil },
         onApply: @escaping (NavigationPwmSettings) -> Void = { _ in }) {
        self.settings = settings
        self.allowsTesting = allowsTesting
        self.onApply = onApply
        _draft = State(initialValue: settings.current)
        _bench = StateObject(wrappedValue: PwmBenchController(linkFactory: linkFactory))
    }

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("输出 PWM · 满量程 255")) {
                    pwmControl("直行基础 PWM", keyPath: \.drivePwm, identifier: "pwm.drive")
                    pwmControl("原地左转 PWM", keyPath: \.leftTurnPwm, identifier: "pwm.turn.left")
                    pwmControl("原地右转 PWM", keyPath: \.rightTurnPwm, identifier: "pwm.turn.right")
                    Text("三项分别设置为 0～255。左转和右转各用自己的 PWM，两轮方向相反；直行纠偏时左右轮会围绕基础值增减，并限制在 255 以内。")
                        .font(.caption).foregroundColor(.secondary)
                    Text("当前已保存：直行 \(settings.current.drivePwm)，左转 \(settings.current.leftTurnPwm)，右转 \(settings.current.rightTurnPwm)")
                        .font(.caption).accessibilityIdentifier("pwm.saved")
                }
                if allowsTesting {
                    Section(header: Text("底盘测试 · 每次 1 秒")) {
                        Text(bench.connected ? "底盘已连接" : "未连接：请在首页启用蓝牙并选择底盘，再打开此面板。")
                        if let voltage = bench.voltage { Text(String(format: "电池电压 %.2f V", voltage)) }
                        Text("先架空底盘。调整数值会立即停车；每次测试自动停止，也可随时点停车。")
                            .font(.caption).foregroundColor(.secondary)
                        HStack {
                            testButton("前进 1 秒", .forward)
                            testButton("左转 1 秒", .turnLeft)
                            testButton("右转 1 秒", .turnRight)
                        }.disabled(!bench.connected || bench.active)
                        Button("停车") { bench.stop() }.tint(.red)
                        Text("最近控车帧：\(bench.frame)").font(.system(.caption, design: .monospaced))
                        Text(bench.status).font(.caption)
                    }
                }
                Section {
                    Button("保存并应用") {
                        bench.stop()
                        do {
                            try settings.save(draft)
                            onApply(draft)
                            saveMessage = "已保存到本机。下一次开始执行使用此参数。"
                        } catch { saveMessage = error.localizedDescription }
                    }.accessibilityIdentifier("pwm.save")
                    Button("恢复 160 / 160 / 160") { bench.stop(); draft = .defaults; saveMessage = "请保存后应用。" }
                    Text(saveMessage.isEmpty ? "滑块与步进器先用于本次测试，点“保存并应用”后才用于航线导航和视觉跟随。" : saveMessage)
                        .font(.caption).foregroundColor(.secondary)
                    Text("航线各阶段间停车2秒；跟随采用短时转向制动，反向先停车2秒。航线、视觉跟随及跟随采集同步使用这三项参数，修改后需手动重新开始。")
                        .font(.caption).foregroundColor(.secondary)
                }
            }.navigationTitle("PWM 调节与测试")
                .toolbar { Button("完成") { bench.close(); presentationMode.wrappedValue.dismiss() } }
        }
        .onAppear { bench.open() }
        .onDisappear { bench.close() }
    }

    private func pwmControl(_ title: String, keyPath: WritableKeyPath<NavigationPwmSettings, Int>, identifier: String) -> some View {
        let value = Binding<Int>(get: { draft[keyPath: keyPath] }, set: {
            bench.stop()
            draft[keyPath: keyPath] = $0
            saveMessage = "参数已更改，尚未保存。"
        })
        return VStack(alignment: .leading, spacing: 10) {
            Stepper("\(title)：\(value.wrappedValue)", value: value, in: 0...255)
                .accessibilityIdentifier(identifier)
            Slider(value: Binding(get: { Double(value.wrappedValue) }, set: { value.wrappedValue = Int($0) }),
                   in: 0...255, step: 1)
                .accessibilityLabel(title)
        }.padding(.vertical, 4)
    }

    private func testButton(_ title: String, _ action: PwmTestAction) -> some View {
        Button(title) { bench.run(action, settings: draft) }.buttonStyle(.bordered)
    }
}

struct PwmSettingsSummary: View {
    @ObservedObject var settings: PwmSettingsModel
    var body: some View {
        Text("直行 \(settings.current.drivePwm) · 左转 \(settings.current.leftTurnPwm) · 右转 \(settings.current.rightTurnPwm) · 阶段间隔 2 秒")
            .font(.caption).foregroundColor(.secondary)
    }
}
