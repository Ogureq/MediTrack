import SwiftUI
import SwiftData

/// A scrolling, month-grouped timeline of deterministically-generated
/// health events (reports added, labs crossing their reference range,
/// score swings, medication starts/ends). Every caption comes from
/// `HealthTimeline` — no AI, no network.
struct HealthTimelineView: View {
    @Query(sort: \MedicalReport.date, order: .reverse) private var reports: [MedicalReport]
    @Query private var vitals: [VitalSample]
    @Query(sort: \ScoreSnapshot.date) private var scores: [ScoreSnapshot]
    @Query private var medications: [Medication]
    @Query private var profiles: [HealthProfile]

    @Environment(\.colorScheme) private var colorScheme

    @State private var selectedCategory: TimelineCategory?

    /// Cached instead of recomputed on each of the ~3 accesses this screen
    /// makes per render (`body`'s empty check, plus `filteredEvents`, which
    /// is itself read twice below).
    @State private var allEvents: [TimelineEvent] = []

    /// Cheap `.count`-based signature deciding when to rebuild `allEvents` —
    /// same convention as `AIChatView`'s `onChange(of: messages.count)`.
    private var dataSignature: String {
        "\(reports.count)-\(vitals.count)-\(scores.count)-\(medications.count)-\(profiles.count)"
    }

    private var filteredEvents: [TimelineEvent] {
        guard let selectedCategory else { return allEvents }
        return allEvents.filter { $0.category == selectedCategory }
    }

    private var groupedByMonth: [(month: Date, events: [TimelineEvent])] {
        let calendar = Calendar.current
        let groups = Dictionary(grouping: filteredEvents) { event in
            calendar.dateInterval(of: .month, for: event.date)?.start ?? event.date
        }
        return groups.keys.sorted(by: >).map { key in (month: key, events: groups[key] ?? []) }
    }

    var body: some View {
        Group {
            if allEvents.isEmpty {
                ContentUnavailableView(
                    "No Timeline Events Yet",
                    systemImage: "clock.arrow.circlepath",
                    description: Text("As you add reports, lab results, vitals, and medications, Gemocode builds a timeline of the notable changes.")
                )
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        filterChips

                        if filteredEvents.isEmpty {
                            Text("No events in this category yet.")
                                .font(.system(size: 13))
                                .foregroundStyle(Editorial.muted(colorScheme))
                        } else {
                            ForEach(groupedByMonth, id: \.month) { group in
                                VStack(alignment: .leading, spacing: 0) {
                                    MicroLabel(verbatim: monthTitle(group.month))
                                        .padding(.bottom, 6)
                                    ForEach(group.events) { event in
                                        TimelineRow(event: event)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 28)
                }
            }
        }
        .ambientScreen()
        .navigationTitle("Health Timeline")
        .task(id: dataSignature) {
            allEvents = HealthTimeline.events(
                reports: reports,
                vitals: vitals,
                scores: scores,
                medications: medications,
                profile: profiles.first
            )
        }
    }

    private func monthTitle(_ date: Date) -> String {
        date.formatted(.dateTime.month(.wide).year())
    }

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(title: "All", category: nil)
                chip(title: "Labs", category: .lab)
                chip(title: "Vitals", category: .vital)
                chip(title: "Score", category: .score)
                chip(title: "Meds", category: .medication)
            }
            .padding(.vertical, 4)
        }
    }

    /// Quiet outlined capsule — no filled background, matching the
    /// editorial system's restrained treatment of secondary controls.
    private func chip(title: LocalizedStringKey, category: TimelineCategory?) -> some View {
        let isSelected = selectedCategory == category
        return Button {
            selectedCategory = category
        } label: {
            Text(title)
                .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                .foregroundStyle(isSelected ? Editorial.ink(colorScheme) : Editorial.muted(colorScheme))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .overlay(
                    Capsule().strokeBorder(
                        isSelected ? Editorial.ink(colorScheme) : Editorial.controlBorder(colorScheme),
                        lineWidth: 1
                    )
                )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

// MARK: - Row

private extension TimelineSignificance {
    /// The small leading dot's color: muted for routine events, and the
    /// editorial tag colors for the two levels worth calling out.
    func dotColor(_ colorScheme: ColorScheme) -> Color {
        switch self {
        case .routine: Editorial.muted(colorScheme)
        case .notable: Editorial.tagWarn(colorScheme)
        case .important: Editorial.tagBad(colorScheme)
        }
    }

    var displayName: String {
        switch self {
        case .routine: String(localized: "Routine")
        case .notable: String(localized: "Notable")
        case .important: String(localized: "Important")
        }
    }
}

private struct TimelineRow: View {
    let event: TimelineEvent

    @Environment(\.colorScheme) private var colorScheme

    private var accessibilityText: String {
        "\(event.significance.displayName): \(event.title). \(event.detail). \(event.date.formatted(date: .abbreviated, time: .omitted))."
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(event.significance.dotColor(colorScheme))
                .frame(width: 6, height: 6)
                .padding(.top, 6)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Image(systemName: event.systemImage)
                        .foregroundStyle(Editorial.muted(colorScheme))
                        .accessibilityHidden(true)
                    Text(event.title)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Editorial.ink(colorScheme))
                    Spacer()
                    Text(event.date, format: .relative(presentation: .named))
                        .font(.system(size: 11))
                        .foregroundStyle(Editorial.muted(colorScheme))
                }
                Text(event.detail)
                    .font(.system(size: 12))
                    .foregroundStyle(Editorial.muted(colorScheme))
            }
        }
        .ledgerRow()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }
}
