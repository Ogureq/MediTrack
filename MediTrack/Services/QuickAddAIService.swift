import Foundation

// MARK: - AI-assisted Quick Add (premium)
//
// `QuickAddParser` (a deterministic, no-network keyword matcher) stays free
// and handles one line at a time. This service is the premium, AI-first
// path: it can turn a whole sentence or paragraph into either one
// (`complete`) or several (`completeBatch`) structured drafts. It reuses the
// same opt-in, Keychain-backed Anthropic API key as `AISummaryService`
// (`AISummaryService.apiKey` / `.isConfigured`) and the same Messages API
// call style, including the `stop_reason == "refusal"` check. Only the
// user's typed text is sent — never the on-device database. The model's job
// is purely to structure the text into one of five shapes (or, for the
// batch endpoint, an array of them); `draft(fromJSON:)` / `drafts(fromJSON:)`
// independently re-validate every value against `VitalPlausibility` — the
// same bounds `QuickAddParser` uses — so a hallucinated number can never
// reach SwiftData.

enum QuickAddAIError: LocalizedError {
    case missingKey
    case badResponse
    case refused
    case http(Int, String)
    case unrecognized

    var errorDescription: String? {
        switch self {
        case .missingKey:
            "Add your Anthropic API key in Profile & Settings first."
        case .badResponse:
            "The AI couldn't make sense of that — try rephrasing or fill it in manually."
        case .refused:
            "The AI declined to interpret this text."
        case .http(let status, let message):
            "AI request failed (\(status)): \(message)"
        case .unrecognized:
            "That doesn't look like a medication, vital, symptom, appointment, or reminder — try rephrasing."
        }
    }
}

enum QuickAddAIService {

    private static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    private static let model = "claude-haiku-4-5-20251001"

    private static let singleMaxTokens = 300
    private static let batchMaxTokens = 800

    /// Hard cap on how many drafts a single `completeBatch` call can
    /// produce. The prompt already asks the model for at most this many;
    /// `drafts(fromJSON:)` also enforces it defensively by dropping any
    /// elements beyond the cap, in case the model over-produces.
    private static let maxBatchSize = 10

    /// Persona and the exact five-shape output JSON. `now` is embedded as an
    /// ISO 8601 UTC timestamp so the model can resolve relative dates
    /// ("tomorrow", "next friday") the same way `QuickAddParser` does —
    /// resolution happens model-side; the mapping functions below never
    /// recompute dates themselves, they only validate and parse what comes back.
    private static func systemPrompt(now: Date) -> String {
        let todayISO = ISO8601DateFormatter().string(from: now)
        return """
            You convert a single free-text health-tracking line into ONE structured JSON \
            object for MediTrack, a personal health-tracking app. This is educational data \
            entry only, not medical advice — do not add commentary, diagnoses, or \
            recommendations. Today's date/time (ISO 8601, UTC) is \(todayISO) — use it to \
            resolve relative dates such as "tomorrow" or "next friday". Never invent a \
            numeric value that is not present in the user's text.

            Respond with a single JSON object and nothing else (no markdown, no commentary, \
            no code fence), matching exactly one of these five shapes:
            \(shapesDescription)

            \(sharedFieldRules) If nothing in the text maps to any of the five shapes, \
            respond with exactly {"kind":"unknown"}.
            """
    }

    /// Persona and output contract for the batch endpoint: the same five
    /// shapes as `systemPrompt`, but the model may report several distinct
    /// items found in one sentence or paragraph (e.g. "weighed 82kg, bp
    /// 130/85, slept 6h, took aspirin 100mg" → four elements).
    private static func batchSystemPrompt(now: Date) -> String {
        let todayISO = ISO8601DateFormatter().string(from: now)
        return """
            You convert free-text health-tracking notes — a sentence or a short paragraph — \
            into a JSON array of structured records for MediTrack, a personal health-tracking \
            app. The text may describe several distinct items (a vital, a medication, a \
            symptom, an appointment, a reminder) in one message; extract every one you can \
            confidently identify, up to \(maxBatchSize). This is educational data entry only, \
            not medical advice — do not add commentary, diagnoses, or recommendations. \
            Today's date/time (ISO 8601, UTC) is \(todayISO) — use it to resolve relative \
            dates such as "tomorrow" or "next friday". Never invent a numeric value that is \
            not present in the user's text.

            Respond with a single JSON array and nothing else (no markdown, no commentary, no \
            code fence), containing at most \(maxBatchSize) elements. Each element must match \
            exactly one of these five shapes:
            \(shapesDescription)

            \(sharedFieldRules)
            If nothing in the text maps to any of the five shapes, respond with an empty \
            array: [].
            """
    }

    private static let shapesDescription = """
        {"kind":"medication","name":String,"dosage":String,"frequency":String}
        {"kind":"vital","type":String,"value":Double,"secondary":Double or null}
        {"kind":"symptom","name":String,"severity":Int}
        {"kind":"appointment","title":String,"date":String (ISO 8601)}
        {"kind":"reminder","title":String,"time":String (ISO 8601) or null}
        """

    private static let sharedFieldRules = """
        "type" for vital must be exactly one of: weight, bloodPressure, heartRate, \
        bloodGlucose, oxygenSaturation, temperature, respiratoryRate, sleepHours. \
        Vitals are stored in canonical metric units — weight in kg, temperature in \
        degrees Celsius, blood pressure/glucose in mmHg/mg per dL — so convert if the \
        user wrote pounds or Fahrenheit. "secondary" is only used for bloodPressure \
        (diastolic); it is null for every other vital type. "severity" is an integer \
        from 1 to 10.
        """

    // MARK: Request/response envelope (mirrors AISummaryService's call style)

    private struct RequestMessage: Encodable {
        let role: String
        let content: String
    }

    private struct RequestBody: Encodable {
        let model: String
        let maxTokens: Int
        let temperature: Double
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
        struct Inner: Decodable { let message: String }
        let error: Inner
    }

    /// Tolerates a fenced ```json ... ``` wrapper, same as `AISummaryService.stripCodeFence`.
    static func stripCodeFence(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("```") else { return trimmed }
        var lines = trimmed.components(separatedBy: .newlines)
        if !lines.isEmpty { lines.removeFirst() }
        if let last = lines.last, last.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
            lines.removeLast()
        }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: JSON → QuickAddDraft (pure, unit-testable, no networking)

    private struct RawDraft: Decodable {
        let kind: String
        let name: String?
        let dosage: String?
        let frequency: String?
        let type: String?
        let value: Double?
        let secondary: Double?
        let severity: Int?
        let title: String?
        let date: String?
        let time: String?
    }

    /// Decodes the model's raw text into a `QuickAddDraft`, re-validating
    /// every field against `VitalPlausibility` so a hallucinated or
    /// out-of-range number is rejected exactly like a failed deterministic
    /// parse would be. All dates are expected pre-resolved to ISO 8601 by
    /// the model, so there's no `now`/`calendar` to thread through here.
    static func draft(fromJSON data: Data) throws -> QuickAddDraft {
        let raw = try decodeRawDraft(from: data)
        return try mapDraft(raw)
    }

    /// Decodes a JSON array of up to `maxBatchSize` raw drafts (the same
    /// five shapes as the single-draft contract) and validates each
    /// independently via `mapDraft`. An element that fails validation is
    /// dropped rather than failing the whole batch — a partially-hallucinated
    /// response shouldn't discard the items the model got right. If the
    /// array is empty, or every element fails validation, throws
    /// `.unrecognized`, the same signal `draft(fromJSON:)` uses for
    /// "nothing recognized".
    static func drafts(fromJSON data: Data) throws -> [QuickAddDraft] {
        var cleanedData = data
        if let text = String(data: data, encoding: .utf8) {
            cleanedData = Data(stripCodeFence(text).utf8)
        }

        let rawArray: [RawDraft]
        do {
            rawArray = try JSONDecoder().decode([RawDraft].self, from: cleanedData)
        } catch {
            throw QuickAddAIError.badResponse
        }

        let mapped = rawArray.prefix(maxBatchSize).compactMap { try? mapDraft($0) }
        guard !mapped.isEmpty else { throw QuickAddAIError.unrecognized }
        return Array(mapped)
    }

    private static func decodeRawDraft(from data: Data) throws -> RawDraft {
        var cleanedData = data
        if let text = String(data: data, encoding: .utf8) {
            cleanedData = Data(stripCodeFence(text).utf8)
        }
        do {
            return try JSONDecoder().decode(RawDraft.self, from: cleanedData)
        } catch {
            throw QuickAddAIError.badResponse
        }
    }

    /// Maps one already-decoded `RawDraft` to a `QuickAddDraft`, validating
    /// vitals against `VitalPlausibility`. Shared by both `draft(fromJSON:)`
    /// (single) and `drafts(fromJSON:)` (batch, via `compactMap(try?)` so an
    /// individual failure just drops that element).
    private static func mapDraft(_ raw: RawDraft) throws -> QuickAddDraft {
        switch raw.kind {
        case "medication":
            guard let name = nonEmpty(raw.name) else { throw QuickAddAIError.badResponse }
            return .medication(name: name, dosage: raw.dosage ?? "", frequency: raw.frequency ?? "")

        case "vital":
            guard let typeRaw = raw.type, let type = VitalType(rawValue: typeRaw) else {
                throw QuickAddAIError.unrecognized
            }
            guard let value = raw.value else { throw QuickAddAIError.badResponse }
            guard VitalPlausibility.isPlausible(value, secondary: raw.secondary, for: type) else {
                throw QuickAddAIError.badResponse
            }
            return .vital(type: type, value: value, secondary: type.usesSecondaryValue ? raw.secondary : nil)

        case "symptom":
            guard let name = nonEmpty(raw.name) else { throw QuickAddAIError.badResponse }
            let severity = min(10, max(1, raw.severity ?? 5))
            return .symptom(name: name, severity: severity)

        case "appointment":
            guard let title = nonEmpty(raw.title) else { throw QuickAddAIError.badResponse }
            guard let dateString = raw.date, let date = parseISO8601(dateString) else {
                throw QuickAddAIError.badResponse
            }
            return .appointment(title: title, date: date)

        case "reminder":
            guard let title = nonEmpty(raw.title) else { throw QuickAddAIError.badResponse }
            let time = raw.time.flatMap(parseISO8601)
            return .reminder(title: title, time: time)

        default:
            // Covers the model's own "nothing matched" signal ({"kind":"unknown"})
            // as well as any other unrecognized value.
            throw QuickAddAIError.unrecognized
        }
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    private static func parseISO8601(_ text: String) -> Date? {
        let withFractionalSeconds = ISO8601DateFormatter()
        withFractionalSeconds.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFractionalSeconds.date(from: text) { return date }
        return ISO8601DateFormatter().date(from: text)
    }

    // MARK: Network call

    /// Shared networking core for both `complete` (single draft) and
    /// `completeBatch` (multiple drafts) — identical request construction,
    /// HTTP/refusal handling, and response-text extraction; only the system
    /// prompt and token budget differ between the two callers.
    private static func send(system: String, maxTokens: Int, userText: String) async throws -> Data {
        guard let key = AISummaryService.apiKey, !key.isEmpty else {
            throw QuickAddAIError.missingKey
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        let bodyEncoder = JSONEncoder()
        bodyEncoder.keyEncodingStrategy = .convertToSnakeCase
        request.httpBody = try bodyEncoder.encode(RequestBody(
            model: model,
            maxTokens: maxTokens,
            temperature: 0,
            system: system,
            messages: [RequestMessage(role: "user", content: userText)]
        ))

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw QuickAddAIError.badResponse
        }
        guard let http = response as? HTTPURLResponse else {
            throw QuickAddAIError.badResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let message = (try? JSONDecoder().decode(APIErrorBody.self, from: data))?
                .error.message ?? "no details"
            throw QuickAddAIError.http(http.statusCode, message)
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let decoded: ResponseBody
        do {
            decoded = try decoder.decode(ResponseBody.self, from: data)
        } catch {
            throw QuickAddAIError.badResponse
        }

        // Check the stop reason before reading content: a safety refusal
        // returns HTTP 200 with an empty or partial content array.
        if decoded.stopReason == "refusal" {
            throw QuickAddAIError.refused
        }

        let responseText = decoded.content
            .filter { $0.type == "text" }
            .compactMap(\.text)
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !responseText.isEmpty, let responseData = responseText.data(using: .utf8) else {
            throw QuickAddAIError.badResponse
        }
        return responseData
    }

    /// Sends `text` to the Anthropic Messages API and maps the response to a
    /// single `QuickAddDraft`. Throws `QuickAddAIError` on any failure —
    /// missing key, network, refusal, malformed JSON, or a failed validation
    /// — so the caller can uniformly fall back to manual entry.
    static func complete(_ text: String) async throws -> QuickAddDraft {
        let responseData = try await send(system: systemPrompt(now: .now), maxTokens: singleMaxTokens, userText: text)
        return try draft(fromJSON: responseData)
    }

    /// Sends `text` (a whole sentence or paragraph that may describe several
    /// items) to the Anthropic Messages API and maps the response to zero or
    /// more `QuickAddDraft`s. Premium-only at the call site (`QuickAddView`
    /// gates this behind `PremiumStore.shared.isPremium`); this service
    /// itself has no notion of entitlement.
    static func completeBatch(_ text: String) async throws -> [QuickAddDraft] {
        let responseData = try await send(system: batchSystemPrompt(now: .now), maxTokens: batchMaxTokens, userText: text)
        return try drafts(fromJSON: responseData)
    }
}
