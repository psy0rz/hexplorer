import Foundation
import MapKit
import SwiftyH3

/// Holds the currently selected (tapped) hexagon cell and its screen polygon.
@Observable
final class SelectedCellState {
    static let shared = SelectedCellState()

    /// The H3 cell index that is currently highlighted, or nil.
    var selectedCellIndex: UInt64? = nil

    /// The visited-cell data for the selected cell (may be nil for unvisited cells).
    var selectedCellInfo: VisitedCell? = nil

    /// The H3 resolution of the selected cell. Updated to match zoom on new taps; user can override with stepper.
    var selectedCellResolution: Int = {
        let stored = UserDefaults.standard.integer(forKey: "selectedResolution")
        return stored == 0 ? 12 : stored
    }() {
        didSet { UserDefaults.standard.set(selectedCellResolution, forKey: "selectedResolution") }
    }

    /// The resolution derived from the current map zoom scale. Updated as the map scrolls/zooms.
    var currentZoomResolution: Int = 12

    /// The coordinate that was tapped, used to re-resolve the cell when resolution changes.
    var tappedCoordinate: CLLocationCoordinate2D? = nil

    /// The geographic boundary of the selected cell (in coordinate space).
    var selectedCellBoundary: [CLLocationCoordinate2D] = []

    private init() {}

    /// Selects the cell at the coordinate, at the resolution of the current zoom.
    /// When that cell is already selected, it clears the selection.
    func toggleSelection(at coordinate: CLLocationCoordinate2D) {
        guard let resolution = H3Cell.Resolution(rawValue: Int32(currentZoomResolution)) else { return }
        let latLng = H3LatLng(latitudeDegs: coordinate.latitude, longitudeDegs: coordinate.longitude)
        guard let tappedCell = try? latLng.cell(at: resolution) else { return }

        if selectedCellIndex == tappedCell.id {
            clear()
        } else {
            let info = CellStore.shared.visitedCells(among: [tappedCell.id])[tappedCell.id]
            select(cell: tappedCell, info: info, coordinate: coordinate)
        }
    }

    func select(cell: H3Cell, info: VisitedCell?, coordinate: CLLocationCoordinate2D) {
        tappedCoordinate = coordinate
        // Snap the display resolution to the current zoom level on each new tap.
        selectedCellResolution = currentZoomResolution
        applyCell(cell, info: info)
    }

    /// Re-resolves the tapped coordinate at a new resolution and updates state.
    func reselect(at resolution: Int) {
        guard let coord = tappedCoordinate else { return }
        guard let res = H3Cell.Resolution(rawValue: Int32(resolution)) else { return }
        let latLng = H3LatLng(latitudeDegs: coord.latitude, longitudeDegs: coord.longitude)
        guard let cell = try? latLng.cell(at: res) else { return }
        let info = CellStore.shared.visitedCells(among: [cell.id])[cell.id]
        selectedCellResolution = resolution
        applyCell(cell, info: info)
    }

    func clear() {
        selectedCellIndex = nil
        selectedCellInfo = nil
        selectedCellBoundary = []
        tappedCoordinate = nil
        // selectedCellResolution is intentionally preserved for the next tap
    }

    private func applyCell(_ cell: H3Cell, info: VisitedCell?) {
        selectedCellIndex = cell.id
        selectedCellInfo = info
        selectedCellBoundary = (try? cell.boundary.map { $0.coordinates }) ?? []
    }
}

extension H3LatLng {
    var coordinates: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitudeDegs, longitude: longitudeDegs)
    }
}
