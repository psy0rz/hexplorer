import Foundation
import CoreLocation
import SwiftyH3

@MainActor
@Observable
final class LocationTracker {
    static let shared = LocationTracker()

    private let manager = CLLocationManager()
    private var backgroundSession: CLBackgroundActivitySession?
    private var updatesTask: Task<Void, Never>?

    private var locationBuffer: [CLLocation] = []
    private var flushTimer: Timer?
    private var lastCellID: UInt64 = 0

    private(set) var isTracking = false
    private(set) var flushCount = 0

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

        flushTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.flushBuffer()
            }
        }

        updatesTask = Task {
            do {
                for try await update in CLLocationUpdate.liveUpdates(.default) {
                    guard isTracking else { break }
                    if update.stationary { continue }
                    guard let location = update.location else { continue }

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
