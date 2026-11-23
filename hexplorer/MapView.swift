import SwiftUI
import MapKit
import SwiftyH3

// MARK: - Annotation model

/// Custom annotation that carries the full MapFlag so the view can read color/priority.
final class FlagAnnotation: NSObject, MKAnnotation {
    let flag: MapFlag

    @objc dynamic var coordinate: CLLocationCoordinate2D { flag.coordinate }
    var title: String? { flag.label.isEmpty ? "" : flag.label }

    init(flag: MapFlag) {
        self.flag = flag
    }
}

// MARK: - Annotation view

final class FlagAnnotationView: MKMarkerAnnotationView {
    static let reuseID = "flag"

    override init(annotation: (any MKAnnotation)?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        clusteringIdentifier = "flags"
        canShowCallout = false
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
        //print to log
        
    }

    override func prepareForDisplay() {
        super.prepareForDisplay()
        guard let flagAnnotation = annotation as? FlagAnnotation else { return }
        markerTintColor = flagAnnotation.flag.color.uiColor
        displayPriority = flagAnnotation.flag.priority.displayPriority
        // Show the label beneath the balloon only for high-visibility flags.
        titleVisibility = flagAnnotation.flag.priority == .low ? .hidden : .adaptive
        if let symbolName = flagAnnotation.flag.priority.symbolName {
            glyphImage = UIImage(systemName: symbolName)
        }
    }
}

// MARK: - Cluster view

/// Shows the count of clustered flags using the colour of the highest-priority member.
final class FlagClusterAnnotationView: MKAnnotationView {
    static let reuseID = MKMapViewDefaultClusterAnnotationViewReuseIdentifier

    private let label = UILabel()

    override init(annotation: (any MKAnnotation)?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        displayPriority = .defaultHigh
        collisionMode = .circle
        frame = CGRect(x: 0, y: 0, width: 40, height: 40)
        label.textAlignment = .center
        label.textColor = .white
        label.font = .boldSystemFont(ofSize: 14)
        label.frame = bounds
        addSubview(label)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForDisplay() {
        super.prepareForDisplay()
        guard let cluster = annotation as? MKClusterAnnotation else { return }
        let members = cluster.memberAnnotations.compactMap { $0 as? FlagAnnotation }
        let count = cluster.memberAnnotations.count
        label.text = "\(count)"

        // Pick the colour of the highest-priority member; fall back to gray.
        let dominantColor: UIColor
        if members.contains(where: { $0.flag.priority == .required }) {
            dominantColor = members.first(where: { $0.flag.priority == .required })!.flag.color.uiColor
        } else if members.contains(where: { $0.flag.priority == .high }) {
            dominantColor = members.first(where: { $0.flag.priority == .high })!.flag.color.uiColor
        } else {
            dominantColor = members.first?.flag.color.uiColor ?? .systemGray
        }

        image = drawCircle(color: dominantColor, diameter: 40, text: "\(count)")
    }

    private func drawCircle(color: UIColor, diameter: CGFloat, text: String) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: diameter, height: diameter))
        return renderer.image { ctx in
            color.setFill()
            ctx.cgContext.fillEllipse(in: CGRect(x: 0, y: 0, width: diameter, height: diameter))
            let attrs: [NSAttributedString.Key: Any] = [
                .foregroundColor: UIColor.white,
                .font: UIFont.boldSystemFont(ofSize: diameter * 0.35)
            ]
            let size = (text as NSString).size(withAttributes: attrs)
            let rect = CGRect(
                x: (diameter - size.width) / 2,
                y: (diameter - size.height) / 2,
                width: size.width,
                height: size.height
            )
            (text as NSString).draw(in: rect, withAttributes: attrs)
        }
    }
}

// MARK: - MapView

struct MapView: UIViewRepresentable {
//    let region: MKCoordinateRegion
    var onMapViewCreated: (MKMapView) -> Void
    /// Called when the user taps the layers button, to open the layers panel.
    var onMapLayersButtonTap: () -> Void

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
//        mapView.setRegion(region, animated: false)
        mapView.preferredConfiguration = MapLayerSettings.shared.makeMapConfiguration()
        mapView.showsUserLocation = true
        // Restore the last zoom and position. Following the user location only moves the center,
        // so the zoom stays; without following the map opens where it was left.
        if let storedRegion = StoredMapViewport.region {
            mapView.setRegion(storedRegion, animated: false)
        }
        mapView.register(FlagAnnotationView.self, forAnnotationViewWithReuseIdentifier: FlagAnnotationView.reuseID)
//        mapView.register(FlagClusterAnnotationView.self, forAnnotationViewWithReuseIdentifier: FlagClusterAnnotationView.reuseID)

        addMapControls(to: mapView, coordinator: context.coordinator)

        // A pan with one finger stops following, as in Apple Maps; a pinch zoom does not.
        let panGesture = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
        panGesture.maximumNumberOfTouches = 1
        panGesture.delegate = context.coordinator
        mapView.addGestureRecognizer(panGesture)

        let tapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        tapGesture.delegate = context.coordinator
        mapView.addGestureRecognizer(tapGesture)

        context.coordinator.mapView = mapView
        DispatchQueue.main.async { onMapViewCreated(mapView) }

        return mapView
    }

    func updateUIView(_ uiView: MKMapView, context: Context) {
        context.coordinator.onMapLayersButtonTap = onMapLayersButtonTap
    }

    /// Adds the layers button and the follow button at the top right, as one Liquid Glass capsule
    /// with a thin line between the buttons, as in Apple Maps.
    private func addMapControls(to mapView: MKMapView, coordinator: Coordinator) {
        let layersButton = coordinator.layersButton
        layersButton.setImage(UIImage(systemName: "square.2.layers.3d"), for: .normal)
        layersButton.accessibilityLabel = "Map layers"
        layersButton.addTarget(coordinator, action: #selector(Coordinator.showMapLayers), for: .touchUpInside)

        // A custom button instead of MKUserTrackingButton: MapKit's own follow mode always zooms in.
        let followButton = coordinator.followButton
        followButton.addTarget(coordinator, action: #selector(Coordinator.toggleFollowingUserLocation), for: .touchUpInside)

        let buttonSeparator = UIView()
        buttonSeparator.backgroundColor = .separator

        let buttonStack = UIStackView(arrangedSubviews: [layersButton, buttonSeparator, followButton])
        buttonStack.axis = .vertical

        // Interactive glass reacts to touches, as the system map controls do.
        let controlsGlassEffect = UIGlassEffect()
        controlsGlassEffect.isInteractive = true
        let controlsBox = UIVisualEffectView(effect: controlsGlassEffect)
        controlsBox.translatesAutoresizingMaskIntoConstraints = false
        controlsBox.cornerConfiguration = .capsule()
        buttonStack.translatesAutoresizingMaskIntoConstraints = false
        controlsBox.contentView.addSubview(buttonStack)
        mapView.addSubview(controlsBox)

        let buttonSize: CGFloat = 44
        NSLayoutConstraint.activate([
            controlsBox.topAnchor.constraint(equalTo: mapView.safeAreaLayoutGuide.topAnchor, constant: 70),
            controlsBox.trailingAnchor.constraint(equalTo: mapView.safeAreaLayoutGuide.trailingAnchor, constant: -10),
            buttonStack.topAnchor.constraint(equalTo: controlsBox.topAnchor),
            buttonStack.bottomAnchor.constraint(equalTo: controlsBox.bottomAnchor),
            buttonStack.leadingAnchor.constraint(equalTo: controlsBox.leadingAnchor),
            buttonStack.trailingAnchor.constraint(equalTo: controlsBox.trailingAnchor),
            layersButton.widthAnchor.constraint(equalToConstant: buttonSize),
            layersButton.heightAnchor.constraint(equalToConstant: buttonSize),
            followButton.heightAnchor.constraint(equalToConstant: buttonSize),
            buttonSeparator.heightAnchor.constraint(equalToConstant: 0.5),
        ])
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
}

// MARK: - Coordinator

extension MapView {
    final class Coordinator: NSObject, MKMapViewDelegate, UIGestureRecognizerDelegate {
        weak var mapView: MKMapView?

        /// Called when the user taps a flag annotation directly.
        var onFlagEdit: ((MapFlag) -> Void)?

        /// Called when the user taps the layers button.
        var onMapLayersButtonTap: (() -> Void)?

        let layersButton = UIButton(type: .system)

        @objc func showMapLayers() {
            onMapLayersButtonTap?()
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            VisitedHexagonOverlays.shared.renderer(for: overlay)
                ?? NewCellFlashes.shared.renderer(for: overlay)
                ?? MKOverlayRenderer(overlay: overlay)
        }

        // MARK: Following the user location

        let followButton = UIButton(type: .system)

        /// When true, the map moves its center to each new user location and keeps its zoom.
        var followsUserLocation = StoredMapViewport.followsUserLocation {
            didSet {
                StoredMapViewport.followsUserLocation = followsUserLocation
                updateFollowButtonImage()
            }
        }

        override init() {
            super.init()
            updateFollowButtonImage()
        }

        private func updateFollowButtonImage() {
            followButton.setImage(UIImage(systemName: followsUserLocation ? "location.fill" : "location"), for: .normal)
        }

        @objc func toggleFollowingUserLocation() {
            followsUserLocation.toggle()
            if followsUserLocation, let mapView, let userCoordinate = mapView.userLocation.location?.coordinate {
                centerMap(mapView, on: userCoordinate)
            }
        }

        @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
            if gesture.state == .began { followsUserLocation = false }
        }

        func mapView(_ mapView: MKMapView, didUpdate userLocation: MKUserLocation) {
            guard followsUserLocation, let userCoordinate = userLocation.location?.coordinate else { return }
            centerMap(mapView, on: userCoordinate)
        }

        /// The duration of a follow move. It is about the time between two location updates,
        /// so the map moves at a constant speed, together with the animated blue dot.
        private static let followMoveDuration: TimeInterval = 1

        /// Animates the move only when the coordinate is in or near the visible area. A far move
        /// jumps directly: an animated pan over a long distance is slow, and loads tiles and
        /// hexagons for the full path.
        private func centerMap(_ mapView: MKMapView, on coordinate: CLLocationCoordinate2D) {
            let visibleMapRect = mapView.visibleMapRect
            let nearbyMapRect = visibleMapRect.insetBy(dx: -visibleMapRect.width / 2, dy: -visibleMapRect.height / 2)
            guard nearbyMapRect.contains(MKMapPoint(coordinate)) else {
                mapView.setCenter(coordinate, animated: false)
                return
            }
            // setCenter(_:animated:) has a fixed duration. A non-animated setCenter in a UIView
            // animation block uses the duration and the curve of the block instead.
            UIView.animate(
                withDuration: Self.followMoveDuration,
                delay: 0,
                options: [.curveLinear, .beginFromCurrentState, .allowUserInteraction]
            ) {
                mapView.setCenter(coordinate, animated: false)
            }
        }

        /// The pan recognizer only watches; MapKit's own gestures must still move the map.
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            gestureRecognizer is UIPanGestureRecognizer
        }

        /// Called once at the end of each pan or zoom, so the viewport is stored only when it settles.
        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            StoredMapViewport.region = mapView.region
        }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let mapView = gesture.view as? MKMapView else { return }
            // If a flag annotation is selected, let MapKit handle it exclusively.
            if mapView.selectedAnnotations.contains(where: { $0 is FlagAnnotation }) { return }
            let point = gesture.location(in: mapView)
            let coordinate = mapView.convert(point, toCoordinateFrom: mapView)
            let state = SelectedCellState.shared
            guard let resolution = H3Cell.Resolution(rawValue: Int32(state.currentZoomResolution)) else { return }
            let latLng = H3LatLng(latitudeDegs: coordinate.latitude, longitudeDegs: coordinate.longitude)

            if let cell = try? latLng.cell(at: resolution) {
//                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    if state.selectedCellIndex == cell.id {
                        state.clear()
                    } else {
                        let info = CellStore.shared.visitedCells(among: [cell.id])[cell.id]
                        state.select(cell: cell, info: info, coordinate: coordinate)
//                    }
                }
            }
        }

        // Cancel the tap gesture if it lands near a flag annotation so MapKit
        // handles it directly with no delay and no cell selection side-effect.
        // We use a coordinate-distance check (50 pt radius) to cover the balloon
        // which renders above the annotation view's anchor frame.
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            guard gestureRecognizer is UITapGestureRecognizer,
                  let mapView = gestureRecognizer.view as? MKMapView else { return true }
            let point = touch.location(in: mapView)
            for annotation in mapView.annotations {
                guard annotation is FlagAnnotation || annotation is MKClusterAnnotation else { continue }
                let annotationPoint = mapView.convert(annotation.coordinate, toPointTo: mapView)
                let dx = point.x - annotationPoint.x
                let dy = point.y - annotationPoint.y
                if dx * dx + dy * dy < 50 * 50 { return false }
            }
            return true
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if annotation is FlagAnnotation {
                return mapView.dequeueReusableAnnotationView(withIdentifier: FlagAnnotationView.reuseID, for: annotation)
            }
            if annotation is MKClusterAnnotation {
                return mapView.dequeueReusableAnnotationView(withIdentifier: FlagClusterAnnotationView.reuseID, for: annotation)
            }
            return nil
        }

        /// Makes the blue dot not selectable: no "My Location" callout and no pointer highlight.
        /// A tap on the dot then selects the hexagon cell below it.
        func mapView(_ mapView: MKMapView, didAdd views: [MKAnnotationView]) {
            for annotationView in views where annotationView.annotation is MKUserLocation {
                annotationView.isEnabled = false
                annotationView.canShowCallout = false
            }
        }

        func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
            guard let flagAnnotation = view.annotation as? FlagAnnotation else { return }
            // Immediately deselect so MapKit doesn't hold selection state.
            mapView.deselectAnnotation(flagAnnotation, animated: false)
            onFlagEdit?(flagAnnotation.flag)
        }

        func mapViewDidChangeVisibleRegion(_ mapView: MKMapView) {
            NotificationCenter.default.post(name: .mapViewportChanged, object: mapView)
            let zoomScale = MKZoomScale(mapView.bounds.width / CGFloat(mapView.visibleMapRect.size.width))
            let latitude = mapView.centerCoordinate.latitude
            let res = h3Resolution(for: zoomScale, latitude: latitude)
            SelectedCellState.shared.currentZoomResolution = Int(res.rawValue)
            VisitedHexagonOverlays.shared.mapViewportDidChange(mapView)
        }
    }
}

// MARK: - Stored viewport

/// The map viewport of the last session, in UserDefaults: the visible region (center and zoom)
/// and whether the map follows the user location (see `MapView.Coordinator.followsUserLocation`).
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

// MARK: - Notifications

extension Notification.Name {
    static let mapViewportChanged = Notification.Name("mapViewportChanged")
}

// MARK: - Shared helpers

func refreshHexagonOverlay(on mapView: MKMapView) {
    VisitedHexagonOverlays.shared.reloadHexagons(on: mapView)
}

/// Full sync: removes stale annotations and adds missing ones.
func syncFlagAnnotations(on mapView: MKMapView) {
    let store = FlagStore.shared
    let existing = mapView.annotations.compactMap { $0 as? FlagAnnotation }
    let storeIDs = Set(store.flags.map { $0.id })

    let toRemove = existing.filter { !storeIDs.contains($0.flag.id) }
    mapView.removeAnnotations(toRemove)

    let existingIDs = Set(existing.map { $0.flag.id })
    let toAdd = store.flags.filter { !existingIDs.contains($0.id) }
    mapView.addAnnotations(toAdd.map { FlagAnnotation(flag: $0) })
}

/// Refreshes a single annotation in place (used after edits).
func refreshFlagAnnotation(id: UUID, on mapView: MKMapView) {
    guard let flag = FlagStore.shared.flags.first(where: { $0.id == id }),
          let existing = mapView.annotations.compactMap({ $0 as? FlagAnnotation }).first(where: { $0.flag.id == id }) else { return }
    mapView.removeAnnotation(existing)
    mapView.addAnnotation(FlagAnnotation(flag: flag))
}
