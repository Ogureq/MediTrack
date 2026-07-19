import SwiftUI
import SwiftData
import UIKit

/// Quick Add: a multi-line text field where the user types (or dictates) a
/// whole sentence or paragraph, sees a live preview of what the free,
/// on-device `QuickAddParser` understood, and confirms. AI is the premium,
/// AI-first path on top of that: it can turn the *same* text into either one
/// richer draft or several — "weighed 82kg, bp 130/85, slept 6h" becomes
/// three ready-to-confirm records — via `QuickAddAIService`. Non-premium
/// users see the same sparkles button with a lock badge; tapping it presents
/// `PaywallView`. Every path (deterministic, single-AI, batch-AI) ultimately
/// produces `QuickAddDraft`s, which `insert(_:)` maps onto the matching
/// SwiftData model.
struct QuickAddView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @ObservedObject private var premiumStore = PremiumStore.shared

    @State private var text = ""
    @State private var draft: QuickAddDraft?
    @State private var isAIFilled = false
    @State private var batchDrafts: [BatchDraftItem] = []
    @State private var isLoadingAI = false
    @State private var aiErrorMessage: String?
    @State private var showingPaywall = false
    /// Guards `save()`/`saveBatch()` against a fast double-tap firing twice
    /// before `dismiss()` actually removes the sheet — check-and-set at the
    /// top of each, and the Add/confirm buttons disable on it too.
    @State private var isSaving = false
    @FocusState private var isFieldFocused: Bool

    private static let examples = ["bp 128/82", "headache severity 6", "dentist tomorrow 3pm"]

    private var trimmedText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Worth offering the AI button rather than a stray keystroke or a
    /// single already-recognized word.
    private var looksLikeAnAttempt: Bool {
        trimmedText.count >= 12 || trimmedText.split(separator: " ").count >= 3
    }

    /// Shown whenever the text looks like a genuine attempt — even when the
    /// deterministic parser already produced a single-item preview, since
    /// AI may still find *more* items in the same text (e.g. a sentence
    /// listing several vitals, of which the on-device parser only catches
    /// the first). Hidden while a batch result is already on screen or a
    /// request is in flight.
    private var showsAIButton: Bool {
        !isLoadingAI && looksLikeAnAttempt && batchDrafts.isEmpty
    }

    /// Heuristic for whether the text plausibly contains multiple items:
    /// a list-like separator, or the deterministic parser only managing to
    /// interpret (or find) a single thing out of what might be more.
    private var looksLikeMultipleItems: Bool {
        trimmedText.contains(",") || trimmedText.contains(" and ") || trimmedText.contains("\n") || draft == nil
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    QuickAddHeader()

                    VStack(alignment: .leading, spacing: 12) {
                        TextField(
                            "Try: weighed 82kg, bp 130/85, slept 6h, took aspirin 100mg",
                            text: $text,
                            axis: .vertical
                        )
                        .font(.system(.title3, design: .rounded, weight: .semibold))
                        .lineLimit(1...4)
                        .focused($isFieldFocused)
                        .submitLabel(.done)
                        .accessibilityLabel("Quick add text")
                        .accessibilityHint("Describe one or more medications, vitals, symptoms, appointments, or reminders in a sentence or paragraph.")

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

                    if !batchDrafts.isEmpty {
                        batchSection
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
                        .disabled(draft == nil || isSaving)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(.ultraThinMaterial)
        .onAppear { isFieldFocused = true }
        .onChange(of: text) { _, newValue in
            handleTextChange(newValue)
        }
        .sheet(isPresented: $showingPaywall) {
            PaywallView()
        }
    }

    // MARK: - Batch review section

    @ViewBuilder
    private var batchSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(batchDrafts) { item in
                QuickAddBatchPreviewCard(draft: item.draft) {
                    removeBatchItem(item.id)
                }
            }

            Button(action: saveBatch) {
                Label(
                    batchDrafts.count == 1
                        ? String(localized: "Add \(batchDrafts.count) item")
                        : String(localized: "Add \(batchDrafts.count) items"),
                    systemImage: "checkmark.circle.fill"
                )
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(QuickAddAIButtonStyle())
            .accessibilityLabel(
                batchDrafts.count == 1
                    ? String(localized: "Add \(batchDrafts.count) item")
                    : String(localized: "Add \(batchDrafts.count) items")
            )
            .disabled(isSaving)
        }
        .transition(.asymmetric(
            insertion: .scale(scale: 0.94).combined(with: .opacity),
            removal: .opacity
        ))
    }

    private func removeBatchItem(_ id: UUID) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            batchDrafts.removeAll { $0.id == id }
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
                ZStack(alignment: .topTrailing) {
                    Label("Fill with AI", systemImage: "sparkles")
                    if !premiumStore.isPremium {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(4)
                            .background(Circle().fill(.orange))
                            .offset(x: 10, y: -10)
                            .accessibilityHidden(true)
                            // `premiumStore.isPremium` can flip out from under
                            // this view (e.g. a purchase restored while the
                            // sheet is open); without suppressing inherited
                            // animation, the badge can animate in from a
                            // stale/zero frame instead of simply appearing.
                            .transaction { $0.animation = nil }
                    }
                }
            }
            .buttonStyle(QuickAddAIButtonStyle())
            .accessibilityLabel(premiumStore.isPremium ? "Fill with AI" : "Fill with AI. Premium feature, locked")
            .accessibilityHint(
                premiumStore.isPremium
                    ? "Asks the AI to turn this text into one or more ready-to-confirm entries."
                    : "Opens the premium upgrade screen to unlock AI-assisted entry."
            )
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
            batchDrafts = []
        }
    }

    /// AI is premium-only. A non-premium tap opens the paywall instead of
    /// calling the network; the deterministic parser above stays free
    /// regardless. Once premium, the heuristic in `looksLikeMultipleItems`
    /// decides whether to ask for one draft or a batch — either way, an
    /// unconfigured API key surfaces the same `QuickAddAIError.missingKey`
    /// message via `aiErrorMessage` that `complete`/`completeBatch` already throw.
    private func fillWithAI() {
        guard premiumStore.isPremium else {
            showingPaywall = true
            return
        }

        let query = trimmedText
        let wantsBatch = looksLikeMultipleItems
        isLoadingAI = true
        aiErrorMessage = nil
        Task {
            do {
                if wantsBatch {
                    let results = try await QuickAddAIService.completeBatch(query)
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        batchDrafts = results.map { BatchDraftItem(draft: $0) }
                        draft = nil
                        isAIFilled = false
                    }
                } else {
                    let result = try await QuickAddAIService.complete(query)
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        draft = result
                        isAIFilled = true
                        batchDrafts = []
                    }
                }
                isLoadingAI = false
            } catch {
                aiErrorMessage = (error as? LocalizedError)?.errorDescription
                    ?? String(localized: "Something went wrong. Try rephrasing.")
                isLoadingAI = false
            }
        }
    }

    /// Maps one confirmed draft onto the matching `@Model` initializer.
    /// Vitals are already in canonical metric units, coming straight from
    /// `QuickAddParser`/`QuickAddAIService`. Every case creates a standalone
    /// top-level model — Quick Add never touches an optional-relationship
    /// child (e.g. `ReminderCompletion`), so there's nothing to insert
    /// before appending.
    private func insert(_ draft: QuickAddDraft) {
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
    }

    private func save() {
        guard let draft, !isSaving else { return }
        isSaving = true
        insert(draft)
        Haptics.success()
        dismiss()
    }

    private func saveBatch() {
        guard !batchDrafts.isEmpty, !isSaving else { return }
        isSaving = true
        for item in batchDrafts {
            insert(item.draft)
        }
        Haptics.success()
        dismiss()
    }
}

/// One AI-produced draft awaiting confirmation in the batch review list.
/// Wrapped in a stable `UUID` (rather than using `QuickAddDraft` itself,
/// which is only `Equatable`) so `ForEach`/removal work correctly even when
/// two drafts happen to be identical (e.g. two "took aspirin 100mg" lines).
private struct BatchDraftItem: Identifiable {
    let id = UUID()
    let draft: QuickAddDraft
}

// MARK: - Header

private struct QuickAddHeader: View {
    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "bolt.fill")
                // Fixed point size, not `.title2` (which would grow with
                // Dynamic Type and clip inside this fixed 52×52 badge) — 22pt
                // matches `.title2`'s default rendered size, so this looks
                // identical at the standard content size category.
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 52, height: 52)
                .background(Glass.accentGradient, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text("Quick Add")
                    .font(.title2.bold())
                Text("Type a sentence — Gemocode figures out the rest.")
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
                    // Fixed point size, not `.headline` (which would grow
                    // with Dynamic Type and clip inside this fixed 42×42
                    // badge) — 17pt semibold matches `.headline`'s default
                    // rendered size, so this looks identical at the standard
                    // content size category.
                    .font(.system(size: 17, weight: .semibold))
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
            display.accessibilitySummary + (isAIFilled ? String(localized: ". AI filled, please double-check.") : "")
        )
    }
}

/// One row in the multi-draft AI review list (`QuickAddView.batchSection`).
/// Reuses `QuickAddPreviewCard`'s visual language (icon, tint, pill, primary
/// text, detail lines, AI-filled caption) but adds a per-item remove button,
/// since a batch result may include an item the user doesn't want to keep.
///
/// Unlike `QuickAddPreviewCard`, only the descriptive content is combined
/// into a single accessibility element — the remove button is left as its
/// own reachable, separately labeled element rather than swallowed into the
/// card's combined label.
private struct QuickAddBatchPreviewCard: View {
    let draft: QuickAddDraft
    let onRemove: () -> Void

    private var display: QuickAddPreviewDisplay { QuickAddPreviewDisplay(draft: draft) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: display.icon)
                    // Fixed point size, not `.headline` (which would grow
                    // with Dynamic Type and clip inside this fixed 42×42
                    // badge) — 17pt semibold matches `.headline`'s default
                    // rendered size, so this looks identical at the standard
                    // content size category.
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 42, height: 42)
                    .background(display.tint.gradient, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    StatusPill(text: display.typeLabel, color: display.tint)
                    Text(display.primaryText)
                        .font(.title3.bold())
                    ForEach(display.detailLines, id: \.self) { line in
                        Text(line)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(display.accessibilitySummary + String(localized: ". AI filled, please double-check."))

                Spacer(minLength: 0)

                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove \(display.typeLabel) item")
            }

            Label("AI-filled — please double-check. Educational, not diagnostic.", systemImage: "sparkles")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
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
            typeLabel = String(localized: "Medication")
            primaryText = name
            let parts = [dosage, frequency].filter { !$0.isEmpty }
            detailLines = parts.isEmpty ? [] : [parts.joined(separator: " · ")]
            accessibilitySummary = parts.isEmpty
                ? String(localized: "Medication: \(name)")
                : String(localized: "Medication: \(name), \(parts.joined(separator: ", "))")

        case let .vital(type, value, secondary):
            icon = type.systemImage
            tint = .blue
            typeLabel = String(localized: "Vital · \(type.displayName)")
            primaryText = Self.vitalValueText(type: type, value: value, secondary: secondary)
            detailLines = []
            accessibilitySummary = String(localized: "Vital, \(type.displayName): \(primaryText)")

        case let .symptom(name, severity):
            icon = "bandage.fill"
            tint = .orange
            typeLabel = String(localized: "Symptom")
            primaryText = name
            detailLines = [String(localized: "Severity \(severity) of 10")]
            accessibilitySummary = String(localized: "Symptom: \(name), severity \(severity) out of 10")

        case let .appointment(title, date):
            icon = "calendar"
            tint = .indigo
            typeLabel = String(localized: "Appointment")
            primaryText = title
            let formattedDate = date.formatted(date: .abbreviated, time: .shortened)
            detailLines = [formattedDate]
            accessibilitySummary = String(localized: "Appointment: \(title), \(formattedDate)")

        case let .reminder(title, time):
            icon = "bell.fill"
            tint = .purple
            typeLabel = String(localized: "Reminder")
            primaryText = title
            if let time {
                let formattedTime = time.formatted(date: .omitted, time: .shortened)
                detailLines = [formattedTime]
                accessibilitySummary = String(localized: "Reminder: \(title), \(formattedTime)")
            } else {
                detailLines = []
                accessibilitySummary = String(localized: "Reminder: \(title)")
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
