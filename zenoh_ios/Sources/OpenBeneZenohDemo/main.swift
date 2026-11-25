import Foundation
import OpenBeneZenoh
import OpenBeneZenohPico

// Small command line harness used to validate the SDK against the PC receiver
// without an iPhone. It exercises the same publish/subscribe path as the app.

struct Options {
    var command: String = "help"
    var endpoint = "tcp/127.0.0.1:7447"
    var robotID = "rtr520"
    var frames = 30
    var fps = 10.0
    var seconds = 10.0
    var key = "openbene/**"
    var legacyVideo = false
    var mode: ZenohSessionMode = .client
    var withDepth = true
}

func parseOptions(_ arguments: [String]) -> Options {
    var options = Options()
    if let first = arguments.first, !first.hasPrefix("--") {
        options.command = first
    }
    var index = options.command == "help" ? 0 : 1
    while index < arguments.count {
        let argument = arguments[index]
        func next() -> String? {
            index += 1
            return index < arguments.count ? arguments[index] : nil
        }
        switch argument {
        case "--endpoint": options.endpoint = next() ?? options.endpoint
        case "--robot": options.robotID = next() ?? options.robotID
        case "--frames": options.frames = Int(next() ?? "") ?? options.frames
        case "--fps": options.fps = Double(next() ?? "") ?? options.fps
        case "--seconds": options.seconds = Double(next() ?? "") ?? options.seconds
        case "--key": options.key = next() ?? options.key
        case "--legacy-video": options.legacyVideo = true
        case "--peer": options.mode = .peer
        case "--no-depth": options.withDepth = false
        default: break
        }
        index += 1
    }
    return options
}

func usage() {
    print("""
    openbene-zenoh-demo — OpenBene Zenoh transport harness

      publish    --endpoint tcp/127.0.0.1:7447 [--robot rtr520] [--frames 30] [--fps 10]
                 [--legacy-video] [--peer] [--no-depth]
      subscribe  --endpoint tcp/127.0.0.1:7447 [--key 'openbene/**'] [--seconds 10] [--peer]
      version
    """)
}

func payloads(frameID: UInt32, robotID: String, withDepth: Bool) -> CaptureFrame {
    let jpegSize = 24_000
    let jpeg = Data((0..<jpegSize).map { UInt8(($0 &* 31 &+ Int(frameID)) & 0xFF) })
    let depth = withDepth
        ? Data((0..<12_000).map { UInt8(($0 &* 17 &+ Int(frameID)) & 0xFF) })
        : nil
    let confidence = withDepth
        ? Data((0..<6_000).map { UInt8(($0 &* 7 &+ Int(frameID)) & 0xFF) })
        : nil
    return CaptureFrame(
        frameID: frameID,
        timestampNs: DispatchTime.now().uptimeNanoseconds,
        rgbJPEG: jpeg,
        depthPNG: depth,
        confidencePNG: confidence,
        pose: (0..<16).map { Float($0) },
        metadata: FrameMetadata(
            width: 640,
            height: 480,
            depthWidth: withDepth ? 256 : 0,
            depthHeight: withDepth ? 192 : 0,
            fx: 500, fy: 500, cx: 320, cy: 240,
            trackingState: "normal",
            depthSource: withDepth ? "scene_depth" : "none",
            confidenceWidth: withDepth ? 256 : 0,
            confidenceHeight: withDepth ? 192 : 0
        )
    )
}

let options = parseOptions(Array(CommandLine.arguments.dropFirst()))

switch options.command {
case "publish":
    let config = ZenohTransportConfig(
        robotID: options.robotID,
        endpoint: options.endpoint,
        mode: options.mode,
        publishLegacyVideo: options.legacyVideo
    )
    let session = PicoZenohSession(endpoint: config.endpoint, mode: config.mode)
    let transport = OpenBeneTransport(config: config, session: session)
    transport.onCommand = { command in
        print("[cmd] \(command)")
    }
    do {
        try transport.start()
    } catch {
        FileHandle.standardError.write(Data("open failed: \(error)\n".utf8))
        exit(1)
    }
    print("publishing \(options.frames) frames to \(config.frameKey) via \(config.endpoint) (zenoh-pico \(PicoZenohSession.zenohVersion))")
    for frame in 0..<UInt32(max(1, options.frames)) {
        transport.publish(frame: payloads(frameID: frame, robotID: config.robotID, withDepth: options.withDepth))
        Thread.sleep(forTimeInterval: 1.0 / max(0.1, options.fps))
    }
    _ = transport.flush()
    let stats = transport.statistics()
    print("sent=\(stats.framesSent) dropped=\(stats.framesDropped) bytes=\(stats.bytesSent) errors=\(stats.publishErrors)")
    transport.stop()

case "subscribe":
    let session = PicoZenohSession(endpoint: options.endpoint, mode: options.mode)
    let counter = Counter()
    do {
        try session.open()
        _ = try session.subscribe(key: options.key) { key, data in
            counter.add(key: key, bytes: data.count)
        }
    } catch {
        FileHandle.standardError.write(Data("open failed: \(error)\n".utf8))
        exit(1)
    }
    print("subscribed to \(options.key) on \(options.endpoint)")
    Thread.sleep(forTimeInterval: max(0.5, options.seconds))
    counter.printSummary()
    session.close()

case "version":
    print("zenoh-pico \(PicoZenohSession.zenohVersion)")

default:
    usage()
}

final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var counts: [String: (messages: Int, bytes: Int)] = [:]

    func add(key: String, bytes: Int) {
        lock.lock()
        var entry = counts[key] ?? (0, 0)
        entry.messages += 1
        entry.bytes += bytes
        counts[key] = entry
        lock.unlock()
    }

    func printSummary() {
        lock.lock()
        let snapshot = counts
        lock.unlock()
        for key in snapshot.keys.sorted() {
            let entry = snapshot[key]!
            print("\(key): \(entry.messages) messages, \(entry.bytes) bytes")
        }
    }
}
