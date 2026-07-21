import Foundation
import WidgetKit

// MARK: - Shared app-group data contract
//
// This is the one source of truth for the JSON payload handed off to the
// GemocodeWidgets extension. The extension target cannot see this module,
// so `GemocodeWidgets/HealthScoreWidget.swift` intentionally duplicates
// these two `Codable` types — keep both definitions in sync.

/// A compact vital reading surfaced on the home-screen widget.
struct WidgetVital: Codable {
    let name: String
    let value: String
    let systemImage: String
}

/// One tracked lab test's urgency, pre-resolved into widget-safe display
/// strings — the widget extension has no strings catalog of its own, so
/// `name`/`dueLabel` must already be localized by the time they're written
/// here (see `WidgetBridge.widgetDueTest(for:now:calendar:)`).
struct WidgetDueTest: Codable {
    let name: String
    let dueLabel: String
    let isOverdue: Bool
}

/// A point-in-time snapshot of the health review, written to the shared
/// app group so the widget extension can render it without touching
/// SwiftData directly.
///
/// `dueTests`/`nextDrawDateISO` are OPTIONAL additions to this contract —
/// a snapshot written by an older build of the app never had them, and
/// must still decode cleanly in a newer widget extension (and vice versa
/// for a downgrade), per the model's backward-compat rule in CLAUDE.md.
/// `nextDrawDateISO` is a `Date` (not a `String`) so it rides the same
/// `.iso8601` encoder/decoder strategy as `updatedAt` below.
struct WidgetSnapshot: Codable {
    let score: Int
    let headline: String
    let updatedAt: Date
    let vitals: [WidgetVital]
    var dueTests: [WidgetDueTest]? = nil
    var nextDrawDateISO: Date? = nil
}

/// Publishes health review snapshots to the shared app group for the
/// Gemocode home-screen widget.
enum WidgetBridge {
    static let appGroupID = "group.com.ogureq.gemocode"
    static let snapshotKey = "widget.snapshot"

    /// Encodes a fresh snapshot and asks WidgetKit to reload timelines.
    /// Silently does nothing if the shared app group isn't available
    /// (e.g. missing entitlement in a debug build) or encoding fails.
    ///
    /// `retestItems`/`now`/`calendar` are optional — every existing call
    /// site keeps compiling unchanged and simply writes a snapshot with no
    /// due-test data (`dueTests` stays `nil`). Passing `retestItems` (e.g.
    /// `RetestSchedule.items(reports:now:)`) additionally derives the next
    /// draw bundle via `RetestSchedule.nextDraw` and populates `dueTests` +
    /// `nextDrawDateISO` from it.
    static func update(
        score: Int,
        headline: String,
        vitals: [WidgetVital],
        retestItems: [RetestItem] = [],
        now: Date = .now,
        calendar: Calendar = .current
    ) {
        guard let defaults = UserDefaults(suiteName: appGroupID) else { return }

        let bundle = RetestSchedule.nextDraw(items: retestItems, now: now, calendar: calendar)
        let dueTests = (bundle?.items ?? []).map { widgetDueTest(for: $0, now: now, calendar: calendar) }

        let snapshot = WidgetSnapshot(
            score: score,
            headline: headline,
            updatedAt: .now,
            vitals: vitals,
            dueTests: dueTests.isEmpty ? nil : dueTests,
            nextDrawDateISO: bundle?.date
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        guard let data = try? encoder.encode(snapshot) else { return }

        defaults.set(data, forKey: snapshotKey)
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: - Due-test display strings (resolved here, not in the widget)

    /// Builds one widget-safe due-test entry: a short catalog display name
    /// (falling back to the item's full name for a series with no catalog
    /// entry) and an already-localized urgency label.
    private static func widgetDueTest(for item: RetestItem, now: Date, calendar: Calendar) -> WidgetDueTest {
        WidgetDueTest(
            name: LabCatalog.reference(for: item.id)?.shortName ?? item.displayName,
            dueLabel: widgetDueLabel(for: item, now: now, calendar: calendar),
            isOverdue: item.status == .overdue
        )
    }

    /// "Overdue" for an overdue item, otherwise a compact "1 wk"/"N wks"
    /// countdown — mirrors the mockup's "Overdue"/"2 wks" tag text at
    /// widget scale. Computed from whole calendar days (via `startOfDay`)
    /// like `RetestSchedule`'s own classification, so a time-of-day
    /// mismatch never tips a week boundary the wrong way.
    private static func widgetDueLabel(for item: RetestItem, now: Date, calendar: Calendar) -> String {
        if item.status == .overdue {
            return String(localized: "Overdue")
        }
        let days = max(0, calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: now),
            to: calendar.startOfDay(for: item.dueDate)
        ).day ?? 0)
        let weeks = max(1, Int((Double(days) / 7).rounded(.up)))
        return weeks == 1
            ? String(localized: "1 wk")
            : String(format: String(localized: "%lld wks"), weeks)
    }
}
