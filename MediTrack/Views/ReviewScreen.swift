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
    @Environment(\.modelContext) private var modelContext

    private var review: HealthReview {
        AnalysisEngine.generateReview(
            profile: profiles.first,
            reports: reports,
            vitals: vitals,
            medications: medications
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
        .background(AmbientBackground())
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
            }
        }
        .task(id: review.score) { recordSnapshot() }
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
            modelContext.insert(ScoreSnapshot(
                date: .now,
                score: current.score,
                criticalCount: current.criticalFindings.count,
                attentionCount: current.attentionFindings.count
            ))
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
                        }
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
    }
}
