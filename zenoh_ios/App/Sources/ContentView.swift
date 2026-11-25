import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var link: ZenohLink

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("电脑地址，例如 192.168.1.23:7447", text: $link.endpoint)
                        .keyboardType(.numbersAndPunctuation)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("机器人 ID", text: $link.robotID)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Picker("采集源", selection: $link.useARKit) {
                        Text("ARKit 实时").tag(true)
                        Text("合成测试帧").tag(false)
                    }
                    .pickerStyle(.segmented)
                    .disabled(link.connected)
                    if let ip = NetworkInfo.wifiIPv4() {
                        LabeledContent("本机 Wi-Fi IP", value: ip)
                    }
                } header: {
                    Text("连接")
                } footer: {
                    Text("手机和电脑连同一个 Wi-Fi。地址填电脑的局域网 IP 和 zenohd 端口（默认 7447）。")
                }

                Section {
                    Button {
                        if link.connected { link.disconnect() } else { link.connect() }
                    } label: {
                        Text(link.connected ? "断开连接" : "连接电脑")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(link.connected ? .red : .accentColor)
                }

                Section("运行状态") {
                    LabeledContent("状态", value: link.statusText)
                    LabeledContent("已发送帧", value: "\(link.framesSent)")
                    LabeledContent("丢弃帧", value: "\(link.framesDropped)")
                    LabeledContent("发送速率", value: String(format: "%.2f MB/s", link.megabytes))
                    LabeledContent("采集", value: link.captureDetail)
                    LabeledContent("最近命令", value: link.lastCommand)
                    if let error = link.linkError {
                        Text(error).foregroundStyle(.red)
                    }
                }

                Section("电脑端需要运行") {
                    Text("""
                    zenohd
                    openbene-recv --endpoint tcp/<电脑IP>:7447 --record runs/test.mcap
                    """)
                    .font(.system(.footnote, design: .monospaced))
                    .textSelection(.enabled)
                }
            }
            .navigationTitle("OpenBene Zenoh")
        }
    }
}
