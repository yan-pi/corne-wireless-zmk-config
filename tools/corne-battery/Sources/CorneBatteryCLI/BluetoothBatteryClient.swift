import Foundation
@preconcurrency import CoreBluetooth
import CorneBatteryCore

private enum BluetoothOperationResult {
    case devices([BluetoothDevice])
    case report(BatteryReport)
}

final class BluetoothBatteryClient: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    private static var batteryServiceUUID: CBUUID { CBUUID(string: "180F") }
    private static var batteryLevelUUID: CBUUID { CBUUID(string: "2A19") }

    private var central: CBCentralManager!
    private var completion: ((Result<BluetoothOperationResult, BatteryCoreError>) -> Void)?
    private var devices = [UUID: CBPeripheral]()
    private var scanTimer: Timer?
    private var connectedPeripheral: CBPeripheral?
    private var batteryServices = [CBService]()
    private var serviceIndices = [ObjectIdentifier: Int]()
    private var batteryCharacteristics = [CBCharacteristic]()
    private var characteristicDiscoveryCount = 0
    private var descriptorDiscoveryCount = 0
    private var cpfDescriptors = [CBDescriptor]()
    private var cpfOwners = [ObjectIdentifier: CBCharacteristic]()
    private var descriptorIndex = 0
    private var rolesByCharacteristic = [ObjectIdentifier: BatteryRole]()
    private var characteristicIndex = 0
    private var samples = [BatterySample]()

    func listDevices(timeout: TimeInterval) throws -> [BluetoothDevice] {
        let result = wait(timeout: timeout) { finish in
            self.startCentral { result in finish(result) }
        }
        switch result {
        case let .success(.devices(value)): return value
        case .success(.report): throw BatteryCoreError.noDevice
        case let .failure(error): throw error
        }
    }

    func status(
        deviceID: String?,
        name: String?,
        timeout: TimeInterval
    ) throws -> BatteryReport {
        let result = wait(timeout: timeout) { finish in
            self.startCentral { [weak self] result in
                guard let self else { return }
                switch result {
                case let .success(.devices(available)):
                    do {
                        let selected = try self.selectDevice(available, id: deviceID, name: name)
                        guard let peripheral = self.devices.values.first(where: {
                            $0.identifier.uuidString == selected.identifier
                        }) else {
                            finish(.failure(.noDevice))
                            return
                        }
                        self.connect(peripheral, finish: finish)
                    } catch let error as BatteryCoreError {
                        finish(.failure(error))
                    } catch {
                        finish(.failure(.noDevice))
                    }
                case .success(.report): finish(.failure(.noDevice))
                case let .failure(error): finish(.failure(error))
                }
            }
        }
        switch result {
        case let .success(.report(value)): return value
        case .success(.devices): throw BatteryCoreError.noDevice
        case let .failure(error): throw error
        }
    }

    private func startCentral(completion: @escaping (Result<BluetoothOperationResult, BatteryCoreError>) -> Void) {
        self.completion = completion
        central = CBCentralManager(delegate: self, queue: .main)
    }

    private func wait(
        timeout: TimeInterval,
        operation: (@escaping (Result<BluetoothOperationResult, BatteryCoreError>) -> Void) -> Void
    ) -> Result<BluetoothOperationResult, BatteryCoreError> {
        var result: Result<BluetoothOperationResult, BatteryCoreError>?
        operation { value in result = value }
        let deadline = Date().addingTimeInterval(timeout)
        while result == nil && Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
        scanTimer?.invalidate()
        if result == nil {
            central?.stopScan()
            if let connectedPeripheral { central?.cancelPeripheralConnection(connectedPeripheral) }
            result = .failure(.timeout)
        }
        if let result { return result }
        return .failure(.timeout)
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            let connected = central.retrieveConnectedPeripherals(withServices: [Self.batteryServiceUUID])
            connected.forEach { devices[$0.identifier] = $0 }
            central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
            let timer = Timer(timeInterval: 2, target: self, selector: #selector(finishScan), userInfo: nil, repeats: false)
            scanTimer = timer
            RunLoop.main.add(timer, forMode: .default)
        case .unauthorized:
            completion?(.failure(.bluetoothUnauthorized))
        case .poweredOff, .unsupported, .resetting:
            completion?(.failure(.bluetoothUnavailable))
        case .unknown:
            break
        @unknown default:
            completion?(.failure(.bluetoothUnavailable))
        }
    }

    @objc private func finishScan() {
        central.stopScan()
        let found = devices.values.map {
            BluetoothDevice(name: $0.name ?? "Unnamed device", identifier: $0.identifier.uuidString)
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        completion?(.success(.devices(found)))
        completion = nil
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        let advertisedNames = [
            peripheral.name,
            advertisementData[CBAdvertisementDataLocalNameKey] as? String,
        ].compactMap { $0 }
        let advertisedServices = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? []
        let isCorne = advertisedNames.contains {
            $0.localizedCaseInsensitiveContains("corne")
        }
        let hasBatteryService = advertisedServices.contains(Self.batteryServiceUUID)
        if isCorne || hasBatteryService {
            devices[peripheral.identifier] = peripheral
        }
    }

    private func selectDevice(
        _ available: [BluetoothDevice],
        id: String?,
        name: String?
    ) throws -> BluetoothDevice {
        if let id {
            guard let device = available.first(where: { $0.identifier.caseInsensitiveCompare(id) == .orderedSame }) else {
                throw BatteryCoreError.noDevice
            }
            return device
        }
        let matches = if let name {
            available.filter { $0.name.caseInsensitiveCompare(name) == .orderedSame }
        } else {
            available.filter { $0.name.localizedCaseInsensitiveContains("corne") }
        }
        guard let first = matches.first else { throw BatteryCoreError.noDevice }
        guard matches.count == 1 else { throw BatteryCoreError.ambiguousDevice(matches.map(\.name)) }
        return first
    }

    private func connect(
        _ peripheral: CBPeripheral,
        finish: @escaping (Result<BluetoothOperationResult, BatteryCoreError>) -> Void
    ) {
        connectedPeripheral = peripheral
        peripheral.delegate = self
        peripheralConnectionCompletion = finish
        if peripheral.state == .connected {
            // Discover all services: filtering by BAS can suppress the callback
            // for cached HID peripherals on macOS.
            peripheral.discoverServices(nil)
        } else {
            central.connect(peripheral, options: nil)
        }
    }

    private var peripheralConnectionCompletion: ((Result<BluetoothOperationResult, BatteryCoreError>) -> Void)?

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.discoverServices(nil)
    }

    func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: Error?
    ) {
        peripheralConnectionCompletion?(.failure(.timeout))
    }

    func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        if peripheralConnectionCompletion != nil && samples.isEmpty {
            peripheralConnectionCompletion?(.failure(.timeout))
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard error == nil, let services = peripheral.services else {
            peripheralConnectionCompletion?(.failure(.noBatteryService))
            return
        }
        batteryServices = services.filter { $0.uuid == Self.batteryServiceUUID }
        guard !batteryServices.isEmpty else {
            peripheralConnectionCompletion?(.failure(.noBatteryService))
            return
        }
        serviceIndices = Dictionary(uniqueKeysWithValues: batteryServices.enumerated().map {
            (ObjectIdentifier($0.element), $0.offset)
        })
        characteristicDiscoveryCount = 0
        batteryCharacteristics.removeAll()
        batteryServices.forEach {
            peripheral.discoverCharacteristics([Self.batteryLevelUUID], for: $0)
        }
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        guard error == nil else {
            peripheralConnectionCompletion?(.failure(.noBatteryService))
            return
        }
        characteristicDiscoveryCount += 1
        batteryCharacteristics.append(contentsOf: (service.characteristics ?? []).filter {
            $0.uuid == Self.batteryLevelUUID
        })
        guard characteristicDiscoveryCount == batteryServices.count else { return }
        guard !batteryCharacteristics.isEmpty else {
            peripheralConnectionCompletion?(.failure(.noBatteryService))
            return
        }
        descriptorDiscoveryCount = 0
        cpfDescriptors.removeAll()
        cpfOwners.removeAll()
        batteryCharacteristics.forEach {
            peripheral.discoverDescriptors(for: $0)
        }
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverDescriptorsFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        descriptorDiscoveryCount += 1
        if error == nil, let cpf = characteristic.descriptors?.first(where: { $0.uuid == CBUUID(string: "2904") }) {
            cpfDescriptors.append(cpf)
            cpfOwners[ObjectIdentifier(cpf)] = characteristic
        }
        guard descriptorDiscoveryCount == batteryCharacteristics.count else { return }
        descriptorIndex = 0
        readNextCPFDescriptor(from: peripheral)
    }

    private func readNextCPFDescriptor(from peripheral: CBPeripheral) {
        guard descriptorIndex < cpfDescriptors.count else {
            characteristicIndex = 0
            readNextCharacteristic(from: peripheral)
            return
        }
        peripheral.readValue(for: cpfDescriptors[descriptorIndex])
    }

    private func readNextCharacteristic(from peripheral: CBPeripheral) {
        guard characteristicIndex < batteryCharacteristics.count else {
            let report = BatteryReport(
                deviceName: peripheral.name ?? "Corne",
                deviceID: peripheral.identifier.uuidString,
                observedAt: Date(),
                batteries: BatteryMapper.map(samples)
            )
            peripheralConnectionCompletion?(.success(.report(report)))
            peripheralConnectionCompletion = nil
            central.cancelPeripheralConnection(peripheral)
            return
        }
        peripheral.readValue(for: batteryCharacteristics[characteristicIndex])
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor descriptor: CBDescriptor,
        error: Error?
    ) {
        if descriptor.uuid == CBUUID(string: "2904"),
           let value = descriptor.value as? Data,
           value.count >= 7,
           let characteristic = cpfOwners[ObjectIdentifier(descriptor)] {
            let description = UInt16(value[5]) | (UInt16(value[6]) << 8)
            rolesByCharacteristic[ObjectIdentifier(characteristic)] =
                BatteryRole.fromPresentationDescription(description)
        }
        descriptorIndex += 1
        readNextCPFDescriptor(from: peripheral)
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        guard characteristic.uuid == Self.batteryLevelUUID else { return }
        let instance: Int
        if let service = characteristic.service {
            instance = serviceIndices[ObjectIdentifier(service)] ?? characteristicIndex
        } else {
            instance = characteristicIndex
        }
        let batteryRole = rolesByCharacteristic[ObjectIdentifier(characteristic)] ?? role(for: instance)
        guard error == nil, let value = characteristic.value else {
            samples.append(BatterySample(instance: instance, role: batteryRole, level: .unavailable))
            characteristicIndex += 1
            readNextCharacteristic(from: peripheral)
            return
        }
        let level = BatteryLevel(rawValue: value)
        if level == .invalid {
            peripheralConnectionCompletion?(.failure(.invalidBatteryValue))
            peripheralConnectionCompletion = nil
            central.cancelPeripheralConnection(peripheral)
            return
        }
        samples.append(BatterySample(instance: instance, role: batteryRole, level: level))
        characteristicIndex += 1
        readNextCharacteristic(from: peripheral)
    }

    private func role(for instance: Int) -> BatteryRole {
        instance == 0 ? .main : instance == 1 ? .auxiliary : .fallback(instance)
    }
}
