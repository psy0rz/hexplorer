import Foundation
import CoreLocation
import SwiftyH3

@MainActor
@Observable
final class LocationTracker {
    static let shared = LocationTracker()

    /// Fixes with a larger error radius than this (in meters) are rejected.
    /// A res-13 cell has an edge of about 3.5 m, so a less accurate fix records the wrong cells.
    private static let maximumHorizontalAccuracy: CLLocationAccuracy = 20

    /// How often the buffer is written to the database while the app is active,
    /// so the map shows new cells quickly.
    private static let activeFlushInterval: TimeInterval = 1
    /// How often the buffer is written while the app is not active. Less frequent
    /// writes let the CPU and the disk stay idle longer.
    private static let inactiveFlushInterval: TimeInterval = 60

    private let manager = CLLocationManager()
    private var backgroundSession: CLBackgroundActivitySession?
    private var updatesTask: Task<Void, Never>?

    private var locationBuffer: [CLLocation] = []
    private var flushTimer: Timer?
    private var lastCellID: UInt64 = 0

    private(set) var isTracking = false
    private(set) var flushCount = 0

    /// Set from the scene phase. Changes the flush interval, and flushes the buffer
    /// when the app becomes active or stops being active.
    var isAppActive = true {
        didSet {
            guard isAppActive != oldValue else { return }
            flushBuffer()
            if isTracking { scheduleFlushTimer() }
        }
    }

    var trackingWasActive: Bool {
        get { UserDefaults.standard.bool(forKey: "locationTrackingActive") }
        set { UserDefaults.standard.set(newValue, forKey: "locationTrackingActive") }
    }

    private init() {
        UserDefaults.standard.register(defaults: ["locationTrackingActive": true])
    }

    func startTracking() {
        guard !isTracking else { return }

        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }

        backgroundSession = CLBackgroundActivitySession()
        isTracking = true
        trackingWasActive = true
        
        scheduleFlushTimer()

        updatesTask = Task {
            do {
                for try await update in CLLocationUpdate.liveUpdates(.default) {
                    guard isTracking else { break }
                    // A stationary update is also recorded: it has the position where the device
                    // stopped. When it is in the same cell as the last fix, the cell check skips it.
                    guard let location = update.location else { continue }
                    // A negative value means the fix has no valid coordinate.
                    guard location.horizontalAccuracy >= 0,
                          location.horizontalAccuracy <= Self.maximumHorizontalAccuracy else {
                        print("Rejected location: horizontalAccuracy=\(location.horizontalAccuracy) m")
                        continue
                    }

                    let latLng = H3LatLng(
                        latitudeDegs: location.coordinate.latitude,
                        longitudeDegs: location.coordinate.longitude
                    )
                    if let cell = try? latLng.cell(at: .res13), cell.id == lastCellID {
                        continue
                    }
                    lastCellID = (try? latLng.cell(at: .res13))?.id ?? lastCellID

                    locationBuffer.append(location)
                }
                if !locationBuffer.isEmpty {
                    flushBuffer()
                }
            } catch {
                print("Location updates ended: \(error)")
            }

            if isTracking {
                stopTracking()
            }
        }
    }

    func stopTracking() {
        isTracking = false
        trackingWasActive = false

        flushBuffer()

        updatesTask?.cancel()
        updatesTask = nil

        flushTimer?.invalidate()
        flushTimer = nil

        backgroundSession?.invalidate()
        backgroundSession = nil

        lastCellID = 0
    }

    /// Replaces the flush timer with one that fires at the interval for the current app state.
    private func scheduleFlushTimer() {
        flushTimer?.invalidate()
        let flushInterval = isAppActive ? Self.activeFlushInterval : Self.inactiveFlushInterval
        flushTimer = Timer.scheduledTimer(withTimeInterval: flushInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.flushBuffer()
            }
        }
        // Lets the system group the timer with other wakeups.
        flushTimer?.tolerance = flushInterval * 0.1
    }

    private func flushBuffer() {
        guard !locationBuffer.isEmpty else { return }
        let locationsToWrite = locationBuffer
        locationBuffer.removeAll()

        let coords = locationsToWrite.map {
            (latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude)
        }
        do {
            try CellStore.shared.recordVisits(locations: coords)
            flushCount += 1
        } catch {
            print("Failed to record visits: \(error)")
        }
    }
}
