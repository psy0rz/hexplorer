import SwiftUI
import MapKit
import SwiftyH3

/// Target hexagon edge length in screen points.
private let targetEdgePixels: Double = 20

/// Precomputed average edge lengths in meters for each H3 resolution (0–15).
private let h3EdgeLengthMeters: [Double] = (0...15).map { res in
    H3Cell.Resolution(rawValue: Int32(res))!.averageHexagonEdgeLength.value
}

/// Pick the H3 resolution whose average edge length is closest to `targetEdgePixels`
/// at the given zoom scale and latitude.
func h3Resolution(for zoomScale: MKZoomScale, latitude: Double) -> H3Cell.Resolution {
    let pixelsPerMeter = MKMapPointsPerMeterAtLatitude(latitude) * Double(zoomScale)
    let maxRes = CellStore.maxResolution // 13

    var bestRes = 0
    var bestDiff = Double.infinity
    for res in 0...maxRes {
        let edgePixels = h3EdgeLengthMeters[res] * pixelsPerMeter
        let diff = abs(edgePixels - targetEdgePixels)
        if diff < bestDiff {
            bestDiff = diff
            bestRes = res
        }
    }
    return H3Cell.Resolution(rawValue: Int32(bestRes))!
}

// MARK: - Overlays

enum CellDensity { case partial, dense, full }

/// Shows the visited cells as native MapKit overlays: one overlay for each density, with its
/// own fill and stroke, on top of one dark halo overlay for all cells. The halo keeps the
/// light outlines visible on light map backgrounds. MapKit draws the overlays and moves them
/// with the map; this class only replaces them when the loaded cells change.
@Observable
final class VisitedHexagonOverlays {
    static let shared = VisitedHexagonOverlays()

    // The cells are loaded for an area larger than the viewport, so that a pan
    // does not query H3 and the database again.
    @ObservationIgnored private var loadedMapRect = MKMapRect.null
    @ObservationIgnored private var loadedResolution: H3Cell.Resolution?

    @ObservationIgnored private var haloOverlay: MKMultiPolygon?
    @ObservationIgnored private var partialOverlay: MKMultiPolygon?
    @ObservationIgnored private var denseOverlay: MKMultiPolygon?
    @ObservationIgnored private var fullOverlay: MKMultiPolygon?

    private init() {}

    /// Loads the cells and replaces the overlays if the viewport left the loaded area
    /// or the resolution changed. Otherwise it does nothing.
    func mapViewportDidChange(_ mapView: MKMapView) {
        let visibleMapRect = mapView.visibleMapRect
        guard mapView.bounds.width > 0, visibleMapRect.width > 0 else { return }

        let zoomScale = MKZoomScale(mapView.bounds.width / CGFloat(visibleMapRect.width))
        let resolution = h3Resolution(for: zoomScale, latitude: mapView.centerCoordinate.latitude)

        if resolution != loadedResolution || !loadedMapRect.contains(visibleMapRect) {
            loadHexagons(around: visibleMapRect, resolution: resolution, on: mapView)
        }
    }

    /// Discards the loaded cells and loads them again, for example after new visits or a filter change.
    func reloadHexagons(on mapView: MKMapView) {
        loadedResolution = nil
        mapViewportDidChange(mapView)
    }

    /// Returns the renderer for one of the overlays of this class, or `nil` for other overlays.
    func renderer(for overlay: any MKOverlay) -> MKOverlayRenderer? {
        guard let multiPolygon = overlay as? MKMultiPolygon else { return nil }
        let colors = OverlayColors.shared
        let renderer = MKMultiPolygonRenderer(multiPolygon: multiPolygon)

        if multiPolygon === haloOverlay {
            renderer.strokeColor = UIColor(colors.halo)
            renderer.lineWidth = colors.haloWidth
        } else if multiPolygon === partialOverlay {
            renderer.strokeColor = UIColor(colors.partial)
            renderer.lineWidth = colors.partialWidth
        } else if multiPolygon === denseOverlay {
            renderer.fillColor = UIColor(colors.denseFill)
            renderer.strokeColor = UIColor(colors.dense)
            renderer.lineWidth = colors.denseWidth
        } else if multiPolygon === fullOverlay {
            renderer.fillColor = UIColor(colors.fullFill)
            renderer.strokeColor = UIColor(colors.full)
            renderer.lineWidth = colors.fullWidth
        } else {
            return nil
        }
        return renderer
    }

    // MARK: - Private

    private func loadHexagons(around visibleMapRect: MKMapRect, resolution: H3Cell.Resolution, on mapView: MKMapView) {
        let loadStartTime = ContinuousClock.now

        // Load half a viewport extra on each side.
        let paddedMapRect = visibleMapRect
            .insetBy(dx: -visibleMapRect.width / 2, dy: -visibleMapRect.height / 2)
            .intersection(.world)

        let candidateCells = Self.hexagons(in: MKCoordinateRegion(paddedMapRect), resolution: resolution)
        let visitedByID = CellStore.shared.visitedCells(among: Set(candidateCells.map { $0.id }))
        let maxLeaves = visitedByID.values.map(\.visitedLeaves).max() ?? 1

        var partialPolygons: [MKPolygon] = []
        var densePolygons: [MKPolygon] = []
        var fullPolygons: [MKPolygon] = []
        for cell in candidateCells {
            guard let info = visitedByID[cell.id],
                  let boundary = try? cell.boundary.map({ MKMapPoint($0.coordinates) }),
                  !boundary.isEmpty else { continue }

            let polygon = MKPolygon(points: boundary, count: boundary.count)
            switch Self.classifyCell(info: info, resolution: Int(resolution.rawValue), maxLeaves: maxLeaves) {
            case .partial: partialPolygons.append(polygon)
            case .dense:   densePolygons.append(polygon)
            case .full:    fullPolygons.append(polygon)
            }
        }

        replaceOverlays(partialPolygons: partialPolygons, densePolygons: densePolygons, fullPolygons: fullPolygons, on: mapView)
        loadedMapRect = paddedMapRect
        loadedResolution = resolution

        print("loadHexagons: res=\(resolution.rawValue), candidates=\(candidateCells.count), partial=\(partialPolygons.count), dense=\(densePolygons.count), full=\(fullPolygons.count), took \(loadStartTime.duration(to: .now))")
    }

    /// Adds the new overlays before it removes the old ones, so the map does not flicker.
    private func replaceOverlays(partialPolygons: [MKPolygon], densePolygons: [MKPolygon], fullPolygons: [MKPolygon], on mapView: MKMapView) {
        let oldOverlays = [haloOverlay, partialOverlay, denseOverlay, fullOverlay].compactMap { $0 }
        let allPolygons = partialPolygons + densePolygons + fullPolygons

        haloOverlay = allPolygons.isEmpty ? nil : MKMultiPolygon(allPolygons)
        partialOverlay = partialPolygons.isEmpty ? nil : MKMultiPolygon(partialPolygons)
        denseOverlay = densePolygons.isEmpty ? nil : MKMultiPolygon(densePolygons)
        fullOverlay = fullPolygons.isEmpty ? nil : MKMultiPolygon(fullPolygons)

        // The order sets the drawing order: the halo below everything, and
        // on a shared edge the denser cell on top.
        let newOverlays = [haloOverlay, partialOverlay, denseOverlay, fullOverlay].compactMap { $0 }
        mapView.addOverlays(newOverlays, level: .aboveLabels)
        mapView.removeOverlays(oldOverlays)
    }

    private static func classifyCell(info: VisitedCell, resolution: Int, maxLeaves: Int) -> CellDensity {
        let filter = FilterState.shared
        switch filter.mode {
        case .resolution:
            guard resolution < CellStore.maxResolution else { return .full }
            if info.visitedChildren >= Int(filter.fullChildrenThreshold)  { return .full }
            if info.visitedChildren >= Int(filter.denseChildrenThreshold) { return .dense }
            return .partial
        case .time:
            let age = Date().timeIntervalSince(info.lastVisitedAt)
            if age <= filter.veryRecentHours * 3600 { return .full }
            if age <= filter.recentDays * 86400     { return .dense }
            return .partial
        case .leafCount:
            guard maxLeaves > 0 else { return .partial }
            let score = Double(info.visitedLeaves) / Double(maxLeaves) * 100
            if score >= filter.fullLeafPercent  { return .full }
            if score >= filter.denseLeafPercent { return .dense }
            return .partial
        }
    }

    /// Returns H3 cells within the region at the given resolution.
    private static func hexagons(in region: MKCoordinateRegion, resolution: H3Cell.Resolution) -> [H3Cell] {
        let lat = region.center.latitude
        let lng = region.center.longitude
        let dLat = region.span.latitudeDelta / 2
        let dLng = region.span.longitudeDelta / 2

        let polygon = H3Polygon([
            H3LatLng(latitudeDegs: lat + dLat, longitudeDegs: lng - dLng),
            H3LatLng(latitudeDegs: lat + dLat, longitudeDegs: lng + dLng),
            H3LatLng(latitudeDegs: lat - dLat, longitudeDegs: lng + dLng),
            H3LatLng(latitudeDegs: lat - dLat, longitudeDegs: lng - dLng),
        ])

        do {
            return try polygon.cells(at: resolution)
        } catch {
            print("Error getting cells: \(error)")
            return []
        }
    }
}
