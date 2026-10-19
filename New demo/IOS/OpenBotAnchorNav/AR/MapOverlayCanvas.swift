import SwiftUI
import OpenBotNavKit

/// Plan view of the demo floor: graph edges, the active route, the markers that
/// were used for localisation and the estimated robot pose.
struct MapOverlayCanvas: View {
    let map: MapData
    let route: Route?
    let pose: Pose2D?
    let usedMarkers: [String]
    var routePoints: [RecordedWaypoint]? = nil

    var body: some View {
        Canvas { context, size in
            let locations = routePoints?.map { (name: $0.name, pose: $0.pose) } ?? map.locations.map { (name: $0.name, pose: $0.pose) }
            let polyline = routePoints?.map { $0.pose } ?? route?.polyline
            let points = locations.map { $0.pose } + map.markers.map { $0.pose } + (polyline ?? map.edges.flatMap { $0.path })
            guard let minX = points.map({ $0.x }).min(),
                  let maxX = points.map({ $0.x }).max(),
                  let minY = points.map({ $0.y }).min(),
                  let maxY = points.map({ $0.y }).max()
            else { return }

            let padding: CGFloat = 14
            let spanX = CGFloat(max(maxX - minX, 0.5))
            let spanY = CGFloat(max(maxY - minY, 0.5))
            let scale = min((size.width - 2 * padding) / spanX, (size.height - 2 * padding) / spanY)
            let offsetX = padding + (size.width - 2 * padding - spanX * scale) / 2
            let offsetY = padding + (size.height - 2 * padding - spanY * scale) / 2

            func screen(_ point: Pose2D) -> CGPoint {
                CGPoint(
                    x: offsetX + CGFloat(point.x - minX) * scale,
                    y: offsetY + CGFloat(maxY - point.y) * scale
                )
            }

            for edge in routePoints == nil ? map.edges : [] {
                var path = Path()
                for (index, point) in edge.path.enumerated() {
                    if index == 0 { path.move(to: screen(point)) } else { path.addLine(to: screen(point)) }
                }
                context.stroke(path, with: .color(.white.opacity(0.25)), lineWidth: 3)
            }

            if let polyline = polyline {
                var path = Path()
                for (index, point) in polyline.enumerated() {
                    if index == 0 { path.move(to: screen(point)) } else { path.addLine(to: screen(point)) }
                }
                context.stroke(path, with: .color(.teal), lineWidth: 5)
            }

            for marker in map.markers {
                let centre = screen(marker.pose)
                let rect = CGRect(x: centre.x - 6, y: centre.y - 6, width: 12, height: 12)
                context.stroke(Path(rect), with: .color(.orange), lineWidth: 2.5)
                if usedMarkers.contains(marker.id) {
                    context.fill(
                        Path(ellipseIn: CGRect(x: centre.x - 3, y: centre.y - 3, width: 6, height: 6)),
                        with: .color(.teal)
                    )
                }
            }

            for location in locations {
                let centre = screen(location.pose)
                context.fill(
                    Path(ellipseIn: CGRect(x: centre.x - 3.5, y: centre.y - 3.5, width: 7, height: 7)),
                    with: .color(.white)
                )
                context.draw(
                    Text(location.name).font(.system(size: 9)).foregroundColor(.white),
                    at: CGPoint(x: centre.x + 6, y: centre.y - 10),
                    anchor: .topLeading
                )
            }

            if let pose = pose {
                let centre = screen(pose)
                let heading = -pose.yawRad
                var triangle = Path()
                triangle.move(to: CGPoint(x: centre.x + 12 * cos(heading), y: centre.y + 12 * sin(heading)))
                triangle.addLine(to: CGPoint(x: centre.x + 8 * cos(heading + 2.5), y: centre.y + 8 * sin(heading + 2.5)))
                triangle.addLine(to: CGPoint(x: centre.x + 8 * cos(heading - 2.5), y: centre.y + 8 * sin(heading - 2.5)))
                triangle.closeSubpath()
                context.fill(triangle, with: .color(.cyan))
            }
        }
    }
}
