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

/// A point-in-time snapshot of the health review, written to the shared
/// app group so the widget extension can render it without touching
/// SwiftData directly.
struct WidgetSnapshot: Codable {
    let score: Int
    let headline: String
    let updatedAt: Date
    let vitals: [WidgetVital]
}

/// Publishes health review snapshots to the shared app group for the
/// Gemocode home-screen widget.
enum WidgetBridge {
    static let appGroupID = "group.com.ogureq.gemocode"
    static let snapshotKey = "widget.snapshot"

    /// Encodes a fresh snapshot and asks WidgetKit to reload timelines.
    /// Silently does nothing if the shared app group isn't available
    /// (e.g. missing entitlement in a debug build) or encoding fails.
    static func update(score: Int, headline: String, vitals: [WidgetVital]) {
        guard let defaults = UserDefaults(suiteName: appGroupID) else { return }

        let snapshot = WidgetSnapshot(
            score: score,
            headline: headline,
            updatedAt: .now,
            vitals: vitals
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        guard let data = try? encoder.encode(snapshot) else { return }

        defaults.set(data, forKey: snapshotKey)
        WidgetCenter.shared.reloadAllTimelines()
    }
}
