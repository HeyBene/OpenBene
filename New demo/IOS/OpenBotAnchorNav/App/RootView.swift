import SwiftUI

/// Destination picker and robot link, mirroring the Android main screen.
struct RootView: View {
    @EnvironmentObject private var demo: DemoSession
    @State private var showArNavigation = false
    @State private var activeLink: RobotLink?

    var body: some View {
        NavigationView {
            Form {
                switch demo.loadState {
                case .loading:
                    Section { Text("loading the demo map...") }
                case .failed(let reason):
                    Section {
                        Text("could not load the demo map")
                            .bold()
                        Text(reason).font(.footnote)
                    }
                case .ready:
                    readyForm
                }
            }
            .navigationTitle("Anchor Nav")
        }
        .navigationViewStyle(.stack)
        .fullScreenCover(isPresented: $showArNavigation) { arScreen }
    }

    @ViewBuilder
    private var readyForm: some View {
        Section(header: Text("Destination")) {
            Picker("Room", selection: $demo.selectedRoom) {
                ForEach(demo.roomNames, id: \.self) { room in
                    Text(room).tag(room)
                }
            }
            Text(demo.routeSummary())
                .font(.system(.footnote, design: .monospaced))
        }

        Section(header: Text("Robot")) {
            Toggle("Drive a real OpenBot over Bluetooth LE", isOn: $demo.useBle)
            Button(demo.scanning ? "Scanning..." : "Scan for OpenBot") {
                demo.startScanning()
            }
            .disabled(demo.scanning || !demo.useBle)
            ForEach(demo.discovered) { robot in
                Button {
                    demo.select(robot)
                } label: {
                    HStack {
                        Text(robot.label)
                        Spacer()
                        if demo.selectedRobot?.id == robot.id {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        }

        Section {
            Button("Start AR navigation") {
                activeLink = demo.makeLink()
                showArNavigation = true
            }
            .disabled(demo.useBle && demo.selectedRobot == nil)
        }

        Section {
            Text(demo.statusText).font(.footnote)
            Text("Robot link: " + demo.describeLink()).font(.footnote)
        }
    }

    @ViewBuilder
    private var arScreen: some View {
        if let map = demo.map,
           let route = try? Router(mapData: map).routeToRoom(
               startLocationId: DemoSession.startLocationId,
               roomName: demo.selectedRoom
           ) {
            ArNavigationView(
                map: map,
                route: route,
                steps: GuidanceBuilder(mapData: map).build(route),
                link: activeLink ?? MockRobotLink(),
                robotDescription: demo.describeLink()
            )
        } else {
            VStack(spacing: 16) {
                Text("no route to " + demo.selectedRoom)
                Button("Close") { showArNavigation = false }
            }
        }
    }
}
