import Foundation
import CoreBluetooth
import OpenBotNavKit

/// BLE link to the OpenBot ESP32 firmware, matching the UUIDs used by
/// openbene_sdk/src/openbene/esp32_ble.py: one service, an RX characteristic for
/// commands and a TX characteristic for telemetry notifications.
final class OpenBotBleLink: NSObject, RobotLink, CBCentralManagerDelegate, CBPeripheralDelegate {

    /// The 520 chassis in this demo has no ultrasonic module fitted, but the
    /// firmware keeps pinging anyway: the echo pin is left floating, picks up
    /// the trigger pulse and reports 1-3 cm, which the obstacle guard reads as
    /// a wall and refuses to drive through. Subscribe to the sonar stream only
    /// when the module is actually installed.
    static let sonarInstalled = false

    struct Discovered {
        let id: UUID
        let name: String
        let rssi: Int
    }

    let telemetry = Telemetry(sourceName: "ble")
    let serviceUuid = CBUUID(string: OpenBotProtocol.serviceUuid)
    let rxUuid = CBUUID(string: OpenBotProtocol.charRxUuid)
    let txUuid = CBUUID(string: OpenBotProtocol.charTxUuid)

    private(set) var discovered: [Discovered] = []
    private(set) var lastControlFrame: String?
    private(set) var lastControlWriteTime: Date?
    private(set) var lastWriteError: String?
    private var central: CBCentralManager?
    private var peripheral: CBPeripheral?
    private var rxCharacteristic: CBCharacteristic?
    private var txCharacteristic: CBCharacteristic?
    private var pendingIdentifier: UUID?
    private var connectWhenSeen: UUID?
    private var onDiscover: ((CBPeripheral, String, Int) -> Void)?
    private var telemetryStream = OpenBotTelemetryStream()
    private var heartbeatTimer: Timer?
    private var lastWriteTime: TimeInterval = 0
    private var scanRequested = false
    private var lastWasStop = true
    private var lastStopWrite: TimeInterval = 0

    init(targetIdentifier: UUID? = nil) {
        self.pendingIdentifier = targetIdentifier
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
        telemetry.sourceName = "ble"
    }

    // ------------------------------------------------------------------ scanning

    func startScan(_ onDiscover: @escaping (CBPeripheral, String, Int) -> Void) {
        self.onDiscover = onDiscover
        discovered = []
        scanRequested = true
        guard let central = central, central.state == .poweredOn else {
            if let identifier = pendingIdentifier { connect(identifier: identifier) }
            return
        }
        central.scanForPeripherals(
            withServices: nil,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
    }

    func stopScan() {
        scanRequested = false
        central?.stopScan()
    }

    func connect(identifier: UUID) {
        pendingIdentifier = identifier
        guard let central = central else { return }
        guard central.state == .poweredOn else { return }
        let known = central.retrievePeripherals(withIdentifiers: [identifier]).first
        if let known = known {
            peripheral = known
            known.delegate = self
            central.connect(known, options: nil)
            telemetry.sourceName = "ble (reconnecting)"
        } else {
            // Not cached yet: listen until the scan hears it again.
            connectWhenSeen = identifier
            central.scanForPeripherals(withServices: nil, options: nil)
        }
    }

    // ------------------------------------------------------------------- driving

    func drive(left: Double, right: Double) {
        guard let peripheral = peripheral, let rx = rxCharacteristic, telemetry.connected else { return }
        let now = Date().timeIntervalSince1970
        if now - lastWriteTime < 0.04 { return }
        lastWriteTime = now
        lastWasStop = left == 0 && right == 0
        let payload = OpenBotProtocol.ctrlCommand(left: left, right: right)
        let type: CBCharacteristicWriteType = rx.properties.contains(.writeWithoutResponse) ? .withoutResponse : .withResponse
        if type == .withoutResponse && !peripheral.canSendWriteWithoutResponse { return }
        peripheral.writeValue(payload, for: rx, type: type)
        noteControlWrite(payload)
    }

    func stop() {
        guard let peripheral = peripheral, let rx = rxCharacteristic else { return }
        let now = Date().timeIntervalSince1970
        // A stop following a turn or straight command must not be lost to the
        // drive rate limit, especially at a node or when AR tracking is lost.
        guard !lastWasStop || now - lastStopWrite >= 0.25 else { return }
        lastWasStop = true
        lastStopWrite = now
        lastWriteTime = now
        let type: CBCharacteristicWriteType = rx.properties.contains(.write) ? .withResponse : .withoutResponse
        let payload = OpenBotProtocol.ctrlCommand(left: 0, right: 0)
        peripheral.writeValue(payload, for: rx, type: type)
        noteControlWrite(payload)
    }

    private func noteControlWrite(_ payload: Data) {
        lastControlFrame = String(decoding: payload, as: UTF8.self).trimmingCharacters(in: .newlines)
        lastControlWriteTime = Date()
    }

    func close() {
        stop()
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
        if let peripheral = peripheral, central?.state == .poweredOn {
            // Keep the link alive briefly so the final stop can be transmitted.
            let central = central
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { central?.cancelPeripheralConnection(peripheral) }
        }
        telemetry.connected = false
    }

    // ------------------------------------------------------------ central events

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            if let identifier = pendingIdentifier {
                connect(identifier: identifier)
            } else if scanRequested {
                central.scanForPeripherals(withServices: nil, options: nil)
            }
        case .unauthorized:
            telemetry.sourceName = "ble (not authorized)"
        default:
            telemetry.connected = false
            break
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        let advertisedName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        let name = advertisedName ?? peripheral.name ?? ""
        let isOpenBot = OpenBotProtocol.isOpenBotName(name)
        guard isOpenBot || peripheral.identifier == connectWhenSeen else { return }

        if !discovered.contains(where: { $0.id == peripheral.identifier }) {
            discovered.append(Discovered(id: peripheral.identifier, name: name.isEmpty ? "OpenBot" : name, rssi: RSSI.intValue))
            onDiscover?(peripheral, name.isEmpty ? "OpenBot" : name, RSSI.intValue)
        }
        if peripheral.identifier == connectWhenSeen {
            connectWhenSeen = nil
            self.peripheral = peripheral
            peripheral.delegate = self
            central.connect(peripheral, options: nil)
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        telemetry.connected = false
        telemetryStream = OpenBotTelemetryStream()
        lastControlFrame = nil
        lastControlWriteTime = nil
        lastWriteError = nil
        peripheral.discoverServices([serviceUuid])
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
        telemetry.connected = false
        rxCharacteristic = nil
        txCharacteristic = nil
        self.peripheral = nil
    }

    // ---------------------------------------------------------- peripheral events

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        for service in peripheral.services ?? [] where service.uuid == serviceUuid {
            peripheral.discoverCharacteristics([rxUuid, txUuid], for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        for characteristic in service.characteristics ?? [] {
            if characteristic.uuid == rxUuid { rxCharacteristic = characteristic }
            if characteristic.uuid == txUuid {
                txCharacteristic = characteristic
                peripheral.setNotifyValue(true, for: characteristic)
            }
        }
        guard let rx = rxCharacteristic,
              rx.properties.contains(.write) || rx.properties.contains(.writeWithoutResponse) else {
            lastWriteError = "底盘 RX 特征不可写。"
            return
        }
        telemetry.connected = true
        enableTelemetry(peripheral)
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        telemetry.connected = false
        telemetry.sourceName = "ble (connection failed)"
    }

    private func enableTelemetry(_ peripheral: CBPeripheral) {
        guard let rx = rxCharacteristic else { return }
        var commands = [
            OpenBotProtocol.heartbeatCommand(intervalMs: 750),
            OpenBotProtocol.sensorStreamCommand(header: "v", intervalMs: 500),
            OpenBotProtocol.sensorStreamCommand(header: "w", intervalMs: 250),
        ]
        if Self.sonarInstalled {
            commands.append(OpenBotProtocol.sensorStreamCommand(header: "s", intervalMs: 250))
        }
        commands.append(OpenBotProtocol.featureCommand())
        let type: CBCharacteristicWriteType = rx.properties.contains(.write) ? .withResponse : .withoutResponse
        for command in commands {
            peripheral.writeValue(command, for: rx, type: type)
        }
        heartbeatTimer?.invalidate()
        // Upstream Vehicle sends h750 every 250 ms; the firmware's watchdog
        // is refreshed by h frames, not by c frames. Keep this on the main
        // queue with AR/BLE so a stalled controller also stops heartbeats.
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            guard let self = self, self.telemetry.connected,
                  let peripheral = self.peripheral, let rx = self.rxCharacteristic else { return }
            peripheral.writeValue(OpenBotProtocol.heartbeatCommand(intervalMs: 750), for: rx,
                                  type: rx.properties.contains(.write) ? .withResponse : .withoutResponse)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard characteristic.uuid == txUuid, let data = characteristic.value else { return }
        let now = Date().timeIntervalSince1970
        telemetryStream.receive(data, to: telemetry, nowS: now, sonarInstalled: Self.sonarInstalled)
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error { lastWriteError = error.localizedDescription }
    }
}
