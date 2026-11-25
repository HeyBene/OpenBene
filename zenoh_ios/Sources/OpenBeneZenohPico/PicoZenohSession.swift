import COpenBeneZenohBridge
import Foundation
import OpenBeneZenoh

/// `ZenohSession` backed by the zenoh-pico static library shipped in
/// `Vendor/CZenohPico.xcframework`.
///
/// The C bridge owns the move-only zenoh-pico handles; this class only keeps a
/// pointer, a lock, and the Swift callbacks that must outlive each subscription.
public final class PicoZenohSession: ZenohSession {
    private var handle: OpaquePointer?
    private let lock = NSLock()
    private var subscriptions: [UInt64: SubscriptionBox] = [:]

    public let endpoint: String
    public let mode: ZenohSessionMode

    public init(endpoint: String, mode: ZenohSessionMode = .client) {
        self.endpoint = OpenBeneProtocol.normalizeEndpoint(endpoint) ?? "tcp/127.0.0.1:7447"
        self.mode = mode
    }

    public static var zenohVersion: String {
        String(cString: obz_version())
    }

    public var isOpen: Bool {
        lock.lock()
        defer { lock.unlock() }
        guard let handle else { return false }
        return obz_session_is_open(handle) != 0
    }

    public func open() throws {
        lock.lock()
        let alreadyOpen = handle != nil
        lock.unlock()
        guard !alreadyOpen else { return }

        var errorBuffer = [CChar](repeating: 0, count: 256)
        let opened = endpoint.withCString { endpointPointer in
            mode.rawValue.withCString { modePointer in
                obz_open_session(endpointPointer, modePointer, &errorBuffer, errorBuffer.count)
            }
        }
        guard let opened else {
            let message = String(cString: errorBuffer)
            throw ZenohTransportError.sessionUnavailable(message.isEmpty ? "open failed" : message)
        }

        lock.lock()
        handle = opened
        lock.unlock()
    }

    public func close() {
        lock.lock()
        let current = handle
        handle = nil
        subscriptions.removeAll()
        lock.unlock()
        if let current {
            obz_close_session(current)
        }
    }

    public func put(key: String, payload: Data) throws {
        lock.lock()
        let session = handle
        lock.unlock()
        guard let session else { throw ZenohTransportError.notRunning }

        let result: Int32 = key.withCString { keyPointer in
            payload.withUnsafeBytes { raw in
                obz_put(session, keyPointer, raw.bindMemory(to: UInt8.self).baseAddress, payload.count)
            }
        }
        guard result == 0 else { throw ZenohTransportError.publishFailed(code: result) }
    }

    public func subscribe(
        key: String,
        handler: @escaping (String, Data) -> Void
    ) throws -> ZenohSubscription {
        lock.lock()
        let session = handle
        lock.unlock()
        guard let session else { throw ZenohTransportError.notRunning }

        let box = SubscriptionBox(handler: handler)
        let context = Unmanaged.passUnretained(box).toOpaque()
        let id: UInt64 = key.withCString { keyPointer in
            obz_subscribe(session, keyPointer, obzSampleTrampoline, context)
        }
        guard id != 0 else { throw ZenohTransportError.subscribeFailed(code: -1) }

        lock.lock()
        subscriptions[id] = box
        lock.unlock()

        return PicoSubscription(owner: self, id: id)
    }

    fileprivate func cancelSubscription(id: UInt64) {
        lock.lock()
        let session = handle
        lock.unlock()
        // Undeclare before dropping the Swift box so an in-flight callback
        // still has a live handler to call.
        if let session {
            _ = obz_unsubscribe(session, id)
        }
        lock.lock()
        subscriptions.removeValue(forKey: id)
        lock.unlock()
    }

    deinit {
        close()
    }
}

private final class SubscriptionBox {
    let handler: (String, Data) -> Void

    init(handler: @escaping (String, Data) -> Void) {
        self.handler = handler
    }
}

private final class PicoSubscription: ZenohSubscription {
    private weak var owner: PicoZenohSession?
    private let id: UInt64
    private var cancelled = false

    init(owner: PicoZenohSession, id: UInt64) {
        self.owner = owner
        self.id = id
    }

    func cancel() {
        guard !cancelled else { return }
        cancelled = true
        owner?.cancelSubscription(id: id)
    }

    deinit { cancel() }
}

private func obzSampleTrampoline(
    _ key: UnsafePointer<CChar>?,
    _ payload: UnsafePointer<UInt8>?,
    _ length: Int,
    _ context: UnsafeMutableRawPointer?
) {
    guard let context else { return }
    let box = Unmanaged<SubscriptionBox>.fromOpaque(context).takeUnretainedValue()
    let keyString = key.map { String(cString: $0) } ?? ""
    let data: Data
    if let payload, length > 0 {
        data = Data(bytes: payload, count: length)
    } else {
        data = Data()
    }
    box.handler(keyString, data)
}
