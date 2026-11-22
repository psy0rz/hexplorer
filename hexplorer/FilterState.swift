import Foundation

/// How the map decides the density (partial, dense or full) of a visited cell.
enum FilterMode: String, CaseIterable, Identifiable {
    /// How recently the cell was visited (`lastVisitedAt`).
    case time       = "Time"
    /// How much of the cell is explored: the visited part of its cells two levels finer.
    case coverage   = "Coverage"
    /// How often the cell was visited (`visitCount`).
    case visits     = "Visits"
    /// How recently the cell was visited for the first time (`firstVisitedAt`).
    case discovered = "Discovered"

    var id: String { rawValue }
}

/// The filter settings. Each mode has a list of stops for its slider, and two indices into that
/// list: the two thumbs, which are the borders between partial, dense and full.
/// The slider keeps the lower index below the upper index.
@Observable
final class FilterState {
    static let shared = FilterState()

    var mode: FilterMode = .time

    // Time: visited at most `veryRecent` ago → full, at most `recent` ago → dense, older → partial.
    var veryRecentAgeStopIndex = FilterState.stopIndex(label: "1 d", in: FilterState.ageStops)
    var recentAgeStopIndex = FilterState.stopIndex(label: "1 wk", in: FilterState.ageStops)

    // Coverage: at least `full` → full, at least `dense` → dense, less → partial.
    var denseCoverageStopIndex = FilterState.stopIndex(label: "10%", in: FilterState.coverageStops)
    var fullCoverageStopIndex = FilterState.stopIndex(label: "50%", in: FilterState.coverageStops)

    // Visits: at least `full` visits → full, at least `dense` visits → dense, fewer → partial.
    var denseVisitCountStopIndex = FilterState.stopIndex(label: "2", in: FilterState.visitCountStops)
    var fullVisitCountStopIndex = FilterState.stopIndex(label: "5", in: FilterState.visitCountStops)

    // Discovered: first visited at most `newly` ago → full, at most `recently` ago → dense, older → partial.
    var newlyDiscoveredAgeStopIndex = FilterState.stopIndex(label: "1 wk", in: FilterState.ageStops)
    var recentlyDiscoveredAgeStopIndex = FilterState.stopIndex(label: "1 mo", in: FilterState.ageStops)

    /// All slider positions together; the map reloads when one of them changes.
    var thresholdStopIndices: [Int] {
        [veryRecentAgeStopIndex, recentAgeStopIndex,
         denseCoverageStopIndex, fullCoverageStopIndex,
         denseVisitCountStopIndex, fullVisitCountStopIndex,
         newlyDiscoveredAgeStopIndex, recentlyDiscoveredAgeStopIndex]
    }

    private init() {}

    // MARK: - Stops

    /// One selectable value on a filter slider.
    struct FilterStop {
        let value: Double
        let label: String
    }

    /// Ages in seconds: fine steps for recent ages, coarse steps for old ages.
    static let ageStops: [FilterStop] = {
        let hour: Double = 3600
        let day = 24 * hour
        return [
            FilterStop(value: 1 * hour,  label: "1 h"),
            FilterStop(value: 2 * hour,  label: "2 h"),
            FilterStop(value: 3 * hour,  label: "3 h"),
            FilterStop(value: 6 * hour,  label: "6 h"),
            FilterStop(value: 12 * hour, label: "12 h"),
            FilterStop(value: 1 * day,   label: "1 d"),
            FilterStop(value: 2 * day,   label: "2 d"),
            FilterStop(value: 3 * day,   label: "3 d"),
            FilterStop(value: 5 * day,   label: "5 d"),
            FilterStop(value: 7 * day,   label: "1 wk"),
            FilterStop(value: 14 * day,  label: "2 wk"),
            FilterStop(value: 21 * day,  label: "3 wk"),
            FilterStop(value: 30 * day,  label: "1 mo"),
            FilterStop(value: 61 * day,  label: "2 mo"),
            FilterStop(value: 91 * day,  label: "3 mo"),
            FilterStop(value: 182 * day, label: "6 mo"),
            FilterStop(value: 365 * day, label: "1 yr"),
        ]
    }()

    /// Coverage as a fraction: fine steps for low coverage, where most cells are.
    static let coverageStops: [FilterStop] = [0.02, 0.05, 0.10, 0.15, 0.20, 0.30, 0.40, 0.50, 0.65, 0.80, 0.90, 1.00]
        .map { FilterStop(value: $0, label: "\(Int(($0 * 100).rounded()))%") }

    /// Visit counts: fine steps for few visits, coarse steps for many.
    static let visitCountStops: [FilterStop] = [1, 2, 3, 4, 5, 7, 10, 15, 20, 30, 50, 100]
        .map { FilterStop(value: $0, label: "\(Int($0))") }

    private static func stopIndex(label: String, in stops: [FilterStop]) -> Int {
        stops.firstIndex { $0.label == label } ?? 0
    }
}
