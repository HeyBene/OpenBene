import Foundation

/// Numeric detector/control evidence only; never saves camera images.
final class FollowDiagnostics {
    private let queue = DispatchQueue(label: "com.openbene.follow-log")
    private let url: URL
    private let tag: String

    init(fileName: String = "follow.jsonl", tag: String = "Follow") {
        self.tag = tag
        url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Diagnostics/" + fileName)
    }

    func record(_ fields: [String: Any]) {
        var fields = fields
        fields["date"] = ISO8601DateFormatter().string(from: Date())
        guard let data = try? JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys]),
              let line = String(data: data, encoding: .utf8) else { return }
        NSLog("[%@] %@", tag, line)
        let url = url
        queue.async {
            do {
                let fm = FileManager.default
                try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                let size = (try? fm.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue ?? 0
                if size > 2_000_000 {
                    let previous = url.deletingPathExtension().appendingPathExtension("previous.jsonl")
                    if fm.fileExists(atPath: previous.path) { try fm.removeItem(at: previous) }
                    try fm.moveItem(at: url, to: previous)
                }
                if !fm.fileExists(atPath: url.path) { fm.createFile(atPath: url.path, contents: nil) }
                let handle = try FileHandle(forWritingTo: url)
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: Data((line + "\n").utf8))
            } catch { NSLog("[Follow] log write error: %@", error.localizedDescription) }
        }
    }
}
