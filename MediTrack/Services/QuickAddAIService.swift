import Foundation

// MARK: - AI-assisted Quick Add fallback (opt-in)
//
// When `QuickAddParser` (a deterministic, no-network keyword matcher) can't
// confidently interpret a Quick Add line, the UI may offer this AI fallback
// instead. It reuses the same opt-in, Keychain-backed Anthropic API key as
// `AISummaryService` (`AISummaryService.apiKey` / `.isConfigured`) and the
// same Messages API call style, including the `stop_reason == "refusal"`
// check. Only the user's typed sentence is sent — never the on-device
// database. The model's job is purely to structure the sentence into one of
// five shapes; `draft(fromJSON:now:calendar:)` independently re-validates
// every value against the same plausibility bounds `QuickAddParser` uses, so
// a hallucinated number can never reach SwiftData.

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

    /// Persona and the exact five-shape output JSON. `now` is embedded as an
    /// ISO 8601 UTC timestamp so the model can resolve relative dates
    /// ("tomorrow", "next friday") the same way `QuickAddParser` does —
    /// resolution happens model-side; the mapping function below never
    /// recomputes dates itself, it only validates and parses what comes back.
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
            {"kind":"medication","name":String,"dosage":String,"frequency":String}
            {"kind":"vital","type":String,"value":Double,"secondary":Double or null}
            {"kind":"symptom","name":String,"severity":Int}
            {"kind":"appointment","title":String,"date":String (ISO 8601)}
            {"kind":"reminder","title":String,"time":String (ISO 8601) or null}

            "type" for vital must be exactly one of: weight, bloodPressure, heartRate, \
            bloodGlucose, oxygenSaturation, temperature, respiratoryRate, sleepHours. \
            Vitals are stored in canonical metric units — weight in kg, temperature in \
            degrees Celsius, blood pressure/glucose in mmHg/mg per dL — so convert if the \
            user wrote pounds or Fahrenheit. "secondary" is only used for bloodPressure \
            (diastolic); it is null for every other vital type. "severity" is an integer \
            from 1 to 10. If nothing in the text maps to any of the five shapes, respond \
            with exactly {"kind":"unknown"}.
            """
    }

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
    /// every field against `QuickAddParser`'s plausibility bounds so a
    /// hallucinated or out-of-range number is rejected exactly like a failed
    /// deterministic parse would be. `now`/`calendar` are part of the
    /// contract for future date-relative validation; today all dates are
    /// expected pre-resolved to ISO 8601 by the model.
    static func draft(fromJSON data: Data, now: Date, calendar: Calendar) throws -> QuickAddDraft {
        var cleanedData = data
        if let text = String(data: data, encoding: .utf8) {
            cleanedData = Data(stripCodeFence(text).utf8)
        }

        let raw: RawDraft
        do {
            raw = try JSONDecoder().decode(RawDraft.self, from: cleanedData)
        } catch {
            throw QuickAddAIError.badResponse
        }

        switch raw.kind {
        case "medication":
            guard let name = nonEmpty(raw.name) else { throw QuickAddAIError.badResponse }
            return .medication(name: name, dosage: raw.dosage ?? "", frequency: raw.frequency ?? "")

        case "vital":
            guard let typeRaw = raw.type, let type = VitalType(rawValue: typeRaw) else {
                throw QuickAddAIError.unrecognized
            }
            guard let value = raw.value else { throw QuickAddAIError.badResponse }
            guard isPlausible(value, secondary: raw.secondary, for: type) else {
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

    /// Mirrors `QuickAddParser`'s plausibility bounds exactly, so an
    /// AI-hallucinated vital reading is rejected the same way a
    /// deterministic mis-parse would be: BP 60...260 / 30...200, weight
    /// 20...300 kg, HR 25...250, temp 25...45 °C, glucose 30...600, SpO2
    /// 50...100, respiratory rate 4...60, sleep 0...24 hours.
    private static func isPlausible(_ value: Double, secondary: Double?, for type: VitalType) -> Bool {
        switch type {
        case .bloodPressure:
            guard let secondary else { return false }
            return (60...260).contains(value) && (30...200).contains(secondary)
        case .weight:
            return (20...300).contains(value)
        case .heartRate:
            return (25...250).contains(value)
        case .temperature:
            return (25...45).contains(value)
        case .bloodGlucose:
            return (30...600).contains(value)
        case .oxygenSaturation:
            return (50...100).contains(value)
        case .respiratoryRate:
            return (4...60).contains(value)
        case .sleepHours:
            return (0...24).contains(value)
        }
    }

    // MARK: Network call

    /// Sends `text` to the Anthropic Messages API and maps the response to a
    /// `QuickAddDraft`. Throws `QuickAddAIError` on any failure — missing
    /// key, network, refusal, malformed JSON, or a failed validation — so
    /// the caller can uniformly fall back to manual entry.
    static func complete(_ text: String) async throws -> QuickAddDraft {
        guard let key = AISummaryService.apiKey, !key.isEmpty else {
            throw QuickAddAIError.missingKey
        }

        let now = Date.now
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
            maxTokens: 300,
            temperature: 0,
            system: systemPrompt(now: now),
            messages: [RequestMessage(role: "user", content: text)]
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

        return try draft(fromJSON: responseData, now: now, calendar: .current)
    }
}
