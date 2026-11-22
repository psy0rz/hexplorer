import SwiftUI
import MapKit
import SwiftyH3
import UniformTypeIdentifiers

private enum ActivePanel: Equatable {
    case flagEditor(MapFlag?)   // nil = new flag, non-nil = editing existing
    case filterOptions
}

struct ContentView: View {
//    private static let initialRegion = MKCoordinateRegion(
//        center: CLLocationCoordinate2D(latitude: 52.7, longitude: 6.8),
//        span: MKCoordinateSpan(latitudeDelta: 1, longitudeDelta: 1)
//    )

    @State private var mapView: MKMapView?
    @State private var showImportPicker = false
    @State private var showExportPicker = false
    @State private var exportDocument: DatabaseDocument?
    @State private var showGenerateConfirmation = false
    @State private var showGenerateFlagsConfirmation = false
    @State private var activePanel: ActivePanel? = nil

    private var tracker = LocationTracker.shared
    private var selectedCell = SelectedCellState.shared
    private var filterState = FilterState.shared

//    private var currentH3Resolution: Int {
//        let lat = mapView?.centerCoordinate.latitude ?? Self.initialRegion.center.latitude
//        return Int(h3Resolution(for: MKZoomScale(zoomScale), latitude: lat).rawValue)
//    }

    var body: some View {
        ZStack {
            MapView(
//                region: Self.initialRegion,
                onMapViewCreated: { mv in
                    self.mapView = mv
                    syncFlagAnnotations(on: mv)
                    mv.delegate.flatMap { $0 as? MapView.Coordinator }?.onFlagEdit = { flag in
                        activePanel = .flagEditor(flag)
                        // Deselect cell so only the flag panel shows.
                        selectedCell.clear()
                    }
                }
            )
            .edgesIgnoringSafeArea(.all)

            if let mapView {
                HexagonHighlightView(mapView: mapView)
                    .edgesIgnoringSafeArea(.all)
            }

            VStack {
                Spacer()
                HStack(spacing: 16) {
                    Button(action: toggleTracking) {
                        HStack {
                            Image(systemName: tracker.isTracking ? "location.fill" : "location")
                            Text(tracker.isTracking ? "Stop" : "Track")
                        }
                        .font(.headline)
                        .padding()
                        .background(tracker.isTracking ? .red : .green)
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                    }
                    Button(action: { activePanel = activePanel == .filterOptions ? nil : .filterOptions }) {
                        Image(systemName: "slider.horizontal.3")
                            .font(.headline)
                            .padding()
                            .background(activePanel == .filterOptions ? Color.blue : .secondary.opacity(0.8))
                            .foregroundStyle(.white)
                            .clipShape(Capsule())
                    }
                    Menu {
                        Button(action: exportDatabase) {
                            Label("Export Database", systemImage: "square.and.arrow.up")
                        }
                        Button(action: { showImportPicker = true }) {
                            Label("Import Database", systemImage: "square.and.arrow.down")
                        }
//                        Button(action: { showGenerateConfirmation = true }) {
//                            Label("Generate Test Visits", systemImage: "dice")
//                        }
//                        Button(action: { showGenerateFlagsConfirmation = true }) {
//                            Label("Generate Test Flags", systemImage: "flag")
//                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.headline)
                            .padding()
                            .background(.secondary.opacity(0.8))
                            .foregroundStyle(.white)
                            .clipShape(Capsule())
                    }
                }
                .confirmationDialog(
                    "Generate 10,000 random test visits in the current map area?",
                    isPresented: $showGenerateConfirmation,
                    titleVisibility: .visible
                ) {
                    Button("Generate", role: .destructive, action: generateTestVisits)
                }
                .confirmationDialog(
                    "Generate 100 random test flags in the current map area?",
                    isPresented: $showGenerateFlagsConfirmation,
                    titleVisibility: .visible
                ) {
                    Button("Generate", role: .destructive, action: generateTestFlags)
                }
                .padding(.bottom, 40)
            }

            // Bottom panel — cell info or flag editor, never both.
            VStack {
                Spacer()
                if selectedCell.selectedCellIndex != nil, activePanel == nil {
                    CellInfoPanel(
                        state: selectedCell,
                        onDelete: {
                            if let mapView { refreshHexagonOverlay(on: mapView) }
                        },
                        onAddFlag: {
                            activePanel = .flagEditor(nil)
                        }
                    )
                } else if case .flagEditor(let flag) = activePanel {
                    FlagEditorPanel(
                        existingFlag: flag,
                        coordinate: selectedCell.tappedCoordinate,
                        onSave: { id in
                            if let id {
                                if let mapView { refreshFlagAnnotation(id: id, on: mapView) }
                            } else {
                                if let mapView { syncFlagAnnotations(on: mapView) }
                            }
                            activePanel = nil
                        },
                        onCancel: {
                            activePanel = nil
                        },
                        onDelete: {
                            if let mapView { syncFlagAnnotations(on: mapView) }
                            activePanel = nil
                        }
                    )
                    .id(flag?.id)
                } else if activePanel == .filterOptions {
                    FilterOptionsPanel(filter: filterState, onClose: { activePanel = nil })
                }
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: selectedCell.selectedCellIndex != nil)
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: activePanel != nil)
            .allowsHitTesting(selectedCell.selectedCellIndex != nil || activePanel != nil)
        }
        .onChange(of: selectedCell.selectedCellIndex) { _, newVal in
            // Dismiss flag editor if the user taps a cell (not a flag callout).
            if newVal != nil { activePanel = nil }
        }
        .onChange(of: tracker.flushCount) {
            if let mapView { refreshHexagonOverlay(on: mapView) }
        }
        .onChange(of: filterState.mode)                  { if let mapView { refreshHexagonOverlay(on: mapView) } }
        .onChange(of: filterState.thresholdStopIndices)   { if let mapView { refreshHexagonOverlay(on: mapView) } }
        .fileExporter(
            isPresented: $showExportPicker,
            document: exportDocument,
            contentType: .data,
            defaultFilename: "visited.sqlite"
        ) { _ in
            exportDocument = nil
        }
        .fileImporter(
            isPresented: $showImportPicker,
            allowedContentTypes: [UTType.database, .data],
            allowsMultipleSelection: false
        ) { result in
            importDatabase(result: result)
        }
    }

    private func toggleTracking() {
        if tracker.isTracking {
            tracker.stopTracking()
        } else {
            tracker.startTracking()
        }
    }

    private func exportDatabase() {
        do {
            let url = try CellStore.shared.exportDatabase()
            exportDocument = DatabaseDocument(url: url)
            showExportPicker = true
        } catch {
            print("Failed to export database: \(error)")
        }
    }

    private func importDatabase(result: Result<[URL], Error>) {
        do {
            let urls = try result.get()
            guard let url = urls.first else { return }
            guard url.startAccessingSecurityScopedResource() else { return }
            defer { url.stopAccessingSecurityScopedResource() }
            try CellStore.shared.importDatabase(from: url)
            FlagStore.shared.load()
            if let mapView {
                refreshHexagonOverlay(on: mapView)
                syncFlagAnnotations(on: mapView)
            }
        } catch {
            print("Failed to import database: \(error)")
        }
    }

    private func generateTestVisits() {
        guard let mapView else { return }
        let region = mapView.region
        do {
            try CellStore.shared.generateTestVisits(
                centerLatitude: region.center.latitude,
                centerLongitude: region.center.longitude,
                latDelta: region.span.latitudeDelta,
                lngDelta: region.span.longitudeDelta
            )
            refreshHexagonOverlay(on: mapView)
        } catch {
            print("Failed to generate test visits: \(error)")
        }
    }

    private func generateTestFlags() {
        guard let mapView else { return }
        let region = mapView.region
        let colors = FlagColor.allCases
        let priorities = FlagPriority.allCases
        for i in 1...1000 {
            let lat = region.center.latitude + Double.random(in: -region.span.latitudeDelta / 2 ... region.span.latitudeDelta / 2)
            let lng = region.center.longitude + Double.random(in: -region.span.longitudeDelta / 2 ... region.span.longitudeDelta / 2)
            let coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lng)
            FlagStore.shared.addFlag(
                at: coordinate,
                label: "Test \(i)",
                color: colors.randomElement()!,
                priority: priorities.randomElement()!
            )
        }
        syncFlagAnnotations(on: mapView)
    }


}


/// A simple FileDocument wrapper for exporting the SQLite database.
struct DatabaseDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.data] }

    let data: Data

    init(url: URL) {
        self.data = (try? Data(contentsOf: url)) ?? Data()
    }

    init(configuration: ReadConfiguration) throws {
        self.data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}


#Preview {
    ContentView()
}
