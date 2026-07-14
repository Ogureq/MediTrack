import SwiftUI
import UIKit
import CoreTransferable
import UniformTypeIdentifiers

// MARK: - Shareable, redacted score card
//
// A fixed-size view designed purely for image export (ShareLink /
// ImageRenderer), meant to be posted outside the app. It is deliberately
// redacted: only the score, its label, and a couple of anonymous rollup
// counts are shown — never the user's name, birthdate, lab values, or any
// finding text. See `DashboardView.scoreCard` for the call site that
// supplies the (already-anonymous) stats and renders this to a UIImage.

/// A single anonymous rollup stat shown on the share card — a count or a
/// direction word only. Callers must never pass raw lab/vital values or
/// finding text here.
struct ShareStat: Identifiable {
    let id = UUID()
    let systemImage: String
    let text: String
}

struct ScoreShareCard: View {
    let score: Int
    let scoreLabel: String
    let stats: [ShareStat]
    let generatedAt: Date

    /// Card size in points. Rendered at 3x scale by `ImageRenderer` for a
    /// 1080x1350px (4:5) export — see `ScoreShareImage` below.
    static let size = CGSize(width: 360, height: 450)

    private var ringColor: Color {
        switch score {
        case 75...: .green
        case 60..<75: .yellow
        case 40..<60: .orange
        default: .red
        }
    }

    var body: some View {
        ZStack {
            background
            VStack(spacing: 0) {
                header
                Spacer(minLength: 8)
                ring
                Spacer(minLength: 8)
                statsList
                Spacer(minLength: 10)
                footer
            }
            .padding(28)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Gemocode health score, \(score) out of 100, \(scoreLabel).")
    }

    // MARK: Background

    /// Hardcoded dark gradient (not driven by `colorScheme`) so the
    /// exported image always looks the same regardless of the sharer's or
    /// viewer's device appearance — this mirrors `ReviewPDFPage`, which
    /// also hardcodes its own look for exported output.
    private var background: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.03, green: 0.10, blue: 0.14), Color(red: 0.01, green: 0.03, blue: 0.08)],
                startPoint: .top,
                endPoint: .bottom
            )
            Circle()
                .fill(Color.teal.opacity(0.35))
                .frame(width: 260, height: 260)
                .blur(radius: 70)
                .offset(x: -100, y: -190)
            Circle()
                .fill(Color.blue.opacity(0.30))
                .frame(width: 240, height: 240)
                .blur(radius: 80)
                .offset(x: 110, y: 200)
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "cross.case.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Glass.accentGradient)
            Text("Gemocode")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Score ring
    //
    // A static (non-animating) ring, deliberately separate from the
    // dashboard's `ScoreRing`: `ImageRenderer` snapshots the view tree
    // synchronously, so an `onAppear`-driven animation could be captured
    // mid-flight or at its zero starting state.

    private var ring: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.14), lineWidth: 16)
            Circle()
                .trim(from: 0, to: max(0.02, CGFloat(score) / 100))
                .stroke(
                    AngularGradient(
                        gradient: Gradient(colors: [ringColor.opacity(0.5), ringColor]),
                        center: .center,
                        startAngle: .degrees(0),
                        endAngle: .degrees(360 * Double(score) / 100)
                    ),
                    style: StrokeStyle(lineWidth: 16, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            VStack(spacing: 2) {
                Text("\(score)")
                    .font(.system(size: 56, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text("of 100")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
                Text(scoreLabel)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(ringColor)
                    .padding(.top, 2)
            }
        }
        .frame(width: 200, height: 200)
    }

    // MARK: Anonymous stats

    private var statsList: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(stats) { stat in
                HStack(spacing: 10) {
                    Image(systemName: stat.systemImage)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.85))
                        .frame(width: 20)
                    Text(stat.text)
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.9))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Footer

    private var footer: some View {
        Text("Tracked privately, on-device")
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.white.opacity(0.45))
            .frame(maxWidth: .infinity, alignment: .center)
    }
}

// MARK: - Transferable PNG export

enum ScoreShareError: Error {
    case renderingFailed
}

/// Lets a `ShareLink` lazily render `ScoreShareCard` to a PNG only when the
/// user actually shares it — same lazy-render pattern as `ReviewPDF` in
/// `ReviewPDFExporter.swift`. Because the rendered image is a flat picture
/// of `ScoreShareCard` alone, nothing beyond that view's own (already
/// redacted) content can ever be included in the share.
struct ScoreShareImage: Transferable {
    let score: Int
    let scoreLabel: String
    let stats: [ShareStat]
    let generatedAt: Date

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .png) { item in
            try await MainActor.run { () throws -> Data in
                let card = ScoreShareCard(
                    score: item.score,
                    scoreLabel: item.scoreLabel,
                    stats: item.stats,
                    generatedAt: item.generatedAt
                )
                let renderer = ImageRenderer(content: card)
                renderer.scale = 3
                guard let data = renderer.uiImage?.pngData() else {
                    throw ScoreShareError.renderingFailed
                }
                return data
            }
        }
    }
}
