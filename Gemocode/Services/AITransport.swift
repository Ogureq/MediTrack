import Foundation

// MARK: - Shared AI transport layer
//
// The single place that knows how to reach "the model" — either the
// owner-funded Cloudflare Workers relay (premium users; the owner's
// Anthropic API key never leaves the server) or, as a fallback for
// development and until the relay is deployed, a direct BYOK call to the
// Anthropic Messages API using the key the user pasted into Profile &
// Settings. `AISummaryService` and `AIChatService` both build their prompts
// exactly as before and hand them to `AITransport.generate` — this file owns
// every network detail: which transport to use, the relay's anonymous-auth
// token dance, timeouts, refusal detection, HTTP error mapping, and the
// `stripCodeFence` helper both callers' JSON parsing relies on.
//
// Data-boundary note: like the callers that use it, this file only ever
// transmits the structured, engine-derived payloads those callers build —
// never raw documents, attachments, OCR text, or the on-device database.

// MARK: - Route

/// Which server-side "kind" of AI request this is. Mirrors the relay's
/// `POST /v1/ai/generate` body's `"kind"` field exactly — the raw value is
/// sent on the wire on the relay path (the direct/BYOK path never sends a
/// `kind`, only the caller-built `DirectSpec`).
/// Bumped whenever an AI-availability input changes (the BYOK key is set or
/// cleared, the relay URL changes) so SwiftUI views that gate on
/// `AISummaryService.isConfigured` — a plain computed property over
/// Keychain/UserDefaults that SwiftUI cannot observe — re-render and
/// re-evaluate the gate. Views hold `@ObservedObject AIConfigState.shared`.
@MainActor
final class AIConfigState: ObservableObject {
    static let shared = AIConfigState()
    @Published private(set) var revision = 0
    func bump() { revision += 1 }
}

enum AIRoute: String {
    case report
    case chat
    case extract
}

// MARK: - Errors

/// Every failure mode either transport can produce, with an
/// educational-tone, jargon-free message suitable for showing directly in
/// the UI (callers currently surface `error.localizedDescription` as-is).
enum AITransportError: LocalizedError {
    /// Neither the relay nor a BYOK key is available.
    case notConfigured
    /// The relay rejected the request's credentials, including after one
    /// automatic re-authentication attempt.
    case unauthorized
    /// The relay requires a premium subscription for this request.
    case premiumRequired
    /// The relay's per-user or global daily usage cap has been reached.
    case quotaExceeded
    /// The model declined to respond (a safety refusal, not an error).
    case refused
    /// The response couldn't be parsed into the expected shape.
    case badResponse
    /// A non-2xx HTTP response with a status code and a short message.
    case http(Int, String)
    /// The request never reached the server (offline, timed out, etc).
    case network(Error)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            "AI features aren't set up yet. Add your Anthropic API key in Profile & Settings, or check back once the hosted AI service is available."
        case .unauthorized:
            "Your AI session couldn't be verified. Please try again."
        case .premiumRequired:
            "This AI feature is part of Gemocode Premium."
        case .quotaExceeded:
            "The AI service has reached today's usage limit. Please try again tomorrow."
        case .refused:
            "The AI declined to respond to this request."
        case .badResponse:
            "The AI service returned an unexpected response."
        case .http(let status, let message):
            "AI request failed (\(status)): \(message)"
        case .network(let error):
            "Couldn't reach the AI service: \(error.localizedDescription)"
        }
    }
}

// MARK: - Relay configuration

/// Where the owner's Cloudflare Workers relay lives. Empty/invalid resolves
/// to `nil`, which routes every call onto the direct/BYOK fallback.
enum RelayConfig {
    /// Compiled-in fallback: the owner's deployed relay. Every build routes
    /// AI calls through this Worker unless a `relay.baseURL` UserDefaults
    /// override points elsewhere (or it's cleared, which falls back to BYOK).
    static let defaultBaseURLString = "https://gemocode-relay.ogureq.workers.dev"

    /// UserDefaults key an owner/tester can set (e.g. via a debug menu or
    /// `-relay.baseURL <url>` launch argument) to point at a relay instance
    /// without a rebuild — always wins over `defaultBaseURLString` when
    /// non-empty.
    static let defaultsKey = "relay.baseURL"

    /// The relay's base URL, or `nil` if none is configured. A value is
    /// only considered configured if it parses as an absolute URL with an
    /// `http`/`https` scheme and a host — anything else (empty string,
    /// garbage text, a bare path) is treated the same as "unset".
    static var baseURL: URL? {
        let override = UserDefaults.standard.string(forKey: defaultsKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let candidate = (override?.isEmpty == false) ? override! : defaultBaseURLString
        return parse(candidate)
    }

    /// Pure parsing logic, split out from the `UserDefaults` read above so
    /// it can be unit-tested directly without touching real defaults.
    static func parse(_ candidate: String) -> URL? {
        guard !candidate.isEmpty, let url = URL(string: candidate),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.host != nil
        else {
            return nil
        }
        return url
    }
}

// MARK: - Transport

enum AITransport {

    // MARK: Availability

    /// Whether *some* AI transport is usable right now — the relay is
    /// configured, or a BYOK key is present. UI gates AI-feature entry
    /// points off this rather than the BYOK key alone.
    static var isAvailable: Bool {
        RelayConfig.baseURL != nil || !(AISummaryService.apiKey ?? "").isEmpty
    }

    // MARK: Caller-supplied prompt (direct/BYOK path only)

    /// Everything the direct Anthropic Messages API call needs that the
    /// relay instead owns server-side: model choice, system prompt, output
    /// budget, and the message turns. Ignored entirely on the relay path —
    /// the relay decides model and system prompt itself so callers can't
    /// smuggle instructions past the server-side safety rails.
    struct DirectSpec {
        let model: String
        let system: String
        let maxTokens: Int
        let messages: [(role: String, text: String)]
        /// Sampling temperature for the direct call, or nil for the API
        /// default. Extraction pins 0 for determinism.
        let temperature: Double?

        init(model: String, system: String, maxTokens: Int, messages: [(role: String, text: String)], temperature: Double? = nil) {
            self.model = model
            self.system = system
            self.maxTokens = maxTokens
            self.messages = messages
            self.temperature = temperature
        }
    }

    /// The relay's `POST /v1/ai/generate` request body: `{"kind":...,
    /// "input":...}`. Generic (rather than `AnyEncodable`) so each caller's
    /// own structured input type is encoded with no extra boxing — kept
    /// internal (not `private`) so `AITransportTests` can assert on the
    /// wire shape directly.
    struct GenerateRequestBody<Input: Encodable>: Encodable {
        let kind: String
        let input: Input
    }

    /// Generates model output for `route`, preferring the relay when
    /// configured and falling back to a direct BYOK call otherwise.
    ///
    /// - Parameters:
    ///   - route: which server-side prompt/model to use on the relay path.
    ///   - input: the structured, engine-derived payload sent as `"input"`
    ///     on the relay path (never raw documents/attachments/database rows).
    ///   - direct: the model/system prompt/messages to use on the direct
    ///     path — ignored on the relay path, where the server owns prompts.
    /// - Returns: the model's plain-text output.
    /// - Throws: `AITransportError` on any failure; never returns partial
    ///   or unverified output.
    static func generate(
        route: AIRoute,
        input: some Encodable & Sendable,
        direct: DirectSpec
    ) async throws -> String {
        if RelayConfig.baseURL != nil {
            return try await generateViaRelay(route: route, input: input, isRetry: false)
        }
        if let key = AISummaryService.apiKey, !key.isEmpty {
            return try await generateDirect(spec: direct, apiKey: key)
        }
        throw AITransportError.notConfigured
    }

    // MARK: stripCodeFence (shared)

    /// Tolerates a fenced ```json ... ``` wrapper, which models sometimes
    /// emit even when asked to respond with raw JSON only. Shared by both
    /// callers' JSON-parsing code so there's exactly one copy of this rule.
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

    // MARK: - Relay path

    private static let relayGenerateTimeoutInterval: TimeInterval = 60

    /// Photo extraction needs a longer deadline than a text generation: the
    /// request carries a base64 image uphill on a phone connection, then the
    /// relay makes its own vision call (now with retries). The relay path
    /// used to share the 60s text budget — a *shorter* deadline than the
    /// BYOK path's 90s despite doing strictly more work — which turned
    /// slow-but-healthy scans into failures.
    private static let relayExtractLabsTimeoutInterval: TimeInterval = 120
    private static let relayAuthTimeoutInterval: TimeInterval = 20

    fileprivate static let relayDeviceIDAccount = "relay.deviceID"
    fileprivate static let relayTokenAccount = "relay.token"

    private struct GenerateResponse: Decodable {
        let text: String
        let refused: Bool
    }

    private struct GenerateErrorBody: Decodable {
        struct Inner: Decodable {
            let code: String
            let message: String
        }
        let error: Inner
    }

    private static func generateViaRelay(
        route: AIRoute,
        input: some Encodable & Sendable,
        isRetry: Bool
    ) async throws -> String {
        guard let baseURL = RelayConfig.baseURL else {
            throw AITransportError.notConfigured
        }

        let token: String
        do {
            token = try await RelayAuthState.shared.validToken(baseURL: baseURL)
        } catch let error as AITransportError {
            throw error
        } catch {
            throw AITransportError.network(error)
        }

        var request = URLRequest(url: baseURL.appendingPathComponent("v1/ai/generate"))
        request.httpMethod = "POST"
        request.timeoutInterval = relayGenerateTimeoutInterval
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        do {
            request.httpBody = try JSONEncoder().encode(GenerateRequestBody(kind: route.rawValue, input: input))
        } catch {
            throw AITransportError.badResponse
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw AITransportError.network(error)
        }
        guard let http = response as? HTTPURLResponse else {
            throw AITransportError.badResponse
        }

        // A single retry: if the token was rejected, drop it (both the
        // in-memory cache and the persisted copy) and re-authenticate once
        // before giving up.
        if http.statusCode == 401, !isRetry {
            await RelayAuthState.shared.invalidate()
            return try await generateViaRelay(route: route, input: input, isRetry: true)
        }

        guard (200..<300).contains(http.statusCode) else {
            throw mapRelayError(status: http.statusCode, data: data)
        }

        guard let decoded = try? JSONDecoder().decode(GenerateResponse.self, from: data) else {
            throw AITransportError.badResponse
        }
        if decoded.refused {
            throw AITransportError.refused
        }
        guard !decoded.text.isEmpty else {
            throw AITransportError.badResponse
        }
        return decoded.text
    }

    /// Maps a non-200 `/v1/ai/generate` response — `{"error":{"code",
    /// "message"}}` — to an `AITransportError`. Falls back to the HTTP
    /// status code when the body is missing or carries an unrecognized
    /// `code`, so a relay running a slightly different error vocabulary
    /// still degrades to a sensible error rather than a blank one.
    static func mapRelayError(status: Int, data: Data) -> AITransportError {
        let body = try? JSONDecoder().decode(GenerateErrorBody.self, from: data)
        let message = body?.error.message ?? "no details"
        switch body?.error.code {
        case "quota_exceeded":
            return .quotaExceeded
        case "premium_required":
            return .premiumRequired
        case "unauthorized":
            return .unauthorized
        case "bad_request":
            return .badResponse
        case "upstream_error":
            return .http(status, message)
        default:
            switch status {
            case 429: return .quotaExceeded
            case 402: return .premiumRequired
            case 401: return .unauthorized
            case 400: return .badResponse
            default: return .http(status, message)
            }
        }
    }

    /// Holds the relay's anonymous-auth device id + cached access token.
    /// An `actor` so the token dance (read-check-refresh-write) is safe
    /// under concurrent `generate` calls without a manual lock.
    private actor RelayAuthState {
        static let shared = RelayAuthState()

        private var token: String?
        private var expiresAt: Date?

        /// Refresh when fewer than 5 minutes remain — matches the "refresh
        /// when <5 min remain or on a 401" rule from the wire contract.
        private static let refreshMargin: TimeInterval = 5 * 60

        func validToken(baseURL: URL) async throws -> String {
            if let token, let expiresAt, expiresAt.timeIntervalSinceNow > Self.refreshMargin {
                return token
            }
            if let stored = Self.loadFromKeychain(), stored.expiresAt.timeIntervalSinceNow > Self.refreshMargin {
                token = stored.token
                expiresAt = stored.expiresAt
                return stored.token
            }
            return try await authenticate(baseURL: baseURL)
        }

        func invalidate() {
            token = nil
            expiresAt = nil
            KeychainStore.delete(AITransport.relayTokenAccount)
        }

        private struct AuthRequestBody: Encodable {
            let deviceID: String
        }

        private struct AuthResponseBody: Decodable {
            let token: String
            let expiresInSeconds: Double
        }

        private func authenticate(baseURL: URL) async throws -> String {
            var request = URLRequest(url: baseURL.appendingPathComponent("v1/auth/anonymous"))
            request.httpMethod = "POST"
            request.timeoutInterval = relayAuthTimeoutInterval
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try? JSONEncoder().encode(AuthRequestBody(deviceID: Self.deviceID()))

            let data: Data
            let response: URLResponse
            do {
                (data, response) = try await URLSession.shared.data(for: request)
            } catch {
                throw AITransportError.network(error)
            }
            guard let http = response as? HTTPURLResponse else {
                throw AITransportError.badResponse
            }
            guard (200..<300).contains(http.statusCode) else {
                if http.statusCode == 401 {
                    throw AITransportError.unauthorized
                }
                throw AITransportError.http(http.statusCode, "authentication failed")
            }
            guard let decoded = try? JSONDecoder().decode(AuthResponseBody.self, from: data) else {
                throw AITransportError.badResponse
            }

            let expiry = Date().addingTimeInterval(decoded.expiresInSeconds)
            token = decoded.token
            expiresAt = expiry
            Self.saveToKeychain(token: decoded.token, expiresAt: expiry)
            return decoded.token
        }

        /// A stable, per-install device id — created once and persisted in
        /// the Keychain, never regenerated for the life of the install.
        private static func deviceID() -> String {
            if let existing = KeychainStore.getString(AITransport.relayDeviceIDAccount), !existing.isEmpty {
                return existing
            }
            let fresh = UUID().uuidString
            KeychainStore.set(fresh, for: AITransport.relayDeviceIDAccount)
            return fresh
        }

        private struct StoredToken: Codable {
            let token: String
            let expiresAt: Date
        }

        private static func loadFromKeychain() -> (token: String, expiresAt: Date)? {
            guard let data = KeychainStore.get(AITransport.relayTokenAccount) else { return nil }
            guard let stored = try? JSONDecoder().decode(StoredToken.self, from: data) else { return nil }
            return (stored.token, stored.expiresAt)
        }

        private static func saveToKeychain(token: String, expiresAt: Date) {
            guard let data = try? JSONEncoder().encode(StoredToken(token: token, expiresAt: expiresAt)) else { return }
            KeychainStore.set(data, for: AITransport.relayTokenAccount)
        }
    }

    // MARK: - Direct (BYOK) path

    private static let directEndpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    private static let directTimeoutInterval: TimeInterval = 90

    private struct DirectRequestMessage: Encodable {
        let role: String
        let content: String
    }

    private struct DirectRequestBody: Encodable {
        let model: String
        let maxTokens: Int
        let temperature: Double?
        let system: String
        let messages: [DirectRequestMessage]
    }

    private struct DirectContentBlock: Decodable {
        let type: String
        let text: String?
    }

    private struct DirectResponseBody: Decodable {
        let content: [DirectContentBlock]
        let stopReason: String?
    }

    private struct DirectAPIErrorBody: Decodable {
        struct Inner: Decodable {
            let message: String
        }
        let error: Inner
    }

    private static func generateDirect(spec: DirectSpec, apiKey: String) async throws -> String {
        var request = URLRequest(url: directEndpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = directTimeoutInterval
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        let bodyEncoder = JSONEncoder()
        bodyEncoder.keyEncodingStrategy = .convertToSnakeCase
        let messages = spec.messages.map { DirectRequestMessage(role: $0.role, content: $0.text) }
        do {
            request.httpBody = try bodyEncoder.encode(DirectRequestBody(
                model: spec.model,
                maxTokens: spec.maxTokens,
                temperature: spec.temperature,
                system: spec.system,
                messages: messages
            ))
        } catch {
            throw AITransportError.badResponse
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw AITransportError.network(error)
        }
        guard let http = response as? HTTPURLResponse else {
            throw AITransportError.badResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let message = (try? JSONDecoder().decode(DirectAPIErrorBody.self, from: data))?
                .error.message ?? "no details"
            throw AITransportError.http(http.statusCode, message)
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let decoded = try? decoder.decode(DirectResponseBody.self, from: data) else {
            throw AITransportError.badResponse
        }

        // Check the stop reason before reading content: a safety refusal
        // returns HTTP 200 with an empty or partial content array.
        if decoded.stopReason == "refusal" {
            throw AITransportError.refused
        }

        let text = decoded.content
            .filter { $0.type == "text" }
            .compactMap(\.text)
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            throw AITransportError.badResponse
        }
        return text
    }
}

// MARK: - Image extraction (additive: AI bloodwork-photo extraction)
//
// A separate, self-contained path for the one AI feature that needs to send
// image content (`AIScanService`). Kept apart from `DirectSpec`/`generate` —
// which only ever carry plain-text messages — rather than growing those
// types to support content-block arrays: every existing caller
// (AISummaryService, AIChatService, QuickAddAIService) keeps working
// unchanged. Mirrors the existing relay-vs-BYOK branching, 401 retry-once,
// timeout, and refusal-before-content-read conventions exactly.

extension AITransport {

    /// One image to send as a Messages API `image` content block (direct/BYOK
    /// path) or as the relay's `{"image": {...}}` request body. Callers
    /// (`AIScanService`) downsample and base64-encode before constructing this.
    struct ImageBlock {
        let mediaType: String
        let base64Data: String
    }

    /// Direct/BYOK-path model + system prompt + user instruction for image
    /// extraction. The message is always exactly one user turn containing
    /// the image block followed by a short trigger text — mirrors the
    /// relay's own request shape (`content: [imageBlock, textBlock]` in
    /// `backend/src/extractLabs.ts`'s `callExtractLabsAnthropic`) so the
    /// BYOK path behaves identically to the relay path; unlike `DirectSpec`
    /// there's no free-form `messages` array to plumb through, since the
    /// turn shape is always exactly these two blocks. No `temperature` —
    /// current models reject the parameter; determinism guidance lives in
    /// the prompt, matching the relay.
    struct DirectImageSpec {
        let model: String
        let system: String
        let userInstruction: String
        let maxTokens: Int
    }

    /// Bundled result of `extractLabs(image:direct:)`: the same
    /// `{"values":[...]}` JSON text `AIScanService.mapValues` has always
    /// parsed (unchanged shape — `valuesJSON` is exactly what the old
    /// `String`-returning version of this function used to hand back),
    /// plus, additively, the relay's optional `facility` field. `facility`
    /// is always `nil` on the direct/BYOK path: that path's prompt has no
    /// facility instruction (see `AIScanService.directPrompt`'s doc comment
    /// on staying byte-identical to the server-owned prompt this pass
    /// doesn't touch), and is `nil` on the relay path too whenever the photo
    /// shows no facility name or the relay predates the field.
    struct ExtractLabsResult {
        let valuesJSON: String
        let facility: String?
    }

    /// Extracts lab values from `image`: relay when configured (POST
    /// `<baseURL>/v1/extract-labs` — no prompt/model is sent, the relay owns
    /// both), else a direct BYOK call using `direct`. Same routing/failure
    /// rule as `generate(route:input:direct:)`.
    static func extractLabs(image: ImageBlock, direct: DirectImageSpec) async throws -> ExtractLabsResult {
        if RelayConfig.baseURL != nil {
            return try await extractLabsViaRelay(image: image, isRetry: false)
        }
        if let key = AISummaryService.apiKey, !key.isEmpty {
            return try await extractLabsDirect(image: image, spec: direct, apiKey: key)
        }
        throw AITransportError.notConfigured
    }

    // MARK: Relay wire shape

    /// The relay's `POST /v1/extract-labs` request body — `{"image":
    /// {"media_type", "data"}}`. No prompt/model/kind field: the relay owns
    /// everything except the image, generalizing the "server owns prompts"
    /// rule `GenerateRequestBody` already follows for `/v1/ai/generate`.
    /// Kept internal (not private) so `AIScanServiceTests` can assert on the
    /// wire shape directly — same convention `GenerateRequestBody` uses.
    struct ExtractLabsRequestBody: Encodable {
        struct ImagePayload: Encodable {
            let mediaType: String
            let data: String
        }
        let image: ImagePayload
    }

    private static func extractLabsViaRelay(image: ImageBlock, isRetry: Bool) async throws -> ExtractLabsResult {
        guard let baseURL = RelayConfig.baseURL else {
            throw AITransportError.notConfigured
        }

        let token: String
        do {
            token = try await RelayAuthState.shared.validToken(baseURL: baseURL)
        } catch let error as AITransportError {
            throw error
        } catch {
            throw AITransportError.network(error)
        }

        var request = URLRequest(url: baseURL.appendingPathComponent("v1/extract-labs"))
        request.httpMethod = "POST"
        request.timeoutInterval = relayExtractLabsTimeoutInterval
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        do {
            request.httpBody = try encoder.encode(
                ExtractLabsRequestBody(image: .init(mediaType: image.mediaType, data: image.base64Data))
            )
        } catch {
            throw AITransportError.badResponse
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw AITransportError.network(error)
        }
        guard let http = response as? HTTPURLResponse else {
            throw AITransportError.badResponse
        }

        // Same single-retry-on-401 rule as generateViaRelay.
        if http.statusCode == 401, !isRetry {
            await RelayAuthState.shared.invalidate()
            return try await extractLabsViaRelay(image: image, isRetry: true)
        }

        guard (200..<300).contains(http.statusCode) else {
            throw mapRelayError(status: http.statusCode, data: data)
        }

        guard let decoded = try? JSONDecoder().decode(ExtractLabsResponseBody.self, from: data) else {
            throw AITransportError.badResponse
        }
        if decoded.refused {
            throw AITransportError.refused
        }
        // Re-serialize the relay's already-sanity-parsed `values` array back
        // into the same `{"values":[...]}` JSON text shape
        // `AIScanService.mapValues` expects, so that function stays the
        // single source of truth for catalog-matching/unit-conversion/
        // plausibility regardless of which path served the request.
        guard let reencoded = try? JSONEncoder().encode(ValuesEnvelope(values: decoded.values)),
              let text = String(data: reencoded, encoding: .utf8) else {
            throw AITransportError.badResponse
        }
        return ExtractLabsResult(valuesJSON: text, facility: decoded.facility)
    }

    /// The relay's `POST /v1/extract-labs` response — `{"values":
    /// [{"name","value","unit","sourceText"}], "facility": String?,
    /// "refused": Bool}`. Unlike `/v1/ai/generate`'s `{"text","refused"}`
    /// envelope, the relay has ALREADY sanity-parsed the model's raw text
    /// into a structured array server-side (see `backend/src/extractLabs.ts`'s
    /// `parseExtractedLabsText`) — there is no free-text `"text"` field to
    /// re-parse here. Field names are camelCase on the wire (the relay's
    /// `LabValue` TypeScript interface uses `sourceText`, not
    /// `source_text` — no snake_case conversion on this decode).
    ///
    /// `facility` is additive: an older relay deployment that predates this
    /// field simply omits the key, and — because the property is
    /// `Optional` — Swift's synthesized `Decodable` conformance already
    /// calls `decodeIfPresent` for it, so a missing key decodes to `nil`
    /// with no custom `init(from:)` needed. Kept internal (not private) so
    /// `AIScanServiceTests`/`AIScanServiceFacilityTests` can assert on it
    /// directly.
    struct ExtractLabsResponseBody: Decodable {
        struct Value: Codable {
            let name: String
            let value: Double
            let unit: String
            let sourceText: String
        }
        let values: [Value]
        let facility: String?
        let refused: Bool
    }

    /// Re-serializes an already-relay-validated `values` array back into the
    /// `{"values":[...]}` JSON text shape `AIScanService.mapValues` expects
    /// as input — see `extractLabsViaRelay` above.
    private struct ValuesEnvelope<Value: Encodable>: Encodable {
        let values: [Value]
    }

    // MARK: Direct (BYOK) wire shape

    /// Kept internal (not private) so `AIScanServiceTests` can assert on the
    /// wire shape directly.
    struct DirectImageSource: Encodable {
        let type: String = "base64"
        let mediaType: String
        let data: String
    }

    /// One user-message content block — either an image or a plain text
    /// block. Kept as a single flexible type (rather than an enum) so
    /// `Encodable` synthesis can omit whichever field doesn't apply
    /// (`encodeIfPresent` on the `Optional` properties), matching the
    /// existing decode-side `DirectContentBlock`'s shape convention. Kept
    /// internal (not private) so `AIScanServiceTests` can assert on the wire
    /// shape directly.
    struct DirectImageContentBlock: Encodable {
        let type: String
        let source: DirectImageSource?
        let text: String?

        static func image(mediaType: String, data: String) -> DirectImageContentBlock {
            DirectImageContentBlock(type: "image", source: DirectImageSource(mediaType: mediaType, data: data), text: nil)
        }

        static func text(_ text: String) -> DirectImageContentBlock {
            DirectImageContentBlock(type: "text", source: nil, text: text)
        }
    }

    /// Kept internal (not private) so `AIScanServiceTests` can assert on the
    /// wire shape directly.
    struct DirectImageMessage: Encodable {
        let role: String
        let content: [DirectImageContentBlock]
    }

    /// Kept internal (not private) so `AIScanServiceTests` can assert on the
    /// wire shape directly.
    struct DirectImageRequestBody: Encodable {
        let model: String
        let maxTokens: Int
        let system: String
        let messages: [DirectImageMessage]
    }

    private static func extractLabsDirect(image: ImageBlock, spec: DirectImageSpec, apiKey: String) async throws -> ExtractLabsResult {
        var request = URLRequest(url: directEndpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = directTimeoutInterval
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        let bodyEncoder = JSONEncoder()
        bodyEncoder.keyEncodingStrategy = .convertToSnakeCase
        let body = DirectImageRequestBody(
            model: spec.model,
            maxTokens: spec.maxTokens,
            system: spec.system,
            // Image block first, then the trigger text — mirrors the
            // relay's own `content: [imageBlock, textBlock]` order exactly
            // (backend/src/extractLabs.ts's callExtractLabsAnthropic).
            messages: [DirectImageMessage(role: "user", content: [
                .image(mediaType: image.mediaType, data: image.base64Data),
                .text(spec.userInstruction)
            ])]
        )
        do {
            request.httpBody = try bodyEncoder.encode(body)
        } catch {
            throw AITransportError.badResponse
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw AITransportError.network(error)
        }
        guard let http = response as? HTTPURLResponse else {
            throw AITransportError.badResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let message = (try? JSONDecoder().decode(DirectAPIErrorBody.self, from: data))?
                .error.message ?? "no details"
            throw AITransportError.http(http.statusCode, message)
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let decoded = try? decoder.decode(DirectResponseBody.self, from: data) else {
            throw AITransportError.badResponse
        }

        // Check the stop reason before reading content — same rule as
        // generateDirect: a safety refusal returns HTTP 200 with an empty
        // or partial content array.
        if decoded.stopReason == "refusal" {
            throw AITransportError.refused
        }

        let text = decoded.content
            .filter { $0.type == "text" }
            .compactMap(\.text)
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            throw AITransportError.badResponse
        }
        // Never populated on this path — see `ExtractLabsResult.facility`'s
        // doc comment.
        return ExtractLabsResult(valuesJSON: text, facility: nil)
    }
}
