import SwiftUI
import SwiftData

/// Full retest schedule — every catalog-tracked lab test across every saved
/// report, grouped by urgency. Reached from the dashboard's "Tests Due" and
/// "You're caught up" cards (see `DashboardView.retestCard`); this screen is
/// the "skip duplicate tests" half of the app's core story, since the
/// Upcoming section is where a user checks "have I already done this?"
/// before booking another draw.
struct RetestScheduleView: View {
    @Query(sort: \MedicalReport.date, order: .reverse) private var reports: [MedicalReport]

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
                    section(title: "Overdue", items: overdueItems, tint: .red)
                    section(title: "Due Soon", items: dueSoonItems, tint: .orange)
                    section(
                        title: "Upcoming",
                        items: upcomingItems,
                        tint: .blue,
                        footer: "Not due yet — testing these again now is usually unnecessary. Your doctor may advise differently."
                    )

                    Section {
                        Text(RetestSchedule.disclaimer)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
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
    private func section(title: LocalizedStringKey, items: [RetestItem], tint: Color, footer: LocalizedStringKey? = nil) -> some View {
        if !items.isEmpty {
            Section {
                ForEach(items) { item in
                    RetestScheduleRow(item: item, tint: tint)
                }
            } header: {
                Text(title)
            } footer: {
                if let footer {
                    Text(footer)
                }
            }
            .listRowBackground(GlassRowBackground())
            .listRowSeparator(.hidden)
        }
    }
}

/// One row in `RetestScheduleView`: test name, last-tested date, and a
/// due summary (absolute for overdue/upcoming, relative for due soon) plus
/// the suggested cadence. Combined into a single accessibility element with
/// a label that reads naturally end-to-end.
private struct RetestScheduleRow: View {
    let item: RetestItem
    let tint: Color

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

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.displayName)
                    .font(.subheadline.weight(.semibold))
                Text("Last tested \(item.lastTestedAt.formatted(.dateTime.month(.abbreviated).day().year()))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(dueText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(tint)
                Text(intervalText)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(item.displayName), last tested \(item.lastTestedAt.formatted(.dateTime.month(.abbreviated).day().year())), \(dueText), \(intervalText)"
        )
    }
}
