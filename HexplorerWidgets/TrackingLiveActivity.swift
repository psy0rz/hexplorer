import ActivityKit
import SwiftUI
import WidgetKit

/// The tracking Live Activity: the duration and the number of new cells of the session,
/// on the Lock Screen and in the Dynamic Island.
struct TrackingLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TrackingActivityAttributes.self) { context in
            // The Lock Screen and the banner.
            HStack(spacing: 12) {
                Image(systemName: "location.fill")
                    .font(.title2)
                    .foregroundStyle(.red)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Tracking")
                        .font(.headline)
                    Text("\(context.state.newCellCount) new cells")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                trackingDurationText(since: context.attributes.trackingStartDate)
                    .font(.title3.monospacedDigit())
            }
            .padding()
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label("Tracking", systemImage: "location.fill")
                        .foregroundStyle(.red)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    trackingDurationText(since: context.attributes.trackingStartDate)
                        .monospacedDigit()
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text("\(context.state.newCellCount) new cells")
                }
            } compactLeading: {
                Image(systemName: "location.fill")
                    .foregroundStyle(.red)
            } compactTrailing: {
                Text("\(context.state.newCellCount)")
                    .monospacedDigit()
            } minimal: {
                Image(systemName: "location.fill")
                    .foregroundStyle(.red)
            }
        }
    }

    /// A timer text that the system updates by itself, so the app does not have to.
    private func trackingDurationText(since trackingStartDate: Date) -> Text {
        Text(timerInterval: trackingStartDate...Date.distantFuture, countsDown: false)
    }
}
