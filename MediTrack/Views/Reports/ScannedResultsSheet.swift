import SwiftUI

/// Lets the user review lab values recognized by `LabScanService` before
/// adding them to the report being edited.
struct ScannedResultsSheet: View {
    @Environment(\.dismiss) private var dismiss

    let values: [ScannedLabValue]
    let onAdd: ([ScannedLabValue]) -> Void

    @State private var selectedIDs: Set<UUID>

    init(values: [ScannedLabValue], onAdd: @escaping ([ScannedLabValue]) -> Void) {
        self.values = values
        self.onAdd = onAdd
        _selectedIDs = State(initialValue: Set(values.map(\.id)))
    }

    var body: some View {
        NavigationStack {
            Group {
                if values.isEmpty {
                    ContentUnavailableView(
                        "No Lab Values Found",
                        systemImage: "doc.text.magnifyingglass",
                        description: Text("Couldn't recognize any known lab tests in the attached documents. You can still add results manually.")
                    )
                } else {
                    List {
                        Section {
                            ForEach(values) { scanned in
                                Button {
                                    toggle(scanned.id)
                                } label: {
                                    HStack(spacing: 10) {
                                        Image(systemName: selectedIDs.contains(scanned.id) ? "checkmark.circle.fill" : "circle")
                                            .foregroundStyle(selectedIDs.contains(scanned.id) ? Color.accentColor : Color.secondary)
                                            .accessibilityHidden(true)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(scanned.reference.name)
                                                .foregroundStyle(.primary)
                                            Text("“\(scanned.sourceLine)”")
                                                .font(.caption2)
                                                .foregroundStyle(.tertiary)
                                                .lineLimit(1)
                                        }
                                        Spacer()
                                        Text("\(scanned.value.compactFormatted) \(scanned.reference.unit)")
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(.primary)
                                    }
                                }
                                .accessibilityElement(children: .combine)
                                .accessibilityAddTraits(selectedIDs.contains(scanned.id) ? .isSelected : [])
                            }
                        } header: {
                            Text("Detected Lab Values")
                        } footer: {
                            Text("Review each value against the original document before adding — text recognition can make mistakes.")
                        }
                        .listRowBackground(GlassRowBackground())
                        .listRowSeparator(.hidden)
                    }
                }
            }
            .ambientScreen()
            .navigationTitle("Scan Results")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add (\(selectedIDs.count))") {
                        onAdd(values.filter { selectedIDs.contains($0.id) })
                        dismiss()
                    }
                    .disabled(selectedIDs.isEmpty)
                }
            }
        }
    }

    private func toggle(_ id: UUID) {
        if selectedIDs.contains(id) {
            selectedIDs.remove(id)
        } else {
            selectedIDs.insert(id)
        }
    }
}
