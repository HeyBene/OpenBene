import Foundation
import Combine
import CoreBluetooth
import OpenBotNavKit

final class DemoSession: ObservableObject {
    enum LoadState { case loading, ready, failed(String) }
    struct DiscoveredRobot: Identifiable {
        let id: UUID
        let name: String
        let rssi: Int
        var label: String { name + "  \(rssi) dBm" }
    }

    @Published private(set) var loadState: LoadState = .loading
    @Published private(set) var maps: [RecordedMap] = []
    @Published var selectedMapID: UUID?
    @Published var useBle = false
    @Published private(set) var statusText = "请先采集地图，数据仅保存在本机。"
    @Published private(set) var selectedRobot: DiscoveredRobot?
    @Published private(set) var scanning = false
    @Published private(set) var discovered: [DiscoveredRobot] = []
    private let store = RecordedMapStore()
    let pwmSettings = PwmSettingsModel()
    private var scanner: OpenBotBleLink?

    var selectedMap: RecordedMap? { maps.first { $0.id == selectedMapID } }

    func load() {
        do {
            maps = try store.loadAll()
            if !maps.contains(where: { $0.id == selectedMapID }) { selectedMapID = maps.first?.id }
            loadState = .ready
            if !store.warnings.isEmpty { statusText = store.warnings.joined(separator: "\n") }
        } catch { loadState = .failed(error.localizedDescription) }
    }

    func save(_ map: RecordedMap) throws {
        try store.save(map)
        selectedMapID = map.id
        load()
        statusText = "地图已保存到本机。"
    }

    func delete(_ map: RecordedMap) throws { try store.delete(map); load() }
    func fileURL(_ map: RecordedMap) throws -> URL { try store.fileURL(for: map) }

    func startScanning() {
        let link = scanner ?? OpenBotBleLink()
        scanner = link
        discovered = []
        statusText = "正在搜索 OpenBot 蓝牙底盘…"
        scanning = true
        link.startScan { [weak self, weak link] _, _, _ in
            guard let self = self else { return }
            self.discovered = (link?.discovered ?? []).map { DiscoveredRobot(id: $0.id, name: $0.name, rssi: $0.rssi) }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in
            guard let self = self else { return }
            self.scanning = false
            self.scanner?.stopScan()
            if self.discovered.isEmpty { self.statusText = "未找到底盘，请检查蓝牙权限、电源和距离。" }
        }
    }

    func select(_ robot: DiscoveredRobot) {
        selectedRobot = robot
        useBle = true
        scanner?.stopScan()
        scanning = false
        statusText = "已选择 " + robot.label
    }

    func makeLink() -> RobotLink {
        guard useBle, let robot = selectedRobot else { return MockRobotLink() }
        return OpenBotBleLink(targetIdentifier: robot.id)
    }

    func describeLink() -> String {
        if !useBle { return "仅预览与模拟轮速，不驱动底盘" }
        return selectedRobot.map { "OpenBot " + $0.name } ?? "未选择底盘"
    }
}
