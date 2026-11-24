import MapKit
import UIKit.UIGestureRecognizerSubclass

/// Keeps the user location in the center of the map, without a change of zoom, while follow mode
/// is on. It owns the follow button. A pan with one finger turns follow mode off, as in Apple Maps;
/// a pinch zoom does not.
///
/// A custom follower instead of `MKUserTrackingMode.follow`: MapKit's own follow mode always zooms in.
final class UserLocationFollower: NSObject, UIGestureRecognizerDelegate {
    let followButton = UIButton(type: .system)

    private weak var mapView: MKMapView?

    /// When true, the map moves its center to each new user location and keeps its zoom.
    private(set) var followsUserLocation = StoredMapViewport.followsUserLocation {
        didSet {
            StoredMapViewport.followsUserLocation = followsUserLocation
            updateFollowButtonImage()
        }
    }

    /// The duration of a follow move. It is about the time between two location updates,
    /// so the map moves at a constant speed, together with the animated blue dot.
    private static let followMoveDuration: TimeInterval = 1

    /// True while one or more fingers touch the map.
    private var mapIsTouched = false

    /// Calls `stepFollowMove` once per frame while a follow move runs; nil when no move runs.
    private var followMoveDisplayLink: CADisplayLink?
    private var followMoveStartPoint = MKMapPoint()
    private var followMoveTargetPoint = MKMapPoint()
    private var followMoveStartTime: CFTimeInterval = 0

    /// True while a follow move changes the map center.
    var isMovingMap: Bool { followMoveDisplayLink != nil }

    override init() {
        super.init()
        followButton.addTarget(self, action: #selector(toggleFollowingUserLocation), for: .touchUpInside)
        updateFollowButtonImage()
    }

    /// Adds the gesture recognizers that watch the user's touches on the map.
    func attach(to mapView: MKMapView) {
        self.mapView = mapView

        let panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        panGesture.maximumNumberOfTouches = 1
        panGesture.delegate = self
        mapView.addGestureRecognizer(panGesture)

        // While a finger touches the map, a follow move stops and no new one starts,
        // so MapKit's own pan and zoom gestures get the map.
        let mapTouchGesture = MapTouchGestureRecognizer(target: self, action: #selector(handleMapTouch(_:)))
        mapTouchGesture.delegate = self
        mapView.addGestureRecognizer(mapTouchGesture)
    }

    func userLocationDidUpdate(to userCoordinate: CLLocationCoordinate2D) {
        guard followsUserLocation, let mapView else { return }
        centerMap(mapView, on: userCoordinate)
    }

    private func updateFollowButtonImage() {
        followButton.setImage(UIImage(systemName: followsUserLocation ? "location.fill" : "location"), for: .normal)
    }

    @objc private func toggleFollowingUserLocation() {
        followsUserLocation.toggle()
        if followsUserLocation, let mapView, let userCoordinate = mapView.userLocation.location?.coordinate {
            centerMap(mapView, on: userCoordinate)
        }
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        if gesture.state == .began { followsUserLocation = false }
    }

    @objc private func handleMapTouch(_ gesture: MapTouchGestureRecognizer) {
        switch gesture.state {
        case .began:
            mapIsTouched = true
            stopFollowMove()
        case .ended, .cancelled, .failed:
            mapIsTouched = false
        default:
            break
        }
    }

    /// The pan and touch recognizers only watch; MapKit's own gestures must still move the map.
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        true
    }

    // MARK: Follow move

    /// Moves the map center to the coordinate. The move is smooth only when the coordinate is
    /// in or near the visible area. A far move jumps directly: a smooth pan over a long distance
    /// is slow, and loads tiles and hexagons for the full path.
    ///
    /// The smooth move sets the center without animation on each frame. An animation
    /// (`UIView.animate` or `setCenter(_:animated: true)`) would block MapKit's pan and zoom
    /// gestures while it runs, and with a location update each second it nearly always runs.
    private func centerMap(_ mapView: MKMapView, on coordinate: CLLocationCoordinate2D) {
        guard !mapIsTouched else { return }

        let visibleMapRect = mapView.visibleMapRect
        let nearbyMapRect = visibleMapRect.insetBy(dx: -visibleMapRect.width / 2, dy: -visibleMapRect.height / 2)
        guard nearbyMapRect.contains(MKMapPoint(coordinate)) else {
            stopFollowMove()
            mapView.setCenter(coordinate, animated: false)
            return
        }

        // A new move starts from where the map is now, also when the previous move has not ended.
        followMoveStartPoint = MKMapPoint(mapView.centerCoordinate)
        followMoveTargetPoint = MKMapPoint(coordinate)
        followMoveStartTime = CACurrentMediaTime()
        if followMoveDisplayLink == nil {
            let displayLink = CADisplayLink(target: self, selector: #selector(stepFollowMove))
            displayLink.add(to: .main, forMode: .common)
            followMoveDisplayLink = displayLink
        }
    }

    /// Moves the map center one frame further, at a constant speed, from the start to the target.
    @objc private func stepFollowMove() {
        guard let mapView else { stopFollowMove(); return }
        let moveProgress = min((CACurrentMediaTime() - followMoveStartTime) / Self.followMoveDuration, 1)
        let framePoint = MKMapPoint(
            x: followMoveStartPoint.x + (followMoveTargetPoint.x - followMoveStartPoint.x) * moveProgress,
            y: followMoveStartPoint.y + (followMoveTargetPoint.y - followMoveStartPoint.y) * moveProgress
        )
        // Stop before the last frame, so `regionDidChangeAnimated` stores the final region.
        if moveProgress >= 1 { stopFollowMove() }
        mapView.setCenter(framePoint.coordinate, animated: false)
    }

    private func stopFollowMove() {
        followMoveDisplayLink?.invalidate()
        followMoveDisplayLink = nil
    }
}

// MARK: - Map touch recognizer

/// Begins when the first finger touches the map and ends when the last finger lifts.
/// It recognizes together with the other gestures and does not cancel their touches,
/// so it only reports the touch.
final class MapTouchGestureRecognizer: UIGestureRecognizer {
    private var activeTouchCount = 0

    override init(target: Any?, action: Selector?) {
        super.init(target: target, action: action)
        cancelsTouchesInView = false
        delaysTouchesEnded = false
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        activeTouchCount += touches.count
        state = state == .possible ? .began : .changed
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        removeTouches(touches)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        removeTouches(touches)
    }

    override func reset() {
        activeTouchCount = 0
    }

    private func removeTouches(_ touches: Set<UITouch>) {
        activeTouchCount -= touches.count
        state = activeTouchCount > 0 ? .changed : .ended
    }
}
