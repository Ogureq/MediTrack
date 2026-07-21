import SwiftUI
import SwiftData
import Charts

struct DashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @Query(sort: \MedicalReport.date, order: .reverse) private var reports: [MedicalReport]
    @Query private var vitals: [VitalSample]
    @Query private var medications: [Medication]
    @Query private var profiles: [HealthProfile]
    @Query(sort: \ScoreSnapshot.date) private var snapshots: [ScoreSnapshot]
    @Query private var symptoms: [SymptomEntry]
    @Query(sort: \Appointment.date) private var appointments: [Appointment]
    @Query private var goals: [HealthGoal]
    @Query(sort: \Reminder.createdAt) private var reminders: [Reminder]

    /// Presents `ReviewScreen` when the score header is tapped — passed in
    /// from `ContentView`, which owns the presentation state and already
    /// does the same thing for the widget's `gemocode://review` deep link.
    /// Defaults to a no-op so this view stays constructible without wiring
    /// it up (e.g. in a preview).
    var onOpenReview: () -> Void = {}

    @State private var showingAddReport = false
    @State private var showingAddVital = false
    @State private var showingQuickAdd = false
    @State private var showingQuarterlyReview = false

    /// The next-draw bundle — everything worth drawing in one visit right
    /// now, per `RetestSchedule.nextDraw`. Cached the same way as
    /// `earliestDataDate` below — building it flattens every report's lab
    /// results, which is wasted work to redo on every render — and rebuilt
    /// via `.task(id: retestSignature)`. Drives `nextDrawCard`.
    @State private var drawBundle: DrawBundle?

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
    ///
    /// Cached instead of a plain computed property — it flattens every
    /// report's lab results, which is wasted work to redo on every render
    /// when it's only needed once `isQuarterlyReviewDue` is checked.
    /// Rebuilt via `.task(id: earliestDataSignature)`.
    @State private var earliestDataDate: Date?

    private var earliestDataSignature: String {
        "\(reports.count)-\(vitals.count)-\(snapshots.count)"
    }

    private static func computeEarliestDataDate(
        reports: [MedicalReport],
        vitals: [VitalSample],
        snapshots: [ScoreSnapshot]
    ) -> Date? {
        let dates = [
            snapshots.first?.date,
            vitals.map(\.date).min(),
            reports.map(\.date).min(),
            reports.flatMap(\.labResults).map(\.date).min(),
        ].compactMap { $0 }
        return dates.min()
    }

    /// Signature for the "Tests due" cache: changes whenever the number of
    /// reports or the total number of lab results changes, which is exactly
    /// when `RetestSchedule.dueOrSoon` could produce a different result.
    private var retestSignature: String {
        "\(reports.count)-\(reports.reduce(0) { $0 + $1.labResults.count })"
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
            let text = count == 1
                ? String(localized: "1 biomarker tracked")
                : String(format: String(localized: "%lld biomarkers tracked"), count)
            stats.append(ShareStat(systemImage: "testtube.2", text: text))
        }
        stats.append(ShareStat(systemImage: shareTrendSystemImage(review: review), text: shareTrendText(review: review)))
        if !reports.isEmpty {
            let text = reports.count == 1
                ? String(localized: "1 report logged")
                : String(format: String(localized: "%lld reports logged"), reports.count)
            stats.append(ShareStat(systemImage: "doc.text", text: text))
        }
        return stats
    }

    private func shareTrendText(review: HealthReview) -> String {
        let worsening = review.trends.filter { $0.direction == .worsening }.count
        let improving = review.trends.filter { $0.direction == .improving }.count
        if worsening > improving { return String(localized: "Trending down") }
        if improving > worsening { return String(localized: "Trending up") }
        return String(localized: "Trending steady")
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

    /// "Jul 20 · Anna"-style micro-label text for the header row — today's
    /// date plus the profile's first name (date alone when there's no
    /// profile name yet). Presentation-only, like the old `greeting` it
    /// replaces: reads the wall clock directly rather than taking `now` as
    /// a parameter, since this is UI text, not analysis.
    private var headerDateNameText: String {
        let dateText = Date.now.formatted(.dateTime.month(.abbreviated).day())
        guard !firstName.isEmpty else { return dateText }
        return "\(dateText) · \(firstName)"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                // Computed once per render and threaded through explicitly —
                // `review` re-runs the full `AnalysisEngine` pass on every
                // access, so every section below takes it as a parameter
                // instead of reading the computed property directly.
                let review = self.review
                // Same idea: `vitalsGrid`/`goalsCard` each used to filter+sort
                // every vital per `VitalType`/goal on every render; grouping
                // once here and threading the dictionary through does it once.
                let vitalsByType = Dictionary(grouping: vitals, by: \.type)
                VStack(alignment: .leading, spacing: 16) {
                    editorialHeader
                    if review.hasData {
                        scoreHeader(review: review)
                        nextDrawCard
                            .transaction { $0.animation = nil }
                        needsAttentionSection(review: review)
                        scanReportButton
                        remindersCard
                            .transaction { $0.animation = nil }
                        quarterlyReviewCard
                            .transaction { $0.animation = nil }
                        scoreHistoryCard
                        BiomarkerCarouselSection()
                            .transaction { $0.animation = nil }
                        alertsSection(review: review)
                            .transaction { $0.animation = nil }
                        appointmentCard
                            .transaction { $0.animation = nil }
                        vitalsGrid(vitalsByType: vitalsByType)
                            .transaction { $0.animation = nil }
                        goalsCard(vitalsByType: vitalsByType)
                            .transaction { $0.animation = nil }
                        recentReportsSection
                            .transaction { $0.animation = nil }
                    } else {
                        emptyState
                    }
                }
                .padding()
            }
            .background(AmbientBackground().accessibilityHidden(true))
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showingAddReport) { AddReportView() }
            .sheet(isPresented: $showingAddVital) { AddVitalSheet() }
            .sheet(isPresented: $showingQuickAdd) { QuickAddView() }
            .sheet(isPresented: $showingQuarterlyReview) { QuarterlyReviewView() }
        }
        .task(id: earliestDataSignature) {
            earliestDataDate = Self.computeEarliestDataDate(reports: reports, vitals: vitals, snapshots: snapshots)
        }
        .task(id: retestSignature) {
            let items = RetestSchedule.items(reports: reports, now: .now)
            drawBundle = RetestSchedule.nextDraw(items: items, now: .now)
        }
    }

    // MARK: Editorial header

    /// Micro-label date/name row plus the small circled "+" — the
    /// restyled home for Quick Add, replacing the old full-width
    /// "Quick Add" pill.
    private var editorialHeader: some View {
        HStack(spacing: 12) {
            MicroLabel(verbatim: headerDateNameText)
            Spacer()
            Button {
                showingQuickAdd = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(Editorial.ink(colorScheme))
                    .frame(width: 28, height: 28)
                    .overlay(Circle().strokeBorder(Editorial.controlBorder(colorScheme), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Quick Add")
            .accessibilityHint("Add a medication, vital, symptom, appointment, or reminder by typing a sentence.")
        }
    }

    // MARK: Score header

    /// The 64pt score, its `EditorialTag`, and the three-zone score
    /// `RangeBar` with a trend caption — tapping anywhere opens the full
    /// review (`onOpenReview`); the share button is a separate tap target
    /// in the top-trailing corner, same split as the card it replaces.
    private func scoreHeader(review: HealthReview) -> some View {
        ZStack(alignment: .topTrailing) {
            Button {
                onOpenReview()
            } label: {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .lastTextBaseline, spacing: 12) {
                        Text("\(review.score)")
                            .font(.system(size: 64, weight: .regular))
                            .kerning(-2.56)
                            .foregroundStyle(Editorial.ink(colorScheme))
                            .contentTransition(.numericText())
                        EditorialTag(verbatim: review.scoreLabel, kind: scoreTagKind(review.score))
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        RangeBar(
                            zones: [
                                (fraction: 0.40, kind: .out),
                                (fraction: 0.35, kind: .inRange),
                                (fraction: 0.25, kind: .optimal),
                            ],
                            marker: CGFloat(review.score) / 100
                        )
                        scoreTrendCaption(review: review)
                            .font(.system(size: 11))
                            .foregroundStyle(Editorial.muted(colorScheme))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.trailing, 32)
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(
                Text("Health score, \(review.score) out of 100")
                    + Text(verbatim: ", ")
                    + Text(verbatim: review.scoreLabel)
            )
            .accessibilityHint("Tap for your detailed review")

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
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Editorial.muted(colorScheme))
                    .frame(width: 28, height: 28)
                    .overlay(Circle().strokeBorder(Editorial.controlBorder(colorScheme), lineWidth: 1))
            }
            .accessibilityLabel("Share score card")
        }
    }

    private func scoreTagKind(_ score: Int) -> TagKind {
        switch score {
        case 75...: .good
        case 60..<75: .warn
        default: .bad
        }
    }

    /// "Health Score · ↗ up 6 since January"-style caption, built from the
    /// existing `snapshots` history: reuses the "Health Score" key, then
    /// appends an arrow (universal glyph, not localized) plus a templated
    /// phrase comparing `review.score` against the earliest snapshot on
    /// record. Falls back to just "Health Score" when there's fewer than
    /// two snapshots to compare.
    private func scoreTrendCaption(review: HealthReview) -> Text {
        let base = Text("Health Score")
        guard snapshots.count >= 2, let baseline = snapshots.first else {
            return base
        }
        let delta = review.score - baseline.score
        let month = baseline.date.formatted(.dateTime.month(.wide))
        let dot = Text(verbatim: " · ")
        if delta > 0 {
            let phrase = String(format: String(localized: "up %lld since %@"), delta, month)
            return base + dot + Text(verbatim: "↗ ") + Text(phrase)
        } else if delta < 0 {
            let phrase = String(format: String(localized: "down %lld since %@"), -delta, month)
            return base + dot + Text(verbatim: "↘ ") + Text(phrase)
        } else {
            let phrase = String(format: String(localized: "steady since %@"), month)
            return base + dot + Text(verbatim: "→ ") + Text(phrase)
        }
    }

    // MARK: Next draw

    /// The restyled retest hero: an `insetCard` naming the next lab draw,
    /// built from `RetestSchedule.nextDraw`'s bundle. Priority mirrors the
    /// card it replaces:
    ///
    /// 1. `drawBundle` has a due/soon item → names the bundled tests (up to
    ///    3) and keeps `RetestSchedule.disclaimer` alongside them.
    /// 2. Otherwise, `drawBundle` is seeded on a lone upcoming item →
    ///    names just that test, no disclaimer (nothing urgent to caveat).
    /// 3. Otherwise nothing renders here — the always-visible
    ///    `scanReportButton` below covers "no lab data yet" instead of a
    ///    separate hero card.
    @ViewBuilder
    private var nextDrawCard: some View {
        if let bundle = drawBundle {
            let hasDueOrSoon = bundle.items.contains { $0.status != .upcoming }
            VStack(alignment: .leading, spacing: 6) {
                nextDrawInsetCard(
                    title: nextDrawTitle(dueDate: bundle.date),
                    subtitle: nextDrawSubtitle(bundle: bundle)
                )
                if hasDueOrSoon {
                    Text(RetestSchedule.disclaimer)
                        .font(.system(size: 10))
                        .foregroundStyle(Editorial.muted(colorScheme))
                }
            }
        }
    }

    private func nextDrawTitle(dueDate: Date) -> String {
        String(format: String(localized: "Next draw — %@"), dueDate.formatted(.dateTime.month(.abbreviated).day()))
    }

    /// "HbA1c + LDL + glucose · one visit · saves ~$80 est." — the joined
    /// test names, the existing "· one visit" tail once there's more than
    /// one, and (new) a "· saves ~$N est." tail once the bundle actually
    /// has a savings figure (never true alongside a lone test, since
    /// `RetestSchedule.estimatedSavings` requires 2+ bundled tests).
    private func nextDrawSubtitle(bundle: DrawBundle) -> String {
        let names = bundle.items.prefix(3).map(\.displayName)
        let joined = names.joined(separator: " + ")
        guard names.count > 1 else { return joined }
        if let savings = bundle.estimatedSavings {
            return String(format: String(localized: "%@ · one visit · saves ~$%lld est."), joined, savings)
        }
        return String(format: String(localized: "%@ · one visit"), joined)
    }

    /// `insetCard` fill, radius 18: title/subtitle plus a "Book"-look accent
    /// pill. The whole card is one `NavigationLink` into the full retest
    /// schedule (there's no separate booking flow today), so the pill is
    /// drawn — not a nested button — to avoid two overlapping tap targets.
    private func nextDrawInsetCard(title: String, subtitle: String) -> some View {
        NavigationLink {
            RetestScheduleView()
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: title)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Editorial.ink(colorScheme))
                        .lineLimit(2)
                    Text(verbatim: subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(Editorial.muted(colorScheme))
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Text("Book")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.vertical, 9)
                    .padding(.horizontal, 16)
                    .background(Editorial.accent(colorScheme), in: Capsule())
            }
            .padding(14)
            .background(Editorial.insetCard(colorScheme), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(title). \(subtitle)")
        }
        .buttonStyle(.plain)
    }

    // MARK: Needs attention

    /// Out-of-range lab rows — a direct restyle of `review.labSnapshots`
    /// filtered to `status.isOutOfRange`, each with its own `RangeBar` built
    /// from the lab's reference range via the `lower:upper:min:max:value:`
    /// initializer.
    @ViewBuilder
    private func needsAttentionSection(review: HealthReview) -> some View {
        let outOfRange = review.labSnapshots.filter { $0.status.isOutOfRange }
        if !outOfRange.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                MicroLabel(verbatim: needsAttentionHeaderText(count: outOfRange.count))
                    .padding(.bottom, 2)
                VStack(spacing: 0) {
                    ForEach(outOfRange) { snapshot in
                        needsAttentionRow(snapshot)
                    }
                }
            }
        }
    }

    private func needsAttentionHeaderText(count: Int) -> String {
        String(format: String(localized: "Needs attention · %lld"), count)
    }

    private func needsAttentionRow(_ snapshot: LabSnapshot) -> some View {
        let axis = snapshot.range.map { rangeAxis(lower: $0.lowerBound, upper: $0.upperBound, value: snapshot.value) }
        return VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .lastTextBaseline) {
                Text(verbatim: snapshot.name)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Editorial.ink(colorScheme))
                Spacer()
                Text(verbatim: "\(snapshot.value.compactFormatted) \(snapshot.unit)")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Editorial.ink(colorScheme))
                EditorialTag(verbatim: snapshot.status.label, kind: tagKind(for: snapshot.status))
            }
            if let range = snapshot.range, let axis {
                RangeBar(
                    lower: range.lowerBound,
                    upper: range.upperBound,
                    min: axis.min,
                    max: axis.max,
                    value: snapshot.value
                )
            }
        }
        .ledgerRow()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(snapshot.name), \(snapshot.value.compactFormatted) \(snapshot.unit), \(snapshot.status.label)")
    }

    /// Padded axis for a lab's `RangeBar`: at least 40% of the reference
    /// range's own span beyond whichever is further out — the reference
    /// range itself, or the value when it's outside that range — so an
    /// out-of-range marker never sits flush against the bar's edge.
    private func rangeAxis(lower: Double, upper: Double, value: Double) -> (min: Double, max: Double) {
        let span = Swift.max(upper - lower, .ulpOfOne)
        let low = Swift.min(lower, value)
        let high = Swift.max(upper, value)
        let pad = span * 0.4
        return (low - pad, high + pad)
    }

    private func tagKind(for status: LabStatus) -> TagKind {
        switch status {
        case .high: .warn
        case .low, .criticalLow, .criticalHigh: .bad
        case .normal, .unknown: .good
        }
    }

    private func tagKind(for severity: Severity) -> TagKind {
        switch severity {
        case .critical: .bad
        case .attention: .warn
        case .info: .good
        }
    }

    // MARK: Scan Bloodwork

    /// Always-visible outlined CTA — the mockup's persistent "Scan
    /// Bloodwork" button, wired to the same `showingAddReport` entry point
    /// the toolbar menu and empty state already use.
    private var scanReportButton: some View {
        Button {
            showingAddReport = true
        } label: {
            Label("Scan Bloodwork", systemImage: "doc.text.viewfinder")
        }
        .buttonStyle(OutlinedPillButtonStyle())
        .accessibilityHint("Opens the report scanner.")
    }

    // MARK: Sections (existing content, restyled below the mockup structure)

    private var remindersCard: some View {
        let today = Date.now
        let doneCount = activeReminders.filter { $0.isCompleted(on: today) }.count
        let hasAISuggestions = activeReminders.contains(where: \.isAISuggested)

        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                MicroLabel("Today")
                Spacer()
                if !activeReminders.isEmpty {
                    Text("\(doneCount) of \(activeReminders.count) done")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Editorial.muted(colorScheme))
                }
                NavigationLink {
                    RemindersView()
                } label: {
                    Text("Manage")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Editorial.accent(colorScheme))
                }
                .buttonStyle(.plain)
            }

            if activeReminders.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("No reminders yet — add one to stay on top of medications, checkups, and healthy habits.")
                        .font(.subheadline)
                        .foregroundStyle(Editorial.muted(colorScheme))
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
                                    .strokeBorder(Glass.bevelStroke(for: colorScheme), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
            } else {
                VStack(spacing: 0) {
                    ForEach(activeReminders) { reminder in
                        TodayReminderRow(
                            reminder: reminder,
                            isCompleted: reminder.isCompleted(on: today)
                        ) {
                            toggleReminderCompletion(reminder, on: today)
                        }
                        .ledgerRow()
                    }
                }
                if hasAISuggestions {
                    Text("AI-suggested reminders are educational, not medical advice — worth discussing with your doctor before changing your routine.")
                        .font(.caption2)
                        .foregroundStyle(Editorial.muted(colorScheme))
                }
            }
        }
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
                        .overlay(Circle().strokeBorder(Glass.bevelStroke(for: colorScheme), lineWidth: 1))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Quarterly Review is ready")
                            .font(.subheadline.weight(.semibold))
                        Text("See how your last 90 days trended.")
                            .font(.caption)
                            .foregroundStyle(Editorial.muted(colorScheme))
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Editorial.muted(colorScheme))
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
                MicroLabel("Score History")
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
            VStack(alignment: .leading, spacing: 0) {
                MicroLabel("Needs Your Attention")
                    .padding(.bottom, 8)
                ForEach(Array(alerts)) { finding in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .top) {
                            Text(finding.title)
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(Editorial.ink(colorScheme))
                            Spacer(minLength: 8)
                            EditorialTag(verbatim: finding.severity.displayName, kind: tagKind(for: finding.severity))
                        }
                        Text(finding.detail)
                            .font(.system(size: 12))
                            .foregroundStyle(Editorial.muted(colorScheme))
                            .lineLimit(3)
                    }
                    .ledgerRow()
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
                MicroLabel("Next Appointment")
                NavigationLink {
                    AppointmentsView()
                } label: {
                    HStack(spacing: 12) {
                        VStack(spacing: 0) {
                            Text(next.date.formatted(.dateTime.month(.abbreviated)))
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(Editorial.muted(colorScheme))
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                            Text(next.date.formatted(.dateTime.day()))
                                .font(.title3.bold())
                                .foregroundStyle(Editorial.accent(colorScheme))
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                        }
                        .frame(width: 44, height: 44)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(Glass.bevelStroke(for: colorScheme), lineWidth: 1)
                        )
                        .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(next.title)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                            Text(next.date.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption)
                                .foregroundStyle(Editorial.muted(colorScheme))
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Editorial.muted(colorScheme))
                            .accessibilityHidden(true)
                    }
                    .ledgerRow()
                    .accessibilityElement(children: .combine)
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private func vitalsGrid(vitalsByType: [VitalType: [VitalSample]]) -> some View {
        let tiles = VitalType.allCases.compactMap { type -> (type: VitalType, latest: VitalSample, history: [VitalSample])? in
            let samples = (vitalsByType[type] ?? []).sorted { $0.date < $1.date }
            guard let latest = samples.last else { return nil }
            return (type, latest, Array(samples.suffix(12)))
        }
        if !tiles.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                MicroLabel("Latest Vitals")
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    ForEach(tiles, id: \.type) { tile in
                        NavigationLink {
                            VitalsView(initialType: tile.type)
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Label(tile.type.displayName, systemImage: tile.type.systemImage)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Editorial.muted(colorScheme))
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
                                    .foregroundStyle(Editorial.muted(colorScheme))
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
    private func goalsCard(vitalsByType: [VitalType: [VitalSample]]) -> some View {
        let active = Array(goals.filter(\.isActive).prefix(2))
        if !active.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                MicroLabel("Goals")
                NavigationLink {
                    GoalsView()
                } label: {
                    VStack(spacing: 0) {
                        ForEach(active) { goal in
                            GoalRow(
                                goal: goal,
                                latest: (vitalsByType[goal.type] ?? []).max { $0.date < $1.date }?.value
                            )
                            .ledgerRow()
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var recentReportsSection: some View {
        if !reports.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                MicroLabel("Recent Reports")
                VStack(spacing: 0) {
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
                                            .strokeBorder(Glass.bevelStroke(for: colorScheme), lineWidth: 1)
                                    )
                                    .accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(report.title)
                                        .font(.subheadline.weight(.semibold))
                                        .lineLimit(1)
                                    Text(report.date.formatted(date: .abbreviated, time: .omitted))
                                        .font(.caption)
                                        .foregroundStyle(Editorial.muted(colorScheme))
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Editorial.muted(colorScheme))
                                    .accessibilityHidden(true)
                            }
                            .ledgerRow()
                            .accessibilityElement(children: .combine)
                        }
                        .buttonStyle(.plain)
                    }
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

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: reminder.systemImage)
                .foregroundStyle(Glass.accentGradient)
                .frame(width: 32, height: 32)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(Glass.bevelStroke(for: colorScheme), lineWidth: 1)
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
        .accessibilityLabel(reminderAccessibilityText)
        .accessibilityValue(isCompleted ? "Done" : "Not done")
        .accessibilityAction(named: isCompleted ? "Mark as not done" : "Mark as done", onToggle)
    }

    /// Built explicitly (rather than as a literal string interpolation) so
    /// the English fragments below go through `String(localized:)` — a
    /// ternary/optional nested *inside* a `Text`/`.accessibilityLabel`
    /// string-interpolation slot is evaluated as a plain `String` first,
    /// so its own literal branches never reach the catalog.
    private var reminderAccessibilityText: String {
        var text = reminder.title
        if reminder.isAISuggested {
            text += String(localized: ", AI suggested")
        }
        if let timeOfDay = reminder.timeOfDay {
            text += ", " + timeOfDay.formatted(date: .omitted, time: .shortened)
        }
        return text
    }
}

/// Kept only for `ReviewScreen`, which still uses this animated ring for its
/// own score header — the dashboard's own score header is now the flat
/// 64pt/`EditorialTag`/`RangeBar` treatment in `scoreHeader(review:)` above.
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
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
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
