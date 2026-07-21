import Foundation

// MARK: - AI Health Analyst report (opt-in)
//
// Strictly opt-in: the user supplies their own Anthropic API key in
// Profile & Settings. Only a structured summary of the already-computed,
// rule-based review is sent to the model — score, finding titles/details,
// and flagged lab values — never raw documents, attachments, OCR text, or
// the on-device database. The deterministic `AnalysisEngine` remains the
// source of every number and every clinical judgment; the model's job is
// narration and organization only. See docs/ROADMAP.md Part 3 §1 for the
// design this implements.

enum AISummaryError: LocalizedError {
    case missingKey
    case badResponse
    case refused
    case http(Int, String)
    case unauthorized
    case premiumRequired
    case quotaExceeded
    case network(Error)
    case invalidOutput(String)

    var errorDescription: String? {
        switch self {
        case .missingKey:
            "Add your Anthropic API key in Profile & Settings, or check back once the hosted AI service is available."
        case .badResponse:
            "The AI service returned an unexpected response."
        case .refused:
            "The AI declined to summarize this content."
        case .http(let status, let message):
            "AI request failed (\(status)): \(message)"
        case .unauthorized:
            "Your AI session couldn't be verified. Please try again."
        case .premiumRequired:
            "This AI feature is part of Gemocode Premium."
        case .quotaExceeded:
            "The AI service has reached today's usage limit. Please try again tomorrow."
        case .network(let error):
            "Couldn't reach the AI service: \(error.localizedDescription)"
        case .invalidOutput(let detail):
            "The AI report failed a safety check (\(detail)). Try generating again."
        }
    }

    /// Maps a thrown `AITransportError` (from `AITransport.generate`) onto
    /// this service's own error type, so callers keep catching
    /// `AISummaryError` exactly as before regardless of which transport
    /// (relay or direct/BYOK) actually served the request.
    static func from(_ error: Error) -> AISummaryError {
        guard let transportError = error as? AITransportError else {
            return (error as? AISummaryError) ?? .badResponse
        }
        switch transportError {
        case .notConfigured: return .missingKey
        case .unauthorized: return .unauthorized
        case .premiumRequired: return .premiumRequired
        case .quotaExceeded: return .quotaExceeded
        case .refused: return .refused
        case .badResponse: return .badResponse
        case .http(let status, let message): return .http(status, message)
        case .network(let underlying): return .network(underlying)
        }
    }
}

// MARK: - Structured report

/// The parsed, verified output of an AI Health Analyst report request.
/// Every `relatedFindingIDs` entry is guaranteed (by `findingIDsCheck`) to
/// reference a finding id that was actually sent in the request, and every
/// number in `overview`/`sections`/`doctorQuestions` is guaranteed (by
/// `numbersEchoCheck`) to have appeared somewhere in the input JSON. A value
/// only ever reaches a caller after both guards pass — on any failure the
/// caller receives a thrown `AISummaryError` instead and falls back to the
/// always-available rule-based review.
struct AIHealthReport: Equatable {
    struct Section: Equatable {
        let title: String
        let body: String
        let relatedFindingIDs: [String]
    }

    let overview: String
    let sections: [Section]
    let doctorQuestions: [String]
}

enum AISummaryService {

    /// Legacy UserDefaults key. No longer written to (the key now lives in
    /// the Keychain), but kept around as the one-time migration source and
    /// because other views still key their `@AppStorage` off this name.
    static let apiKeyDefaultsKey = "anthropicAPIKey"
    private static let keychainAccount = "anthropic.apiKey"

    /// The stored Anthropic API key, backed by the Keychain rather than
    /// UserDefaults (which persists to an unencrypted plist). Reading
    /// performs a one-time migration: if a legacy UserDefaults value is
    /// still present, it's moved into the Keychain and removed from
    /// UserDefaults.
    static var apiKey: String? {
        get {
            migrateLegacyKeyIfNeeded()
            let stored = KeychainStore.getString(keychainAccount)
            return (stored?.isEmpty ?? true) ? nil : stored
        }
        set {
            if let newValue, !newValue.isEmpty {
                KeychainStore.set(newValue, for: keychainAccount)
            } else {
                KeychainStore.delete(keychainAccount)
            }
            // The Keychain isn't observable — nudge views gating on
            // `isConfigured` (e.g. ReviewScreen's AI card) to re-evaluate.
            Task { @MainActor in AIConfigState.shared.bump() }
        }
    }

    /// Whether AI features are reachable right now — the relay is
    /// configured, or the user has a BYOK key. UI (`ReviewScreen`,
    /// `AIChatView`, `QuickAddView`) gates AI entry points off this rather
    /// than the presence of a key alone, so a relay-only build (no key
    /// ever entered) still shows the AI features.
    static var isConfigured: Bool {
        AITransport.isAvailable
    }

    /// Moves a legacy plaintext key out of UserDefaults and into the
    /// Keychain, once. No-ops if there's nothing to migrate or the Keychain
    /// already has a value.
    private static func migrateLegacyKeyIfNeeded() {
        guard let legacyKey = UserDefaults.standard.string(forKey: apiKeyDefaultsKey),
              !legacyKey.isEmpty else { return }
        KeychainStore.set(legacyKey, for: keychainAccount)
        UserDefaults.standard.removeObject(forKey: apiKeyDefaultsKey)
    }

    /// Model used only on the direct/BYOK fallback path — on the relay
    /// path the server owns model choice. See `AITransport.DirectSpec`.
    private static let model = "claude-opus-4-8"

    /// Persona, hard safety rails, and the exact input/output JSON shape.
    /// The input shape mirrors `ReportInput`'s Swift property names
    /// (camelCase); the output shape mirrors `RawReport`/`RawSection` below
    /// so `parseReportJSON` can decode it with the default key strategy.
    private static let reportSystemPrompt = """
        You are an educational health analyst inside Gemocode, a personal health-tracking \
        app. The user message is a JSON object already computed by a deterministic, \
        rule-based analysis engine — you did not compute any of it and must not recompute, \
        re-derive, or contradict it. Its shape is:
        { "score": Int, "scoreLabel": String, "profileSummary": String or null, \
        "findings": [{"id", "severity", "category", "title", "detail"}], \
        "labValues": [{"id", "name", "value", "unit", "status"}], "deltas": [String] }

        Hard rules:
        1. Never diagnose. Do not state or imply the user has a specific medical condition.
        2. Never prescribe or recommend starting, stopping, or changing any medication or \
        treatment.
        3. Never invent a number. Every number you write must already appear in the input \
        JSON.
        4. Every section you write must cite the finding ids ("f0", "f1", ...) it draws \
        from in relatedFindingIDs. Never introduce a concern with no corresponding finding \
        id.
        5. Always end with at least three specific follow-up questions the user can bring \
        to their doctor.
        6. Keep the tone warm, plain-language, and non-alarmist — this is educational only, \
        not medical advice.
        7. If any labValues have status "low", "high", "criticalLow", or "criticalHigh", \
        include exactly one additional section titled exactly "Lifestyle & nutrition to \
        discuss" covering only those out-of-range markers. You may mention general \
        mainstream dietary/hydration topics commonly discussed for that marker — for \
        example: water intake and limiting sugary drinks for elevated glucose; sodium \
        reduction for elevated blood pressure; soluble fiber such as oats, and limiting \
        saturated fat, for elevated LDL/cholesterol; limiting alcohol for elevated liver \
        enzymes or triglycerides. Every item must be framed as a topic to confirm with a \
        doctor or registered dietitian. Never present anything as a fix, treatment, or \
        cure. Never give doses, amounts, brands, supplements, or herbal remedies. Never \
        instruct starting, stopping, or changing any medication. If no labValues are out \
        of range, omit this section entirely.

        Respond with a single JSON object and nothing else (no markdown, no commentary, no \
        code fence) matching exactly this shape:
        { "overview": String, \
        "sections": [{"title": String, "body": String, "relatedFindingIDs": [String]}], \
        "doctorQuestions": [String] }
        """

    // MARK: Structured input payload (our own schema, sent as the user message text)

    struct FindingPayload: Encodable, Equatable, Sendable {
        let id: String
        let severity: String
        let category: String
        let title: String
        let detail: String
    }

    struct LabValuePayload: Encodable, Equatable, Sendable {
        let id: String
        let name: String
        let value: Double
        let unit: String
        let status: String
    }

    struct ReportInput: Encodable, Equatable, Sendable {
        let score: Int
        let scoreLabel: String
        let profileSummary: String?
        let findings: [FindingPayload]
        let labValues: [LabValuePayload]
        let deltas: [String]
    }

    // MARK: Output payload (parsed from the model's response text)

    private struct RawSection: Decodable {
        let title: String
        let body: String
        let relatedFindingIDs: [String]
    }

    private struct RawReport: Decodable {
        let overview: String
        let sections: [RawSection]
        let doctorQuestions: [String]
    }

    // MARK: Building the request payload

    /// Assigns each finding a stable, request-scoped id ("f0", "f1", ...) —
    /// `Finding.id` is a fresh UUID on every `generateReview()` call and
    /// can't be cited across a request/response round trip. Only lab
    /// values currently outside their reference range are included: the
    /// model only needs to narrate what's flagged, not restate the whole
    /// panel. `deltas` is a small caller-supplied list of plain-text facts
    /// (e.g. a score change since the last review) — empty by default so
    /// callers that only have a `HealthReview` handy don't need to compute
    /// anything extra.
    static func buildReportInput(
        review: HealthReview,
        profileSummary: String? = nil,
        deltas: [String] = []
    ) -> ReportInput {
        let findingPayloads = review.findings.enumerated().map { index, finding in
            FindingPayload(
                id: "f\(index)",
                severity: severityToken(finding.severity),
                category: finding.category.rawValue,
                title: finding.title,
                detail: finding.detail
            )
        }
        let labPayloads = review.labSnapshots
            .filter { $0.status.isOutOfRange }
            .map { snapshot in
                LabValuePayload(
                    id: snapshot.id,
                    name: snapshot.name,
                    value: snapshot.value,
                    unit: snapshot.unit,
                    status: labStatusToken(snapshot.status)
                )
            }
        return ReportInput(
            score: review.score,
            scoreLabel: review.scoreLabel,
            profileSummary: profileSummary,
            findings: findingPayloads,
            labValues: labPayloads,
            deltas: deltas
        )
    }

    static func severityToken(_ severity: Severity) -> String {
        switch severity {
        case .info: "info"
        case .attention: "attention"
        case .critical: "critical"
        }
    }

    static func labStatusToken(_ status: LabStatus) -> String {
        switch status {
        case .criticalLow: "criticalLow"
        case .low: "low"
        case .normal: "normal"
        case .high: "high"
        case .criticalHigh: "criticalHigh"
        case .unknown: "unknown"
        }
    }

    // MARK: Guards (pure, no network — unit-testable directly)

    /// Every `relatedFindingIDs` citation in the model's output must name a
    /// finding id that was actually present in the request. This turns
    /// "never introduce a risk with no basis" from a prompt request into a
    /// structurally checkable contract.
    static func findingIDsCheck(ids: [String], validIDs: Set<String>) -> Bool {
        ids.allSatisfy { validIDs.contains($0) }
    }

    /// Every decimal number token that appears in the model's free-text
    /// output must also appear — within floating-point rounding tolerance,
    /// so "120" matches an input of 120.0 — somewhere in `allowedNumbers`.
    /// Small integers 1...10 are always allowed since they're commonly used
    /// for list counts ("3 questions") rather than clinical figures.
    /// `numbersEchoCheck` with the offending token surfaced — used by
    /// `generateReport` so a guard failure names the number instead of
    /// collapsing into a generic error. The Bool variant stays for its
    /// existing tests/callers.
    static func firstUnexpectedNumber(output: String, allowedNumbers: Set<Double>) -> Double? {
        for value in decimalTokens(in: output) {
            if value.truncatingRemainder(dividingBy: 1) == 0, (1...10).contains(value) {
                continue
            }
            if allowedNumbers.contains(where: { abs($0 - value) < 0.05 }) {
                continue
            }
            return value
        }
        return nil
    }

    static func numbersEchoCheck(output: String, allowedNumbers: Set<Double>) -> Bool {
        for value in decimalTokens(in: output) {
            if value.truncatingRemainder(dividingBy: 1) == 0, (1...10).contains(value) {
                continue
            }
            if allowedNumbers.contains(where: { abs($0 - value) < 0.05 }) {
                continue
            }
            return false
        }
        return true
    }

    /// Extracts the allow-set for `numbersEchoCheck` straight from the input
    /// JSON string that was sent to the model — this naturally covers the
    /// score, every finding's numbers, every lab value, and any numbers
    /// embedded in caller-supplied `deltas` text, with no separate
    /// bookkeeping required.
    static func allowedNumbers(fromInputJSON json: String) -> Set<Double> {
        Set(decimalTokens(in: json))
    }

    static func decimalTokens(in text: String) -> [Double] {
        guard let regex = try? NSRegularExpression(pattern: #"-?\d+(?:\.\d+)?"#) else { return [] }
        let ns = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
            .compactMap { Double(ns.substring(with: $0.range)) }
    }

    // MARK: Parsing the model's JSON response

    static func parseReportJSON(_ raw: String) throws -> AIHealthReport {
        // Tolerates a fenced ```json ... ``` wrapper, which models
        // sometimes emit even when asked to respond with raw JSON only.
        // Shared with `AIChatService` and the direct/BYOK path in
        // `AITransport` via `AITransport.stripCodeFence`.
        let cleaned = AITransport.stripCodeFence(raw)
        guard let data = cleaned.data(using: .utf8) else {
            throw AISummaryError.badResponse
        }
        let decoded: RawReport
        do {
            decoded = try JSONDecoder().decode(RawReport.self, from: data)
        } catch {
            // A truncated response (max_tokens cut) or malformed JSON both
            // land here — the char count distinguishes them at a glance.
            throw AISummaryError.invalidOutput("report JSON didn't parse, \(cleaned.count) chars")
        }
        return AIHealthReport(
            overview: decoded.overview,
            sections: decoded.sections.map {
                AIHealthReport.Section(title: $0.title, body: $0.body, relatedFindingIDs: $0.relatedFindingIDs)
            },
            doctorQuestions: decoded.doctorQuestions
        )
    }

    // MARK: Call

    /// Generates a structured "AI Health Analyst" report from a
    /// `HealthReview`. `profileSummary` is a short caller-built description
    /// (e.g. age/sex/conditions) and `deltas` are optional caller-supplied
    /// plain-text facts (e.g. a score change since the last review) — both
    /// default to empty/nil so the API stays small for callers that only
    /// have a `HealthReview` on hand.
    ///
    /// Throws `AISummaryError` on *any* failure — missing key, network,
    /// refusal, malformed JSON, or a failed guard — so callers can
    /// uniformly fall back to the always-available rule-based review. No
    /// partially verified report is ever returned.
    static func generateReport(
        review: HealthReview,
        profileSummary: String? = nil,
        deltas: [String] = []
    ) async throws -> AIHealthReport {
        let input = buildReportInput(review: review, profileSummary: profileSummary, deltas: deltas)
        let inputData = try JSONEncoder().encode(input)
        guard let inputJSON = String(data: inputData, encoding: .utf8) else {
            throw AISummaryError.badResponse
        }

        // On the relay path `input` (the structured, engine-derived JSON)
        // is what's sent — the relay owns model/system prompt. On the
        // direct/BYOK fallback path, `direct` supplies both, exactly as
        // this service built them before the transport was shared.
        let direct = AITransport.DirectSpec(
            model: model,
            system: reportSystemPrompt,
            maxTokens: 4000,
            messages: [(role: "user", text: inputJSON)]
        )

        let text: String
        do {
            text = try await AITransport.generate(route: .report, input: input, direct: direct)
        } catch {
            throw AISummaryError.from(error)
        }

        let report = try parseReportJSON(text)

        let validIDs = Set(input.findings.map(\.id))
        let citedIDs = report.sections.flatMap(\.relatedFindingIDs)
        guard findingIDsCheck(ids: citedIDs, validIDs: validIDs) else {
            throw AISummaryError.invalidOutput("cited an unknown finding ID")
        }

        let outputText = ([report.overview] + report.sections.flatMap { [$0.title, $0.body] } + report.doctorQuestions)
            .joined(separator: "\n")
        let allowed = allowedNumbers(fromInputJSON: inputJSON)
        if let offender = firstUnexpectedNumber(output: outputText, allowedNumbers: allowed) {
            throw AISummaryError.invalidOutput("mentioned \(offender), which isn't in your data")
        }

        guard !report.doctorQuestions.isEmpty else {
            throw AISummaryError.invalidOutput("no doctor questions section")
        }

        return report
    }
}
