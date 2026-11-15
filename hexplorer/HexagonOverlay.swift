import MapKit

final class HexagonOverlay: NSObject, MKOverlay {
    let boundingMapRect: MKMapRect = .world
    let coordinate = CLLocationCoordinate2D(latitude: 0, longitude: 0)
}
