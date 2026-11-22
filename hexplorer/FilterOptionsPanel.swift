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
            Divider()
            modeControls
        }
        .padding(16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
    }

    @ViewBuilder
    private var modeControls: some View {
        switch filter.mode {
        case .resolution:
            sliderRow(label: "Dense from", value: $filter.denseChildrenThreshold, range: 1...7, unit: "children")
            sliderRow(label: "Full from",  value: $filter.fullChildrenThreshold,  range: 1...7, unit: "children")
        case .time:
            timeSlider
        case .leafCount:
            sliderRow(label: "Dense from", value: $filter.denseLeafPercent, range: 1...99,  unit: "%")
            sliderRow(label: "Full from",  value: $filter.fullLeafPercent,  range: 1...100, unit: "%")
        }
    }

    /// One track for the three time levels: full (visited very recently), dense (recently)
    /// and partial (longer ago). The two thumbs are the borders between the levels.
    private var timeSlider: some View {
        let ageStops = FilterState.ageStops
        let colors = OverlayColors.shared

        return TwoThumbStopSlider(
            lowerStopIndex: $filter.veryRecentAgeStopIndex,
            upperStopIndex: $filter.recentAgeStopIndex,
            stopCount: ageStops.count,
            stopLabel: { ageStops[$0].label },
            lowerSegmentColor: colors.full,
            middleSegmentColor: colors.dense,
            upperSegmentColor: .secondary.opacity(0.3)
        )
    }

    @ViewBuilder
    private func sliderRow(label: String, value: Binding<Double>, range: ClosedRange<Double>, unit: String) -> some View {
        VStack(spacing: 2) {
            HStack {
                Text(label)
                    .font(.caption)
                Spacer()
                Text("\(Int(value.wrappedValue)) \(unit)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Slider(value: value, in: range, step: 1)
        }
    }
}
