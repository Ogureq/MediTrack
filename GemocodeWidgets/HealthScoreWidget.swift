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

/// A point-in-time snapshot of the health review, read from the shared
/// app group.
struct WidgetSnapshot: Codable {
    let score: Int
    let headline: String
    let updatedAt: Date
    let vitals: [WidgetVital]
}

extension WidgetSnapshot {
    /// Sample data used for the widget gallery placeholder/snapshot.
    static let sample = WidgetSnapshot(
        score: 92,
        headline: "Looking good",
        updatedAt: .now,
        vitals: [
            WidgetVital(name: "Resting Heart Rate", value: "68 bpm", systemImage: "heart.fill"),
            WidgetVital(name: "Blood Pressure", value: "118/76 mmHg", systemImage: "waveform.path.ecg"),
        ]
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

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            WidgetScoreHeader(score: snapshot.score, numberSize: 40, colorScheme: colorScheme)

            Spacer(minLength: 8)

            Text(snapshot.headline)
                .font(.system(size: 10))
                .foregroundStyle(WidgetEditorial.muted(colorScheme))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "Health score \(snapshot.score), \(widgetScoreLabel(for: snapshot.score)). \(snapshot.headline)"
        )
    }
}

// MARK: - Medium family

private struct MediumHealthScoreView: View {
    let snapshot: WidgetSnapshot
    let snapshotDate: Date
    @Environment(\.colorScheme) private var colorScheme

    private var vitals: [WidgetVital] { Array(snapshot.vitals.prefix(3)) }

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            WidgetScoreHeader(score: snapshot.score, numberSize: 32, colorScheme: colorScheme)
                .frame(width: 96, alignment: .leading)

            VStack(alignment: .leading, spacing: 0) {
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
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
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
