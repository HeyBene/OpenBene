import SwiftUI
import SceneKit
import OpenBotNavKit

final class MapRecordingController: ObservableObject {
    let session: AnchorARSession
    let capture: MapCapture
    let followDriver: PersonFollowDriver
    @Published private(set) var settling = false
    private var stationaryWork: DispatchWorkItem?
    private var closed = false
    private var stationaryGeneration = 0
    @Published private(set) var start: RecordedWaypoint?
    @Published private(set) var waypoints: [RecordedWaypoint] = []
    @Published private(set) var trajectoryStarted = false
    @Published private(set) var trajectoryCapacityReached = false
    @Published private(set) var trajectoryPointCount = 0
    @Published private(set) var trajectoryDistanceM = 0.0
    private let layer = SCNNode()
    private let trajectoryDrawing = PhoneTrajectoryDrawing()
    private var trajectory = CaptureTrajectory()
    private var lastFrameTimestampS: Double?
    private var anchorStart: RecordedWaypoint?
    private var lastStatusTimeS = -Double.infinity

    init(anchor: AnchorDefinition, linkFactory: () -> RobotLink? = { nil }, pwm: NavigationPwmSettings = .defaults) {
        followDriver = PersonFollowDriver(link: linkFactory(), pwm: pwm)
        session = AnchorARSession(anchor: anchor)
        capture = MapCapture(anchor: anchor)
        session.onSceneReady = { [weak self] view in
            guard let self = self else { return }
            view.scene.rootNode.addChildNode(self.layer)
            view.scene.rootNode.addChildNode(self.trajectoryDrawing.root)
        }
        session.onFrame = { [weak self] pose, normal, timestampS in
            self?.handleFrame(pose: pose, normal: normal, timestampS: timestampS)
        }
        session.onCameraFrame = { [weak self] frame in
            guard let self = self else { return }
            self.followDriver.scan(frame, viewportSize: self.session.sceneView?.bounds.size ?? .zero)
        }
        session.onUnavailable = { [weak self] reason in
            self?.followDriver.stop(reason: reason)
            self?.trajectory.breakSegment()
            self?.trajectoryDrawing.hideCursor()
        }
        session.onTrackingLimited = { [weak self] reason in
            self?.followDriver.trackingUnavailable(reason)
            self?.trajectory.breakSegment()
            self?.trajectoryDrawing.hideCursor()
        }
    }

    func applyPwm(_ value: NavigationPwmSettings) { followDriver.applyPwm(value) }

    func performStationary(_ action: @escaping (MapRecordingController) throws -> Void,
                           completion: @escaping (Error?) -> Void) {
        guard !settling, !closed else { return }
        stationaryGeneration += 1
        let token = stationaryGeneration
        let wait = followDriver.needsStationaryPause
        followDriver.stop(reason: "已停止跟随，准备记录节点。")
        let work = DispatchWorkItem { [weak self] in
            guard let self = self, !self.closed, self.stationaryGeneration == token else { return }
            self.stationaryWork = nil; self.settling = false
            do { try action(self); completion(nil) } catch { completion(error) }
        }
        if wait {
            settling = true; stationaryWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: work)
        } else { work.perform() }
    }

    func pauseMovement() {
        stationaryGeneration += 1
        stationaryWork?.cancel(); stationaryWork = nil; settling = false
        followDriver.stop()
    }

    func suspend() { pauseMovement(); session.pause() }

    func close() {
        closed = true
        stationaryGeneration += 1
        stationaryWork?.cancel(); stationaryWork = nil
        followDriver.close(); session.pause()
    }

    func beginAtMountedPose() throws {
        let pose = try session.capturePose()
        guard let time = lastFrameTimestampS, capture.start == nil else {
            throw RecordingError.invalid("请先撤销已有节点和起点。")
        }
        trajectory.begin(pose: pose, timestampS: time)
        anchorStart = RecordedWaypoint(name: "锚点处出发位置", pose: pose, trajectoryIndex: 0)
        trajectoryDrawing.reset()
        followDriver.setEnabled(true)
        publishTrajectory()
    }

    func recordStart() throws {
        followDriver.stop()
        let pose = try session.capturePose()
        guard trajectory.started else {
            throw RecordingError.invalid("请先将手机固定到支架并确认出发位置，再采集起点。")
        }
        let index = try pin(pose)
        try capture.recordStart(pose: pose, trajectoryIndex: index)
        update()
    }
    func addNode(_ name: String) throws {
        followDriver.stop()
        let pose = try session.capturePose()
        let index = try pin(pose)
        try capture.addWaypoint(name: name, pose: pose, trajectoryIndex: index)
        update()
    }

    /// Snapshot on main; planning runs off main without touching the AR scene.
    func makeMap(name: String, completion: @escaping (Result<RecordedMap, Error>) -> Void) {
        followDriver.stop()
        guard let start = capture.start else {
            completion(.failure(RecordingError.invalid("请先采集起点。"))); return
        }
        let nodes = capture.waypoints, samples = trajectory.recordedSamples
        let anchor = capture.anchor, anchorStart = self.anchorStart
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result { try RecordedMap.planned(name: name, anchor: anchor, start: start,
                waypoints: nodes, samples: samples, anchorStart: anchorStart) }
            DispatchQueue.main.async { completion(result) }
        }
    }

    private func pin(_ pose: Pose2D) throws -> Int {
        guard let timestampS = lastFrameTimestampS, timestampS.isFinite else {
            throw RecordingError.invalid("相机帧尚未就绪，请稍候。")
        }
        let index = try trajectory.pin(pose: pose, timestampS: timestampS)
        trajectoryDrawing.rebuild(trajectory.samples, session: session)
        publishTrajectory()
        return index
    }
    func undo() {
        followDriver.stop()
        capture.undo()
        if capture.start == nil {
            followDriver.setEnabled(false)
            anchorStart = nil
            trajectory.reset()
            trajectoryDrawing.reset()
            publishTrajectory()
        }
        update()
    }

    private func handleFrame(pose: Pose2D?, normal: Bool, timestampS: Double) {
        lastFrameTimestampS = timestampS
        followDriver.observeFrame(trackingNormal: normal && pose != nil && trajectory.started && !trajectory.capacityReached,
                                  timestampS: timestampS)
        guard trajectory.started else { return }
        let previous = trajectory.samples.last
        let pruned = trajectory.prunedSampleCount
        if trajectory.observe(pose: pose, trackingNormal: normal, timestampS: timestampS),
           let sample = trajectory.samples.last {
            if trajectory.prunedSampleCount != pruned {
                trajectoryDrawing.rebuild(trajectory.samples, session: session)
            } else if !sample.startsSegment, let previous = previous {
                trajectoryDrawing.append(from: previous.pose, to: sample.pose, session: session)
            }
            if timestampS - lastStatusTimeS >= 0.10 {
                lastStatusTimeS = timestampS
                publishTrajectory()
            }
        }
        if trajectory.capacityReached && !trajectoryCapacityReached {
            followDriver.stop(reason: "轨迹已达容量上限，跟随已停止，请保存地图。")
            followDriver.setEnabled(false)
            publishTrajectory()
        }
        if normal, let pose = pose {
            trajectoryDrawing.showPhone(at: pose, timestampS: timestampS, session: session)
        } else { trajectoryDrawing.hideCursor() }
    }

    private func publishTrajectory() {
        trajectoryStarted = trajectory.started
        trajectoryCapacityReached = trajectory.capacityReached
        trajectoryPointCount = trajectory.recordedSamples.count
        trajectoryDistanceM = trajectory.distanceM
    }

    private func update() { start = capture.start; waypoints = capture.waypoints; redraw() }
    private func redraw() { ARMapDrawing.draw(points: (start.map { [$0] } ?? []) + waypoints, in: layer, session: session) }
}

struct MapRecordingView: View {
    @StateObject private var controller: MapRecordingController
    private let onSave: (RecordedMap) throws -> Void

    init(anchor: AnchorDefinition, linkFactory: @escaping () -> RobotLink? = { nil },
         pwm: NavigationPwmSettings = .defaults, onSave: @escaping (RecordedMap) throws -> Void) {
        _controller = StateObject(wrappedValue: MapRecordingController(anchor: anchor, linkFactory: linkFactory, pwm: pwm))
        self.onSave = onSave
    }

    var body: some View { MapRecordingContent(controller: controller, onSave: onSave) }
}

private struct MapRecordingContent: View {
    @ObservedObject private var controller: MapRecordingController
    @ObservedObject private var session: AnchorARSession
    @Environment(\.presentationMode) private var presentationMode
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var demo: DemoSession
    @State private var nodeName = ""
    @State private var mapName = ""
    @State private var showSave = false
    @State private var errorText: String?
    @State private var saveError: String?
    @State private var saving = false
    @State private var showPwmSettings = false
    private let onSave: (RecordedMap) throws -> Void

    init(controller: MapRecordingController, onSave: @escaping (RecordedMap) throws -> Void) {
        _controller = ObservedObject(wrappedValue: controller)
        _session = ObservedObject(wrappedValue: controller.session)
        self.onSave = onSave
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                ArSessionView(session: session, followDriver: controller.followDriver).ignoresSafeArea()
                VStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("采集地图").font(.headline)
                        Text(session.message)
                        if let pose = session.pose {
                            Text(String(format: "位置 %.2f, %.2f m · 朝向 %.1f°", pose.x, pose.y, pose.yawDeg))
                                .font(.system(.caption, design: .monospaced))
                        }
                        if controller.trajectoryStarted {
                            Text(String(format: "手机轨迹 %.2f m", controller.trajectoryDistanceM) +
                                 " · \(controller.trajectoryPointCount) 点" +
                                 (session.trackingNormal ? "" : " · 已暂停"))
                                .font(.caption).accessibilityIdentifier("capture.trajectory.status")
                            Text("紫色：30 Hz 手机轨迹 · 保存时生成带状空间内的子节点").font(.caption2)
                        } else {
                            Text("识别后将手机固定在支架上，再确认出发位置；无需移到图片正上方。").font(.caption)
                        }
                        if controller.trajectoryCapacityReached { Text("已达到轨迹容量上限，请保存已有节点。 ").foregroundColor(.orange) }
                        Text("手持采集时保持与支架一致的镜头朝向和俯仰；节点记录期望的车头朝向。").font(.caption)
                    }.frame(maxWidth: .infinity, alignment: .leading).padding().background(Color.black.opacity(0.65)).cornerRadius(12)
                    Spacer(minLength: 0)
                    ScrollView {
                        VStack(alignment: .leading, spacing: 10) {
                            FollowControls(driver: controller.followDriver, title: "跟随采集", disabled: controller.settling, onPwm: {
                                controller.followDriver.stop(); showPwmSettings = true
                            })
                            Divider().overlay(Color.white.opacity(0.4))
                            Text(controller.start == nil ? "请走到起点，采集当前位置和朝向。" : "起点已采集 · \(controller.waypoints.count) 个节点")
                            if !controller.waypoints.isEmpty {
                                Text(controller.waypoints.map { $0.name }.joined(separator: " → ")).font(.caption).lineLimit(1)
                            }
                            if !controller.trajectoryStarted {
                                Button("确认支架处出发位置") { perform { try controller.beginAtMountedPose() } }
                                    .buttonStyle(.borderedProminent).disabled(!canCapture)
                            } else if controller.start == nil {
                                Button("采集起点") { stationary { try $0.recordStart() } }
                                    .buttonStyle(.borderedProminent).disabled(!canCapture)
                            } else {
                                TextField("节点名称（留空自动编号）", text: $nodeName)
                                    .textFieldStyle(.roundedBorder).foregroundColor(.primary)
                                Button("添加节点与朝向") {
                                    let name = nodeName.trimmingCharacters(in: .whitespacesAndNewlines)
                                    stationary { try $0.addNode(name.isEmpty ? "节点 \($0.waypoints.count + 1)" : name) }
                                    nodeName = ""
                                }.buttonStyle(.borderedProminent).disabled(!canCapture)
                            }
                            if controller.settling { ProgressView("停车稳定中，2秒后记录…").tint(.white) }
                            HStack {
                                Button("撤销") { controller.undo() }.disabled(!controller.trajectoryStarted || controller.settling)
                                Button("保存地图") { controller.followDriver.stop(); showSave = true }.disabled(controller.waypoints.isEmpty || controller.settling)
                                Spacer()
                                Button("取消") { presentationMode.wrappedValue.dismiss() }
                            }.buttonStyle(.bordered)
                        }.padding()
                    }.frame(maxHeight: geometry.size.height * 0.60)
                        .background(Color.black.opacity(0.65)).cornerRadius(12)
                }.padding().foregroundColor(.white)
            }
        }
        .onAppear { session.start() }
        .onDisappear { controller.close() }
        .onChange(of: scenePhase) { if $0 == .active { session.start() } else if $0 == .background { controller.suspend() } else { controller.pauseMovement() } }
        .sheet(isPresented: $showPwmSettings) {
            PwmSettingsView(settings: demo.pwmSettings, onApply: controller.applyPwm)
        }
        .sheet(isPresented: $showSave) {
            NavigationView {
                Form {
                    TextField("地图名称", text: $mapName)
                    Text("保存30 Hz原始轨迹，并在轨迹左右各15cm内生成尽量少的直线子节点；导航只显示生成的航线。")
                    if saving { ProgressView("正在生成并校验子节点路线…") }
                    if let saveError = saveError { Text(saveError).foregroundColor(.red) }
                    Button("保存到本机") {
                        saving = true
                        saveError = nil
                        controller.makeMap(name: mapName) { result in
                            do {
                                try onSave(result.get())
                                saving = false
                                showSave = false
                                presentationMode.wrappedValue.dismiss()
                            } catch { saving = false; saveError = error.localizedDescription }
                        }
                    }.disabled(saving || mapName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .navigationTitle("保存地图")
                .toolbar { Button("取消") { showSave = false }.disabled(saving) }
                .interactiveDismissDisabled(saving)
            }
        }
        .alert("无法完成操作", isPresented: Binding(get: { errorText != nil }, set: { if !$0 { errorText = nil } })) {
            Button("确定", role: .cancel) { errorText = nil }
        } message: { Text(errorText ?? "") }
    }

    private var canCapture: Bool { session.localised && session.trackingNormal && session.pose != nil && !controller.trajectoryCapacityReached && !controller.settling }
    private func stationary(_ action: @escaping (MapRecordingController) throws -> Void) {
        controller.performStationary(action) { if let error = $0 { errorText = error.localizedDescription } }
    }
    private func perform(_ action: () throws -> Void) {
        do { try action() } catch { errorText = error.localizedDescription }
    }
}
