import SwiftUI
import MapKit
import SwiftyH3

// MARK: - MapView

struct MapView: UIViewRepresentable {
    var onMapViewCreated: (MKMapView) -> Void
    /// Called when the user taps the layers button, to open the layers panel.
    var onMapLayersButtonTap: () -> Void
    /// Called when the user taps a flag, to edit it.
    var onFlagTap: (MapFlag) -> Void

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.preferredConfiguration = MapLayerSettings.shared.makeMapConfiguration()
        mapView.showsUserLocation = true
        // Restore the last zoom and position. Following the user location only moves the center,
        // so the zoom stays; without following the map opens where it was left.
        if let storedRegion = StoredMapViewport.region {
            mapView.setRegion(storedRegion, animated: false)
        }
        mapView.registerFlagAnnotationViews()

        let mapControls = MapControlsView(
            layersButton: context.coordinator.layersButton,
            followButton: context.coordinator.userLocationFollower.followButton
        )
        mapView.addSubview(mapControls)
        NSLayoutConstraint.activate([
            mapControls.topAnchor.constraint(equalTo: mapView.safeAreaLayoutGuide.topAnchor, constant: 70),
            mapControls.trailingAnchor.constraint(equalTo: mapView.safeAreaLayoutGuide.trailingAnchor, constant: -10),
        ])

        context.coordinator.userLocationFollower.attach(to: mapView)

        let tapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        tapGesture.delegate = context.coordinator
        mapView.addGestureRecognizer(tapGesture)

        DispatchQueue.main.async { onMapViewCreated(mapView) }

        return mapView
    }

    func updateUIView(_ uiView: MKMapView, context: Context) {
        context.coordinator.onMapLayersButtonTap = onMapLayersButtonTap
        context.coordinator.onFlagTap = onFlagTap
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
}

// MARK: - Coordinator

extension MapView {
    /// The delegate of the map view. MapKit allows only one delegate, so the coordinator
    /// passes each job to the class that does it.
    final class Coordinator: NSObject, MKMapViewDelegate, UIGestureRecognizerDelegate {
        var onMapLayersButtonTap: (() -> Void)?
        var onFlagTap: ((MapFlag) -> Void)?

        let layersButton = UIButton(type: .system)
        let userLocationFollower = UserLocationFollower()

        override init() {
            super.init()
            layersButton.setImage(UIImage(systemName: "square.2.layers.3d"), for: .normal)
            layersButton.accessibilityLabel = "Map layers"
            layersButton.addTarget(self, action: #selector(showMapLayers), for: .touchUpInside)
        }

        @objc private func showMapLayers() {
            onMapLayersButtonTap?()
        }

        // MARK: Map changes

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            VisitedHexagonOverlays.shared.renderer(for: overlay)
                ?? CellFlasher.shared.renderer(for: overlay)
                ?? MKOverlayRenderer(overlay: overlay)
        }

        func mapView(_ mapView: MKMapView, didUpdate userLocation: MKUserLocation) {
            guard let userCoordinate = userLocation.location?.coordinate else { return }
            userLocationFollower.userLocationDidUpdate(to: userCoordinate)
        }

        func mapViewDidChangeVisibleRegion(_ mapView: MKMapView) {
            NotificationCenter.default.post(name: .mapViewportChanged, object: mapView)
            let zoomScale = MKZoomScale(mapView.bounds.width / CGFloat(mapView.visibleMapRect.size.width))
            let zoomResolution = h3Resolution(for: zoomScale, latitude: mapView.centerCoordinate.latitude)
            SelectedCellState.shared.currentZoomResolution = Int(zoomResolution.rawValue)
            VisitedHexagonOverlays.shared.mapViewportDidChange(mapView)
        }

        /// Called once at the end of each pan or zoom, so the viewport is stored only when it settles.
        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            // A follow move changes the region on each frame; only its last frame is stored.
            guard !userLocationFollower.isMovingMap else { return }
            StoredMapViewport.region = mapView.region
        }

        // MARK: Cell taps

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let mapView = gesture.view as? MKMapView else { return }
            // If a flag annotation is selected, let MapKit handle it exclusively.
            if mapView.selectedAnnotations.contains(where: { $0 is FlagAnnotation }) { return }
            let tappedCoordinate = mapView.convert(gesture.location(in: mapView), toCoordinateFrom: mapView)
            SelectedCellState.shared.toggleSelection(at: tappedCoordinate)
        }

        /// A tap near a flag does not select a cell: MapKit handles it directly, with no delay.
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            guard let mapView = gestureRecognizer.view as? MKMapView else { return true }
            return !mapView.hasFlagAnnotation(near: touch.location(in: mapView))
        }

        // MARK: Annotations

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            mapView.dequeueFlagAnnotationView(for: annotation)
        }

        /// Makes the blue dot not selectable: no "My Location" callout and no pointer highlight.
        /// A tap on the dot then selects the hexagon cell below it.
        func mapView(_ mapView: MKMapView, didAdd views: [MKAnnotationView]) {
            for annotationView in views where annotationView.annotation is MKUserLocation {
                annotationView.isEnabled = false
                annotationView.canShowCallout = false
            }
        }

        /// Deselects each tapped flag or cluster at once. MapKit does not split or join a selected
        /// cluster, so a cluster that stays selected looks like a normal marker after a zoom.
        func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
            if let flagAnnotation = view.annotation as? FlagAnnotation {
                mapView.deselectAnnotation(flagAnnotation, animated: false)
                onFlagTap?(flagAnnotation.flag)
            } else if let clusterAnnotation = view.annotation as? MKClusterAnnotation {
                mapView.deselectAnnotation(clusterAnnotation, animated: false)
                // Zoom in until the flags of the cluster show separately.
                mapView.showAnnotations(clusterAnnotation.memberAnnotations, animated: true)
            }
        }
    }
}

// MARK: - Notifications

extension Notification.Name {
    static let mapViewportChanged = Notification.Name("mapViewportChanged")
}
