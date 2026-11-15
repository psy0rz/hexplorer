import Foundation
import MapKit
import SwiftUI
import GRDB

// MARK: - Supporting types

enum FlagColor: String, Codable, CaseIterable, Identifiable {
    case red, orange, yellow, green, blue, purple, gray

    var id: String { rawValue }

    var uiColor: UIColor {
        switch self {
        case .red:    return .systemRed
        case .orange: return .systemOrange
        case .yellow: return .systemYellow
        case .green:  return .systemGreen
        case .blue:   return .systemBlue
        case .purple: return .systemPurple
        case .gray:   return .systemGray
        }
    }

    var label: String { rawValue.capitalized }
}

enum FlagPriority: String, Codable, CaseIterable, Identifiable {
    /// Always visible — never hidden when pins overlap.
    case required
    /// Visible at most zoom levels; hidden when heavily overlapping.
    case high
    /// Hidden early when pins overlap; useful for informational markers.
    case low

    var id: String { rawValue }

    var displayPriority: MKFeatureDisplayPriority {
        switch self {
        case .required: return .required
        case .high:     return .defaultHigh
        case .low:      return .defaultLow
        }
    }

    var label: String {
        switch self {
        case .required: return "Always visible"
        case .high:     return "High"
        case .low:      return "Low"
        }
    }
}

// MARK: - Model

struct MapFlag: Codable, Identifiable, Equatable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "flag"

    let id: UUID
    var latitude: Double
    var longitude: Double
    var label: String
    var color: FlagColor
    var priority: FlagPriority

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    init(
        id: UUID = UUID(),
        coordinate: CLLocationCoordinate2D,
        label: String = "",
        color: FlagColor = .red,
        priority: FlagPriority = .high
    ) {
        self.id = id
        self.latitude = coordinate.latitude
        self.longitude = coordinate.longitude
        self.label = label
        self.color = color
        self.priority = priority
    }

    // GRDB column mapping
    enum Columns {
        static let id       = Column(CodingKeys.id)
        static let latitude = Column(CodingKeys.latitude)
        static let longitude = Column(CodingKeys.longitude)
        static let label    = Column(CodingKeys.label)
        static let color    = Column(CodingKeys.color)
        static let priority = Column(CodingKeys.priority)
    }
}

// MARK: - Store

@Observable
final class FlagStore {
    static let shared = FlagStore()

    private(set) var flags: [MapFlag] = []

    private var db: DatabasePool { CellStore.shared.db }

    private init() {
        load()
    }

    func addFlag(at coordinate: CLLocationCoordinate2D, label: String = "", color: FlagColor = .red, priority: FlagPriority = .high) {
        let flag = MapFlag(coordinate: coordinate, label: label, color: color, priority: priority)
        do {
            try db.write { db in try flag.insert(db) }
            flags.append(flag)
        } catch {
            print("FlagStore addFlag error: \(error)")
        }
    }

    func updateFlag(_ updated: MapFlag) {
        do {
            try db.write { db in try updated.update(db) }
            if let idx = flags.firstIndex(where: { $0.id == updated.id }) {
                flags[idx] = updated
            }
        } catch {
            print("FlagStore updateFlag error: \(error)")
        }
    }

    func removeFlag(id: UUID) {
        do {
            _ = try db.write { db in try MapFlag.deleteOne(db, key: id) }
            flags.removeAll { $0.id == id }
        } catch {
            print("FlagStore removeFlag error: \(error)")
        }
    }

    func removeFlag(at offsets: IndexSet) {
        let toRemove = offsets.map { flags[$0] }
        do {
            try db.write { db in
                for flag in toRemove { try MapFlag.deleteOne(db, key: flag.id) }
            }
            flags.remove(atOffsets: offsets)
        } catch {
            print("FlagStore removeFlag(at:) error: \(error)")
        }
    }


     func load() {
        do {
            flags = try db.read { db in try MapFlag.fetchAll(db) }
        } catch {
            print("FlagStore load error: \(error)")
        }
    }

}
