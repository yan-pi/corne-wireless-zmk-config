import Foundation
import Testing
@testable import CorneBatteryCore

@Test("battery level values are validated")
func batteryLevelValuesAreValidated() {
    #expect(BatteryLevel(rawValue: Data([0])) == .available(0))
    #expect(BatteryLevel(rawValue: Data([100])) == .available(100))
    #expect(BatteryLevel(rawValue: Data([255])) == .unavailable)
    #expect(BatteryLevel(rawValue: Data([101])) == .invalid)
    #expect(BatteryLevel(rawValue: Data()) == .invalid)
}

@Test("battery status uses critical and low thresholds")
func batteryStatusUsesThresholds() {
    #expect(BatteryStatus.forPercent(100) == .normal)
    #expect(BatteryStatus.forPercent(15) == .low)
    #expect(BatteryStatus.forPercent(5) == .critical)
    #expect(BatteryStatus.forPercent(nil) == .unavailable)
}

@Test("ZMK auxiliary CPF description identifies the right battery")
func zmkAuxiliaryCPFDescriptionIdentifiesRightBattery() {
    #expect(BatteryRole.fromPresentationDescription(0x0108) == .auxiliary)
    #expect(BatteryRole.fromPresentationDescription(0x0000) == .main)
}

@Test("main and auxiliary batteries map to left and right")
func mainAndAuxiliaryBatteriesMapToHalves() {
    let batteries = BatteryMapper.map([
        BatterySample(instance: 1, role: .auxiliary, level: .available(44)),
        BatterySample(instance: 0, role: .main, level: .available(77)),
    ])

    #expect(batteries.map(\.label) == ["left", "right"])
    #expect(batteries.map(\.percentage) == [77, 44])
}

@Test("low notification only fires on the downward threshold crossing")
func lowNotificationCrossing() {
    #expect(LowBatteryAlert.shouldNotify(previous: 20, current: 15))
    #expect(LowBatteryAlert.shouldNotify(previous: 15, current: 10) == false)
    #expect(LowBatteryAlert.shouldNotify(previous: nil, current: 15) == false)
    #expect(LowBatteryAlert.shouldNotify(previous: 25, current: nil) == false)
    #expect(LowBatteryAlert.shouldRearm(previous: 15, current: 20))
}

@Test("status output encodes unavailable health explicitly")
func statusOutputEncodesUnavailableHealth() throws {
    let report = BatteryReport(
        deviceName: "Corne",
        deviceID: "device-id",
        observedAt: Date(timeIntervalSince1970: 0),
        batteries: BatteryMapper.map([
            BatterySample(instance: 0, role: .main, level: .available(80)),
        ])
    )

    let data = try report.jsonData()
    let json = String(decoding: data, as: UTF8.self)
    #expect(json.contains("\"health\":null"))
    #expect(json.contains("\"label\":\"left\""))
    #expect(json.contains("\"percentage\":80"))
}
