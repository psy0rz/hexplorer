import SwiftUI
import SwiftyH3

struct CellInfoPanel: View {
    let state: SelectedCellState
    var onDelete: (() -> Void)? = nil
    var onAddFlag: (() -> Void)? = nil

    @State private var showDeleteConfirmation = false

    private var info: VisitedCell? { state.selectedCellInfo }
    private var resolution: Int { state.selectedCellResolution }

    private static let edgeLengthKm: [Double] = [
        1107.71, 418.68, 158.24, 59.81, 22.61, 8.54,
        3.23, 1.22, 0.46, 0.17, 0.066, 0.025,
        0.0095, 0.0036, 0.0014, 0.0005
    ]

    private var edgeLength: String {
        let km = Self.edgeLengthKm[safe: resolution] ?? 0
        if km >= 1 { return String(format: "~%.1f km", km) }
        return String(format: "~%.0f m", km * 1000)
    }

    private var leafFraction: Double {
        guard let info else { return 0 }
        let depth = CellStore.maxResolution - resolution
        if depth <= 0 { return 1.0 }
        guard info.visitedLeaves > 0 else { return 0 }
        let total = pow(7.0, Double(depth))
        return min(Double(info.visitedLeaves) / total, 1.0)
    }

    /// The score that the coverage filter uses (see `VisitedHexagonOverlays.explorationScore`).
    private var explorationScore: Double {
        guard let info, let cellResolution = H3Cell.Resolution(rawValue: Int32(resolution)) else { return 0 }
        return VisitedHexagonOverlays.explorationScore(visitedLeaves: info.visitedLeaves, resolution: cellResolution)
    }

    private var coverageText: String {
        guard let info else { return "Not yet visited" }
        let isLeaf = resolution >= CellStore.maxResolution
        let leaves = isLeaf ? 1 : info.visitedLeaves
        return "\(leaves) \(leaves == 1 ? "cell" : "cells") · \(Int(leafFraction * 100))% · score \(String(format: "%.2f", explorationScore))"
    }

    private var cellIDHex: String {
        guard let id = state.selectedCellIndex else { return "" }
        return String(id, radix: 16, uppercase: true)
    }

    /// The center of the selected cell, packaged for the share sheet.
    private var sharedCellLocation: SharedCellLocation? {
        guard let id = state.selectedCellIndex,
              let center = try? H3Cell(id).center else { return nil }
        return SharedCellLocation(
            name: "Hexplorer cell \(cellIDHex)",
            latitude: center.latitudeDegs,
            longitude: center.longitudeDegs
        )
    }

    private var resolutionBinding: Binding<Int> {
        Binding(
            get: { resolution },
            set: { newVal in
                let clamped = min(max(newVal, 0), CellStore.maxResolution)
                if clamped != state.selectedCellResolution {
                    state.reselect(at: clamped)
                }
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            headerRow
            Divider()
            infoRows
            Divider()
            footerRow
        }
        .padding(16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
        .contentShape(Rectangle())
        .onTapGesture { state.clear() }
    }

    @ViewBuilder
    private var headerRow: some View {
        HStack {
            Label("Cell", systemImage: "hexagon")
                .font(.headline)
            Text(cellIDHex)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Spacer()
            Button { state.clear() } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
                    .font(.title3)
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var infoRows: some View {
        Stepper(value: resolutionBinding, in: 0...CellStore.maxResolution) {
            LabeledContent("Level", value: "\(resolution)")
        }
        LabeledContent("Size", value: edgeLength)
        LabeledContent("Discovered", value: info.map { $0.firstVisitedAt.formatted(.relative(presentation: .named)) } ?? "—")
        LabeledContent("Last visit", value: info.map { $0.lastVisitedAt.formatted(.relative(presentation: .named)) } ?? "—")
        LabeledContent("Visits", value: info.map { "\($0.visitCount)" } ?? "—")
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Coverage")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(coverageText)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(info == nil ? .secondary : .primary)
                    .italic(info == nil)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4).fill(Color.secondary.opacity(0.2))
                    RoundedRectangle(cornerRadius: 4)
                        .fill(LinearGradient(colors: [.yellow, .orange], startPoint: .leading, endPoint: .trailing))
                        .frame(width: geo.size.width * CGFloat(leafFraction))
                }
            }
            .frame(height: 8)
        }
    }

    @ViewBuilder
    private var footerRow: some View {
        HStack {
            if let sharedCellLocation {
                Button {
                    sharedCellLocation.openInAppleMaps()
                } label: {
                    Image(systemName: "map")
                        .font(.body)
                        .padding(8)
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Open in Apple Maps")

                Button {
                    sharedCellLocation.openDirectionsInAppleMaps()
                } label: {
                    Image(systemName: "arrow.triangle.turn.up.right.diamond")
                        .font(.body)
                        .padding(8)
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Directions in Apple Maps")
            }

            Spacer()

            if let sharedCellLocation {
                Button {
                    sharedCellLocation.presentShareSheet()
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.body)
                        .padding(8)
                }
                .buttonStyle(.bordered)
            }

            Button(role: .destructive) { showDeleteConfirmation = true } label: {
                Image(systemName: "trash").font(.body).padding(8)
            }
            .buttonStyle(.bordered)
            .tint(.red)
            .disabled(info == nil)
            .confirmationDialog(
                "Delete all visited leaves in this cell?",
                isPresented: $showDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    guard let id = state.selectedCellIndex else { return }
                    try? CellStore.shared.deleteLeavesInCell(h3Index: id)
                    state.reselect(at: resolution)
                    onDelete?()
                }
            }
            Button {
                onAddFlag?()
            } label: {
                Image(systemName: "flag")
                    .font(.body)
                    .padding(8)
            }
            .buttonStyle(.bordered)

        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
