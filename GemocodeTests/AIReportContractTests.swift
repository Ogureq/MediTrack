import XCTest
@testable import Gemocode

/// Pure, network-free tests for the AI Health Analyst report's verification
/// pipeline: the two hallucination guards (`numbersEchoCheck`,
/// `findingIDsCheck`) and the response JSON parser (`parseReportJSON`).
/// None of these tests touch the network — `AISummaryService.generateReport`
/// itself is not exercised here.
final class AIReportContractTests: XCTestCase {

    // MARK: numbersEchoCheck

    func testNumbersEchoCheckPassesWhenEveryNumberIsAllowed() {
        let allowed: Set<Double> = [78, 210.0, 5.2]
        let output = "Your score of 78 reflects a cholesterol reading of 210 and a ratio of 5.2."
        XCTAssertTrue(AISummaryService.numbersEchoCheck(output: output, allowedNumbers: allowed))
    }

    func testNumbersEchoCheckFailsOnHallucinatedNumber() {
        let allowed: Set<Double> = [78, 210.0]
        let output = "Your cholesterol of 245 is a concern."
        XCTAssertFalse(AISummaryService.numbersEchoCheck(output: output, allowedNumbers: allowed))
    }

    func testNumbersEchoCheckToleratesIntegerVsDecimalFormatting() {
        let allowed: Set<Double> = [120.0]
        // Output writes "120" (integer-looking) where the allow-set has 120.0.
        XCTAssertTrue(AISummaryService.numbersEchoCheck(output: "Your reading was 120 mmHg.", allowedNumbers: allowed))

        let allowedDecimal: Set<Double> = [120]
        // And the reverse: allow-set has a bare Int-valued Double, output uses a decimal.
        XCTAssertTrue(AISummaryService.numbersEchoCheck(output: "Your reading was 120.0 mmHg.", allowedNumbers: allowedDecimal))
    }

    func testNumbersEchoCheckAllowsSmallOrdinalsRegardlessOfAllowSet() {
        let allowed: Set<Double> = [] // deliberately empty
        XCTAssertTrue(AISummaryService.numbersEchoCheck(output: "Here are 3 questions to ask.", allowedNumbers: allowed))
        XCTAssertTrue(AISummaryService.numbersEchoCheck(output: "This is your 1st and only note.", allowedNumbers: allowed))
    }

    func testNumbersEchoCheckStillRejectsOutOfRangeNumberEvenNearOrdinals() {
        let allowed: Set<Double> = []
        // 42 is outside the always-allowed 1...10 ordinal band and not in allowedNumbers.
        XCTAssertFalse(AISummaryService.numbersEchoCheck(output: "You are 42 years old.", allowedNumbers: allowed))
    }

    // MARK: findingIDsCheck

    func testFindingIDsCheckPassesWhenAllIDsAreValid() {
        let validIDs: Set<String> = ["f0", "f1", "f2"]
        XCTAssertTrue(AISummaryService.findingIDsCheck(ids: ["f0", "f2"], validIDs: validIDs))
    }

    func testFindingIDsCheckPassesForEmptyCitationList() {
        XCTAssertTrue(AISummaryService.findingIDsCheck(ids: [], validIDs: ["f0"]))
    }

    func testFindingIDsCheckFailsOnUnknownFindingID() {
        let validIDs: Set<String> = ["f0", "f1"]
        XCTAssertFalse(AISummaryService.findingIDsCheck(ids: ["f0", "f9"], validIDs: validIDs))
    }

    // MARK: parseReportJSON

    func testParseReportJSONWellFormed() throws {
        let json = """
        {
          "overview": "Overall things look steady.",
          "sections": [
            { "title": "Cholesterol", "body": "Slightly elevated.", "relatedFindingIDs": ["f0"] }
          ],
          "doctorQuestions": ["Should I retest in 3 months?", "Is my ratio a concern?"]
        }
        """
        let report = try AISummaryService.parseReportJSON(json)
        XCTAssertEqual(report.overview, "Overall things look steady.")
        XCTAssertEqual(report.sections.count, 1)
        let section = try XCTUnwrap(report.sections.first)
        XCTAssertEqual(section.title, "Cholesterol")
        XCTAssertEqual(section.body, "Slightly elevated.")
        XCTAssertEqual(section.relatedFindingIDs, ["f0"])
        XCTAssertEqual(report.doctorQuestions.count, 2)
    }

    func testParseReportJSONToleratesFencedCodeBlock() throws {
        let fenced = """
        ```json
        {
          "overview": "Fenced overview.",
          "sections": [],
          "doctorQuestions": ["Any follow-up labs recommended?"]
        }
        ```
        """
        let report = try AISummaryService.parseReportJSON(fenced)
        XCTAssertEqual(report.overview, "Fenced overview.")
        XCTAssertTrue(report.sections.isEmpty)
        XCTAssertEqual(report.doctorQuestions, ["Any follow-up labs recommended?"])
    }

    func testParseReportJSONToleratesPlainFenceWithoutLanguageTag() throws {
        let fenced = """
        ```
        {"overview": "No language tag.", "sections": [], "doctorQuestions": ["Q1?"]}
        ```
        """
        let report = try AISummaryService.parseReportJSON(fenced)
        XCTAssertEqual(report.overview, "No language tag.")
    }

    func testParseReportJSONMalformedThrows() {
        let malformed = "{ this is not valid JSON "
        XCTAssertThrowsError(try AISummaryService.parseReportJSON(malformed)) { error in
            XCTAssertTrue(error is AISummaryError)
        }
    }

    func testParseReportJSONMissingRequiredFieldThrows() {
        // Valid JSON, but missing the required "doctorQuestions" key.
        let incomplete = """
        { "overview": "Missing a field.", "sections": [] }
        """
        XCTAssertThrowsError(try AISummaryService.parseReportJSON(incomplete)) { error in
            XCTAssertTrue(error is AISummaryError)
        }
    }
}
