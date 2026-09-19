import Foundation
import Darwin
import CorneBatteryCore

struct Arguments {
    enum Command { case devices, status, monitor, help }
    let command: Command
    let deviceID: String?
    let name: String?
    let json: Bool
    let timeout: TimeInterval

    init(_ arguments: [String]) throws {
        guard let rawCommand = arguments.first else {
            command = .status
            deviceID = nil
            name = nil
            json = false
            timeout = 10
            return
        }
        var parsedCommand: Command
        switch rawCommand {
        case "devices": parsedCommand = .devices
        case "status": parsedCommand = .status
        case "monitor": parsedCommand = .monitor
        case "help", "--help", "-h": parsedCommand = .help
        default: throw CLIError.usage("Unknown command: \(rawCommand)")
        }

        var parsedID: String?
        var parsedName: String?
        var parsedJSON = false
        var parsedTimeout: TimeInterval = parsedCommand == .monitor ? 60 : 10
        var index = 1
        while index < arguments.count {
            switch arguments[index] {
            case "--device":
                index += 1
                guard index < arguments.count else { throw CLIError.usage("--device requires a UUID") }
                parsedID = arguments[index]
            case "--name":
                index += 1
                guard index < arguments.count else { throw CLIError.usage("--name requires a device name") }
                parsedName = arguments[index]
            case "--json": parsedJSON = true
            case "--timeout":
                index += 1
                guard index < arguments.count, let value = Double(arguments[index]), value > 0 else {
                    throw CLIError.usage("--timeout requires a positive number of seconds")
                }
                parsedTimeout = value
            case "--help", "-h":
                parsedCommand = .help
            default: throw CLIError.usage("Unknown option: \(arguments[index])")
            }
            index += 1
        }
        command = parsedCommand
        deviceID = parsedID
        name = parsedName
        json = parsedJSON
        timeout = parsedTimeout
    }
}

enum CLIError: LocalizedError {
    case usage(String)

    var errorDescription: String? {
        switch self {
        case let .usage(message): return message + "\n\n" + Self.helpText
        }
    }

    static let helpText = """
    Usage:
      corne-battery devices [--timeout SECONDS]
      corne-battery status [--device UUID | --name NAME] [--json] [--timeout SECONDS]
      corne-battery monitor [--device UUID | --name NAME] [--timeout SECONDS]

    The keyboard exposes one reading per half. Two parallel cells on one half
    are reported as one combined 1S pack by the controller.
    """
}

#if os(macOS)
struct CorneBatteryCLI {
    static func main() {
        do {
            let arguments = try Arguments(Array(CommandLine.arguments.dropFirst()))
            switch arguments.command {
            case .help:
                print(CLIError.helpText)
            case .devices:
                try listDevices(timeout: arguments.timeout)
            case .status:
                try printStatus(arguments)
            case .monitor:
                try monitor(arguments)
            }
        } catch {
            fputs("corne-battery: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }

    private static func listDevices(timeout: TimeInterval) throws {
        let devices = try BluetoothBatteryClient().listDevices(timeout: timeout)
        if devices.isEmpty {
            throw BatteryCoreError.noDevice
        }
        for device in devices {
            print("\(device.name)\t\(device.identifier)")
        }
    }

    private static func printStatus(_ arguments: Arguments) throws {
        let report = try BluetoothBatteryClient().status(
            deviceID: arguments.deviceID,
            name: arguments.name,
            timeout: arguments.timeout
        )
        if arguments.json {
            print(String(decoding: try report.jsonData(), as: UTF8.self))
        } else {
            printHuman(report)
        }
    }

    private static func printHuman(_ report: BatteryReport) {
        print("\(report.deviceName) (\(report.deviceID))")
        for battery in report.batteries {
            let value = battery.percentage.map { "\($0)%" } ?? "unavailable"
            print("  \(battery.label): \(value) [\(battery.status.rawValue)]")
        }
        print("  observed: \(report.observedAt.formatted(.iso8601))")
        print("  health: unavailable (not reported by ZMK firmware)")
    }

    private static func monitor(_ arguments: Arguments) throws {
        let defaults = UserDefaults.standard
        print("Monitoring Corne battery levels. Press Ctrl-C to stop.")
        while true {
            do {
                let report = try BluetoothBatteryClient().status(
                    deviceID: arguments.deviceID,
                    name: arguments.name,
                    timeout: min(arguments.timeout, 20)
                )
                for battery in report.batteries {
                    let key = "corne-battery.last.\(report.deviceID).\(battery.label)"
                    let previous = defaults.object(forKey: key) as? Int
                    if LowBatteryAlert.shouldNotify(previous: previous, current: battery.percentage) {
                        sendNotification(for: battery, deviceName: report.deviceName)
                    }
                    if let current = battery.percentage {
                        if LowBatteryAlert.shouldRearm(previous: previous, current: current) || previous == nil {
                            defaults.set(current, forKey: key)
                        } else {
                            defaults.set(current, forKey: key)
                        }
                    }
                }
            } catch {
                fputs("corne-battery monitor: \(error.localizedDescription)\n", stderr)
            }
            RunLoop.current.run(until: Date().addingTimeInterval(60))
        }
    }

    private static func sendNotification(for battery: BatteryReading, deviceName: String) {
        let title = appleScriptString("Corne battery low")
        let body = appleScriptString(
            "\(deviceName) \(battery.label) battery is at \(battery.percentage.map(String.init) ?? "unknown")%."
        )
        let script = "display notification \(body) with title \(title) sound name \"Glass\""
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        do {
            try process.run()
        } catch {
            fputs("corne-battery: unable to send notification: \(error.localizedDescription)\n", stderr)
        }
    }

    private static func appleScriptString(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: " ")
        return "\"\(escaped)\""
    }
}

CorneBatteryCLI.main()
#else
print("corne-battery is currently supported on macOS only")
#endif
