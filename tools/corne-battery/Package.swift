// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CorneBattery",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "CorneBatteryCore", targets: ["CorneBatteryCore"]),
        .executable(name: "corne-battery", targets: ["CorneBatteryCLI"]),
    ],
    targets: [
        .target(name: "CorneBatteryCore"),
        .executableTarget(name: "CorneBatteryCLI", dependencies: ["CorneBatteryCore"]),
        .testTarget(name: "CorneBatteryCoreTests", dependencies: ["CorneBatteryCore"]),
    ]
)
