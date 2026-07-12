import SwiftUI
import SwiftData
import UIKit

/// Quick Add: a single text field where the user types a natural sentence
/// ("aspirin 100mg twice daily"), sees a live preview of what
/// `QuickAddParser` understood, and confirms. When the deterministic parser
/// can't confidently interpret the text, an optional "Fill with AI" button
/// (shown only when an Anthropic API key is configured) offers
/// `QuickAddAIService` as a fallback. Either path produces the same
/// `QuickAddDraft`, which `save()` maps onto the matching SwiftData model.
struct QuickAddView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var text = ""
    @State private var draft: QuickAddDraft?
    @State private var isAIFilled = false
    @State private var isLoadingAI = false
    @State private var aiErrorMessage: String?
    @FocusState private var isFieldFocused: Bool

    private static let examples = ["bp 128/82", "headache severity 6", "dentist tomorrow 3pm"]

    private var trimmedText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The deterministic parser failed, but the text looks like a genuine
    /// attempt rather than a stray keystroke — worth offering the AI fallback.
    private var looksLikeAnAttempt: Bool {
        trimmedText.count >= 12 || trimmedText.split(separator: " ").count >= 3
    }

    private var showsAIButton: Bool {
        draft == nil && !isLoadingAI && looksLikeAnAttempt && AISummaryService.isConfigured
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    QuickAddHeader()

                    VStack(alignment: .leading, spacing: 12) {
                        TextField("Try: aspirin 100mg twice daily", text: $text, axis: .vertical)
                            .font(.system(.title3, design: .rounded, weight: .semibold))
                            .lineLimit(1...3)
                            .focused($isFieldFocused)
                            .submitLabel(.done)
                            .accessibilityLabel("Quick add text")
                            .accessibilityHint("Describe a medication, vital, symptom, appointment, or reminder in a sentence.")

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(Self.examples, id: \.self) { example in
                                    QuickAddExampleChip(label: example) {
                                        text = example
                                    }
                                }
                            }
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassCard()

                    aiAssistSection

                    if let draft {
                        QuickAddPreviewCard(draft: draft, isAIFilled: isAIFilled)
                            .transition(.asymmetric(
                                insertion: .scale(scale: 0.94).combined(with: .opacity),
                                removal: .opacity
                            ))
                    }
                }
                .padding()
            }
            .ambientScreen()
            .navigationTitle("Quick Add")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { save() }
                        .disabled(draft == nil)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(.ultraThinMaterial)
        .onAppear { isFieldFocused = true }
        .onChange(of: text) { _, newValue in
            handleTextChange(newValue)
        }
    }

    @ViewBuilder
    private var aiAssistSection: some View {
        if isLoadingAI {
            HStack(spacing: 10) {
                ProgressView()
                Text("Asking AI…")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
            .accessibilityElement(children: .combine)
        } else if showsAIButton {
            Button(action: fillWithAI) {
                Label("Fill with AI", systemImage: "sparkles")
            }
            .buttonStyle(QuickAddAIButtonStyle())
            .accessibilityLabel("Fill with AI")
            .accessibilityHint("Asks the AI to interpret this text since it couldn't be recognized automatically.")
        }

        if let aiErrorMessage {
            Label(aiErrorMessage, systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.orange)
                .accessibilityLabel("AI fill failed: \(aiErrorMessage)")
        }
    }

    private func handleTextChange(_ newValue: String) {
        aiErrorMessage = nil
        let parsed = QuickAddParser.parse(newValue, now: .now, calendar: .current)
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            draft = parsed
            isAIFilled = false
        }
    }

    private func fillWithAI() {
        let query = trimmedText
        isLoadingAI = true
        aiErrorMessage = nil
        Task {
            do {
                let result = try await QuickAddAIService.complete(query)
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    draft = result
                    isAIFilled = true
                }
                isLoadingAI = false
            } catch {
                aiErrorMessage = (error as? LocalizedError)?.errorDescription
                    ?? "Something went wrong. Try rephrasing."
                isLoadingAI = false
            }
        }
    }

    /// Maps the confirmed draft onto the matching `@Model` initializer.
    /// Vitals are already in canonical metric units, coming straight from
    /// `QuickAddParser`/`QuickAddAIService`. Every case creates a standalone
    /// top-level model — Quick Add never touches an optional-relationship
    /// child (e.g. `ReminderCompletion`), so there's nothing to insert
    /// before appending.
    private func save() {
        guard let draft else { return }
        switch draft {
        case let .medication(name, dosage, frequency):
            modelContext.insert(Medication(name: name, dosage: dosage, frequency: frequency))

        case let .vital(type, value, secondary):
            modelContext.insert(VitalSample(type: type, value: value, secondaryValue: secondary))

        case let .symptom(name, severity):
            modelContext.insert(SymptomEntry(name: name, severity: severity))

        case let .appointment(title, date):
            modelContext.insert(Appointment(title: title, date: date))

        case let .reminder(title, time):
            modelContext.insert(Reminder(title: title, timeOfDay: time))
        }
        Haptics.success()
        dismiss()
    }
}

// MARK: - Header

private struct QuickAddHeader: View {
    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "bolt.fill")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 52, height: 52)
                .background(Glass.accentGradient, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text("Quick Add")
                    .font(.title2.bold())
                Text("Type a sentence — MediTrack figures out the rest.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Example chips

private struct QuickAddExampleChip: View {
    let label: String
    let action: () -> Void

    var body: some View {
        Button {
            QuickAddHaptics.selection()
            action()
        } label: {
            Text(label)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(Glass.bevelStroke, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Fill example: \(label)")
    }
}

/// Light selection feedback for chip taps — `UIHelpers.Haptics` only defines
/// the success notification haptic used on save, so this stays local to this file.
private enum QuickAddHaptics {
    static func selection() {
        UISelectionFeedbackGenerator().selectionChanged()
    }
}

// MARK: - AI fill button style

private struct QuickAddAIButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.vertical, 11)
            .padding(.horizontal, 18)
            .background(
                Capsule()
                    .fill(Glass.accentGradient)
                    .opacity(configuration.isPressed ? 0.8 : 1)
            )
            .overlay(Capsule().strokeBorder(Glass.bevelStroke, lineWidth: 1))
            .shadow(color: .blue.opacity(0.3), radius: 8, x: 0, y: 4)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(duration: 0.2), value: configuration.isPressed)
    }
}

// MARK: - Preview card

private struct QuickAddPreviewCard: View {
    let draft: QuickAddDraft
    let isAIFilled: Bool

    private var display: QuickAddPreviewDisplay { QuickAddPreviewDisplay(draft: draft) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: display.icon)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(width: 42, height: 42)
                    .background(display.tint.gradient, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    StatusPill(text: display.typeLabel, color: display.tint)
                    Text(display.primaryText)
                        .font(.title3.bold())
                }
                Spacer(minLength: 0)
            }

            if !display.detailLines.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(display.detailLines, id: \.self) { line in
                        Text(line)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if isAIFilled {
                Label("AI-filled — please double-check. Educational, not diagnostic.", systemImage: "sparkles")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            display.accessibilitySummary + (isAIFilled ? ". AI filled, please double-check." : "")
        )
    }
}

/// Derives the icon, tint, labels, and formatted lines shown in
/// `QuickAddPreviewCard` from a `QuickAddDraft`. Kept as a plain struct
/// (rather than inline switch logic in the view) so the preview and its
/// accessibility summary are always built from the same source of truth.
private struct QuickAddPreviewDisplay {
    let icon: String
    let tint: Color
    let typeLabel: String
    let primaryText: String
    let detailLines: [String]
    let accessibilitySummary: String

    init(draft: QuickAddDraft) {
        switch draft {
        case let .medication(name, dosage, frequency):
            icon = "pills.fill"
            tint = .teal
            typeLabel = "Medication"
            primaryText = name
            let parts = [dosage, frequency].filter { !$0.isEmpty }
            detailLines = parts.isEmpty ? [] : [parts.joined(separator: " · ")]
            accessibilitySummary = "Medication: \(name)" + (parts.isEmpty ? "" : ", \(parts.joined(separator: ", "))")

        case let .vital(type, value, secondary):
            icon = type.systemImage
            tint = .blue
            typeLabel = "Vital · \(type.displayName)"
            primaryText = Self.vitalValueText(type: type, value: value, secondary: secondary)
            detailLines = []
            accessibilitySummary = "Vital, \(type.displayName): \(primaryText)"

        case let .symptom(name, severity):
            icon = "bandage.fill"
            tint = .orange
            typeLabel = "Symptom"
            primaryText = name
            detailLines = ["Severity \(severity) of 10"]
            accessibilitySummary = "Symptom: \(name), severity \(severity) out of 10"

        case let .appointment(title, date):
            icon = "calendar"
            tint = .indigo
            typeLabel = "Appointment"
            primaryText = title
            let formattedDate = date.formatted(date: .abbreviated, time: .shortened)
            detailLines = [formattedDate]
            accessibilitySummary = "Appointment: \(title), \(formattedDate)"

        case let .reminder(title, time):
            icon = "bell.fill"
            tint = .purple
            typeLabel = "Reminder"
            primaryText = title
            if let time {
                let formattedTime = time.formatted(date: .omitted, time: .shortened)
                detailLines = [formattedTime]
                accessibilitySummary = "Reminder: \(title), \(formattedTime)"
            } else {
                detailLines = []
                accessibilitySummary = "Reminder: \(title)"
            }
        }
    }

    /// Mirrors `VitalSample.formattedValue`'s blood-pressure special case —
    /// the draft hasn't been materialized into a `VitalSample` yet, so this
    /// small formatter is duplicated here rather than borrowed from Models.swift.
    private static func vitalValueText(type: VitalType, value: Double, secondary: Double?) -> String {
        if type == .bloodPressure, let secondary {
            return "\(Int(value))/\(Int(secondary)) \(type.unit)"
        }
        return Units.formatted(value, for: type)
    }
}
