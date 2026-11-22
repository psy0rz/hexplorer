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

/// How much a visited cell is "explored". `classifyCell` decides the density from the
/// active filter mode (time, coverage, visits or discovered). Each density has its own overlay layer
/// and its own colors in `OverlayColors`.
enum CellDensity {
    /// Visited a little: only an outline, no fill.
    case partial
    /// Visited more: outline and a light fill.
    case dense
    /// Visited the most: outline and the strongest fill.
    case full
}

/// Shows the visited cells as native MapKit overlays: one overlay for each density, with its
/// own fill and stroke, on top of one dark halo overlay for all cells. The halo keeps the
/// light outlines visible on light map backgrounds. MapKit draws the overlays and moves them
/// with the map; this class only replaces the overlays whose cells changed.
@Observable
final class VisitedHexagonOverlays {
    static let shared = VisitedHexagonOverlays()

    /// The overlay layers. The order of the cases is the drawing order on the map,
    /// from bottom to top; `insert(_:for:replacing:on:)` depends on it.
    ///
    /// Each visited cell is in two layers: the halo layer, and the layer of its density.
    /// Two adjacent cells share an edge. When they have different densities, both layers
    /// draw that edge, and the line of the higher (denser) layer is on top.
    private enum OverlayLayer: CaseIterable {
        /// All visited cells, as a wide dark line below all other layers. It shows as a thin
        /// dark edge on each side of the light outlines, so they stay visible on light backgrounds.
        case halo
        /// The partial cells: outline only.
        case partial
        /// The dense cells: fill and outline.
        case dense
        /// The full cells: fill and outline, on top of everything.
        case full
    }

    /// The overlay of one layer that is on the map now, and the cells it shows.
    /// A reload compares the cells, and replaces the overlay only if they changed.
    private struct LayerContent {
        let overlay: MKMultiPolygon
        let cellIDs: Set<UInt64>
    }

    // The cells are loaded for an area larger than the viewport, so that a pan
    // does not query H3 and the database again.
    @ObservationIgnored private var loadedMapRect = MKMapRect.null
    @ObservationIgnored private var loadedResolution: H3Cell.Resolution?

    @ObservationIgnored private var contentByLayer: [OverlayLayer: LayerContent] = [:]

    private init() {}

    /// Loads the cells and updates the overlays if the viewport left the loaded area
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
        guard let multiPolygon = overlay as? MKMultiPolygon,
              let layer = OverlayLayer.allCases.first(where: { contentByLayer[$0]?.overlay === multiPolygon })
        else { return nil }

        let colors = OverlayColors.shared
        let renderer = MKMultiPolygonRenderer(multiPolygon: multiPolygon)
        switch layer {
        case .halo:
            renderer.strokeColor = UIColor(colors.halo)
            renderer.lineWidth = colors.haloWidth
        case .partial:
            renderer.strokeColor = UIColor(colors.partial)
            renderer.lineWidth = colors.partialWidth
        case .dense:
            renderer.fillColor = UIColor(colors.denseFill)
            renderer.strokeColor = UIColor(colors.dense)
            renderer.lineWidth = colors.denseWidth
        case .full:
            renderer.fillColor = UIColor(colors.fullFill)
            renderer.strokeColor = UIColor(colors.full)
            renderer.lineWidth = colors.fullWidth
        }
        return renderer
    }

    // MARK: - Private

    /// Loads the visited cells near the viewport and puts them on the map, in these steps:
    /// 1. Find all H3 cells of the resolution in the viewport plus padding.
    /// 2. Get the cells of those that are visited from the database.
    /// 3. Give each visited cell a density, and put its polygon into the halo layer and
    ///    into the layer of its density (see `OverlayLayer`).
    /// 4. Replace the overlays of the layers whose cells changed.
    private func loadHexagons(around visibleMapRect: MKMapRect, resolution: H3Cell.Resolution, on mapView: MKMapView) {
        let loadStartTime = ContinuousClock.now

        // Load half a viewport extra on each side.
        let paddedMapRect = visibleMapRect
            .insetBy(dx: -visibleMapRect.width / 2, dy: -visibleMapRect.height / 2)
            .intersection(.world)

        let candidateCells = Self.hexagons(in: MKCoordinateRegion(paddedMapRect), resolution: resolution)
        let visitedByID = CellStore.shared.visitedCells(among: Set(candidateCells.map { $0.id }))
        // Coverage needs an extra database query, so calculate it only in coverage mode.
        let coverageByCellID = FilterState.shared.mode == .coverage
            ? Self.coverageByCellID(of: candidateCells.filter { visitedByID[$0.id] != nil }, resolution: resolution)
            : [:]

        // The polygons go to MapKit; the cell IDs let `updateOverlays` find the changed layers.
        var polygonsByLayer: [OverlayLayer: [MKPolygon]] = [:]
        var cellIDsByLayer: [OverlayLayer: Set<UInt64>] = [:]
        for cell in candidateCells {
            guard let info = visitedByID[cell.id],
                  let boundary = try? cell.boundary.map({ MKMapPoint($0.coordinates) }),
                  !boundary.isEmpty else { continue }

            let polygon = MKPolygon(points: boundary, count: boundary.count)
            let densityLayer: OverlayLayer = switch Self.classifyCell(info: info, coverage: coverageByCellID[cell.id] ?? 0) {
            case .partial: .partial
            case .dense:   .dense
            case .full:    .full
            }
            // The same polygon goes into the halo layer and into its density layer.
            for layer in [OverlayLayer.halo, densityLayer] {
                polygonsByLayer[layer, default: []].append(polygon)
                cellIDsByLayer[layer, default: []].insert(cell.id)
            }
        }

        let changedLayers = updateOverlays(polygonsByLayer: polygonsByLayer, cellIDsByLayer: cellIDsByLayer, on: mapView)
        loadedMapRect = paddedMapRect
        loadedResolution = resolution

        let cellCounts = OverlayLayer.allCases.map { "\($0)=\(cellIDsByLayer[$0]?.count ?? 0)" }.joined(separator: ", ")
        print("loadHexagons: res=\(resolution.rawValue), candidates=\(candidateCells.count), \(cellCounts), changed=[\(changedLayers.map { "\($0)" }.joined(separator: ", "))], took \(loadStartTime.duration(to: .now))")
    }

    /// Replaces only the layers whose cells changed, and returns them. A new overlay goes directly
    /// above the overlay it replaces, so the drawing order stays the same, and the old overlay
    /// is removed after that, so the map does not flicker.
    private func updateOverlays(
        polygonsByLayer: [OverlayLayer: [MKPolygon]],
        cellIDsByLayer: [OverlayLayer: Set<UInt64>],
        on mapView: MKMapView
    ) -> [OverlayLayer] {
        var changedLayers: [OverlayLayer] = []

        for layer in OverlayLayer.allCases {
            let newCellIDs = cellIDsByLayer[layer] ?? []
            let oldContent = contentByLayer[layer]
            guard newCellIDs != (oldContent?.cellIDs ?? []) else { continue }
            changedLayers.append(layer)

            if let polygons = polygonsByLayer[layer], !polygons.isEmpty {
                let newOverlay = MKMultiPolygon(polygons)
                // Set the content first: MapKit asks for the renderer while the overlay is inserted.
                contentByLayer[layer] = LayerContent(overlay: newOverlay, cellIDs: newCellIDs)
                insert(newOverlay, for: layer, replacing: oldContent?.overlay, on: mapView)
            } else {
                contentByLayer[layer] = nil
            }
            if let oldOverlay = oldContent?.overlay {
                mapView.removeOverlay(oldOverlay)
            }
        }
        return changedLayers
    }

    /// Inserts the overlay at the position of its layer: above the overlay it replaces, else above
    /// the nearest lower layer, else below the nearest higher layer.
    private func insert(_ overlay: MKMultiPolygon, for layer: OverlayLayer, replacing oldOverlay: MKMultiPolygon?, on mapView: MKMapView) {
        if let oldOverlay {
            mapView.insertOverlay(overlay, above: oldOverlay)
            return
        }

        let layers = OverlayLayer.allCases
        guard let layerIndex = layers.firstIndex(of: layer) else { return }

        if let lowerOverlay = layers[..<layerIndex].reversed().lazy.compactMap({ self.contentByLayer[$0]?.overlay }).first {
            mapView.insertOverlay(overlay, above: lowerOverlay)
        } else if let higherOverlay = layers[(layerIndex + 1)...].lazy.compactMap({ self.contentByLayer[$0]?.overlay }).first {
            mapView.insertOverlay(overlay, below: higherOverlay)
        } else {
            mapView.addOverlay(overlay, level: .aboveLabels)
        }
    }

    /// Gives a visited cell its density, from the filter mode and the slider positions in `FilterState`.
    /// `coverage` is used only in coverage mode.
    private static func classifyCell(info: VisitedCell, coverage: Double) -> CellDensity {
        let filter = FilterState.shared
        switch filter.mode {
        case .time:
            return density(
                forAge: Date().timeIntervalSince(info.lastVisitedAt),
                fullMaxAge: FilterState.ageStops[filter.veryRecentAgeStopIndex].value,
                denseMaxAge: FilterState.ageStops[filter.recentAgeStopIndex].value
            )
        case .discovered:
            return density(
                forAge: Date().timeIntervalSince(info.firstVisitedAt),
                fullMaxAge: FilterState.ageStops[filter.newlyDiscoveredAgeStopIndex].value,
                denseMaxAge: FilterState.ageStops[filter.recentlyDiscoveredAgeStopIndex].value
            )
        case .coverage:
            return density(
                forAmount: coverage,
                denseMinimum: FilterState.coverageStops[filter.denseCoverageStopIndex].value,
                fullMinimum: FilterState.coverageStops[filter.fullCoverageStopIndex].value
            )
        case .visits:
            return density(
                forAmount: Double(info.visitCount),
                denseMinimum: FilterState.visitCountStops[filter.denseVisitCountStopIndex].value,
                fullMinimum: FilterState.visitCountStops[filter.fullVisitCountStopIndex].value
            )
        }
    }

    /// For ages: younger is denser.
    private static func density(forAge age: TimeInterval, fullMaxAge: TimeInterval, denseMaxAge: TimeInterval) -> CellDensity {
        if age <= fullMaxAge { return .full }
        if age <= denseMaxAge { return .dense }
        return .partial
    }

    /// For amounts such as coverage or visit count: more is denser.
    private static func density(forAmount amount: Double, denseMinimum: Double, fullMinimum: Double) -> CellDensity {
        if amount >= fullMinimum { return .full }
        if amount >= denseMinimum { return .dense }
        return .partial
    }

    /// The coverage of each cell: the fraction of its descendants two resolutions finer that are
    /// visited (one resolution finer just above the leaf resolution). A leaf cell has coverage 1.
    /// Two levels down gives 49 descendants: fine enough to show partial coverage, and the same
    /// meaning at every zoom level.
    private static func coverageByCellID(of visitedCells: [H3Cell], resolution: H3Cell.Resolution) -> [UInt64: Double] {
        let descendantResolutionValue = min(Int(resolution.rawValue) + 2, CellStore.maxResolution)
        guard descendantResolutionValue > Int(resolution.rawValue),
              let descendantResolution = H3Cell.Resolution(rawValue: Int32(descendantResolutionValue))
        else { return Dictionary(uniqueKeysWithValues: visitedCells.map { ($0.id, 1.0) }) }

        var descendantIDsByCellID: [UInt64: [UInt64]] = [:]
        for cell in visitedCells {
            descendantIDsByCellID[cell.id] = (try? cell.children(at: descendantResolution).map(\.id)) ?? []
        }

        // Query in chunks, to stay below the SQLite limit for the number of query parameters.
        let allDescendantIDs = descendantIDsByCellID.values.flatMap { $0 }
        var visitedDescendantIDs = Set<UInt64>()
        for chunkStart in stride(from: 0, to: allDescendantIDs.count, by: 10_000) {
            let chunk = allDescendantIDs[chunkStart..<min(chunkStart + 10_000, allDescendantIDs.count)]
            visitedDescendantIDs.formUnion(CellStore.shared.visitedCells(among: Set(chunk)).keys)
        }

        return descendantIDsByCellID.mapValues { descendantIDs in
            guard !descendantIDs.isEmpty else { return 0 }
            let visitedCount = descendantIDs.filter { visitedDescendantIDs.contains($0) }.count
            return Double(visitedCount) / Double(descendantIDs.count)
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
