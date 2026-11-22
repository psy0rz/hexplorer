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
        glyphImage = switch flagAnnotation.flag.priority {
        case .required: UIImage(systemName: "flag.fill")
        case .high:     UIImage(systemName: "flag")
        case .low:      UIImage(systemName: "arrow.down")
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

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
//        mapView.setRegion(region, animated: false)
        mapView.mapType = .satellite
        mapView.showsUserLocation = true
        mapView.userTrackingMode = .follow
        mapView.register(FlagAnnotationView.self, forAnnotationViewWithReuseIdentifier: FlagAnnotationView.reuseID)
//        mapView.register(FlagClusterAnnotationView.self, forAnnotationViewWithReuseIdentifier: FlagClusterAnnotationView.reuseID)

        let trackingButton = MKUserTrackingButton(mapView: mapView)
        trackingButton.translatesAutoresizingMaskIntoConstraints = false
        trackingButton.backgroundColor = UIColor.systemBackground.withAlphaComponent(0.8)
        trackingButton.layer.cornerRadius = 5
        mapView.addSubview(trackingButton)
        NSLayoutConstraint.activate([
            trackingButton.topAnchor.constraint(equalTo: mapView.safeAreaLayoutGuide.topAnchor, constant: 60),
            trackingButton.trailingAnchor.constraint(equalTo: mapView.safeAreaLayoutGuide.trailingAnchor, constant: -10),
        ])

        let tapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        tapGesture.delegate = context.coordinator
        mapView.addGestureRecognizer(tapGesture)

        context.coordinator.mapView = mapView
        DispatchQueue.main.async { onMapViewCreated(mapView) }

        return mapView
    }

    func updateUIView(_ uiView: MKMapView, context: Context) {}

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

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            VisitedHexagonOverlays.shared.renderer(for: overlay) ?? MKOverlayRenderer(overlay: overlay)
        }

        func mapView(_ mapView: MKMapView, didChange mode: MKUserTrackingMode, animated: Bool) {
            if mode == .followWithHeading {
                mapView.setUserTrackingMode(.follow, animated: animated)
            }
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
            guard let mapView = gestureRecognizer.view as? MKMapView else { return true }
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
