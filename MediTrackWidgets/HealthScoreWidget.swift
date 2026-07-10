import WidgetKit
import SwiftUI

// MARK: - Shared data contract
//
// This target cannot see the MediTrack app module, so the two `Codable`
// types below intentionally duplicate `MediTrack/Services/WidgetBridge.swift`.
// Keep both definitions in sync: app group "group.com.ogureq.meditrack",
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
    static let appGroupID = "group.com.ogureq.meditrack"
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
        .description("Your latest MediTrack health score at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: - Score color logic

private func scoreColor(for score: Int) -> Color {
    switch score {
    case 80...:
        return .teal
    case 60..<80:
        return .orange
    default:
        return .red
    }
}

// MARK: - Root entry view

struct HealthScoreWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: HealthScoreEntry

    var body: some View {
        Group {
            if let snapshot = entry.snapshot {
                switch family {
                case .systemMedium:
                    MediumHealthScoreView(snapshot: snapshot, snapshotDate: entry.snapshotDate)
                default:
                    SmallHealthScoreView(snapshot: snapshot)
                }
            } else {
                EmptyStateView()
            }
        }
        .containerBackground(for: .widget) {
            backgroundGradient
        }
    }

    private var backgroundGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.07, green: 0.11, blue: 0.18),
                Color(red: 0.03, green: 0.05, blue: 0.10),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

// MARK: - Score ring

private struct ScoreRingView: View {
    let score: Int
    var lineWidth: CGFloat = 9

    private var color: Color { scoreColor(for: score) }

    private var trimFraction: CGFloat {
        CGFloat(max(0, min(100, score))) / 100
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.16), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.02, trimFraction))
                .stroke(
                    LinearGradient(
                        colors: [color.opacity(0.55), color],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            VStack(spacing: 1) {
                Text("\(score)")
                    .font(.title2.bold())
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                Text("Health Score")
                    .font(.system(size: 8.5))
                    .foregroundStyle(.white.opacity(0.65))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
    }
}

// MARK: - Small family

private struct SmallHealthScoreView: View {
    let snapshot: WidgetSnapshot

    var body: some View {
        ScoreRingView(score: snapshot.score)
            .padding(10)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Medium family

private struct MediumHealthScoreView: View {
    let snapshot: WidgetSnapshot
    let snapshotDate: Date

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            ScoreRingView(score: snapshot.score, lineWidth: 8)
                .frame(width: 74, height: 74)

            VStack(alignment: .leading, spacing: 5) {
                Text(snapshot.headline)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)

                ForEach(Array(snapshot.vitals.prefix(3)), id: \.name) { vital in
                    Label(vital.value, systemImage: vital.systemImage)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.75))
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                (Text("Updated ") + Text(snapshotDate, style: .relative))
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

// MARK: - Empty state

private struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "heart.text.square")
                .font(.title2)
                .foregroundStyle(.white.opacity(0.7))
            Text("Open MediTrack to sync")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
