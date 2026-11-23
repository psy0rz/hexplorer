import ActivityKit
import Foundation

/// The data of the tracking Live Activity on the Lock Screen and in the Dynamic Island.
/// The widget extension has an identical copy in HexplorerWidgets/TrackingActivityAttributes.swift:
/// ActivityKit matches the two by name, so keep both the same.
struct TrackingActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// The number of res-13 cells in this tracking session that were not visited before.
        var newCellCount: Int
    }

    /// When tracking started. The system counts the duration from this date, so the app
    /// does not have to update the activity every second.
    var trackingStartDate: Date
}

/// Starts, updates and ends the tracking Live Activity.
@MainActor
final class TrackingLiveActivityController {
    static let shared = TrackingLiveActivityController()

    private var trackingActivity: Activity<TrackingActivityAttributes>?

    private init() {}

    /// Ends activities that are left from an earlier run, then starts a new one.
    /// A request fails when the app is not in the foreground; then there is no activity for this session.
    func start(trackingStartDate: Date) {
        Task {
            for leftoverActivity in Activity<TrackingActivityAttributes>.activities {
                await leftoverActivity.end(nil, dismissalPolicy: .immediate)
            }
            guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
            do {
                trackingActivity = try Activity.request(
                    attributes: TrackingActivityAttributes(trackingStartDate: trackingStartDate),
                    content: ActivityContent(state: .init(newCellCount: 0), staleDate: nil)
                )
            } catch {
                print("Could not start the tracking Live Activity: \(error)")
            }
        }
    }

    func update(newCellCount: Int) {
        guard let trackingActivity else { return }
        Task {
            await trackingActivity.update(ActivityContent(state: .init(newCellCount: newCellCount), staleDate: nil))
        }
    }

    func end(newCellCount: Int) {
        guard let trackingActivity else { return }
        self.trackingActivity = nil
        Task {
            await trackingActivity.end(
                ActivityContent(state: .init(newCellCount: newCellCount), staleDate: nil),
                dismissalPolicy: .immediate
            )
        }
    }
}
