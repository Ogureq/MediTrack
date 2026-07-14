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
    case unauthorized
    case premiumRequired
    case quotaExceeded
    case network(Error)

    var errorDescription: String? {
        switch self {
        case .missingKey:
            "Add your Anthropic API key in Profile & Settings, or check back once the hosted AI service is available."
        case .badResponse:
            "The AI service returned an unexpected response."
        case .refused:
            "The AI declined to answer that question."
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
        }
    }

    /// Maps a thrown `AITransportError` (from `AITransport.generate`) onto
    /// this service's own error type, so callers keep catching `AIChatError`
    /// exactly as before regardless of which transport (relay or
    /// direct/BYOK) actually served the request.
    static func from(_ error: Error) -> AIChatError {
        guard let transportError = error as? AITransportError else {
            return (error as? AIChatError) ?? .badResponse
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

enum AIChatService {

    /// Model used only on the direct/BYOK fallback path — on the relay
    /// path the server owns model choice. See `AITransport.DirectSpec`.
    private static let model = "claude-sonnet-5"
    private static let maxTokens = 700
    private static let historyLimit = 12

    /// The relay wire contract's cap on the `"context"` field of a `"chat"`
    /// request — see `cappedContext(_:limit:)`.
    static let contextCharacterLimit = 8000

    /// System-prompt rules: the assistant is an educational health
    /// companion, may only discuss the data in the provided context, must
    /// decline to diagnose/prescribe/interpret anything outside that
    /// context, must nudge toward a doctor or pharmacist whenever a finding
    /// comes up, and must keep answers short and plain-language.
    private static func systemPrompt(context: String) -> String {
        """
        You are an educational health companion inside Gemocode, a personal health-tracking \
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

    /// Truncates `context` to at most `limit` characters (defaulting to the
    /// relay wire contract's `"context"` cap of 8000), keeping the start of
    /// the text — `buildContext` front-loads the score and findings before
    /// less critical detail, so a prefix truncation keeps the most
    /// important facts. Pure and unit-testable, no networking.
    static func cappedContext(_ context: String, limit: Int = contextCharacterLimit) -> String {
        guard context.count > limit else { return context }
        return String(context.prefix(limit))
    }

    // MARK: Relay input shape ("chat" kind)

    /// One turn as sent to the relay's `POST /v1/ai/generate` `"chat"`
    /// input — `{"role": "user"|"assistant", "text": "..."}`.
    struct ChatTurn: Encodable, Sendable, Equatable {
        let role: String
        let text: String
    }

    /// The relay's `"chat"` input shape — `{"context": String, "messages":
    /// [ChatTurn]}`, capped client-side to the wire contract's ≤8000-char
    /// context / ≤12-message limits before this is built.
    struct ChatInput: Encodable, Sendable, Equatable {
        let context: String
        let messages: [ChatTurn]
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
        let trimmed = trimmedHistory(history, limit: historyLimit)
        guard !trimmed.isEmpty else {
            throw AIChatError.badResponse
        }
        let boundedContext = cappedContext(context)

        // On the relay path `input` (context + trimmed turns) is what's
        // sent — the relay owns model/system prompt. On the direct/BYOK
        // fallback path, `direct` supplies both, exactly as this service
        // built them before the transport was shared.
        let direct = AITransport.DirectSpec(
            model: model,
            system: systemPrompt(context: boundedContext),
            maxTokens: maxTokens,
            messages: trimmed.map { (role: $0.role == .user ? "user" : "assistant", text: $0.text) }
        )
        let input = ChatInput(
            context: boundedContext,
            messages: trimmed.map { ChatTurn(role: $0.role == .user ? "user" : "assistant", text: $0.text) }
        )

        do {
            return try await AITransport.generate(route: .chat, input: input, direct: direct)
        } catch {
            throw AIChatError.from(error)
        }
    }
}
