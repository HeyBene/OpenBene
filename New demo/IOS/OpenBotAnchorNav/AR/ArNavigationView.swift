import SwiftUI
import ARKit

/// AR camera view with the navigation overlay: status card on top, guidance and
/// the drive controls at the bottom, plan view of the floor on the right.
struct ArNavigationView: View {
    @StateObject private var controller: ArNavigationController
    @Environment(\.presentationMode) private var presentationMode
    private let map: MapData
    private let route: Route

    init(map: MapData, route: Route, steps: [GuidanceStep], link: RobotLink, robotDescription: String) {
        self.map = map
        self.route = route
        _controller = StateObject(
            wrappedValue: ArNavigationController(
                map: map,
                route: route,
                steps: steps,
                link: link,
                robotDescription: robotDescription
            )
        )
    }

    var body: some View {
        ZStack {
            ArSceneView(sceneView: controller.sceneView)
                .ignoresSafeArea()

            MapOverlayCanvas(
                map: map,
                route: route,
                pose: controller.robotPose,
                usedMarkers: controller.usedMarkers
            )
            .frame(width: 180, height: 180)
            .background(Color.black.opacity(0.35))
            .cornerRadius(16)
            .padding(.trailing, 16)
            .padding(.top, 170)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)

            VStack(spacing: 12) {
                statusCard
                Spacer()
                bottomCard
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .onAppear { controller.start() }
        .onDisappear { controller.stopEverything() }
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(controller.stateText)
                .font(.headline)
                .foregroundColor(.white)
            Text(controller.detailText)
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.white.opacity(0.9))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.black.opacity(0.55))
        .cornerRadius(14)
    }

    private var bottomCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Picker("Mode", selection: modeBinding) {
                    Text("Route").tag(false)
                    Text("Follow").tag(true)
                }
                .pickerStyle(.segmented)
                .frame(width: 170)
                Spacer()
            }
            Text(controller.guidanceText)
                .font(.body)
                .foregroundColor(.white)
            if controller.followMode && !controller.isArmed {
                Text(controller.followAction)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.85))
            }
            ProgressView(value: controller.progress)
                .progressViewStyle(.linear)
                .tint(.teal)
            HStack(spacing: 12) {
                Button("Start driving") { controller.arm() }
                    .buttonStyle(.borderedProminent)
                    .disabled(controller.isArmed || (!controller.followMode && !controller.isLocalised))
                Button("Stop") {
                    controller.stopEverything()
                    presentationMode.wrappedValue.dismiss()
                }
                .buttonStyle(.bordered)
                .tint(.red)
                Spacer()
                if !controller.isLocalised && !controller.followMode {
                    Text("waiting for a marker")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.8))
                }
            }
        }
        .padding(14)
        .background(Color.black.opacity(0.55))
        .cornerRadius(14)
    }

    /// The segmented control drives the controller directly; follow mode needs no
    /// marker, so switching is allowed at any time and stops the robot first.
    private var modeBinding: Binding<Bool> {
        Binding(
            get: { controller.followMode },
            set: { controller.setFollowMode($0) }
        )
    }
}

/// Hosts the ARSCNView that shows the camera feed and the route nodes.
struct ArSceneView: UIViewRepresentable {
    let sceneView: ARSCNView

    func makeUIView(context: Context) -> ARSCNView {
        sceneView.automaticallyUpdatesLighting = false
        return sceneView
    }

    func updateUIView(_ uiView: ARSCNView, context: Context) {}
}
