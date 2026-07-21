import SwiftUI
import SwiftData

/// Full retest schedule — every catalog-tracked lab test across every saved
/// report, grouped by urgency. Reached from the dashboard's "Tests Due" and
/// "You're caught up" cards (see `DashboardView.retestCard`); this screen is
/// the "skip duplicate tests" half of the app's core story, since the
/// Upcoming section is where a user checks "have I already done this?"
/// before booking another draw.
///
/// Editorial redesign: each row's range-bar shows *time elapsed toward the
/// next due date* rather than a lab value inside a reference range — the
/// same `RangeBar` component, a different axis. A fully "out" (warm) bar
/// means the interval has fully elapsed (overdue); a partial "in-range"
/// (mint) fill means there's still buffer before the test is worth
/// repeating. See `<scratchpad>/EDITORIAL-TOKENS.md`.
struct RetestScheduleView: View {
    @Query(sort: \MedicalReport.date, order: .reverse) private var reports: [MedicalReport]

    @Environment(\.colorScheme) private var colorScheme

    /// All tracked tests, overdue first — cached the same way as
    /// `DashboardView`'s `retestItems`: `RetestSchedule.items` flattens
    /// every report's lab results, which is wasted work to redo on every
    /// render, so it's rebuilt only when `signature` changes.
    @State private var items: [RetestItem] = []

    /// The next-draw bundle built over `items` (see `RetestSchedule.nextDraw`)
    /// — drives both the "Next draw" inset card and the "In This Draw"
    /// section below. Rebuilt alongside `items` in the same `.task`.
    @State private var bundle: DrawBundle?

    /// Presents `BookDrawSheet` for the current `bundle` — set from the
    /// "Book" pill in `nextDrawCard(bundle:)`, which used to be a no-op (see
    /// this file's own prior comment history).
    @State private var showingBookSheet = false

    /// Mirrors `DashboardView.retestSignature`: changes exactly when the
    /// number of reports or the total number of lab results changes, which
    /// is exactly when `RetestSchedule.items` could produce a different
    /// result.
    private var signature: String {
        "\(reports.count)-\(reports.reduce(0) { $0 + $1.labResults.count })"
    }

    /// Ids already accounted for by the next-draw bundle — excluded from
    /// the plain urgency sections below so nothing appears twice.
    private var bundleIDs: Set<String> {
        Set(bundle?.items.map(\.id) ?? [])
    }

    /// Defensive-only: `RetestSchedule.nextDraw` always folds in every
    /// due/soon item as its bundle seed, so this is normally empty. Kept
    /// (rather than assumed away) so a future engine change can't silently
    /// hide an overdue test from this screen.
    private var overdueItems: [RetestItem] {
        items.filter { $0.status == .overdue && !bundleIDs.contains($0.id) }
    }

    private var dueSoonItems: [RetestItem] {
        items.filter { $0.status == .dueSoon && !bundleIDs.contains($0.id) }
    }

    /// Upcoming tests NOT already pulled into the next-draw bundle's
    /// "might as well" window — the "Not Due — Don't Pay Yet" section.
    private var notDueItems: [RetestItem] {
        items.filter { $0.status == .upcoming && !bundleIDs.contains($0.id) }
    }

    var body: some View {
        Group {
            if items.isEmpty {
                ContentUnavailableView {
                    Label("No Retest Schedule Yet", systemImage: "calendar.badge.clock")
                } description: {
                    Text("Scan a lab report and Gemocode will build a schedule here, telling you when each test is worth repeating.")
                }
            } else {
                List {
                    Section {
                        HStack {
                            Spacer()
                            Text(trackedCountText)
                                .font(.system(size: 12))
                                .foregroundStyle(Editorial.muted(colorScheme))
                        }
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)

                    if let bundle {
                        Section {
                            nextDrawCard(bundle: bundle)
                        }
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets())
                    }

                    section(title: "In This Draw", items: bundle?.items ?? [])
                    section(title: "Overdue", items: overdueItems)
                    section(title: "Due Soon", items: dueSoonItems)
                    section(
                        title: "Not Due — Don't Pay Yet",
                        items: notDueItems,
                        footer: "Not due yet — testing these again now is usually unnecessary. Your doctor may advise differently.",
                        showWaste: true
                    )

                    Section {
                        Text(RetestSchedule.disclaimer)
                            .font(.system(size: 11))
                            .foregroundStyle(Editorial.muted(colorScheme))
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
            }
        }
        .ambientScreen()
        .navigationTitle("Retest Schedule")
        .task(id: signature) {
            let freshItems = RetestSchedule.items(reports: reports, now: .now)
            items = freshItems
            bundle = RetestSchedule.nextDraw(items: freshItems, now: .now)
        }
        .sheet(isPresented: $showingBookSheet) {
            if let bundle {
                BookDrawSheet(bundle: bundle)
            }
        }
    }

    private var trackedCountText: String {
        String(format: String(localized: "%lld tests tracked"), LabCatalog.count)
    }

    // MARK: - Next draw card

    /// "Next draw — Aug 2 / 3 tests bundled · saves ~$80 est." inset card,
    /// with an optional "fasting required" chip and a "Book" accent pill
    /// that opens `BookDrawSheet` for this bundle — matching
    /// `DashboardView.nextDrawInsetCard`'s own "Book" pill.
    private func nextDrawCard(bundle: DrawBundle) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: nextDrawTitle(date: bundle.date))
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Editorial.ink(colorScheme))
                    Text(verbatim: nextDrawSubtitle(bundle: bundle))
                        .font(.system(size: 12))
                        .foregroundStyle(Editorial.muted(colorScheme))
                    if bundle.requiresFasting {
                        EditorialTag("Fasting Required", kind: .warn)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
                // Kept as its own standalone control (not folded into the
                // combined text element above) so VoiceOver users can still
                // reach it as a separate button, not just hear its label.
                Button("Book") { showingBookSheet = true }
                    .buttonStyle(AccentPillButtonStyle())
                    .accessibilityHint("Opens a form to add this draw as an appointment.")
            }
            .padding(14)
            .background(Editorial.insetCard(colorScheme), in: RoundedRectangle(cornerRadius: 18, style: .continuous))

            // Shown once here — near the top, above every other $ figure on
            // this screen (the bundle's own savings tail above, and any
            // "testing now wastes ~$N" line in the Not Due section below).
            //
            // `RetestSchedule.pricingFootnote` is a plain runtime `String`
            // (its own doc comment: "views are responsible for localizing
            // it"), so `NSLocalizedString` — the one Foundation API that
            // looks a *runtime* string up in the catalog by its exact
            // English text, matching this project's "key == English source
            // text" convention — is used here rather than `Text(_:)`/
            // `String(localized:)`, which both require a compile-time
            // literal key.
            Text(NSLocalizedString(RetestSchedule.pricingFootnote, comment: "Pricing footnote for RetestSchedule money figures"))
                .font(.system(size: 10))
                .foregroundStyle(Editorial.muted(colorScheme))
        }
    }

    private func nextDrawTitle(date: Date) -> String {
        String(format: String(localized: "Next draw — %@"), date.formatted(.dateTime.month(.abbreviated).day()))
    }

    private func nextDrawSubtitle(bundle: DrawBundle) -> String {
        let count = bundle.items.count
        if let savings = bundle.estimatedSavings {
            return String(format: String(localized: "%lld tests bundled · saves ~$%lld est."), count, savings)
        }
        return count == 1
            ? String(localized: "1 test bundled")
            : String(format: String(localized: "%lld tests bundled"), count)
    }

    // MARK: - Sections

    /// One urgency section — omitted entirely when `items` is empty, per
    /// the screen's "only render sections that have something to show" rule.
    /// `showWaste` additionally surfaces
    /// `RetestSchedule.estimatedEarlyTestingWaste` under each row, for the
    /// "Not Due — Don't Pay Yet" section only.
    @ViewBuilder
    private func section(
        title: LocalizedStringKey,
        items: [RetestItem],
        footer: LocalizedStringKey? = nil,
        showWaste: Bool = false
    ) -> some View {
        if !items.isEmpty {
            Section {
                ForEach(items) { item in
                    RetestScheduleRow(
                        item: item,
                        wasteText: showWaste ? wasteText(for: item) : nil
                    )
                    .ledgerRow()
                }
            } header: {
                MicroLabel(title)
            } footer: {
                if let footer {
                    Text(footer)
                        .font(.system(size: 11))
                        .foregroundStyle(Editorial.muted(colorScheme))
                }
            }
            .listRowBackground(GlassRowBackground())
            .listRowSeparator(.hidden)
        }
    }

    private func wasteText(for item: RetestItem) -> String? {
        guard let waste = RetestSchedule.estimatedEarlyTestingWaste(for: item, now: .now) else { return nil }
        return String(format: String(localized: "testing now wastes ~$%lld est."), waste)
    }
}

/// One row in `RetestScheduleView`: test name, a status badge (or, for
/// upcoming tests, the plain due date), a time-until-due bar, and — for
/// overdue/due-soon tests — a detail line with the suggested cadence.
/// Combined into a single accessibility element with a label that reads
/// naturally end-to-end.
private struct RetestScheduleRow: View {
    let item: RetestItem
    /// "testing now wastes ~$N est." — only ever set for the "Not Due —
    /// Don't Pay Yet" section, and only when the test has a known typical
    /// price (see `RetestScheduleView.wasteText(for:)`).
    var wasteText: String? = nil

    @Environment(\.colorScheme) private var colorScheme

    private var dueText: String {
        switch item.status {
        case .overdue:
            String(format: String(localized: "Overdue since %@"), item.dueDate.formatted(.dateTime.month(.abbreviated).year()))
        case .dueSoon:
            String(format: String(localized: "Due %@"), relativeDueText(item.dueDate))
        case .upcoming:
            String(format: String(localized: "Due %@"), item.dueDate.formatted(.dateTime.month(.abbreviated).year()))
        }
    }

    private var intervalText: String {
        item.intervalMonths == 1
            ? String(localized: "every 1 month")
            : String(format: String(localized: "every %lld months"), item.intervalMonths)
    }

    private func relativeDueText(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: .now)
    }

    /// Fraction of the retest interval (last tested → due date) that has
    /// elapsed as of now, clamped to 0...1 — 1.0 means the interval is
    /// fully spent (due or overdue).
    private var elapsedFraction: CGFloat {
        let total = item.dueDate.timeIntervalSince(item.lastTestedAt)
        guard total > 0 else { return 1 }
        let elapsed = Date().timeIntervalSince(item.lastTestedAt)
        return CGFloat(min(max(elapsed / total, 0), 1))
    }

    /// The bar reuses the shared range-bar's `.out`/`.inRange` zone tokens
    /// (rather than the tag's sharper bad/warn hexes) to stay inside the
    /// range-bar's own color grammar — overdue/due-soon read as fully or
    /// mostly "out" (elapsed), upcoming as "in" (buffer remaining).
    private var barZones: [(fraction: CGFloat, kind: RangeZoneKind)] {
        switch item.status {
        case .overdue:
            return [(fraction: 1, kind: .out)]
        case .dueSoon:
            return [(fraction: elapsedFraction, kind: .out), (fraction: max(0, 1 - elapsedFraction), kind: .inRange)]
        case .upcoming:
            return [(fraction: elapsedFraction, kind: .inRange)]
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(item.displayName)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(item.status == .upcoming ? Editorial.muted(colorScheme) : Editorial.ink(colorScheme))
                Spacer()
                statusBadge
            }
            RangeBar(zones: barZones, marker: elapsedFraction)
                .background(Capsule().fill(Editorial.hairline(colorScheme)))
            if item.status != .upcoming {
                Text("\(dueText) · \(intervalText)")
                    .font(.system(size: 11))
                    .foregroundStyle(Editorial.muted(colorScheme))
            }
            if let wasteText {
                Text(verbatim: wasteText)
                    .font(.system(size: 11))
                    .foregroundStyle(Editorial.muted(colorScheme))
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            wasteText.map { "\(item.displayName), last tested \(item.lastTestedAt.formatted(.dateTime.month(.abbreviated).day().year())), \(dueText), \(intervalText), \($0)" }
                ?? "\(item.displayName), last tested \(item.lastTestedAt.formatted(.dateTime.month(.abbreviated).day().year())), \(dueText), \(intervalText)"
        )
    }

    /// Short status badge — a bold tag for overdue/due-soon, and plain
    /// muted due-date text for upcoming tests (the mockup's "not due, don't
    /// pay yet" section never shows a colored tag, only the two urgent
    /// sections do).
    @ViewBuilder
    private var statusBadge: some View {
        switch item.status {
        case .overdue:
            EditorialTag("Overdue", kind: .bad)
        case .dueSoon:
            EditorialTag("Due Soon", kind: .warn)
        case .upcoming:
            Text(dueText)
                .font(.system(size: 12))
                .foregroundStyle(Editorial.muted(colorScheme))
        }
    }
}
