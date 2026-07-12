import { describe, expect, it } from "vitest";
import {
  MAX_DELTAS,
  MAX_FINDINGS,
  MAX_TEXT_FIELD_LENGTH,
  REPORT_SUMMARY_MAX_TOKENS,
  REPORT_SUMMARY_SYSTEM_PROMPT,
  buildAnthropicRequest,
  formatClientSSEEvent,
  mapAnthropicHttpError,
  mapAnthropicSSEEvent,
  validateReportSummaryRequest,
  type ReportSummaryRequest
} from "../src/relay";

function validPayload(): unknown {
  return {
    score: 78,
    scoreLabel: "Good",
    profileSummary: "42-year-old, no known allergies.",
    findings: [
      {
        id: "f0",
        severity: "attention",
        category: "labs",
        title: "LDL Cholesterol Elevated",
        detail: "LDL 142 mg/dL, above the 130 mg/dL reference high."
      }
    ],
    labValues: [{ id: "lv0", name: "LDL Cholesterol", value: 142, unit: "mg/dL", status: "high" }],
    deltas: ["Score improved by 4 points since last review."]
  };
}

describe("validateReportSummaryRequest — valid input", () => {
  it("accepts a well-formed payload and echoes it back unchanged", () => {
    const result = validateReportSummaryRequest(validPayload());
    expect(result.ok).toBe(true);
    expect(result.errors).toEqual([]);
    expect(result.value).toEqual(validPayload());
  });

  it("accepts the minimal required shape with empty arrays and no optional fields", () => {
    const result = validateReportSummaryRequest({ score: 0, findings: [], labValues: [], deltas: [] });
    expect(result.ok).toBe(true);
    expect(result.value).toEqual({
      score: 0,
      scoreLabel: undefined,
      profileSummary: null,
      findings: [],
      labValues: [],
      deltas: []
    });
  });

  it("accepts score at both boundary values 0 and 100", () => {
    expect(validateReportSummaryRequest({ score: 0, findings: [], labValues: [], deltas: [] }).ok).toBe(true);
    expect(validateReportSummaryRequest({ score: 100, findings: [], labValues: [], deltas: [] }).ok).toBe(true);
  });
});

describe("validateReportSummaryRequest — score", () => {
  it("rejects a missing score", () => {
    const payload = validPayload() as Record<string, unknown>;
    delete payload.score;
    const result = validateReportSummaryRequest(payload);
    expect(result.ok).toBe(false);
    expect(result.errors.some((e) => e.includes("score"))).toBe(true);
  });

  it("rejects a non-integer score", () => {
    const result = validateReportSummaryRequest({ ...(validPayload() as object), score: 55.5 });
    expect(result.ok).toBe(false);
  });

  it("rejects a score above 100", () => {
    const result = validateReportSummaryRequest({ ...(validPayload() as object), score: 150 });
    expect(result.ok).toBe(false);
  });

  it("rejects a negative score", () => {
    const result = validateReportSummaryRequest({ ...(validPayload() as object), score: -1 });
    expect(result.ok).toBe(false);
  });
});

describe("validateReportSummaryRequest — rejects oversized text and unknown/attachment-shaped fields", () => {
  it("rejects a finding.detail longer than the text field cap", () => {
    const payload = validPayload() as { findings: Array<Record<string, unknown>> };
    payload.findings[0]!.detail = "x".repeat(MAX_TEXT_FIELD_LENGTH + 1);
    const result = validateReportSummaryRequest(payload);
    expect(result.ok).toBe(false);
    expect(result.errors.some((e) => e.includes("exceeds max length"))).toBe(true);
  });

  it("rejects an unknown top-level field (e.g. an attachment payload)", () => {
    const payload = { ...(validPayload() as object), attachmentBase64: "irrelevant" };
    const result = validateReportSummaryRequest(payload);
    expect(result.ok).toBe(false);
    expect(result.errors.some((e) => e.includes("attachmentBase64"))).toBe(true);
  });

  it("rejects an unknown nested field on a finding", () => {
    const payload = validPayload() as { findings: Array<Record<string, unknown>> };
    payload.findings[0]!.rawOcrText = "some free text that should not be here";
    const result = validateReportSummaryRequest(payload);
    expect(result.ok).toBe(false);
    expect(result.errors.some((e) => e.includes("rawOcrText"))).toBe(true);
  });

  it("rejects a base64-blob-shaped string even inside an otherwise-allowed text field", () => {
    const payload = validPayload() as { findings: Array<Record<string, unknown>> };
    payload.findings[0]!.detail = "A".repeat(400); // long, base64-alphabet-only run
    const result = validateReportSummaryRequest(payload);
    expect(result.ok).toBe(false);
    expect(result.errors.some((e) => e.includes("binary/base64"))).toBe(true);
  });

  it("rejects a findings array over the max count", () => {
    const many = Array.from({ length: MAX_FINDINGS + 1 }, (_, i) => ({
      id: `f${i}`,
      severity: "info",
      category: "labs",
      title: "x",
      detail: "x"
    }));
    const result = validateReportSummaryRequest({ score: 50, findings: many, labValues: [], deltas: [] });
    expect(result.ok).toBe(false);
  });

  it("rejects a deltas array over the max count", () => {
    const many = Array.from({ length: MAX_DELTAS + 1 }, (_, i) => `delta ${i}`);
    const result = validateReportSummaryRequest({ score: 50, findings: [], labValues: [], deltas: many });
    expect(result.ok).toBe(false);
  });

  it("rejects a non-object body", () => {
    expect(validateReportSummaryRequest("not an object").ok).toBe(false);
    expect(validateReportSummaryRequest(null).ok).toBe(false);
    expect(validateReportSummaryRequest([1, 2, 3]).ok).toBe(false);
  });

  it("rejects a labValue with a non-numeric value field", () => {
    const payload = { score: 50, findings: [], deltas: [], labValues: [{ id: "lv0", name: "x", unit: "x", status: "high", value: "142" }] };
    const result = validateReportSummaryRequest(payload);
    expect(result.ok).toBe(false);
  });
});

describe("buildAnthropicRequest", () => {
  it("builds a streaming request using the given model and the versioned system prompt", () => {
    const input: ReportSummaryRequest = {
      score: 80,
      scoreLabel: "Good",
      profileSummary: null,
      findings: [],
      labValues: [],
      deltas: []
    };
    const request = buildAnthropicRequest(input, "claude-opus-4-8");

    expect(request.model).toBe("claude-opus-4-8");
    expect(request.stream).toBe(true);
    expect(request.max_tokens).toBe(REPORT_SUMMARY_MAX_TOKENS);
    expect(request.system).toBe(REPORT_SUMMARY_SYSTEM_PROMPT);
    expect(request.messages).toHaveLength(1);
    expect(request.messages[0]).toEqual({ role: "user", content: JSON.stringify(input) });
  });

  it("never embeds request content in the system prompt (it stays a fixed constant)", () => {
    const inputA = buildAnthropicRequest({ score: 1, findings: [], labValues: [], deltas: [] }, "m");
    const inputB = buildAnthropicRequest({ score: 99, findings: [], labValues: [], deltas: [] }, "m");
    expect(inputA.system).toBe(inputB.system);
  });
});

describe("mapAnthropicSSEEvent — refusal and delta mapping", () => {
  it("maps a text delta to a client delta event", () => {
    const event = mapAnthropicSSEEvent({ type: "content_block_delta", delta: { type: "text_delta", text: "Hello" } });
    expect(event).toEqual({ type: "delta", text: "Hello" });
  });

  it("ignores non-text content block deltas", () => {
    const event = mapAnthropicSSEEvent({ type: "content_block_delta", delta: { type: "input_json_delta" } });
    expect(event).toBeNull();
  });

  it("maps a refusal stop_reason to a refused event", () => {
    const event = mapAnthropicSSEEvent({ type: "message_delta", delta: { stop_reason: "refusal" } });
    expect(event).toEqual({ type: "refused" });
  });

  it("ignores a normal end_turn stop_reason", () => {
    const event = mapAnthropicSSEEvent({ type: "message_delta", delta: { stop_reason: "end_turn" } });
    expect(event).toBeNull();
  });

  it("maps message_stop to a done event", () => {
    expect(mapAnthropicSSEEvent({ type: "message_stop" })).toEqual({ type: "done" });
  });

  it("maps an error event to a typed error event", () => {
    const event = mapAnthropicSSEEvent({ type: "error", error: { type: "overloaded_error", message: "Overloaded" } });
    expect(event).toEqual({ type: "error", code: "overloaded_error", message: "Overloaded" });
  });

  it("ignores unrecognized event types (e.g. content_block_start)", () => {
    expect(mapAnthropicSSEEvent({ type: "content_block_start" })).toBeNull();
    expect(mapAnthropicSSEEvent({ type: "ping" })).toBeNull();
  });
});

describe("mapAnthropicHttpError", () => {
  it("maps 429 to rate_limited", () => {
    expect(mapAnthropicHttpError(429, null).code).toBe("rate_limited");
  });

  it("maps a 5xx status to upstream_unavailable", () => {
    expect(mapAnthropicHttpError(529, null).code).toBe("upstream_unavailable");
  });

  it("maps other 4xx statuses to upstream_error", () => {
    expect(mapAnthropicHttpError(400, null).code).toBe("upstream_error");
  });

  it("surfaces the upstream error message when present", () => {
    const result = mapAnthropicHttpError(400, { error: { message: "invalid model" } });
    expect(result.message).toBe("invalid model");
  });

  it("falls back to a generic message when the body is unparsable", () => {
    const result = mapAnthropicHttpError(500, null);
    expect(result.message).toBeTruthy();
  });
});

describe("formatClientSSEEvent", () => {
  it("frames an event as a single SSE data line terminated by a blank line", () => {
    const formatted = formatClientSSEEvent({ type: "delta", text: "hi" });
    expect(formatted).toBe('data: {"type":"delta","text":"hi"}\n\n');
  });
});
