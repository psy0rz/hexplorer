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

    var mode: FilterMode = .resolution

    // Time mode
    var recentDays: Double = 7       // → dense
    var veryRecentHours: Double = 24  // → full

    // Resolution mode (visitedChildren thresholds, range 1–7)
    var denseChildrenThreshold: Double = 2
    var fullChildrenThreshold: Double = 6

    // Leaf count mode (% of the max visitedLeaves on screen, range 1–100)
    var denseLeafPercent: Double = 10
    var fullLeafPercent: Double = 50

    private init() {}
}
