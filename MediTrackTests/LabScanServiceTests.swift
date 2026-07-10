import XCTest
@testable import MediTrack

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
}
