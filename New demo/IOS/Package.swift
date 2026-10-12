// swift-tools-version:5.9
//
// The navigation kernel is a plain SwiftPM target so the routing, guidance,
// pose and executor logic can be tested with `swift test` on any Mac, without
// building the AR app. The Xcode project (project.yml, XcodeGen) compiles the
// very same sources into the app.
import PackageDescription

let package = Package(
    name: "OpenBotNavKit",
    platforms: [.iOS(.v15), .macOS(.v12)],
    products: [
        .library(name: "OpenBotNavKit", targets: ["OpenBotNavKit"]),
    ],
    targets: [
        .target(
            name: "OpenBotNavKit",
            path: "OpenBotNavKit/Sources/OpenBotNavKit"
        ),
        .testTarget(
            name: "OpenBotNavKitTests",
            dependencies: ["OpenBotNavKit"],
            path: "OpenBotNavKit/Tests/OpenBotNavKitTests",
            resources: [.copy("Resources/demo_floor.json")]
        ),
    ]
)
