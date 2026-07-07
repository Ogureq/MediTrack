import Foundation

// MARK: - AI plain-language summary (opt-in)
//
// Strictly opt-in: the user supplies their own Anthropic API key in
// Profile & Settings. Only the generated review text is sent — never
// documents, attachments, or the raw database.

enum AISummaryError: LocalizedError {
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
            "The AI declined to summarize this content."
        case .http(let status, let message):
            "AI request failed (\(status)): \(message)"
        }
    }
}

enum AISummaryService {

    static let apiKeyDefaultsKey = "anthropicAPIKey"

    static var isConfigured: Bool {
        !(UserDefaults.standard.string(forKey: apiKeyDefaultsKey) ?? "").isEmpty
    }

    private static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    private static let model = "claude-opus-4-8"

    private static let systemPrompt = """
        You are a friendly health-literacy assistant inside a personal health-tracking app. \
        The user will give you a structured, rule-based review of their own health data. \
        Rewrite it as a short plain-language summary (at most ~180 words) for the patient: \
        warm, clear, and non-alarmist. Structure it as: what looks good, what is worth \
        watching, and what to bring up with their doctor. Never diagnose, never suggest \
        medication changes or treatments, and close with a one-line reminder to discuss \
        results with their clinician. Plain text only, no markdown headers.
        """

    // MARK: Request/response shapes (Messages API)

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

    static func summarize(_ review: HealthReview) async throws -> String {
        guard let key = UserDefaults.standard.string(forKey: apiKeyDefaultsKey),
              !key.isEmpty else {
            throw AISummaryError.missingKey
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 90
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        request.httpBody = try encoder.encode(RequestBody(
            model: model,
            maxTokens: 1024,
            system: systemPrompt,
            messages: [RequestMessage(role: "user", content: review.shareText)]
        ))

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AISummaryError.badResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let message = (try? JSONDecoder().decode(APIErrorBody.self, from: data))?
                .error.message ?? "no details"
            throw AISummaryError.http(http.statusCode, message)
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let decoded = try decoder.decode(ResponseBody.self, from: data)

        // Check the stop reason before reading content: a safety refusal
        // returns HTTP 200 with an empty or partial content array.
        if decoded.stopReason == "refusal" {
            throw AISummaryError.refused
        }
        let text = decoded.content
            .filter { $0.type == "text" }
            .compactMap(\.text)
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            throw AISummaryError.badResponse
        }
        return text
    }
}
