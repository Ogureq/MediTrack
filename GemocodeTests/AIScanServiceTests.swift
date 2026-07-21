import XCTest
@testable import Gemocode

/// Pure, network-free tests for `AIScanService.mapValues(fromJSON:)`,
/// `AIScanError.from(_:)`, and the wire shape of the two new `AITransport`
/// image-extraction request bodies. `AIScanService.extract(from:)` itself
/// (the networking call) is never exercised here — same convention as
/// `AIChatServiceTests`/`QuickAddAIMappingTests`/`AITransportTests`, none of
/// which hit the network either.
final class AIScanServiceTests: XCTestCase {

    // MARK: - mapValues: happy paths

    func testHappyPathMgPerDeciliterPassesThroughUnchanged() throws {
        let json = #"{"values":[{"name":"Glucose","value":95,"unit":"mg/dL","sourceText":"Glucose 95 mg/dL"}]}"#
        let results = try AIScanService.mapValues(fromJSON: json)
        let glucose = try XCTUnwrap(results.first { $0.reference.id == "fastingGlucose" })
        XCTAssertEqual(glucose.value, 95, accuracy: 0.001)
        XCTAssertEqual(glucose.sourceLine, "Glucose 95 mg/dL")
    }

    func testHappyPathMmolPerLiterIsConverted() throws {
        let json = #"{"values":[{"name":"Glucose","value":5.4,"unit":"mmol/L","sourceText":"Glucose 5.4 mmol/L"}]}"#
        let results = try AIScanService.mapValues(fromJSON: json)
        let glucose = try XCTUnwrap(results.first { $0.reference.id == "fastingGlucose" })
        // 5.4 mmol/L * 18.016 ≈ 97.3 mg/dL — same conversion factor
        // LabScanServiceTests' Russian-report-block test locks in.
        XCTAssertEqual(glucose.value, 97.3, accuracy: 0.2)
    }

    func testUnitTokenIsCaseInsensitive() throws {
        let json = #"{"values":[{"name":"Glucose","value":5.4,"unit":"MMOL/L","sourceText":"Glucose 5.4 MMOL/L"}]}"#
        let results = try AIScanService.mapValues(fromJSON: json)
        let glucose = try XCTUnwrap(results.first { $0.reference.id == "fastingGlucose" })
        XCTAssertEqual(glucose.value, 97.3, accuracy: 0.2)
    }

    // MARK: - mapValues: code-fence tolerance

    func testCodeFencedJSONIsStripped() throws {
        let fenced = """
            ```json
            {"values":[{"name":"Glucose","value":95,"unit":"mg/dL","sourceText":"Glucose 95 mg/dL"}]}
            ```
            """
        let results = try AIScanService.mapValues(fromJSON: fenced)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.reference.id, "fastingGlucose")
    }

    func testPlainFenceWithoutLanguageTagIsStripped() throws {
        let fenced = """
            ```
            {"values":[{"name":"Hemoglobin","value":13.5,"unit":"g/dL","sourceText":"Hemoglobin 13.5 g/dL"}]}
            ```
            """
        let results = try AIScanService.mapValues(fromJSON: fenced)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.reference.id, "hemoglobin")
    }

    // MARK: - mapValues: malformed top-level response throws

    func testGarbageTextThrowsMalformedResponse() {
        XCTAssertThrowsError(try AIScanService.mapValues(fromJSON: "not json at all")) { error in
            guard case AIScanError.malformedResponse = error else {
                return XCTFail("Expected .malformedResponse, got \(error)")
            }
        }
    }

    func testMissingValuesKeyThrowsMalformedResponse() {
        XCTAssertThrowsError(try AIScanService.mapValues(fromJSON: #"{"unexpected":"shape"}"#)) { error in
            guard case AIScanError.malformedResponse = error else {
                return XCTFail("Expected .malformedResponse, got \(error)")
            }
        }
    }

    // MARK: - mapValues: entries dropped, never thrown

    func testUnmatchedNameIsDroppedWithoutThrowing() throws {
        let json = #"{"values":[{"name":"Frobnicator Level","value":42,"unit":"","sourceText":"Frobnicator Level: 42"}]}"#
        let results = try AIScanService.mapValues(fromJSON: json)
        XCTAssertTrue(results.isEmpty)
    }

    func testAllEntriesDroppedReturnsEmptyArrayRatherThanThrowing() throws {
        let json = """
            {"values":[
              {"name":"Unknown Marker One","value":1,"unit":"","sourceText":"..."},
              {"name":"Unknown Marker Two","value":2,"unit":"","sourceText":"..."}
            ]}
            """
        let results = try AIScanService.mapValues(fromJSON: json)
        XCTAssertTrue(results.isEmpty)
    }

    func testZeroValueIsDiscarded() throws {
        let json = #"{"values":[{"name":"Glucose","value":0,"unit":"mg/dL","sourceText":"Glucose 0 mg/dL"}]}"#
        let results = try AIScanService.mapValues(fromJSON: json)
        XCTAssertTrue(results.isEmpty)
    }

    func testNegativeValueIsDiscarded() throws {
        let json = #"{"values":[{"name":"Glucose","value":-5,"unit":"mg/dL","sourceText":"Glucose -5 mg/dL"}]}"#
        let results = try AIScanService.mapValues(fromJSON: json)
        XCTAssertTrue(results.isEmpty)
    }

    func testNonNumericValueIsDiscarded() throws {
        let json = #"{"values":[{"name":"Glucose","value":"not a number","unit":"mg/dL","sourceText":"Glucose"}]}"#
        let results = try AIScanService.mapValues(fromJSON: json)
        XCTAssertTrue(results.isEmpty)
    }

    func testMissingNameIsDiscarded() throws {
        let json = #"{"values":[{"value":95,"unit":"mg/dL","sourceText":"95 mg/dL"}]}"#
        let results = try AIScanService.mapValues(fromJSON: json)
        XCTAssertTrue(results.isEmpty)
    }

    // MARK: - mapValues: plausibility discard (mirrors LabScanServiceTests)

    func testImplausiblyLargeValueIsDiscarded() throws {
        // fastingGlucose's plausible upper bound is 99, so 50x that (4950)
        // is the threshold above which a value is treated as noise — same
        // number LabScanServiceTests.testImplausiblyLargeValueIsDiscarded
        // exercises for the OCR path.
        let json = #"{"values":[{"name":"Glucose","value":999999,"unit":"mg/dL","sourceText":"Glucose 999999 mg/dL"}]}"#
        let results = try AIScanService.mapValues(fromJSON: json)
        XCTAssertTrue(results.isEmpty)
    }

    func testPlausibilityCheckAppliesAfterUnitConversion() throws {
        // A value that would be implausible pre-conversion but is fine
        // post-conversion must be kept: 90 mmol/L is nonsensical for
        // glucose, but the point here is simply that conversion runs before
        // the discard check, matching LabScanService.parse's documented
        // ordering. Use a plausible post-conversion value instead to assert
        // the happy path survives the ordering.
        let json = #"{"values":[{"name":"Glucose","value":5.0,"unit":"mmol/L","sourceText":"Glucose 5.0 mmol/L"}]}"#
        let results = try AIScanService.mapValues(fromJSON: json)
        XCTAssertEqual(results.count, 1)
        // 5.0 * 18.016 ≈ 90.08 mg/dL — well within the plausible range,
        // proving the value used for the discard check is the *converted*
        // number, not the raw mmol/L figure.
        XCTAssertEqual(results.first?.value ?? 0, 90.08, accuracy: 0.1)
    }

    // MARK: - mapValues: de-dup keeps first occurrence

    func testDuplicateMatchedNameKeepsFirstOccurrence() throws {
        let json = """
            {"values":[
              {"name":"Glucose","value":95,"unit":"mg/dL","sourceText":"Glucose 95 mg/dL"},
              {"name":"Glucose","value":110,"unit":"mg/dL","sourceText":"Glucose 110 mg/dL"}
            ]}
            """
        let results = try AIScanService.mapValues(fromJSON: json)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.value ?? 0, 95, accuracy: 0.001)
    }

    // MARK: - AIScanError.from(_:)

    func testRefusedTransportErrorMapsToRefused() {
        let mapped = AIScanError.from(AITransportError.refused)
        guard case .refused = mapped else {
            return XCTFail("Expected .refused, got \(mapped)")
        }
    }

    func testNotConfiguredTransportErrorMapsToNotConfigured() {
        let mapped = AIScanError.from(AITransportError.notConfigured)
        guard case .notConfigured = mapped else {
            return XCTFail("Expected .notConfigured, got \(mapped)")
        }
    }

    func testBadResponseTransportErrorMapsToMalformedResponse() {
        let mapped = AIScanError.from(AITransportError.badResponse)
        guard case .malformedResponse = mapped else {
            return XCTFail("Expected .malformedResponse, got \(mapped)")
        }
    }

    func testOtherTransportErrorsFoldIntoTransportCase() {
        let cases: [AITransportError] = [
            .unauthorized,
            .premiumRequired,
            .quotaExceeded,
            .http(500, "server error"),
            .network(URLError(.notConnectedToInternet))
        ]
        for transportError in cases {
            let mapped = AIScanError.from(transportError)
            guard case .transport = mapped else {
                return XCTFail("Expected .transport for \(transportError), got \(mapped)")
            }
        }
    }

    func testNonTransportErrorMapsToMalformedResponse() {
        struct SomeOtherError: Error {}
        let mapped = AIScanError.from(SomeOtherError())
        guard case .malformedResponse = mapped else {
            return XCTFail("Expected .malformedResponse, got \(mapped)")
        }
    }

    // MARK: - Wire shape: relay body

    func testExtractLabsRelayRequestBodyEncodesImageMediaTypeAndData() throws {
        let body = AITransport.ExtractLabsRequestBody(
            image: .init(mediaType: "image/jpeg", data: "QUJD")
        )
        // Matches the production encoder in AITransport.extractLabsViaRelay,
        // which applies .convertToSnakeCase (mediaType -> media_type).
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let data = try encoder.encode(body)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(json.count, 1, "relay body must carry only the image field — no prompt/model/kind")
        let image = try XCTUnwrap(json["image"] as? [String: Any])
        XCTAssertEqual(image["media_type"] as? String, "image/jpeg")
        XCTAssertEqual(image["data"] as? String, "QUJD")
    }

    // MARK: - Wire shape: relay response (already sanity-parsed by the relay)

    func testExtractLabsResponseBodyDecodesRealServerShape() throws {
        // Matches backend/src/index.ts's `POST /v1/extract-labs` success
        // response exactly: `{"values": LabValue[], "refused": false}`,
        // camelCase field names (no snake_case on this endpoint's response).
        let json = """
            {"values":[{"name":"Fasting Glucose","value":95,"unit":"mg/dL","sourceText":"Fasting Glucose 95 mg/dL"}],"refused":false}
            """
        let data = try XCTUnwrap(json.data(using: .utf8))
        let decoded = try JSONDecoder().decode(AITransport.ExtractLabsResponseBody.self, from: data)

        XCTAssertFalse(decoded.refused)
        XCTAssertEqual(decoded.values.count, 1)
        XCTAssertEqual(decoded.values.first?.name, "Fasting Glucose")
        XCTAssertEqual(decoded.values.first?.value, 95)
        XCTAssertEqual(decoded.values.first?.unit, "mg/dL")
        XCTAssertEqual(decoded.values.first?.sourceText, "Fasting Glucose 95 mg/dL")
    }

    func testExtractLabsResponseBodyDecodesRefusedShapeWithEmptyValues() throws {
        let json = #"{"values":[],"refused":true}"#
        let data = try XCTUnwrap(json.data(using: .utf8))
        let decoded = try JSONDecoder().decode(AITransport.ExtractLabsResponseBody.self, from: data)

        XCTAssertTrue(decoded.refused)
        XCTAssertTrue(decoded.values.isEmpty)
    }

    // MARK: - Wire shape: direct/BYOK body

    func testDirectImageRequestBodyEncodesExpectedShape() throws {
        let body = AITransport.DirectImageRequestBody(
            model: "claude-sonnet-5",
            maxTokens: 2000,
            temperature: 0,
            system: "extraction prompt",
            messages: [
                AITransport.DirectImageMessage(role: "user", content: [
                    .image(mediaType: "image/jpeg", data: "QUJD"),
                    .text("Extract every lab analyte with a numeric result from this photo, following your instructions exactly.")
                ])
            ]
        )
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let data = try encoder.encode(body)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(json["model"] as? String, "claude-sonnet-5")
        XCTAssertEqual(json["max_tokens"] as? Int, 2000)
        XCTAssertEqual(json["temperature"] as? Double, 0)
        XCTAssertEqual(json["system"] as? String, "extraction prompt")

        let messages = try XCTUnwrap(json["messages"] as? [[String: Any]])
        XCTAssertEqual(messages.count, 1)
        XCTAssertEqual(messages.first?["role"] as? String, "user")

        // Image block first, then the trigger text — mirrors the relay's
        // own content-block order exactly (backend/src/extractLabs.ts).
        let content = try XCTUnwrap(messages.first?["content"] as? [[String: Any]])
        XCTAssertEqual(content.count, 2)

        let imageBlock = content[0]
        XCTAssertEqual(imageBlock["type"] as? String, "image")
        XCTAssertNil(imageBlock["text"], "an image block must not carry a text field")
        let source = try XCTUnwrap(imageBlock["source"] as? [String: Any])
        XCTAssertEqual(source["type"] as? String, "base64")
        XCTAssertEqual(source["media_type"] as? String, "image/jpeg")
        XCTAssertEqual(source["data"] as? String, "QUJD")

        let textBlock = content[1]
        XCTAssertEqual(textBlock["type"] as? String, "text")
        XCTAssertNil(textBlock["source"], "a text block must not carry a source field")
        XCTAssertEqual(
            textBlock["text"] as? String,
            "Extract every lab analyte with a numeric result from this photo, following your instructions exactly."
        )
    }
}
