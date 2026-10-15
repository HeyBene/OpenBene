import SwiftUI
import ARKit
import OpenBotNavKit

struct ArNavigationView: View {
    @EnvironmentObject private var demo: DemoSession
    @StateObject private var controller: ArNavigationController
    @Environment(\.presentationMode) private var presentationMode
    @Environment(\.scenePhase) private var scenePhase
    private let map: MapData
    private let route: Route
    @State private var showPwmSettings = false

    init(recordedMap: RecordedMap, map: MapData, route: Route, link: RobotLink,
         robotDescription: String, requiresConnection: Bool, pwm: NavigationPwmSettings = .defaults) {
        self.map = map
        self.route = route
        _controller = StateObject(wrappedValue: ArNavigationController(map: recordedMap,
            link: link, robotDescription: robotDescription, requiresConnection: requiresConnection, pwm: pwm))
    }

    var body: some View {
        ZStack {
            ArSessionView(session: controller.session).ignoresSafeArea()
            MapOverlayCanvas(map: map, route: route, pose: controller.robotPose, usedMarkers: controller.usedMarkers)
                .frame(width: 160, height: 160)
                .background(Color.black.opacity(0.5)).cornerRadius(12)
                .padding(.trailing).padding(.top, 155)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            VStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(controller.stateText).font(.headline)
                    Text(controller.detailText).font(.system(.caption, design: .monospaced))
                }.frame(maxWidth: .infinity, alignment: .leading)
                    .padding().background(Color.black.opacity(0.65)).cornerRadius(12)
                Spacer()
                VStack(alignment: .leading, spacing: 10) {
                    Picker("模式", selection: Binding(get: { controller.followMode }, set: { controller.setFollowMode($0) })) {
                        Text("航线").tag(false)
                        Text("跟随").tag(true)
                    }.pickerStyle(.segmented)
                    Text(controller.guidanceText)
                    ProgressView(value: controller.progress).tint(.teal)
                    if !controller.followMode {
                        HStack {
                            Text("PWM 直行 \(controller.pwm.drivePwm) · 左转 \(controller.pwm.leftTurnPwm) · 右转 \(controller.pwm.rightTurnPwm)").font(.caption)
                            Spacer()
                            Button("调节 PWM") { controller.stopDriving(); showPwmSettings = true }
                        }
                    }
                    HStack {
                        Button("开始执行") { controller.arm() }
                            .buttonStyle(.borderedProminent)
                            .disabled(controller.isArmed || !controller.readyToStart)
                        Button("停车") { controller.stopDriving() }.buttonStyle(.bordered).tint(.red)
                        Button("退出") {
                            controller.stopEverything()
                            presentationMode.wrappedValue.dismiss()
                        }.buttonStyle(.bordered)
                    }
                    if !controller.followMode {
                        Text("转向航线 → 停 2 秒 → 直行 → 停 2 秒 → 调整节点朝向 → 停 2 秒 → 下一段")
                            .font(.caption)
                    }
                }.padding().background(Color.black.opacity(0.65)).cornerRadius(12)
            }.padding().foregroundColor(.white)
        }
        .onAppear { controller.start() }
        .onDisappear { controller.stopEverything() }
        .onChange(of: scenePhase) { if $0 == .active { controller.start() } else if $0 == .background { controller.stopDriving(); controller.session.pause() } }
        .sheet(isPresented: $showPwmSettings) {
            PwmSettingsView(settings: demo.pwmSettings, onApply: controller.applyPwm)
        }
    }
}

struct ArSessionView: View {
    @ObservedObject var session: AnchorARSession
    var body: some View {
        ZStack {
            Color.black
            if let view = session.sceneView {
                ArSceneView(sceneView: view, onVisible: session.sceneBecameVisible,
                            onRendered: session.sceneDidRender)
            }
            if !session.hasRenderedFrame {
                VStack(spacing: 12) {
                    ProgressView().tint(.white)
                    Text(session.message).foregroundColor(.white)
                }.padding().background(Color.black.opacity(0.7)).cornerRadius(12)
                    .accessibilityIdentifier("ar.camera.startup")
            }
        }
    }
}

struct ArSceneView: UIViewControllerRepresentable {
    let sceneView: ARSCNView
    let onVisible: () -> Void
    let onRendered: () -> Bool

    func makeUIViewController(context: Context) -> ARSceneViewController {
        ARSceneViewController(sceneView: sceneView, onVisible: onVisible, onRendered: onRendered)
    }
    func updateUIViewController(_ controller: ARSceneViewController, context: Context) {}
}

final class ARSceneViewController: UIViewController, ARSCNViewDelegate {
    private let sceneView: ARSCNView
    private let onVisible: () -> Void
    private let onRendered: () -> Bool

    init(sceneView: ARSCNView, onVisible: @escaping () -> Void, onRendered: @escaping () -> Bool) {
        self.sceneView = sceneView
        self.onVisible = onVisible
        self.onRendered = onRendered
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        sceneView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(sceneView)
        NSLayoutConstraint.activate([
            sceneView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            sceneView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            sceneView.topAnchor.constraint(equalTo: view.topAnchor),
            sceneView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        sceneView.delegate = self
        sceneView.isAccessibilityElement = true
        sceneView.accessibilityIdentifier = "ar.camera.preview"
        sceneView.accessibilityLabel = "相机预览"
        sceneView.accessibilityValue = "准备中"
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        view.layoutIfNeeded()
        onVisible()
    }

    func renderer(_ renderer: SCNSceneRenderer, didRenderScene scene: SCNScene, atTime time: TimeInterval) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, self.onRendered() else { return }
            self.sceneView.accessibilityValue = "已显示"
            // This delegate only observes startup; stop dispatching render
            // callbacks once a camera frame has actually been displayed.
            self.sceneView.delegate = nil
        }
    }
}
