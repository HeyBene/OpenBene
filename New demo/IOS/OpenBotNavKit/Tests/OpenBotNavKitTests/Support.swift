import Foundation
import XCTest
@testable import OpenBotNavKit

/// SwiftPM synthesises `Bundle.module` for its resource bundles; when the same
/// sources are built by Xcode the test bundle holds the resources instead.
private final class BundleToken {}

private enum ResourceBundle {
    static let current: Bundle = {
        #if SWIFT_PACKAGE
        return Bundle.module
        #else
        return Bundle(for: BundleToken.self)
        #endif
    }()
}

enum TestSupport {
    /// The same map the Python tests, the Android assets and the iOS app use.
    static func demoMap(file: StaticString = #filePath, line: UInt = #line) -> MapData {
        guard let url = ResourceBundle.current.url(forResource: "demo_floor", withExtension: "json") else {
            XCTFail("demo_floor.json is missing from the test bundle", file: file, line: line)
            return MapData(mapId: "empty", name: "empty", markers: [], locations: [], edges: [], rooms: [])
        }
        do {
            let text = try String(contentsOf: url, encoding: .utf8)
            return try MapData.parse(text)
        } catch {
            XCTFail("could not parse the demo map: \(error)", file: file, line: line)
            return MapData(mapId: "empty", name: "empty", markers: [], locations: [], edges: [], rooms: [])
        }
    }

    /// A rigid transform used as the (arbitrary) AR world frame the estimator has
    /// to solve for. map = arFromMap.inverse() composed with each observation.
    static let arFromMap = Pose2D.fromDeg(x: 12.5, y: -4.0, yawDeg: 37.0)

    static func observation(
        marker: Marker,
        truePose: Pose2D,
        noise: (position: Double, yawDeg: Double) = (0.0, 0.0)
    ) -> ArObservation {
        let markerInAr = arFromMap.compose(marker.pose)
        let deviceInAr = arFromMap.compose(truePose)
        let jittered = Pose2D(
            x: deviceInAr.x + noise.position,
            y: deviceInAr.y,
            yawRad: wrapRad(deviceInAr.yawRad + noise.yawDeg * Double.pi / 180.0)
        )
        return ArObservation(markerId: marker.id, markerInAr: markerInAr, deviceInAr: jittered)
    }
}
