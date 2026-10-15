import Foundation

public final class RecordedMapStore {
    public let directory: URL
    public private(set) var warnings: [String] = []
    private var paths: [UUID: URL] = [:]

    public init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Maps", isDirectory: true)
    }

    public func loadAll() throws -> [RecordedMap] {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let files = try FileManager.default.contentsOfDirectory(at: directory,
            includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles])
        var maps: [RecordedMap] = []
        paths = [:]
        warnings = []
        for file in files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) where file.pathExtension.lowercased() == "json" {
            do {
                guard try file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else { continue }
                let map = try read(from: file)
                guard paths[map.id] == nil else { throw RecordingError.invalid("地图编号重复。") }
                paths[map.id] = file
                maps.append(map)
            } catch { warnings.append(file.lastPathComponent + ": " + error.localizedDescription) }
        }
        return maps.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    public func read(from url: URL) throws -> RecordedMap {
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= 2 * 1024 * 1024 else { throw RecordingError.invalid("地图文件不能超过 2 MB。") }
        let data = try Data(contentsOf: url)
        guard data.count <= 2 * 1024 * 1024 else { throw RecordingError.invalid("地图文件不能超过 2 MB。") }
        let map = try JSONDecoder().decode(RecordedMap.self, from: data)
        try map.validate()
        return map
    }

    public func save(_ map: RecordedMap) throws {
        try map.validate()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(map.id.uuidString + ".json")
        guard paths[map.id] == nil, !FileManager.default.fileExists(atPath: url.path) else {
            throw RecordingError.invalid("此地图已保存。")
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(map).write(to: url, options: .atomic)
        paths[map.id] = url
    }

    public func importCopy(from url: URL) throws -> RecordedMap {
        let original = try read(from: url)
        let copy = RecordedMap(name: original.name, anchor: original.anchor,
                               start: original.start, waypoints: original.waypoints)
        try save(copy)
        return copy
    }

    public func fileURL(for map: RecordedMap) throws -> URL {
        let url = paths[map.id] ?? directory.appendingPathComponent(map.id.uuidString + ".json")
        guard FileManager.default.fileExists(atPath: url.path) else { throw RecordingError.invalid("地图文件不存在。") }
        return url
    }

    public func delete(_ map: RecordedMap) throws {
        try FileManager.default.removeItem(at: fileURL(for: map))
        paths.removeValue(forKey: map.id)
    }
}
