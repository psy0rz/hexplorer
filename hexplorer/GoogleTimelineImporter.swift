import Foundation

/// A location from a Google Timeline export, with the time that Google gives for it.
nonisolated struct TimelineLocation: Sendable {
    let latitude: Double
    let longitude: Double
    let visitedAt: Date
}

/// Imports the location history that Google Maps exports from the phone:
/// - `Timeline.json` from Android (an object with `semanticSegments` and `rawSignals`)
/// - `location-history.json` from iOS (an array of segments)
@MainActor
@Observable
final class GoogleTimelineImporter {
    static let shared = GoogleTimelineImporter()

    private(set) var isImporting = false
    private(set) var recordedLocationCount = 0
    private(set) var totalLocationCount = 0

    /// The number of locations in one write transaction, so the progress can update between transactions.
    private static let locationsPerWriteBatch = 1_000

    private init() {}

    /// Reads the export file and records all locations in it. Returns the number of new res-13 cells.
    func importTimeline(from fileURL: URL) async throws -> Int {
        isImporting = true
        recordedLocationCount = 0
        totalLocationCount = 0
        defer { isImporting = false }

        let locations = try await Task.detached(priority: .userInitiated) {
            try GoogleTimelineParser.readLocations(from: fileURL)
        }.value
        totalLocationCount = locations.count

        let cellStore = CellStore.shared
        var newLeafCellCount = 0
        var batchStartIndex = 0
        while batchStartIndex < locations.count {
            let batchEndIndex = min(batchStartIndex + Self.locationsPerWriteBatch, locations.count)
            let visitBatch = locations[batchStartIndex..<batchEndIndex].map {
                (latitude: $0.latitude, longitude: $0.longitude, visitedAt: $0.visitedAt)
            }
            let batchNewLeafCellIDs = try await Task.detached(priority: .userInitiated) {
                try cellStore.recordVisits(locations: visitBatch)
            }.value
            newLeafCellCount += batchNewLeafCellIDs.count
            recordedLocationCount = batchEndIndex
            batchStartIndex = batchEndIndex
        }
        return newLeafCellCount
    }
}

enum GoogleTimelineImportError: LocalizedError {
    case unknownFileFormat

    var errorDescription: String? {
        switch self {
        case .unknownFileFormat:
            "The file is not a Google Timeline export (Timeline.json or location-history.json)."
        }
    }
}

/// Reads the locations from the two Google Timeline export formats.
nonisolated enum GoogleTimelineParser {
    /// Raw position signals with a larger accuracy radius than this are not used.
    /// Cell tower positions can be wrong by kilometers.
    static let maximumRawSignalAccuracyMeters = 50.0

    /// Returns all locations in the file, oldest first.
    static func readLocations(from fileURL: URL) throws -> [TimelineLocation] {
        let fileData = try Data(contentsOf: fileURL, options: .mappedIfSafe)
        let decoder = JSONDecoder()
        let dateParser = GoogleDateParser()
        var locations: [TimelineLocation]

        // Android gives an object, iOS gives an array.
        switch firstNonWhitespaceByte(in: fileData) {
        case UInt8(ascii: "{"):
            let androidTimeline = try decoder.decode(AndroidTimelineFile.self, from: fileData)
            locations = androidLocations(in: androidTimeline, dateParser: dateParser)
        case UInt8(ascii: "["):
            let iPhoneSegments = try decoder.decode([IPhoneTimelineSegment].self, from: fileData)
            locations = iPhoneLocations(in: iPhoneSegments, dateParser: dateParser)
        default:
            throw GoogleTimelineImportError.unknownFileFormat
        }

        // In time order, so each visit after the first one can increment the visit count.
        locations.sort { $0.visitedAt < $1.visitedAt }
        return locations
    }

    // MARK: - Android Timeline.json

    private static func androidLocations(in androidTimeline: AndroidTimelineFile, dateParser: GoogleDateParser) -> [TimelineLocation] {
        var locations: [TimelineLocation] = []

        func appendLocation(coordinateText: String?, timeText: String?) {
            guard let coordinateText, let timeText,
                  let coordinate = coordinate(fromGoogleText: coordinateText),
                  let visitedAt = dateParser.date(from: timeText) else { return }
            locations.append(TimelineLocation(latitude: coordinate.latitude, longitude: coordinate.longitude, visitedAt: visitedAt))
        }

        for segment in androidTimeline.semanticSegments ?? [] {
            for pathPoint in segment.timelinePath ?? [] {
                appendLocation(coordinateText: pathPoint.point, timeText: pathPoint.time)
            }
            if let placeCoordinateText = segment.visit?.topCandidate?.placeLocation?.latLng {
                appendLocation(coordinateText: placeCoordinateText, timeText: segment.startTime)
                appendLocation(coordinateText: placeCoordinateText, timeText: segment.endTime)
            }
            if let activity = segment.activity {
                appendLocation(coordinateText: activity.start?.latLng, timeText: segment.startTime)
                appendLocation(coordinateText: activity.end?.latLng, timeText: segment.endTime)
            }
        }

        for rawSignal in androidTimeline.rawSignals ?? [] {
            guard let position = rawSignal.position else { continue }
            if let accuracyMeters = position.accuracyMeters?.value,
               accuracyMeters > maximumRawSignalAccuracyMeters { continue }
            appendLocation(coordinateText: position.LatLng ?? position.latLng, timeText: position.timestamp)
        }
        return locations
    }

    // MARK: - iOS location-history.json

    private static func iPhoneLocations(in iPhoneSegments: [IPhoneTimelineSegment], dateParser: GoogleDateParser) -> [TimelineLocation] {
        var locations: [TimelineLocation] = []

        func appendLocation(coordinateText: String?, visitedAt: Date?) {
            guard let coordinateText, let visitedAt,
                  let coordinate = coordinate(fromGoogleText: coordinateText) else { return }
            locations.append(TimelineLocation(latitude: coordinate.latitude, longitude: coordinate.longitude, visitedAt: visitedAt))
        }

        for segment in iPhoneSegments {
            let segmentStartTime = segment.startTime.flatMap(dateParser.date(from:))
            let segmentEndTime = segment.endTime.flatMap(dateParser.date(from:))

            for pathPoint in segment.timelinePath ?? [] {
                // A path point has no time of its own, only an offset in minutes from the start of the segment.
                guard let segmentStartTime else { break }
                let offsetMinutes = pathPoint.durationMinutesOffsetFromStartTime?.value ?? 0
                appendLocation(coordinateText: pathPoint.point,
                               visitedAt: segmentStartTime.addingTimeInterval(offsetMinutes * 60))
            }
            if let placeCoordinateText = segment.visit?.topCandidate?.placeLocation {
                appendLocation(coordinateText: placeCoordinateText, visitedAt: segmentStartTime)
                appendLocation(coordinateText: placeCoordinateText, visitedAt: segmentEndTime)
            }
            if let activity = segment.activity {
                appendLocation(coordinateText: activity.start, visitedAt: segmentStartTime)
                appendLocation(coordinateText: activity.end, visitedAt: segmentEndTime)
            }
        }
        return locations
    }

    // MARK: - Helpers

    /// Reads a Google coordinate text. Android uses `"52.0123456°, 4.0123456°"`, iOS uses `"geo:52.012345,4.012345"`.
    static func coordinate(fromGoogleText coordinateText: String) -> (latitude: Double, longitude: Double)? {
        let numbersText = coordinateText
            .replacingOccurrences(of: "geo:", with: "")
            .replacingOccurrences(of: "°", with: "")
        let numberTexts = numbersText.split(separator: ",")
        guard numberTexts.count == 2,
              let latitude = Double(numberTexts[0].trimmingCharacters(in: .whitespaces)),
              let longitude = Double(numberTexts[1].trimmingCharacters(in: .whitespaces)),
              (-90...90).contains(latitude),
              (-180...180).contains(longitude) else { return nil }
        return (latitude, longitude)
    }

    private static func firstNonWhitespaceByte(in fileData: Data) -> UInt8? {
        fileData.first { !" \t\r\n".utf8.contains($0) && $0 != 0xEF && $0 != 0xBB && $0 != 0xBF }
    }
}

/// Parses the ISO 8601 times in the exports. Some times have fractional seconds and some do not.
private nonisolated struct GoogleDateParser {
    private let fractionalSecondsFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    private let wholeSecondsFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    func date(from timeText: String) -> Date? {
        fractionalSecondsFormatter.date(from: timeText) ?? wholeSecondsFormatter.date(from: timeText)
    }
}

/// A number that the export can write as a JSON number or as a JSON string.
private nonisolated struct NumberOrNumberText: Decodable {
    let value: Double?

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let number = try? container.decode(Double.self) {
            value = number
        } else if let numberText = try? container.decode(String.self) {
            value = Double(numberText)
        } else {
            value = nil
        }
    }
}

// MARK: - Android Timeline.json format

private nonisolated struct AndroidTimelineFile: Decodable {
    let semanticSegments: [Segment]?
    let rawSignals: [RawSignal]?

    struct Segment: Decodable {
        let startTime: String?
        let endTime: String?
        let timelinePath: [PathPoint]?
        let visit: Visit?
        let activity: Activity?
    }

    struct PathPoint: Decodable {
        let point: String?
        let time: String?
    }

    struct Visit: Decodable {
        let topCandidate: Candidate?

        struct Candidate: Decodable {
            let placeLocation: PlaceLocation?
        }

        struct PlaceLocation: Decodable {
            let latLng: String?
        }
    }

    struct Activity: Decodable {
        let start: Endpoint?
        let end: Endpoint?

        struct Endpoint: Decodable {
            let latLng: String?
        }
    }

    struct RawSignal: Decodable {
        let position: Position?

        struct Position: Decodable {
            // The export writes "LatLng" with a capital L.
            let LatLng: String?
            let latLng: String?
            let accuracyMeters: NumberOrNumberText?
            let timestamp: String?
        }
    }
}

// MARK: - iOS location-history.json format

private nonisolated struct IPhoneTimelineSegment: Decodable {
    let startTime: String?
    let endTime: String?
    let visit: Visit?
    let activity: Activity?
    let timelinePath: [PathPoint]?

    struct Visit: Decodable {
        let topCandidate: Candidate?

        struct Candidate: Decodable {
            let placeLocation: String?
        }
    }

    struct Activity: Decodable {
        let start: String?
        let end: String?
    }

    struct PathPoint: Decodable {
        let point: String?
        let durationMinutesOffsetFromStartTime: NumberOrNumberText?
    }
}
