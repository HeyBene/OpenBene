import Foundation
import Combine
import CoreBluetooth

/// Application state shared by the picker and the AR screen: the demo map, the
/// destination, and the choice of robot link.
final class DemoSession: ObservableObject {

    enum LoadState {
        case loading
        case ready
        case failed(String)
    }

    struct DiscoveredRobot: Identifiable {
        let id: UUID
        let name: String
        let rssi: Int

        var label: String { name + "  \(rssi) dBm" }
    }

    static let startLocationId = "loc_entrance"

    @Published private(set) var loadState: LoadState = .loading
    @Published private(set) var roomNames: [String] = []
    @Published var selectedRoom = "Room 101"
    @Published var useBle = false
    @Published private(set) var statusText = "Idle. Put the phone on the robot and start from the entrance marker."
    @Published private(set) var selectedRobot: DiscoveredRobot?
    @Published private(set) var scanning = false

    private(set) var map: MapData?
    private var scanner: OpenBotBleLink?

    func load() {
        guard map == nil else { return }
        guard let url = Bundle.main.url(forResource: "demo_floor", withExtension: "json") else {
            loadState = .failed("demo_floor.json is missing from the app bundle")
            return
        }
        do {
            let text = try String(contentsOf: url, encoding: .utf8)
            let parsed = try MapData.parse(text)
            map = parsed
            roomNames = parsed.roomNames()
            if let first = roomNames.first, !roomNames.contains(selectedRoom) {
                selectedRoom = first
            }
            loadState = .ready
        } catch {
            loadState = .failed("\(error)")
        }
    }

    /// Route preview, in the same shape as the Python demo output.
    func routeSummary() -> String {
        guard let map = map else { return "" }
        do {
            guard let route = try Router(mapData: map).routeToRoom(
                startLocationId: DemoSession.startLocationId,
                roomName: selectedRoom
            ) else { return "no route to " + selectedRoom }

            var lines: [String] = []
            let start = (try? map.location(route.startLocationId).name) ?? route.startLocationId
            lines.append(String(format: "%-14@ %5.1f m", start as NSString, route.totalDistanceM))
            for step in GuidanceBuilder(mapData: map).build(route) {
                lines.append("  - " + step.message)
            }
            let markers = route.locationSequence().map { $0.replacingOccurrences(of: "loc_", with: "") }
            lines.append("markers on the way: " + markers.joined(separator: " -> "))
            return lines.joined(separator: "\n")
        } catch {
            return "route error: \(error)"
        }
    }

    func startScanning() {
        let link = scanner ?? OpenBotBleLink()
        scanner = link
        statusText = "Scanning for the OpenBot BLE service..."
        scanning = true
        link.startScan { [weak self] peripheral, name, rssi in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.statusText = "Found " + name + "  \(rssi) dBm"
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 8.0) { [weak self] in
            guard let self = self else { return }
            self.scanning = false
            self.scanner?.stopScan()
            if self.scanner?.discovered.isEmpty ?? true {
                self.statusText = "No OpenBot found. Check that the ESP32 is powered and in range."
            }
        }
    }

    var discovered: [DiscoveredRobot] {
        (scanner?.discovered ?? []).map { DiscoveredRobot(id: $0.id, name: $0.name, rssi: $0.rssi) }
    }

    func select(_ robot: DiscoveredRobot) {
        selectedRobot = robot
        useBle = true
        statusText = "Selected " + robot.label
    }

    /// The link the AR screen drives. Falls back to the bench mock.
    func makeLink() -> RobotLink {
        guard useBle, let robot = selectedRobot else { return MockRobotLink() }
        let link = OpenBotBleLink(targetIdentifier: robot.id)
        link.connect(identifier: robot.id)
        return link
    }

    func describeLink() -> String {
        if !useBle { return "mock link (commands are only shown on screen)" }
        guard let robot = selectedRobot else { return "mock link (no OpenBot selected)" }
        return "OpenBot " + robot.name
    }

    func setStatus(_ text: String) {
        statusText = text
    }
}
