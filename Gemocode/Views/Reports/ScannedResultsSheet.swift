import SwiftUI
import SwiftData

/// Lets the user review lab values recognized by `LabScanService` before
/// adding them to the report being edited.
struct ScannedResultsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Query private var profiles: [HealthProfile]

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
                                scannedValueRow(scanned)
                            }
                        } header: {
                            MicroLabel("Detected Lab Values")
                        } footer: {
                            Text("Review each value against the original document before adding — text recognition can make mistakes.")
                        }
                        .listRowBackground(GlassRowBackground())
                        .listRowSeparator(.hidden)
                    }
                    .listStyle(.plain)
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

    /// One ledger row per scanned value: selection indicator, name + value +
    /// (when out of range) status tag on the first line, the range-bar
    /// beneath it, and the original OCR line as a quoted caption — the same
    /// "name, value, tag, bar" grammar used everywhere a lab value appears.
    private func scannedValueRow(_ scanned: ScannedLabValue) -> some View {
        let isSelected = selectedIDs.contains(scanned.id)
        let sex = profiles.first?.sex
        let range = scanned.reference.referenceRange(for: sex)
        let status = AnalysisEngine.status(
            value: scanned.value,
            range: range,
            criticalLow: scanned.reference.criticalLow,
            criticalHigh: scanned.reference.criticalHigh
        )

        return Button {
            toggle(scanned.id)
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 17))
                    .foregroundStyle(isSelected ? Editorial.accent(colorScheme) : Editorial.controlBorder(colorScheme))
                    .accessibilityHidden(true)
                    .padding(.top, 1)

                VStack(alignment: .leading, spacing: 7) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(scanned.reference.name)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Editorial.ink(colorScheme))
                        Spacer(minLength: 8)
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text("\(scanned.value.compactFormatted) \(scanned.reference.unit)")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(Editorial.ink(colorScheme))
                            if status.isOutOfRange {
                                StatusPill(text: status.label, color: status.color)
                            }
                        }
                    }

                    if let range {
                        let axis = rangeBarAxis(range: range, value: scanned.value)
                        RangeBar(
                            lower: range.lowerBound,
                            upper: range.upperBound,
                            min: axis.min,
                            max: axis.max,
                            value: scanned.value,
                            accessibilityLabel: Text("\(scanned.reference.name) \(scanned.value.compactFormatted) \(scanned.reference.unit), \(status.label)")
                        )
                    }

                    Text("“\(scanned.sourceLine)”")
                        .font(.system(size: 11))
                        .foregroundStyle(Editorial.muted(colorScheme))
                        .lineLimit(1)
                }
            }
        }
        .buttonStyle(.plain)
        .ledgerRow()
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func toggle(_ id: UUID) {
        if selectedIDs.contains(id) {
            selectedIDs.remove(id)
        } else {
            selectedIDs.insert(id)
        }
    }
}

/// Axis bounds for a `RangeBar` built around a reference range: padded on
/// both sides so the out-of-range zones read clearly, and widened further
/// whenever the value itself sits outside that padding so the marker is
/// never clipped to the bar's edge. `private` and intentionally duplicated
/// (rather than shared) in every file that needs it — `Support
/// /EditorialComponents.swift` isn't owned by this pass, and a file-private
/// helper can't collide with another agent's same-named helper elsewhere in
/// the module.
private func rangeBarAxis(range: ClosedRange<Double>, value: Double) -> (min: Double, max: Double) {
    let width = range.upperBound - range.lowerBound
    let pad = width > 0 ? width * 0.35 : max(abs(range.upperBound), 1) * 0.2
    let lower = Swift.min(range.lowerBound - pad, value - pad * 0.15)
    let upper = Swift.max(range.upperBound + pad, value + pad * 0.15)
    return (lower, upper)
}
