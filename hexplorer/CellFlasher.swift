import MapKit
import SwiftyH3

/// The polygon of one flash, so the map delegate can tell it from the other overlays.
/// It keeps the flash color, so the renderer can use it.
final class CellFlashPolygon: MKPolygon {
    var flashColor: UIColor = .systemYellow
}

/// Flashes H3 cells on the map, one cell after the other, in the order they were given.
/// Each flash is a map overlay, so it moves with the map, also during the follow animation.
@MainActor
final class CellFlasher {
    static let shared = CellFlasher()

    /// How long a flash takes to fade out.
    private static let fadeDuration: Duration = .seconds(0.3)
    /// The number of opacity steps of the fade. Few steps keep the redraws, and so the energy, low.
    private static let fadeStepCount = 30

    /// A flash that waits for the flashes before it to end.
    private struct QueuedFlash {
        let flashPolygon: CellFlashPolygon
        weak var mapView: MKMapView?
    }

    /// The flashes that wait for their turn, oldest first.
    private var queuedFlashes: [QueuedFlash] = []
    /// The task that shows the queued flashes, or `nil` when the queue is empty.
    private var flashQueueTask: Task<Void, Never>?

    private init() {}

    /// Flashes the cells one by one, in order. When earlier flashes still run,
    /// these cells wait until the earlier flashes end.
    func flash(cells: [H3Cell], color: UIColor, on mapView: MKMapView) {
        for cell in cells {
            guard let boundary = try? cell.boundary.map({ MKMapPoint($0.coordinates) }),
                  !boundary.isEmpty else { continue }
            let flashPolygon = CellFlashPolygon(points: boundary, count: boundary.count)
            flashPolygon.flashColor = color
            queuedFlashes.append(QueuedFlash(flashPolygon: flashPolygon, mapView: mapView))
        }
        guard flashQueueTask == nil, !queuedFlashes.isEmpty else { return }
        flashQueueTask = Task { await showQueuedFlashes() }
    }

    /// Returns the renderer for a flash polygon, or `nil` for other overlays.
    func renderer(for overlay: any MKOverlay) -> MKOverlayRenderer? {
        guard let flashPolygon = overlay as? CellFlashPolygon else { return nil }
        let renderer = MKPolygonRenderer(polygon: flashPolygon)
        renderer.fillColor = flashPolygon.flashColor.withAlphaComponent(0.6)
        renderer.strokeColor = .white
        renderer.lineWidth = 2
        return renderer
    }

    private func showQueuedFlashes() async {
        while !queuedFlashes.isEmpty {
            let nextFlash = queuedFlashes.removeFirst()
            guard let mapView = nextFlash.mapView else { continue }
            await showFlash(nextFlash.flashPolygon, on: mapView)
        }
        flashQueueTask = nil
    }

    /// Adds the flash polygon, fades it out and removes it again.
    private func showFlash(_ flashPolygon: CellFlashPolygon, on mapView: MKMapView) async {
        mapView.addOverlay(flashPolygon, level: .aboveLabels)
        let stepDuration = Self.fadeDuration / Self.fadeStepCount
        for step in 1...Self.fadeStepCount {
            try? await Task.sleep(for: stepDuration)
            guard let renderer = mapView.renderer(for: flashPolygon) else { continue }
            renderer.alpha = 1 - CGFloat(step) / CGFloat(Self.fadeStepCount)
            renderer.setNeedsDisplay()
        }
        mapView.removeOverlay(flashPolygon)
    }
}
