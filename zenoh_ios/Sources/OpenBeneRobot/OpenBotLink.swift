import CoreBluetooth
import Foundation

/// Scans for and talks to the OpenBot ESP32 over BLE.
///
/// CoreBluetooth delivers callbacks on the main queue, so this class is
/// main-actor isolated and can drive SwiftUI state directly.
@MainActor
public final class OpenBotLink: NSObject, ObservableObject {
    public struct Device: Identifiable, Equatable {
        public let id: UUID
        public let name: String
        public let rssi: Int
    }

    @Published public private(set) var isScanning = false
    @Published public private(set) var devices: [Device] = []
    @Published public private(set) var isConnected = false
    @Published public private(set) var connectedName: String?
    @Published public private(set) var voltage: Double?
    @Published public private(set) var sonarCm: Int?
    @Published public private(set) var leftRPM: Double?
    @Published public private(set) var rightRPM: Double?
    @Published public private(set) var bumper: String?
    @Published public private(set) var robotType: String?
    @Published public private(set) var lastError: String?
    @Published public private(set) var lastSent: WheelCommand = .stop
    @Published public private(set) var sentCommands = 0

    private var central: CBCentralManager?
    private var peripheral: CBPeripheral?
    private var writeCharacteristic: CBCharacteristic?
    private var notifyCharacteristic: CBCharacteristic?
    private var heartbeat: Timer?
    private var watchdog: Timer?
    private var lineBuffer = ""

    public override init() {
        super.init()
    }

    public var bluetoothStateText: String {
        switch central?.state {
        case .poweredOn: return "蓝牙可用"
        case .poweredOff: return "蓝牙未开启"
        case .unauthorized: return "未授权蓝牙"
        case .unsupported: return "设备不支持蓝牙"
        case .resetting: return "蓝牙正在重置"
        case .unknown, nil: return "正在初始化蓝牙"
        @unknown default: return "蓝牙状态未知"
        }
    }

    // MARK: - Scanning

    public func startScanning() {
        lastError = nil
        devices = []
        if central == nil {
            central = CBCentralManager(delegate: self, queue: .main)
            return // scanning starts once the manager is powered on
        }
        beginScan()
    }

    public func stopScanning() {
        central?.stopScan()
        isScanning = false
    }

    private func beginScan() {
        guard let central, central.state == .poweredOn else { return }
        devices = []
        isScanning = true
        central.scanForPeripherals(
            withServices: nil,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
    }

    public func connect(_ device: Device) {
        guard let central,
              let target = central.retrievePeripherals(withIdentifiers: [device.id]).first else {
            lastError = "找不到刚扫描到的设备，请重新扫描"
            return
        }
        lastError = nil
        peripheral = target
        target.delegate = self
        central.connect(target, options: nil)
    }

    public func disconnect() {
        stopTimers()
        if let peripheral {
            central?.cancelPeripheralConnection(peripheral)
        }
        resetConnection()
    }

    private func resetConnection() {
        peripheral = nil
        writeCharacteristic = nil
        notifyCharacteristic = nil
        isConnected = false
        connectedName = nil
        voltage = nil
        sonarCm = nil
        leftRPM = nil
        rightRPM = nil
        bumper = nil
        robotType = nil
        lastSent = .stop
    }

    // MARK: - Commands

    /// Sends one drive command. While a key is held the app repeats this; on
    /// release it calls `stop()`.
    public func send(_ command: WheelCommand) {
        guard isConnected, let peripheral, let characteristic = writeCharacteristic else {
            lastError = "尚未连接 OpenBot"
            return
        }
        lastSent = command
        peripheral.writeValue(
            OpenBotBLE.driveCommand(left: command.left, right: command.right),
            for: characteristic,
            type: .withoutResponse
        )
        sentCommands += 1
        armWatchdog()
    }

    public func stop() {
        watchdog?.invalidate()
        watchdog = nil
        guard isConnected, let peripheral, let characteristic = writeCharacteristic else { return }
        lastSent = .stop
        peripheral.writeValue(
            OpenBotBLE.driveCommand(left: 0, right: 0),
            for: characteristic,
            type: .withoutResponse
        )
    }

    /// Safety net: if the app stops sending (key released, view dismissed,
    /// connection hiccup) the robot gets an explicit stop shortly after.
    private func armWatchdog() {
        watchdog?.invalidate()
        watchdog = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.stop() }
        }
    }

    // MARK: - Handshake

    private func writeRaw(_ data: Data) {
        guard let peripheral, let characteristic = writeCharacteristic else { return }
        peripheral.writeValue(data, for: characteristic, type: .withoutResponse)
    }

    private func requestFeatures() {
        writeRaw(OpenBotBLE.featureCommand())
        writeRaw(OpenBotBLE.sensorStreamCommand("v", intervalMs: 500))
        writeRaw(OpenBotBLE.sensorStreamCommand("w", intervalMs: 500))
        writeRaw(OpenBotBLE.sensorStreamCommand("s", intervalMs: 500))
        startHeartbeat()
    }

    private func startHeartbeat() {
        heartbeat?.invalidate()
        heartbeat = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isConnected else { return }
                self.writeRaw(OpenBotBLE.heartbeatCommand(intervalMs: 300))
            }
        }
    }

    private func stopTimers() {
        heartbeat?.invalidate()
        heartbeat = nil
        watchdog?.invalidate()
        watchdog = nil
    }

    private func ingest(_ data: Data) {
        let text = String(decoding: data, as: UTF8.self)
            .replacingOccurrences(of: "\0", with: "")
        lineBuffer += text
        // Firmware notifications may arrive without a trailing newline, so
        // every chunk is also treated as a complete message.
        let lines = lineBuffer.split(whereSeparator: { $0 == "\n" || $0 == "\r" }).map(String.init)
        lineBuffer = ""
        for line in lines where !line.isEmpty {
            apply(OpenBotTelemetry.parse(line))
        }
    }

    private func apply(_ telemetry: OpenBotTelemetry) {
        switch telemetry {
        case .voltage(let value): voltage = value
        case .sonar(let cm): sonarCm = cm
        case .wheel(let left, let right):
            leftRPM = left
            rightRPM = right
        case .bumper(let id): bumper = id
        case .features(let type, _): robotType = type
        case .unknown: break
        }
    }
}

// MARK: - CBCentralManagerDelegate

extension OpenBotLink: CBCentralManagerDelegate {
    public nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Task { @MainActor in
            if central.state == .poweredOn, self.peripheral == nil {
                self.beginScan()
            }
        }
    }

    public nonisolated func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        let advertised = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        let name = advertised ?? peripheral.name ?? "未命名设备"
        Task { @MainActor in
            guard self.devices.contains(where: { $0.id == peripheral.identifier }) == false else {
                return
            }
            self.devices.append(Device(id: peripheral.identifier, name: name, rssi: RSSI.intValue))
        }
    }

    public nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        Task { @MainActor in
            self.isScanning = false
            self.central?.stopScan()
            self.connectedName = peripheral.name ?? "OpenBot"
            peripheral.discoverServices([CBUUID(string: OpenBotBLE.serviceUUID)])
        }
    }

    public nonisolated func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: Error?
    ) {
        Task { @MainActor in
            self.lastError = error?.localizedDescription ?? "连接失败"
            self.resetConnection()
        }
    }

    public nonisolated func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        Task { @MainActor in
            self.lastError = error.map { "连接已断开：\($0.localizedDescription)" }
            self.stopTimers()
            self.resetConnection()
        }
    }
}

// MARK: - CBPeripheralDelegate

extension OpenBotLink: CBPeripheralDelegate {
    public nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard error == nil else {
            Task { @MainActor in self.lastError = error?.localizedDescription }
            return
        }
        for service in peripheral.services ?? [] where service.uuid == CBUUID(string: OpenBotBLE.serviceUUID) {
            peripheral.discoverCharacteristics(
                [CBUUID(string: OpenBotBLE.rxUUID), CBUUID(string: OpenBotBLE.txUUID)],
                for: service
            )
        }
    }

    public nonisolated func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        guard error == nil else {
            Task { @MainActor in self.lastError = error?.localizedDescription }
            return
        }
        let rx = service.characteristics?.first { $0.uuid == CBUUID(string: OpenBotBLE.rxUUID) }
        let tx = service.characteristics?.first { $0.uuid == CBUUID(string: OpenBotBLE.txUUID) }
        Task { @MainActor in
            self.writeCharacteristic = rx
            self.notifyCharacteristic = tx
            if let tx {
                peripheral.setNotifyValue(true, for: tx)
            }
            self.isConnected = rx != nil
            if rx == nil {
                self.lastError = "设备缺少 OpenBot 写入特征，可能不是 OpenBot 固件"
            } else {
                self.requestFeatures()
            }
        }
    }

    public nonisolated func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        guard error == nil, let data = characteristic.value else { return }
        Task { @MainActor in self.ingest(data) }
    }
}
