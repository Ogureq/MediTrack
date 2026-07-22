import CoreGraphics
import XCTest
@testable import Gemocode

final class LabScanServiceTests: XCTestCase {

    func testParsesInlineValueAndNextLineFallback() throws {
        let lines = ["Hemoglobin 13.5 g/dL", "Glucose", "95"]
        let results = LabScanService.parse(lines: lines)

        XCTAssertEqual(results.count, 2)

        let hemoglobin = try XCTUnwrap(results.first { $0.reference.id == "hemoglobin" })
        XCTAssertEqual(hemoglobin.value, 13.5, accuracy: 0.001)
        XCTAssertEqual(hemoglobin.sourceLine, "Hemoglobin 13.5 g/dL")

        let glucose = try XCTUnwrap(results.first { $0.reference.id == "fastingGlucose" })
        XCTAssertEqual(glucose.value, 95, accuracy: 0.001)
        XCTAssertEqual(glucose.sourceLine, "Glucose")
    }

    func testParsesInlineValueOnSameLine() throws {
        let lines = ["Glucose 95 mg/dL"]
        let results = LabScanService.parse(lines: lines)
        let glucose = try XCTUnwrap(results.first)
        XCTAssertEqual(glucose.reference.id, "fastingGlucose")
        XCTAssertEqual(glucose.value, 95, accuracy: 0.001)
    }

    func testUnrecognizedLinesAreIgnored() {
        let lines = ["Patient Name: Jane Doe", "Date of Birth: 01/01/1980"]
        let results = LabScanService.parse(lines: lines)
        XCTAssertTrue(results.isEmpty)
    }

    func testEmptyLinesArrayProducesNoResults() {
        XCTAssertTrue(LabScanService.parse(lines: []).isEmpty)
    }

    func testDoesNotFallBackToNextLineIfNextLineIsAnotherKnownTest() {
        // "Glucose" has no inline value; the next line is itself a recognized
        // test label (not a bare number), so no value should be extracted for
        // Glucose and it should be skipped entirely.
        let lines = ["Glucose", "Hemoglobin 13.5 g/dL"]
        let results = LabScanService.parse(lines: lines)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.reference.id, "hemoglobin")
    }

    func testDuplicateTestKeepsOnlyFirstOccurrence() throws {
        let lines = ["Glucose 95 mg/dL", "Glucose 110 mg/dL"]
        let results = LabScanService.parse(lines: lines)
        XCTAssertEqual(results.count, 1)
        let glucose = try XCTUnwrap(results.first)
        XCTAssertEqual(glucose.value, 95, accuracy: 0.001)
    }

    func testZeroValueIsDiscarded() {
        // `firstNumber` has no concept of a minus sign (it only accumulates
        // digits/'.'/','), so a literal zero is the reliable way to exercise
        // the `value > 0` guard.
        let lines = ["Glucose 0 mg/dL"]
        let results = LabScanService.parse(lines: lines)
        XCTAssertTrue(results.isEmpty)
    }

    func testImplausiblyLargeValueIsDiscarded() {
        // fastingGlucose's plausible upper bound is 99, so 50x that (4950) is
        // the threshold above which a value is treated as noise (e.g. a date/ID).
        let lines = ["Glucose 999999 mg/dL"]
        let results = LabScanService.parse(lines: lines)
        XCTAssertTrue(results.isEmpty)
    }

    func testShortLinesAreSkipped() {
        // Lines under 3 characters are ignored outright.
        let lines = ["Hemoglobin 13.5 g/dL", "95"]
        let results = LabScanService.parse(lines: lines)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.reference.id, "hemoglobin")
    }

    // MARK: Russian & Turkish OCR support

    func testParsesRussianReportBlockWithUnitConversion() throws {
        // A synthetic Invitro/Helix-style Russian report block: comma
        // decimals, Cyrillic aliases, and mmol/L, µmol/L and g/L values
        // that must be converted to the catalog's canonical mg/dL, mg/dL,
        // and g/dL units respectively.
        let lines = [
            "Глюкоза 5,4 ммоль/л",
            "Креатинин 74 мкмоль/л",
            "Гемоглобин 141 г/л",
            "АЛТ 22 Ед/л"
        ]
        let results = LabScanService.parse(lines: lines)
        XCTAssertEqual(results.count, 4)

        let glucose = try XCTUnwrap(results.first { $0.reference.id == "fastingGlucose" })
        // 5.4 mmol/L * 18.016 ≈ 97.3 mg/dL
        XCTAssertEqual(glucose.value, 97.3, accuracy: 0.2)

        let creatinine = try XCTUnwrap(results.first { $0.reference.id == "creatinine" })
        // 74 µmol/L / 88.42 ≈ 0.837 mg/dL
        XCTAssertEqual(creatinine.value, 0.837, accuracy: 0.01)

        let hemoglobin = try XCTUnwrap(results.first { $0.reference.id == "hemoglobin" })
        // 141 g/L / 10 = 14.1 g/dL
        XCTAssertEqual(hemoglobin.value, 14.1, accuracy: 0.001)

        // "Ед/л" (U/L) already matches the catalog's canonical ALT unit, so
        // no conversion should be applied.
        let alt = try XCTUnwrap(results.first { $0.reference.id == "alt" })
        XCTAssertEqual(alt.value, 22, accuracy: 0.001)
    }

    func testParsesTurkishReportBlock() throws {
        let lines = [
            "Glukoz 92 mg/dL",
            "Trigliserid 1,4 mmol/L"
        ]
        let results = LabScanService.parse(lines: lines)
        XCTAssertEqual(results.count, 2)

        // Already in the canonical unit: passes through unchanged.
        let glucose = try XCTUnwrap(results.first { $0.reference.id == "fastingGlucose" })
        XCTAssertEqual(glucose.value, 92, accuracy: 0.001)

        let triglycerides = try XCTUnwrap(results.first { $0.reference.id == "triglycerides" })
        // 1.4 mmol/L * 88.57 ≈ 124.0 mg/dL
        XCTAssertEqual(triglycerides.value, 124.0, accuracy: 0.2)
    }

    func testElectrolyteInMillimolesPerLiterPassesThroughUnchanged() throws {
        // Potassium's canonical unit (mEq/L) is numerically equivalent to
        // mmol/L for a monovalent ion, so no conversion table entry exists
        // for it — the value must pass through untouched.
        let lines = ["Калий 4.2 ммоль/л"]
        let results = LabScanService.parse(lines: lines)
        let potassium = try XCTUnwrap(results.first)
        XCTAssertEqual(potassium.reference.id, "potassium")
        XCTAssertEqual(potassium.value, 4.2, accuracy: 0.001)
    }

    func testEnglishMgPerDeciliterPassesThroughUnchanged() throws {
        // No unit token to convert: existing English mg/dL behavior must
        // stay byte-identical.
        let lines = ["Glucose 95 mg/dL"]
        let results = LabScanService.parse(lines: lines)
        let glucose = try XCTUnwrap(results.first)
        XCTAssertEqual(glucose.reference.id, "fastingGlucose")
        XCTAssertEqual(glucose.value, 95, accuracy: 0.001)
    }

    func testShortRussianAliasDoesNotMatchInsideALongerWord() {
        // "аст" (AST) must not fire inside "контраст" ("contrast"); the
        // word-boundary check in LabSynonyms.match(in:) should reject it,
        // and no other alias in the line matches either.
        let lines = ["Контраст введен пациенту"]
        let results = LabScanService.parse(lines: lines)
        XCTAssertTrue(results.isEmpty)
    }

    func testShortEnglishAliasDoesNotMatchInsideALongerWord() {
        // "ast" must not fire inside "Blast"; guards the same word-boundary
        // mechanism from the English side.
        let lines = ["Blast cells present 5"]
        let results = LabScanService.parse(lines: lines)
        XCTAssertTrue(results.isEmpty)
    }

    // MARK: - assembleRows (OCR geometry -> visual rows)

    /// Builds one columnar report row as four separate OCR fragments (name /
    /// value / unit / reference-range), each with a slightly jittered
    /// vertical center — the way four independent Vision text observations
    /// on the same printed line typically come back — so tests exercise the
    /// tolerance comparison rather than relying on exactly-equal y values.
    private func columnarRow(
        y: CGFloat,
        name: String,
        value: String,
        unit: String,
        range: String
    ) -> [(text: String, box: CGRect)] {
        let height: CGFloat = 0.02
        return [
            (text: name, box: CGRect(x: 0.05, y: y, width: 0.35, height: height)),
            (text: value, box: CGRect(x: 0.45, y: y - 0.002, width: 0.10, height: height)),
            (text: unit, box: CGRect(x: 0.65, y: y + 0.001, width: 0.10, height: height)),
            (text: range, box: CGRect(x: 0.85, y: y - 0.001, width: 0.14, height: height))
        ]
    }

    func testAssembleRowsEmptyInputProducesNoRows() {
        XCTAssertEqual(LabScanService.assembleRows([]), [])
    }

    func testAssembleRowsGroupsFragmentsByYProximityAndSortsLeftToRight() {
        // Three fragments on one visual row, given to assembleRows in
        // shuffled order and with y-centers a bit apart (but well within the
        // 60%-of-box-height tolerance) — output must be one row, in reading
        // (left-to-right) order.
        let fragments: [(text: String, box: CGRect)] = [
            (text: "Value", box: CGRect(x: 0.5, y: 0.5, width: 0.2, height: 0.02)),
            (text: "Unit", box: CGRect(x: 0.75, y: 0.498, width: 0.15, height: 0.02)),
            (text: "Name", box: CGRect(x: 0.05, y: 0.503, width: 0.3, height: 0.02))
        ]
        XCTAssertEqual(LabScanService.assembleRows(fragments), ["Name Value Unit"])
    }

    func testAssembleRowsSeparatesRowsThatAreFarApartVertically() {
        // Two fragments whose y-centers differ far more than the tolerance
        // (0.6 * 0.02 = 0.012) must land in separate rows, ordered
        // top-to-bottom. Vision's normalized boxes are bottom-left-origin
        // with y increasing upward, so the larger y ("Row1") sorts first.
        let fragments: [(text: String, box: CGRect)] = [
            (text: "Row2", box: CGRect(x: 0.1, y: 0.5, width: 0.2, height: 0.02)),
            (text: "Row1", box: CGRect(x: 0.1, y: 0.9, width: 0.2, height: 0.02))
        ]
        XCTAssertEqual(LabScanService.assembleRows(fragments), ["Row1", "Row2"])
    }

    func testAssembleRowsSingleFragmentPerLineBehavesIdentically() {
        // The pre-geometry behavior: one Vision observation per full printed
        // line (a wide observation, or a report layout with no separate
        // columns). Each fragment must still become its own row, unchanged,
        // and feeding the result into parse(lines:) must reproduce
        // testParsesInlineValueAndNextLineFallback's result exactly — this
        // is the "existing tests keep passing unchanged" guarantee for the
        // geometry rewrite.
        let fragments: [(text: String, box: CGRect)] = [
            (text: "Hemoglobin 13.5 g/dL", box: CGRect(x: 0.05, y: 0.9, width: 0.9, height: 0.02)),
            (text: "Glucose", box: CGRect(x: 0.05, y: 0.85, width: 0.9, height: 0.02)),
            (text: "95", box: CGRect(x: 0.05, y: 0.8, width: 0.9, height: 0.02))
        ]
        let rows = LabScanService.assembleRows(fragments)
        XCTAssertEqual(rows, ["Hemoglobin 13.5 g/dL", "Glucose", "95"])

        let results = LabScanService.parse(lines: rows)
        XCTAssertEqual(results.count, 2)
        let hemoglobin = results.first { $0.reference.id == "hemoglobin" }
        XCTAssertEqual(hemoglobin?.value ?? -1, 13.5, accuracy: 0.001)
        let glucose = results.first { $0.reference.id == "fastingGlucose" }
        XCTAssertEqual(glucose?.value ?? -1, 95, accuracy: 0.001)
    }

    // MARK: - UK columnar report layout (real-world reproduction)

    func testParsesUKColumnarReportLayout() throws {
        // A synthetic reproduction of the real UK-style four-column report
        // (name / value / unit / reference range, each its own OCR
        // fragment/box) that originally produced zero values: Vision's
        // bounding boxes are the only thing that ties a name cell to its
        // value cell, so this exercises assembleRows and parse(lines:)
        // together end-to-end.
        var fragments: [(text: String, box: CGRect)] = []
        fragments += columnarRow(y: 0.90, name: "HAEMOGLOBIN (g/L)", value: "151", unit: "g/L", range: "130 - 170")
        fragments += columnarRow(y: 0.85, name: "MCHC (g/L)", value: "*358", unit: "g/L", range: "300 - 350")
        fragments += columnarRow(y: 0.80, name: "PLATELET COUNT", value: "287", unit: "x10^9/L", range: "150 - 400")
        fragments += columnarRow(y: 0.75, name: "SODIUM", value: "140", unit: "mmol/L", range: "135 - 145")
        fragments += columnarRow(y: 0.70, name: "UREA", value: "*8.4", unit: "mmol/L", range: "1.7 - 8.3")
        fragments += columnarRow(y: 0.65, name: "CREATININE", value: "*114", unit: "umol/L", range: "66 - 112")
        fragments += columnarRow(y: 0.60, name: "FASTING BLOOD GLUCOSE", value: "5.0", unit: "mmol/L", range: "3.9 - 5.8")
        fragments += columnarRow(y: 0.55, name: "LDL CHOLESTEROL", value: "2.6", unit: "mmol/L", range: "Up to 3.0")
        // A note line and a URL line, each a single wide OCR fragment (as a
        // real one-observation-per-full-line report footer would look).
        fragments.append((text: "Note: reference ranges are raised in pregnancy",
                           box: CGRect(x: 0.05, y: 0.50, width: 0.9, height: 0.02)))
        fragments.append((text: "For UK guidelines see www.renal.org/bloodresults",
                           box: CGRect(x: 0.05, y: 0.45, width: 0.9, height: 0.02)))

        let rows = LabScanService.assembleRows(fragments)
        XCTAssertEqual(rows, [
            "HAEMOGLOBIN (g/L) 151 g/L 130 - 170",
            "MCHC (g/L) *358 g/L 300 - 350",
            "PLATELET COUNT 287 x10^9/L 150 - 400",
            "SODIUM 140 mmol/L 135 - 145",
            "UREA *8.4 mmol/L 1.7 - 8.3",
            "CREATININE *114 umol/L 66 - 112",
            "FASTING BLOOD GLUCOSE 5.0 mmol/L 3.9 - 5.8",
            "LDL CHOLESTEROL 2.6 mmol/L Up to 3.0",
            "Note: reference ranges are raised in pregnancy",
            "For UK guidelines see www.renal.org/bloodresults"
        ])

        let results = LabScanService.parse(lines: rows)
        // Exactly the 8 lab rows; the note and URL lines match no synonym
        // and produce nothing.
        XCTAssertEqual(results.count, 8)

        let hemoglobin = try XCTUnwrap(results.first { $0.reference.id == "hemoglobin" })
        // 151 g/L / 10 = 15.1 g/dL. The "(g/L)" in the NAME cell sits before
        // the matched alias's range end, so it never reaches firstNumber;
        // the "(g/l)" that DOES follow the match is skipped as non-numeric
        // until the real value "151".
        XCTAssertEqual(hemoglobin.value, 15.1, accuracy: 0.05)

        let mchc = try XCTUnwrap(results.first { $0.reference.id == "mchc" })
        // The asterisked flag is stripped (firstNumber skips non-numeric
        // leading characters) and the UK "g/L" value converts to the
        // catalog's canonical g/dL: 358 g/L -> 35.8 g/dL.
        XCTAssertEqual(mchc.value, 35.8, accuracy: 0.01)

        let platelets = try XCTUnwrap(results.first { $0.reference.id == "platelets" })
        XCTAssertEqual(platelets.value, 287, accuracy: 0.001)

        let sodium = try XCTUnwrap(results.first { $0.reference.id == "sodium" })
        // No conversion rule for sodium (mmol/L is numerically equivalent to
        // its canonical mEq/L) — passes through unchanged.
        XCTAssertEqual(sodium.value, 140, accuracy: 0.001)

        let bun = try XCTUnwrap(results.first { $0.reference.id == "bun" })
        // "Urea" aliases to "bun"; 8.4 mmol/L * 2.8 = 23.52 mg/dL BUN.
        XCTAssertEqual(bun.value, 23.5, accuracy: 0.2)

        let creatinine = try XCTUnwrap(results.first { $0.reference.id == "creatinine" })
        // 114 µmol/L / 88.42 ≈ 1.289 mg/dL.
        XCTAssertEqual(creatinine.value, 1.29, accuracy: 0.02)

        let glucose = try XCTUnwrap(results.first { $0.reference.id == "fastingGlucose" })
        // "Fasting Blood Glucose" (UK alias) -> 5.0 mmol/L * 18.016 ≈ 90.08 mg/dL.
        XCTAssertEqual(glucose.value, 90.1, accuracy: 0.5)

        let ldl = try XCTUnwrap(results.first { $0.reference.id == "ldlCholesterol" })
        // The longer "ldl cholesterol" candidate (mapped to ldlCholesterol)
        // must win over the shorter "cholesterol" candidate (mapped to
        // totalCholesterol) that is also a substring of this line — proving
        // the longest-match rule keeps an LDL row from being misfiled as
        // Total Cholesterol. 2.6 mmol/L * 38.67 ≈ 100.5 mg/dL.
        XCTAssertEqual(ldl.value, 100.5, accuracy: 0.5)
        XCTAssertFalse(results.contains { $0.reference.id == "totalCholesterol" })

        // The reference-range column's own numbers must never be picked up
        // as a value for any test.
        let rangeBoundaryNumbers: Set<Double> = [170, 130, 350, 300, 400, 150, 145, 135, 8.3, 1.7, 112, 66, 5.8, 3.9, 3.0]
        for result in results {
            XCTAssertFalse(rangeBoundaryNumbers.contains(result.value),
                            "\(result.reference.id) picked up a reference-range number (\(result.value)) instead of its value")
        }
    }

    // MARK: - UK/international alias coverage

    func testUKAliasHaemoglobinMatchesHemoglobin() throws {
        let lines = ["Haemoglobin 145 g/L"]
        let results = LabScanService.parse(lines: lines)
        let hemoglobin = try XCTUnwrap(results.first)
        XCTAssertEqual(hemoglobin.reference.id, "hemoglobin")
        XCTAssertEqual(hemoglobin.value, 14.5, accuracy: 0.001)
    }

    func testUKAliasRedCellCountMatchesRedBloodCells() throws {
        let lines = ["Red Cell Count 4.8 million/uL 4.2 - 5.4"]
        let results = LabScanService.parse(lines: lines)
        let redCells = try XCTUnwrap(results.first)
        XCTAssertEqual(redCells.reference.id, "redBloodCells")
        XCTAssertEqual(redCells.value, 4.8, accuracy: 0.001)
    }

    func testUKAliasWhiteCellCountMatchesWhiteBloodCells() throws {
        let lines = ["White Cell Count 6.2 thousand/uL 4.5 - 11.0"]
        let results = LabScanService.parse(lines: lines)
        let whiteCells = try XCTUnwrap(results.first)
        XCTAssertEqual(whiteCells.reference.id, "whiteBloodCells")
        XCTAssertEqual(whiteCells.value, 6.2, accuracy: 0.001)
    }

    func testUKAliasAspartateTransferaseMatchesAST() throws {
        let lines = ["Aspartate Transferase 35 U/L"]
        let results = LabScanService.parse(lines: lines)
        let ast = try XCTUnwrap(results.first)
        XCTAssertEqual(ast.reference.id, "ast")
        XCTAssertEqual(ast.value, 35, accuracy: 0.001)
    }

    func testUKAliasAlanineTransferaseMatchesALT() throws {
        let lines = ["Alanine Transferase 40 U/L"]
        let results = LabScanService.parse(lines: lines)
        let alt = try XCTUnwrap(results.first)
        XCTAssertEqual(alt.reference.id, "alt")
        XCTAssertEqual(alt.value, 40, accuracy: 0.001)
    }

    func testUKAliasFastingCholesterolMatchesTotalCholesterol() throws {
        let lines = ["Fasting Cholesterol 4.5 mmol/L Up to 5.0"]
        let results = LabScanService.parse(lines: lines)
        let cholesterol = try XCTUnwrap(results.first)
        XCTAssertEqual(cholesterol.reference.id, "totalCholesterol")
        // 4.5 mmol/L * 38.67 ≈ 174.0 mg/dL.
        XCTAssertEqual(cholesterol.value, 174.0, accuracy: 0.5)
    }

    func testUKAliasFastingTriglyceridesMatchesTriglycerides() throws {
        let lines = ["Fasting Triglycerides 1.1 mmol/L Up to 1.7"]
        let results = LabScanService.parse(lines: lines)
        let triglycerides = try XCTUnwrap(results.first)
        XCTAssertEqual(triglycerides.reference.id, "triglycerides")
        // 1.1 mmol/L * 88.57 ≈ 97.4 mg/dL.
        XCTAssertEqual(triglycerides.value, 97.4, accuracy: 0.5)
    }

    func testUreaAliasAlreadyMapsToBUN() throws {
        // Confirms "urea" (bare, as printed on UK panels) already routes to
        // the "bun" catalog id without any new alias needed.
        let lines = ["Urea 8.4 mmol/L 1.7 - 8.3"]
        let results = LabScanService.parse(lines: lines)
        let bun = try XCTUnwrap(results.first)
        XCTAssertEqual(bun.reference.id, "bun")
        XCTAssertEqual(bun.value, 23.5, accuracy: 0.2)
    }

    func testDottedTIBCAliasSurvivesWordBoundaryCheck() throws {
        // The dots in "T.I.B.C" are non-letters, so the word-boundary check
        // in LabSynonyms.match(in:) — which only inspects the characters
        // immediately outside the matched range — is unaffected by them.
        let lines = ["T.I.B.C 300 ug/dL 250 - 450"]
        let results = LabScanService.parse(lines: lines)
        let tibc = try XCTUnwrap(results.first)
        XCTAssertEqual(tibc.reference.id, "tibc")
        XCTAssertEqual(tibc.value, 300, accuracy: 0.001)
    }

    func testPlainTIBCAlreadyAutoMatchesViaShortName() throws {
        // "TIBC" alone needs no alias: it's already the catalog's own
        // shortName, auto-matched by match(in:).
        let lines = ["TIBC 320 ug/dL 250 - 450"]
        let results = LabScanService.parse(lines: lines)
        let tibc = try XCTUnwrap(results.first)
        XCTAssertEqual(tibc.reference.id, "tibc")
        XCTAssertEqual(tibc.value, 320, accuracy: 0.001)
    }

    func testCorrectedCalciumImportsWhenNoPlainCalciumRowPresent() throws {
        let lines = ["Corrected Calcium 2.30 mmol/L 2.20 - 2.60"]
        let results = LabScanService.parse(lines: lines)
        let calcium = try XCTUnwrap(results.first)
        XCTAssertEqual(calcium.reference.id, "calcium")
        // 2.30 mmol/L * 4.008 ≈ 9.22 mg/dL.
        XCTAssertEqual(calcium.value, 9.22, accuracy: 0.05)
    }

    func testCorrectedCalciumRowIsSkippedWhenPlainCalciumRowAppearsFirst() throws {
        // Documents the accepted tradeoff: "calcium" and "corrected calcium"
        // are the SAME catalog id, and parse(lines:) dedupes by first
        // occurrence. On a typical UK panel the raw "Calcium" row prints
        // before "Corrected Calcium", so the raw value wins and the
        // corrected row is silently skipped — same behavior as any other
        // duplicate-test row, not a new failure mode introduced by the alias.
        let lines = [
            "Calcium 2.30 mmol/L 2.20 - 2.60",
            "Corrected Calcium 2.35 mmol/L 2.20 - 2.60"
        ]
        let results = LabScanService.parse(lines: lines)
        XCTAssertEqual(results.count, 1)
        let calcium = try XCTUnwrap(results.first)
        XCTAssertEqual(calcium.reference.id, "calcium")
        // The FIRST (raw, uncorrected) row's value, not the second.
        XCTAssertEqual(calcium.value, 9.22, accuracy: 0.05)
    }

    func testPlainCalciumRowStillMatchesCalciumAfterCorrectedCalciumAliasAdded() throws {
        // Guards against the new "corrected calcium" alias somehow changing
        // which id a plain "Calcium" row resolves to.
        let lines = ["Calcium 9.5 mg/dL 8.6 - 10.3"]
        let results = LabScanService.parse(lines: lines)
        let calcium = try XCTUnwrap(results.first)
        XCTAssertEqual(calcium.reference.id, "calcium")
        XCTAssertEqual(calcium.value, 9.5, accuracy: 0.001)
    }

    // MARK: Separator normalization
    //
    // A thousands comma used to be read as a decimal point, turning
    // "Ferritin 1,234" into 1.234 — a 1000x understatement that the
    // plausibility filter cannot catch, since it only rejects values that
    // are too high. European decimal commas must keep working.

    func testDecimalCommaStaysADecimal() {
        XCTAssertEqual(LabScanService.normalizedNumberToken("5,4"), "5.4")
        XCTAssertEqual(LabScanService.normalizedNumberToken("12,75"), "12.75")
    }

    func testLeadingZeroCommaIsADecimalNotGrouping() {
        XCTAssertEqual(LabScanService.normalizedNumberToken("0,123"), "0.123")
    }

    func testThousandsCommaIsDropped() {
        XCTAssertEqual(LabScanService.normalizedNumberToken("1,234"), "1234")
        XCTAssertEqual(LabScanService.normalizedNumberToken("12,345"), "12345")
        XCTAssertEqual(LabScanService.normalizedNumberToken("1,234,567"), "1234567")
    }

    func testMixedSeparatorsUseTheLastOneAsTheDecimal() {
        XCTAssertEqual(LabScanService.normalizedNumberToken("1,234.56"), "1234.56")
        XCTAssertEqual(LabScanService.normalizedNumberToken("1.234,56"), "1234.56")
    }

    func testPlainTokensAreUnchanged() {
        XCTAssertEqual(LabScanService.normalizedNumberToken("126"), "126")
        XCTAssertEqual(LabScanService.normalizedNumberToken("5.4"), "5.4")
    }

    func testThousandsSeparatedFerritinParsesAtFullMagnitude() throws {
        let results = LabScanService.parse(lines: ["Ferritin 1,234 ng/mL"])
        let ferritin = try XCTUnwrap(results.first)
        XCTAssertEqual(ferritin.reference.id, "ferritin")
        XCTAssertEqual(ferritin.value, 1234, accuracy: 0.001)
    }
}
