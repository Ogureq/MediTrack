import SwiftUI
import SwiftData
import Charts

// MARK: - Biomarker series (pure model)

/// One lab test's history, grouped and time-ordered for display.
///
/// Deliberately SwiftData-free (no `LabResult` references) so
/// `BiomarkerGrouping.series(from:)` is a pure function that unit tests can
/// exercise without a `ModelContext`.
struct BiomarkerSeries: Equatable, Identifiable {
    /// One value in a series' history. A plain struct rather than a tuple so
    /// `points`, and therefore the whole series, stays `Equatable`.
    struct Point: Equatable {
        let date: Date
        let value: Double
    }

    /// Equal to `LabResult.seriesKey` (catalog id when the test came from the
    /// built-in catalog, `"custom:<name>"` otherwise). Reusing that key means
    /// a card can push `LabDetailView(seriesKey:)` directly with `id`.
    let id: String
    let name: String
    let unit: String
    /// Ascending by date (oldest first).
    let points: [Point]

    var latest: Double { points.last?.value ?? 0 }
    var latestDate: Date { points.last?.date ?? .distantPast }
}

// MARK: - Grouping

enum BiomarkerGrouping {
    /// The carousel is a single scrolling row, not a full list — cap how many
    /// distinct tests it will ever render.
    static let seriesCap = 12

    /// Groups lab results into per-test series ready for the carousel.
    ///
    /// Grouping reuses `LabResult.seriesKey` (catalog id, falling back to
    /// lowercased custom name) instead of re-deriving the grouping rule, so
    /// this always agrees with `LabDetailView` and `ReviewScreen` about what
    /// counts as "the same test". Each series' points are sorted ascending by
    /// date, and the series themselves are ordered by most-recent result
    /// first (ties broken by id for determinism), capped at `seriesCap`.
    static func series(from results: [LabResult]) -> [BiomarkerSeries] {
        let grouped = Dictionary(grouping: results, by: \.seriesKey)

        let unordered: [BiomarkerSeries] = grouped.map { key, group in
            let ascending = group.sorted { $0.date < $1.date }
            let points = ascending.map { BiomarkerSeries.Point(date: $0.date, value: $0.value) }
            let mostRecent = ascending.last
            return BiomarkerSeries(
                id: key,
                name: mostRecent?.displayName ?? String(localized: "Unknown Test"),
                unit: mostRecent?.unit ?? "",
                points: points
            )
        }

        let ordered = unordered.sorted { lhs, rhs in
            if lhs.latestDate != rhs.latestDate { return lhs.latestDate > rhs.latestDate }
            return lhs.id < rhs.id
        }
        return Array(ordered.prefix(seriesCap))
    }
}

// MARK: - Carousel section

/// Horizontally scrolling row of compact biomarker cards, one per lab test
/// the user has results for. Self-contained — queries its own data and
/// renders nothing when there is nothing to show — so a single inserted
/// `BiomarkerCarouselSection()` line works inside the dashboard's scrolling
/// `VStack`.
struct BiomarkerCarouselSection: View {
    @Query private var labResults: [LabResult]
    @Query private var profiles: [HealthProfile]

    /// Cached grouping — `BiomarkerGrouping.series(from:)` flattens and
    /// sorts every lab result on every call, so this is computed once when
    /// the result count changes rather than on every render.
    @State private var series: [BiomarkerSeries] = []

    var body: some View {
        Group {
            if series.isEmpty {
                EmptyView()
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Biomarkers")
                        .font(.headline)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .top, spacing: 12) {
                            ForEach(series) { item in
                                NavigationLink {
                                    LabDetailView(seriesKey: item.id)
                                } label: {
                                    BiomarkerCard(series: item, sex: profiles.first?.sex)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        // Small inset so each card's drop shadow doesn't clip
                        // against the scroll view's edge.
                        .padding(.horizontal, 2)
                        .padding(.vertical, 2)
                    }
                }
            }
        }
        // This section flips from EmptyView to populated content via `.task`
        // below, moments after the dashboard first appears. Without nulling
        // the transaction here, an ambient animation already in flight (e.g.
        // from the onboarding fullScreenCover dismissing) gets inherited by
        // this insertion and animates it in from a stale/offset frame — see
        // the same guard, for the same reason, in ReviewScreen.
        .transaction { $0.animation = nil }
        .task(id: labResults.count) {
            series = BiomarkerGrouping.series(from: labResults)
        }
    }
}

// MARK: - Card

/// One compact card: test name, latest value, status pill, mini sparkline,
/// and a relative date caption. The enclosing `NavigationLink` (in
/// `BiomarkerCarouselSection`) opens `LabDetailView` exactly the way
/// `ReviewScreen` and `ReportDetailView` already do.
private struct BiomarkerCard: View {
    let series: BiomarkerSeries
    let sex: BiologicalSex?

    /// Nil for a manually entered test that isn't in the built-in catalog —
    /// those fall back to a neutral pill instead of an invented range.
    private var reference: LabReference? {
        LabCatalog.reference(for: series.id)
    }

    private var range: ClosedRange<Double>? {
        reference?.referenceRange(for: sex)
    }

    /// Reuses `AnalysisEngine.status`, the same classification `LabDetailView`
    /// and `ReviewScreen` use for this test, so the pill here never disagrees
    /// with the detail screen. A nil reference/range resolves to `.unknown`
    /// ("No Range"), which is the neutral pill for custom tests.
    private var status: LabStatus {
        AnalysisEngine.status(
            value: series.latest,
            range: range,
            criticalLow: reference?.criticalLow,
            criticalHigh: reference?.criticalHigh
        )
    }

    private var sparklinePoints: [BiomarkerSeries.Point] {
        Array(series.points.suffix(12))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(series.name)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Text("\(series.latest.compactFormatted) \(series.unit)")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(status.isOutOfRange ? status.color : .primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            StatusPill(text: status.label, color: status.color)

            sparkline
                .frame(height: 40)

            Text("Updated \(series.latestDate.formatted(.relative(presentation: .named)))")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
        .padding(12)
        .frame(width: 160, alignment: .leading)
        .glassCard(cornerRadius: 16)
        .accessibilityElement(children: .combine)
    }

    /// Decorative history sparkline — hidden from accessibility since the
    /// combined card label already conveys name, value, status, and date.
    @ViewBuilder
    private var sparkline: some View {
        if sparklinePoints.count >= 2 {
            Chart(Array(sparklinePoints.enumerated()), id: \.offset) { entry in
                LineMark(
                    x: .value("Date", entry.element.date),
                    y: .value("Value", entry.element.value)
                )
                .interpolationMethod(.monotone)
                .lineStyle(StrokeStyle(lineWidth: 1.5, lineCap: .round))
            }
            .foregroundStyle(Glass.accentGradient)
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .chartYScale(domain: .automatic(includesZero: false))
            .accessibilityHidden(true)
        } else {
            Color.clear.accessibilityHidden(true)
        }
    }
}
