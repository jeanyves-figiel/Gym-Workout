import CoreBluetooth
import Foundation
import LiftSensor
import Observation
import WatchKit

private let batteryLevelUUID = CBUUID(string: "2A19")

/// Bluetooth bike sensors on the Watch (#623 A + B): power meters, cadence sensors and heart-rate straps, paired once
/// and connected for rides. Watts (with a 3″ average), cadence and strap heart rate feed the power player.
@MainActor @Observable
final class BikeSensors: NSObject {
    static let shared = BikeSensors()

    enum Kind: String, Codable {
        case power, cadence, heart

        var symbol: String {
            switch self {
            case .power: "bolt.fill"
            case .cadence: "arrow.triangle.2.circlepath"
            case .heart: "heart.fill"
            }
        }

        var service: CBUUID {
            switch self {
            case .power: CBUUID(string: "1818")
            case .cadence: CBUUID(string: "1816")
            case .heart: CBUUID(string: "180D")
            }
        }

        var measurement: CBUUID {
            switch self {
            case .power: CBUUID(string: "2A63")
            case .cadence: CBUUID(string: "2A5B")
            case .heart: CBUUID(string: "2A37")
            }
        }
    }

    struct Sensor: Identifiable, Equatable {
        let id: UUID
        var name: String
        var kind: Kind
        var battery: Int?
        var connected = false
    }

    private static let pairedKey = "bikeSensors"
    private static let ftpKey = "bikeFTP"

    /// Sensors seen while scanning or paired, by id.
    private(set) var sensors: [UUID: Sensor] = [:]
    private(set) var scanning = false
    /// Paired sensors: id → kind, kept on the Watch.
    private(set) var paired: [UUID: Kind]
    private(set) var watts: Int?
    private(set) var avg3: Double?
    private(set) var cadence: Double?
    private(set) var heartRate: Int?
    /// FTP set on the iPhone or by a test on the Watch.
    private(set) var ftp: Int?

    /// FTP test (#623 C): start, and the 20′ average once the all-out part is over.
    private(set) var testStart: Date?
    private(set) var testResult: Int?
    private var testSum = 0.0
    private var testCount = 0

    private var central: CBCentralManager?
    private var peripherals: [UUID: CBPeripheral] = [:]
    private var lastCrank: [UUID: BikePower.CrankReading] = [:]
    private var rolling = BikePower.Rolling()
    private var wanted = false

    override init() {
        let raw = UserDefaults.standard.dictionary(forKey: Self.pairedKey) as? [String: String] ?? [:]
        paired = Dictionary(uniqueKeysWithValues: raw.compactMap { k, v in UUID(uuidString: k).flatMap { id in Kind(rawValue: v).map { (id, $0) } } })
        let f = UserDefaults.standard.integer(forKey: Self.ftpKey)
        ftp = f > 0 ? f : nil
        super.init()
    }

    func setFTP(_ value: Int?) {
        ftp = value
        UserDefaults.standard.set(value ?? 0, forKey: Self.ftpKey)
    }

    var hasPower: Bool { paired.values.contains(.power) }
    var list: [Sensor] { sensors.values.sorted { ($0.kind.rawValue, $0.name) < ($1.kind.rawValue, $1.name) } }
    var zone: BikePower.Zone? { BikePower.zone(watts: avg3 ?? Double(watts ?? 0), ftp: ftp) }

    // MARK: Control

    private func ensureCentral() {
        if central == nil { central = CBCentralManager(delegate: self, queue: nil) }
    }

    /// Looks for sensors to pair (Sensors page).
    func startScan() {
        scanning = true
        ensureCentral()
        if central?.state == .poweredOn { central?.scanForPeripherals(withServices: [Kind.power.service, Kind.cadence.service, Kind.heart.service]) }
    }

    func stopScan() {
        scanning = false
        central?.stopScan()
    }

    /// Connects the paired sensors (ride start).
    func connect() {
        wanted = true
        ensureCentral()
        guard let central, central.state == .poweredOn else { return }
        for p in central.retrievePeripherals(withIdentifiers: Array(paired.keys)) {
            peripherals[p.identifier] = p
            p.delegate = self
            if sensors[p.identifier] == nil, let kind = paired[p.identifier] {
                sensors[p.identifier] = Sensor(id: p.identifier, name: p.name ?? kind.rawValue.capitalized, kind: kind)
            }
            central.connect(p)
        }
    }

    /// Disconnects all (ride end); values clear.
    func disconnect() {
        wanted = false
        for p in peripherals.values { central?.cancelPeripheralConnection(p) }
        watts = nil
        avg3 = nil
        cadence = nil
        heartRate = nil
        rolling = BikePower.Rolling()
        testStart = nil
    }

    func pair(_ s: Sensor) {
        paired[s.id] = s.kind
        save()
        WKInterfaceDevice.current().play(.success)
        if let p = peripherals[s.id] { central?.connect(p) }
    }

    func unpair(_ s: Sensor) {
        paired[s.id] = nil
        save()
        if let p = peripherals[s.id] { central?.cancelPeripheralConnection(p) }
    }

    private func save() {
        UserDefaults.standard.set(Dictionary(uniqueKeysWithValues: paired.map { ($0.key.uuidString, $0.value.rawValue) }), forKey: Self.pairedKey)
    }

    // MARK: FTP test

    func startTest() {
        testStart = Date()
        testResult = nil
        testSum = 0
        testCount = 0
    }

    func stopTest() { testStart = nil }

    /// Test phase now; nil when no test runs.
    func testPhase(now: Date = Date()) -> (phase: BikePower.TestPhase, left: TimeInterval)? {
        testStart.map { BikePower.testPhase(elapsed: now.timeIntervalSince($0)) }
    }

    /// Average watts of the all-out part so far.
    var testAverage: Int? { testCount > 0 ? Int((testSum / Double(testCount)).rounded()) : nil }

    private func testSample(_ w: Int) {
        guard let phase = testPhase()?.phase else { return }
        if phase == .allOut {
            testSum += Double(w)
            testCount += 1
        } else if phase != .warmUp, testResult == nil, testCount >= 60 {
            // All-out part over: 95 % of its average is the new FTP.
            let ftp = BikePower.ftp(twentyMinuteAverage: testSum / Double(testCount))
            testResult = ftp
            setFTP(ftp)
            WKInterfaceDevice.current().play(.notification)
        }
    }

    // MARK: Data

    fileprivate func receive(_ bytes: [UInt8], kind: Kind, from id: UUID) {
        let now = Date().timeIntervalSinceReferenceDate
        switch kind {
        case .power:
            guard let p = BikePower.parsePower(bytes) else { return }
            watts = max(0, p.watts)
            rolling.add(Double(max(0, p.watts)), at: now)
            avg3 = rolling.average
            testSample(max(0, p.watts))
            if let c = p.crank { crank(c, from: id) }
        case .cadence:
            if let c = BikePower.parseCadence(bytes) { crank(c, from: id) }
        case .heart:
            heartRate = BikePower.parseHeartRate(bytes)
        }
    }

    private func crank(_ c: BikePower.CrankReading, from id: UUID) {
        if let last = lastCrank[id], last.time != c.time {
            cadence = BikePower.cadence(from: last, to: c) ?? cadence
        } else if let last = lastCrank[id], last.time == c.time, c.revs == last.revs {
            // No new revolution for a while: coasting.
            cadence = 0
        }
        lastCrank[id] = c
    }

    fileprivate func found(_ p: CBPeripheral, services: [CBUUID]) {
        let kind: Kind = services.contains(Kind.power.service) ? .power : services.contains(Kind.cadence.service) ? .cadence : .heart
        peripherals[p.identifier] = p
        p.delegate = self
        var s = sensors[p.identifier] ?? Sensor(id: p.identifier, name: p.name ?? kind.rawValue.capitalized, kind: kind)
        s.name = p.name ?? s.name
        sensors[p.identifier] = s
    }

    fileprivate func connected(_ p: CBPeripheral, _ on: Bool) {
        sensors[p.identifier]?.connected = on
        if on {
            p.discoverServices(nil)
        } else if wanted, paired[p.identifier] != nil {
            central?.connect(p)
        }
    }

    fileprivate func battery(_ level: Int, of id: UUID) { sensors[id]?.battery = level }

    fileprivate func powered() {
        if scanning { startScan() }
        if wanted { connect() }
    }
}

extension BikeSensors: CBCentralManagerDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        guard central.state == .poweredOn else { return }
        Task { @MainActor in self.powered() }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                                    advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let services = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? []
        Task { @MainActor in self.found(peripheral, services: services) }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        Task { @MainActor in self.connected(peripheral, true) }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        Task { @MainActor in self.connected(peripheral, false) }
    }
}

extension BikeSensors: CBPeripheralDelegate {
    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        for s in peripheral.services ?? [] {
            peripheral.discoverCharacteristics([Kind.power.measurement, Kind.cadence.measurement, Kind.heart.measurement, batteryLevelUUID], for: s)
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        for c in service.characteristics ?? [] {
            if c.uuid == batteryLevelUUID {
                peripheral.readValue(for: c)
            } else {
                peripheral.setNotifyValue(true, for: c)
            }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let data = characteristic.value else { return }
        let bytes = [UInt8](data)
        let id = peripheral.identifier
        let uuid = characteristic.uuid
        Task { @MainActor in
            if uuid == batteryLevelUUID {
                if let b = bytes.first { self.battery(Int(b), of: id) }
                return
            }
            let kind: Kind? = uuid == Kind.power.measurement ? .power : uuid == Kind.cadence.measurement ? .cadence
                : uuid == Kind.heart.measurement ? .heart : nil
            if let kind { self.receive(bytes, kind: kind, from: id) }
        }
    }
}
