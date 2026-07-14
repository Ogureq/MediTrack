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
                List {
                    Section {
                        filterChips
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets())

                    if filteredEvents.isEmpty {
                        Section {
                            Text("No events in this category yet.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        .listRowBackground(GlassRowBackground())
                        .listRowSeparator(.hidden)
                    } else {
                        ForEach(groupedByMonth, id: \.month) { group in
                            Section(monthTitle(group.month)) {
                                ForEach(group.events) { event in
                                    TimelineRow(event: event)
                                }
                            }
                            .listRowBackground(GlassRowBackground())
                            .listRowSeparator(.hidden)
                        }
                    }
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

    private func chip(title: String, category: TimelineCategory?) -> some View {
        let isSelected = selectedCategory == category
        return Button {
            selectedCategory = category
        } label: {
            Text(title)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(
                    Capsule().strokeBorder(
                        isSelected ? Color.accentColor.opacity(0.7) : Color.primary.opacity(0.1),
                        lineWidth: 1
                    )
                )
                .foregroundStyle(isSelected ? Color.accentColor : .primary)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

// MARK: - Row

private extension TimelineSignificance {
    var color: Color {
        switch self {
        case .routine: .blue
        case .notable: .orange
        case .important: .red
        }
    }

    var displayName: String {
        switch self {
        case .routine: "Routine"
        case .notable: "Notable"
        case .important: "Important"
        }
    }
}

private struct TimelineRow: View {
    let event: TimelineEvent

    private var accessibilityText: String {
        "\(event.significance.displayName): \(event.title). \(event.detail). \(event.date.formatted(date: .abbreviated, time: .omitted))."
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(event.significance.color)
                .frame(width: 10, height: 10)
                .padding(.top, 6)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Image(systemName: event.systemImage)
                        .foregroundStyle(event.significance.color)
                        .accessibilityHidden(true)
                    Text(event.title)
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text(event.date, format: .relative(presentation: .named))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Text(event.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }
}
