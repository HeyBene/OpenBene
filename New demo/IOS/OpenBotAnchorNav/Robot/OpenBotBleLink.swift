import Foundation
import CoreBluetooth

/// BLE link to the OpenBot ESP32 firmware, matching the UUIDs used by
/// openbene_sdk/src/openbene/esp32_ble.py: one service, an RX characteristic for
/// commands and a TX characteristic for telemetry notifications.
final class OpenBotBleLink: NSObject, RobotLink, CBCentralManagerDelegate, CBPeripheralDelegate {

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
    private var central: CBCentralManager?
    private var peripheral: CBPeripheral?
    private var rxCharacteristic: CBCharacteristic?
    private var txCharacteristic: CBCharacteristic?
    private var pendingIdentifier: UUID?
    private var connectWhenSeen: UUID?
    private var onDiscover: ((CBPeripheral, String, Int) -> Void)?
    private var lineBuffer = ""
    private var lastWriteTime: TimeInterval = 0

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
        }
    }

    // ------------------------------------------------------------------- driving

    func drive(left: Double, right: Double) {
        guard let peripheral = peripheral, let rx = rxCharacteristic else { return }
        let now = Date().timeIntervalSince1970
        if now - lastWriteTime < 0.04 { return }
        lastWriteTime = now
        let payload = OpenBotProtocol.ctrlCommand(left: left, right: right)
        peripheral.writeValue(payload, for: rx, type: .withoutResponse)
    }

    func stop() {
        drive(left: 0.0, right: 0.0)
    }

    func close() {
        stop()
        if let peripheral = peripheral, central?.state == .poweredOn {
            central?.cancelPeripheralConnection(peripheral)
        }
        telemetry.connected = false
    }

    // ------------------------------------------------------------ central events

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            if let identifier = connectWhenSeen {
                connectWhenSeen = nil
                connect(identifier: identifier)
            }
        case .unauthorized:
            telemetry.sourceName = "ble (not authorized)"
        default:
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
        telemetry.connected = true
        peripheral.discoverServices([serviceUuid])
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        telemetry.connected = false
        /* A dropped link drops the robot back to the mock behaviour; the
           executor keeps steering, so reconnecting is left to the user. */
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
        guard rxCharacteristic != nil else { return }
        enableTelemetry(peripheral)
    }

    private func enableTelemetry(_ peripheral: CBPeripheral) {
        guard let rx = rxCharacteristic else { return }
        let commands = [
            OpenBotProtocol.heartbeatCommand(intervalMs: 500),
            OpenBotProtocol.sensorStreamCommand(header: "v", intervalMs: 500),
            OpenBotProtocol.sensorStreamCommand(header: "w", intervalMs: 250),
            OpenBotProtocol.sensorStreamCommand(header: "s", intervalMs: 250),
            OpenBotProtocol.featureCommand(),
        ]
        for command in commands {
            peripheral.writeValue(command, for: rx, type: .withResponse)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard characteristic.uuid == txUuid, let data = characteristic.value else { return }
        let text = String(data: data, encoding: .utf8) ?? ""
        lineBuffer += text
        let now = Date().timeIntervalSince1970
        while let index = lineBuffer.firstIndex(of: "\n") {
            let line = String(lineBuffer[lineBuffer.startIndex..<index])
            lineBuffer.removeSubrange(lineBuffer.startIndex...index)
            OpenBotProtocol.apply(line, to: telemetry, nowS: now)
        }
        if !lineBuffer.isEmpty {
            OpenBotProtocol.apply(lineBuffer, to: telemetry, nowS: now)
            lineBuffer = ""
        }
    }
}
