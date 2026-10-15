import SwiftUI
import SceneKit
import OpenBotNavKit

final class MapRecordingController: ObservableObject {
    let session: AnchorARSession
    let capture: MapCapture
    @Published private(set) var start: RecordedWaypoint?
    @Published private(set) var waypoints: [RecordedWaypoint] = []
    private let layer = SCNNode()

    init(anchor: AnchorDefinition) {
        session = AnchorARSession(anchor: anchor)
        capture = MapCapture(anchor: anchor)
        session.onSceneReady = { [weak self] view in
            guard let self = self else { return }
            view.scene.rootNode.addChildNode(self.layer)
        }
    }

    func recordStart() throws {
        try capture.recordStart(pose: session.capturePose())
        update()
    }
    func addNode(_ name: String) throws {
        try capture.addWaypoint(name: name, pose: session.capturePose())
        update()
    }
    func undo() { capture.undo(); update() }

    private func update() { start = capture.start; waypoints = capture.waypoints; redraw() }
    private func redraw() { ARMapDrawing.draw(points: (start.map { [$0] } ?? []) + waypoints, in: layer, session: session) }
}

struct MapRecordingView: View {
    @StateObject private var controller: MapRecordingController
    private let onSave: (RecordedMap) throws -> Void

    init(anchor: AnchorDefinition, onSave: @escaping (RecordedMap) throws -> Void) {
        _controller = StateObject(wrappedValue: MapRecordingController(anchor: anchor))
        self.onSave = onSave
    }

    var body: some View { MapRecordingContent(controller: controller, onSave: onSave) }
}

private struct MapRecordingContent: View {
    @ObservedObject private var controller: MapRecordingController
    @ObservedObject private var session: AnchorARSession
    @Environment(\.presentationMode) private var presentationMode
    @Environment(\.scenePhase) private var scenePhase
    @State private var nodeName = ""
    @State private var mapName = ""
    @State private var showSave = false
    @State private var errorText: String?
    @State private var saveError: String?
    private let onSave: (RecordedMap) throws -> Void

    init(controller: MapRecordingController, onSave: @escaping (RecordedMap) throws -> Void) {
        _controller = ObservedObject(wrappedValue: controller)
        _session = ObservedObject(wrappedValue: controller.session)
        self.onSave = onSave
    }

    var body: some View {
        ZStack {
            ArSessionView(session: session).ignoresSafeArea()
            VStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("采集地图").font(.headline)
                    Text(session.message)
                    if let pose = session.pose {
                        Text(String(format: "位置 %.2f, %.2f m · 朝向 %.1f°", pose.x, pose.y, pose.yawDeg))
                            .font(.system(.caption, design: .monospaced))
                    }
                    Text("记录时面向希望到达节点后的朝向；锚点图片保持固定。").font(.caption)
                }.frame(maxWidth: .infinity, alignment: .leading).padding().background(Color.black.opacity(0.65)).cornerRadius(12)
                Spacer()
                VStack(alignment: .leading, spacing: 10) {
                    Text(controller.start == nil ? "请走到起点，采集当前位置和朝向。" : "起点已采集 · \(controller.waypoints.count) 个节点")
                    if !controller.waypoints.isEmpty {
                        Text(controller.waypoints.map { $0.name }.joined(separator: " → ")).font(.caption)
                    }
                    if controller.start == nil {
                        Button("采集起点") { perform { try controller.recordStart() } }
                            .buttonStyle(.borderedProminent).disabled(!canCapture)
                    } else {
                        TextField("节点名称（留空自动编号）", text: $nodeName)
                            .textFieldStyle(.roundedBorder).foregroundColor(.primary)
                        Button("添加节点与朝向") {
                            let name = nodeName.trimmingCharacters(in: .whitespacesAndNewlines)
                            perform {
                                try controller.addNode(name.isEmpty ? "节点 \(controller.waypoints.count + 1)" : name)
                                nodeName = ""
                            }
                        }.buttonStyle(.borderedProminent).disabled(!canCapture)
                    }
                    HStack {
                        Button("撤销") { controller.undo() }.disabled(controller.start == nil)
                        Button("保存地图") { showSave = true }.disabled(controller.waypoints.isEmpty)
                        Spacer()
                        Button("取消") { presentationMode.wrappedValue.dismiss() }
                    }.buttonStyle(.bordered)
                }.padding().background(Color.black.opacity(0.65)).cornerRadius(12)
            }.padding().foregroundColor(.white)
        }
        .onAppear { session.start() }
        .onDisappear { session.pause() }
        .onChange(of: scenePhase) { if $0 == .active { session.start() } else if $0 == .background { session.pause() } }
        .sheet(isPresented: $showSave) {
            NavigationView {
                Form {
                    TextField("地图名称", text: $mapName)
                    Text("按采集顺序保存所有节点的位置与朝向。")
                    if let saveError = saveError { Text(saveError).foregroundColor(.red) }
                    Button("保存到本机") {
                        do {
                            let map = try controller.capture.finish(name: mapName)
                            try onSave(map)
                            showSave = false
                            presentationMode.wrappedValue.dismiss()
                        } catch { saveError = error.localizedDescription }
                    }.disabled(mapName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .navigationTitle("保存地图")
                .toolbar { Button("取消") { showSave = false } }
            }
        }
        .alert("无法完成操作", isPresented: Binding(get: { errorText != nil }, set: { if !$0 { errorText = nil } })) {
            Button("确定", role: .cancel) { errorText = nil }
        } message: { Text(errorText ?? "") }
    }

    private var canCapture: Bool { session.localised && session.trackingNormal && session.pose != nil }
    private func perform(_ action: () throws -> Void) {
        do { try action() } catch { errorText = error.localizedDescription }
    }
}
