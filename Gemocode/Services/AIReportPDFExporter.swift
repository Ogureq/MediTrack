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
// doctor, never as an instruction to take/start/stop/change anything), the
// "needs attention"/all-clear box copy (a restatement of already-verified
// status/range data, not a recommendation), and the disclaimer text below —
// everything else comes straight from the already-verified
// `AIHealthReport`/`HealthReview`.
enum AIReportPDFExporter {

    // MARK: - Fixed copy (single source of truth — quoted by tests)

    static let scannedValuesSectionTitle = "Scanned Values"
    static let attentionBoxTitle = "Needs attention"
    static let allNormalMessage = "All scanned values are within their typical ranges."
    static let doctorQuestionsSectionTitle = "Questions & topics for your doctor"
    static let doctorQuestionsLeadIn =
        "Bring these to your next appointment — including any medication or supplement changes your doctor may recommend."
    static let aiGeneratedDisclaimer =
        "This document was generated with AI assistance and verified against your recorded values. It is educational, not medical advice, and is not a prescription."

    private static let documentTitle = "AI Health Analysis"
    private static let appName = "Gemocode"
    private static let footerLeftText = "Gemocode · AI Health Analysis"

    // MARK: - Pure content model

    /// The full-width band at the top of the document. Kept as its own
    /// struct (rather than reusing `.meta` strings) so `render` can lay the
    /// title/subtitle out inside a filled rect while `layoutText` still
    /// surfaces every piece of text it contains.
    struct HeaderInfo {
        let title: String
        let appName: String
        let generatedAtText: String
        let profileName: String
    }

    /// One row of the scanned-values table — also reused, unmodified, for
    /// the "needs attention" box, so the two can never disagree about a
    /// lab's status or range. `range` (not just formatted text) is kept so
    /// `render` can decide layout; `rangeColumnText`/`rangeSpanText` are the
    /// two textual projections the table column and the attention line need.
    struct LabRow {
        let name: String
        let value: Double
        let unit: String
        let status: LabStatus
        let range: ClosedRange<Double>?

        var valueUnit: String { "\(value.compactFormatted) \(unit)" }

        /// "100–199 mg/dL" for the table's TYPICAL RANGE column, or an em
        /// dash when the range is unknown.
        var rangeColumnText: String {
            guard let range else { return "—" }
            return "\(range.lowerBound.compactFormatted)–\(range.upperBound.compactFormatted) \(unit)"
        }

        /// "100–199" (no unit — the value already carries one) for the
        /// attention-box line, e.g. "245 mg/dL — High · typical 100–199".
        var rangeSpanText: String {
            guard let range else { return "not available" }
            return "\(range.lowerBound.compactFormatted)–\(range.upperBound.compactFormatted)"
        }
    }

    /// A tagged block of document content — deliberately UIKit-free so
    /// `layoutBlocks`/`layoutText` can run with zero rendering dependency.
    enum Block {
        case headerBand(HeaderInfo)
        case attentionBox([LabRow])
        case allClearBox(String)
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

        blocks.append(.headerBand(HeaderInfo(
            title: documentTitle,
            appName: appName,
            generatedAtText: generatedAt.formatted(date: .long, time: .shortened),
            profileName: profileName
        )))
        blocks.append(.spacer)

        if !scannedLabs.isEmpty {
            let rows = scannedLabs.map { row(for: $0, review: review) }
            let abnormalRows = rows.filter { $0.status.isOutOfRange }
            if abnormalRows.isEmpty {
                blocks.append(.allClearBox(allNormalMessage))
            } else {
                blocks.append(.attentionBox(abnormalRows))
            }
            blocks.append(.spacer)

            blocks.append(.sectionHeader(scannedValuesSectionTitle))
            blocks.append(.tableHeader)
            for row in rows {
                blocks.append(.tableRow(row))
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

    /// Matches a scanned `LabResult` to its already-evaluated status/range in
    /// `review.labSnapshots` (by `seriesKey`). Falls back to computing both
    /// locally only if no snapshot matches — this should only ever happen if
    /// the caller passed a `review` that didn't actually include this lab
    /// result.
    private static func row(for lab: LabResult, review: HealthReview) -> LabRow {
        let name = lab.displayName
        if let snapshot = review.labSnapshots.first(where: { $0.id == lab.seriesKey }) {
            return LabRow(name: name, value: lab.value, unit: lab.unit, status: snapshot.status, range: snapshot.range)
        }
        let range = lab.referenceRange(for: nil)
        let status = AnalysisEngine.status(
            value: lab.value,
            range: range,
            criticalLow: lab.catalogReference?.criticalLow,
            criticalHigh: lab.catalogReference?.criticalHigh
        )
        return LabRow(name: name, value: lab.value, unit: lab.unit, status: status, range: range)
    }

    /// Flattens `layoutBlocks` to plain visible text — the pure, testable
    /// projection of the document's content. A block may expand to zero,
    /// one, or several lines (e.g. the header band's title/app name/date,
    /// or one line per attention-box row); `render` draws from the richer
    /// `layoutBlocks` (which retains table columns, ranges, and status
    /// colors), so this is the same underlying content without layout
    /// metadata.
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
        ).flatMap(textLines)
    }

    private static func textLines(of block: Block) -> [String] {
        switch block {
        case .headerBand(let info):
            var lines = [info.title, info.appName, info.generatedAtText]
            if !info.profileName.isEmpty { lines.append(info.profileName) }
            return lines
        case .attentionBox(let rows):
            return rows.map(attentionLine)
        case .allClearBox(let text):
            return [text]
        case .sectionHeader(let text): return [text]
        case .paragraph(let text): return [text]
        case .tableHeader: return ["TEST | RESULT | TYPICAL RANGE | STATUS"]
        case .tableRow(let row): return [tableRowLine(row)]
        case .bullet(let text): return [text]
        case .disclaimer(let text): return [text]
        case .spacer: return []
        }
    }

    /// "Total Cholesterol: 245 mg/dL — High · typical 100–199" — name,
    /// value+unit, status, and typical range on one line, as used both by
    /// the attention box's content and its `layoutText` projection.
    private static func attentionLine(_ row: LabRow) -> String {
        "\(row.name): \(row.valueUnit) — \(row.status.label) · typical \(row.rangeSpanText)"
    }

    private static func tableRowLine(_ row: LabRow) -> String {
        "\(row.name): \(row.valueUnit) — \(row.status.label) (typical \(row.rangeColumnText))"
    }

    // MARK: - Rendering (UIGraphicsPDFRenderer, US Letter, paginated)

    private static let pageWidth: CGFloat = 612
    private static let pageHeight: CGFloat = 792
    private static let margin: CGFloat = 36
    private static var contentWidth: CGFloat { pageWidth - margin * 2 }

    private static let headerBandHeight: CGFloat = 92
    private static let footerReservedHeight: CGFloat = 30

    // Deep teal → blue, print-friendly (holds up in grayscale printing,
    // unlike a pastel or fully-saturated gradient).
    private static let bandColorStart = UIColor(red: 10.0 / 255, green: 110.0 / 255, blue: 122.0 / 255, alpha: 1)
    private static let bandColorEnd = UIColor(red: 10.0 / 255, green: 132.0 / 255, blue: 1.0, alpha: 1)

    private static let sectionRuleColor = UIColor(red: 0.04, green: 0.50, blue: 0.54, alpha: 0.35)
    private static let zebraRowColor = UIColor(white: 0.96, alpha: 1)

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
    /// reads (the caller supplies `generatedAt`), and the footer's page
    /// numbers fall directly out of the same content-driven pagination, not
    /// a separate counting pass.
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
            var pageNumber = 0
            // Alternating-row shading counter for the scanned-values table
            // — reset to 0 on every `.tableHeader` so zebra striping
            // restarts per table rather than continuing across pages.
            var tableRowIndex = 0

            func drawFooter() {
                let font = UIFont.systemFont(ofSize: 8.5)
                let color = UIColor(white: 0.45, alpha: 1)
                let baselineY = pageHeight - footerReservedHeight + 8
                (footerLeftText as NSString).draw(
                    at: CGPoint(x: margin, y: baselineY),
                    withAttributes: [.font: font, .foregroundColor: color]
                )
                let pageText = "Page \(pageNumber)"
                let size = (pageText as NSString).size(withAttributes: [.font: font])
                (pageText as NSString).draw(
                    at: CGPoint(x: pageWidth - margin - size.width, y: baselineY),
                    withAttributes: [.font: font, .foregroundColor: color]
                )
            }

            func openPage() {
                context.beginPage()
                pageOpen = true
                pageNumber += 1
                y = margin
                // Content is always confined above `pageHeight -
                // footerReservedHeight` by `ensureRoom`, so drawing the
                // footer immediately (rather than right before the next
                // `beginPage()`) is safe — nothing drawn later on this page
                // can overwrite it.
                drawFooter()
            }

            func ensurePageOpen() {
                if !pageOpen { openPage() }
            }

            func ensureRoom(for height: CGFloat) {
                ensurePageOpen()
                if y + height > pageHeight - footerReservedHeight {
                    openPage()
                }
            }

            func measure(_ text: String, font: UIFont, width: CGFloat) -> CGFloat {
                guard !text.isEmpty else { return 0 }
                let attributed = NSAttributedString(string: text, attributes: [.font: font])
                return ceil(attributed.boundingRect(
                    with: CGSize(width: width, height: .greatestFiniteMagnitude),
                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                    context: nil
                ).height)
            }

            func drawText(_ text: String, font: UIFont, color: UIColor, spacingAfter: CGFloat) {
                guard !text.isEmpty else { return }
                let attributed = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color])
                let height = measure(text, font: font, width: contentWidth)
                ensureRoom(for: height)
                attributed.draw(in: CGRect(x: margin, y: y, width: contentWidth, height: height))
                y += height + spacingAfter
            }

            /// Header + a thin accent rule underneath, so section starts
            /// read clearly even in the middle of a dense page.
            func drawSectionHeader(_ text: String) {
                let font = UIFont.boldSystemFont(ofSize: 13)
                let headerColor = UIColor(red: 0.04, green: 0.50, blue: 0.54, alpha: 1)
                let height = measure(text, font: font, width: contentWidth)
                ensureRoom(for: height + 6)
                (text as NSString).draw(
                    in: CGRect(x: margin, y: y, width: contentWidth, height: height),
                    withAttributes: [.font: font, .foregroundColor: headerColor]
                )
                y += height + 3
                context.cgContext.setStrokeColor(sectionRuleColor.cgColor)
                context.cgContext.setLineWidth(0.75)
                context.cgContext.move(to: CGPoint(x: margin, y: y))
                context.cgContext.addLine(to: CGPoint(x: margin + contentWidth, y: y))
                context.cgContext.strokePath()
                y += 7
            }

            /// Rounded, tinted callout used for both the "needs attention"
            /// box and the all-clear box — an optional bold title followed
            /// by wrapped body lines, inset inside a filled rounded rect
            /// with a solid accent stripe on the left edge.
            func drawCallout(title: String?, lines: [String], accent: UIColor, fill: UIColor, textColor: UIColor) {
                let horizontalPadding: CGFloat = 12
                let verticalPadding: CGFloat = 10
                let titleFont = UIFont.boldSystemFont(ofSize: 11)
                let lineFont = UIFont.systemFont(ofSize: 10.5)
                let innerWidth = contentWidth - horizontalPadding * 2 - 6

                var contentHeight: CGFloat = 0
                if let title { contentHeight += measure(title, font: titleFont, width: innerWidth) + 4 }
                for line in lines { contentHeight += measure(line, font: lineFont, width: innerWidth) + 3 }
                let boxHeight = contentHeight + verticalPadding * 2

                ensureRoom(for: boxHeight)
                let boxRect = CGRect(x: margin, y: y, width: contentWidth, height: boxHeight)
                let path = UIBezierPath(roundedRect: boxRect, cornerRadius: 8)
                context.cgContext.saveGState()
                context.cgContext.setFillColor(fill.cgColor)
                context.cgContext.addPath(path.cgPath)
                context.cgContext.fillPath()
                context.cgContext.restoreGState()

                let stripe = CGRect(x: margin, y: y, width: 4, height: boxHeight)
                context.cgContext.setFillColor(accent.cgColor)
                context.cgContext.fill(stripe)

                var cursorY = y + verticalPadding
                let textX = margin + horizontalPadding + 6
                if let title {
                    let h = measure(title, font: titleFont, width: innerWidth)
                    (title as NSString).draw(
                        in: CGRect(x: textX, y: cursorY, width: innerWidth, height: h),
                        withAttributes: [.font: titleFont, .foregroundColor: textColor]
                    )
                    cursorY += h + 4
                }
                for line in lines {
                    let h = measure(line, font: lineFont, width: innerWidth)
                    (line as NSString).draw(
                        in: CGRect(x: textX, y: cursorY, width: innerWidth, height: h),
                        withAttributes: [.font: lineFont, .foregroundColor: textColor]
                    )
                    cursorY += h + 3
                }
                y = boxRect.maxY + 10
            }

            func drawHeaderBand(_ info: HeaderInfo) {
                ensurePageOpen()
                let bandRect = CGRect(x: 0, y: 0, width: pageWidth, height: headerBandHeight)
                context.cgContext.saveGState()
                context.cgContext.addRect(bandRect)
                context.cgContext.clip()
                if let gradient = CGGradient(
                    colorsSpace: CGColorSpaceCreateDeviceRGB(),
                    colors: [bandColorStart.cgColor, bandColorEnd.cgColor] as CFArray,
                    locations: [0, 1]
                ) {
                    context.cgContext.drawLinearGradient(
                        gradient,
                        start: CGPoint(x: bandRect.minX, y: bandRect.midY),
                        end: CGPoint(x: bandRect.maxX, y: bandRect.midY),
                        options: []
                    )
                } else {
                    context.cgContext.setFillColor(bandColorStart.cgColor)
                    context.cgContext.fill(bandRect)
                }
                context.cgContext.restoreGState()

                (info.title as NSString).draw(
                    in: CGRect(x: margin, y: 22, width: contentWidth, height: 28),
                    withAttributes: [.font: UIFont.boldSystemFont(ofSize: 22), .foregroundColor: UIColor.white]
                )
                let subtitleParts = [info.appName, info.generatedAtText, info.profileName].filter { !$0.isEmpty }
                let subtitle = subtitleParts.joined(separator: "  ·  ")
                (subtitle as NSString).draw(
                    in: CGRect(x: margin, y: 56, width: contentWidth, height: 18),
                    withAttributes: [.font: UIFont.systemFont(ofSize: 10.5), .foregroundColor: UIColor.white.withAlphaComponent(0.85)]
                )

                y = headerBandHeight + 16
            }

            for block in blocks {
                switch block {
                case .headerBand(let info):
                    drawHeaderBand(info)
                case .attentionBox(let rows):
                    drawCallout(
                        title: attentionBoxTitle,
                        lines: rows.map(attentionLine),
                        accent: .systemOrange,
                        fill: UIColor(red: 1.0, green: 0.94, blue: 0.86, alpha: 1),
                        textColor: UIColor(red: 0.42, green: 0.22, blue: 0.02, alpha: 1)
                    )
                case .allClearBox(let text):
                    drawCallout(
                        title: nil,
                        lines: [text],
                        accent: .systemGreen,
                        fill: UIColor(red: 0.87, green: 0.96, blue: 0.89, alpha: 1),
                        textColor: UIColor(red: 0.05, green: 0.35, blue: 0.14, alpha: 1)
                    )
                case .sectionHeader(let text):
                    drawSectionHeader(text)
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
                        in: CGRect(x: margin, y: y, width: contentWidth * tableColumnTest, height: 14),
                        withAttributes: [.font: headerFont, .foregroundColor: headerColor]
                    )
                    ("RESULT" as NSString).draw(
                        in: CGRect(x: margin + contentWidth * tableColumnTest, y: y, width: contentWidth * tableColumnResult, height: 14),
                        withAttributes: [.font: headerFont, .foregroundColor: headerColor]
                    )
                    ("TYPICAL RANGE" as NSString).draw(
                        in: CGRect(x: margin + contentWidth * (tableColumnTest + tableColumnResult), y: y, width: contentWidth * tableColumnRange, height: 14),
                        withAttributes: [.font: headerFont, .foregroundColor: headerColor]
                    )
                    ("STATUS" as NSString).draw(
                        in: CGRect(x: margin + contentWidth * (tableColumnTest + tableColumnResult + tableColumnRange), y: y, width: contentWidth * tableColumnStatus, height: 14),
                        withAttributes: [.font: headerFont, .foregroundColor: headerColor]
                    )
                    y += 16
                    tableRowIndex = 0
                case .tableRow(let row):
                    let rowHeight: CGFloat = 16
                    ensureRoom(for: rowHeight)
                    let statusColor = color(for: row.status)

                    // Abnormal rows get a faint tint of their status color;
                    // otherwise alternate rows get a very light gray fill
                    // (zebra striping) so a dense panel stays readable.
                    if row.status.isOutOfRange {
                        context.cgContext.setFillColor(statusColor.withAlphaComponent(0.10).cgColor)
                        context.cgContext.fill(CGRect(x: margin, y: y, width: contentWidth, height: rowHeight))
                    } else if tableRowIndex % 2 == 1 {
                        context.cgContext.setFillColor(zebraRowColor.cgColor)
                        context.cgContext.fill(CGRect(x: margin, y: y, width: contentWidth, height: rowHeight))
                    }
                    tableRowIndex += 1

                    (row.name as NSString).draw(
                        in: CGRect(x: margin + 3, y: y, width: contentWidth * tableColumnTest - 3, height: rowHeight),
                        withAttributes: [.font: UIFont.systemFont(ofSize: 10.5), .foregroundColor: UIColor.black]
                    )
                    (row.valueUnit as NSString).draw(
                        in: CGRect(x: margin + contentWidth * tableColumnTest, y: y, width: contentWidth * tableColumnResult, height: rowHeight),
                        withAttributes: [.font: UIFont.boldSystemFont(ofSize: 10.5), .foregroundColor: UIColor.black]
                    )
                    (row.rangeColumnText as NSString).draw(
                        in: CGRect(x: margin + contentWidth * (tableColumnTest + tableColumnResult), y: y, width: contentWidth * tableColumnRange, height: rowHeight),
                        withAttributes: [.font: UIFont.systemFont(ofSize: 9.5), .foregroundColor: UIColor(white: 0.3, alpha: 1)]
                    )
                    let statusX = margin + contentWidth * (tableColumnTest + tableColumnResult + tableColumnRange)
                    let dotRect = CGRect(x: statusX, y: y + 4, width: 8, height: 8)
                    context.cgContext.setFillColor(statusColor.cgColor)
                    context.cgContext.fillEllipse(in: dotRect)
                    (row.status.label as NSString).draw(
                        in: CGRect(x: statusX + 12, y: y, width: contentWidth * tableColumnStatus - 12, height: rowHeight),
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

    // Table column proportions (sum to 1.0) — declared once so the header
    // row and every data row stay aligned.
    private static let tableColumnTest: CGFloat = 0.32
    private static let tableColumnResult: CGFloat = 0.20
    private static let tableColumnRange: CGFloat = 0.28
    private static let tableColumnStatus: CGFloat = 0.20
}
