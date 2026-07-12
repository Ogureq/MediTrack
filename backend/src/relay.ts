// The report-summary relay: validates the app's structured-report payload,
// builds the Anthropic Messages API call, and streams the answer back as a
// small client-facing SSE event shape. See docs/ROADMAP.md Part 4 §1.3 for
// the design and MediTrack/Services/AISummaryService.swift for the client
// contract this mirrors (`ReportInput`/`reportSystemPrompt`) — the payload
// shape here is intentionally the same one the app already builds, so
// migrating the client to call this endpoint (§3.1 of the roadmap) is a
// transport change, not a data-model change.
//
// This file is split into two halves on purpose:
//   - Pure functions (validation, prompt/request building, SSE-event
//     mapping) — fully unit-tested in test/relay.test.ts, no network.
//   - `relayReportSummary`, which actually calls `fetch` and streams bytes
//     — not unit-tested here (no network in tests, per project convention),
//     but written to be a thin, inspectable composition of the pure parts.

// ---------------------------------------------------------------------------
// Structured request schema
// ---------------------------------------------------------------------------

export const MAX_TEXT_FIELD_LENGTH = 2000; // detail / profileSummary / delta strings
export const MAX_SHORT_FIELD_LENGTH = 200; // id / name / unit / category / severity / status / title / scoreLabel
export const MAX_FINDINGS = 50;
export const MAX_LAB_VALUES = 100;
export const MAX_DELTAS = 20;

export interface FindingPayload {
  id: string;
  severity: string;
  category: string;
  title: string;
  detail: string;
}

export interface LabValuePayload {
  id: string;
  name: string;
  value: number;
  unit: string;
  status: string;
}

export interface ReportSummaryRequest {
  score: number;
  scoreLabel?: string;
  profileSummary?: string | null;
  findings: FindingPayload[];
  labValues: LabValuePayload[];
  deltas: string[];
}

export interface ValidationResult {
  ok: boolean;
  value?: ReportSummaryRequest;
  errors: string[];
}

const TOP_LEVEL_KEYS = new Set(["score", "scoreLabel", "profileSummary", "findings", "labValues", "deltas"]);
const FINDING_KEYS = new Set(["id", "severity", "category", "title", "detail"]);
const LAB_VALUE_KEYS = new Set(["id", "name", "unit", "status", "value"]);

// Long unbroken runs of base64-alphabet characters are the shape of
// embedded image/PDF/attachment data (or any other binary blob) — this
// endpoint must never accept those, per the "reject attachments/base64"
// requirement and docs/ROADMAP.md Part 4 §2's data-boundary principle
// (engine-derived structured data only, never raw documents). 300 chars is
// comfortably longer than any legitimate title/detail sentence but far
// shorter than even a tiny image, so it catches attachment-shaped payloads
// without false-positiving on normal prose.
const BASE64_BLOB_PATTERN = /^[A-Za-z0-9+/_-]{300,}={0,2}$/;

function isPlainObject(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function checkUnknownKeys(obj: Record<string, unknown>, allowed: Set<string>, path: string, errors: string[]): void {
  for (const key of Object.keys(obj)) {
    if (!allowed.has(key)) {
      errors.push(`${path}.${key}: unknown field`);
    }
  }
}

function checkStringField(
  obj: Record<string, unknown>,
  key: string,
  path: string,
  maxLength: number,
  required: boolean,
  errors: string[]
): string | undefined {
  const value = obj[key];
  if (value === undefined || value === null) {
    if (required) errors.push(`${path}.${key}: required`);
    return undefined;
  }
  if (typeof value !== "string") {
    errors.push(`${path}.${key}: must be a string`);
    return undefined;
  }
  if (value.length > maxLength) {
    errors.push(`${path}.${key}: exceeds max length ${maxLength}`);
    return undefined;
  }
  if (BASE64_BLOB_PATTERN.test(value.replace(/\s+/g, ""))) {
    errors.push(`${path}.${key}: looks like binary/base64 data, which is not accepted`);
    return undefined;
  }
  return value;
}

/**
 * Validates an unknown request body against the report-summary schema:
 * `score` (int 0-100), `findings[]`, `labValues[]`, `deltas[]`, plus the
 * optional `scoreLabel`/`profileSummary` strings the client already sends
 * (see `AISummaryService.ReportInput` on the client). Rejects unknown
 * top-level or nested fields (so an `attachment`/`imageData`/etc. field
 * is rejected outright, not silently dropped), oversized free-text
 * fields, and base64-blob-shaped strings anywhere in the payload.
 */
export function validateReportSummaryRequest(body: unknown): ValidationResult {
  const errors: string[] = [];

  if (!isPlainObject(body)) {
    return { ok: false, errors: ["body: must be a JSON object"] };
  }

  checkUnknownKeys(body, TOP_LEVEL_KEYS, "body", errors);

  let score: number | undefined;
  if (typeof body.score !== "number" || !Number.isInteger(body.score)) {
    errors.push("body.score: must be an integer");
  } else if (body.score < 0 || body.score > 100) {
    errors.push("body.score: must be between 0 and 100");
  } else {
    score = body.score;
  }

  const scoreLabel = checkStringField(body, "scoreLabel", "body", MAX_SHORT_FIELD_LENGTH, false, errors);
  const profileSummary = checkStringField(body, "profileSummary", "body", MAX_TEXT_FIELD_LENGTH, false, errors);

  const findings: FindingPayload[] = [];
  if (body.findings === undefined) {
    errors.push("body.findings: required");
  } else if (!Array.isArray(body.findings)) {
    errors.push("body.findings: must be an array");
  } else if (body.findings.length > MAX_FINDINGS) {
    errors.push(`body.findings: exceeds max count ${MAX_FINDINGS}`);
  } else {
    body.findings.forEach((raw, index) => {
      const path = `body.findings[${index}]`;
      if (!isPlainObject(raw)) {
        errors.push(`${path}: must be an object`);
        return;
      }
      checkUnknownKeys(raw, FINDING_KEYS, path, errors);
      const id = checkStringField(raw, "id", path, MAX_SHORT_FIELD_LENGTH, true, errors);
      const severity = checkStringField(raw, "severity", path, MAX_SHORT_FIELD_LENGTH, true, errors);
      const category = checkStringField(raw, "category", path, MAX_SHORT_FIELD_LENGTH, true, errors);
      const title = checkStringField(raw, "title", path, MAX_SHORT_FIELD_LENGTH, true, errors);
      const detail = checkStringField(raw, "detail", path, MAX_TEXT_FIELD_LENGTH, true, errors);
      if (id !== undefined && severity !== undefined && category !== undefined && title !== undefined && detail !== undefined) {
        findings.push({ id, severity, category, title, detail });
      }
    });
  }

  const labValues: LabValuePayload[] = [];
  if (body.labValues === undefined) {
    errors.push("body.labValues: required");
  } else if (!Array.isArray(body.labValues)) {
    errors.push("body.labValues: must be an array");
  } else if (body.labValues.length > MAX_LAB_VALUES) {
    errors.push(`body.labValues: exceeds max count ${MAX_LAB_VALUES}`);
  } else {
    body.labValues.forEach((raw, index) => {
      const path = `body.labValues[${index}]`;
      if (!isPlainObject(raw)) {
        errors.push(`${path}: must be an object`);
        return;
      }
      checkUnknownKeys(raw, LAB_VALUE_KEYS, path, errors);
      const id = checkStringField(raw, "id", path, MAX_SHORT_FIELD_LENGTH, true, errors);
      const name = checkStringField(raw, "name", path, MAX_SHORT_FIELD_LENGTH, true, errors);
      const unit = checkStringField(raw, "unit", path, MAX_SHORT_FIELD_LENGTH, true, errors);
      const status = checkStringField(raw, "status", path, MAX_SHORT_FIELD_LENGTH, true, errors);
      let value: number | undefined;
      if (typeof raw.value !== "number" || !Number.isFinite(raw.value)) {
        errors.push(`${path}.value: must be a finite number`);
      } else {
        value = raw.value;
      }
      if (id !== undefined && name !== undefined && unit !== undefined && status !== undefined && value !== undefined) {
        labValues.push({ id, name, unit, status, value });
      }
    });
  }

  const deltas: string[] = [];
  if (body.deltas === undefined) {
    errors.push("body.deltas: required");
  } else if (!Array.isArray(body.deltas)) {
    errors.push("body.deltas: must be an array");
  } else if (body.deltas.length > MAX_DELTAS) {
    errors.push(`body.deltas: exceeds max count ${MAX_DELTAS}`);
  } else {
    body.deltas.forEach((raw, index) => {
      const path = `body.deltas[${index}]`;
      if (typeof raw !== "string") {
        errors.push(`${path}: must be a string`);
        return;
      }
      if (raw.length > MAX_TEXT_FIELD_LENGTH) {
        errors.push(`${path}: exceeds max length ${MAX_TEXT_FIELD_LENGTH}`);
        return;
      }
      if (BASE64_BLOB_PATTERN.test(raw.replace(/\s+/g, ""))) {
        errors.push(`${path}: looks like binary/base64 data, which is not accepted`);
        return;
      }
      deltas.push(raw);
    });
  }

  if (errors.length > 0 || score === undefined) {
    return { ok: false, errors };
  }

  return {
    ok: true,
    errors: [],
    value: {
      score,
      scoreLabel,
      profileSummary: profileSummary ?? null,
      findings,
      labValues,
      deltas
    }
  };
}

// ---------------------------------------------------------------------------
// Anthropic Messages API request construction
// ---------------------------------------------------------------------------

export const ANTHROPIC_MESSAGES_URL = "https://api.anthropic.com/v1/messages";
export const ANTHROPIC_API_VERSION = "2023-06-01";
export const REPORT_SUMMARY_MAX_TOKENS = 1024; // matches the client's current value (AISummaryService.swift)

/**
 * Persona, hard safety rails, and the exact input/output JSON shape. This
 * is the versioned, server-side system prompt described in
 * docs/ROADMAP.md Part 4 §1.3/§3.1 — the client no longer sends or
 * controls it. Bump `REPORT_SUMMARY_SYSTEM_PROMPT_VERSION` on any wording
 * change so it shows up in usage logs/metrics if it's ever attached there.
 */
export const REPORT_SUMMARY_SYSTEM_PROMPT_VERSION = "2026-07-p1";

export const REPORT_SUMMARY_SYSTEM_PROMPT = `You are an educational health analyst inside MediTrack, a personal health-tracking \
app. The user message is a JSON object already computed by a deterministic, \
rule-based analysis engine on the user's device — you did not compute any of it and \
must not recompute, re-derive, or contradict it. Its shape is:
{ "score": Int, "scoreLabel": String or null, "profileSummary": String or null, \
"findings": [{"id", "severity", "category", "title", "detail"}], \
"labValues": [{"id", "name", "value", "unit", "status"}], "deltas": [String] }

Hard rules:
1. Never diagnose. Do not state or imply the user has a specific medical condition.
2. Never prescribe or recommend starting, stopping, or changing any medication or \
treatment.
3. Never invent a number. Every number you write must already appear in the input JSON.
4. Every section you write must cite the finding ids ("f0", "f1", ...) it draws from. \
Never introduce a concern with no corresponding finding id.
5. Always end with at least three specific follow-up questions the user can bring to \
their doctor.
6. Keep the tone warm, plain-language, and non-alarmist — this is educational only, \
not medical advice.

Respond with plain prose only (no markdown headers, no code fences, no JSON) — a short \
overview paragraph, then the findings organized into clearly-labeled sections, then the \
follow-up questions.`;

export interface AnthropicMessagesRequest {
  model: string;
  max_tokens: number;
  system: string;
  stream: true;
  messages: [{ role: "user"; content: string }];
}

export function buildAnthropicRequest(input: ReportSummaryRequest, model: string): AnthropicMessagesRequest {
  return {
    model,
    max_tokens: REPORT_SUMMARY_MAX_TOKENS,
    system: REPORT_SUMMARY_SYSTEM_PROMPT,
    stream: true,
    messages: [{ role: "user", content: JSON.stringify(input) }]
  };
}

// ---------------------------------------------------------------------------
// SSE re-framing: Anthropic's wire format -> the client's minimal event shape
// ---------------------------------------------------------------------------

/** The subset of Anthropic's streaming Messages API event shapes this relay cares about. */
export interface AnthropicSSEEventLike {
  type: string;
  delta?: { type?: string; text?: string; stop_reason?: string | null };
  error?: { type?: string; message?: string };
}

export type ClientSSEEvent =
  | { type: "delta"; text: string }
  | { type: "done" }
  | { type: "refused" }
  | { type: "error"; code: string; message?: string };

/**
 * Maps one parsed Anthropic stream event to the client's event shape, or
 * `null` if this event carries nothing the client needs (e.g.
 * `content_block_start`). Refusal detection mirrors the existing client
 * logic (`AISummaryError.refused` in AISummaryService.swift), just
 * relocated server-side per docs/ROADMAP.md Part 4 §1.3: a terminal
 * `message_delta` with `stop_reason: "refusal"` maps to `{"type":"refused"}`
 * instead of passing through whatever partial text preceded it.
 */
export function mapAnthropicSSEEvent(event: AnthropicSSEEventLike): ClientSSEEvent | null {
  switch (event.type) {
    case "content_block_delta":
      if (event.delta?.type === "text_delta" && typeof event.delta.text === "string") {
        return { type: "delta", text: event.delta.text };
      }
      return null;
    case "message_delta":
      if (event.delta?.stop_reason === "refusal") {
        return { type: "refused" };
      }
      return null;
    case "message_stop":
      return { type: "done" };
    case "error":
      return { type: "error", code: event.error?.type ?? "unknown_error", message: event.error?.message };
    default:
      return null;
  }
}

export function formatClientSSEEvent(event: ClientSSEEvent): string {
  return `data: ${JSON.stringify(event)}\n\n`;
}

/** Maps a non-2xx Anthropic HTTP response (no stream ever started) to a typed client error event. */
export function mapAnthropicHttpError(status: number, body: unknown): Extract<ClientSSEEvent, { type: "error" }> {
  const message =
    isPlainObject(body) && isPlainObject(body.error) && typeof body.error.message === "string"
      ? body.error.message
      : "The AI service returned an error.";
  const code = status === 429 ? "rate_limited" : status >= 500 ? "upstream_unavailable" : "upstream_error";
  return { type: "error", code, message };
}

// ---------------------------------------------------------------------------
// Network wiring (not unit-tested — see test/relay.test.ts for what is)
// ---------------------------------------------------------------------------

/**
 * Calls the Anthropic Messages API with `stream: true` and returns a
 * `Response` whose body is a `ReadableStream` of re-framed SSE events
 * (`formatClientSSEEvent`-shaped), suitable for returning directly from a
 * Worker `fetch` handler. Pass `fetchImpl` to substitute a stub in tests
 * that specifically want to exercise this wiring (this module's own test
 * suite does not — it hits network only in production, per the "no
 * network in tests" project convention).
 */
export async function relayReportSummary(opts: {
  anthropicApiKey: string;
  input: ReportSummaryRequest;
  model: string;
  fetchImpl?: typeof fetch;
}): Promise<Response> {
  const doFetch = opts.fetchImpl ?? fetch;
  const anthropicRequest = buildAnthropicRequest(opts.input, opts.model);

  const upstream = await doFetch(ANTHROPIC_MESSAGES_URL, {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "x-api-key": opts.anthropicApiKey,
      "anthropic-version": ANTHROPIC_API_VERSION
    },
    body: JSON.stringify(anthropicRequest)
  });

  if (!upstream.ok || !upstream.body) {
    const errorBody = await safeJson(upstream);
    const clientEvent = mapAnthropicHttpError(upstream.status, errorBody);
    return new Response(formatClientSSEEvent(clientEvent), {
      // The error is framed as an SSE event (not an HTTP error status) so
      // the client's single event-stream parser handles both the
      // "stream started, then refused/errored mid-way" and "never started"
      // cases uniformly, per §1.3's re-framing design.
      status: 200,
      headers: { "content-type": "text/event-stream" }
    });
  }

  const { readable, writable } = new TransformStream<Uint8Array, Uint8Array>();
  void pumpAnthropicStream(upstream.body, writable);

  return new Response(readable, {
    status: 200,
    headers: {
      "content-type": "text/event-stream",
      "cache-control": "no-cache",
      connection: "keep-alive"
    }
  });
}

async function pumpAnthropicStream(source: ReadableStream<Uint8Array>, dest: WritableStream<Uint8Array>): Promise<void> {
  const reader = source.pipeThrough(new TextDecoderStream()).getReader();
  const writer = dest.getWriter();
  const encoder = new TextEncoder();
  let buffer = "";
  try {
    while (true) {
      const { value, done } = await reader.read();
      if (done) break;
      buffer += value;
      const lines = buffer.split("\n");
      buffer = lines.pop() ?? "";
      for (const line of lines) {
        if (!line.startsWith("data:")) continue;
        const jsonText = line.slice(5).trim();
        if (!jsonText || jsonText === "[DONE]") continue;
        let parsed: AnthropicSSEEventLike;
        try {
          parsed = JSON.parse(jsonText) as AnthropicSSEEventLike;
        } catch {
          continue;
        }
        const clientEvent = mapAnthropicSSEEvent(parsed);
        if (clientEvent) {
          await writer.write(encoder.encode(formatClientSSEEvent(clientEvent)));
        }
      }
    }
  } finally {
    await writer.close();
  }
}

async function safeJson(response: Response): Promise<unknown> {
  try {
    return await response.json();
  } catch {
    return null;
  }
}
