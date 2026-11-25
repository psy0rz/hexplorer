import MapKit
import SwiftyH3

/// The polygon of one flash, so the map delegate can tell it from the other overlays.
/// It keeps the flash color, so the renderer can use it.
final class CellFlashPolygon: MKPolygon {
    var flashColor: UIColor = .systemYellow
}

/// Flashes a pattern of H3 cells on the map again and again, one cell after the other, in the order they were given.
/// Each flash is a map overlay, so it moves with the map, also during the follow animation.
@MainActor
final class CellFlasher {
    static let shared = CellFlasher()

    /// How long a flash takes to fade out.
    private static let fadeDuration: Duration = .seconds(1)
    /// The number of opacity steps of the fade. Few steps keep the redraws, and so the energy, low.
    private static let fadeStepCount = 30
    /// The time between the starts of two flashes. Flashes overlap: a flash does not wait for the fade before it to end.
    private static let flashStartInterval: Duration = .seconds(0.1)
    /// The pause between the end of a pattern run and the next run.
    private static let repeatPause: Duration = .seconds(3)

    private weak var mapView: MKMapView?

    /// The cells that flash again and again, in order; empty when no pattern repeats.
    /// The loop reads it at the start of each run, so a new pattern waits until the current run ends.
    private var repeatedFlashCells: [H3Cell] = []
    private var repeatedFlashColor: UIColor = .systemYellow
    /// The task that runs the pattern again and again, or `nil` when no pattern repeats.
    private var repeatedFlashTask: Task<Void, Never>?

    private init() {}

    func attach(to mapView: MKMapView) {
        self.mapView = mapView
    }

    /// Flashes the cells in order, and starts again after each run. A run that has started always ends first:
    /// other cells start after the current run. A call with the same cells and color changes nothing,
    /// so callers can send the cells at each change of the data. An empty list stops the loop after the current run.
    func repeatFlashing(cells: [H3Cell], color: UIColor) {
        repeatedFlashCells = cells
        repeatedFlashColor = color
        guard repeatedFlashTask == nil, !cells.isEmpty else { return }
        repeatedFlashTask = Task {
            await runRepeatedFlashLoop()
            repeatedFlashTask = nil
        }
    }

    /// Stops the loop after the current run.
    func stopRepeatedFlashing() {
        repeatedFlashCells = []
    }

    /// Returns the renderer for a flash polygon, or `nil` for other overlays.
    func renderer(for overlay: any MKOverlay) -> MKOverlayRenderer? {
        guard let flashPolygon = overlay as? CellFlashPolygon else { return nil }
        let renderer = MKPolygonRenderer(polygon: flashPolygon)
        renderer.fillColor = flashPolygon.flashColor.withAlphaComponent(0.8)
        renderer.strokeColor = .white
        renderer.lineWidth = 2
        return renderer
    }

    /// Starts one flash per cell, with `flashStartInterval` between the starts, waits until the last fade has ended
    /// and the pause has passed, and starts again with the pattern of that time.
    private func runRepeatedFlashLoop() async {
        while !repeatedFlashCells.isEmpty, mapView != nil {
            let runColor = repeatedFlashColor
            for cell in repeatedFlashCells {
                Task { await showFlash(of: cell, color: runColor) }
                try? await Task.sleep(for: Self.flashStartInterval)
            }
            try? await Task.sleep(for: Self.repeatPause)
        }
    }

    /// Adds a flash polygon for the cell, fades it out and removes it again.
    private func showFlash(of cell: H3Cell, color: UIColor) async {
        guard let mapView,
              let boundary = try? cell.boundary.map({ MKMapPoint($0.coordinates) }),
              !boundary.isEmpty else { return }
        let flashPolygon = CellFlashPolygon(points: boundary, count: boundary.count)
        flashPolygon.flashColor = color
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
