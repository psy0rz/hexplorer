import SwiftUI

struct FilterOptionsPanel: View {
    @Bindable var filter: FilterState
    var onClose: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Display Mode", systemImage: "slider.horizontal.3")
                    .font(.headline)
                Spacer()
                Button("Reset", systemImage: "arrow.counterclockwise") { filter.resetActiveModeToDefaults() }
                    .labelStyle(.iconOnly)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .buttonStyle(.plain)
                    .accessibilityLabel("Reset \(filter.mode.rawValue) to defaults")
                Button { onClose?() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .font(.title3)
                }
                .buttonStyle(.plain)
            }
            Divider()
            Picker("Mode", selection: $filter.mode) {
                ForEach(FilterMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            Label(filter.mode.explanation, systemImage: filter.mode.systemImage)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Divider()
            modeControls
        }
        .padding(16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
    }

    /// One slider for each mode. The two thumbs are the borders between partial, dense and full.
    /// For ages a lower value is denser, so the segments run full → partial; for amounts
    /// a higher value is denser, so they run partial → full.
    @ViewBuilder
    private var modeControls: some View {
        switch filter.mode {
        case .time:
            stopSlider(stops: FilterState.ageStops,
                       lowerStopIndex: $filter.veryRecentAgeStopIndex,
                       upperStopIndex: $filter.recentAgeStopIndex,
                       lowerValueIsDenser: true)
        case .coverage:
            stopSlider(stops: FilterState.coverageStops,
                       lowerStopIndex: $filter.denseCoverageStopIndex,
                       upperStopIndex: $filter.fullCoverageStopIndex,
                       lowerValueIsDenser: false)
        case .visits:
            stopSlider(stops: FilterState.visitCountStops,
                       lowerStopIndex: $filter.denseVisitCountStopIndex,
                       upperStopIndex: $filter.fullVisitCountStopIndex,
                       lowerValueIsDenser: false)
        case .discovered:
            stopSlider(stops: FilterState.ageStops,
                       lowerStopIndex: $filter.newlyDiscoveredAgeStopIndex,
                       upperStopIndex: $filter.recentlyDiscoveredAgeStopIndex,
                       lowerValueIsDenser: true)
        }
    }

    private func stopSlider(
        stops: [FilterState.FilterStop],
        lowerStopIndex: Binding<Int>,
        upperStopIndex: Binding<Int>,
        lowerValueIsDenser: Bool
    ) -> some View {
        let colors = OverlayColors.shared
        let partialSegmentColor = Color.secondary.opacity(0.3)
        return TwoThumbStopSlider(
            lowerStopIndex: lowerStopIndex,
            upperStopIndex: upperStopIndex,
            stopCount: stops.count,
            stopLabel: { stops[$0].label },
            lowerSegmentColor: lowerValueIsDenser ? colors.full : partialSegmentColor,
            middleSegmentColor: colors.dense,
            upperSegmentColor: lowerValueIsDenser ? partialSegmentColor : colors.full
        )
    }
}
