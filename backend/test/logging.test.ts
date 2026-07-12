import { describe, expect, it } from "vitest";
import { buildUsageLogEntry, hashUserId } from "../src/logging";

describe("hashUserId", () => {
  it("is deterministic for the same input", async () => {
    const a = await hashUserId("user-123");
    const b = await hashUserId("user-123");
    expect(a).toBe(b);
  });

  it("differs across inputs", async () => {
    const a = await hashUserId("user-123");
    const b = await hashUserId("user-456");
    expect(a).not.toBe(b);
  });

  it("never returns the raw input verbatim", async () => {
    const userId = "user-123-plainly-visible";
    const hash = await hashUserId(userId);
    expect(hash).not.toContain(userId);
    expect(hash).toMatch(/^[0-9a-f]{64}$/);
  });
});

describe("buildUsageLogEntry", () => {
  it("includes only metadata fields, never content", () => {
    const entry = buildUsageLogEntry({
      userIdHash: "abc123",
      feature: "report_summary",
      model: "claude-opus-4-8",
      tokensReserved: 1024,
      latencyMs: 250,
      status: 200,
      now: new Date("2026-07-12T12:00:00.000Z")
    });

    expect(entry).toEqual({
      userIdHash: "abc123",
      feature: "report_summary",
      model: "claude-opus-4-8",
      tokensReserved: 1024,
      latencyMs: 250,
      status: 200,
      timestamp: "2026-07-12T12:00:00.000Z"
    });

    // Structural guard: this is what makes "never log content" checkable —
    // there is no key on the entry that could carry a prompt or response.
    const allowedKeys = ["userIdHash", "feature", "model", "tokensReserved", "latencyMs", "status", "timestamp"];
    expect(Object.keys(entry).sort()).toEqual(allowedKeys.sort());
  });
});
