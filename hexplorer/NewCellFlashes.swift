import MapKit
import SwiftyH3

/// The polygon of one flash, so the map delegate can tell it from the other overlays.
final class NewCellFlashPolygon: MKPolygon {}

/// Flashes newly visited cells on the map, so the user sees that tracking records them.
/// Each flash is a map overlay, so it moves with the map, also during the follow animation.
@MainActor
final class NewCellFlashes {
    static let shared = NewCellFlashes()

    /// How long a flash takes to fade out.
    private static let fadeDuration: Duration = .seconds(1)
    /// The number of opacity steps of the fade. Few steps keep the redraws, and so the energy, low.
    private static let fadeStepCount = 30

    private init() {}

    /// Flashes the cells at the resolution that the map shows now. Several new leaf cells
    /// in the same displayed cell give one flash.
    func flash(newLeafCellIDs: [UInt64], on mapView: MKMapView) {
        guard !newLeafCellIDs.isEmpty,
              let displayedResolution = H3Cell.Resolution(rawValue: Int32(SelectedCellState.shared.currentZoomResolution))
        else { return }

        let displayedCells = Set(newLeafCellIDs.compactMap { try? H3Cell($0).parent(at: displayedResolution) })
        for displayedCell in displayedCells {
            guard let boundary = try? displayedCell.boundary.map({ MKMapPoint($0.coordinates) }),
                  !boundary.isEmpty else { continue }
            let flashPolygon = NewCellFlashPolygon(points: boundary, count: boundary.count)
            mapView.addOverlay(flashPolygon, level: .aboveLabels)
            fadeOut(flashPolygon, on: mapView)
        }
    }

    /// Returns the renderer for a flash polygon, or `nil` for other overlays.
    func renderer(for overlay: any MKOverlay) -> MKOverlayRenderer? {
        guard let flashPolygon = overlay as? NewCellFlashPolygon else { return nil }
        let renderer = MKPolygonRenderer(polygon: flashPolygon)
        renderer.fillColor = UIColor.systemYellow.withAlphaComponent(0.6)
        renderer.strokeColor = .white
        renderer.lineWidth = 2
        return renderer
    }

    private func fadeOut(_ flashPolygon: NewCellFlashPolygon, on mapView: MKMapView) {
        Task { [weak mapView] in
            let stepDuration = Self.fadeDuration / Self.fadeStepCount
            for step in 1...Self.fadeStepCount {
                try? await Task.sleep(for: stepDuration)
                guard let renderer = mapView?.renderer(for: flashPolygon) else { continue }
                renderer.alpha = 1 - CGFloat(step) / CGFloat(Self.fadeStepCount)
                renderer.setNeedsDisplay()
            }
            mapView?.removeOverlay(flashPolygon)
        }
    }
}
