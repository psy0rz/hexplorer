import Foundation
import MapKit

/// The base map that MapKit draws below the hexagons.
enum MapStyle: String, CaseIterable, Identifiable {
    /// The street map.
    case standard  = "Standard"
    /// The satellite images.
    case satellite = "Satellite"

    var id: String { rawValue }
}

/// The map layer settings from the layers panel. All settings are stored in UserDefaults.
@Observable
final class MapLayerSettings {
    static let shared = MapLayerSettings()

    var mapStyle = MapStyle(rawValue: UserDefaults.standard.string(forKey: "mapLayers.style") ?? "") ?? .satellite {
        didSet { UserDefaults.standard.set(mapStyle.rawValue, forKey: "mapLayers.style") }
    }

    /// Road and place names on the satellite map. The standard map always shows them:
    /// MapKit has no setting to hide them there.
    var showsSatelliteLabels = UserDefaults.standard.object(forKey: "mapLayers.showsSatelliteLabels") as? Bool ?? true {
        didSet { UserDefaults.standard.set(showsSatelliteLabels, forKey: "mapLayers.showsSatelliteLabels") }
    }

    /// Icons and names of shops, parks and other places, on both map styles.
    var showsPointsOfInterest = UserDefaults.standard.object(forKey: "mapLayers.showsPointsOfInterest") as? Bool ?? true {
        didSet { UserDefaults.standard.set(showsPointsOfInterest, forKey: "mapLayers.showsPointsOfInterest") }
    }

    private init() {}

    /// The MapKit configuration for the current settings. A satellite map with labels is
    /// a hybrid map; without labels it is an imagery map, which has no points of interest.
    func makeMapConfiguration() -> MKMapConfiguration {
        let pointOfInterestFilter: MKPointOfInterestFilter = showsPointsOfInterest ? .includingAll : .excludingAll
        switch mapStyle {
        case .standard:
            let standardConfiguration = MKStandardMapConfiguration()
            standardConfiguration.pointOfInterestFilter = pointOfInterestFilter
            return standardConfiguration
        case .satellite where showsSatelliteLabels:
            let hybridConfiguration = MKHybridMapConfiguration()
            hybridConfiguration.pointOfInterestFilter = pointOfInterestFilter
            return hybridConfiguration
        case .satellite:
            return MKImageryMapConfiguration()
        }
    }

    /// Points of interest show only on maps with labels.
    var canShowPointsOfInterest: Bool {
        mapStyle == .standard || showsSatelliteLabels
    }
}
