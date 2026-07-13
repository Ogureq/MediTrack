import XCTest
@testable import MediTrack

/// Pure, network-free tests for the non-networking pieces of `AITransport`:
/// `RelayConfig` base-URL resolution, the shared `stripCodeFence` helper,
/// `AITransportError`'s user-presentable messages, and the exact JSON shape
/// of the relay's `POST /v1/ai/generate` request body for both the
/// `"report"` and `"chat"` kinds (including the client-side chat caps).
/// `AITransport.generate` itself — the relay auth dance and the direct/BYOK
/// call — is not exercised here; it makes live network calls.
final class AITransportTests: XCTestCase {

    // MARK: Setup / teardown — reset the exact UserDefaults key under test

    override func setUpWithError() throws {
        try super.setUpWithError()
        UserDefaults.standard.removeObject(forKey: RelayConfig.defaultsKey)
    }

    override func tearDownWithError() throws {
        UserDefaults.standard.removeObject(forKey: RelayConfig.defaultsKey)
        try super.tearDownWithError()
    }

    // MARK: RelayConfig.parse (pure)

    func testRelayConfigParseRejectsEmptyString() {
        XCTAssertNil(RelayConfig.parse(""))
    }

    func testRelayConfigParseRejectsMalformedURL() {
        XCTAssertNil(RelayConfig.parse("not a url"))
    }

    func testRelayConfigParseRejectsNonHTTPScheme() {
        XCTAssertNil(RelayConfig.parse("ftp://example.com"))
    }

    func testRelayConfigParseRejectsURLWithNoHost() {
        // No "//" authority marker, so this parses as scheme + path with no host.
        XCTAssertNil(RelayConfig.parse("https:no-authority-here"))
    }

    func testRelayConfigParseAcceptsValidHTTPSURL() throws {
        let url = try XCTUnwrap(RelayConfig.parse("https://relay.example.com"))
        XCTAssertEqual(url.host, "relay.example.com")
    }

    func testRelayConfigParseAcceptsValidHTTPURLForLocalDev() throws {
        let url = try XCTUnwrap(RelayConfig.parse("http://localhost:8787"))
        XCTAssertEqual(url.scheme, "http")
    }

    // MARK: RelayConfig.baseURL (UserDefaults + compiled-in fallback)

    func testRelayConfigBaseURLIsNilWhenNothingConfigured() {
        // No UserDefaults override, and `defaultBaseURLString` is empty
        // until the owner deploys and fills it in.
        XCTAssertNil(RelayConfig.baseURL)
    }

    func testRelayConfigBaseURLUserDefaultsOverrideWins() throws {
        UserDefaults.standard.set("https://relay.example.com", forKey: RelayConfig.defaultsKey)
        let url = try XCTUnwrap(RelayConfig.baseURL)
        XCTAssertEqual(url.host, "relay.example.com")
    }

    func testRelayConfigBaseURLIgnoresBlankOverrideAndFallsBackToDefault() {
        UserDefaults.standard.set("   ", forKey: RelayConfig.defaultsKey)
        XCTAssertNil(RelayConfig.baseURL)
    }

    func testRelayConfigBaseURLIgnoresInvalidOverride() {
        UserDefaults.standard.set("definitely not a url", forKey: RelayConfig.defaultsKey)
        XCTAssertNil(RelayConfig.baseURL)
    }

    func testRelayConfigBaseURLTrimsWhitespaceAroundOverride() throws {
        UserDefaults.standard.set("  https://relay.example.com  ", forKey: RelayConfig.defaultsKey)
        let url = try XCTUnwrap(RelayConfig.baseURL)
        XCTAssertEqual(url.host, "relay.example.com")
    }

    // MARK: stripCodeFence

    func testStripCodeFenceLeavesPlainTextUnchanged() {
        XCTAssertEqual(AITransport.stripCodeFence(#"{"a":1}"#), #"{"a":1}"#)
    }

    func testStripCodeFenceRemovesJSONLanguageTaggedFence() {
        let fenced = "```json\n{\"overview\": \"Fenced overview.\"}\n```"
        XCTAssertEqual(AITransport.stripCodeFence(fenced), "{\"overview\": \"Fenced overview.\"}")
    }

    func testStripCodeFenceRemovesPlainFenceWithoutLanguageTag() {
        let fenced = "```\n{\"overview\": \"No language tag.\"}\n```"
        XCTAssertEqual(AITransport.stripCodeFence(fenced), "{\"overview\": \"No language tag.\"}")
    }

    func testStripCodeFenceTrimsSurroundingWhitespace() {
        XCTAssertEqual(AITransport.stripCodeFence("  \n {\"a\":1}  \n  "), "{\"a\":1}")
    }

    func testStripCodeFenceWithoutClosingFenceOnlyDropsOpeningLine() {
        let fenced = "```json\n{\"a\":1}"
        XCTAssertEqual(AITransport.stripCodeFence(fenced), "{\"a\":1}")
    }

    // MARK: AITransportError user-presentable messages

    func testEveryTransportErrorHasANonEmptyUserPresentableMessage() {
        let allCases: [AITransportError] = [
            .notConfigured,
            .unauthorized,
            .premiumRequired,
            .quotaExceeded,
            .refused,
            .badResponse,
            .http(500, "server error"),
            .network(URLError(.notConnectedToInternet))
        ]
        for error in allCases {
            let message = error.errorDescription
            XCTAssertNotNil(message, "\(error) has no errorDescription")
            XCTAssertFalse(message?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true,
                            "\(error) has an empty errorDescription")
        }
    }

    func testHTTPErrorMessageIncludesStatusCodeAndMessage() {
        let error = AITransportError.http(429, "rate limited")
        let description = try? XCTUnwrap(error.errorDescription)
        XCTAssertTrue(description?.contains("429") ?? false)
        XCTAssertTrue(description?.contains("rate limited") ?? false)
    }

    // MARK: Generate request body shape — "report" kind

    func testReportGenerateRequestBodyEncodesKindAndInputFields() throws {
        let input = AISummaryService.ReportInput(
            score: 80,
            scoreLabel: "Good",
            profileSummary: "45-year-old male",
            findings: [
                AISummaryService.FindingPayload(id: "f0", severity: "info", category: "labs", title: "T", detail: "D")
            ],
            labValues: [
                AISummaryService.LabValuePayload(id: "l0", name: "Potassium", value: 6.8, unit: "mmol/L", status: "criticalHigh")
            ],
            deltas: ["Health score changed from 70 to 80."]
        )
        let body = AITransport.GenerateRequestBody(kind: AIRoute.report.rawValue, input: input)
        let data = try JSONEncoder().encode(body)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(json["kind"] as? String, "report")
        let decodedInput = try XCTUnwrap(json["input"] as? [String: Any])
        XCTAssertEqual(decodedInput["score"] as? Int, 80)
        XCTAssertEqual(decodedInput["scoreLabel"] as? String, "Good")
        XCTAssertEqual(decodedInput["profileSummary"] as? String, "45-year-old male")
        let findings = try XCTUnwrap(decodedInput["findings"] as? [[String: Any]])
        XCTAssertEqual(findings.first?["id"] as? String, "f0")
        let labValues = try XCTUnwrap(decodedInput["labValues"] as? [[String: Any]])
        XCTAssertEqual(labValues.first?["name"] as? String, "Potassium")
        let deltas = try XCTUnwrap(decodedInput["deltas"] as? [String])
        XCTAssertEqual(deltas, ["Health score changed from 70 to 80."])
    }

    // MARK: Generate request body shape — "chat" kind

    func testChatGenerateRequestBodyEncodesKindAndInputFields() throws {
        let input = AIChatService.ChatInput(
            context: "Health score: 80/100 (Good)",
            messages: [AIChatService.ChatTurn(role: "user", text: "What does my score mean?")]
        )
        let body = AITransport.GenerateRequestBody(kind: AIRoute.chat.rawValue, input: input)
        let data = try JSONEncoder().encode(body)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(json["kind"] as? String, "chat")
        let decodedInput = try XCTUnwrap(json["input"] as? [String: Any])
        XCTAssertEqual(decodedInput["context"] as? String, "Health score: 80/100 (Good)")
        let messages = try XCTUnwrap(decodedInput["messages"] as? [[String: Any]])
        XCTAssertEqual(messages.count, 1)
        XCTAssertEqual(messages.first?["role"] as? String, "user")
        XCTAssertEqual(messages.first?["text"] as? String, "What does my score mean?")
    }

    // MARK: Chat caps are enforced client-side before the body is built

    func testChatContextIsCappedTo8000CharsBeforeBeingSent() throws {
        let oversized = String(repeating: "a", count: 9000)
        let capped = AIChatService.cappedContext(oversized)
        XCTAssertEqual(capped.count, AIChatService.contextCharacterLimit)

        let input = AIChatService.ChatInput(context: capped, messages: [])
        let body = AITransport.GenerateRequestBody(kind: AIRoute.chat.rawValue, input: input)
        let data = try JSONEncoder().encode(body)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let decodedInput = try XCTUnwrap(json["input"] as? [String: Any])
        let context = try XCTUnwrap(decodedInput["context"] as? String)
        XCTAssertLessThanOrEqual(context.count, 8000)
    }

    func testChatContextUnderLimitIsUnchanged() {
        let short = "Health score: 80/100 (Good)"
        XCTAssertEqual(AIChatService.cappedContext(short), short)
    }

    func testChatMessagesAreCappedTo12BeforeBeingSent() throws {
        let history = (0..<20).map { AIChatMessage(role: .user, text: "message \($0)") }
        let trimmed = AIChatService.trimmedHistory(history, limit: 12)
        XCTAssertLessThanOrEqual(trimmed.count, 12)

        let turns = trimmed.map {
            AIChatService.ChatTurn(role: $0.role == .user ? "user" : "assistant", text: $0.text)
        }
        let input = AIChatService.ChatInput(context: "context", messages: turns)
        let body = AITransport.GenerateRequestBody(kind: AIRoute.chat.rawValue, input: input)
        let data = try JSONEncoder().encode(body)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let decodedInput = try XCTUnwrap(json["input"] as? [String: Any])
        let messages = try XCTUnwrap(decodedInput["messages"] as? [[String: Any]])
        XCTAssertLessThanOrEqual(messages.count, 12)
    }
}
