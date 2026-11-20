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

// MARK: - View

/// Draws the visited cells on top of the map. The cells are projected to screen points
/// again on every viewport change, the same way `HexagonHighlightView` does.
struct VisitedHexagonsView: View {
    let mapView: MKMapView

    private var hexagonsState: VisitedHexagonsState { VisitedHexagonsState.shared }

    var body: some View {
        let screenPaths = hexagonsState.screenPaths
        let colors = OverlayColors.shared

        ZStack {
            // Fills blend normally, so their colors stay as configured.
            Canvas { context, _ in
                context.fill(screenPaths.dense, with: .color(colors.denseFill))
                context.fill(screenPaths.full, with: .color(colors.fullFill))
                VisitedHexagonsDrawStats.fillCanvasRenderCount += 1
                VisitedHexagonsDrawStats.fillCount += 2
                VisitedHexagonsDrawStats.logIfIntervalElapsed()
            }

            // Strokes invert the map below them, so they stay visible on light and dark terrain.
            Canvas { context, _ in
                context.stroke(screenPaths.partial, with: .color(colors.partial), lineWidth: colors.partialWidth)
                context.stroke(screenPaths.dense, with: .color(colors.dense), lineWidth: colors.denseWidth)
                context.stroke(screenPaths.full, with: .color(colors.full), lineWidth: colors.fullWidth)
                VisitedHexagonsDrawStats.strokeCanvasRenderCount += 1
                VisitedHexagonsDrawStats.strokeCount += 3
                VisitedHexagonsDrawStats.logIfIntervalElapsed()
            }
            .blendMode(.difference)
        }
        .allowsHitTesting(false)
        .task {
            hexagonsState.mapViewportDidChange(mapView)
            for await _ in NotificationCenter.default.notifications(named: .mapViewportChanged, object: mapView) {
                hexagonsState.mapViewportDidChange(mapView)
            }
        }
    }
}

// MARK: - Draw statistics

/// Counts the drawing work and prints it at most once per second, to check the cost of
/// redrawing on every viewport change. A print happens on the first event after the
/// interval ends, so the last interval of a pan prints at the next pan.
enum VisitedHexagonsDrawStats {
    static var projectCount = 0
    static var addHexagonCount = 0
    static var fillCanvasRenderCount = 0
    static var strokeCanvasRenderCount = 0
    static var fillCount = 0
    static var strokeCount = 0
    private static var intervalStartTime = ContinuousClock.now

    static func logIfIntervalElapsed() {
        let intervalDuration = intervalStartTime.duration(to: .now)
        guard intervalDuration >= .seconds(1) else { return }

        let hexagonsPerProjection = projectCount > 0 ? addHexagonCount / projectCount : 0
        print("drawStats over \(intervalDuration): projections=\(projectCount), addHexagon=\(addHexagonCount) (\(hexagonsPerProjection)/projection), fillCanvas=\(fillCanvasRenderCount) (fills=\(fillCount)), strokeCanvas=\(strokeCanvasRenderCount) (strokes=\(strokeCount))")

        projectCount = 0
        addHexagonCount = 0
        fillCanvasRenderCount = 0
        strokeCanvasRenderCount = 0
        fillCount = 0
        strokeCount = 0
        intervalStartTime = .now
    }
}

// MARK: - State

enum CellDensity { case partial, dense, full }

/// Screen-space outlines of the visible visited cells, grouped by density.
struct VisitedHexagonPaths {
    var partial = Path()
    var dense = Path()
    var full = Path()

    mutating func addHexagon(_ screenPoints: [CGPoint], density: CellDensity) {
        VisitedHexagonsDrawStats.addHexagonCount += 1
        switch density {
        case .partial:
            partial.addLines(screenPoints)
            partial.closeSubpath()
        case .dense:
            dense.addLines(screenPoints)
            dense.closeSubpath()
        case .full:
            full.addLines(screenPoints)
            full.closeSubpath()
        }
    }
}

/// A visited cell kept in geographic coordinates, so it can be projected again after each pan or zoom.
private struct VisitedHexagon {
    let boundary: [CLLocationCoordinate2D]
    let boundingMapRect: MKMapRect
    let density: CellDensity
}

@Observable
final class VisitedHexagonsState {
    static let shared = VisitedHexagonsState()

    /// Outlines in the map view's coordinate space for the current viewport.
    private(set) var screenPaths = VisitedHexagonPaths()

    // The cells are loaded for an area larger than the viewport, so that a pan
    // only reprojects them and does not query H3 and the database on every frame.
    @ObservationIgnored private var loadedHexagons: [VisitedHexagon] = []
    @ObservationIgnored private var loadedMapRect = MKMapRect.null
    @ObservationIgnored private var loadedResolution: H3Cell.Resolution?

    private init() {}

    /// Loads the cells again if the viewport left the loaded area or the resolution changed,
    /// then projects the cells to screen points.
    func mapViewportDidChange(_ mapView: MKMapView) {
        let visibleMapRect = mapView.visibleMapRect
        guard mapView.bounds.width > 0, visibleMapRect.width > 0 else { return }

        let zoomScale = MKZoomScale(mapView.bounds.width / CGFloat(visibleMapRect.width))
        let resolution = h3Resolution(for: zoomScale, latitude: mapView.centerCoordinate.latitude)

        if resolution != loadedResolution || !loadedMapRect.contains(visibleMapRect) {
            loadHexagons(around: visibleMapRect, resolution: resolution)
        }
        projectHexagons(on: mapView)
    }

    /// Discards the loaded cells and loads them again, for example after new visits or a filter change.
    func reloadHexagons(on mapView: MKMapView) {
        loadedResolution = nil
        mapViewportDidChange(mapView)
    }

    // MARK: - Private

    private func loadHexagons(around visibleMapRect: MKMapRect, resolution: H3Cell.Resolution) {
        let loadStartTime = ContinuousClock.now

        // Load half a viewport extra on each side.
        let paddedMapRect = visibleMapRect
            .insetBy(dx: -visibleMapRect.width / 2, dy: -visibleMapRect.height / 2)
            .intersection(.world)

        let candidateCells = Self.hexagons(in: MKCoordinateRegion(paddedMapRect), resolution: resolution)
        let visitedByID = CellStore.shared.visitedCells(among: Set(candidateCells.map { $0.id }))
        let maxLeaves = visitedByID.values.map(\.visitedLeaves).max() ?? 1

        var hexagons: [VisitedHexagon] = []
        for cell in candidateCells {
            guard let info = visitedByID[cell.id],
                  let boundary = try? cell.boundary.map({ $0.coordinates }),
                  !boundary.isEmpty else { continue }

            let boundaryMapRect = boundary
                .map { MKMapRect(origin: MKMapPoint($0), size: MKMapSize(width: 0, height: 0)) }
                .reduce(MKMapRect.null) { $0.union($1) }
            let density = Self.classifyCell(info: info, resolution: Int(resolution.rawValue), maxLeaves: maxLeaves)
            hexagons.append(VisitedHexagon(boundary: boundary, boundingMapRect: boundaryMapRect, density: density))
        }

        loadedHexagons = hexagons
        loadedMapRect = paddedMapRect
        loadedResolution = resolution

        print("loadHexagons: res=\(resolution.rawValue), candidates=\(candidateCells.count), visited=\(hexagons.count), took \(loadStartTime.duration(to: .now))")
    }

    private func projectHexagons(on mapView: MKMapView) {
        let visibleMapRect = mapView.visibleMapRect
        var paths = VisitedHexagonPaths()
        for hexagon in loadedHexagons where hexagon.boundingMapRect.intersects(visibleMapRect) {
            let screenPoints = hexagon.boundary.map { mapView.convert($0, toPointTo: mapView) }
            paths.addHexagon(screenPoints, density: hexagon.density)
        }
        screenPaths = paths
        VisitedHexagonsDrawStats.projectCount += 1
        VisitedHexagonsDrawStats.logIfIntervalElapsed()
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
