import XCTest
import Foundation
@testable import Gemocode

/// Pure, network-free tests for `AIReportPDFExporter.layoutText` — the exact
/// textual content of the auto-generated AI report PDF, decoupled from the
/// `UIGraphicsPDFRenderer` drawing pipeline in `render`. No `ModelContainer`
/// is needed: `LabResult` (like other `@Model` types) can be instantiated
/// standalone and read back without ever being inserted into a context —
/// see `ModelsTests`. Fixed dates are built from `DateComponents`, mirroring
/// `HealthTimelineTests`/`QuarterlyReviewTests`.
final class AIReportPDFExporterTests: XCTestCase {

    /// Builds a deterministic date from components so tests never depend on
    /// the wall clock.
    private func date(year: Int, month: Int, day: Int, hour: Int = 9, minute: Int = 30) throws -> Date {
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = day
        comps.hour = hour
        comps.minute = minute
        return try XCTUnwrap(Calendar.current.date(from: comps))
    }

    // MARK: Fixtures

    /// Two scanned lab results, matched by `seriesKey` to the two
    /// `LabSnapshot`s in `makeReview(generatedAt:)` below.
    private func makeScannedLabs(date: Date) -> [LabResult] {
        [
            LabResult(catalogID: "totalCholesterol", value: 245, unit: "mg/dL", date: date),
            LabResult(catalogID: "hemoglobin", value: 14.2, unit: "g/dL", date: date)
        ]
    }

    private func makeReview(generatedAt: Date) -> HealthReview {
        let cholesterolSnapshot = LabSnapshot(
            id: "totalcholesterol", // seriesKey lowercases the catalogID
            name: "Total Cholesterol",
            unit: "mg/dL",
            value: 245,
            date: generatedAt,
            status: .high,
            range: 100...199,
            reference: LabCatalog.reference(for: "totalCholesterol")
        )
        let hemoglobinSnapshot = LabSnapshot(
            id: "hemoglobin",
            name: "Hemoglobin",
            unit: "g/dL",
            value: 14.2,
            date: generatedAt,
            status: .normal,
            range: 13.5...17.5,
            reference: LabCatalog.reference(for: "hemoglobin")
        )
        return HealthReview(
            generatedAt: generatedAt,
            hasData: true,
            score: 78,
            summary: "Reviewed 2 lab results from 1 report. 1 item is outside typical ranges and worth discussing at your next visit.",
            findings: [],
            trends: [],
            labSnapshots: [cholesterolSnapshot, hemoglobinSnapshot]
        )
    }

    /// A hand-built, already-"verified" `AIHealthReport` — no networking,
    /// no `AISummaryService` guards exercised here (those are covered by
    /// `AIReportContractTests`).
    private func makeReport() -> AIHealthReport {
        AIHealthReport(
            overview: "Your overall score is 78, generally good with one area to watch.",
            sections: [
                AIHealthReport.Section(
                    title: "Cholesterol",
                    body: "Your total cholesterol of 245 mg/dL is above the typical range. Tracking it over time will help you and your doctor spot any trend.",
                    relatedFindingIDs: []
                ),
                AIHealthReport.Section(
                    title: "Hemoglobin",
                    body: "Your hemoglobin of 14.2 g/dL is within the typical range.",
                    relatedFindingIDs: []
                )
            ],
            doctorQuestions: [
                "Should I retest my cholesterol in a few months?",
                "Are there lifestyle changes that could help lower it?",
                "Do any of my current supplements affect these results?"
            ]
        )
    }

    // MARK: Doctor-questions section

    func testLayoutTextIncludesDoctorQuestionsSectionTitleAndLeadInExactly() throws {
        let generatedAt = try date(year: 2026, month: 7, day: 14)
        let lines = AIReportPDFExporter.layoutText(
            report: makeReport(),
            review: makeReview(generatedAt: generatedAt),
            scannedLabs: makeScannedLabs(date: generatedAt),
            profileName: "Jordan Rivera",
            generatedAt: generatedAt
        )

        XCTAssertTrue(lines.contains(AIReportPDFExporter.doctorQuestionsSectionTitle))
        XCTAssertTrue(lines.contains(AIReportPDFExporter.doctorQuestionsLeadIn))
        // Pin the exact wording so a future edit can't accidentally soften
        // this into an instruction rather than a discussion topic.
        XCTAssertEqual(
            AIReportPDFExporter.doctorQuestionsLeadIn,
            "Bring these to your next appointment — including any medication or supplement changes your doctor may recommend."
        )
    }

    func testLayoutTextIncludesEveryDoctorQuestionVerbatim() throws {
        let generatedAt = try date(year: 2026, month: 7, day: 14)
        let report = makeReport()
        let lines = AIReportPDFExporter.layoutText(
            report: report,
            review: makeReview(generatedAt: generatedAt),
            scannedLabs: makeScannedLabs(date: generatedAt),
            profileName: "Jordan Rivera",
            generatedAt: generatedAt
        )

        for question in report.doctorQuestions {
            XCTAssertTrue(lines.contains(question), "Expected doctor question to appear verbatim: \(question)")
        }
    }

    // MARK: Disclaimer block

    func testLayoutTextIncludesBothDisclaimerStringsInFull() throws {
        let generatedAt = try date(year: 2026, month: 7, day: 14)
        let lines = AIReportPDFExporter.layoutText(
            report: makeReport(),
            review: makeReview(generatedAt: generatedAt),
            scannedLabs: makeScannedLabs(date: generatedAt),
            profileName: "Jordan Rivera",
            generatedAt: generatedAt
        )

        XCTAssertTrue(lines.contains(HealthReview.disclaimer))
        XCTAssertTrue(lines.contains(AIReportPDFExporter.aiGeneratedDisclaimer))
    }

    // MARK: Scanned lab names

    func testLayoutTextIncludesEveryScannedLabName() throws {
        let generatedAt = try date(year: 2026, month: 7, day: 14)
        let scannedLabs = makeScannedLabs(date: generatedAt)
        let lines = AIReportPDFExporter.layoutText(
            report: makeReport(),
            review: makeReview(generatedAt: generatedAt),
            scannedLabs: scannedLabs,
            profileName: "Jordan Rivera",
            generatedAt: generatedAt
        )

        for lab in scannedLabs {
            let name = lab.displayName
            XCTAssertTrue(
                lines.contains(where: { $0.contains(name) }),
                "Expected a line mentioning scanned lab: \(name)"
            )
        }
    }

    // MARK: Section titles

    func testLayoutTextSectionTitlesAndBodiesMatchReportSections() throws {
        let generatedAt = try date(year: 2026, month: 7, day: 14)
        let report = makeReport()
        let lines = AIReportPDFExporter.layoutText(
            report: report,
            review: makeReview(generatedAt: generatedAt),
            scannedLabs: makeScannedLabs(date: generatedAt),
            profileName: "Jordan Rivera",
            generatedAt: generatedAt
        )

        for section in report.sections {
            XCTAssertTrue(lines.contains(section.title))
            XCTAssertTrue(lines.contains(section.body))
        }
    }

    // MARK: No imperative medication instructions

    func testLayoutTextContainsNoImperativeTakeInstruction() throws {
        let generatedAt = try date(year: 2026, month: 7, day: 14)
        let lines = AIReportPDFExporter.layoutText(
            report: makeReport(),
            review: makeReview(generatedAt: generatedAt),
            scannedLabs: makeScannedLabs(date: generatedAt),
            profileName: "Jordan Rivera",
            generatedAt: generatedAt
        )
        let fullText = lines.joined(separator: "\n")

        // The exporter's own fixed copy (lead-in + disclaimer) — the only
        // text it contributes beyond the already-verified AI report — must
        // never issue an imperative "take" instruction (take/start/stop/
        // change a medication). Word-boundary match so "mistake" etc. don't
        // false-positive.
        let takePattern = try NSRegularExpression(pattern: #"\btake\b"#, options: .caseInsensitive)
        let range = NSRange(fullText.startIndex..., in: fullText)
        XCTAssertEqual(
            takePattern.numberOfMatches(in: fullText, range: range),
            0,
            "The PDF's fixed copy and fixture content must never use an imperative 'take' instruction."
        )
    }

    // MARK: Empty profile name

    func testLayoutTextOmitsBlankLineWhenProfileNameIsEmpty() throws {
        let generatedAt = try date(year: 2026, month: 7, day: 14)
        let lines = AIReportPDFExporter.layoutText(
            report: makeReport(),
            review: makeReview(generatedAt: generatedAt),
            scannedLabs: makeScannedLabs(date: generatedAt),
            profileName: "",
            generatedAt: generatedAt
        )

        XCTAssertFalse(lines.contains(""))
    }

    // MARK: Attention box (out-of-range fixture)

    /// The fixture's cholesterol snapshot is `.high` (out of range) and its
    /// hemoglobin snapshot is `.normal` — the attention box must list
    /// exactly the cholesterol row, with its range, and must not also emit
    /// an all-clear box.
    func testAttentionBoxListsExactlyOutOfRangeFixtureLabsWithRanges() throws {
        let generatedAt = try date(year: 2026, month: 7, day: 14)
        let blocks = AIReportPDFExporter.layoutBlocks(
            report: makeReport(),
            review: makeReview(generatedAt: generatedAt),
            scannedLabs: makeScannedLabs(date: generatedAt),
            profileName: "Jordan Rivera",
            generatedAt: generatedAt
        )

        let attentionBoxes: [[AIReportPDFExporter.LabRow]] = blocks.compactMap {
            if case .attentionBox(let rows) = $0 { return rows }
            return nil
        }
        XCTAssertEqual(attentionBoxes.count, 1, "Expected exactly one attention box block.")
        let rows = try XCTUnwrap(attentionBoxes.first)
        XCTAssertEqual(rows.count, 1, "Expected exactly one out-of-range row (cholesterol).")
        let row = try XCTUnwrap(rows.first)
        XCTAssertEqual(row.name, "Total Cholesterol")
        XCTAssertEqual(row.rangeSpanText, "100–199")
        XCTAssertTrue(row.status.isOutOfRange)

        let allClearBoxes = blocks.filter { if case .allClearBox = $0 { return true } else { return false } }
        XCTAssertTrue(allClearBoxes.isEmpty, "Should not also emit an all-clear box when a value is out of range.")

        // The same content must round-trip through layoutText.
        let lines = AIReportPDFExporter.layoutText(
            report: makeReport(),
            review: makeReview(generatedAt: generatedAt),
            scannedLabs: makeScannedLabs(date: generatedAt),
            profileName: "Jordan Rivera",
            generatedAt: generatedAt
        )
        XCTAssertTrue(lines.contains("Total Cholesterol: 245 mg/dL — High · typical 100–199"))
        XCTAssertFalse(lines.contains(AIReportPDFExporter.allNormalMessage))
    }

    // MARK: All-clear box (all-normal fixture)

    private func makeAllNormalScannedLabs(date: Date) -> [LabResult] {
        [LabResult(catalogID: "hemoglobin", value: 14.2, unit: "g/dL", date: date)]
    }

    private func makeAllNormalReview(generatedAt: Date) -> HealthReview {
        let hemoglobinSnapshot = LabSnapshot(
            id: "hemoglobin",
            name: "Hemoglobin",
            unit: "g/dL",
            value: 14.2,
            date: generatedAt,
            status: .normal,
            range: 13.5...17.5,
            reference: LabCatalog.reference(for: "hemoglobin")
        )
        return HealthReview(
            generatedAt: generatedAt,
            hasData: true,
            score: 92,
            summary: "Reviewed 1 lab result from 1 report. Everything is within typical ranges.",
            findings: [],
            trends: [],
            labSnapshots: [hemoglobinSnapshot]
        )
    }

    func testAllNormalFixtureProducesAllClearLine() throws {
        let generatedAt = try date(year: 2026, month: 7, day: 14)
        let scannedLabs = makeAllNormalScannedLabs(date: generatedAt)
        let review = makeAllNormalReview(generatedAt: generatedAt)

        let blocks = AIReportPDFExporter.layoutBlocks(
            report: makeReport(),
            review: review,
            scannedLabs: scannedLabs,
            profileName: "Jordan Rivera",
            generatedAt: generatedAt
        )

        let allClearMessages: [String] = blocks.compactMap {
            if case .allClearBox(let text) = $0 { return text }
            return nil
        }
        XCTAssertEqual(allClearMessages, [AIReportPDFExporter.allNormalMessage])

        let attentionBoxes = blocks.filter { if case .attentionBox = $0 { return true } else { return false } }
        XCTAssertTrue(attentionBoxes.isEmpty, "Should not emit an attention box when every scanned value is normal.")

        let lines = AIReportPDFExporter.layoutText(
            report: makeReport(),
            review: review,
            scannedLabs: scannedLabs,
            profileName: "Jordan Rivera",
            generatedAt: generatedAt
        )
        XCTAssertTrue(lines.contains("All scanned values are within their typical ranges."))
        XCTAssertEqual(
            AIReportPDFExporter.allNormalMessage,
            "All scanned values are within their typical ranges."
        )
    }

    // MARK: Typical-range table column

    func testRangeColumnTextPresentForKnownRangeLabs() throws {
        let generatedAt = try date(year: 2026, month: 7, day: 14)
        let blocks = AIReportPDFExporter.layoutBlocks(
            report: makeReport(),
            review: makeReview(generatedAt: generatedAt),
            scannedLabs: makeScannedLabs(date: generatedAt),
            profileName: "Jordan Rivera",
            generatedAt: generatedAt
        )

        let tableRows: [AIReportPDFExporter.LabRow] = blocks.compactMap {
            if case .tableRow(let row) = $0 { return row }
            return nil
        }
        XCTAssertEqual(tableRows.count, 2)
        let cholesterolRow = try XCTUnwrap(tableRows.first { $0.name == "Total Cholesterol" })
        XCTAssertEqual(cholesterolRow.rangeColumnText, "100–199 mg/dL")
        let hemoglobinRow = try XCTUnwrap(tableRows.first { $0.name == "Hemoglobin" })
        XCTAssertEqual(hemoglobinRow.rangeColumnText, "13.5–17.5 g/dL")

        let lines = AIReportPDFExporter.layoutText(
            report: makeReport(),
            review: makeReview(generatedAt: generatedAt),
            scannedLabs: makeScannedLabs(date: generatedAt),
            profileName: "Jordan Rivera",
            generatedAt: generatedAt
        )
        XCTAssertTrue(lines.contains(where: { $0.contains("100–199 mg/dL") }))
        XCTAssertTrue(lines.contains(where: { $0.contains("13.5–17.5 g/dL") }))
    }

    // MARK: render — sanity check on the actual PDF bytes

    func testRenderProducesNonEmptyValidPDFData() throws {
        let generatedAt = try date(year: 2026, month: 7, day: 14)
        let data = AIReportPDFExporter.render(
            report: makeReport(),
            review: makeReview(generatedAt: generatedAt),
            scannedLabs: makeScannedLabs(date: generatedAt),
            profileName: "Jordan Rivera",
            generatedAt: generatedAt
        )

        XCTAssertFalse(data.isEmpty)
        let header = try XCTUnwrap(String(data: data.prefix(4), encoding: .ascii))
        XCTAssertEqual(header, "%PDF")
    }
}
