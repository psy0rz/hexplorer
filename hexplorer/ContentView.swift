import SwiftUI
import MapKit
import SwiftyH3
import UniformTypeIdentifiers

private enum ActivePanel: Equatable {
    case flagEditor(MapFlag?)   // nil = new flag, non-nil = editing existing
    case filterOptions
    case mapLayers
}

/// The kind of file that the file importer opens.
private enum FileImportKind {
    case database
    case googleTimeline

    var allowedContentTypes: [UTType] {
        switch self {
        case .database: [UTType.database, .data]
        case .googleTimeline: [.json]
        }
    }
}

struct ContentView: View {
    @State private var mapView: MKMapView?
    @State private var showImportPicker = false
    @State private var fileImportKind: FileImportKind = .database
    @State private var googleTimelineImportMessage: String?
    @State private var showExportPicker = false
    @State private var exportDocument: DatabaseDocument?
    @State private var showGenerateConfirmation = false
    @State private var showGenerateFlagsConfirmation = false
    @State private var activePanel: ActivePanel? = nil
    @State private var trackingToastIsShown = false
    @Environment(\.scenePhase) private var scenePhase

    /// The icon frame of the round buttons at the bottom, so all three buttons have the same size.
    private static let bottomButtonIconSize: CGFloat = 22

    private var tracker = LocationTracker.shared
    private var selectedCell = SelectedCellState.shared
    private var filterState = FilterState.shared
    private var mapLayerSettings = MapLayerSettings.shared
    private var googleTimelineImporter = GoogleTimelineImporter.shared

    var body: some View {
        ZStack {
            MapView(
                onMapViewCreated: { createdMapView in
                    self.mapView = createdMapView
                    createdMapView.syncFlagAnnotations()
                },
                onMapLayersButtonTap: {
                    activePanel = activePanel == .mapLayers ? nil : .mapLayers
                },
                onFlagTap: { tappedFlag in
                    activePanel = .flagEditor(tappedFlag)
                    // Deselect cell so only the flag panel shows.
                    selectedCell.clear()
                }
            )
            .edgesIgnoringSafeArea(.all)

            if let mapView {
                HexagonHighlightView(mapView: mapView)
                    .edgesIgnoringSafeArea(.all)
            }


            VStack {
                Spacer()
                // One container, so SwiftUI renders the glass of the three buttons together.
                GlassEffectContainer {
                    HStack(spacing: 16) {
                        ////tracking button
                        Button(action: toggleTracking) {
                            // The icon shows the state: a location arrow while tracking, a crossed-out one when not.
                            Image(systemName: tracker.isTracking ? "location.fill" : "location.slash.fill")
                                .contentTransition(.symbolEffect(.replace))
                                .font(.headline)
                                .frame(width: Self.bottomButtonIconSize, height: Self.bottomButtonIconSize)
                                .padding()
                                .foregroundStyle(.white)
                                .glassEffect(.regular.tint(tracker.isTracking ? .red : .green).interactive(), in: .circle)
                        }
                        .accessibilityLabel(tracker.isTracking ? "Stop tracking" : "Start tracking")
                        .sensoryFeedback(trigger: tracker.isTracking) { _, isTrackingNow in
                            isTrackingNow ? .start : .stop
                        }
                        ////filter options
                        Button(action: { activePanel = activePanel == .filterOptions ? nil : .filterOptions }) {
                            // The active display mode, so it is clear what the map colors mean.
                            Image(systemName: filterState.mode.systemImage)
                                .font(.headline)
                                // Same size for each icon, so the button does not change width with the mode.
                                .frame(width: Self.bottomButtonIconSize, height: Self.bottomButtonIconSize)
                                .padding()
                                // The app tint color, the same as the icons of the map controls in MapView.
                                .foregroundStyle(.tint)
                                .glassEffect(.regular.interactive(), in: .circle)
                        }
                        .accessibilityLabel("Display mode: \(filterState.mode.rawValue)")
                        ////menu
                        Menu {
                            Button(action: exportDatabase) {
                                Label("Export Database", systemImage: "square.and.arrow.up")
                            }
                            Button(action: {
                                fileImportKind = .database
                                showImportPicker = true
                            }) {
                                Label("Import Database", systemImage: "square.and.arrow.down")
                            }
                            Button(action: {
                                fileImportKind = .googleTimeline
                                showImportPicker = true
                            }) {
                                Label("Import Google Timeline", systemImage: "clock.arrow.circlepath")
                            }
                            .disabled(googleTimelineImporter.isImporting)
//                            Button(action: { showGenerateConfirmation = true }) {
//                                Label("Generate Test Visits", systemImage: "dice")
//                            }
//                            Button(action: { showGenerateFlagsConfirmation = true }) {
//                                Label("Generate Test Flags", systemImage: "flag")
//                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                                .font(.headline)
                                .frame(width: Self.bottomButtonIconSize, height: Self.bottomButtonIconSize)
                                .padding()
                                // The app tint color, the same as the icons of the map controls in MapView.
                                .foregroundStyle(.tint)
                                .glassEffect(.regular.interactive(), in: .circle)
                        }
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
                            if let mapView { VisitedHexagonOverlays.shared.reloadHexagons(on: mapView) }
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
                                if let mapView { mapView.refreshFlagAnnotation(id: id) }
                            } else {
                                if let mapView { mapView.syncFlagAnnotations() }
                            }
                            activePanel = nil
                        },
                        onCancel: {
                            activePanel = nil
                        },
                        onDelete: {
                            if let mapView { mapView.syncFlagAnnotations() }
                            activePanel = nil
                        }
                    )
                    .id(flag?.id)
                } else if activePanel == .filterOptions {
                    FilterOptionsPanel(filter: filterState, onClose: { activePanel = nil })
                } else if activePanel == .mapLayers {
                    MapLayersPanel(settings: mapLayerSettings, onClose: { activePanel = nil })
                }
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: selectedCell.selectedCellIndex != nil)
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: activePanel != nil)
            .allowsHitTesting(selectedCell.selectedCellIndex != nil || activePanel != nil)

            // While tracking, a pill at the top left with the number of new cells in this session.
            if tracker.isTracking {
                HStack(spacing: 6) {
                    Circle()
                        .fill(.red)
                        .frame(width: 8, height: 8)
                    Text("Tracking · \(tracker.sessionNewCellCount) new cells")
                        .contentTransition(.numericText())
                }
                .font(.footnote.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .glassEffect(.regular, in: .capsule)
                .animation(.default, value: tracker.sessionNewCellCount)
                .accessibilityElement(children: .combine)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                // The same height as the map controls at the top right of MapView.
                .padding(.top, 60)
                .padding(.leading, 10)
                .transition(.opacity)
                .allowsHitTesting(false)
            }

            // While a Google Timeline import runs, a pill at the top with the progress.
            if googleTimelineImporter.isImporting {
                HStack(spacing: 8) {
                    ProgressView()
                    if googleTimelineImporter.totalLocationCount == 0 {
                        Text("Reading Google Timeline…")
                    } else {
                        Text("Importing \(googleTimelineImporter.recordedLocationCount) of \(googleTimelineImporter.totalLocationCount) locations")
                            .contentTransition(.numericText())
                    }
                }
                .font(.footnote.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .glassEffect(.regular, in: .capsule)
                .frame(maxHeight: .infinity, alignment: .top)
                .padding(.top, 8)
                .transition(.opacity)
                .allowsHitTesting(false)
            }

            // A short message at the top after the user turns tracking on or off.
            if trackingToastIsShown {
                Label(tracker.isTracking ? "Tracking On" : "Tracking Off",
                      systemImage: tracker.isTracking ? "location.fill" : "location.slash.fill")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .glassEffect(.regular, in: .capsule)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .allowsHitTesting(false)
            }
        }
        .onChange(of: selectedCell.selectedCellIndex) { _, newVal in
            // Dismiss flag editor if the user taps a cell (not a flag callout).
            if newVal != nil { activePanel = nil }
        }
        // Each tap changes isTracking and so restarts this task: the message stays 2 s after the last tap.
        // A restart cancels the old sleep; the guard then stops the old task before it hides the message.
        .task(id: tracker.isTracking) {
            guard (try? await Task.sleep(for: .seconds(2))) != nil else { return }
            withAnimation { trackingToastIsShown = false }
        }
        .onChange(of: tracker.flushCount) {
            // When the app is not active, nobody sees the map. The reload on activation shows the new cells.
            guard scenePhase == .active else { return }
            if let mapView { VisitedHexagonOverlays.shared.reloadHexagons(on: mapView) }
            // New visits can change the trail.
            updateRepeatedFlashing()
        }
        .onChange(of: scenePhase, initial: true) { _, newScenePhase in
            let isAppActive = newScenePhase == .active
            tracker.isAppActive = isAppActive
            // Setting isAppActive flushes the buffer, so the reload includes all visits.
            if isAppActive, let mapView { VisitedHexagonOverlays.shared.reloadHexagons(on: mapView) }
            updateRepeatedFlashing()
        }
        .onChange(of: mapView)                             { updateRepeatedFlashing() }
        .onChange(of: selectedCell.selectedCellIndex)      { updateRepeatedFlashing(restartsForNewSelection: true) }
        .onChange(of: selectedCell.currentZoomResolution)  { updateRepeatedFlashing() }
        .onChange(of: mapLayerSettings.mapStyle)             { applyMapLayerSettings() }
        .onChange(of: mapLayerSettings.showsSatelliteLabels)  { applyMapLayerSettings() }
        .onChange(of: mapLayerSettings.showsPointsOfInterest) { applyMapLayerSettings() }
        .onChange(of: filterState.mode)                  { if let mapView { VisitedHexagonOverlays.shared.reloadHexagons(on: mapView) } }
        .onChange(of: filterState.thresholdStopIndices)   { if let mapView { VisitedHexagonOverlays.shared.reloadHexagons(on: mapView) } }
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
            switch fileImportKind {
            case .database: importDatabase(result: result)
            case .googleTimeline: importGoogleTimeline(result: result)
            }
        }
        .alert(
            "Google Timeline Import",
            isPresented: Binding(
                get: { googleTimelineImportMessage != nil },
                set: { isPresented in if !isPresented { googleTimelineImportMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(googleTimelineImportMessage ?? "")
        }
    }

    /// Sends the pattern that must repeat now to the flasher:
    /// - with a selected cell: that cell with the 5 cells visited just before and just after it, in white.
    ///   An unvisited cell has no visit time, so nothing flashes.
    /// - without a selected cell: the trail of the 5 cells visited last, at the resolution the map shows now, in blue.
    /// The flasher ignores a pattern that did not change, so this can run at each change of the data.
    /// When `restartsForNewSelection` is true and a cell is selected, the pattern of that cell starts at once,
    /// so a tap on a cell shows its pattern directly. In all other cases, the new pattern waits for the current run.
    private func updateRepeatedFlashing(restartsForNewSelection: Bool = false) {
        // When the app is not active, nobody sees the map.
        guard scenePhase == .active else {
            CellFlasher.shared.stopRepeatedFlashing()
            return
        }
        if selectedCell.selectedCellIndex != nil {
            let cellsInVisitOrder = selectedCell.selectedCellInfo.map {
                CellStore.shared.cellsVisitedAround($0, count: 5)
            } ?? []
            CellFlasher.shared.repeatFlashing(cells: cellsInVisitOrder.map { H3Cell($0.h3Index) },
                                              color: .white,
                                              restartsCurrentRun: restartsForNewSelection)
        } else {
            let trailCellsInVisitOrder = CellStore.shared.cellsVisitedLast(
                atResolution: selectedCell.currentZoomResolution, count: 5)
            CellFlasher.shared.repeatFlashing(cells: trailCellsInVisitOrder.map { H3Cell($0.h3Index) },
                                              color: .systemBlue)
        }
    }

    private func applyMapLayerSettings() {
        mapView?.preferredConfiguration = mapLayerSettings.makeMapConfiguration()
    }

    private func toggleTracking() {
        if tracker.isTracking {
            tracker.stopTracking()
        } else {
            tracker.startTracking()
        }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            trackingToastIsShown = true
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
                VisitedHexagonOverlays.shared.reloadHexagons(on: mapView)
                mapView.syncFlagAnnotations()
            }
        } catch {
            print("Failed to import database: \(error)")
        }
    }

    private func importGoogleTimeline(result: Result<[URL], Error>) {
        guard let url = try? result.get().first else { return }
        Task {
            guard url.startAccessingSecurityScopedResource() else { return }
            defer { url.stopAccessingSecurityScopedResource() }
            do {
                let newLeafCellCount = try await googleTimelineImporter.importTimeline(from: url)
                googleTimelineImportMessage = "Imported \(googleTimelineImporter.totalLocationCount) locations with \(newLeafCellCount) new cells."
            } catch {
                print("Failed to import Google Timeline: \(error)")
                googleTimelineImportMessage = "The import failed: \(error.localizedDescription)"
            }
            if let mapView { VisitedHexagonOverlays.shared.reloadHexagons(on: mapView) }
            updateRepeatedFlashing()
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
            VisitedHexagonOverlays.shared.reloadHexagons(on: mapView)
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
        mapView.syncFlagAnnotations()
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
