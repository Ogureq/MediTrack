import SwiftUI
import SwiftData

/// The Quarterly Health Review ritual: a guided, read-only recap of the last
/// ~90 days built entirely from `QuarterlyReview.build(...)` — deterministic,
/// on-device, no AI. Presented as a large-detent sheet from `DashboardView`
/// when `QuarterlyReview.isDue(...)` is true.
struct QuarterlyReviewView: View {
    @Environment(\.dismiss) private var dismiss

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
                    scoreTrajectoryCard
                    whatChangedSection
                    winsCard
                    doctorQuestionsCard
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
                Text("Score Trajectory")
                    .font(.headline)
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
                Text("Score Trajectory")
                    .font(.headline)
                Text("Only one score reading this quarter (\(onlyScore)) — trends will show once there's another to compare.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard()
        }
    }

    private func scoreBubble(label: String, value: Int) -> some View {
        VStack(spacing: 2) {
            Text("\(value)")
                .font(.title2.bold())
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(width: 64, height: 64)
        .background(.ultraThinMaterial, in: Circle())
        .overlay(Circle().strokeBorder(Glass.bevelStroke, lineWidth: 1))
    }

    private var deltaColor: Color {
        guard let scoreDelta = summary.scoreDelta else { return .secondary }
        if scoreDelta > 0 { return .teal }
        if scoreDelta < 0 { return .orange }
        return .secondary
    }

    private var deltaSystemImage: String {
        guard let scoreDelta = summary.scoreDelta else { return "arrow.right.circle.fill" }
        if scoreDelta > 0 { return "arrow.up.right.circle.fill" }
        if scoreDelta < 0 { return "arrow.down.right.circle.fill" }
        return "equal.circle.fill"
    }

    private func scoreTrajectoryAccessibilityLabel(startScore: Int, endScore: Int) -> String {
        var text = "Health score went from \(startScore) to \(endScore)"
        if let scoreDelta = summary.scoreDelta {
            text += scoreDelta == 0 ? ", unchanged" : ", a change of \(scoreDelta >= 0 ? "+" : "")\(scoreDelta) points"
        }
        return text
    }

    // MARK: What changed

    @ViewBuilder
    private var whatChangedSection: some View {
        if !summary.vitalChanges.isEmpty || !summary.labChanges.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("What Changed")
                    .font(.headline)
                VStack(spacing: 10) {
                    ForEach(Array(summary.vitalChanges.enumerated()), id: \.offset) { index, change in
                        if index > 0 { Divider() }
                        ChangeRow(
                            title: change.type.displayName,
                            fromText: Units.formatted(change.firstValue, for: change.type),
                            toText: Units.formatted(change.lastValue, for: change.type),
                            direction: change.direction
                        )
                    }
                    if !summary.vitalChanges.isEmpty && !summary.labChanges.isEmpty {
                        Divider()
                    }
                    ForEach(Array(summary.labChanges.enumerated()), id: \.offset) { index, change in
                        if index > 0 { Divider() }
                        ChangeRow(
                            title: change.name,
                            fromText: "\(change.previousValue.compactFormatted) \(change.unit)",
                            toText: "\(change.latestValue.compactFormatted) \(change.unit)",
                            direction: change.direction
                        )
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
                Text("Wins")
                    .font(.headline)
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
            .tintedGlassCard(.teal, cornerRadius: Glass.cardRadius)
        }
    }

    // MARK: Questions for your doctor

    @ViewBuilder
    private var doctorQuestionsCard: some View {
        if !summary.doctorQuestions.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Questions for Your Doctor")
                    .font(.headline)
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(summary.doctorQuestions, id: \.self) { question in
                        Label(question, systemImage: "checkmark.circle")
                            .font(.subheadline)
                            .accessibilityElement(children: .combine)
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
            .font(.footnote)
            .foregroundStyle(.secondary)
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard(cornerRadius: 16)
    }

    private var doneButton: some View {
        Button {
            QuarterlyReview.markCompleted(now: .now, defaults: .standard)
            Haptics.success()
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
/// direction pill. Colors stay non-alarming — improved is teal, worsened is
/// orange (never red), and a metric with no clear better/worse semantic
/// (like weight) renders as a neutral "Changed" in secondary color.
private struct ChangeRow: View {
    let title: String
    let fromText: String
    let toText: String
    let direction: Direction

    private var color: Color {
        switch direction {
        case .improved: .teal
        case .worsened: .orange
        case .steady: .secondary
        }
    }

    private var systemImage: String {
        switch direction {
        case .improved: "checkmark.circle.fill"
        case .worsened: "exclamationmark.triangle.fill"
        case .steady: "minus.circle.fill"
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(color)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text("\(fromText) → \(toText)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(direction.label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(fromText) to \(toText), \(direction.label)")
    }
}

/// One "wins" checklist row: icon plus text, combined into a single
/// accessibility element.
private struct WinRow: View {
    let systemImage: String
    let text: String

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.subheadline.weight(.semibold))
            .accessibilityElement(children: .combine)
    }
}
