import Foundation

// MARK: - Ask about your report (AI chat)
//
// Strictly opt-in, same key as `AISummaryService` (Profile & Settings).
// Conversation memory is CLIENT-HELD ONLY: nothing is persisted to disk or
// SwiftData, and nothing is sent to Anthropic except the visible on-screen
// history (trimmed to the last few turns) plus a compact text summary of the
// already-computed, rule-based `HealthReview` — never raw documents,
// attachments, OCR text, or the on-device database. See `AISummaryService`
// for the sibling "AI Health Analyst report" feature this reuses the API key
// and call style from.

/// One turn in an on-screen chat conversation. Held only in view state —
/// never persisted.
struct AIChatMessage: Identifiable, Equatable {
    enum Role: Equatable {
        case user
        case assistant
    }

    let id: UUID
    let role: Role
    let text: String

    init(id: UUID = UUID(), role: Role, text: String) {
        self.id = id
        self.role = role
        self.text = text
    }
}

enum AIChatError: LocalizedError {
    case missingKey
    case badResponse
    case refused
    case http(Int, String)

    var errorDescription: String? {
        switch self {
        case .missingKey:
            "Add your Anthropic API key in Profile & Settings first."
        case .badResponse:
            "The AI service returned an unexpected response."
        case .refused:
            "The AI declined to answer that question."
        case .http(let status, let message):
            "AI request failed (\(status)): \(message)"
        }
    }
}

enum AIChatService {

    private static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    private static let model = "claude-sonnet-5"
    private static let maxTokens = 700
    private static let historyLimit = 12

    /// System-prompt rules: the assistant is an educational health
    /// companion, may only discuss the data in the provided context, must
    /// decline to diagnose/prescribe/interpret anything outside that
    /// context, must nudge toward a doctor or pharmacist whenever a finding
    /// comes up, and must keep answers short and plain-language.
    private static func systemPrompt(context: String) -> String {
        """
        You are an educational health companion inside MediTrack, a personal health-tracking \
        app. The user is asking about the health review summarized in the context block below. \
        You did not compute any of this data and must not recompute, re-derive, or contradict it.

        Hard rules:
        1. You may ONLY discuss the data present in the context block below. Do not speculate \
        about, interpret, or answer questions about health data, symptoms, or medications that \
        are not present in the context.
        2. Never diagnose. Do not state or imply the user has a specific medical condition.
        3. Never prescribe or recommend starting, stopping, or changing any medication or \
        treatment.
        4. If the user asks something outside the scope of the context, say plainly that you \
        can only discuss this review and suggest they bring the question to their doctor or \
        pharmacist.
        5. Whenever your answer touches a specific finding, suggest discussing it with a \
        doctor or pharmacist.
        6. Keep answers short, warm, and plain-language — this is educational only, not \
        medical advice.

        Context:
        \(context)
        """
    }

    // MARK: Context building (pure, unit-testable)

    /// Serializes a `HealthReview` plus a short profile summary into a
    /// compact, deterministic plain-text block for the system prompt. Same
    /// input always produces the same output — findings are walked in the
    /// order `HealthReview.findings` already provides (already deterministic
    /// out of `AnalysisEngine`), never re-sorted or re-grouped here.
    static func buildContext(review: HealthReview, profileSummary: String) -> String {
        var lines: [String] = []
        lines.append("Health score: \(review.score)/100 (\(review.scoreLabel))")

        let trimmedProfile = profileSummary.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedProfile.isEmpty {
            lines.append("Profile: \(trimmedProfile)")
        }

        if review.findings.isEmpty {
            lines.append("Findings: none")
        } else {
            lines.append("Findings:")
            for (index, finding) in review.findings.enumerated() {
                var line = "\(index + 1). [\(finding.severity.displayName)] \(finding.title) — \(finding.detail)"
                if let recommendation = finding.recommendation {
                    line += " Recommendation: \(recommendation)"
                }
                lines.append(line)
            }
        }

        return lines.joined(separator: "\n")
    }

    // MARK: History trimming (pure, unit-testable)

    /// Keeps at most `limit` most-recent messages, then drops a leading
    /// assistant message so the trimmed history always starts with a user
    /// turn — the Messages API requires alternating turns starting with
    /// `user`.
    static func trimmedHistory(_ history: [AIChatMessage], limit: Int = 12) -> [AIChatMessage] {
        var trimmed = Array(history.suffix(max(limit, 0)))
        while let first = trimmed.first, first.role == .assistant {
            trimmed.removeFirst()
        }
        return trimmed
    }

    // MARK: Request/response shapes (Messages API envelope)

    private struct RequestMessage: Encodable {
        let role: String
        let content: String
    }

    private struct RequestBody: Encodable {
        let model: String
        let maxTokens: Int
        let system: String
        let messages: [RequestMessage]
    }

    private struct ContentBlock: Decodable {
        let type: String
        let text: String?
    }

    private struct ResponseBody: Decodable {
        let content: [ContentBlock]
        let stopReason: String?
    }

    private struct APIErrorBody: Decodable {
        struct Inner: Decodable {
            let message: String
        }
        let error: Inner
    }

    // MARK: Call

    /// Sends at most the last `historyLimit` messages of `history` (mapped
    /// to Messages-API role/content) with `context` as the system prompt,
    /// and returns the assistant's reply text.
    ///
    /// Throws `AIChatError` on any failure — missing key, network, refusal,
    /// or a malformed response — so callers can show an inline error while
    /// keeping the rest of the conversation intact.
    static func reply(history: [AIChatMessage], context: String) async throws -> String {
        guard let key = AISummaryService.apiKey, !key.isEmpty else {
            throw AIChatError.missingKey
        }

        let trimmed = trimmedHistory(history, limit: historyLimit)
        let messages = trimmed.map {
            RequestMessage(role: $0.role == .user ? "user" : "assistant", content: $0.text)
        }
        guard !messages.isEmpty else {
            throw AIChatError.badResponse
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        let bodyEncoder = JSONEncoder()
        bodyEncoder.keyEncodingStrategy = .convertToSnakeCase
        request.httpBody = try bodyEncoder.encode(RequestBody(
            model: model,
            maxTokens: maxTokens,
            system: systemPrompt(context: context),
            messages: messages
        ))

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AIChatError.badResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let message = (try? JSONDecoder().decode(APIErrorBody.self, from: data))?
                .error.message ?? "no details"
            throw AIChatError.http(http.statusCode, message)
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let decoded = try decoder.decode(ResponseBody.self, from: data)

        // Check the stop reason before reading content: a safety refusal
        // returns HTTP 200 with an empty or partial content array.
        if decoded.stopReason == "refusal" {
            throw AIChatError.refused
        }

        let text = decoded.content
            .filter { $0.type == "text" }
            .compactMap(\.text)
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            throw AIChatError.badResponse
        }

        return text
    }
}
