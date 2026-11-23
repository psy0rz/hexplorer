import SwiftUI

/// The bottom panel where the user selects the map style and the labels.
struct MapLayersPanel: View {
    @Bindable var settings: MapLayerSettings
    var onClose: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Map", systemImage: "square.2.layers.3d")
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
            Picker("Map Style", selection: $settings.mapStyle) {
                ForEach(MapStyle.allCases) { mapStyle in
                    Text(mapStyle.rawValue).tag(mapStyle)
                }
            }
            .pickerStyle(.segmented)
            Toggle("Labels", isOn: $settings.showsSatelliteLabels)
                .disabled(settings.mapStyle == .standard)
            Toggle("Points of Interest", isOn: $settings.showsPointsOfInterest)
                .disabled(!settings.canShowPointsOfInterest)
        }
        .padding(16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
    }
}
