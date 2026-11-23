import SwiftUI
import MapKit

struct FlagEditorPanel: View {
    /// Non-nil when editing an existing flag; nil when creating a new one.
    var existingFlag: MapFlag?
    var coordinate: CLLocationCoordinate2D?
    var onSave: ((UUID?) -> Void)? = nil   // passes the flag id when editing, nil when adding
    var onCancel: (() -> Void)? = nil
    var onDelete: (() -> Void)? = nil

    @State private var label: String
    @State private var color: FlagColor
    @State private var priority: FlagPriority
    @State private var showDeleteConfirmation = false

    init(existingFlag: MapFlag? = nil,
         coordinate: CLLocationCoordinate2D? = nil,
         onSave: ((UUID?) -> Void)? = nil,
         onCancel: (() -> Void)? = nil,
         onDelete: (() -> Void)? = nil) {
        self.existingFlag = existingFlag
        self.coordinate   = coordinate
        self.onSave       = onSave
        self.onCancel     = onCancel
        self.onDelete     = onDelete
        _label    = State(initialValue: existingFlag?.label    ?? "")
        _color    = State(initialValue: existingFlag?.color    ?? .red)
        _priority = State(initialValue: existingFlag?.priority ?? .high)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            headerRow
            Divider()
            fieldsSection
            Divider()
            footerRow
        }
        .padding(16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
        .contentShape(Rectangle())
        .onTapGesture {}   // prevent tap-through dismissing the underlying cell selection
    }

    @ViewBuilder
    private var headerRow: some View {
        HStack {
            // Same icon as the map marker; "mappin" matches the marker's default glyph.
            // The icon sits in a circle of the selected colour, like the marker balloon.
            Label {
                Text(existingFlag == nil ? "New Flag" : "Edit Flag")
            } icon: {
                Image(systemName: priority.symbolName ?? "mappin")
                    .font(.footnote)
                    .foregroundStyle(.white)
                    .frame(width: 26, height: 26)
                    .background(Color(color.uiColor), in: Circle())
            }
            .font(.headline)
//                .foregroundStyle(Color(existingFlag?.color.uiColor ?? FlagColor.red.uiColor))
            Spacer()
            Button { onCancel?() } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.primary)
                    .font(.title3)
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var fieldsSection: some View {
        TextField("Label (optional)", text: $label)
            .textFieldStyle(.roundedBorder)
            .font(.subheadline)
            .onTapGesture {}

        // Color swatches
        HStack(spacing: 10) {
            ForEach(FlagColor.allCases) { c in
                Circle()
                    .fill(Color(c.uiColor))
                    .frame(width: 26, height: 26)
                    .overlay(Circle().strokeBorder(Color.primary, lineWidth: color == c ? 2.5 : 0))
                    .onTapGesture { color = c }
            }
            Spacer()
        }

        // Priority
        Picker("Priority", selection: $priority) {
            ForEach(FlagPriority.allCases) { flagPriority in
                Text(flagPriority.label).tag(flagPriority)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }

    @ViewBuilder
    private var footerRow: some View {
        HStack {
            Spacer()

            if existingFlag != nil {
                Button(role: .destructive) {
                    showDeleteConfirmation = true
                } label: {
                    Image(systemName: "trash").font(.body).padding(8)
                }
                .buttonStyle(.bordered)
                .tint(.red)
                .confirmationDialog(
                    "Delete this flag?",
                    isPresented: $showDeleteConfirmation,
                    titleVisibility: .visible
                ) {
                    Button("Delete", role: .destructive) {
                        if let id = existingFlag?.id {
                            FlagStore.shared.removeFlag(id: id)
                        }
                        onDelete?()
                    }
                }
            }


            Button {
                commit()
            } label: {
                Label(existingFlag == nil ? "Add Flag" : "Save",
                      systemImage: existingFlag == nil ? "flag.badge.plus" : "checkmark")
                    .font(.body)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private func commit() {
        if let existing = existingFlag {
            var updated = existing
            updated.label    = label
            updated.color    = color
            updated.priority = priority
            FlagStore.shared.updateFlag(updated)
            onSave?(existing.id)
        } else {
            guard let coord = coordinate else { return }
            FlagStore.shared.addFlag(at: coord, label: label, color: color, priority: priority)
            onSave?(nil)
        }
        SelectedCellState.shared.clear()
    }
}
