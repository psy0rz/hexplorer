import Foundation

/// How the map decides the density (partial, dense or full) of a visited cell.
enum FilterMode: String, CaseIterable, Identifiable {
    /// How recently the cell was visited (`lastVisitedAt`).
    case time       = "Time"
    /// How well the cell is explored: the exploration score from its visited leaf cells
    /// (0.5 ≈ one route through the cell, 1 = fully visited), the same at every zoom level.
    case coverage   = "Coverage"
    /// How often the cell was visited (`visitCount`).
    case visits     = "Visits"
    /// How recently the cell was visited for the first time (`firstVisitedAt`).
    case discovered = "Discovered"

    var id: String { rawValue }

    /// One sentence for the filter panel that tells what the mode shows.
    var explanation: String {
        switch self {
        case .time:       "Colors cells by how recently you were last there."
        case .coverage:   "Colors cells by how well you explored them: 0.5 is about one route through the cell, 1 is everything."
        case .visits:     "Colors cells by how many times you came back to them."
        case .discovered: "Colors cells by when you visited them for the first time."
        }
    }
}

/// The filter settings. Each mode has a list of stops for its slider, and two indices into that
/// list: the two thumbs, which are the borders between partial, dense and full.
/// The slider keeps the lower index below the upper index.
///
/// All settings are stored in UserDefaults. A slider position is stored as the label of its stop,
/// not as the index, so a stored setting stays correct when a stop list changes; an unknown
/// label falls back to the default.
@Observable
final class FilterState {
    static let shared = FilterState()

    var mode = FilterMode(rawValue: UserDefaults.standard.string(forKey: "filter.mode") ?? "") ?? .time {
        didSet { UserDefaults.standard.set(mode.rawValue, forKey: "filter.mode") }
    }

    // Time: visited at most `veryRecent` ago → full, at most `recent` ago → dense, older → partial.
    var veryRecentAgeStopIndex = FilterState.storedStopIndex(forKey: "filter.time.veryRecentAge", in: FilterState.ageStops, defaultLabel: DefaultStopLabel.veryRecentAge) {
        didSet { Self.storeStop(at: veryRecentAgeStopIndex, in: Self.ageStops, forKey: "filter.time.veryRecentAge") }
    }
    var recentAgeStopIndex = FilterState.storedStopIndex(forKey: "filter.time.recentAge", in: FilterState.ageStops, defaultLabel: DefaultStopLabel.recentAge) {
        didSet { Self.storeStop(at: recentAgeStopIndex, in: Self.ageStops, forKey: "filter.time.recentAge") }
    }

    // Coverage: an exploration score of at least `full` → full, at least `dense` → dense, less → partial.
    var denseCoverageStopIndex = FilterState.storedStopIndex(forKey: "filter.coverage.dense", in: FilterState.coverageStops, defaultLabel: DefaultStopLabel.denseCoverage) {
        didSet { Self.storeStop(at: denseCoverageStopIndex, in: Self.coverageStops, forKey: "filter.coverage.dense") }
    }
    var fullCoverageStopIndex = FilterState.storedStopIndex(forKey: "filter.coverage.full", in: FilterState.coverageStops, defaultLabel: DefaultStopLabel.fullCoverage) {
        didSet { Self.storeStop(at: fullCoverageStopIndex, in: Self.coverageStops, forKey: "filter.coverage.full") }
    }

    // Visits: at least `full` visits → full, at least `dense` visits → dense, fewer → partial.
    var denseVisitCountStopIndex = FilterState.storedStopIndex(forKey: "filter.visits.dense", in: FilterState.visitCountStops, defaultLabel: DefaultStopLabel.denseVisitCount) {
        didSet { Self.storeStop(at: denseVisitCountStopIndex, in: Self.visitCountStops, forKey: "filter.visits.dense") }
    }
    var fullVisitCountStopIndex = FilterState.storedStopIndex(forKey: "filter.visits.full", in: FilterState.visitCountStops, defaultLabel: DefaultStopLabel.fullVisitCount) {
        didSet { Self.storeStop(at: fullVisitCountStopIndex, in: Self.visitCountStops, forKey: "filter.visits.full") }
    }

    // Discovered: first visited at most `newly` ago → full, at most `recently` ago → dense, older → partial.
    var newlyDiscoveredAgeStopIndex = FilterState.storedStopIndex(forKey: "filter.discovered.newlyAge", in: FilterState.ageStops, defaultLabel: DefaultStopLabel.newlyDiscoveredAge) {
        didSet { Self.storeStop(at: newlyDiscoveredAgeStopIndex, in: Self.ageStops, forKey: "filter.discovered.newlyAge") }
    }
    var recentlyDiscoveredAgeStopIndex = FilterState.storedStopIndex(forKey: "filter.discovered.recentlyAge", in: FilterState.ageStops, defaultLabel: DefaultStopLabel.recentlyDiscoveredAge) {
        didSet { Self.storeStop(at: recentlyDiscoveredAgeStopIndex, in: Self.ageStops, forKey: "filter.discovered.recentlyAge") }
    }

    /// All slider positions together; the map reloads when one of them changes.
    var thresholdStopIndices: [Int] {
        [veryRecentAgeStopIndex, recentAgeStopIndex,
         denseCoverageStopIndex, fullCoverageStopIndex,
         denseVisitCountStopIndex, fullVisitCountStopIndex,
         newlyDiscoveredAgeStopIndex, recentlyDiscoveredAgeStopIndex]
    }

    private init() {}

    // MARK: - Defaults

    /// The default slider positions, as stop labels.
    private enum DefaultStopLabel {
        static let veryRecentAge = "1 d"
        static let recentAge = "1 wk"
        static let denseCoverage = "0.50"
        static let fullCoverage = "0.70"
        static let denseVisitCount = "2"
        static let fullVisitCount = "5"
        static let newlyDiscoveredAge = "1 wk"
        static let recentlyDiscoveredAge = "1 mo"
    }

    /// Sets the two slider positions of the active mode back to their defaults.
    /// The other modes keep their positions.
    func resetActiveModeToDefaults() {
        switch mode {
        case .time:
            veryRecentAgeStopIndex = Self.stopIndex(label: DefaultStopLabel.veryRecentAge, in: Self.ageStops)
            recentAgeStopIndex = Self.stopIndex(label: DefaultStopLabel.recentAge, in: Self.ageStops)
        case .coverage:
            denseCoverageStopIndex = Self.stopIndex(label: DefaultStopLabel.denseCoverage, in: Self.coverageStops)
            fullCoverageStopIndex = Self.stopIndex(label: DefaultStopLabel.fullCoverage, in: Self.coverageStops)
        case .visits:
            denseVisitCountStopIndex = Self.stopIndex(label: DefaultStopLabel.denseVisitCount, in: Self.visitCountStops)
            fullVisitCountStopIndex = Self.stopIndex(label: DefaultStopLabel.fullVisitCount, in: Self.visitCountStops)
        case .discovered:
            newlyDiscoveredAgeStopIndex = Self.stopIndex(label: DefaultStopLabel.newlyDiscoveredAge, in: Self.ageStops)
            recentlyDiscoveredAgeStopIndex = Self.stopIndex(label: DefaultStopLabel.recentlyDiscoveredAge, in: Self.ageStops)
        }
    }

    private static func stopIndex(label: String, in stops: [FilterStop]) -> Int {
        stops.firstIndex { $0.label == label } ?? 0
    }

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

    /// Exploration scores: fine steps from 0.5 (one route through the cell) to 0.8, where most cells are.
    static let coverageStops: [FilterStop] = [0.10, 0.20, 0.30, 0.40, 0.50, 0.55, 0.60, 0.65, 0.70, 0.75, 0.80, 0.90, 1.00]
        .map { FilterStop(value: $0, label: String(format: "%.2f", $0)) }

    /// Visit counts: fine steps for few visits, coarse steps for many.
    static let visitCountStops: [FilterStop] = [1, 2, 3, 4, 5, 7, 10, 15, 20, 30, 50, 100]
        .map { FilterStop(value: $0, label: "\(Int($0))") }

    // MARK: - Storage

    /// Reads the stored stop label for the key; falls back to the default label if nothing is stored
    /// or the label is no longer in the list.
    private static func storedStopIndex(forKey key: String, in stops: [FilterStop], defaultLabel: String) -> Int {
        let storedLabel = UserDefaults.standard.string(forKey: key)
        return stops.firstIndex { $0.label == storedLabel } ?? stopIndex(label: defaultLabel, in: stops)
    }

    private static func storeStop(at stopIndex: Int, in stops: [FilterStop], forKey key: String) {
        UserDefaults.standard.set(stops[stopIndex].label, forKey: key)
    }
}
