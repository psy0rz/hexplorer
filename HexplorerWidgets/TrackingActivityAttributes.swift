import ActivityKit
import Foundation

/// The data of the tracking Live Activity. This is a copy of the type in
/// hexplorer/TrackingLiveActivity.swift: ActivityKit matches the two by name, so keep both the same.
struct TrackingActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// The number of res-13 cells in this tracking session that were not visited before.
        var newCellCount: Int
    }

    /// When tracking started. The system counts the duration from this date.
    var trackingStartDate: Date
}
