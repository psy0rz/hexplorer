import SwiftUI

/// A slider with two thumbs on one track of discrete stops. Each thumb shows the label of its
/// stop, and the thumbs split the track into three colored segments. The thumbs cannot pass
/// each other or share a stop: a thumb that is dragged into the other one pushes it along.
struct TwoThumbStopSlider: View {
    @Binding var lowerStopIndex: Int
    @Binding var upperStopIndex: Int
    let stopCount: Int
    /// The text on a thumb; VoiceOver also speaks it.
    let stopLabel: (Int) -> String
    let lowerSegmentColor: Color
    let middleSegmentColor: Color
    let upperSegmentColor: Color

    private enum Thumb { case lower, upper }

    /// The thumb that the current drag moves; the nearest thumb when the drag starts.
    @State private var draggedThumb: Thumb?

    private let thumbWidth: CGFloat = 40
    private let thumbHeight: CGFloat = 24

    var body: some View {
        GeometryReader { geometry in
            // The thumb centers run from half a thumb from the left edge to half a thumb from the right edge.
            let stopSpacing = (geometry.size.width - thumbWidth) / CGFloat(max(stopCount - 1, 1))
            let lowerThumbX = thumbWidth / 2 + CGFloat(lowerStopIndex) * stopSpacing
            let upperThumbX = thumbWidth / 2 + CGFloat(upperStopIndex) * stopSpacing

            ZStack {
                HStack(spacing: 0) {
                    lowerSegmentColor.frame(width: lowerThumbX - thumbWidth / 2)
                    middleSegmentColor.frame(width: upperThumbX - lowerThumbX)
                    upperSegmentColor
                }
                .frame(height: 6)
                .clipShape(Capsule())
                .padding(.horizontal, thumbWidth / 2)

                thumb(.lower, stopIndex: lowerStopIndex).position(x: lowerThumbX, y: geometry.size.height / 2)
                thumb(.upper, stopIndex: upperStopIndex).position(x: upperThumbX, y: geometry.size.height / 2)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        guard stopSpacing > 0 else { return }
                        let touchedThumb = draggedThumb
                            ?? (abs(drag.startLocation.x - lowerThumbX) < abs(drag.startLocation.x - upperThumbX) ? .lower : .upper)
                        draggedThumb = touchedThumb
                        let touchedStopIndex = Int(((drag.location.x - thumbWidth / 2) / stopSpacing).rounded())
                        move(touchedThumb, to: touchedStopIndex)
                    }
                    .onEnded { _ in draggedThumb = nil }
            )
        }
        .frame(height: thumbHeight + 4)
        .sensoryFeedback(.selection, trigger: lowerStopIndex)
        .sensoryFeedback(.selection, trigger: upperStopIndex)
    }

    /// Moves a thumb to a stop, and pushes the other thumb if they would meet.
    /// Each thumb keeps one stop free at its far end of the track for the other thumb.
    private func move(_ thumb: Thumb, to requestedStopIndex: Int) {
        switch thumb {
        case .lower:
            lowerStopIndex = min(max(requestedStopIndex, 0), stopCount - 2)
            upperStopIndex = max(upperStopIndex, lowerStopIndex + 1)
        case .upper:
            upperStopIndex = min(max(requestedStopIndex, 1), stopCount - 1)
            lowerStopIndex = min(lowerStopIndex, upperStopIndex - 1)
        }
    }

    private func thumb(_ thumb: Thumb, stopIndex: Int) -> some View {
        Text(stopLabel(stopIndex))
            .font(.caption2.weight(.semibold).monospacedDigit())
            .foregroundStyle(.black)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(width: thumbWidth, height: thumbHeight)
            .background(Capsule().fill(.white).shadow(color: .black.opacity(0.25), radius: 2, y: 1))
            .accessibilityAdjustableAction { direction in
                move(thumb, to: stopIndex + (direction == .increment ? 1 : -1))
            }
    }
}
