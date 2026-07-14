import SwiftUI
import SwiftData
import Charts

struct DashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \MedicalReport.date, order: .reverse) private var reports: [MedicalReport]
    @Query private var vitals: [VitalSample]
    @Query private var medications: [Medication]
    @Query private var profiles: [HealthProfile]
    @Query(sort: \ScoreSnapshot.date) private var snapshots: [ScoreSnapshot]
    @Query private var symptoms: [SymptomEntry]
    @Query(sort: \Appointment.date) private var appointments: [Appointment]
    @Query private var goals: [HealthGoal]
    @Query(sort: \Reminder.createdAt) private var reminders: [Reminder]

    /// Switches the enclosing `TabView` to the Review tab when the score
    /// card is tapped — passed in from `ContentView`, which owns `AppTab`
    /// and already does the same thing for the widget's deep link. Defaults
    /// to a no-op so this view stays constructible without wiring a tab
    /// selection (e.g. in a preview).
    var onOpenReview: () -> Void = {}

    @State private var showingAddReport = false
    @State private var showingAddVital = false
    @State private var showingQuickAdd = false
    @State private var showingQuarterlyReview = false

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

    /// Earliest data point already fetched by this view — reused so the
    /// Quarterly Review "is it due" check needs no extra `@Query`. Also
    /// considers report and lab-result dates (not just snapshots/vitals) so
    /// a user who has only ever logged lab reports still gets credit for
    /// their history and sees the Quarterly Review card once it's due.
    private var earliestDataDate: Date? {
        let dates = [
            snapshots.first?.date,
            vitals.map(\.date).min(),
            reports.map(\.date).min(),
            reports.flatMap(\.labResults).map(\.date).min(),
        ].compactMap { $0 }
        return dates.min()
    }

    private var isQuarterlyReviewDue: Bool {
        QuarterlyReview.isDue(
            lastCompleted: QuarterlyReview.lastCompleted(defaults: .standard),
            earliestData: earliestDataDate,
            now: .now,
            calendar: .current
        )
    }

    /// Anonymous rollup stats for the shareable score card — counts and a
    /// trend direction only, never a name, date, or lab value. See
    /// `ScoreShareCard`. Takes the already-computed `review` so callers
    /// never trigger a second `AnalysisEngine.generateReview` pass.
    private func shareStats(review: HealthReview) -> [ShareStat] {
        var stats: [ShareStat] = []
        if !review.labSnapshots.isEmpty {
            let count = review.labSnapshots.count
            stats.append(ShareStat(systemImage: "testtube.2", text: "\(count) biomarker\(count == 1 ? "" : "s") tracked"))
        }
        stats.append(ShareStat(systemImage: shareTrendSystemImage(review: review), text: shareTrendText(review: review)))
        if !reports.isEmpty {
            stats.append(ShareStat(systemImage: "doc.text", text: "\(reports.count) report\(reports.count == 1 ? "" : "s") logged"))
        }
        return stats
    }

    private func shareTrendText(review: HealthReview) -> String {
        let worsening = review.trends.filter { $0.direction == .worsening }.count
        let improving = review.trends.filter { $0.direction == .improving }.count
        if worsening > improving { return "Trending down" }
        if improving > worsening { return "Trending up" }
        return "Trending steady"
    }

    private func shareTrendSystemImage(review: HealthReview) -> String {
        let worsening = review.trends.filter { $0.direction == .worsening }.count
        let improving = review.trends.filter { $0.direction == .improving }.count
        if worsening > improving { return "arrow.down.right.circle.fill" }
        if improving > worsening { return "arrow.up.right.circle.fill" }
        return "equal.circle.fill"
    }

    private var activeReminders: [Reminder] {
        reminders.filter(\.isActive)
    }

    private var firstName: String {
        let name = profiles.first?.name.trimmingCharacters(in: .whitespaces) ?? ""
        return name.components(separatedBy: " ").first ?? ""
    }

    /// Time-of-day-aware greeting shown in the scrollable header. Reads the
    /// wall clock directly since this is presentation, not analysis — unlike
    /// `AnalysisEngine`, which must stay deterministic.
    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: .now)
        let timeGreeting: String
        switch hour {
        case 5..<12: timeGreeting = "Good morning"
        case 12..<17: timeGreeting = "Good afternoon"
        case 17..<22: timeGreeting = "Good evening"
        default: timeGreeting = "Good night"
        }
        guard !firstName.isEmpty else { return timeGreeting }
        return "\(timeGreeting), \(firstName)"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                // Computed once per render and threaded through explicitly —
                // `review` re-runs the full `AnalysisEngine` pass on every
                // access, so every section below takes it as a parameter
                // instead of reading the computed property directly.
                let review = self.review
                VStack(alignment: .leading, spacing: 16) {
                    greetingHeader
                    quickAddButton
                    if review.hasData {
                        scoreCard(review: review)
                        remindersCard
                        quarterlyReviewCard
                        scoreHistoryCard
                        BiomarkerCarouselSection()
                        alertsSection(review: review)
                        appointmentCard
                        vitalsGrid
                        goalsCard
                        recentReportsSection
                    } else {
                        emptyState
                    }
                }
                .padding()
            }
            .background(AmbientBackground().accessibilityHidden(true))
            .navigationTitle("Dashboard")
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
                .accessibilityLabel("Add")
            }
            .sheet(isPresented: $showingAddReport) { AddReportView() }
            .sheet(isPresented: $showingAddVital) { AddVitalSheet() }
            .sheet(isPresented: $showingQuickAdd) { QuickAddView() }
            .sheet(isPresented: $showingQuarterlyReview) { QuarterlyReviewView() }
        }
    }

    // MARK: Sections

    private var quickAddButton: some View {
        Button {
            showingQuickAdd = true
        } label: {
            Label("Quick Add", systemImage: "sparkles")
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .tintedGlassCard(.teal, cornerRadius: 999)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Quick Add")
        .accessibilityHint("Add a medication, vital, symptom, appointment, or reminder by typing a sentence.")
    }

    private var greetingHeader: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(greeting)
                .font(.title2.bold())
            Text(Date.now.formatted(date: .complete, time: .omitted))
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func scoreCard(review: HealthReview) -> some View {
        ZStack(alignment: .topTrailing) {
            Button {
                onOpenReview()
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
                        .accessibilityHidden(true)
                }
                .padding()
                .glassCard()
                .accessibilityElement(children: .combine)
            }
            .buttonStyle(.plain)

            // Redacted, shareable score card — see ScoreShareCard.swift.
            // Rendered lazily (ScoreShareImage's Transferable) only when
            // the user actually taps Share.
            ShareLink(
                item: ScoreShareImage(
                    score: review.score,
                    scoreLabel: review.scoreLabel,
                    stats: shareStats(review: review),
                    generatedAt: .now
                ),
                preview: SharePreview("Gemocode Score", image: Image(systemName: "heart.text.square.fill"))
            ) {
                Image(systemName: "square.and.arrow.up")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(8)
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay(Circle().strokeBorder(Glass.bevelStroke, lineWidth: 1))
            }
            .accessibilityLabel("Share score card")
            .padding(10)
        }
    }

    private var remindersCard: some View {
        let today = Date.now
        let doneCount = activeReminders.filter { $0.isCompleted(on: today) }.count
        let hasAISuggestions = activeReminders.contains(where: \.isAISuggested)

        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text("Today")
                    .font(.headline)
                Spacer()
                if !activeReminders.isEmpty {
                    Text("\(doneCount) of \(activeReminders.count) done")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                NavigationLink {
                    RemindersView()
                } label: {
                    Text("Manage")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
            }

            if activeReminders.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("No reminders yet — add one to stay on top of medications, checkups, and healthy habits.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    NavigationLink {
                        RemindersView()
                    } label: {
                        Label("Add a Reminder", systemImage: "bell.badge.plus")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .strokeBorder(Glass.bevelStroke, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
            } else {
                VStack(spacing: 10) {
                    ForEach(Array(activeReminders.enumerated()), id: \.offset) { index, reminder in
                        if index > 0 {
                            Divider()
                        }
                        TodayReminderRow(
                            reminder: reminder,
                            isCompleted: reminder.isCompleted(on: today)
                        ) {
                            toggleReminderCompletion(reminder, on: today)
                        }
                    }
                }
                if hasAISuggestions {
                    Text("AI-suggested reminders are educational, not medical advice — worth discussing with your doctor before changing your routine.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding()
        .glassCard()
    }

    /// Toggles today's completion for a reminder: inserts a `ReminderCompletion`
    /// when marking done, deletes today's completion when un-marking. Day
    /// comparisons go through `Calendar`, never string/date-equality, so this
    /// stays correct across time zones and DST changes.
    private func toggleReminderCompletion(_ reminder: Reminder, on day: Date) {
        let calendar = Calendar.current
        if let existing = (reminder.completions ?? []).first(where: { calendar.isDate($0.date, inSameDayAs: day) }) {
            modelContext.delete(existing)
        } else {
            modelContext.insert(ReminderCompletion(date: day, reminder: reminder))
            Haptics.success()
        }
    }

    @ViewBuilder
    private var quarterlyReviewCard: some View {
        if isQuarterlyReviewDue {
            Button {
                showingQuarterlyReview = true
            } label: {
                HStack(spacing: 14) {
                    Image(systemName: "calendar.badge.clock")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Glass.accentGradient)
                        .frame(width: 40, height: 40)
                        .background(.ultraThinMaterial, in: Circle())
                        .overlay(Circle().strokeBorder(Glass.bevelStroke, lineWidth: 1))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Quarterly Review is ready")
                            .font(.subheadline.weight(.semibold))
                        Text("See how your last 90 days trended.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
                .padding(12)
                .tintedGlassCard(.teal, cornerRadius: 16)
                .accessibilityElement(children: .combine)
            }
            .buttonStyle(.plain)
        }
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
                .accessibilityLabel("Health score history chart")
                .frame(height: 110)
                .padding()
                .glassCard(cornerRadius: 16)
            }
        }
    }

    @ViewBuilder
    private func alertsSection(review: HealthReview) -> some View {
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
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(finding.severity.displayName): \(finding.title). \(finding.detail)")
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
                        .accessibilityHidden(true)
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
                            .accessibilityHidden(true)
                    }
                    .padding(12)
                    .glassCard(cornerRadius: 16)
                    .accessibilityElement(children: .combine)
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var vitalsGrid: some View {
        let tiles = VitalType.allCases.compactMap { type -> (type: VitalType, latest: VitalSample, history: [VitalSample])? in
            let samples = vitals.filter { $0.type == type }.sorted { $0.date < $1.date }
            guard let latest = samples.last else { return nil }
            return (type, latest, Array(samples.suffix(12)))
        }
        if !tiles.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Latest Vitals")
                    .font(.headline)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    ForEach(tiles, id: \.type) { tile in
                        NavigationLink {
                            VitalsView(initialType: tile.type)
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Label(tile.type.displayName, systemImage: tile.type.systemImage)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                Text(tile.latest.formattedValue)
                                    .font(.title3.bold())
                                    .contentTransition(.numericText())
                                if tile.history.count >= 2 {
                                    Chart(tile.history) { sample in
                                        LineMark(
                                            x: .value("Date", sample.date),
                                            y: .value("Value", Units.display(sample.value, for: tile.type))
                                        )
                                        .interpolationMethod(.monotone)
                                        .lineStyle(StrokeStyle(lineWidth: 1.5, lineCap: .round))
                                    }
                                    .foregroundStyle(Glass.accentGradient)
                                    .chartXAxis(.hidden)
                                    .chartYAxis(.hidden)
                                    .chartYScale(domain: .automatic(includesZero: false))
                                    .frame(height: 26)
                                    .accessibilityHidden(true)
                                }
                                Text(tile.latest.date.formatted(date: .abbreviated, time: .omitted))
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .glassCard(cornerRadius: 16)
                            .accessibilityElement(children: .combine)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var goalsCard: some View {
        let active = Array(goals.filter(\.isActive).prefix(2))
        if !active.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Goals")
                    .font(.headline)
                NavigationLink {
                    GoalsView()
                } label: {
                    VStack(spacing: 12) {
                        ForEach(active) { goal in
                            GoalRow(
                                goal: goal,
                                latest: vitals.filter { $0.type == goal.type }.max { $0.date < $1.date }?.value
                            )
                        }
                    }
                    .padding(12)
                    .glassCard(cornerRadius: 16)
                }
                .buttonStyle(.plain)
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
                                .accessibilityHidden(true)
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
                                .accessibilityHidden(true)
                        }
                        .padding(12)
                        .glassCard(cornerRadius: 16)
                        .accessibilityElement(children: .combine)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            ContentUnavailableView(
                "Welcome to Gemocode",
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

/// A single row in the dashboard's "Today" reminders card: icon, title
/// (with an AI-suggested sparkles badge), optional time, and a tap-to-toggle
/// completion circle.
struct TodayReminderRow: View {
    let reminder: Reminder
    let isCompleted: Bool
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: reminder.systemImage)
                .foregroundStyle(Glass.accentGradient)
                .frame(width: 32, height: 32)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(Glass.bevelStroke, lineWidth: 1)
                )
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(reminder.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(isCompleted ? .secondary : .primary)
                        .strikethrough(isCompleted)
                        .lineLimit(1)
                    if reminder.isAISuggested {
                        Image(systemName: "sparkles")
                            .font(.caption2)
                            .foregroundStyle(Glass.accentGradient)
                            .accessibilityHidden(true)
                    }
                }
                if let timeOfDay = reminder.timeOfDay {
                    Text(timeOfDay.formatted(date: .omitted, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button(action: onToggle) {
                Image(systemName: isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(isCompleted ? Color.green : Color.secondary.opacity(0.5))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isCompleted ? "Completed" : "Mark as done")
            .accessibilityAddTraits(isCompleted ? [.isSelected] : [])
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(reminder.title)\(reminder.isAISuggested ? ", AI suggested" : "")\(reminder.timeOfDay.map { ", " + $0.formatted(date: .omitted, time: .shortened) } ?? "")"
        )
        .accessibilityValue(isCompleted ? "Done" : "Not done")
        .accessibilityAction(named: isCompleted ? "Mark as not done" : "Mark as done", onToggle)
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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Health score, \(score) out of 100")
    }
}
