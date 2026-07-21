import SwiftUI
import SwiftData
import StoreKit

/// The Quarterly Health Review ritual: a guided, read-only recap of the last
/// ~90 days built entirely from `QuarterlyReview.build(...)` — deterministic,
/// on-device, no AI. Presented as a large-detent sheet from `DashboardView`
/// when `QuarterlyReview.isDue(...)` is true.
struct QuarterlyReviewView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.requestReview) private var requestReview

    @Query(sort: \ScoreSnapshot.date) private var snapshots: [ScoreSnapshot]
    @Query private var vitals: [VitalSample]
    @Query private var labResults: [LabResult]
    @Query private var goals: [HealthGoal]
    @Query(sort: \Reminder.createdAt) private var reminders: [Reminder]
    @Query private var symptoms: [SymptomEntry]

    /// Cached once instead of being recomputed on every one of the ~19
    /// property accesses this screen makes into it per render. Starts as an
    /// empty-input build (a pure, deterministic call — no environment or
    /// `ModelContext` needed) so the first render already has something
    /// sensible to show, then `.task` immediately replaces it with the real
    /// recap built from the `@Query` results.
    @State private var summary = QuarterlyReview.build(
        snapshots: [], vitals: [], labResults: [], goals: [], reminders: [], symptoms: [],
        now: .now, calendar: .current
    )

    /// Cheap signature used to decide when to rebuild `summary` — mirrors
    /// the `.count`-based invalidation already used elsewhere in the app
    /// (e.g. `AIChatView`'s `onChange(of: messages.count)`).
    private var dataSignature: String {
        "\(snapshots.count)-\(vitals.count)-\(labResults.count)-\(goals.count)-\(reminders.count)-\(symptoms.count)"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    // Each card below populates from `.empty` placeholder
                    // content to the real recap via `.task(id: dataSignature)`
                    // while this sheet is still presenting — nulling the
                    // transaction keeps that population from inheriting an
                    // ambient animation and animating in from a stale frame,
                    // same reasoning as ReviewScreen's cards.
                    scoreTrajectoryCard
                        .transaction { $0.animation = nil }
                    whatChangedSection
                        .transaction { $0.animation = nil }
                    winsCard
                        .transaction { $0.animation = nil }
                    doctorQuestionsCard
                        .transaction { $0.animation = nil }
                    disclaimerCard
                    doneButton
                }
                .padding()
            }
            .background(AmbientBackground().accessibilityHidden(true))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    ShareLink(item: summary.shareText) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .accessibilityLabel("Share quarterly review")
                }
            }
        }
        .task(id: dataSignature) {
            summary = QuarterlyReview.build(
                snapshots: snapshots,
                vitals: vitals,
                labResults: labResults,
                goals: goals,
                reminders: reminders,
                symptoms: symptoms,
                now: .now,
                calendar: .current
            )
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(.ultraThinMaterial)
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(Glass.accentGradient)
                    .accessibilityHidden(true)
                Text("Your Quarterly Review")
                    .font(.title2.bold())
            }
            Text("\(summary.periodStart.formatted(date: .abbreviated, time: .omitted)) – \(summary.periodEnd.formatted(date: .abbreviated, time: .omitted))")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    // MARK: Score trajectory

    @ViewBuilder
    private var scoreTrajectoryCard: some View {
        if let startScore = summary.startScore, let endScore = summary.endScore {
            VStack(alignment: .leading, spacing: 10) {
                MicroLabel("Score Trajectory")
                HStack(spacing: 14) {
                    scoreBubble(label: "Then", value: startScore)
                    Image(systemName: deltaSystemImage)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(deltaColor)
                        .accessibilityHidden(true)
                    scoreBubble(label: "Now", value: endScore)
                    Spacer()
                    if let scoreDelta = summary.scoreDelta {
                        Text(scoreDelta >= 0 ? "+\(scoreDelta)" : "\(scoreDelta)")
                            .font(.title3.bold())
                            .foregroundStyle(deltaColor)
                            .contentTransition(.numericText())
                    }
                }
            }
            .padding()
            .glassCard()
            .accessibilityElement(children: .combine)
            .accessibilityLabel(scoreTrajectoryAccessibilityLabel(startScore: startScore, endScore: endScore))
        } else if let onlyScore = summary.startScore ?? summary.endScore {
            VStack(alignment: .leading, spacing: 6) {
                MicroLabel("Score Trajectory")
                Text("Only one score reading this quarter (\(onlyScore)) — trends will show once there's another to compare.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard()
        }
    }

    private func scoreBubble(label: LocalizedStringKey, value: Int) -> some View {
        VStack(spacing: 2) {
            Text("\(value)")
                .font(.title2.bold())
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(width: 64, height: 64)
        .background(.ultraThinMaterial, in: Circle())
        .overlay(Circle().strokeBorder(Glass.bevelStroke(for: colorScheme), lineWidth: 1))
    }

    /// Non-alarming by design (see `ChangeRow` below): a worsened score
    /// reads as `tagWarn`, never `tagBad` — this is a wellness recap, not a
    /// medical alert.
    private var deltaColor: Color {
        guard let scoreDelta = summary.scoreDelta else { return Editorial.muted(colorScheme) }
        if scoreDelta > 0 { return Editorial.tagGood(colorScheme) }
        if scoreDelta < 0 { return Editorial.tagWarn(colorScheme) }
        return Editorial.muted(colorScheme)
    }

    private var deltaSystemImage: String {
        guard let scoreDelta = summary.scoreDelta else { return "arrow.right.circle.fill" }
        if scoreDelta > 0 { return "arrow.up.right.circle.fill" }
        if scoreDelta < 0 { return "arrow.down.right.circle.fill" }
        return "equal.circle.fill"
    }

    private func scoreTrajectoryAccessibilityLabel(startScore: Int, endScore: Int) -> String {
        var text = String(format: String(localized: "Health score went from %lld to %lld"), startScore, endScore)
        if let scoreDelta = summary.scoreDelta {
            if scoreDelta == 0 {
                text += String(localized: ", unchanged")
            } else {
                text += String(format: String(localized: ", a change of %@%lld points"), scoreDelta >= 0 ? "+" : "", scoreDelta)
            }
        }
        return text
    }

    // MARK: What changed

    @ViewBuilder
    private var whatChangedSection: some View {
        if !summary.vitalChanges.isEmpty || !summary.labChanges.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                MicroLabel("What Changed")
                VStack(spacing: 0) {
                    ForEach(Array(summary.vitalChanges.enumerated()), id: \.offset) { _, change in
                        ChangeRow(
                            title: change.type.displayName,
                            fromText: Units.formatted(change.firstValue, for: change.type),
                            toText: Units.formatted(change.lastValue, for: change.type),
                            direction: change.direction
                        )
                        .ledgerRow()
                    }
                    ForEach(Array(summary.labChanges.enumerated()), id: \.offset) { _, change in
                        ChangeRow(
                            title: change.name,
                            fromText: "\(change.previousValue.compactFormatted) \(change.unit)",
                            toText: "\(change.latestValue.compactFormatted) \(change.unit)",
                            direction: change.direction
                        )
                        .ledgerRow()
                    }
                }
                .padding()
                .glassCard()
            }
        }
    }

    // MARK: Wins

    @ViewBuilder
    private var winsCard: some View {
        let hasStreak = summary.longestStreak >= 2
        let hasGoals = !summary.goalsAchieved.isEmpty
        let symptomFree = summary.symptomCount == 0
        if hasStreak || hasGoals || symptomFree {
            VStack(alignment: .leading, spacing: 10) {
                MicroLabel("Wins")
                VStack(alignment: .leading, spacing: 10) {
                    if hasStreak {
                        WinRow(
                            systemImage: "flame.fill",
                            text: "Longest reminder streak: \(summary.longestStreak) days"
                        )
                    }
                    ForEach(summary.goalsAchieved, id: \.self) { goal in
                        WinRow(systemImage: "target", text: "Goal achieved: \(goal)")
                    }
                    if symptomFree {
                        WinRow(systemImage: "checkmark.seal.fill", text: "No symptoms logged this quarter")
                    }
                }
            }
            .padding()
            .tintedGlassCard(Editorial.tagGood(colorScheme), cornerRadius: Glass.cardRadius)
        }
    }

    // MARK: Questions for your doctor

    @ViewBuilder
    private var doctorQuestionsCard: some View {
        if !summary.doctorQuestions.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                MicroLabel("Questions for Your Doctor")
                VStack(spacing: 0) {
                    ForEach(summary.doctorQuestions, id: \.self) { question in
                        Label(question, systemImage: "checkmark.circle")
                            .font(.subheadline)
                            .accessibilityElement(children: .combine)
                            .ledgerRow()
                    }
                }
                Text("These are prompts drawn from your own tracked numbers, not a diagnosis — bring them to your next visit.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .glassCard()
        }
    }

    // MARK: Footer

    private var disclaimerCard: some View {
        Text(QuarterlyReviewSummary.disclaimer)
            .font(.system(size: 11))
            .foregroundStyle(Editorial.muted(colorScheme))
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard(cornerRadius: 16)
    }

    private var doneButton: some View {
        Button {
            QuarterlyReview.markCompleted(now: .now, defaults: .standard)
            Haptics.success()
            // Peak-delight moment: a completed recap with real data behind
            // it. The system decides whether a prompt actually appears
            // (max 3/year, never twice for one version), so this can fire
            // every quarter — but skip data-empty first-week recaps, where
            // there's nothing to be delighted about yet.
            if !snapshots.isEmpty || !labResults.isEmpty {
                requestReview()
            }
            dismiss()
        } label: {
            Label("Done — see you next quarter", systemImage: "checkmark.circle.fill")
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(GlassProminentButtonStyle())
    }
}

// MARK: - Rows

/// One "what changed" row: a metric name, its before → after values, and a
/// direction badge. Colors stay non-alarming — improved is `tagGood`,
/// worsened is `tagWarn` (never `tagBad`/red), and a metric with no clear
/// better/worse semantic (like weight) renders as a neutral "Changed" in
/// muted text, with no tag at all.
private struct ChangeRow: View {
    let title: String
    let fromText: String
    let toText: String
    let direction: Direction

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Editorial.ink(colorScheme))
                Text("\(fromText) → \(toText)")
                    .font(.system(size: 12))
                    .foregroundStyle(Editorial.muted(colorScheme))
            }
            Spacer()
            directionBadge
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(fromText) to \(toText), \(direction.label)")
    }

    /// Non-alarming by design: `.improved` is the only tag-worthy state
    /// (`.good`). `.worsened` still never renders as `.bad`/red — this is a
    /// wellness recap, not a medical alert — so it gets `.warn` instead,
    /// same as the original orange. `.steady` (a metric with no clear
    /// better/worse semantic, like weight) stays plain muted text, matching
    /// the "no forced tag for a neutral state" rule used elsewhere in this
    /// redesign.
    @ViewBuilder
    private var directionBadge: some View {
        switch direction {
        case .improved:
            EditorialTag(verbatim: direction.label, kind: .good)
        case .worsened:
            EditorialTag(verbatim: direction.label, kind: .warn)
        case .steady:
            Text(direction.label)
                .font(.system(size: 12))
                .foregroundStyle(Editorial.muted(colorScheme))
        }
    }
}

/// One "wins" checklist row: icon plus text, combined into a single
/// accessibility element.
private struct WinRow: View {
    let systemImage: String
    let text: LocalizedStringKey

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.subheadline.weight(.semibold))
            .accessibilityElement(children: .combine)
    }
}
