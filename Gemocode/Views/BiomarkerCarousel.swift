import SwiftUI
import SwiftData

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

/// Flat ledger of the lab tests the user has results for, one row per test.
/// Self-contained — queries its own data and renders nothing when there is
/// nothing to show — so a single inserted `BiomarkerCarouselSection()` line
/// works inside the dashboard's scrolling `VStack`.
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
                    MicroLabel("Biomarkers")
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(series) { item in
                            NavigationLink {
                                LabDetailView(seriesKey: item.id)
                            } label: {
                                BiomarkerRow(series: item, sex: profiles.first?.sex)
                            }
                            .buttonStyle(.plain)
                        }
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

// MARK: - Row

/// One flat ledger row: test name, relative "updated" caption, latest value,
/// status tag, and a `RangeBar` showing where the value sits inside its
/// reference range. The enclosing `NavigationLink` (in
/// `BiomarkerCarouselSection`) opens `LabDetailView` exactly the way
/// `ReviewScreen` and `ReportDetailView` already do.
private struct BiomarkerRow: View {
    let series: BiomarkerSeries
    let sex: BiologicalSex?

    @Environment(\.colorScheme) private var colorScheme

    /// Nil for a manually entered test that isn't in the built-in catalog —
    /// those fall back to a neutral tag instead of an invented range.
    private var reference: LabReference? {
        LabCatalog.reference(for: series.id)
    }

    private var range: ClosedRange<Double>? {
        reference?.referenceRange(for: sex)
    }

    /// Reuses `AnalysisEngine.status`, the same classification `LabDetailView`
    /// and `ReviewScreen` use for this test, so the tag here never disagrees
    /// with the detail screen. A nil reference/range resolves to `.unknown`
    /// ("No Range"), which is the neutral tag for custom tests.
    private var status: LabStatus {
        AnalysisEngine.status(
            value: series.latest,
            range: range,
            criticalLow: reference?.criticalLow,
            criticalHigh: reference?.criticalHigh
        )
    }

    /// Maps a lab status to the editorial tag palette. Matches the token
    /// spec exactly: "High" reads as the cautionary amber tag, "Low" (and
    /// any critical flag) reads as the more urgent red tag.
    private var tagKind: TagKind {
        switch status {
        case .normal: .good
        case .high: .warn
        case .low, .criticalLow, .criticalHigh: .bad
        case .unknown: .warn
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(series.name)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Editorial.ink(colorScheme))
                        .lineLimit(1)
                    Text("Updated \(series.latestDate.formatted(.relative(presentation: .named)))")
                        .font(.system(size: 11))
                        .foregroundStyle(Editorial.muted(colorScheme))
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 4) {
                    Text("\(series.latest.compactFormatted) \(series.unit)")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Editorial.ink(colorScheme))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    EditorialTag(verbatim: status.label, kind: tagKind)
                }
            }

            if let range {
                let bounds = axisBounds(range: range, value: series.latest)
                RangeBar(
                    lower: range.lowerBound,
                    upper: range.upperBound,
                    min: bounds.min,
                    max: bounds.max,
                    value: series.latest,
                    accessibilityLabel: Text(
                        "\(series.name) \(series.latest.compactFormatted) \(series.unit), \(status.label)"
                    )
                )
            }
        }
        .ledgerRow()
        .accessibilityElement(children: .combine)
    }

    /// Extends the reference range with padding on both sides so the
    /// `RangeBar` axis has visual breathing room, while still keeping the
    /// current value's marker safely inside the drawn bounds even when the
    /// reading is far outside the reference range.
    private func axisBounds(range: ClosedRange<Double>, value: Double) -> (min: Double, max: Double) {
        let span = Swift.max(range.upperBound - range.lowerBound, 0.0001)
        let pad = span * 0.6
        let lower = Swift.min(range.lowerBound - pad, value - span * 0.05)
        let upper = Swift.max(range.upperBound + pad, value + span * 0.05)
        return (lower, upper)
    }
}
