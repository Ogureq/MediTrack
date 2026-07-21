import WidgetKit
import SwiftUI

// MARK: - Shared data contract
//
// This target cannot see the Gemocode app module, so the two `Codable`
// types below intentionally duplicate `Gemocode/Services/WidgetBridge.swift`.
// Keep both definitions in sync: app group "group.com.ogureq.gemocode",
// UserDefaults key "widget.snapshot", JSON encoded with an `.iso8601`
// date strategy on both sides.

/// A compact vital reading surfaced on the home-screen widget.
struct WidgetVital: Codable {
    let name: String
    let value: String
    let systemImage: String
}

/// One tracked lab test's urgency, pre-resolved into widget-safe display
/// strings by `WidgetBridge` — this extension has no strings catalog of
/// its own, so `name`/`dueLabel` arrive already localized.
struct WidgetDueTest: Codable {
    let name: String
    let dueLabel: String
    let isOverdue: Bool
}

/// A point-in-time snapshot of the health review, read from the shared
/// app group.
///
/// `dueTests`/`nextDrawDateISO` are OPTIONAL — a snapshot written by an
/// older app build never had them, and must still decode here; keep this
/// struct byte-equivalent in shape with `Gemocode/Services/WidgetBridge.swift`.
/// `nextDrawDateISO` is a `Date`, riding the same `.iso8601` strategy as
/// `updatedAt`.
struct WidgetSnapshot: Codable {
    let score: Int
    let headline: String
    let updatedAt: Date
    let vitals: [WidgetVital]
    var dueTests: [WidgetDueTest]? = nil
    var nextDrawDateISO: Date? = nil
}

extension WidgetSnapshot {
    /// Sample data used for the widget gallery placeholder/snapshot —
    /// includes a due-tests set so the gallery preview shows the 6u/7u
    /// "next test" layout rather than falling back to the legacy vitals list.
    static let sample = WidgetSnapshot(
        score: 78,
        headline: "Looking good",
        updatedAt: .now,
        vitals: [
            WidgetVital(name: "Resting Heart Rate", value: "68 bpm", systemImage: "heart.fill"),
            WidgetVital(name: "Blood Pressure", value: "118/76 mmHg", systemImage: "waveform.path.ecg"),
        ],
        dueTests: [
            WidgetDueTest(name: "HbA1c", dueLabel: "Overdue", isOverdue: true),
            WidgetDueTest(name: "LDL", dueLabel: "2 wks", isOverdue: false),
            WidgetDueTest(name: "Glucose", dueLabel: "2 wks", isOverdue: false),
        ],
        nextDrawDateISO: Calendar.current.date(byAdding: .day, value: 13, to: .now)
    )
}

/// Reads the latest snapshot written by the app into the shared app group.
enum WidgetSnapshotStore {
    static let appGroupID = "group.com.ogureq.gemocode"
    static let snapshotKey = "widget.snapshot"

    static func load() -> WidgetSnapshot? {
        guard let defaults = UserDefaults(suiteName: appGroupID),
              let data = defaults.data(forKey: snapshotKey) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(WidgetSnapshot.self, from: data)
    }
}

// MARK: - Timeline entry

struct HealthScoreEntry: TimelineEntry {
    let date: Date
    /// `nil` means no snapshot has ever been written by the app.
    let snapshot: WidgetSnapshot?

    var snapshotDate: Date { snapshot?.updatedAt ?? date }
}

// MARK: - Timeline provider

struct HealthScoreProvider: TimelineProvider {
    func placeholder(in context: Context) -> HealthScoreEntry {
        HealthScoreEntry(date: .now, snapshot: .sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (HealthScoreEntry) -> Void) {
        completion(HealthScoreEntry(date: .now, snapshot: .sample))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<HealthScoreEntry>) -> Void) {
        let entry = HealthScoreEntry(date: .now, snapshot: WidgetSnapshotStore.load())
        let refreshDate = Calendar.current.date(byAdding: .minute, value: 30, to: .now)
            ?? Date.now.addingTimeInterval(30 * 60)
        completion(Timeline(entries: [entry], policy: .after(refreshDate)))
    }
}

// MARK: - Widget configuration

struct HealthScoreWidget: Widget {
    let kind: String = "HealthScoreWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: HealthScoreProvider()) { entry in
            HealthScoreWidgetView(entry: entry)
        }
        .configurationDisplayName("Health Score")
        .description("Your latest Gemocode health score at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: - Editorial tokens (mirrored)
//
// The widget extension cannot import the app module, so these mirror the
// `Editorial` token enum in `Gemocode/Support/Theme.swift` byte-for-byte.
// If those hex values change, update this table too. Paper-and-ink
// editorial system: flat canvas, ink typography, one accent, range-bar
// grammar instead of gauges/gradients.
private enum WidgetEditorial {
    static func canvas(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(wHex: 0x0F1114) : Color(wHex: 0xFFFFFF)
    }
    static func ink(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(wHex: 0xEEF0F2) : Color(wHex: 0x000000)
    }
    static func muted(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(wHex: 0x8D939C) : Color(wHex: 0x8F8F8F)
    }
    static func hairline(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(wHex: 0x282B31) : Color(wHex: 0xF0F0F0)
    }
    static func tagGood(_ scheme: ColorScheme) -> Color { Color(wHex: 0x2F8F5B) }
    static func tagWarn(_ scheme: ColorScheme) -> Color { Color(wHex: 0xB98317) }
    static func tagBad(_ scheme: ColorScheme) -> Color { Color(wHex: 0xCF3F2F) }
    /// The one filled accent — identical in both color schemes, mirroring
    /// `Editorial.accent`.
    static func accent(_ scheme: ColorScheme) -> Color { Color(wHex: 0x0A84FF) }
    static func zoneOut(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(wHex: 0x4D3D28) : Color(wHex: 0xE8C9A8)
    }
    static func zoneIn(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(wHex: 0x274434) : Color(wHex: 0xBFE3CD)
    }
    static func zoneOptimal(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(wHex: 0x356048) : Color(wHex: 0x9FD4B4)
    }
    static func barMarker(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? .white : .black
    }
}

private extension Color {
    /// `0xRRGGBB` convenience initializer used only to key in the mirrored
    /// editorial hex values above.
    init(wHex hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

// MARK: - Score band text (mirrors AnalysisEngine.scoreLabel wording)
//
// Duplicated rather than shared (no app-module import available). Keep the
// thresholds/wording in sync with `Gemocode/Services/AnalysisEngine.swift`
// `scoreLabel`. The widget has no strings catalog of its own (see report),
// so — matching this file's pre-existing behavior — these stay plain,
// non-localized literals rather than introducing a new catalog.
private enum WidgetTagKind {
    case good
    case warn
    case bad
}

private func widgetScoreLabel(for score: Int) -> String {
    switch score {
    case 90...100: return "Excellent"
    case 75..<90: return "Good"
    case 60..<75: return "Fair"
    case 40..<60: return "Needs Attention"
    default: return "Talk to Your Doctor"
    }
}

private func widgetScoreTagKind(for score: Int) -> WidgetTagKind {
    switch score {
    case 75...100: return .good
    case 40..<75: return .warn
    default: return .bad
    }
}

// MARK: - Root entry view

struct HealthScoreWidgetView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var colorScheme
    let entry: HealthScoreEntry

    var body: some View {
        Group {
            if let snapshot = entry.snapshot {
                Group {
                    switch family {
                    case .systemMedium:
                        MediumHealthScoreView(snapshot: snapshot, snapshotDate: entry.snapshotDate)
                    default:
                        SmallHealthScoreView(snapshot: snapshot)
                    }
                }
                // Health data must not be readable off a locked device: the
                // system swaps these views for redacted placeholders until
                // the device is unlocked. The empty state carries no data
                // and stays legible.
                .privacySensitive()
            } else {
                EmptyStateView()
            }
        }
        .containerBackground(for: .widget) {
            WidgetEditorial.canvas(colorScheme)
        }
        // Tapping the widget lands on the Review tab (handled in ContentView).
        .widgetURL(URL(string: "gemocode://review"))
    }
}

// MARK: - Shared score row (micro-label + number + tag + range bar)

private struct WidgetScoreHeader: View {
    let score: Int
    let numberSize: CGFloat
    let colorScheme: ColorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("HEALTH SCORE")
                .font(.system(size: 8, weight: .semibold))
                .kerning(0.96)
                .foregroundStyle(WidgetEditorial.muted(colorScheme))

            HStack(alignment: .lastTextBaseline, spacing: 6) {
                Text("\(score)")
                    .font(.system(size: numberSize, weight: .regular))
                    .kerning(-numberSize * 0.03)
                    .foregroundStyle(WidgetEditorial.ink(colorScheme))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)

                WidgetTag(
                    text: widgetScoreLabel(for: score),
                    kind: widgetScoreTagKind(for: score),
                    colorScheme: colorScheme
                )
            }

            WidgetScoreRangeBar(score: score, colorScheme: colorScheme)
        }
    }
}

/// Status pill mirroring `EditorialTag` from `Support/EditorialComponents.swift`
/// at widget scale (8pt vs. 9pt) — duplicated locally since the widget
/// target cannot import that file.
private struct WidgetTag: View {
    let text: String
    let kind: WidgetTagKind
    let colorScheme: ColorScheme

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 8, weight: .semibold))
            .kerning(0.48)
            .foregroundStyle(.white)
            .padding(.vertical, 2)
            .padding(.horizontal, 7)
            .background(fill, in: Capsule())
    }

    private var fill: Color {
        switch kind {
        case .good: WidgetEditorial.tagGood(colorScheme)
        case .warn: WidgetEditorial.tagWarn(colorScheme)
        case .bad: WidgetEditorial.tagBad(colorScheme)
        }
    }
}

/// Range-bar strip mirroring `RangeBar` from `Support/EditorialComponents.swift`
/// at widget scale — a fixed 40/35/25 three-zone split (matching the
/// dashboard's score bar in the mockups) with the marker at `score`/100.
/// Decorative: the header text above already states the score and band.
private struct WidgetScoreRangeBar: View {
    let score: Int
    let colorScheme: ColorScheme

    private var marker: CGFloat {
        CGFloat(Swift.min(100, Swift.max(0, score))) / 100
    }

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            let markerWidth: CGFloat = 2

            ZStack(alignment: .leading) {
                HStack(spacing: 0) {
                    WidgetEditorial.zoneOut(colorScheme).frame(width: width * 0.40, height: height)
                    WidgetEditorial.zoneIn(colorScheme).frame(width: width * 0.35, height: height)
                    WidgetEditorial.zoneOptimal(colorScheme).frame(width: width * 0.25, height: height)
                }
                WidgetEditorial.barMarker(colorScheme)
                    .frame(width: markerWidth, height: height)
                    .offset(x: Swift.min(Swift.max(0, width * marker), Swift.max(0, width - markerWidth)))
            }
        }
        .frame(height: 5)
        .clipShape(Capsule())
        .accessibilityHidden(true)
    }
}

// MARK: - Small family

private struct SmallHealthScoreView: View {
    let snapshot: WidgetSnapshot
    @Environment(\.colorScheme) private var colorScheme

    /// Every widget string below is a plain English literal by design —
    /// see the "Score band text" note above: this target has no strings
    /// catalog, so anything that must be localized (like `dueLabel`/`name`
    /// on a `WidgetDueTest`) is resolved app-side before it's written here.
    private var overdueCount: Int {
        (snapshot.dueTests ?? []).filter(\.isOverdue).count
    }

    /// "N test(s) overdue" once a schedule snapshot is available; falls
    /// back to the plain `headline` for an older snapshot with no
    /// `dueTests` at all, or once nothing is overdue.
    private var captionText: String {
        guard overdueCount > 0 else { return snapshot.headline }
        return overdueCount == 1 ? "1 test overdue" : "\(overdueCount) tests overdue"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            WidgetScoreHeader(score: snapshot.score, numberSize: 40, colorScheme: colorScheme)

            Spacer(minLength: 8)

            Text(captionText)
                .font(.system(size: 10))
                .foregroundStyle(WidgetEditorial.muted(colorScheme))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "Health score \(snapshot.score), \(widgetScoreLabel(for: snapshot.score)). \(captionText)"
        )
    }
}

// MARK: - Medium family

private struct MediumHealthScoreView: View {
    let snapshot: WidgetSnapshot
    let snapshotDate: Date
    @Environment(\.colorScheme) private var colorScheme

    private var dueTests: [WidgetDueTest] { snapshot.dueTests ?? [] }
    private var overdueCount: Int { dueTests.filter(\.isOverdue).count }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            leftTile
            rightTile
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    /// Score + tag + bar, plus an overdue-count caption — the 6u/7u left
    /// tile. Falls back to nothing (just the score header) when there's no
    /// schedule data yet, matching the small widget's own fallback.
    private var leftTile: some View {
        VStack(alignment: .leading, spacing: 8) {
            WidgetScoreHeader(score: snapshot.score, numberSize: 32, colorScheme: colorScheme)
            Spacer(minLength: 4)
            if overdueCount > 0 {
                Text(overdueCount == 1 ? "1 test overdue" : "\(overdueCount) tests overdue")
                    .font(.system(size: 10))
                    .foregroundStyle(WidgetEditorial.muted(colorScheme))
                    .lineLimit(1)
            }
        }
        .frame(width: 96, alignment: .leading)
    }

    /// "NEXT TEST" + up to 3 due rows + next-draw date + coverage caption
    /// when there's schedule data (6u/7u); otherwise the legacy vitals
    /// list this tile showed before the schedule redesign, so an
    /// old/no-schedule snapshot still renders something useful.
    @ViewBuilder
    private var rightTile: some View {
        if dueTests.isEmpty {
            legacyVitalsList
        } else {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .lastTextBaseline) {
                    Text("NEXT TEST")
                        .font(.system(size: 8, weight: .semibold))
                        .kerning(0.96)
                        .foregroundStyle(WidgetEditorial.muted(colorScheme))
                    Spacer()
                    if let nextDrawDate = snapshot.nextDrawDateISO {
                        Text(nextDrawDate, format: .dateTime.month(.abbreviated).day())
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(WidgetEditorial.accent(colorScheme))
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(dueTests.prefix(3).enumerated()), id: \.offset) { _, test in
                        HStack(spacing: 4) {
                            Text(test.name)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(WidgetEditorial.ink(colorScheme))
                                .lineLimit(1)
                            Spacer(minLength: 4)
                            WidgetTag(text: test.dueLabel, kind: test.isOverdue ? .bad : .warn, colorScheme: colorScheme)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                .padding(.top, 10)

                Spacer(minLength: 4)

                Text(dueTests.count == 1 ? "one visit covers it" : "one visit covers all \(dueTests.count)")
                    .font(.system(size: 10))
                    .foregroundStyle(WidgetEditorial.muted(colorScheme))
                    .lineLimit(1)
            }
        }
    }

    /// Pre-redesign medium-widget content: up to 3 vitals with a
    /// "Updated …" relative timestamp. Kept verbatim as the fallback for a
    /// snapshot with no `dueTests` (e.g. written by an older app build, or
    /// before the user has any tracked lab tests).
    private var legacyVitalsList: some View {
        let vitals = Array(snapshot.vitals.prefix(3))
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(vitals.enumerated()), id: \.offset) { index, vital in
                HStack(spacing: 6) {
                    Image(systemName: vital.systemImage)
                        .font(.system(size: 11))
                        .foregroundStyle(WidgetEditorial.muted(colorScheme))
                        .accessibilityHidden(true)
                    Text(vital.name)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(WidgetEditorial.ink(colorScheme))
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text(vital.value)
                        .font(.system(size: 11))
                        .foregroundStyle(WidgetEditorial.muted(colorScheme))
                        .lineLimit(1)
                }
                .padding(.vertical, 6)
                .overlay(alignment: .bottom) {
                    if index < vitals.count - 1 {
                        Rectangle()
                            .fill(WidgetEditorial.hairline(colorScheme))
                            .frame(height: 0.5)
                    }
                }
                .accessibilityElement(children: .combine)
            }

            Spacer(minLength: 4)

            (Text("Updated ") + Text(snapshotDate, style: .relative))
                .font(.system(size: 9))
                .foregroundStyle(WidgetEditorial.muted(colorScheme))
                .lineLimit(1)
        }
    }
}

// MARK: - Empty state

private struct EmptyStateView: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "heart.text.square")
                .font(.system(size: 20))
                .foregroundStyle(WidgetEditorial.ink(colorScheme).opacity(0.55))
            Text("Open Gemocode to sync")
                .font(.system(size: 11))
                .foregroundStyle(WidgetEditorial.muted(colorScheme))
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }
}
