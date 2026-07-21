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
}
