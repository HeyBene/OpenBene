import XCTest
@testable import OpenBotNavKit

final class RouterTests: XCTestCase {

    func testDemoMapParses() {
        let map = TestSupport.demoMap()
        XCTAssertEqual(map.mapId, "openbene_demo_floor")
        XCTAssertEqual(map.markers.count, 4)
        XCTAssertEqual(map.locations.count, 4)
        XCTAssertEqual(map.edges.count, 3)
        XCTAssertEqual(map.roomNames(), ["Room 101", "Room 102"])
        XCTAssertEqual(map.markerForPayload("openbene:mk_junction")?.id, "mk_junction")
    }

    func testRoom101RouteMatchesThePythonDemo() throws {
        let map = TestSupport.demoMap()
        let route = try XCTUnwrap(try Router(mapData: map).routeToRoom(startLocationId: "loc_entrance", roomName: "Room 101"))
        XCTAssertEqual(route.totalDistanceM, 10.0, accuracy: 1e-9)
        XCTAssertEqual(route.locationSequence(), ["loc_entrance", "loc_junction", "loc_room101"])
        XCTAssertEqual(route.legs.map { $0.toId }, ["loc_junction", "loc_room101"])
        XCTAssertEqual(route.legs[0].distanceM, 6.0, accuracy: 1e-9)
        XCTAssertEqual(route.legs[1].distanceM, 4.0, accuracy: 1e-9)
    }

    func testRoom102RouteMatchesThePythonDemo() throws {
        let map = TestSupport.demoMap()
        let route = try XCTUnwrap(try Router(mapData: map).routeToRoom(startLocationId: "loc_entrance", roomName: "Room 102"))
        XCTAssertEqual(route.totalDistanceM, 12.0, accuracy: 1e-9)
        XCTAssertEqual(route.legs.count, 2)
        XCTAssertEqual(route.locationSequence(), ["loc_entrance", "loc_junction", "loc_room102"])
    }

    func testGuidanceMatchesThePythonMessages() throws {
        let map = TestSupport.demoMap()
        let builder = GuidanceBuilder(mapData: map)

        let room101 = try XCTUnwrap(try Router(mapData: map).routeToRoom(startLocationId: "loc_entrance", roomName: "Room 101"))
        let steps = builder.build(room101)
        XCTAssertEqual(steps.count, 2)
        XCTAssertEqual(steps[0].kind, .turnLeft)
        XCTAssertEqual(steps[0].message, "Forward 6.0 m, then turn left at Corridor Junction")
        XCTAssertEqual(steps[1].kind, .arrive)
        XCTAssertEqual(steps[1].message, "Forward 4.0 m, then arrive at Room 101")

        let room102 = try XCTUnwrap(try Router(mapData: map).routeToRoom(startLocationId: "loc_entrance", roomName: "Room 102"))
        let straight = builder.build(room102)
        XCTAssertEqual(straight.count, 1)
        XCTAssertEqual(straight[0].kind, .arrive)
        XCTAssertEqual(straight[0].message, "Forward 12.0 m, then arrive at Room 102")
    }

    func testRouteBackwardsThroughTheJunction() throws {
        let map = TestSupport.demoMap()
        let route = try XCTUnwrap(try Router(mapData: map).routeToLocation(startLocationId: "loc_room101", destinationLocationId: "loc_room102"))
        XCTAssertEqual(route.locationSequence(), ["loc_room101", "loc_junction", "loc_room102"])
        XCTAssertEqual(route.totalDistanceM, 10.0, accuracy: 1e-9)
    }
}
