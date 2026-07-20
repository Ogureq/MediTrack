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
// finding text. See `DashboardView.scoreHeader` for the call site that
// supplies the (already-anonymous) stats and renders this to a UIImage.
//
// Styled paper-and-ink, matching `DashboardView`'s own score header: a 64pt
// score, an `EditorialTag`, and the same three-zone `RangeBar`.

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

    /// Fixed to light mode regardless of the sharer's or viewer's system
    /// appearance — like the dark gradient this replaces, the exported
    /// image must always look the same. The editorial system's canonical
    /// look is the light "paper" palette, so every `Editorial` token below
    /// is read with `.light` explicitly (rather than an `@Environment`
    /// read, which would reflect this view's real environment instead).
    private let scheme: ColorScheme = .light

    private var tagKind: TagKind {
        switch score {
        case 75...: .good
        case 60..<75: .warn
        default: .bad
        }
    }

    var body: some View {
        ZStack {
            background
            VStack(spacing: 0) {
                header
                Spacer(minLength: 10)
                scoreBlock
                Spacer(minLength: 18)
                statsList
                Spacer(minLength: 14)
                footer
            }
            .padding(28)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
        // Forces every descendant that reads `@Environment(\.colorScheme)`
        // itself (`RangeBar`, `EditorialTag`) to the same fixed `.light`
        // look as the tokens read directly above, regardless of the actual
        // system appearance in effect when `ImageRenderer` snapshots this.
        .environment(\.colorScheme, .light)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Gemocode health score, \(score) out of 100, \(scoreLabel).")
    }

    // MARK: Background

    private var background: some View {
        Editorial.canvas(scheme)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "cross.case.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Editorial.ink(scheme))
            Text("Gemocode")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(Editorial.ink(scheme))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Score block
    //
    // A static (non-animating) score + tag + range bar, mirroring
    // `DashboardView.scoreHeader`'s treatment. Deliberately separate from
    // the dashboard's own live view: `ImageRenderer` snapshots the view
    // tree synchronously, so anything animated could be captured mid-flight.

    private var scoreBlock: some View {
        VStack(spacing: 14) {
            HStack(alignment: .lastTextBaseline, spacing: 12) {
                Text("\(score)")
                    .font(.system(size: 64, weight: .regular))
                    .kerning(-2.56)
                    .foregroundStyle(Editorial.ink(scheme))
                EditorialTag(verbatim: scoreLabel, kind: tagKind)
            }
            RangeBar(
                zones: [
                    (fraction: 0.40, kind: .out),
                    (fraction: 0.35, kind: .inRange),
                    (fraction: 0.25, kind: .optimal),
                ],
                marker: CGFloat(score) / 100
            )
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: Anonymous stats

    private var statsList: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(stats) { stat in
                HStack(spacing: 10) {
                    Image(systemName: stat.systemImage)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Editorial.muted(scheme))
                        .frame(width: 20)
                    Text(stat.text)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Editorial.ink(scheme))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Footer

    private var footer: some View {
        Text("Tracked privately, on-device")
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(Editorial.muted(scheme))
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
