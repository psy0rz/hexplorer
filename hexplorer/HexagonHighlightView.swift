import SwiftUI
import MapKit

struct HexagonHighlightView: View {
    let mapView: MKMapView

    private var state: SelectedCellState { SelectedCellState.shared }

    @State private var viewportVersion: Int = 0

    var body: some View {
        let screenPts = state.selectedCellBoundary.map { coord in
            mapView.convert(coord, toPointTo: mapView)
        }

        ZStack {
            // Crosshair centered on the tapped coordinate.
            if let coord = state.tappedCoordinate {
                let pt = mapView.convert(coord, toPointTo: mapView)
                GeometryReader { geo in
                    Path { p in
                        // Horizontal line.
                        p.move(to: CGPoint(x: 0, y: pt.y))
                        p.addLine(to: CGPoint(x: geo.size.width, y: pt.y))
                        // Vertical line.
                        p.move(to: CGPoint(x: pt.x, y: 0))
                        p.addLine(to: CGPoint(x: pt.x, y: geo.size.height))
                    }
                    .stroke(Color.yellow.opacity(0.6), lineWidth: 2)
                }
            }

            if screenPts.count >= 3 {
                // Fill tint.
//                HexPolygon(points: screenPts)
//                    .fill(Color.yellow.opacity(0.20))
                

                // Stroke with stacked shadows for the glow effect.
                HexPolygon(points: screenPts)
                    .stroke(Color.yellow.opacity(0.95), lineWidth: 2.5)
                    .shadow(color: .yellow, radius: 6)
                    .shadow(color: .yellow, radius: 12)
                    .shadow(color: .yellow.opacity(0.5), radius: 20)
            }
        }
        .allowsHitTesting(false)
        .onReceive(NotificationCenter.default.publisher(for: .mapViewportChanged)) { _ in
            viewportVersion &+= 1
        }
        .id(viewportVersion)
    }
}

struct HexPolygon: Shape {
    var points: [CGPoint]

    func path(in rect: CGRect) -> Path {
        var p = Path()
        guard let first = points.first else { return p }
        p.move(to: first)
        for pt in points.dropFirst() { p.addLine(to: pt) }
        p.closeSubpath()
        return p
    }
}

