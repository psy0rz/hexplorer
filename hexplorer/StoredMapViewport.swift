import MapKit

/// The map viewport of the last session, in UserDefaults: the visible region (center and zoom)
/// and whether the map follows the user location (see `UserLocationFollower.followsUserLocation`).
enum StoredMapViewport {
    private static let centerLatitudeKey = "map.centerLatitude"
    private static let centerLongitudeKey = "map.centerLongitude"
    private static let latitudeDeltaKey = "map.latitudeDelta"
    private static let longitudeDeltaKey = "map.longitudeDelta"
    private static let followsUserLocationKey = "map.followsUserLocation"

    /// `nil` until a region was stored for the first time.
    static var region: MKCoordinateRegion? {
        get {
            let defaults = UserDefaults.standard
            guard defaults.object(forKey: latitudeDeltaKey) != nil else { return nil }
            return MKCoordinateRegion(
                center: CLLocationCoordinate2D(
                    latitude: defaults.double(forKey: centerLatitudeKey),
                    longitude: defaults.double(forKey: centerLongitudeKey)
                ),
                span: MKCoordinateSpan(
                    latitudeDelta: defaults.double(forKey: latitudeDeltaKey),
                    longitudeDelta: defaults.double(forKey: longitudeDeltaKey)
                )
            )
        }
        set {
            guard let newValue else { return }
            let defaults = UserDefaults.standard
            defaults.set(newValue.center.latitude, forKey: centerLatitudeKey)
            defaults.set(newValue.center.longitude, forKey: centerLongitudeKey)
            defaults.set(newValue.span.latitudeDelta, forKey: latitudeDeltaKey)
            defaults.set(newValue.span.longitudeDelta, forKey: longitudeDeltaKey)
        }
    }

    /// `true` on the first launch, so a new user starts at their own location.
    static var followsUserLocation: Bool {
        get { UserDefaults.standard.object(forKey: followsUserLocationKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: followsUserLocationKey) }
    }
}
