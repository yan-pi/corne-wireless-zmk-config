import Foundation

public enum BatteryLevel: Equatable, Sendable {
    case available(Int)
    case unavailable
    case invalid

    public init(rawValue: Data) {
        guard let value = rawValue.first else {
            self = .invalid
            return
        }
        switch value {
        case 0...100:
            self = .available(Int(value))
        case 255:
            self = .unavailable
        default:
            self = .invalid
        }
    }

    public var percentage: Int? {
        guard case let .available(value) = self else { return nil }
        return value
    }
}

public enum BatteryRole: Equatable, Sendable {
    case main
    case auxiliary
    case fallback(Int)

    public var name: String {
        switch self {
        case .main: return "main"
        case .auxiliary: return "auxiliary"
        case let .fallback(instance): return "fallback-\(instance)"
        }
    }
}

public struct BluetoothDevice: Codable, Equatable, Sendable {
    public let name: String
    public let identifier: String

    public init(name: String, identifier: String) {
        self.name = name
        self.identifier = identifier
    }
}

public struct BatterySample: Equatable, Sendable {
    public let instance: Int
    public let role: BatteryRole
    public let level: BatteryLevel

    public init(instance: Int, role: BatteryRole, level: BatteryLevel) {
        self.instance = instance
        self.role = role
        self.level = level
    }
}

public enum BatteryStatus: String, Codable, Equatable, Sendable {
    case normal
    case low
    case critical
    case unavailable

    public static func forPercent(_ percentage: Int?) -> BatteryStatus {
        guard let percentage else { return .unavailable }
        if percentage <= 5 { return .critical }
        if percentage <= LowBatteryAlert.warningThreshold { return .low }
        return .normal
    }
}

public struct BatteryReading: Codable, Equatable, Sendable {
    public let label: String
    public let role: String
    public let percentage: Int?
    public let status: BatteryStatus
    public let source: String

    public init(label: String, role: BatteryRole, level: BatteryLevel, source: String) {
        self.label = label
        self.role = role.name
        self.percentage = level.percentage
        self.status = BatteryStatus.forPercent(level.percentage)
        self.source = source
    }
}

public struct BatteryHealth: Codable, Equatable, Sendable {
    public let status: String
    public let reason: String

    public init(status: String = "unavailable", reason: String = "not_reported_by_firmware") {
        self.status = status
        self.reason = reason
    }
}

public struct BatteryReport: Codable, Equatable, Sendable {
    public let deviceName: String
    public let deviceID: String
    public let observedAt: Date
    public let batteries: [BatteryReading]
    public let health: BatteryHealth?

    public init(
        deviceName: String,
        deviceID: String,
        observedAt: Date,
        batteries: [BatteryReading],
        health: BatteryHealth? = nil
    ) {
        self.deviceName = deviceName
        self.deviceID = deviceID
        self.observedAt = observedAt
        self.batteries = batteries
        self.health = health
    }

    private enum CodingKeys: String, CodingKey {
        case deviceName, deviceID, observedAt, batteries, health
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(deviceName, forKey: .deviceName)
        try container.encode(deviceID, forKey: .deviceID)
        try container.encode(observedAt, forKey: .observedAt)
        try container.encode(batteries, forKey: .batteries)
        if let health {
            try container.encode(health, forKey: .health)
        } else {
            try container.encodeNil(forKey: .health)
        }
    }

    public func jsonData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(self)
    }
}

public enum BatteryMapper {
    public static func map(_ samples: [BatterySample]) -> [BatteryReading] {
        let main = samples.first(where: { $0.role == .main })
        let auxiliary = samples.first(where: { $0.role == .auxiliary })
        let fallback = samples.filter {
            if case .fallback = $0.role { return true }
            return false
        }.sorted { $0.instance < $1.instance }

        let left = main ?? fallback.first
        let right = auxiliary ?? fallback.dropFirst().first
        return [
            reading(label: "left", sample: left, defaultRole: .main),
            reading(label: "right", sample: right, defaultRole: .auxiliary),
        ]
    }

    private static func reading(
        label: String,
        sample: BatterySample?,
        defaultRole: BatteryRole
    ) -> BatteryReading {
        guard let sample else {
            return BatteryReading(
                label: label,
                role: defaultRole,
                level: .unavailable,
                source: "not_discovered"
            )
        }
        return BatteryReading(
            label: label,
            role: sample.role,
            level: sample.level,
            source: "bluetooth_battery_service_\(sample.instance)"
        )
    }
}

public enum LowBatteryAlert {
    public static let warningThreshold = 15
    public static let rearmThreshold = 20

    public static func shouldNotify(previous: Int?, current: Int?) -> Bool {
        guard let previous, let current else { return false }
        return previous > warningThreshold && current <= warningThreshold
    }

    public static func shouldRearm(previous: Int?, current: Int?) -> Bool {
        guard let previous, let current else { return false }
        return previous <= rearmThreshold && current >= rearmThreshold
    }
}

public enum BatteryCoreError: LocalizedError, Equatable {
    case noDevice
    case ambiguousDevice([String])
    case bluetoothUnavailable
    case bluetoothUnauthorized
    case timeout
    case noBatteryService
    case invalidBatteryValue

    public var errorDescription: String? {
        switch self {
        case .noDevice:
            return "No Corne battery device found. Wake the keyboard and check that it is paired."
        case let .ambiguousDevice(names):
            return "More than one matching device found: \(names.joined(separator: ", ")). Use --device or --name."
        case .bluetoothUnavailable:
            return "Bluetooth is unavailable. Turn on Bluetooth and try again."
        case .bluetoothUnauthorized:
            return "Bluetooth permission was denied. Allow corne-battery in System Settings > Privacy & Security > Bluetooth."
        case .timeout:
            return "Timed out waiting for the Corne battery service. Wake both halves and try again."
        case .noBatteryService:
            return "The device does not expose a Bluetooth Battery Service. Reflash the firmware with CONFIG_BT_BAS=y."
        case .invalidBatteryValue:
            return "The device returned an invalid Battery Level value."
        }
    }
}
