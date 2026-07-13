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

    @State private var aiReport: AIHealthReport?
    @State private var isGeneratingSummary = false
    @State private var isPulsing = false
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
        Group {
            if !review.hasData {
                ContentUnavailableView(
                    "No Data to Review",
                    systemImage: "heart.text.square",
                    description: Text("Add medical reports, lab results, or vitals and MediTrack will generate a detailed review of your health data.")
                )
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        headerCard
                        aiSummaryCard
                        findingsGroup("Critical", severity: .critical, findings: review.criticalFindings)
                        findingsGroup("Needs Attention", severity: .attention, findings: review.attentionFindings)
                        findingsGroup("Informational", severity: .info, findings: review.infoFindings)
                        trendsCard
                        labValuesCard
                        disclaimerCard
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
                        preview: SharePreview("MediTrack Health Review", image: Image(systemName: "doc.richtext"))
                    ) {
                        Label("Export as PDF", systemImage: "doc.richtext")
                    }
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .accessibilityLabel("Share health review")
            }
        }
        .task(id: review.score) { recordSnapshot() }
        .sheet(isPresented: $showingAIChat) {
            AIChatView(review: review, profileSummary: aiProfileSummary ?? "")
        }
        .sheet(isPresented: $showingPaywall) {
            PaywallView()
        }
    }

    /// Keeps one score snapshot per day so the dashboard can chart history.
    private func recordSnapshot() {
        guard review.hasData else { return }
        let current = review
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
                title: "Health Score Update",
                body: "Your health score changed: \(previousScore) → \(newScore)",
                at: Date().addingTimeInterval(5)
            )
        }
    }

    // MARK: Cards

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 16) {
                ScoreRing(score: review.score)
                    .frame(width: 92, height: 92)
                VStack(alignment: .leading, spacing: 4) {
                    Text(review.scoreLabel)
                        .font(.headline)
                    Text("Generated \(review.generatedAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            Text(review.summary)
                .font(.subheadline)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var aiSummaryCard: some View {
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
                    Text("Generating your report…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .opacity(isPulsing ? 1 : 0.6)
                        .onAppear {
                            withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
                                isPulsing = true
                            }
                        }
                        .onDisappear { isPulsing = false }
                }
                if let aiReport {
                    aiReportContent(aiReport)
                } else if let aiError {
                    Text(aiError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                if aiReport == nil && !isGeneratingSummary {
                    if AIReportQuota.canGenerate(isPremium: premiumStore.isPremium, defaults: .standard) {
                        Button {
                            generateAISummary()
                        } label: {
                            Label("Generate AI Health Analyst Report", systemImage: "sparkles")
                        }
                        .buttonStyle(GlassButtonStyle())
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
                        .buttonStyle(GlassButtonStyle())
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
                    .buttonStyle(GlassButtonStyle())
                } else {
                    Button {
                        showingPaywall = true
                    } label: {
                        Label("Ask about this report", systemImage: "lock.fill")
                    }
                    .buttonStyle(GlassButtonStyle())
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

    private func generateAISummary() {
        guard !isGeneratingSummary else { return }
        isGeneratingSummary = true
        aiError = nil
        let current = review
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
                Label(title, systemImage: severity.systemImage)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(severity.color)
                ForEach(findings) { finding in
                    FindingRow(finding: finding)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .tintedGlassCard(severity.color)
                }
            }
        }
    }

    @ViewBuilder
    private var trendsCard: some View {
        if !review.trends.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Trends")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                VStack(spacing: 10) {
                    ForEach(Array(review.trends.enumerated()), id: \.element.id) { index, trend in
                        if index > 0 {
                            Divider()
                        }
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: trend.direction.systemImage)
                                .foregroundStyle(trend.direction.color)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text(trend.metricName)
                                        .font(.subheadline.weight(.semibold))
                                    Spacer()
                                    Text(trend.direction.displayName)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(trend.direction.color)
                                }
                                Text(trend.detail)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityElement(children: .combine)
                    }
                }
                .padding()
                .glassCard()
            }
        }
    }

    @ViewBuilder
    private var labValuesCard: some View {
        if !review.labSnapshots.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Latest Lab Values")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                VStack(spacing: 10) {
                    ForEach(Array(review.labSnapshots.enumerated()), id: \.element.id) { index, snapshot in
                        if index > 0 {
                            Divider()
                        }
                        NavigationLink {
                            LabDetailView(seriesKey: snapshot.id)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(snapshot.name)
                                        .font(.subheadline)
                                    Text(snapshot.date.formatted(date: .abbreviated, time: .omitted))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 3) {
                                    Text("\(snapshot.value.compactFormatted) \(snapshot.unit)")
                                        .font(.subheadline.weight(.semibold))
                                    StatusPill(text: snapshot.status.label, color: snapshot.status.color)
                                }
                                Image(systemName: "chevron.right")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                                    .accessibilityHidden(true)
                            }
                            .accessibilityElement(children: .combine)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
                .glassCard()
            }
        }
    }

    private var disclaimerCard: some View {
        Text(HealthReview.disclaimer)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard(cornerRadius: 16)
    }
}

struct FindingRow: View {
    let finding: Finding

    private var accessibilitySummary: String {
        var text = "\(finding.severity.displayName): \(finding.title). \(finding.detail)"
        if let recommendation = finding.recommendation {
            text += " Recommended: \(recommendation)"
        }
        return text
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: finding.severity.systemImage)
                    .foregroundStyle(finding.severity.color)
                Text(finding.title)
                    .font(.subheadline.weight(.semibold))
            }
            Text(finding.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
            if let recommendation = finding.recommendation {
                Label(recommendation, systemImage: "arrow.turn.down.right")
                    .font(.caption)
                    .foregroundStyle(finding.severity.color)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }
}
