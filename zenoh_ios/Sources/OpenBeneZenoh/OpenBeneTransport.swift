import Foundation

/// Publishes capture frames, status and telemetry over a `ZenohSession`, and
/// routes incoming control commands back to the app.
///
/// Frames go through a bounded queue drained by a single worker queue. A slow
/// or disconnected PC therefore drops frames instead of blocking ARKit capture.
public final class OpenBeneTransport {
    public let config: ZenohTransportConfig

    /// Invoked on the Zenoh reader thread. Hop to the main actor before
    /// touching UI state.
    public var onCommand: ((RobotCommand) -> Void)?
    public var onStateChange: ((Bool, String?) -> Void)?

    private let session: ZenohSession
    private let nowMs: () -> Int64
    private let lock = NSLock()
    private let sendQueue = DispatchQueue(label: "io.openbene.zenoh.send", qos: .userInitiated)
    private let heartbeatQueue = DispatchQueue(label: "io.openbene.zenoh.heartbeat", qos: .utility)

    private var pending: [CaptureFrame] = []
    private var draining = false
    private var running = false
    private var subscription: ZenohSubscription?
    private var heartbeat: DispatchSourceTimer?
    private var stats = TransportStats()

    public init(
        config: ZenohTransportConfig,
        session: ZenohSession,
        nowMs: @escaping () -> Int64 = { Int64(Date().timeIntervalSince1970 * 1000) }
    ) {
        self.config = config
        self.session = session
        self.nowMs = nowMs
    }

    public var isRunning: Bool {
        lock.lock()
        defer { lock.unlock() }
        return running
    }

    public var queueSnapshot: QueueSnapshot {
        lock.lock()
        defer { lock.unlock() }
        return QueueSnapshot(pending: pending.count, dropped: stats.framesDropped)
    }

    public func statistics() -> TransportStats {
        lock.lock()
        defer { lock.unlock() }
        return stats
    }

    public func start() throws {
        lock.lock()
        let alreadyRunning = running
        lock.unlock()
        guard !alreadyRunning else { return }

        try session.open()
        do {
            try session.put(
                key: config.statusKey,
                payload: StatusMessage(robotID: config.robotID, connected: true, timestampMs: nowMs()).jsonData()
            )
            try session.put(
                key: config.sessionKey,
                payload: SessionEvent(
                    kind: .start,
                    sessionID: config.sessionID,
                    robotID: config.robotID,
                    timestampMs: nowMs()
                ).jsonData()
            )
            let subscription = try session.subscribe(key: config.commandKey) { [weak self] _, payload in
                guard let self else { return }
                let command = RobotCommand.parse(payload)
                self.lock.lock()
                self.stats.commandsReceived += 1
                self.lock.unlock()
                self.onCommand?(command)
            }

            lock.lock()
            running = true
            self.subscription = subscription
            lock.unlock()
        } catch {
            session.close()
            throw error
        }

        startHeartbeat()
        onStateChange?(true, nil)
    }

    public func stop() {
        lock.lock()
        let wasRunning = running
        running = false
        let pendingFrames = pending
        pending = []
        stats.framesDropped += UInt64(pendingFrames.count)
        lock.unlock()
        guard wasRunning else { return }

        heartbeat?.cancel()
        heartbeat = nil

        if session.isOpen {
            try? session.put(
                key: config.sessionKey,
                payload: SessionEvent(
                    kind: .stop,
                    sessionID: config.sessionID,
                    robotID: config.robotID,
                    timestampMs: nowMs()
                ).jsonData()
            )
            try? session.put(
                key: config.statusKey,
                payload: StatusMessage(robotID: config.robotID, connected: false, timestampMs: nowMs()).jsonData()
            )
        }

        lock.lock()
        let currentSubscription = subscription
        subscription = nil
        lock.unlock()
        currentSubscription?.cancel()
        session.close()
        onStateChange?(false, nil)
    }

    @discardableResult
    public func publish(frame: CaptureFrame) -> Bool {
        lock.lock()
        guard running else {
            lock.unlock()
            return false
        }
        guard pending.count < config.maxQueuedFrames else {
            stats.framesDropped += 1
            lock.unlock()
            return false
        }
        pending.append(frame)
        stats.framesQueued += 1
        let shouldStart = !draining
        draining = true
        lock.unlock()

        if shouldStart {
            sendQueue.async { [weak self] in self?.drain() }
        }
        return true
    }

    public func publish(telemetry: TelemetryMessage) {
        guard session.isOpen else { return }
        do {
            try session.put(key: config.telemetryKey, payload: telemetry.jsonData())
            lock.lock()
            stats.bytesSent += 1
            lock.unlock()
        } catch {
            lock.lock()
            stats.publishErrors += 1
            lock.unlock()
        }
    }

    public func publish(sensors: SensorSamples) {
        guard session.isOpen else { return }
        do {
            try session.put(key: config.sensorKey, payload: sensors.jsonData())
        } catch {
            lock.lock()
            stats.publishErrors += 1
            lock.unlock()
        }
    }

    /// Blocks until queued frames are drained or the timeout elapses. Intended
    /// for tests and for a clean shutdown; never call it from the send queue.
    @discardableResult
    public func flush(timeout: TimeInterval = 5) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            lock.lock()
            let empty = pending.isEmpty
            lock.unlock()
            if empty { return true }
            Thread.sleep(forTimeInterval: 0.01)
        }
        lock.lock()
        let empty = pending.isEmpty
        lock.unlock()
        return empty
    }

    private func drain() {
        while true {
            lock.lock()
            guard !pending.isEmpty else {
                draining = false
                lock.unlock()
                return
            }
            let frame = pending.removeFirst()
            lock.unlock()

            do {
                let packet = FrameCodec.encodeCaptureFrame(frame)
                try session.put(key: config.frameKey, payload: packet)
                var bytes = UInt64(packet.count)

                if config.publishLegacyVideo, let jpeg = frame.rgbJPEG {
                    let legacy = FrameCodec.encodeLegacyVideoFrame(
                        jpeg: jpeg,
                        frameID: frame.frameID,
                        timestampNs: frame.timestampNs
                    )
                    try session.put(key: config.videoKey, payload: legacy)
                    bytes += UInt64(legacy.count)
                }

                lock.lock()
                stats.framesSent += 1
                stats.bytesSent += bytes
                lock.unlock()
            } catch {
                lock.lock()
                stats.publishErrors += 1
                lock.unlock()
            }
        }
    }

    private func startHeartbeat() {
        let timer = DispatchSource.makeTimerSource(queue: heartbeatQueue)
        let interval = max(0.5, config.statusInterval)
        timer.schedule(deadline: .now() + interval, repeating: interval)
        timer.setEventHandler { [weak self] in
            guard let self, self.session.isOpen else { return }
            try? self.session.put(
                key: self.config.statusKey,
                payload: StatusMessage(
                    robotID: self.config.robotID,
                    connected: true,
                    timestampMs: self.nowMs()
                ).jsonData()
            )
        }
        heartbeat = timer
        timer.resume()
    }
}
