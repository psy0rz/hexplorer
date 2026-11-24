import MapKit

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

/// The map marker of one flag. MapKit draws the balloon; this view sets its colour, glyph,
/// label and display priority from the flag.
final class FlagAnnotationView: MKMarkerAnnotationView {
    static let reuseID = "flag"

    override init(annotation: (any MKAnnotation)?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        clusteringIdentifier = Self.clusteringIdentifier(for: annotation)
        canShowCallout = false
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Sets the clustering identifier again when a reused view gets a new flag. MapKit decides the
    /// clusters after it sets the annotation and before `prepareForDisplay`, so a later value has no effect.
    override var annotation: (any MKAnnotation)? {
        willSet { clusteringIdentifier = Self.clusteringIdentifier(for: newValue) }
    }

    /// "Always show" flags get no identifier, so they never join a cluster and always show on their own.
    private static func clusteringIdentifier(for annotation: (any MKAnnotation)?) -> String? {
        guard let flagAnnotation = annotation as? FlagAnnotation,
              flagAnnotation.flag.priority != .required else { return nil }
        return "flags"
    }

    /// MapKit reuses marker views, so this sets every display property again for each flag.
    override func prepareForDisplay() {
        super.prepareForDisplay()
        guard let flagAnnotation = annotation as? FlagAnnotation else { return }
        markerTintColor = flagAnnotation.flag.color.uiColor
        displayPriority = flagAnnotation.flag.priority.displayPriority
        // Show the label beneath the balloon only for high-visibility flags.
        titleVisibility = flagAnnotation.flag.priority == .low ? .hidden : .adaptive
        // nil shows MapKit's default pin glyph, instead of the glyph of the flag that used this view before.
        glyphImage = flagAnnotation.flag.priority.symbolName.flatMap { UIImage(systemName: $0) }
    }
}

// MARK: - Map view helpers

extension MKMapView {
    func registerFlagAnnotationViews() {
        register(FlagAnnotationView.self, forAnnotationViewWithReuseIdentifier: FlagAnnotationView.reuseID)
    }

    /// Returns the view for a flag, or `nil` for other annotations. For a flag cluster, `nil`
    /// makes MapKit draw its default cluster marker.
    func dequeueFlagAnnotationView(for annotation: any MKAnnotation) -> MKAnnotationView? {
        guard annotation is FlagAnnotation else { return nil }
        return dequeueReusableAnnotationView(withIdentifier: FlagAnnotationView.reuseID, for: annotation)
    }

    /// True when a flag or a flag cluster is within 50 points of the point. The radius also
    /// covers the balloon, which is drawn above the anchor of the annotation view.
    func hasFlagAnnotation(near point: CGPoint) -> Bool {
        let searchRadius: CGFloat = 50
        return annotations.contains { annotation in
            guard annotation is FlagAnnotation || annotation is MKClusterAnnotation else { return false }
            let annotationPoint = convert(annotation.coordinate, toPointTo: self)
            let dx = point.x - annotationPoint.x
            let dy = point.y - annotationPoint.y
            return dx * dx + dy * dy < searchRadius * searchRadius
        }
    }

    /// Makes the flag annotations the same as the flags in `FlagStore`: removes the annotations
    /// of deleted flags and adds the annotations of new flags.
    func syncFlagAnnotations() {
        let storedFlags = FlagStore.shared.flags
        let flagAnnotationsOnMap = annotations.compactMap { $0 as? FlagAnnotation }

        let storedFlagIDs = Set(storedFlags.map(\.id))
        removeAnnotations(flagAnnotationsOnMap.filter { !storedFlagIDs.contains($0.flag.id) })

        let flagIDsOnMap = Set(flagAnnotationsOnMap.map(\.flag.id))
        let missingFlags = storedFlags.filter { !flagIDsOnMap.contains($0.id) }
        addAnnotations(missingFlags.map { FlagAnnotation(flag: $0) })
    }

    /// Replaces the annotation of one flag, so the map shows the edited flag.
    func refreshFlagAnnotation(id flagID: UUID) {
        guard let editedFlag = FlagStore.shared.flags.first(where: { $0.id == flagID }),
              let oldAnnotation = annotations.compactMap({ $0 as? FlagAnnotation }).first(where: { $0.flag.id == flagID })
        else { return }
        removeAnnotation(oldAnnotation)
        addAnnotation(FlagAnnotation(flag: editedFlag))
    }
}
