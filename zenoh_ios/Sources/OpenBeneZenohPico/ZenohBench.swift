import Foundation
import OpenBeneZenoh
import OpenBeneZenohPico

public enum Bench {
    public static func run(endpoint: String, sizes: [Int], count: Int) {
        let session = PicoZenohSession(endpoint: endpoint, mode: .client)
        let t0 = DispatchTime.now().uptimeNanoseconds
        do { try session.open() } catch {
            FileHandle.standardError.write(Data("open failed: \(error)\n".utf8)); exit(1)
        }
        print(String(format: "open: %.0f ms", ms(since: t0)))

        for size in sizes {
            let payload = Data(repeating: 0x41, count: size)
            let start = DispatchTime.now().uptimeNanoseconds
            for _ in 0..<count { try? session.put(key: "openbene/bench/frame", payload: payload) }
            let putMs = ms(since: start) / Double(count)
            print(String(format: "%7d B  put %6.2f ms/frame (%6.1f fps)", size, putMs, 1000 / max(0.001, putMs)))
        }

        let tSettle = DispatchTime.now().uptimeNanoseconds
        Thread.sleep(forTimeInterval: 2.0)
        print(String(format: "settle after burst: %.0f ms (UDP-style drain)", ms(since: tSettle)))

        let tClose = DispatchTime.now().uptimeNanoseconds
        session.close()
        print(String(format: "close: %.0f ms", ms(since: tClose)))
    }

    /// Simulates the real transport path: encode + bounded queue + drain.
    public static func pipeline(endpoint: String, frames: Int, fps: Double, withDepth: Bool) {
        let config = ZenohTransportConfig(robotID: "bench", endpoint: endpoint)
        let session = PicoZenohSession(endpoint: config.endpoint, mode: config.mode)
        let transport = OpenBeneTransport(config: config, session: session)
        let tOpen = DispatchTime.now().uptimeNanoseconds
        do { try transport.start() } catch {
            FileHandle.standardError.write(Data("open failed: \(error)\n".utf8)); exit(1)
        }
        print(String(format: "start: %.0f ms", ms(since: tOpen)))

        let interval = 1.0 / fps
        let tLoop = DispatchTime.now().uptimeNanoseconds
        var rejected = 0
        for index in 0..<frames {
            let frameStart = DispatchTime.now().uptimeNanoseconds
            let frame = CaptureFrame(
                frameID: UInt32(index),
                timestampNs: DispatchTime.now().uptimeNanoseconds,
                rgbJPEG: Data(repeating: 0x42, count: 24_000),
                depthPNG: withDepth ? Data(repeating: 0x43, count: 12_000) : nil,
                confidencePNG: withDepth ? Data(repeating: 0x44, count: 6_000) : nil,
                pose: Array(repeating: 1, count: 16),
                metadata: FrameMetadata(width: 640, height: 480)
            )
            if !transport.publish(frame: frame) { rejected += 1 }
            let elapsed = Double(DispatchTime.now().uptimeNanoseconds - frameStart) / 1_000_000
            let remaining = interval * 1000 - elapsed
            if remaining > 0 { Thread.sleep(forTimeInterval: remaining / 1000) }
        }
        let loopMs = ms(since: tLoop)
        let tFlush = DispatchTime.now().uptimeNanoseconds
        let flushed = transport.flush(timeout: 20)
        let stats = transport.statistics()
        print(String(format: "loop %.0f ms / %d frames = %.1f fps, queue-rejected %d, flush %.0f ms ok=%@, sent %llu",
                     loopMs, frames, Double(frames) / max(0.001, loopMs / 1000), rejected,
                     ms(since: tFlush), flushed ? "yes" : "no", stats.framesSent))
        let tStop = DispatchTime.now().uptimeNanoseconds
        transport.stop()
        print(String(format: "stop: %.0f ms", ms(since: tStop)))
    }

    private static func ms(since nanos: UInt64) -> Double {
        Double(DispatchTime.now().uptimeNanoseconds - nanos) / 1_000_000
    }
}
