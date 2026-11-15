import SwiftUI

@main
struct HexplorerApp: App {
    init() {
        // Ensure CellStore is initialized on the main thread before any renderer accesses it
        _ = CellStore.shared

        // Restart tracking if it was active before the app was terminated
        let tracker = LocationTracker.shared
        if tracker.trackingWasActive {
            tracker.startTracking()
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
