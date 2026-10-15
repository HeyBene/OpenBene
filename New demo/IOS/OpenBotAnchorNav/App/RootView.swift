import SwiftUI
import OpenBotNavKit

private enum MapNotice: Identifiable {
    case error(String), delete(RecordedMap)
    var id: String { String(describing: self) }
}

private struct NavigationPresentation: Identifiable {
    let id = UUID()
    let map: RecordedMap
    let link: RobotLink
    let robotDescription: String
    let requiresConnection: Bool
    let pwm: NavigationPwmSettings
}

struct RootView: View {
    @EnvironmentObject private var demo: DemoSession
    @Environment(\.scenePhase) private var scenePhase
    @State private var showRecording = false
    @State private var navigation: NavigationPresentation?
    @State private var sharedURL: URL?
    @State private var showShare = false
    @State private var showPwmSettings = false
    @State private var notice: MapNotice?

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("本地采集地图")) {
                    Button("采集新地图") { showRecording = true }
                    if demo.maps.isEmpty {
                        Text("暂无地图。先识别锚点，采集起点和节点后保存。").foregroundColor(.secondary)
                    } else {
                        Picker("地图", selection: $demo.selectedMapID) {
                            ForEach(demo.maps) { map in Text(map.name).tag(Optional(map.id)) }
                        }
                    }
                }
                if let map = demo.selectedMap {
                    Section(header: Text("按顺序执行的航线")) {
                        poseRow(map.start)
                        ForEach(map.waypoints) { poseRow($0) }
                        Text(String(format: "总长 %.2f m · %@ · 图像宽度 %.1f cm",
                                    map.distanceM, map.anchor.title, map.anchor.sizeM * 100))
                            .font(.caption).foregroundColor(.secondary)
                        Button("导出地图 JSON") {
                            do { sharedURL = try demo.fileURL(map); showShare = true }
                            catch { notice = .error(error.localizedDescription) }
                        }
                        Button("删除此地图", role: .destructive) { notice = .delete(map) }
                    }
                }
                Section(header: Text("底盘")) {
                    Toggle("通过蓝牙驱动 OpenBot", isOn: $demo.useBle)
                    Text(demo.describeLink()).font(.caption)
                    if demo.useBle {
                        Button(demo.scanning ? "正在搜索…" : "搜索底盘") { demo.startScanning() }.disabled(demo.scanning)
                        ForEach(demo.discovered) { robot in
                            Button {
                                demo.select(robot)
                            } label: {
                                HStack {
                                    Text(robot.label)
                                    Spacer()
                                    if demo.selectedRobot?.id == robot.id { Image(systemName: "checkmark") }
                                }
                            }
                        }
                    }
                }
                Section(header: Text("PWM 参数")) {
                    Button("PWM 调节与测试") { showPwmSettings = true }
                        .accessibilityIdentifier("pwm.open")
                    PwmSettingsSummary(settings: demo.pwmSettings)
                }
                Section {
                    Button("应用地图并显示航线") {
                        guard let map = demo.selectedMap else { return }
                        navigation = NavigationPresentation(map: map, link: demo.makeLink(),
                            robotDescription: demo.describeLink(), requiresConnection: demo.useBle,
                            pwm: demo.pwmSettings.current)
                    }.disabled(demo.selectedMap == nil || demo.useBle && demo.selectedRobot == nil)
                    Text("识别同一张锚点图，把机器人放回起点，再开始执行。").font(.caption)
                    Text(demo.statusText).font(.caption).foregroundColor(.secondary)
                    if case .failed(let reason) = demo.loadState {
                        Text(reason).foregroundColor(.red)
                        Button("重新加载") { demo.load() }
                    }
                }
            }.navigationTitle("本地锚点航线")
        }.navigationViewStyle(.stack)
        .onChange(of: scenePhase) { if $0 == .active { demo.load() } }
        .fullScreenCover(isPresented: $showRecording, onDismiss: { demo.load() }) {
            MapRecordingFlow { try demo.save($0) }
        }
        .fullScreenCover(item: $navigation) { request in
            if let map = try? request.map.mapData(), let route = try? request.map.route() {
                ArNavigationView(recordedMap: request.map, map: map, route: route,
                    link: request.link, robotDescription: request.robotDescription,
                    requiresConnection: request.requiresConnection, pwm: request.pwm)
            } else {
                VStack {
                    Text("地图航线不可用。")
                    Button("返回") { navigation = nil }
                }
            }
        }
        .sheet(isPresented: $showShare) {
            if let sharedURL = sharedURL { ShareFileView(url: sharedURL) }
        }
        .sheet(isPresented: $showPwmSettings) {
            PwmSettingsView(settings: demo.pwmSettings, allowsTesting: true, linkFactory: {
                guard demo.useBle, demo.selectedRobot != nil else { return nil }
                return demo.makeLink()
            })
        }
        .alert(item: $notice) { notice in
            switch notice {
            case .error(let reason):
                return Alert(title: Text("操作失败"), message: Text(reason), dismissButton: .default(Text("确定")))
            case .delete(let map):
                return Alert(title: Text("删除地图？"), message: Text("删除本机的“" + map.name + "”文件。"),
                    primaryButton: .destructive(Text("删除")) {
                        do { try demo.delete(map) } catch { self.notice = .error(error.localizedDescription) }
                    }, secondaryButton: .cancel(Text("取消")))
            }
        }
    }

    private func poseRow(_ point: RecordedWaypoint) -> some View {
        VStack(alignment: .leading) {
            Text(point.name)
            Text(String(format: "位置 %.2f, %.2f m · 朝向 %.1f°", point.pose.x, point.pose.y, point.pose.yawDeg))
                .font(.caption).foregroundColor(.secondary)
        }
    }
}

/// Keep setup and capture in one presentation. Dismissing a sheet and opening
/// another cover with separately captured optional state could present an
/// empty view until a later parent refresh (for example switching apps).
private struct MapRecordingFlow: View {
    @State private var anchor: AnchorDefinition?
    let onSave: (RecordedMap) throws -> Void

    var body: some View {
        if let anchor = anchor {
            MapRecordingView(anchor: anchor, onSave: onSave)
        } else {
            CreateMapOptions { anchor = $0 }
        }
    }
}

private struct CreateMapOptions: View {
    @Environment(\.presentationMode) private var presentationMode
    @State private var anchorID = AnchorDefinition.templates[0].id
    @State private var widthCM = "20"
    @State private var share = false
    let onCreate: (AnchorDefinition) -> Void

    private var template: AnchorDefinition { AnchorDefinition.templates.first { $0.id == anchorID }! }
    private var imageURL: URL? { Bundle.main.url(forResource: template.imageName, withExtension: "png") }
    private var widthM: Double { (Double(widthCM) ?? 0) / 100 }

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("定位锚点")) {
                    Picker("标记图片", selection: $anchorID) {
                        ForEach(AnchorDefinition.templates) { Text($0.title).tag($0.id) }
                    }
                    if let url = imageURL, let image = UIImage(contentsOfFile: url.path) {
                        Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 220)
                        Button("分享 / 打印定位图片") { share = true }
                    }
                    TextField("完整图片打印宽度（cm）", text: $widthCM).keyboardType(.decimalPad)
                    Text("默认完整图片宽度 20 cm。将图片平放并固定在地面，采集和使用时保持位置、尺寸与方向不变。")
                        .font(.caption)
                }
                Section {
                    Text("先识别锚点，再在实际起点和各节点分别采集位置、朝向；直线连接相邻节点。")
                    Button("开始采集") {
                        onCreate(AnchorDefinition(id: template.id, imageName: template.imageName, sizeM: widthM))
                    }.disabled(!(0.05...1.0).contains(widthM))
                }
            }.navigationTitle("新建地图")
                .toolbar { Button("取消") { presentationMode.wrappedValue.dismiss() } }
        }
        .sheet(isPresented: $share) { if let url = imageURL { ShareFileView(url: url) } }
    }
}

struct ShareFileView: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
