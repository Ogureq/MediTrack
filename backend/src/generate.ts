// POST /v1/ai/generate — the single AI entry point for all three kinds the
// iOS client needs ("report", "chat", "extract"). Non-streaming for v1 (see
// README.md's "Known simplifications" — streaming chat is a later upgrade).
// The server owns every system prompt and model choice; the client only ever
// sends `{"kind", "input"}` and gets back `{"text", "refused"}`.
//
// Prompts are ported from the client's current BYO-key services:
//   - "report" -> Gemocode/Services/AISummaryService.swift (src/relay.ts)
//   - "chat"   -> Gemocode/Services/AIChatService.swift (this file)
//   - "extract"-> Gemocode/Services/QuickAddAIService.swift (this file)
// adapted only where the server-relay shape requires it (plain prose instead
// of a nested JSON envelope for "report"; a date-only `today` instead of a
// full ISO 8601 timestamp for "extract" — see each builder below).
//
// This file is split the same way relay.ts is:
//   - Pure functions (validation, prompt/request building, response mapping)
//     — fully unit-tested in test/generate.test.ts, no network.
//   - `callAnthropic`, which actually calls `fetch` — not unit-tested here
//     directly (no network in tests), but callers can substitute a stub via
//     `fetchImpl` (exercised in test/index.test.ts with a mocked fetch).

import { checkStringField, checkUnknownKeys, isPlainObject, type ValidationResult } from "./validation";
import { REPORT_SUMMARY_SYSTEM_PROMPT, validateReportSummaryRequest, type ReportSummaryRequest } from "./relay";

// ---------------------------------------------------------------------------
// Kinds, per-kind limits (from the fixed wire contract)
// ---------------------------------------------------------------------------

export type GenerateKind = "report" | "chat" | "extract";

export const REPORT_MAX_TOKENS = 1500;
export const CHAT_MAX_TOKENS = 700;
export const EXTRACT_MAX_TOKENS = 800;

export const MAX_CHAT_CONTEXT_LENGTH = 8000;
export const MAX_CHAT_MESSAGE_LENGTH = 2000;
export const MAX_CHAT_MESSAGES = 12;
export const MAX_EXTRACT_TEXT_LENGTH = 1000;

/** Max tokens reserved against the quota ledger for a given kind — see quota.ts / README's "known simplifications" for why this is a pre-flight reservation, not a true-up against actual usage. */
export function maxTokensForKind(kind: GenerateKind): number {
  switch (kind) {
    case "report":
      return REPORT_MAX_TOKENS;
    case "chat":
      return CHAT_MAX_TOKENS;
    case "extract":
      return EXTRACT_MAX_TOKENS;
  }
}

// ---------------------------------------------------------------------------
// "chat" kind — input schema + system prompt
// ---------------------------------------------------------------------------

export interface ChatMessagePayload {
  role: "user" | "assistant";
  text: string;
}

export interface ChatInput {
  context: string;
  messages: ChatMessagePayload[];
}

const CHAT_TOP_LEVEL_KEYS = new Set(["context", "messages"]);
const CHAT_MESSAGE_KEYS = new Set(["role", "text"]);

export function validateChatInput(input: unknown): ValidationResult<ChatInput> {
  const errors: string[] = [];
  if (!isPlainObject(input)) {
    return { ok: false, errors: ["input: must be a JSON object"] };
  }

  checkUnknownKeys(input, CHAT_TOP_LEVEL_KEYS, "input", errors);
  const context = checkStringField(input, "context", "input", MAX_CHAT_CONTEXT_LENGTH, true, errors);

  const messages: ChatMessagePayload[] = [];
  if (input.messages === undefined) {
    errors.push("input.messages: required");
  } else if (!Array.isArray(input.messages)) {
    errors.push("input.messages: must be an array");
  } else if (input.messages.length === 0) {
    errors.push("input.messages: must not be empty");
  } else if (input.messages.length > MAX_CHAT_MESSAGES) {
    errors.push(`input.messages: exceeds max count ${MAX_CHAT_MESSAGES}`);
  } else {
    input.messages.forEach((raw, index) => {
      const path = `input.messages[${index}]`;
      if (!isPlainObject(raw)) {
        errors.push(`${path}: must be an object`);
        return;
      }
      checkUnknownKeys(raw, CHAT_MESSAGE_KEYS, path, errors);
      const role = raw.role;
      if (role !== "user" && role !== "assistant") {
        errors.push(`${path}.role: must be "user" or "assistant"`);
      }
      const text = checkStringField(raw, "text", path, MAX_CHAT_MESSAGE_LENGTH, true, errors);
      if ((role === "user" || role === "assistant") && text !== undefined) {
        messages.push({ role, text });
      }
    });
    if (messages.length > 0 && messages[0]!.role !== "user") {
      errors.push("input.messages[0].role: the first message must be \"user\"");
    }
  }

  if (errors.length > 0 || context === undefined) {
    return { ok: false, errors };
  }

  return { ok: true, errors: [], value: { context, messages } };
}

/**
 * Faithful port of `AIChatService.systemPrompt(context:)`
 * (Gemocode/Services/AIChatService.swift) — same persona, same six hard
 * rules, same "Context:" block. Unchanged in meaning; only the language
 * ("`the context block below`") stays literal since it still refers to the
 * embedded `Context:` section that follows.
 */
export function buildChatSystemPrompt(context: string): string {
  return `You are an educational health companion inside Gemocode, a personal health-tracking \
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
${context}`;
}

// ---------------------------------------------------------------------------
// "extract" kind — input schema + system prompt
// ---------------------------------------------------------------------------

export interface ExtractInput {
  text: string;
  today: string;
}

const EXTRACT_TOP_LEVEL_KEYS = new Set(["text", "today"]);
const DATE_ONLY_PATTERN = /^\d{4}-\d{2}-\d{2}$/;

export function validateExtractInput(input: unknown): ValidationResult<ExtractInput> {
  const errors: string[] = [];
  if (!isPlainObject(input)) {
    return { ok: false, errors: ["input: must be a JSON object"] };
  }

  checkUnknownKeys(input, EXTRACT_TOP_LEVEL_KEYS, "input", errors);
  const text = checkStringField(input, "text", "input", MAX_EXTRACT_TEXT_LENGTH, true, errors);

  let today: string | undefined;
  if (input.today === undefined) {
    errors.push("input.today: required");
  } else if (typeof input.today !== "string" || !DATE_ONLY_PATTERN.test(input.today)) {
    errors.push("input.today: must be a date string in YYYY-MM-DD format");
  } else {
    today = input.today;
  }

  if (errors.length > 0 || text === undefined || today === undefined) {
    return { ok: false, errors };
  }

  return { ok: true, errors: [], value: { text, today } };
}

/**
 * Ported from `QuickAddAIService.systemPrompt(now:)`
 * (Gemocode/Services/QuickAddAIService.swift). Adapted: the Swift version
 * embeds a full ISO 8601 UTC timestamp so the on-device call can resolve
 * relative dates ("tomorrow") the same way `QuickAddParser` does; the fixed
 * wire contract only sends a date-only `today` (`YYYY-MM-DD`), so the prompt
 * text below refers to a date instead of a date/time. All five output
 * shapes, the vital-type enum, the unit-conversion instruction, and the
 * "never invent a number" / "respond with exactly one JSON object" rules are
 * unchanged from the client version.
 */
export function buildExtractSystemPrompt(today: string): string {
  return `You convert a single free-text health-tracking line into ONE structured JSON \
object for Gemocode, a personal health-tracking app. This is educational data \
entry only, not medical advice — do not add commentary, diagnoses, or \
recommendations. Today's date (YYYY-MM-DD) is ${today} — use it to \
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
with exactly {"kind":"unknown"}.`;
}

// ---------------------------------------------------------------------------
// Top-level request validation + Anthropic request assembly
// ---------------------------------------------------------------------------

export interface AnthropicMessage {
  role: "user" | "assistant";
  content: string;
}

export interface AnthropicRequestSpec {
  max_tokens: number;
  temperature?: number;
  system: string;
  messages: AnthropicMessage[];
}

export interface GenerateValidationOk {
  ok: true;
  kind: GenerateKind;
  request: AnthropicRequestSpec;
}

export interface GenerateValidationErr {
  ok: false;
  errors: string[];
}

export type GenerateValidationResult = GenerateValidationOk | GenerateValidationErr;

const GENERATE_TOP_LEVEL_KEYS = new Set(["kind", "input"]);
const KNOWN_KINDS: ReadonlySet<string> = new Set(["report", "chat", "extract"]);

function buildReportRequest(input: ReportSummaryRequest): AnthropicRequestSpec {
  return {
    max_tokens: REPORT_MAX_TOKENS,
    system: REPORT_SUMMARY_SYSTEM_PROMPT,
    messages: [{ role: "user", content: JSON.stringify(input) }]
  };
}

function buildChatRequest(input: ChatInput): AnthropicRequestSpec {
  return {
    max_tokens: CHAT_MAX_TOKENS,
    system: buildChatSystemPrompt(input.context),
    messages: input.messages.map((m) => ({ role: m.role, content: m.text }))
  };
}

function buildExtractRequest(input: ExtractInput): AnthropicRequestSpec {
  return {
    max_tokens: EXTRACT_MAX_TOKENS,
    system: buildExtractSystemPrompt(input.today),
    messages: [{ role: "user", content: input.text }]
  };
}

/**
 * Validates the full `POST /v1/ai/generate` body (`{"kind", "input"}`) and,
 * on success, returns the fully-built (model-less — the caller attaches
 * `model` from env per kind) Anthropic Messages API request alongside the
 * resolved `kind`. Rejects unknown top-level fields and unknown/missing
 * `kind` values outright.
 */
export function validateGenerateRequest(body: unknown): GenerateValidationResult {
  if (!isPlainObject(body)) {
    return { ok: false, errors: ["body: must be a JSON object"] };
  }

  const errors: string[] = [];
  checkUnknownKeys(body, GENERATE_TOP_LEVEL_KEYS, "body", errors);

  const kind = body.kind;
  if (typeof kind !== "string" || !KNOWN_KINDS.has(kind)) {
    errors.push('body.kind: must be one of "report", "chat", "extract"');
    return { ok: false, errors };
  }
  if (errors.length > 0) {
    return { ok: false, errors };
  }

  const typedKind = kind as GenerateKind;
  switch (typedKind) {
    case "report": {
      const result = validateReportSummaryRequest(body.input);
      if (!result.ok || !result.value) return { ok: false, errors: result.errors };
      return { ok: true, kind: "report", request: buildReportRequest(result.value) };
    }
    case "chat": {
      const result = validateChatInput(body.input);
      if (!result.ok || !result.value) return { ok: false, errors: result.errors };
      return { ok: true, kind: "chat", request: buildChatRequest(result.value) };
    }
    case "extract": {
      const result = validateExtractInput(body.input);
      if (!result.ok || !result.value) return { ok: false, errors: result.errors };
      return { ok: true, kind: "extract", request: buildExtractRequest(result.value) };
    }
  }
}

// ---------------------------------------------------------------------------
// Anthropic Messages API — non-streaming call + response mapping
// ---------------------------------------------------------------------------

export const ANTHROPIC_MESSAGES_URL = "https://api.anthropic.com/v1/messages";
export const ANTHROPIC_API_VERSION = "2023-06-01";

interface AnthropicContentBlock {
  type: string;
  text?: string;
}

interface AnthropicMessageResponse {
  content?: AnthropicContentBlock[];
  stop_reason?: string | null;
}

export interface GenerateResult {
  text: string;
  refused: boolean;
}

/**
 * Maps a parsed, successful (HTTP 2xx) Anthropic Messages API response body
 * to the client's flat `{"text", "refused"}` shape. Mirrors the existing
 * client logic (`AISummaryError.refused`/`AIChatError.refused`/
 * `QuickAddAIError.refused` in the Swift services this endpoint replaces): a
 * `stop_reason: "refusal"` maps to `{"text": "", "refused": true}` — the
 * stop reason is checked before reading content, since a safety refusal
 * still returns HTTP 200 with an empty or partial content array.
 */
export function mapAnthropicMessageResponse(response: AnthropicMessageResponse): GenerateResult {
  if (response.stop_reason === "refusal") {
    return { text: "", refused: true };
  }
  const text = (response.content ?? [])
    .filter((block): block is AnthropicContentBlock & { text: string } => block.type === "text" && typeof block.text === "string")
    .map((block) => block.text)
    .join("\n")
    .trim();
  return { text, refused: false };
}

export type AnthropicCallResult =
  | { ok: true; result: GenerateResult }
  | { ok: false; status: number; message: string };

async function safeJson(response: Response): Promise<unknown> {
  try {
    return await response.json();
  } catch {
    return null;
  }
}

/**
 * Calls the Anthropic Messages API (non-streaming — no `stream` field is
 * set) with the given model + request spec and maps the result to either a
 * successful `GenerateResult` or a typed upstream failure. Every non-2xx
 * response and every network-level failure (fetch throwing) maps uniformly
 * to `{ok: false, status, message}` — the caller (src/index.ts) turns any
 * `ok: false` into the wire contract's single `502 upstream_error` shape;
 * this function keeps the real status around only for logging.
 */
export async function callAnthropic(opts: {
  anthropicApiKey: string;
  model: string;
  spec: AnthropicRequestSpec;
  fetchImpl?: typeof fetch;
}): Promise<AnthropicCallResult> {
  const doFetch = opts.fetchImpl ?? fetch;
  const body = {
    model: opts.model,
    max_tokens: opts.spec.max_tokens,
    ...(opts.spec.temperature !== undefined ? { temperature: opts.spec.temperature } : {}),
    system: opts.spec.system,
    messages: opts.spec.messages
  };

  let upstream: Response;
  try {
    upstream = await doFetch(ANTHROPIC_MESSAGES_URL, {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "x-api-key": opts.anthropicApiKey,
        "anthropic-version": ANTHROPIC_API_VERSION
      },
      body: JSON.stringify(body)
    });
  } catch (err) {
    return { ok: false, status: 0, message: err instanceof Error ? err.message : "Network error calling the AI service." };
  }

  const parsed = await safeJson(upstream);
  if (!upstream.ok) {
    const message =
      isPlainObject(parsed) && isPlainObject(parsed.error) && typeof parsed.error.message === "string"
        ? parsed.error.message
        : "The AI service returned an error.";
    return { ok: false, status: upstream.status, message };
  }

  return { ok: true, result: mapAnthropicMessageResponse((parsed ?? {}) as AnthropicMessageResponse) };
}
