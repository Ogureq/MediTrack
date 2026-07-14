// The "report" kind's request schema and system prompt for POST
// /v1/ai/generate. See Gemocode/Services/AISummaryService.swift for the
// client contract this mirrors (`ReportInput`/`reportSystemPrompt`) — the
// payload shape here is intentionally the same one the app already builds.
// The prompt below is a faithful port of AISummaryService's
// `reportSystemPrompt`, adapted to ask for plain prose instead of a nested
// JSON envelope: `/v1/ai/generate` returns one flat `{"text", "refused"}`
// shape for every kind (see src/generate.ts), so there's no client-side
// consumer of a structured `{overview, sections, doctorQuestions}` object on
// this endpoint the way there was for the old direct-to-Anthropic call.
//
// This module is pure (validation + prompt text) and network-free — the
// actual Anthropic call, model selection, and response mapping live in
// src/generate.ts alongside the "chat"/"extract" kinds, so all three share
// one non-streaming request/response pipeline.

import { checkStringField, checkUnknownKeys, isPlainObject, type ValidationResult } from "./validation";

export const MAX_TEXT_FIELD_LENGTH = 2000; // detail / profileSummary / delta strings
export const MAX_SHORT_FIELD_LENGTH = 200; // id / name / unit / category / severity / status / title / scoreLabel
export const MAX_FINDINGS = 50;
export const MAX_LAB_VALUES = 100;
export const MAX_DELTAS = 20;

// Hard ceiling on the whole serialized `input` object, independent of the
// per-field caps above (50 findings * 2000 chars + 100 labs + 20 deltas *
// 2000 chars could otherwise add up to well over 32KB). Measured in UTF-16
// code units via `JSON.stringify(...).length`, which is close enough to
// bytes for a "reasonable size cap" gate — this isn't a byte-exact quota.
export const MAX_REPORT_INPUT_SIZE = 32 * 1024;

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

const TOP_LEVEL_KEYS = new Set(["score", "scoreLabel", "profileSummary", "findings", "labValues", "deltas"]);
const FINDING_KEYS = new Set(["id", "severity", "category", "title", "detail"]);
const LAB_VALUE_KEYS = new Set(["id", "name", "unit", "status", "value"]);

/**
 * Validates the "report" kind's `input`: `score` (int 0-100), `findings[]`,
 * `labValues[]`, `deltas[]`, plus the optional `scoreLabel`/`profileSummary`
 * strings the client already sends (see `AISummaryService.ReportInput` on
 * the client). Rejects unknown top-level or nested fields (so an
 * `attachment`/`imageData`/etc. field is rejected outright, not silently
 * dropped), oversized free-text fields, an oversized overall payload, and
 * base64-blob-shaped strings anywhere in the payload.
 */
export function validateReportSummaryRequest(body: unknown): ValidationResult<ReportSummaryRequest> {
  const errors: string[] = [];

  if (!isPlainObject(body)) {
    return { ok: false, errors: ["input: must be a JSON object"] };
  }

  if (JSON.stringify(body).length > MAX_REPORT_INPUT_SIZE) {
    return { ok: false, errors: [`input: exceeds max size ${MAX_REPORT_INPUT_SIZE} characters`] };
  }

  checkUnknownKeys(body, TOP_LEVEL_KEYS, "input", errors);

  let score: number | undefined;
  if (typeof body.score !== "number" || !Number.isInteger(body.score)) {
    errors.push("input.score: must be an integer");
  } else if (body.score < 0 || body.score > 100) {
    errors.push("input.score: must be between 0 and 100");
  } else {
    score = body.score;
  }

  const scoreLabel = checkStringField(body, "scoreLabel", "input", MAX_SHORT_FIELD_LENGTH, false, errors);
  const profileSummary = checkStringField(body, "profileSummary", "input", MAX_TEXT_FIELD_LENGTH, false, errors);

  const findings: FindingPayload[] = [];
  if (body.findings === undefined) {
    errors.push("input.findings: required");
  } else if (!Array.isArray(body.findings)) {
    errors.push("input.findings: must be an array");
  } else if (body.findings.length > MAX_FINDINGS) {
    errors.push(`input.findings: exceeds max count ${MAX_FINDINGS}`);
  } else {
    body.findings.forEach((raw, index) => {
      const path = `input.findings[${index}]`;
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
    errors.push("input.labValues: required");
  } else if (!Array.isArray(body.labValues)) {
    errors.push("input.labValues: must be an array");
  } else if (body.labValues.length > MAX_LAB_VALUES) {
    errors.push(`input.labValues: exceeds max count ${MAX_LAB_VALUES}`);
  } else {
    body.labValues.forEach((raw, index) => {
      const path = `input.labValues[${index}]`;
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
    errors.push("input.deltas: required");
  } else if (!Array.isArray(body.deltas)) {
    errors.push("input.deltas: must be an array");
  } else if (body.deltas.length > MAX_DELTAS) {
    errors.push(`input.deltas: exceeds max count ${MAX_DELTAS}`);
  } else {
    body.deltas.forEach((raw, index) => {
      const path = `input.deltas[${index}]`;
      if (typeof raw !== "string") {
        errors.push(`${path}: must be a string`);
        return;
      }
      if (raw.length > MAX_TEXT_FIELD_LENGTH) {
        errors.push(`${path}: exceeds max length ${MAX_TEXT_FIELD_LENGTH}`);
        return;
      }
      const stripped = raw.replace(/\s+/g, "");
      if (/^[A-Za-z0-9+/_-]{300,}={0,2}$/.test(stripped)) {
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
// System prompt
// ---------------------------------------------------------------------------

/**
 * Persona, hard safety rails, and the exact input JSON shape. This is the
 * versioned, server-side system prompt for the "report" kind — the client no
 * longer sends or controls it. Bump `REPORT_SUMMARY_SYSTEM_PROMPT_VERSION` on
 * any wording change so it shows up in usage logs/metrics if it's ever
 * attached there. Ported from `AISummaryService.reportSystemPrompt`
 * (Gemocode/Services/AISummaryService.swift), adapted from "respond with a
 * single JSON object" to "respond with plain prose" since this relay always
 * returns one flat `{"text", "refused"}` shape regardless of kind (see
 * src/generate.ts) rather than parsing/re-validating a nested JSON envelope
 * server-side.
 */
export const REPORT_SUMMARY_SYSTEM_PROMPT_VERSION = "2026-07-p1";

export const REPORT_SUMMARY_SYSTEM_PROMPT = `You are an educational health analyst inside Gemocode, a personal health-tracking \
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
