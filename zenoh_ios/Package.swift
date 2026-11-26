// swift-tools-version: 5.9
import PackageDescription

// OpenBene Zenoh transport SDK for iOS/iPadOS.
//
// The package deliberately lives outside the existing Flutter apps so the
// current WebSocket/BLE paths keep working while the Zenoh transport is
// developed and validated. `OpenBeneZenoh` is pure Swift and platform neutral;
// `OpenBeneZenohPico` adds the zenoh-pico session used by the phone.
let package = Package(
    name: "OpenBeneZenoh",
    platforms: [
        .iOS(.v16),
        .macOS(.v13),
    ],
    products: [
        .library(name: "OpenBeneZenoh", targets: ["OpenBeneZenoh"]),
        .library(name: "OpenBeneZenohPico", targets: ["OpenBeneZenohPico"]),
        .library(name: "OpenBeneRobot", targets: ["OpenBeneRobot"]),
        .executable(name: "openbene-zenoh-demo", targets: ["OpenBeneZenohDemo"]),
    ],
    targets: [
        // Prebuilt zenoh-pico 1.1.0 (EPL-2.0 OR Apache-2.0), copied from the
        // Beneros swiftros project where the same artifact already ships.
        .binaryTarget(
            name: "CZenohPico",
            path: "Vendor/CZenohPico.xcframework"
        ),
        .target(
            name: "COpenBeneZenohBridge",
            dependencies: ["CZenohPico"],
            path: "Sources/COpenBeneZenohBridge",
            publicHeadersPath: "include",
            cSettings: [
                .define(
                    "ZENOH_MACOS", to: "1",
                    .when(platforms: [.macOS, .macCatalyst, .iOS, .visionOS])),
                .define("Z_FEATURE_LINK_TCP", to: "1"),
            ]
        ),
        .target(
            name: "OpenBeneZenoh",
            path: "Sources/OpenBeneZenoh"
        ),
        .target(
            name: "OpenBeneZenohPico",
            dependencies: ["OpenBeneZenoh", "COpenBeneZenohBridge"],
            path: "Sources/OpenBeneZenohPico"
        ),
        .target(
            name: "OpenBeneRobot",
            path: "Sources/OpenBeneRobot"
        ),
        .executableTarget(
            name: "OpenBeneZenohDemo",
            dependencies: ["OpenBeneZenoh", "OpenBeneZenohPico"],
            path: "Sources/OpenBeneZenohDemo"
        ),
        .testTarget(
            name: "OpenBeneZenohTests",
            dependencies: ["OpenBeneZenoh"],
            path: "Tests/OpenBeneZenohTests"
        ),
        .testTarget(
            name: "OpenBeneRobotTests",
            dependencies: ["OpenBeneRobot"],
            path: "Tests/OpenBeneRobotTests"
        ),
    ]
)
