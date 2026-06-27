import Foundation
import CoreBluetooth

/// Reads live heart rate from a Whoop strap in "Broadcast Heart Rate" mode,
/// which exposes the standard BLE Heart Rate Service (0x180D) / Heart Rate
/// Measurement characteristic (0x2A37).
///
/// CoreBluetooth does NOT work on the iOS Simulator — this provider is only
/// used on a physical device.
final class WhoopBLEProvider: NSObject, LiveHeartRateProvider {

    var onSample: ((HeartRateSample) -> Void)?
    var onStateChange: ((HRConnectionState) -> Void)?

    private let hrService = CBUUID(string: "180D")
    private let hrMeasurement = CBUUID(string: "2A37")

    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var wantRunning = false
    private var broadScanFallback: DispatchWorkItem?

    override init() {
        super.init()
        // queue: nil → delegate callbacks arrive on the main queue.
        central = CBCentralManager(delegate: self, queue: nil)
    }

    func start() {
        wantRunning = true
        if central.state == .poweredOn { beginScan() }
        // otherwise we start once centralManagerDidUpdateState reports poweredOn
    }

    func stop() {
        wantRunning = false
        broadScanFallback?.cancel()
        broadScanFallback = nil
        if central.state == .poweredOn { central.stopScan() }
        if let p = peripheral { central.cancelPeripheralConnection(p) }
        peripheral = nil
        onStateChange?(.idle)
    }

    // MARK: - Scanning

    private func beginScan() {
        guard wantRunning, peripheral == nil else { return }
        onStateChange?(.scanning)

        // Reconnect fast if we already know the strap from a previous session.
        let known = central.retrieveConnectedPeripherals(withServices: [hrService])
        if let p = known.first {
            connect(p)
            return
        }

        // Primary: scan for advertised HR service.
        central.scanForPeripherals(withServices: [hrService], options: nil)

        // Fallback: some Whoop firmware doesn't advertise 0x180D in the
        // advertisement packet. If nothing turns up quickly, scan broadly and
        // match by name, then verify the service after connecting.
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.wantRunning, self.peripheral == nil else { return }
            self.central.stopScan()
            self.central.scanForPeripherals(withServices: nil, options: nil)
        }
        broadScanFallback = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 4, execute: work)
    }

    private func connect(_ p: CBPeripheral) {
        broadScanFallback?.cancel()
        central.stopScan()
        peripheral = p
        p.delegate = self
        onStateChange?(.connecting)
        central.connect(p, options: nil)
    }

    // MARK: - HR packet parsing (BLE Heart Rate Measurement, 0x2A37)

    private func parse(_ data: Data) -> HeartRateSample? {
        let bytes = [UInt8](data)
        guard let flags = bytes.first else { return nil }
        let is16Bit = (flags & 0x01) != 0
        let bpm: Int
        if is16Bit {
            guard bytes.count >= 3 else { return nil }
            bpm = Int(bytes[1]) | (Int(bytes[2]) << 8)
        } else {
            guard bytes.count >= 2 else { return nil }
            bpm = Int(bytes[1])
        }
        // Sensor-contact: bit 2 = supported, bit 1 = contact detected.
        let contactSupported = (flags & 0x04) != 0
        let contact = (flags & 0x02) != 0
        let worn = contactSupported ? contact : true
        return HeartRateSample(bpm: bpm, worn: worn, timestamp: Date())
    }
}

// MARK: - CBCentralManagerDelegate

extension WhoopBLEProvider: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            if wantRunning { beginScan() }
        case .unauthorized:
            onStateChange?(.unauthorized)
        case .poweredOff, .unsupported, .resetting:
            onStateChange?(.unsupported)
        default:
            break
        }
    }

    func centralManager(_ central: CBCentralManager,
                        didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any],
                        rssi RSSI: NSNumber) {
        let advName = (advertisementData[CBAdvertisementDataLocalNameKey] as? String)
            ?? peripheral.name ?? ""
        let advServices = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? []
        let looksLikeHR = advServices.contains(hrService)
        let looksLikeWhoop = advName.uppercased().contains("WHOOP")
        guard looksLikeHR || looksLikeWhoop else { return }
        connect(peripheral)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.discoverServices([hrService])
    }

    func centralManager(_ central: CBCentralManager,
                        didFailToConnect peripheral: CBPeripheral, error: Error?) {
        onStateChange?(.disconnected)
        self.peripheral = nil
        if wantRunning { beginScan() }
    }

    func centralManager(_ central: CBCentralManager,
                        didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        onStateChange?(.disconnected)
        // Keep the reference and let CoreBluetooth reconnect when back in range.
        if wantRunning { central.connect(peripheral, options: nil) }
    }
}

// MARK: - CBPeripheralDelegate

extension WhoopBLEProvider: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let svc = peripheral.services?.first(where: { $0.uuid == hrService }) else {
            // Connected device has no HR service — not our peripheral; keep looking.
            central.cancelPeripheralConnection(peripheral)
            self.peripheral = nil
            if wantRunning { beginScan() }
            return
        }
        peripheral.discoverCharacteristics([hrMeasurement], for: svc)
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let ch = service.characteristics?.first(where: { $0.uuid == hrMeasurement }) else { return }
        peripheral.setNotifyValue(true, for: ch)
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        if characteristic.isNotifying { onStateChange?(.streaming) }
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard characteristic.uuid == hrMeasurement, let data = characteristic.value,
              let sample = parse(data) else { return }
        onSample?(sample)
    }
}
