import { describe, expect, it } from "vitest";
import {
  MAX_DELTAS,
  MAX_FINDINGS,
  MAX_REPORT_INPUT_SIZE,
  MAX_TEXT_FIELD_LENGTH,
  REPORT_SUMMARY_SYSTEM_PROMPT,
  validateReportSummaryRequest
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

  it("rejects a base64-blob-shaped delta string", () => {
    const payload = validPayload() as Record<string, unknown>;
    payload.deltas = ["QmFzZTY0".repeat(60)]; // 480 chars of unbroken base64 alphabet
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

  it("rejects an overall payload above the total size cap even when every individual field is legal", () => {
    // 50 findings * ~1950-char details ≈ 100KB serialized — every field is
    // individually under its cap, so only the whole-payload gate catches it.
    const findings = Array.from({ length: MAX_FINDINGS }, (_, i) => ({
      id: `f${i}`,
      severity: "info",
      category: "labs",
      title: "Finding",
      detail: "word ".repeat(390) // ordinary prose, not base64-shaped
    }));
    const payload = { score: 50, findings, labValues: [], deltas: [] };
    expect(JSON.stringify(payload).length).toBeGreaterThan(MAX_REPORT_INPUT_SIZE);
    const result = validateReportSummaryRequest(payload);
    expect(result.ok).toBe(false);
    expect(result.errors.some((e) => e.includes("exceeds max size"))).toBe(true);
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

describe("REPORT_SUMMARY_SYSTEM_PROMPT", () => {
  it("keeps the educational-not-diagnostic and never-invent-a-number rails from the client prompt", () => {
    expect(REPORT_SUMMARY_SYSTEM_PROMPT).toContain("Never diagnose");
    expect(REPORT_SUMMARY_SYSTEM_PROMPT).toContain("Never prescribe");
    expect(REPORT_SUMMARY_SYSTEM_PROMPT).toContain("Never invent a number");
    expect(REPORT_SUMMARY_SYSTEM_PROMPT).toContain("educational only");
    expect(REPORT_SUMMARY_SYSTEM_PROMPT).toContain("follow-up questions");
  });
});
