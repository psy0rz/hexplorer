import Foundation

enum FilterMode: String, CaseIterable, Identifiable {
    case resolution = "Resolution"
    case time       = "Time"
    case leafCount  = "Leaves"

    var id: String { rawValue }
}

@Observable
final class FilterState {
    static let shared = FilterState()

    var mode: FilterMode = .time

    // Time mode: indices into `ageStops`. A cell visited at most `veryRecentMaxAge` ago is full,
    // at most `recentMaxAge` ago is dense, and older is partial.
    // The time slider keeps veryRecentAgeStopIndex < recentAgeStopIndex.
    var veryRecentAgeStopIndex = FilterState.ageStopIndex(label: "1 d")
    var recentAgeStopIndex = FilterState.ageStopIndex(label: "1 wk")

    var veryRecentMaxAge: TimeInterval { Self.ageStops[veryRecentAgeStopIndex].seconds }
    var recentMaxAge: TimeInterval { Self.ageStops[recentAgeStopIndex].seconds }

    // Resolution mode (visitedChildren thresholds, range 1–7)
    var denseChildrenThreshold: Double = 2
    var fullChildrenThreshold: Double = 6

    // Leaf count mode (% of the max visitedLeaves on screen, range 1–100)
    var denseLeafPercent: Double = 10
    var fullLeafPercent: Double = 50

    private init() {}

    // MARK: - Age stops

    /// One selectable age on the time slider.
    struct AgeStop {
        let seconds: TimeInterval
        let label: String
    }

    /// The ages the time slider can select: fine steps for recent ages, coarse steps for old ages.
    static let ageStops: [AgeStop] = {
        let hour: TimeInterval = 3600
        let day = 24 * hour
        return [
            AgeStop(seconds: 1 * hour,  label: "1 h"),
            AgeStop(seconds: 2 * hour,  label: "2 h"),
            AgeStop(seconds: 3 * hour,  label: "3 h"),
            AgeStop(seconds: 6 * hour,  label: "6 h"),
            AgeStop(seconds: 12 * hour, label: "12 h"),
            AgeStop(seconds: 1 * day,   label: "1 d"),
            AgeStop(seconds: 2 * day,   label: "2 d"),
            AgeStop(seconds: 3 * day,   label: "3 d"),
            AgeStop(seconds: 5 * day,   label: "5 d"),
            AgeStop(seconds: 7 * day,   label: "1 wk"),
            AgeStop(seconds: 14 * day,  label: "2 wk"),
            AgeStop(seconds: 21 * day,  label: "3 wk"),
            AgeStop(seconds: 30 * day,  label: "1 mo"),
            AgeStop(seconds: 61 * day,  label: "2 mo"),
            AgeStop(seconds: 91 * day,  label: "3 mo"),
            AgeStop(seconds: 182 * day, label: "6 mo"),
            AgeStop(seconds: 365 * day, label: "1 yr"),
        ]
    }()

    private static func ageStopIndex(label: String) -> Int {
        ageStops.firstIndex { $0.label == label } ?? 0
    }
}
