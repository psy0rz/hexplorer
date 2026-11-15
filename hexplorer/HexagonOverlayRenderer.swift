import MapKit
import SwiftyH3
import SwiftUI

/// Target hexagon edge length in screen points.
private let targetEdgePixels: Double = 20//

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



final class HexagonOverlayRenderer: MKOverlayRenderer {

    override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in context: CGContext) {
        guard self.overlay is HexagonOverlay else { return }
        let region = MKCoordinateRegion(mapRect)
        let latitude = region.center.latitude
        let resolution = h3Resolution(for: zoomScale, latitude: latitude)
//        print("scale=\(zoomScale), lat=\(String(format: "%.1f", latitude)), h3=\(resolution.rawValue)")
//        print("\(Date())")

        let gridPath = CGMutablePath()
        let partialPath = CGMutablePath()
        let densePath = CGMutablePath()
        let fullPath = CGMutablePath()

        let visibleCells = Self.hexagons(in: region, resolution: resolution)

        let visibleIDs = Set(visibleCells.map { $0.id })
        let visitedMap = CellStore.shared.visitedCells(among: visibleIDs)

        let maxLeaves = visitedMap.values.map(\.visitedLeaves).max() ?? 1

        for cell in visibleCells {
            guard let boundary = try? cell.boundary.map({ $0.coordinates }),
                  !boundary.isEmpty else { continue }

            let points = boundary.map { point(for: MKMapPoint($0)) }

            let path: CGMutablePath

            if let info = visitedMap[cell.id] {
                switch Self.classifyCell(info: info, resolution: Int(resolution.rawValue), maxLeaves: maxLeaves) {
                case .full:    path = fullPath
                case .dense:   path = densePath
                case .partial: path = partialPath
                }
            } else {
                path = gridPath
            }

            path.move(to: points[0])
            for i in 1..<points.count { path.addLine(to: points[i]) }
            path.closeSubpath()
        }

        let colors = OverlayColors.shared
        let lineWidth = 1 / CGFloat(zoomScale)

        // Draw fills (back to front: partial, dense, full)
//        if !partialPath.isEmpty {
//            context.setFillColor(UIColor(colors.partialFill).cgColor)
//            context.addPath(partialPath)
//            context.drawPath(using: .fill)
//        }
        if !densePath.isEmpty {
            context.setFillColor(UIColor(colors.denseFill).cgColor)
            context.addPath(densePath)
            context.drawPath(using: .fill)
        }
        if !fullPath.isEmpty {
            context.setFillColor(UIColor(colors.fullFill).cgColor)
            context.addPath(fullPath)
            context.drawPath(using: .fill)
        }

        // Draw strokes
        context.setBlendMode(.normal)
        if !partialPath.isEmpty {
            context.setLineWidth(lineWidth * colors.partialWidth)
            context.setStrokeColor(UIColor(colors.partial).cgColor)
            context.addPath(partialPath)
            context.drawPath(using: .stroke)
        }
        if !densePath.isEmpty {
            context.setLineWidth(lineWidth * colors.denseWidth)
            context.setStrokeColor(UIColor(colors.dense).cgColor)
            context.addPath(densePath)
            context.drawPath(using: .stroke)
        }
        if !fullPath.isEmpty {
            context.setLineWidth(lineWidth * colors.fullWidth)
            context.setStrokeColor(UIColor(colors.full).cgColor)
            context.addPath(fullPath)
            context.drawPath(using: .stroke)
        }
    }

    // MARK: - Private

    private enum CellDensity { case partial, dense, full }

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
        let dLat = region.span.latitudeDelta * 0.6
        let dLng = region.span.longitudeDelta * 0.6

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
