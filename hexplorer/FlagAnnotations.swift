import MapKit

/// When true, flag clusters are drawn by `FlagClusterAnnotationView`: a circle in the colour of
/// the highest-priority flag. When false, MapKit draws its default cluster marker.
private let usesCustomFlagClusterView = false

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

// MARK: - Cluster view

///NOTE: disabled
/// Shows the count of clustered flags as a circle in the colour of the highest-priority member.
final class FlagClusterAnnotationView: MKAnnotationView {
    static let reuseID = MKMapViewDefaultClusterAnnotationViewReuseIdentifier

    private static let circleDiameter: CGFloat = 40

    override init(annotation: (any MKAnnotation)?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        displayPriority = .defaultHigh
        collisionMode = .circle
        frame = CGRect(x: 0, y: 0, width: Self.circleDiameter, height: Self.circleDiameter)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForDisplay() {
        super.prepareForDisplay()
        guard let cluster = annotation as? MKClusterAnnotation else { return }
        let memberFlags = cluster.memberAnnotations.compactMap { ($0 as? FlagAnnotation)?.flag }

        // The colour of the highest-priority member; gray when there are no flag members.
        let highestPriorityFlag = memberFlags.first { $0.priority == .required }
            ?? memberFlags.first { $0.priority == .high }
            ?? memberFlags.first
        let circleColor = highestPriorityFlag?.color.uiColor ?? .systemGray

        image = drawCircle(color: circleColor, text: "\(cluster.memberAnnotations.count)")
    }

    private func drawCircle(color: UIColor, text: String) -> UIImage {
        let diameter = Self.circleDiameter
        let imageRenderer = UIGraphicsImageRenderer(size: CGSize(width: diameter, height: diameter))
        return imageRenderer.image { drawingContext in
            color.setFill()
            drawingContext.cgContext.fillEllipse(in: CGRect(x: 0, y: 0, width: diameter, height: diameter))
            let textAttributes: [NSAttributedString.Key: Any] = [
                .foregroundColor: UIColor.white,
                .font: UIFont.boldSystemFont(ofSize: diameter * 0.35)
            ]
            let textSize = (text as NSString).size(withAttributes: textAttributes)
            let textRect = CGRect(
                x: (diameter - textSize.width) / 2,
                y: (diameter - textSize.height) / 2,
                width: textSize.width,
                height: textSize.height
            )
            (text as NSString).draw(in: textRect, withAttributes: textAttributes)
        }
    }
}

// MARK: - Map view helpers

extension MKMapView {
    func registerFlagAnnotationViews() {
        register(FlagAnnotationView.self, forAnnotationViewWithReuseIdentifier: FlagAnnotationView.reuseID)
        // Without this registration, the default cluster identifier gives MapKit's own cluster view.
        if usesCustomFlagClusterView {
            register(FlagClusterAnnotationView.self, forAnnotationViewWithReuseIdentifier: FlagClusterAnnotationView.reuseID)
        }
    }

    /// Returns the view for a flag or a flag cluster, or `nil` for other annotations.
    func dequeueFlagAnnotationView(for annotation: any MKAnnotation) -> MKAnnotationView? {
        if annotation is FlagAnnotation {
            return dequeueReusableAnnotationView(withIdentifier: FlagAnnotationView.reuseID, for: annotation)
        }
        if annotation is MKClusterAnnotation {
            return dequeueReusableAnnotationView(withIdentifier: FlagClusterAnnotationView.reuseID, for: annotation)
        }
        return nil
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
