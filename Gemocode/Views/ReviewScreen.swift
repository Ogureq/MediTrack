import SwiftUI
import SwiftData

/// The detailed health review. Designed to be pushed onto any navigation
/// stack or hosted directly in a tab (wrapped in a NavigationStack).
struct ReviewScreen: View {
    @Query(sort: \MedicalReport.date, order: .reverse) private var reports: [MedicalReport]
    @Query private var vitals: [VitalSample]
    @Query private var medications: [Medication]
    @Query private var profiles: [HealthProfile]
    @Query(sort: \ScoreSnapshot.date) private var snapshots: [ScoreSnapshot]
    @Query private var symptoms: [SymptomEntry]
    @Query(sort: \Appointment.date) private var appointments: [Appointment]
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme

    @State private var aiReport: AIHealthReport?
    @State private var isGeneratingSummary = false
    @State private var aiError: String?
    @State private var showingAIChat = false
    @State private var showingPaywall = false
    @ObservedObject private var premiumStore = PremiumStore.shared
    // Observed so the AI card re-evaluates `AISummaryService.isConfigured`
    // the moment a key is added or removed in Profile — the Keychain itself
    // is invisible to SwiftUI.
    @ObservedObject private var aiConfig = AIConfigState.shared

    private var review: HealthReview {
        AnalysisEngine.generateReview(
            profile: profiles.first,
            reports: reports,
            vitals: vitals,
            medications: medications,
            symptoms: symptoms,
            appointments: appointments
        )
    }

    var body: some View {
        // One engine pass per render: `review` is a computed property that
        // runs the full AnalysisEngine, so every helper below takes this
        // local instead of touching the property again (same pattern as
        // DashboardView).
        let review = self.review
        return Group {
            if !review.hasData {
                ContentUnavailableView(
                    "No Data to Review",
                    systemImage: "heart.text.square",
                    description: Text("Add medical reports, lab results, or vitals and Gemocode will generate a detailed review of your health data.")
                )
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // Every card below has its implicit animation nulled
                        // out. Without this, an ambient transaction already in
                        // flight when this screen first appears (e.g. from the
                        // onboarding fullScreenCover dismissing, or from
                        // `premiumStore`/`aiConfig` publishing their
                        // asynchronously-loaded values moments after appear)
                        // gets inherited by these section insertions and animates
                        // them in from a stale/offset frame — which reads as the
                        // score header sliding under the nav title and a finding
                        // card momentarily double-drawn over the AI card below it.
                        // Nulling it makes each card render directly in its final,
                        // laid-out position with no animated insertion. The AI
                        // card's own "generating…" pulse is unaffected because it
                        // runs on a TimelineView (see `aiSummaryCard`) rather than
                        // a transaction-borne `withAnimation`.
                        headerCard(review: review)
                            .transaction { $0.animation = nil }
                        categoryBreakdown(review: review)
                            .transaction { $0.animation = nil }
                        // Also nulled, like every other card here — the
                        // generating-report pulse below is intentionally
                        // rebuilt on a TimelineView so it animates every
                        // frame regardless of this transaction, instead of
                        // relying on an ambient/withAnimation transaction
                        // this modifier would otherwise cancel.
                        aiSummaryCard(review: review)
                            .transaction { $0.animation = nil }
                        findingsGroup(String(localized: "Critical"), severity: .critical, findings: review.criticalFindings)
                            .transaction { $0.animation = nil }
                        findingsGroup(String(localized: "Needs Attention"), severity: .attention, findings: review.attentionFindings)
                            .transaction { $0.animation = nil }
                        findingsGroup(String(localized: "Informational"), severity: .info, findings: review.infoFindings)
                            .transaction { $0.animation = nil }
                        trendsCard(review: review)
                            .transaction { $0.animation = nil }
                        labValuesCard(review: review)
                            .transaction { $0.animation = nil }
                        disclaimerCard
                            .transaction { $0.animation = nil }
                    }
                    .padding()
                }
            }
        }
        .background(AmbientBackground().accessibilityHidden(true))
        .navigationTitle("Health Review")
        .toolbar {
            if review.hasData {
                Menu {
                    ShareLink(item: review.shareText) {
                        Label("Share as Text", systemImage: "text.alignleft")
                    }
                    ShareLink(
                        item: ReviewPDF(review: review),
                        preview: SharePreview("Gemocode Health Review", image: Image(systemName: "doc.richtext"))
                    ) {
                        Label("Export as PDF", systemImage: "doc.richtext")
                    }
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .accessibilityLabel("Share health review")
            }
        }
        .task(id: review.score) { recordSnapshot(review: review) }
        .sheet(isPresented: $showingAIChat) {
            AIChatView(review: review, profileSummary: aiProfileSummary ?? "")
        }
        .sheet(isPresented: $showingPaywall) {
            PaywallView()
        }
    }

    /// Keeps one score snapshot per day so the dashboard can chart history.
    private func recordSnapshot(review current: HealthReview) {
        guard current.hasData else { return }
        if let last = snapshots.last, Calendar.current.isDate(last.date, inSameDayAs: .now) {
            if last.score != current.score {
                last.date = .now
                last.score = current.score
                last.criticalCount = current.criticalFindings.count
                last.attentionCount = current.attentionFindings.count
            }
        } else {
            let previousScore = snapshots.last?.score
            modelContext.insert(ScoreSnapshot(
                date: .now,
                score: current.score,
                criticalCount: current.criticalFindings.count,
                attentionCount: current.attentionFindings.count
            ))
            notifyScoreChangeIfNeeded(previousScore: previousScore, newScore: current.score)
        }

        // Mirror the latest score onto the home-screen widget. Uses the
        // vitals already queried by this screen — no extra fetching.
        let widgetVitals: [WidgetVital] = Dictionary(grouping: vitals, by: \.type)
            .compactMap { _, samples in samples.max(by: { $0.date < $1.date }) }
            .sorted { $0.date > $1.date }
            .prefix(3)
            .map { sample in
                WidgetVital(name: sample.type.displayName, value: sample.formattedValue, systemImage: sample.type.systemImage)
            }
        WidgetBridge.update(score: current.score, headline: current.scoreLabel, vitals: widgetVitals)
    }

    /// Notifies the user when a freshly *inserted* snapshot's score moved by
    /// at least 5 points from the prior snapshot. Only called from the
    /// "new day, new snapshot" branch of `recordSnapshot()` above, so this
    /// fires at most once per inserted snapshot — never on an in-place
    /// same-day update, and never when there's no prior snapshot or the
    /// score is unchanged / shifts by less than 5 points.
    private func notifyScoreChangeIfNeeded(previousScore: Int?, newScore: Int) {
        guard let previousScore, abs(newScore - previousScore) >= 5 else { return }
        Task {
            guard await NotificationService.requestAuthorization() else { return }
            NotificationService.scheduleOneTime(
                id: "scoreChange-\(UUID().uuidString)",
                title: String(localized: "Health Score Update"),
                body: String(format: String(localized: "Your health score changed: %lld → %lld"), previousScore, newScore),
                at: Date().addingTimeInterval(5)
            )
        }
    }

    // MARK: Cards

    /// Flat score header: a large tight-tracking number and a status tag —
    /// no ring, no card. Matches the mockup's flush treatment; the score
    /// header is deliberately the one section on this screen without a
    /// bordered container.
    private func headerCard(review: HealthReview) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("\(review.score)")
                    .font(.system(size: 64, weight: .regular))
                    .tracking(-2.56)
                    .foregroundStyle(Editorial.ink(colorScheme))
                EditorialTag(verbatim: review.scoreLabel, kind: scoreTagKind(review.score))
            }
            Text(review.summary)
                .font(.system(size: 13))
                .foregroundStyle(Editorial.muted(colorScheme))
            Text("Generated \(review.generatedAt.formatted(date: .abbreviated, time: .shortened))")
                .font(.system(size: 11))
                .foregroundStyle(Editorial.muted(colorScheme))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    /// Maps the engine's numeric score to a tag color using the exact same
    /// tier boundaries `HealthReview.scoreLabel` already uses — purely a
    /// presentation choice, no new scoring logic.
    private func scoreTagKind(_ score: Int) -> TagKind {
        switch score {
        case 75...100: .good
        case 40..<75: .warn
        default: .bad
        }
    }

    /// Category breakdown ledger: `Finding.category` grouping (already
    /// computed by the engine, just never surfaced in the UI before) shown
    /// as ledger rows — name, worst-severity tag, and a bar whose fill
    /// tracks the share of that category's findings that need attention.
    /// There's no per-category numeric score in `HealthReview` (only one
    /// overall `score`), so unlike the mockup's illustrative 0–100 numbers,
    /// this bar is a "how much of this category is flagged" fraction, not a
    /// sub-score — the closest honest analog available from real data.
    @ViewBuilder
    private func categoryBreakdown(review: HealthReview) -> some View {
        let groups = categoryGroups(for: review)
        if !groups.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                MicroLabel("By Category")
                VStack(spacing: 0) {
                    ForEach(groups, id: \.category.rawValue) { group in
                        categoryRow(group)
                    }
                }
            }
        }
    }

    private struct FindingCategoryGroup {
        let category: FindingCategory
        let findings: [Finding]
    }

    private func categoryGroups(for review: HealthReview) -> [FindingCategoryGroup] {
        let order: [FindingCategory] = [.labs, .vitals, .trends, .medications, .general]
        return order.compactMap { category in
            let matches = review.findings.filter { $0.category == category }
            return matches.isEmpty ? nil : FindingCategoryGroup(category: category, findings: matches)
        }
    }

    private func categoryDisplayName(_ category: FindingCategory) -> String {
        switch category {
        case .labs: String(localized: "Lab Results")
        case .vitals: String(localized: "Vitals")
        case .trends: String(localized: "Trends")
        case .medications: String(localized: "Medications")
        case .general: String(localized: "General")
        }
    }

    private func tagKind(for severity: Severity) -> TagKind {
        switch severity {
        case .critical: .bad
        case .attention: .warn
        case .info: .good
        }
    }

    private func categoryRow(_ group: FindingCategoryGroup) -> some View {
        let worst = group.findings.map(\.severity).max() ?? .info
        let concerningCount = group.findings.filter { $0.severity != .info }.count
        let fraction: CGFloat = group.findings.isEmpty ? 0 : CGFloat(concerningCount) / CGFloat(group.findings.count)
        let zones: [(fraction: CGFloat, kind: RangeZoneKind)] = {
            if fraction <= 0 { return [(fraction: 1, kind: .inRange)] }
            if fraction >= 1 { return [(fraction: 1, kind: .out)] }
            return [(fraction: fraction, kind: .out), (fraction: 1 - fraction, kind: .inRange)]
        }()
        let topFinding = group.findings.max(by: { $0.severity < $1.severity })

        return VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: categoryDisplayName(group.category))
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Editorial.ink(colorScheme))
                Spacer()
                EditorialTag(verbatim: worst.displayName, kind: tagKind(for: worst))
            }
            RangeBar(zones: zones, marker: fraction)
                .background(Capsule().fill(Editorial.hairline(colorScheme)))
            if let topFinding {
                Text(verbatim: categoryDetailText(topFinding, totalCount: group.findings.count))
                    .font(.system(size: 11))
                    .foregroundStyle(Editorial.muted(colorScheme))
                    .lineLimit(2)
            }
        }
        .ledgerRow()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(categoryAccessibilityLabel(group, worst: worst, detail: topFinding))
    }

    private func categoryDetailText(_ finding: Finding, totalCount: Int) -> String {
        guard totalCount > 1 else { return finding.detail }
        return "\(finding.detail) \(String(format: String(localized: "and %lld more"), totalCount - 1))"
    }

    private func categoryAccessibilityLabel(_ group: FindingCategoryGroup, worst: Severity, detail: Finding?) -> String {
        var text = "\(categoryDisplayName(group.category)), \(worst.displayName)"
        if let detail {
            text += ". \(detail.detail)"
        }
        return text
    }

    @ViewBuilder
    private func aiSummaryCard(review: HealthReview) -> some View {
        if AISummaryService.isConfigured {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("AI Health Analyst", systemImage: "sparkles")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Glass.accentGradient)
                    Spacer()
                    if isGeneratingSummary {
                        ProgressView()
                    }
                }
                if isGeneratingSummary {
                    // Driven by TimelineView rather than `withAnimation` +
                    // `@State` so the pulse keeps animating every frame even
                    // though `aiSummaryCard`'s call site nulls its enclosing
                    // transaction (see the comment on that call site) — a
                    // transaction-borne animation would otherwise be
                    // cancelled the instant it started.
                    TimelineView(.animation) { timeline in
                        Text("Generating your report…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .opacity(0.6 + 0.4 * abs(sin(timeline.date.timeIntervalSinceReferenceDate * 2)))
                    }
                }
                if let aiReport {
                    aiReportContent(aiReport)
                } else if let aiError {
                    Text(aiError)
                        .font(.caption)
                        .foregroundStyle(Editorial.tagBad(colorScheme))
                }
                if aiReport == nil && !isGeneratingSummary {
                    if AIReportQuota.canGenerate(isPremium: premiumStore.isPremium, defaults: .standard) {
                        Button {
                            generateAISummary(review: review)
                        } label: {
                            Label("Generate AI Health Analyst Report", systemImage: "sparkles")
                        }
                        .buttonStyle(GlassProminentButtonStyle())
                        .disabled(isGeneratingSummary)
                        if !premiumStore.isPremium {
                            Text("Your first AI report is free — Premium unlocks unlimited.")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    } else {
                        Button {
                            showingPaywall = true
                        } label: {
                            Label("Unlock unlimited AI reports", systemImage: "crown")
                        }
                        .buttonStyle(GlassProminentButtonStyle())
                        Text("You've used your free AI report. Every tracking feature stays free forever.")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                if premiumStore.isPremium {
                    Button {
                        showingAIChat = true
                    } label: {
                        Label("Ask about this report", systemImage: "bubble.left.and.text.bubble.right")
                    }
                    .buttonStyle(OutlinedPillButtonStyle())
                } else {
                    Button {
                        showingPaywall = true
                    } label: {
                        Label("Ask about this report", systemImage: "lock.fill")
                    }
                    .buttonStyle(OutlinedPillButtonStyle())
                    .accessibilityHint("Chat about your report is a Premium feature. Opens the upgrade screen.")
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard()
        }
    }

    /// Renders a verified `AIHealthReport`: an overview paragraph, each
    /// section as a titled block, and the doctor questions as a checklist —
    /// all inside the AI Summary card. On fallback (an `aiError` instead)
    /// today's plain error text is shown unchanged, above.
    @ViewBuilder
    private func aiReportContent(_ report: AIHealthReport) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(report.overview)
                .font(.subheadline)

            ForEach(Array(report.sections.enumerated()), id: \.offset) { _, section in
                VStack(alignment: .leading, spacing: 4) {
                    Text(section.title)
                        .font(.subheadline.weight(.semibold))
                    Text(section.body)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            }

            if !report.doctorQuestions.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Questions for Your Doctor")
                        .font(.subheadline.weight(.semibold))
                    ForEach(Array(report.doctorQuestions.enumerated()), id: \.offset) { _, question in
                        Label(question, systemImage: "checkmark.circle")
                            .font(.subheadline)
                    }
                }
            }

            Text("Generated by Claude — informational only, not medical advice.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    /// A short, caller-built profile description ("42-year-old male;
    /// conditions: hypertension") sent alongside the structured review so
    /// the AI report can be personalized without the model ever seeing raw
    /// profile records.
    private var aiProfileSummary: String? {
        guard let profile = profiles.first else { return nil }
        var parts: [String] = []
        if let age = profile.age {
            parts.append("\(age)-year-old")
        }
        if profile.sex != .unspecified {
            parts.append(profile.sex.displayName.lowercased())
        }
        if !profile.conditions.isEmpty {
            parts.append("conditions: \(profile.conditions)")
        }
        if !profile.allergies.isEmpty {
            parts.append("allergies: \(profile.allergies)")
        }
        return parts.isEmpty ? nil : parts.joined(separator: "; ")
    }

    /// Optional plain-text facts about how the score has moved since the
    /// previous recorded snapshot. Kept separate from `HealthReview` so the
    /// AI report API stays small — most callers won't have this handy.
    private var aiScoreDeltas: [String] {
        guard snapshots.count >= 2 else { return [] }
        let previous = snapshots[snapshots.count - 2]
        let latest = snapshots[snapshots.count - 1]
        guard previous.score != latest.score else { return [] }
        return ["Health score changed from \(previous.score) to \(latest.score) since the previous review."]
    }

    private func generateAISummary(review: HealthReview) {
        guard !isGeneratingSummary else { return }
        isGeneratingSummary = true
        aiError = nil
        let current = review  // the caller's already-computed pass
        let profileSummary = aiProfileSummary
        let deltas = aiScoreDeltas
        Task {
            do {
                aiReport = try await AISummaryService.generateReport(
                    review: current,
                    profileSummary: profileSummary,
                    deltas: deltas
                )
                Haptics.success()
                // A free report is only spent when generation succeeds —
                // failed or refused calls never count against the quota.
                // Entitlements load asynchronously on cold launch, so make
                // sure they're resolved before deciding this user is free:
                // a paying subscriber must never burn the trial report.
                await premiumStore.ensureEntitlementsLoaded()
                if !premiumStore.isPremium {
                    AIReportQuota.recordUse(defaults: .standard)
                }
            } catch {
                aiError = error.localizedDescription
            }
            isGeneratingSummary = false
        }
    }

    @ViewBuilder
    private func findingsGroup(_ title: String, severity: Severity, findings: [Finding]) -> some View {
        if !findings.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                MicroLabel(verbatim: "\(title) · \(findings.count)")
                VStack(spacing: 0) {
                    ForEach(findings) { finding in
                        FindingRow(finding: finding)
                            .ledgerRow()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func trendsCard(review: HealthReview) -> some View {
        if !review.trends.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                MicroLabel("Trends")
                VStack(spacing: 0) {
                    ForEach(Array(review.trends.enumerated()), id: \.element.id) { _, trend in
                        trendRow(trend)
                            .ledgerRow()
                    }
                }
                .padding()
                .glassCard()
            }
        }
    }

    private func trendRow(_ trend: TrendInsight) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                Text(trend.metricName)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Editorial.ink(colorScheme))
                Spacer()
                trendTag(trend.direction)
            }
            Text(trend.detail)
                .font(.system(size: 12))
                .foregroundStyle(Editorial.muted(colorScheme))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    /// Only `.improving`/`.worsening` read as clearly good/bad, so only
    /// those get a colored tag; `.stable`/`.rising`/`.falling` are
    /// direction-neutral and render as plain muted text instead (same
    /// "no forced tag for a neutral state" rule the schedule's Upcoming
    /// rows use).
    @ViewBuilder
    private func trendTag(_ direction: TrendDirection) -> some View {
        switch direction {
        case .improving:
            EditorialTag(verbatim: direction.displayName, kind: .good)
        case .worsening:
            EditorialTag(verbatim: direction.displayName, kind: .bad)
        case .stable, .rising, .falling:
            Text(direction.displayName)
                .font(.system(size: 12))
                .foregroundStyle(Editorial.muted(colorScheme))
        }
    }

    @ViewBuilder
    private func labValuesCard(review: HealthReview) -> some View {
        if !review.labSnapshots.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                MicroLabel("Latest Lab Values")
                VStack(spacing: 0) {
                    ForEach(Array(review.labSnapshots.enumerated()), id: \.element.id) { _, snapshot in
                        labRow(snapshot)
                            .ledgerRow()
                    }
                }
                .padding()
                .glassCard()
            }
        }
    }

    private func labRow(_ snapshot: LabSnapshot) -> some View {
        NavigationLink {
            LabDetailView(seriesKey: snapshot.id)
        } label: {
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(snapshot.name)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Editorial.ink(colorScheme))
                        Text(snapshot.date.formatted(date: .abbreviated, time: .omitted))
                            .font(.system(size: 11))
                            .foregroundStyle(Editorial.muted(colorScheme))
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 3) {
                        Text("\(snapshot.value.compactFormatted) \(snapshot.unit)")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Editorial.ink(colorScheme))
                        labStatusBadge(snapshot.status)
                    }
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Editorial.muted(colorScheme))
                        .accessibilityHidden(true)
                }
                labRangeBar(snapshot)
            }
            .accessibilityElement(children: .combine)
        }
        .buttonStyle(.plain)
    }

    /// A colored tag for a definite status, plain muted text for
    /// `.unknown` (no reference range to judge against — not a "good"
    /// result, just an unjudged one, so it doesn't get a green tag).
    @ViewBuilder
    private func labStatusBadge(_ status: LabStatus) -> some View {
        switch status {
        case .criticalLow, .criticalHigh:
            EditorialTag(verbatim: status.label, kind: .bad)
        case .low, .high:
            EditorialTag(verbatim: status.label, kind: .warn)
        case .normal:
            EditorialTag(verbatim: status.label, kind: .good)
        case .unknown:
            Text(status.label)
                .font(.system(size: 11))
                .foregroundStyle(Editorial.muted(colorScheme))
        }
    }

    /// The lab row's range bar: the reference range as the in-range zone,
    /// padded on both sides for the out-of-range zones, with the marker at
    /// the latest value. Omitted when there's no reference range to plot
    /// against (nothing invented in its place).
    @ViewBuilder
    private func labRangeBar(_ snapshot: LabSnapshot) -> some View {
        if let range = snapshot.range, range.upperBound > range.lowerBound {
            let span = range.upperBound - range.lowerBound
            let padding = span * 0.4
            let baseMin = range.lowerBound - padding
            let baseMax = range.upperBound + padding
            let axisMin = snapshot.value < baseMin ? snapshot.value - padding * 0.2 : baseMin
            let axisMax = snapshot.value > baseMax ? snapshot.value + padding * 0.2 : baseMax
            RangeBar(lower: range.lowerBound, upper: range.upperBound, min: axisMin, max: axisMax, value: snapshot.value)
        }
    }

    private var disclaimerCard: some View {
        Text(HealthReview.disclaimer)
            .font(.system(size: 11))
            .foregroundStyle(Editorial.muted(colorScheme))
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard(cornerRadius: 16)
    }
}

struct FindingRow: View {
    let finding: Finding

    @Environment(\.colorScheme) private var colorScheme

    private var accessibilitySummary: String {
        var text = "\(finding.severity.displayName): \(finding.title). \(finding.detail)"
        if let recommendation = finding.recommendation {
            text += String(format: String(localized: " Recommended: %@"), recommendation)
        }
        return text
    }

    private var tagKind: TagKind {
        switch finding.severity {
        case .critical: .bad
        case .attention: .warn
        case .info: .good
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(finding.title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Editorial.ink(colorScheme))
                Spacer()
                EditorialTag(verbatim: finding.severity.displayName, kind: tagKind)
            }
            Text(finding.detail)
                .font(.system(size: 13))
                .foregroundStyle(Editorial.muted(colorScheme))
            if let recommendation = finding.recommendation {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: "arrow.turn.down.right")
                        .font(.system(size: 11))
                        .foregroundStyle(Editorial.muted(colorScheme))
                        .accessibilityHidden(true)
                    Text(recommendation)
                        .font(.system(size: 13))
                        .foregroundStyle(Editorial.ink(colorScheme))
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }
}
