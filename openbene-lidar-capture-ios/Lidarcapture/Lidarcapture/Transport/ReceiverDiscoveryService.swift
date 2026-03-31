import Foundation

struct DiscoveredReceiver: Identifiable, Equatable {
    let id: String
    let name: String
    let host: String
    let port: Int

    var wsURL: URL? {
        URL(string: "ws://\(host):\(port)")
    }
}

final class ReceiverDiscoveryService: NSObject, ObservableObject {
    @Published private(set) var receivers: [DiscoveredReceiver] = []
    @Published private(set) var isBrowsing: Bool = false

    private let browser = NetServiceBrowser()
    private var resolvingServices: [String: NetService] = [:]
    private var resolvedReceivers: [String: DiscoveredReceiver] = [:]
    private let serviceType = "_openbene-capture._tcp."
    private let serviceDomain = "local."

    override init() {
        super.init()
        browser.delegate = self
    }

    func startBrowsing() {
        guard !isBrowsing else { return }
        receivers = []
        resolvedReceivers = [:]
        resolvingServices = [:]
        isBrowsing = true
        browser.searchForServices(ofType: serviceType, inDomain: serviceDomain)
    }

    func stopBrowsing() {
        browser.stop()
        resolvingServices.values.forEach { $0.stop() }
        resolvingServices = [:]
        isBrowsing = false
    }

    private func updateReceivers() {
        receivers = resolvedReceivers.values.sorted { $0.name < $1.name }
    }

    private func ipv4Address(from addresses: [Data]) -> String? {
        for addressData in addresses {
            let addressString = addressData.withUnsafeBytes { pointer -> String? in
                guard let sockaddrPointer = pointer.baseAddress?.assumingMemoryBound(to: sockaddr.self) else {
                    return nil
                }
                guard sockaddrPointer.pointee.sa_family == sa_family_t(AF_INET) else {
                    return nil
                }
                var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                let result = getnameinfo(
                    sockaddrPointer,
                    socklen_t(addressData.count),
                    &hostname,
                    socklen_t(hostname.count),
                    nil,
                    0,
                    NI_NUMERICHOST
                )
                guard result == 0 else { return nil }
                return String(cString: hostname)
            }
            if let addressString {
                return addressString
            }
        }
        return nil
    }
}

extension ReceiverDiscoveryService: NetServiceBrowserDelegate {
    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        let key = "\(service.name).\(service.type)"
        service.delegate = self
        resolvingServices[key] = service
        service.resolve(withTimeout: 5)
    }

    func netServiceBrowserDidStopSearch(_ browser: NetServiceBrowser) {
        DispatchQueue.main.async {
            self.isBrowsing = false
        }
    }
}

extension ReceiverDiscoveryService: NetServiceDelegate {
    func netServiceDidResolveAddress(_ sender: NetService) {
        let key = "\(sender.name).\(sender.type)"
        defer { resolvingServices.removeValue(forKey: key) }
        guard let addresses = sender.addresses,
              let host = ipv4Address(from: addresses) else { return }
        let receiver = DiscoveredReceiver(id: key, name: sender.name, host: host, port: sender.port)
        DispatchQueue.main.async {
            self.resolvedReceivers[key] = receiver
            self.updateReceivers()
        }
    }

    func netService(_ sender: NetService, didNotResolve errorDict: [String : NSNumber]) {
        let key = "\(sender.name).\(sender.type)"
        resolvingServices.removeValue(forKey: key)
    }
}
