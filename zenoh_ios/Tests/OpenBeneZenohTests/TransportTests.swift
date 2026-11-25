import XCTest
@testable import OpenBeneZenoh

final class FakeZenohSession: ZenohSession {
    private let lock = NSLock()
    private(set) var isOpen = false
    private(set) var puts: [(key: String, payload: Data)] = []
    private var handler: ((String, Data) -> Void)?
    var failOpen = false

    func open() throws {
        if failOpen { throw ZenohTransportError.sessionUnavailable("boom") }
        isOpen = true
    }

    func close() { isOpen = false }

    func put(key: String, payload: Data) throws {
        guard isOpen else { throw ZenohTransportError.notRunning }
        lock.lock(); puts.append((key, payload)); lock.unlock()
    }

    func subscribe(key: String, handler: @escaping (String, Data) -> Void) throws -> ZenohSubscription {
        self.handler = handler
        return FakeSubscription()
    }

    func emitCommand(_ json: String) {
        handler?("openbene/rtr520/cmd", Data(json.utf8))
    }

    func payloads(for key: String) -> [Data] {
        lock.lock(); defer { lock.unlock() }
        return puts.filter { $0.key == key }.map(\.payload)
    }
}

private final class FakeSubscription: ZenohSubscription {
    func cancel() {}
}

final class TransportTests: XCTestCase {
    private func makeTransport(session: FakeZenohSession, legacy: Bool = false) -> OpenBeneTransport {
        var clock: Int64 = 1_000
        return OpenBeneTransport(
            config: ZenohTransportConfig(
                robotID: "rtr520",
                endpoint: "tcp/127.0.0.1:7447",
                publishLegacyVideo: legacy,
                maxQueuedFrames: 2,
                sessionID: "session-1"
            ),
            session: session,
            nowMs: { clock += 1; return clock }
        )
    }

    func testStartPublishesPresenceAndSessionStart() throws {
        let session = FakeZenohSession()
        let transport = makeTransport(session: session)
        try transport.start()
        defer { transport.stop() }

        let statuses = session.payloads(for: "openbene/rtr520/status")
        XCTAssertEqual(statuses.count, 1)
        let status = try XCTUnwrap(JSONSerialization.jsonObject(with: statuses[0]) as? [String: Any])
        XCTAssertEqual(status["state"] as? String, "online")

        let sessionEvents = session.payloads(for: "openbene/rtr520/session")
        let event = try XCTUnwrap(JSONSerialization.jsonObject(with: sessionEvents[0]) as? [String: Any])
        XCTAssertEqual(event["event"] as? String, "start")
        XCTAssertEqual(event["session_id"] as? String, "session-1")
    }

    func testPublishWritesPacketAndOptionalLegacyVideo() throws {
        let session = FakeZenohSession()
        let transport = makeTransport(session: session, legacy: true)
        try transport.start()
        defer { transport.stop() }

        let frame = CaptureFrame(
            frameID: 3,
            timestampNs: 42,
            rgbJPEG: Data([0xFF, 0xD8]),
            metadata: FrameMetadata(width: 640, height: 480)
        )
        XCTAssertTrue(transport.publish(frame: frame))
        XCTAssertTrue(transport.flush())

        let packets = session.payloads(for: "openbene/rtr520/frame")
        XCTAssertEqual(packets.count, 1)
        XCTAssertEqual(try FrameCodec.decodeCaptureFrame(packets[0]).frameID, 3)

        let videos = session.payloads(for: "openbene/rtr520/video")
        XCTAssertEqual(videos.count, 1)
        XCTAssertEqual(try FrameCodec.decodeLegacyVideoFrame(videos[0]).jpeg, Data([0xFF, 0xD8]))

        let stats = transport.statistics()
        XCTAssertEqual(stats.framesSent, 1)
        XCTAssertEqual(stats.framesDropped, 0)
    }

    func testQueueDropsWhenFull() throws {
        let session = BlockingSession()
        let transport = OpenBeneTransport(
            config: ZenohTransportConfig(
                robotID: "rtr520",
                endpoint: "tcp/127.0.0.1:7447",
                maxQueuedFrames: 1,
                sessionID: "s"
            ),
            session: session
        )
        try transport.start()
        defer { session.unblock(); transport.stop() }

        // Wait until the worker is parked inside the first frame's put, so the
        // second frame deterministically fills the one-slot queue.
        XCTAssertTrue(transport.publish(frame: makeFrame(1)))
        XCTAssertTrue(session.waitUntilBlocked())
        XCTAssertTrue(transport.publish(frame: makeFrame(2)))
        XCTAssertFalse(transport.publish(frame: makeFrame(3)))
        XCTAssertEqual(transport.queueSnapshot.dropped, 1)
    }

    func testRoutesCommandsToCallback() throws {
        let session = FakeZenohSession()
        let transport = makeTransport(session: session)
        var received: RobotCommand?
        transport.onCommand = { received = $0 }
        try transport.start()
        defer { transport.stop() }

        session.emitCommand(#"{"cmd":"stop","seq":5}"#)
        XCTAssertEqual(received, .stop(sequence: 5, sentAtMs: 0))
        XCTAssertEqual(transport.statistics().commandsReceived, 1)
    }

    func testStopPublishesOfflineStatus() throws {
        let session = FakeZenohSession()
        let transport = makeTransport(session: session)
        try transport.start()
        transport.stop()

        let statuses = session.payloads(for: "openbene/rtr520/status")
        XCTAssertEqual(statuses.count, 2)
        let last = try XCTUnwrap(JSONSerialization.jsonObject(with: statuses[1]) as? [String: Any])
        XCTAssertEqual(last["state"] as? String, "offline")
        XCTAssertFalse(transport.isRunning)
    }

    private func makeFrame(_ id: UInt32) -> CaptureFrame {
        CaptureFrame(frameID: id, timestampNs: UInt64(id), rgbJPEG: Data([1]), metadata: FrameMetadata(width: 1, height: 1))
    }
}

/// Blocks the first `put` so the queue can be observed while full.
private final class BlockingSession: ZenohSession {
    private let gate = DispatchSemaphore(value: 0)
    private let entered = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var putCount = 0
    private(set) var isOpen = false

    func open() throws { isOpen = true }
    func close() { isOpen = false; unblock() }

    func put(key: String, payload: Data) throws {
        lock.lock()
        putCount += 1
        // `start()` publishes status and the session event first; block the
        // first capture frame so the bounded queue can be observed full.
        let shouldBlock = putCount == 3
        lock.unlock()
        if shouldBlock {
            entered.signal()
            gate.wait()
        }
    }

    func subscribe(key: String, handler: @escaping (String, Data) -> Void) throws -> ZenohSubscription {
        FakeSubscription()
    }

    func unblock() { gate.signal() }

    func waitUntilBlocked() -> Bool {
        entered.wait(timeout: .now() + 2) == .success
    }
}
