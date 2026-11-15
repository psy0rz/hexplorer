import Foundation
import MapKit
import GRDB
import SwiftyH3

struct VisitedCell: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "visitedCell"

    var h3Index: UInt64
    var firstVisitedAt: Date
    var lastVisitedAt: Date
    var visitCount: Int
    var visitedChildren: Int
    var visitedLeaves: Int
}

final class CellStore {
    static let shared = CellStore()

    private static let leafResolution = H3Cell.Resolution(rawValue: Int32(maxResolution))!
    static let maxResolution = 13

    private(set) var db: DatabasePool

    let databaseURL: URL = FileManager.default
        .urls(for: .documentDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("visited.sqlite")

    private init() {
        let path = databaseURL.path

        do {
            db = try DatabasePool(path: path)
            try db.write { db in
                try db.create(table: "visitedCell", ifNotExists: true) { t in
                    t.primaryKey("h3Index", .integer)
                    t.column("firstVisitedAt", .datetime).notNull()
                    t.column("lastVisitedAt", .datetime).notNull()
                    t.column("visitCount", .integer).notNull().defaults(to: 1)
                    t.column("visitedChildren", .integer).notNull().defaults(to: 0)
                    t.column("visitedLeaves", .integer).notNull().defaults(to: 0)
                }
                if try db.columns(in: "visitedCell").map(\.name).contains("visitedChildren") == false {
                    try db.alter(table: "visitedCell") { t in
                        t.add(column: "visitedChildren", .integer).notNull().defaults(to: 0)
                        t.add(column: "visitedLeaves", .integer).notNull().defaults(to: 0)
                    }
                }
                try db.create(table: "flag", ifNotExists: true) { t in
                    t.column("id", .text).primaryKey()
                    t.column("latitude", .double).notNull()
                    t.column("longitude", .double).notNull()
                    t.column("label", .text).notNull().defaults(to: "")
                    t.column("color", .text).notNull().defaults(to: "red")
                    t.column("priority", .text).notNull().defaults(to: "high")
                }
            }
        } catch {
            fatalError("Failed to initialize CellStore: \(error)")
        }
    }

    // MARK: - Public API

    func recordVisit(latitude: Double, longitude: Double) throws {
        try recordVisits(locations: [(latitude: latitude, longitude: longitude)])
    }

    func recordVisits(locations: [(latitude: Double, longitude: Double)]) throws {
        let now = Date()
        try db.write { [leafResolution = Self.leafResolution] db in
            for location in locations {
                let latLng = H3LatLng(
                    latitudeDegs: location.latitude,
                    longitudeDegs: location.longitude
                )
                try Self.recordVisit(in: db, latLng: latLng, now: now, leafResolution: leafResolution)
            }
        }
    }

    func generateTestVisits(centerLatitude: Double, centerLongitude: Double, latDelta: Double, lngDelta: Double, count: Int = 10_000) throws {
        var locations: [(latitude: Double, longitude: Double)] = []
        for _ in 0..<count {
            let lat = centerLatitude + Double.random(in: -latDelta/2...latDelta/2)
            let lng = centerLongitude + Double.random(in: -lngDelta/2...lngDelta/2)
            locations.append((latitude: lat, longitude: lng))
        }
        try recordVisits(locations: locations)
    }

    func deleteAll() throws {
        _ = try db.write { db in
            try VisitedCell.deleteAll(db)
        }
    }

    /// Deletes all res-13 leaf descendants of the given cell index, then cleans up ancestors.
    func deleteLeavesInCell(h3Index: UInt64) throws {
        let cell = H3Cell(h3Index)
        guard let resolution = try? cell.resolution else { return }
        guard let leafResolution = H3Cell.Resolution(rawValue: Int32(Self.maxResolution)) else { return }

        if Int(resolution.rawValue) >= Self.maxResolution {
            // The selected cell is itself a leaf — delete it directly.
            try db.write { db in
                try Self.deleteLeaf(cell, in: db)
            }
            return
        }

        // For higher-level cells, enumerate only the *visited* leaf rows in the
        // DB, then filter to those that are actually descendants of `cell`.
        // This avoids materialising the (potentially millions of) H3 leaf
        // descendants when only a small fraction have been visited.
        let ancestorResolution = resolution

        try db.write { [leafResolution] db in
            let sql = "SELECT * FROM visitedCell WHERE (h3Index >> 52) & 0xF = ?"
            let leafRes = Int64(leafResolution.rawValue)
            let visitedLeaves = try VisitedCell.fetchAll(db, sql: sql, arguments: [leafRes])

            for row in visitedLeaves {
                let leafCell = H3Cell(row.h3Index)
                // Check if this leaf's ancestor at the target resolution matches.
                guard let ancestor = try? leafCell.parent(at: ancestorResolution),
                      ancestor.id == cell.id else { continue }
                try Self.deleteLeaf(leafCell, in: db)
            }
        }
    }

    /// Deletes all res-13 leaf cells within the visible region, then walks each
    /// leaf's parent chain: decrements visitedChildren/visitedLeaves and deletes
    /// the ancestor row as soon as visitedChildren reaches 0.
    func deleteVisible(in region: MKCoordinateRegion) throws {
        let lat  = region.center.latitude
        let lng  = region.center.longitude
        let dLat = region.span.latitudeDelta  / 2
        let dLng = region.span.longitudeDelta / 2

        // 1. Find all res-13 leaf cells in the visible area.
        let polygon = H3Polygon([
            H3LatLng(latitudeDegs: lat + dLat, longitudeDegs: lng - dLng),
            H3LatLng(latitudeDegs: lat + dLat, longitudeDegs: lng + dLng),
            H3LatLng(latitudeDegs: lat - dLat, longitudeDegs: lng + dLng),
            H3LatLng(latitudeDegs: lat - dLat, longitudeDegs: lng - dLng),
        ])
        guard let leafResolution = H3Cell.Resolution(rawValue: Int32(Self.maxResolution)),
              let leafCells = try? polygon.cells(at: leafResolution),
              !leafCells.isEmpty else { return }

        try db.write { db in
            for leafCell in leafCells {
                try Self.deleteLeaf(leafCell, in: db)
            }
        }
    }

    /// Deletes a single res-13 leaf row, then walks up the parent chain:
    /// decrements visitedChildren and visitedLeaves on each ancestor, deleting
    /// the ancestor row when its visitedChildren count reaches 0.
    private static func deleteLeaf(_ leafCell: H3Cell, in db: Database) throws {
        let leafKey = ["h3Index": Int64(bitPattern: leafCell.id)]

        // If this leaf isn't in the DB, nothing to do.
        guard try VisitedCell.fetchOne(db, key: leafKey) != nil else { return }
        try VisitedCell.deleteOne(db, key: leafKey)

        var childWasDeleted = true
        var cell: H3Cell? = try? leafCell.parent()

        while let current = cell {
            let key = ["h3Index": Int64(bitPattern: current.id)]
            guard var row = try VisitedCell.fetchOne(db, key: key) else { break }

            if childWasDeleted {
                row.visitedChildren -= 1
            }
            row.visitedLeaves -= 1

            if row.visitedChildren <= 0 {
                try VisitedCell.deleteOne(db, key: key)
                childWasDeleted = true
            } else {
                try row.update(db)
                childWasDeleted = false
            }

            cell = try? current.parent()
        }
    }

    /// Creates a temporary copy of the database suitable for sharing.
    func exportDatabase() throws -> URL {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("visited-export.sqlite")
        try? FileManager.default.removeItem(at: tempURL)
        _ = try db.backup(to: DatabaseQueue(path: tempURL.path))
        return tempURL
    }

    /// Replaces the current database contents with the contents of the imported file.
    func importDatabase(from sourceURL: URL) throws {
        print("importing db")
        // Copy the file into the app's temp sandbox first. SQLite's C-level file
        // operations cannot use a security-scoped URL directly, even after
        // startAccessingSecurityScopedResource() is called.
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("hexplorer-import-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: tempURL) }
        try FileManager.default.copyItem(at: sourceURL, to: tempURL)

        let sourceDB = try DatabaseQueue(path: tempURL.path)
        try db.barrierWriteWithoutTransaction { db in
            try db.execute(sql: "DELETE FROM visitedCell")
            try db.execute(sql: "DELETE FROM flag")
        }
        try sourceDB.backup(to: db)
        print("import db done")
    }

    func visitedCells(among ids: Set<UInt64>) -> [UInt64: VisitedCell] {
        guard !ids.isEmpty else { return [:] }
        do {
            return try db.read { db in
                let placeholders = databaseQuestionMarks(count: ids.count)
                let sql = "SELECT * FROM visitedCell WHERE h3Index IN (\(placeholders))"
                let arguments = StatementArguments(ids.map { DatabaseValue(value: Int64(bitPattern: $0)) })
                let rows = try VisitedCell.fetchAll(db, sql: sql, arguments: arguments)
                return Dictionary(uniqueKeysWithValues: rows.map { ($0.h3Index, $0) })
            }
        } catch {
            print("CellStore query error: \(error)")
            return [:]
        }
    }

    // MARK: - Private

    private static func recordVisit(
        in db: Database,
        latLng: H3LatLng,
        now: Date,
        leafResolution: H3Cell.Resolution
    ) throws {
        guard let leafCell = try? latLng.cell(at: leafResolution) else { return }

        // 1. Walk the parent chain to collect all cell IDs.
        var chain: [H3Cell] = []
        var cell: H3Cell? = leafCell
        while let current = cell {
            chain.append(current)
            cell = try? current.parent()
        }

        // 2. Single SELECT to fetch all existing rows.
        let ids = chain.map { Int64(bitPattern: $0.id) }
        let placeholders = databaseQuestionMarks(count: ids.count)
        let sql = "SELECT * FROM visitedCell WHERE h3Index IN (\(placeholders))"
        let rows = try VisitedCell.fetchAll(db, sql: sql, arguments: StatementArguments(ids))
        let existingMap = Dictionary(uniqueKeysWithValues: rows.map { ($0.h3Index, $0) })

        // 3. Walk the chain and upsert using in-memory lookup.
        var leafIsNew = false
        var childIsNew = false

        for current in chain {
            let isLeaf = current == leafCell
            if var existing = existingMap[current.id] {
                let countVisit = now.timeIntervalSince(existing.lastVisitedAt) > 60
                if !countVisit && !childIsNew && !leafIsNew { return }
                if countVisit { existing.visitCount += 1 }
                existing.lastVisitedAt = now
                if isLeaf {
                    existing.visitedChildren = 7
                } else if childIsNew {
                    existing.visitedChildren += 1
                }
                if leafIsNew { existing.visitedLeaves += 1 }
                try existing.update(db)
                childIsNew = false
            } else {
                try VisitedCell(
                    h3Index: current.id,
                    firstVisitedAt: now,
                    lastVisitedAt: now,
                    visitCount: 1,
                    visitedChildren: childIsNew ? 1 : 0,
                    visitedLeaves: leafIsNew ? 1 : 0
                ).insert(db)
                childIsNew = true
                if isLeaf { leafIsNew = true }
            }
        }
    }
}
