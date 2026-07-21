import XCTest
@testable import Gemocode

/// Tests for the additive `facility` field on the relay's `/v1/extract-labs`
/// response — decoded by `AITransport.ExtractLabsResponseBody` and carried
/// through `AIScanService.AIScanResult`. Pure, network-free decoding tests,
/// same convention as `AIScanServiceTests`/`AITransportTests` (neither of
/// which this file duplicates or edits — this is a NEW file, scoped to just
/// the facility addition).
final class AIScanServiceFacilityTests: XCTestCase {

    // MARK: - ExtractLabsResponseBody: facility present

    func testDecodesFacilityWhenPresent() throws {
        let json = """
            {"values":[{"name":"Fasting Glucose","value":95,"unit":"mg/dL","sourceText":"Fasting Glucose 95 mg/dL"}],"facility":"Quest Diagnostics","refused":false}
            """
        let data = try XCTUnwrap(json.data(using: .utf8))
        let decoded = try JSONDecoder().decode(AITransport.ExtractLabsResponseBody.self, from: data)

        XCTAssertEqual(decoded.facility, "Quest Diagnostics")
        XCTAssertFalse(decoded.refused)
        XCTAssertEqual(decoded.values.count, 1)
    }

    func testDecodesExplicitNullFacility() throws {
        let json = """
            {"values":[{"name":"Fasting Glucose","value":95,"unit":"mg/dL","sourceText":"Fasting Glucose 95 mg/dL"}],"facility":null,"refused":false}
            """
        let data = try XCTUnwrap(json.data(using: .utf8))
        let decoded = try JSONDecoder().decode(AITransport.ExtractLabsResponseBody.self, from: data)

        XCTAssertNil(decoded.facility)
    }

    // MARK: - ExtractLabsResponseBody: facility absent (old-relay tolerance)

    func testDecodesNilFacilityWhenFieldIsAbsentEntirely() throws {
        // The exact shape an old, pre-facility relay deployment would still
        // send — no "facility" key at all. Must decode successfully with
        // `facility == nil` rather than throwing, so an app build with this
        // change never breaks against a relay that hasn't redeployed yet.
        let json = """
            {"values":[{"name":"Fasting Glucose","value":95,"unit":"mg/dL","sourceText":"Fasting Glucose 95 mg/dL"}],"refused":false}
            """
        let data = try XCTUnwrap(json.data(using: .utf8))
        let decoded = try JSONDecoder().decode(AITransport.ExtractLabsResponseBody.self, from: data)

        XCTAssertNil(decoded.facility)
        XCTAssertEqual(decoded.values.count, 1)
        XCTAssertFalse(decoded.refused)
    }

    func testDecodesNilFacilityOnRefusedShapeWithEmptyValues() throws {
        let json = #"{"values":[],"refused":true}"#
        let data = try XCTUnwrap(json.data(using: .utf8))
        let decoded = try JSONDecoder().decode(AITransport.ExtractLabsResponseBody.self, from: data)

        XCTAssertNil(decoded.facility)
        XCTAssertTrue(decoded.refused)
        XCTAssertTrue(decoded.values.isEmpty)
    }

    // MARK: - Empty-string facility is passed through as-is (caller's job to blank-check)

    func testDecodesEmptyStringFacilityAsEmptyStringNotNil() throws {
        // `AITransport.ExtractLabsResponseBody` itself never blank-checks —
        // `ScanReportView.scanAttachmentsWithAI()` is the caller that trims
        // and discards an empty string before ever assigning it to
        // `scannedFacility`. This test locks in that the decode layer stays
        // a faithful pass-through.
        let json = """
            {"values":[],"facility":"","refused":false}
            """
        let data = try XCTUnwrap(json.data(using: .utf8))
        let decoded = try JSONDecoder().decode(AITransport.ExtractLabsResponseBody.self, from: data)

        XCTAssertEqual(decoded.facility, "")
    }
}
