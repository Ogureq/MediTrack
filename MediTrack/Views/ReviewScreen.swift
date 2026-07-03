import SwiftUI
import SwiftData

/// The detailed health review. Designed to be pushed onto any navigation
/// stack or hosted directly in a tab (wrapped in a NavigationStack).
struct ReviewScreen: View {
    @Query(sort: \MedicalReport.date, order: .reverse) private var reports: [MedicalReport]
    @Query private var vitals: [VitalSample]
    @Query private var medications: [Medication]
    @Query private var profiles: [HealthProfile]

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
                reviewList
            }
        }
        .navigationTitle("Health Review")
        .toolbar {
            if review.hasData {
                ShareLink(item: review.shareText) {
                    Image(systemName: "square.and.arrow.up")
                }
            }
        }
    }

    private var reviewList: some View {
        List {
            Section {
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
                }
                .padding(.vertical, 4)
                Text(review.summary)
                    .font(.subheadline)
            }

            if !review.criticalFindings.isEmpty {
                Section {
                    ForEach(review.criticalFindings) { finding in
                        FindingRow(finding: finding)
                    }
                } header: {
                    Label("Critical", systemImage: Severity.critical.systemImage)
                        .foregroundStyle(Severity.critical.color)
                }
            }

            if !review.attentionFindings.isEmpty {
                Section {
                    ForEach(review.attentionFindings) { finding in
                        FindingRow(finding: finding)
                    }
                } header: {
                    Label("Needs Attention", systemImage: Severity.attention.systemImage)
                        .foregroundStyle(Severity.attention.color)
                }
            }

            if !review.infoFindings.isEmpty {
                Section {
                    ForEach(review.infoFindings) { finding in
                        FindingRow(finding: finding)
                    }
                } header: {
                    Label("Informational", systemImage: Severity.info.systemImage)
                        .foregroundStyle(Severity.info.color)
                }
            }

            if !review.trends.isEmpty {
                Section("Trends") {
                    ForEach(review.trends) { trend in
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
                        .padding(.vertical, 2)
                    }
                }
            }

            if !review.labSnapshots.isEmpty {
                Section("Latest Lab Values") {
                    ForEach(review.labSnapshots) { snapshot in
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
            }

            Section {
                Text(HealthReview.disclaimer)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
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
        .padding(.vertical, 2)
    }
}
