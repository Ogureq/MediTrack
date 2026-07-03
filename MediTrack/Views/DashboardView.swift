import SwiftUI
import SwiftData

struct DashboardView: View {
    @Query(sort: \MedicalReport.date, order: .reverse) private var reports: [MedicalReport]
    @Query private var vitals: [VitalSample]
    @Query private var medications: [Medication]
    @Query private var profiles: [HealthProfile]

    @State private var showingAddReport = false
    @State private var showingAddVital = false

    private var review: HealthReview {
        AnalysisEngine.generateReview(
            profile: profiles.first,
            reports: reports,
            vitals: vitals,
            medications: medications
        )
    }

    private var navigationTitle: String {
        let name = profiles.first?.name.trimmingCharacters(in: .whitespaces) ?? ""
        guard let firstName = name.components(separatedBy: " ").first, !firstName.isEmpty else {
            return "Dashboard"
        }
        return "Hi, \(firstName)"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if review.hasData {
                        scoreCard
                        alertsSection
                        vitalsGrid
                        recentReportsSection
                    } else {
                        emptyState
                    }
                }
                .padding()
            }
            .navigationTitle(navigationTitle)
            .toolbar {
                Menu {
                    Button {
                        showingAddReport = true
                    } label: {
                        Label("Add Report", systemImage: "doc.badge.plus")
                    }
                    Button {
                        showingAddVital = true
                    } label: {
                        Label("Add Vital", systemImage: "waveform.path.ecg")
                    }
                } label: {
                    Image(systemName: "plus")
                }
            }
            .sheet(isPresented: $showingAddReport) { AddReportView() }
            .sheet(isPresented: $showingAddVital) { AddVitalSheet() }
        }
    }

    // MARK: Sections

    private var scoreCard: some View {
        NavigationLink {
            ReviewScreen()
        } label: {
            HStack(spacing: 16) {
                ScoreRing(score: review.score)
                    .frame(width: 84, height: 84)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Health Score")
                        .font(.headline)
                    Text(review.scoreLabel)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text("Tap for your detailed review")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding()
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var alertsSection: some View {
        let alerts = review.findings.filter { $0.severity > .info }.prefix(3)
        if !alerts.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Needs Your Attention")
                    .font(.headline)
                ForEach(Array(alerts)) { finding in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: finding.severity.systemImage)
                            .foregroundStyle(finding.severity.color)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(finding.title)
                                .font(.subheadline.weight(.semibold))
                            Text(finding.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(3)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(finding.severity.color.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }

    @ViewBuilder
    private var vitalsGrid: some View {
        let tiles = VitalType.allCases.compactMap { type -> (VitalType, VitalSample)? in
            guard let latest = vitals.filter({ $0.type == type }).max(by: { $0.date < $1.date }) else {
                return nil
            }
            return (type, latest)
        }
        if !tiles.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Latest Vitals")
                    .font(.headline)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    ForEach(tiles, id: \.0) { type, sample in
                        NavigationLink {
                            VitalsView(initialType: type)
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Label(type.displayName, systemImage: type.systemImage)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                Text(sample.formattedValue)
                                    .font(.title3.bold())
                                Text(sample.date.formatted(date: .abbreviated, time: .omitted))
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var recentReportsSection: some View {
        if !reports.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Recent Reports")
                    .font(.headline)
                ForEach(reports.prefix(3)) { report in
                    NavigationLink {
                        ReportDetailView(report: report)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: report.category.systemImage)
                                .foregroundStyle(Color.accentColor)
                                .frame(width: 36, height: 36)
                                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(report.title)
                                    .font(.subheadline.weight(.semibold))
                                    .lineLimit(1)
                                Text(report.date.formatted(date: .abbreviated, time: .omitted))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(12)
                        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            ContentUnavailableView(
                "Welcome to MediTrack",
                systemImage: "heart.text.square",
                description: Text("Track your medical reports, lab results, vitals and medications — and get a detailed review of your health data. Everything stays on your device.")
            )
            HStack {
                Button {
                    showingAddReport = true
                } label: {
                    Label("Add Report", systemImage: "doc.badge.plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                Button {
                    showingAddVital = true
                } label: {
                    Label("Add Vital", systemImage: "waveform.path.ecg")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.top, 40)
    }
}

struct ScoreRing: View {
    let score: Int

    private var ringColor: Color {
        switch score {
        case 75...: .green
        case 60..<75: .yellow
        case 40..<60: .orange
        default: .red
        }
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color(.systemGray5), lineWidth: 10)
            Circle()
                .trim(from: 0, to: max(0.02, CGFloat(score) / 100))
                .stroke(ringColor, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text("\(score)")
                    .font(.title2.bold())
                Text("of 100")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
