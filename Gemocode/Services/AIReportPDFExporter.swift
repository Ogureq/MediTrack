import Foundation
import UIKit

// MARK: - AI Health Analysis PDF export
//
// Renders a verified `AIHealthReport` (from `AISummaryService`, generated
// automatically right after a scan in `ScanReportView`) as a polished,
// shareable PDF. The document's textual content is built once as a pure,
// UIKit-free `[Block]` array (`layoutBlocks`) — `layoutText` flattens that
// to a plain `[String]` for content-only unit tests (see
// `AIReportPDFExporterTests`), and `render` walks the same blocks to draw a
// paginated PDF with `UIGraphicsPDFRenderer`. Keeping one array as the
// single source of truth means the doctor-questions lead-in, the
// disclaimer text, every section title, and every scanned lab name are all
// verifiable without touching Core Graphics.
//
// HARD SAFETY RULE (mirrors `AISummaryService`'s system prompt): this
// exporter never adds its own medical instructions. The only fixed copy it
// contributes is `doctorQuestionsLeadIn` (framed as topics to raise with a
// doctor, never as an instruction to take/start/stop/change anything) and
// the disclaimer text below — everything else comes straight from the
// already-verified `AIHealthReport`/`HealthReview`.
enum AIReportPDFExporter {

    // MARK: - Fixed copy (single source of truth — quoted by tests)

    static let scannedValuesSectionTitle = "Scanned Values"
    static let doctorQuestionsSectionTitle = "Questions & topics for your doctor"
    static let doctorQuestionsLeadIn =
        "Bring these to your next appointment — including any medication or supplement changes your doctor may recommend."
    static let aiGeneratedDisclaimer =
        "This document was generated with AI assistance and verified against your recorded values. It is educational, not medical advice, and is not a prescription."

    private static let documentTitle = "AI Health Analysis"
    private static let appName = "Gemocode"

    // MARK: - Pure content model

    /// One row of the scanned-values table. `status` (not just its label)
    /// is kept so `render` can color the status dot.
    struct LabRow {
        let name: String
        let valueUnit: String
        let status: LabStatus
    }

    /// A tagged block of document content — deliberately UIKit-free so
    /// `layoutBlocks`/`layoutText` can run with zero rendering dependency.
    enum Block {
        case title(String)
        case meta(String)
        case sectionHeader(String)
        case paragraph(String)
        case tableHeader
        case tableRow(LabRow)
        case bullet(String)
        case disclaimer(String)
        case spacer
    }

    /// Builds the whole report's content, in display order, as a pure
    /// `[Block]` array. Scanned lab status/range is read from `review`'s
    /// already-computed `labSnapshots` (matched by `LabResult.seriesKey`)
    /// rather than recomputed here, so the exporter never re-derives a
    /// clinical judgment the analysis engine already made.
    static func layoutBlocks(
        report: AIHealthReport,
        review: HealthReview,
        scannedLabs: [LabResult],
        profileName: String,
        generatedAt: Date
    ) -> [Block] {
        var blocks: [Block] = []

        blocks.append(.title(documentTitle))
        blocks.append(.meta(appName))
        blocks.append(.meta(generatedAt.formatted(date: .long, time: .shortened)))
        if !profileName.isEmpty {
            blocks.append(.meta(profileName))
        }
        blocks.append(.spacer)

        if !scannedLabs.isEmpty {
            blocks.append(.sectionHeader(scannedValuesSectionTitle))
            blocks.append(.tableHeader)
            for lab in scannedLabs {
                blocks.append(.tableRow(row(for: lab, review: review)))
            }
            blocks.append(.spacer)
        }

        blocks.append(.sectionHeader("Overview"))
        blocks.append(.paragraph(report.overview))
        blocks.append(.spacer)

        for section in report.sections {
            blocks.append(.sectionHeader(section.title))
            blocks.append(.paragraph(section.body))
        }
        if !report.sections.isEmpty {
            blocks.append(.spacer)
        }

        blocks.append(.paragraph("Overall health score: \(review.score)/100 (\(review.scoreLabel))."))
        blocks.append(.spacer)

        blocks.append(.sectionHeader(doctorQuestionsSectionTitle))
        blocks.append(.paragraph(doctorQuestionsLeadIn))
        for question in report.doctorQuestions {
            blocks.append(.bullet(question))
        }
        blocks.append(.spacer)

        blocks.append(.disclaimer(HealthReview.disclaimer))
        blocks.append(.disclaimer(aiGeneratedDisclaimer))

        return blocks
    }

    /// Matches a scanned `LabResult` to its already-evaluated status in
    /// `review.labSnapshots` (by `seriesKey`). Falls back to computing the
    /// status locally only if no snapshot matches — this should only ever
    /// happen if the caller passed a `review` that didn't actually include
    /// this lab result.
    private static func row(for lab: LabResult, review: HealthReview) -> LabRow {
        let name = lab.displayName
        let valueUnit = "\(lab.value.compactFormatted) \(lab.unit)"
        if let snapshot = review.labSnapshots.first(where: { $0.id == lab.seriesKey }) {
            return LabRow(name: name, valueUnit: valueUnit, status: snapshot.status)
        }
        let range = lab.referenceRange(for: nil)
        let status = AnalysisEngine.status(
            value: lab.value,
            range: range,
            criticalLow: lab.catalogReference?.criticalLow,
            criticalHigh: lab.catalogReference?.criticalHigh
        )
        return LabRow(name: name, valueUnit: valueUnit, status: status)
    }

    /// Flattens `layoutBlocks` to plain visible text, one entry per block —
    /// the pure, testable projection of the document's content. `render`
    /// draws from the richer `layoutBlocks` (which retains table columns
    /// and status colors); this is the same underlying content, just
    /// without layout/styling metadata.
    static func layoutText(
        report: AIHealthReport,
        review: HealthReview,
        scannedLabs: [LabResult],
        profileName: String,
        generatedAt: Date
    ) -> [String] {
        layoutBlocks(
            report: report,
            review: review,
            scannedLabs: scannedLabs,
            profileName: profileName,
            generatedAt: generatedAt
        ).compactMap(textContent)
    }

    private static func textContent(of block: Block) -> String? {
        switch block {
        case .title(let text): text
        case .meta(let text): text
        case .sectionHeader(let text): text
        case .paragraph(let text): text
        case .tableHeader: "Test | Result | Status"
        case .tableRow(let row): "\(row.name): \(row.valueUnit) — \(row.status.label)"
        case .bullet(let text): text
        case .disclaimer(let text): text
        case .spacer: nil
        }
    }

    // MARK: - Rendering (UIGraphicsPDFRenderer, US Letter, paginated)

    private static let pageWidth: CGFloat = 612
    private static let pageHeight: CGFloat = 792
    private static let margin: CGFloat = 36
    private static var contentWidth: CGFloat { pageWidth - margin * 2 }

    private static func color(for status: LabStatus) -> UIColor {
        switch status {
        case .criticalLow, .criticalHigh: .systemRed
        case .low, .high: .systemOrange
        case .normal: .systemGreen
        case .unknown: .systemGray
        }
    }

    /// Renders the report as a paginated PDF and returns its bytes. Pure
    /// and deterministic given its inputs — no networking, no wall-clock
    /// reads (the caller supplies `generatedAt`).
    static func render(
        report: AIHealthReport,
        review: HealthReview,
        scannedLabs: [LabResult],
        profileName: String,
        generatedAt: Date
    ) -> Data {
        let blocks = layoutBlocks(
            report: report,
            review: review,
            scannedLabs: scannedLabs,
            profileName: profileName,
            generatedAt: generatedAt
        )

        let pageRect = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)

        return renderer.pdfData { context in
            var y: CGFloat = margin
            var pageOpen = false

            func openPage() {
                context.beginPage()
                pageOpen = true
                y = margin
            }

            func ensurePageOpen() {
                if !pageOpen { openPage() }
            }

            func ensureRoom(for height: CGFloat) {
                ensurePageOpen()
                if y + height > pageHeight - margin {
                    openPage()
                }
            }

            func drawText(_ text: String, font: UIFont, color: UIColor, spacingAfter: CGFloat) {
                guard !text.isEmpty else { return }
                let attributed = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color])
                let bounds = attributed.boundingRect(
                    with: CGSize(width: contentWidth, height: .greatestFiniteMagnitude),
                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                    context: nil
                )
                let height = ceil(bounds.height)
                ensureRoom(for: height)
                attributed.draw(in: CGRect(x: margin, y: y, width: contentWidth, height: height))
                y += height + spacingAfter
            }

            for block in blocks {
                switch block {
                case .title(let text):
                    drawText(text, font: .boldSystemFont(ofSize: 22), color: .black, spacingAfter: 4)
                case .meta(let text):
                    drawText(text, font: .systemFont(ofSize: 10), color: UIColor(white: 0.35, alpha: 1), spacingAfter: 2)
                case .sectionHeader(let text):
                    drawText(
                        text,
                        font: .boldSystemFont(ofSize: 13),
                        color: UIColor(red: 0.04, green: 0.50, blue: 0.54, alpha: 1),
                        spacingAfter: 4
                    )
                case .paragraph(let text):
                    drawText(text, font: .systemFont(ofSize: 11), color: .black, spacingAfter: 8)
                case .bullet(let text):
                    drawText("•  \(text)", font: .systemFont(ofSize: 11), color: .black, spacingAfter: 6)
                case .disclaimer(let text):
                    drawText(text, font: .systemFont(ofSize: 8.5), color: UIColor(white: 0.4, alpha: 1), spacingAfter: 6)
                case .tableHeader:
                    ensureRoom(for: 14)
                    let headerFont = UIFont.boldSystemFont(ofSize: 9.5)
                    let headerColor = UIColor(white: 0.4, alpha: 1)
                    ("TEST" as NSString).draw(
                        in: CGRect(x: margin, y: y, width: contentWidth * 0.5, height: 14),
                        withAttributes: [.font: headerFont, .foregroundColor: headerColor]
                    )
                    ("RESULT" as NSString).draw(
                        in: CGRect(x: margin + contentWidth * 0.5, y: y, width: contentWidth * 0.3, height: 14),
                        withAttributes: [.font: headerFont, .foregroundColor: headerColor]
                    )
                    ("STATUS" as NSString).draw(
                        in: CGRect(x: margin + contentWidth * 0.8, y: y, width: contentWidth * 0.2, height: 14),
                        withAttributes: [.font: headerFont, .foregroundColor: headerColor]
                    )
                    y += 16
                case .tableRow(let row):
                    let rowHeight: CGFloat = 16
                    ensureRoom(for: rowHeight)
                    let statusColor = color(for: row.status)
                    (row.name as NSString).draw(
                        in: CGRect(x: margin, y: y, width: contentWidth * 0.5, height: rowHeight),
                        withAttributes: [.font: UIFont.systemFont(ofSize: 10.5), .foregroundColor: UIColor.black]
                    )
                    (row.valueUnit as NSString).draw(
                        in: CGRect(x: margin + contentWidth * 0.5, y: y, width: contentWidth * 0.3, height: rowHeight),
                        withAttributes: [.font: UIFont.boldSystemFont(ofSize: 10.5), .foregroundColor: UIColor.black]
                    )
                    let dotRect = CGRect(x: margin + contentWidth * 0.8, y: y + 4, width: 8, height: 8)
                    context.cgContext.setFillColor(statusColor.cgColor)
                    context.cgContext.fillEllipse(in: dotRect)
                    (row.status.label as NSString).draw(
                        in: CGRect(x: margin + contentWidth * 0.8 + 12, y: y, width: contentWidth * 0.2 - 12, height: rowHeight),
                        withAttributes: [.font: UIFont.systemFont(ofSize: 9), .foregroundColor: statusColor]
                    )
                    y += rowHeight + 2
                case .spacer:
                    if pageOpen { y += 10 }
                }
            }

            // Guarantees at least one page even for a degenerate empty report.
            ensurePageOpen()
        }
    }
}
