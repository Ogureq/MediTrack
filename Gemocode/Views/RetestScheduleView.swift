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

    /// Mirrors `DashboardView.retestSignature`: changes exactly when the
    /// number of reports or the total number of lab results changes, which
    /// is exactly when `RetestSchedule.items` could produce a different
    /// result.
    private var signature: String {
        "\(reports.count)-\(reports.reduce(0) { $0 + $1.labResults.count })"
    }

    private var overdueItems: [RetestItem] {
        items.filter { $0.status == .overdue }
    }

    private var dueSoonItems: [RetestItem] {
        items.filter { $0.status == .dueSoon }
    }

    private var upcomingItems: [RetestItem] {
        items.filter { $0.status == .upcoming }
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
                    section(title: "Overdue", items: overdueItems)
                    section(title: "Due Soon", items: dueSoonItems)
                    section(
                        title: "Upcoming",
                        items: upcomingItems,
                        footer: "Not due yet — testing these again now is usually unnecessary. Your doctor may advise differently."
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
            items = RetestSchedule.items(reports: reports, now: .now)
        }
    }

    /// One urgency section — omitted entirely when `items` is empty, per
    /// the screen's "only render sections that have something to show" rule.
    @ViewBuilder
    private func section(title: LocalizedStringKey, items: [RetestItem], footer: LocalizedStringKey? = nil) -> some View {
        if !items.isEmpty {
            Section {
                ForEach(items) { item in
                    RetestScheduleRow(item: item)
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
}

/// One row in `RetestScheduleView`: test name, a status badge (or, for
/// upcoming tests, the plain due date), a time-until-due bar, and — for
/// overdue/due-soon tests — a detail line with the suggested cadence.
/// Combined into a single accessibility element with a label that reads
/// naturally end-to-end.
private struct RetestScheduleRow: View {
    let item: RetestItem

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
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(item.displayName), last tested \(item.lastTestedAt.formatted(.dateTime.month(.abbreviated).day().year())), \(dueText), \(intervalText)"
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
