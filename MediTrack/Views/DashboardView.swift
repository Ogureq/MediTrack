import SwiftUI
import SwiftData
import Charts

struct DashboardView: View {
    @Query(sort: \MedicalReport.date, order: .reverse) private var reports: [MedicalReport]
    @Query private var vitals: [VitalSample]
    @Query private var medications: [Medication]
    @Query private var profiles: [HealthProfile]
    @Query(sort: \ScoreSnapshot.date) private var snapshots: [ScoreSnapshot]
    @Query private var symptoms: [SymptomEntry]
    @Query(sort: \Appointment.date) private var appointments: [Appointment]

    @State private var showingAddReport = false
    @State private var showingAddVital = false

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

    private var nextAppointment: Appointment? {
        appointments.first(where: \.isUpcoming)
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
                    Text(Date.now.formatted(date: .complete, time: .omitted))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                    if review.hasData {
                        scoreCard
                        scoreHistoryCard
                        alertsSection
                        appointmentCard
                        vitalsGrid
                        recentReportsSection
                    } else {
                        emptyState
                    }
                }
                .padding()
            }
            .background(AmbientBackground())
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
            .glassCard()
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var scoreHistoryCard: some View {
        if snapshots.count >= 2 {
            VStack(alignment: .leading, spacing: 8) {
                Text("Score History")
                    .font(.headline)
                Chart(snapshots) { snapshot in
                    AreaMark(
                        x: .value("Date", snapshot.date),
                        y: .value("Score", snapshot.score)
                    )
                    .interpolationMethod(.monotone)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.teal.opacity(0.35), .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    LineMark(
                        x: .value("Date", snapshot.date),
                        y: .value("Score", snapshot.score)
                    )
                    .interpolationMethod(.monotone)
                    .foregroundStyle(Glass.accentGradient)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                }
                .chartYScale(domain: 0...100)
                .frame(height: 110)
                .padding()
                .glassCard(cornerRadius: 16)
            }
        }
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
                    .tintedGlassCard(finding.severity.color)
                }
            }
        }
    }

    @ViewBuilder
    private var appointmentCard: some View {
        if let next = nextAppointment {
            VStack(alignment: .leading, spacing: 8) {
                Text("Next Appointment")
                    .font(.headline)
                NavigationLink {
                    AppointmentsView()
                } label: {
                    HStack(spacing: 12) {
                        VStack(spacing: 0) {
                            Text(next.date.formatted(.dateTime.month(.abbreviated)))
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text(next.date.formatted(.dateTime.day()))
                                .font(.title3.bold())
                                .foregroundStyle(Color.accentColor)
                        }
                        .frame(width: 44, height: 44)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(Glass.bevelStroke, lineWidth: 1)
                        )
                        VStack(alignment: .leading, spacing: 2) {
                            Text(next.title)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                            Text(next.date.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(12)
                    .glassCard(cornerRadius: 16)
                }
                .buttonStyle(.plain)
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
                            .glassCard(cornerRadius: 16)
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
                                .foregroundStyle(Glass.accentGradient)
                                .frame(width: 36, height: 36)
                                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .strokeBorder(Glass.bevelStroke, lineWidth: 1)
                                )
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
                        .glassCard(cornerRadius: 16)
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
            HStack(spacing: 12) {
                Button {
                    showingAddReport = true
                } label: {
                    Label("Add Report", systemImage: "doc.badge.plus")
                }
                .buttonStyle(GlassProminentButtonStyle())
                Button {
                    showingAddVital = true
                } label: {
                    Label("Add Vital", systemImage: "waveform.path.ecg")
                }
                .buttonStyle(GlassButtonStyle())
            }
        }
        .padding(20)
        .glassCard()
        .padding(.top, 32)
    }
}

struct ScoreRing: View {
    let score: Int

    @State private var progress: CGFloat = 0

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
                .stroke(Color.primary.opacity(0.08), lineWidth: 10)
            Circle()
                .trim(from: 0, to: max(0.02, progress))
                .stroke(
                    AngularGradient(
                        gradient: Gradient(colors: [ringColor.opacity(0.45), ringColor]),
                        center: .center,
                        startAngle: .degrees(0),
                        endAngle: .degrees(360 * Double(score) / 100)
                    ),
                    style: StrokeStyle(lineWidth: 10, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .shadow(color: ringColor.opacity(0.55), radius: 6)
            VStack(spacing: 0) {
                Text("\(score)")
                    .font(.title2.bold())
                    .contentTransition(.numericText())
                Text("of 100")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.9)) {
                progress = CGFloat(score) / 100
            }
        }
        .onChange(of: score) { _, newScore in
            withAnimation(.easeOut(duration: 0.6)) {
                progress = CGFloat(newScore) / 100
            }
        }
    }
}
