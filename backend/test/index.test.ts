// Route-level tests for the two wire-contract endpoints, exercising the real
// worker `fetch` handler end-to-end with an in-memory KV and a stubbed
// global `fetch` for the Anthropic upstream — no network, no Wrangler
// runtime. Covers: auth issuance shape, per-kind generate happy paths,
// refusal mapping, the premium-enforcement matrix (flag on/off × premium
// claim × kind, including the one-lifetime-free-report rule), quota 429s,
// input-validation rejections, and the metadata-only logging guarantee.

import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import worker from "../src/index";
import type { Env } from "../src/env";
import type { KVLike } from "../src/quota";
import { issueAnonymousToken, verifyAnonymousToken } from "../src/auth";

const JWT_SECRET = "test-only-secret-value-not-used-anywhere-real";
const DEVICE_ID = "6f1e1c1a-2b3c-4d5e-8f90-112233445566";

class MemoryKV implements KVLike {
  readonly store = new Map<string, string>();

  async get(key: string): Promise<string | null> {
    return this.store.has(key) ? (this.store.get(key) as string) : null;
  }

  async put(key: string, value: string): Promise<void> {
    this.store.set(key, value);
  }
}

function makeEnv(overrides: Partial<Env> = {}): Env {
  return {
    QUOTA_KV: new MemoryKV(),
    PER_USER_DAILY_TOKENS: 60000,
    GLOBAL_DAILY_TOKENS: 5000000,
    MODEL_REPORT: "model-report",
    MODEL_CHAT: "model-chat",
    MODEL_EXTRACT: "model-extract",
    ENFORCE_PREMIUM: "false",
    ANTHROPIC_API_KEY: "test-upstream-key",
    JWT_SECRET,
    ...overrides
  };
}

function call(env: Env, path: string, init?: RequestInit): Promise<Response> {
  return worker.fetch(new Request(`https://relay.example${path}`, init), env, {} as ExecutionContext);
}

function postJson(env: Env, path: string, body: unknown, token?: string): Promise<Response> {
  return call(env, path, {
    method: "POST",
    headers: {
      "content-type": "application/json",
      ...(token ? { authorization: `Bearer ${token}` } : {})
    },
    body: JSON.stringify(body)
  });
}

async function mintToken(premium: boolean, deviceId = DEVICE_ID): Promise<string> {
  const issued = await issueAnonymousToken({ secret: JWT_SECRET, deviceId, premium });
  return issued.token;
}

function anthropicSuccess(text: string): Response {
  return new Response(JSON.stringify({ stop_reason: "end_turn", content: [{ type: "text", text }] }), { status: 200 });
}

function anthropicRefusal(): Response {
  return new Response(JSON.stringify({ stop_reason: "refusal", content: [] }), { status: 200 });
}

function stubUpstream(respond: () => Response): ReturnType<typeof vi.fn> {
  const stub = vi.fn(async (_input: unknown, _init?: unknown) => respond());
  vi.stubGlobal("fetch", stub);
  return stub;
}

function reportBody(): unknown {
  return {
    kind: "report",
    input: {
      score: 78,
      scoreLabel: "Good",
      profileSummary: null,
      findings: [
        { id: "f0", severity: "attention", category: "labs", title: "LDL Elevated", detail: "LDL 142 mg/dL, above range." }
      ],
      labValues: [{ id: "lv0", name: "LDL Cholesterol", value: 142, unit: "mg/dL", status: "high" }],
      deltas: []
    }
  };
}

function chatBody(): unknown {
  return {
    kind: "chat",
    input: {
      context: "Health score: 78/100 (Good)",
      messages: [{ role: "user", text: "What does my score mean?" }]
    }
  };
}

function extractBody(): unknown {
  return {
    kind: "extract",
    input: { text: "bp 120 over 80 this morning", today: "2026-07-13" }
  };
}

async function errorCode(response: Response): Promise<string> {
  const body = (await response.json()) as { error?: { code?: string; message?: string } };
  return body.error?.code ?? "";
}

beforeEach(() => {
  vi.spyOn(console, "log").mockImplementation(() => {});
});

afterEach(() => {
  vi.unstubAllGlobals();
  vi.restoreAllMocks();
});

// ---------------------------------------------------------------------------
// POST /v1/auth/anonymous
// ---------------------------------------------------------------------------

describe("POST /v1/auth/anonymous", () => {
  it("issues a 24h token for a valid deviceID, with premium=false", async () => {
    const env = makeEnv();
    const response = await postJson(env, "/v1/auth/anonymous", { deviceID: DEVICE_ID });
    expect(response.status).toBe(200);

    const body = (await response.json()) as { token: string; expiresInSeconds: number };
    expect(Object.keys(body).sort()).toEqual(["expiresInSeconds", "token"]);
    expect(body.expiresInSeconds).toBe(86400);

    const claims = await verifyAnonymousToken(JWT_SECRET, body.token);
    expect(claims).toEqual({ sub: DEVICE_ID, premium: false });
  });

  it("still issues premium=false when an appTransaction is supplied (verification unimplemented — fails closed)", async () => {
    const env = makeEnv();
    const response = await postJson(env, "/v1/auth/anonymous", {
      deviceID: DEVICE_ID,
      appTransaction: "ZmFrZS1qd3MtcGF5bG9hZA"
    });
    expect(response.status).toBe(200);
    const body = (await response.json()) as { token: string };
    const claims = await verifyAnonymousToken(JWT_SECRET, body.token);
    expect(claims.premium).toBe(false);
  });

  it("returns 400 bad_request on a missing deviceID", async () => {
    const response = await postJson(makeEnv(), "/v1/auth/anonymous", {});
    expect(response.status).toBe(400);
    expect(await errorCode(response)).toBe("bad_request");
  });

  it("returns 400 bad_request on a malformed (non-UUID) deviceID", async () => {
    const response = await postJson(makeEnv(), "/v1/auth/anonymous", { deviceID: "not-a-uuid" });
    expect(response.status).toBe(400);
    expect(await errorCode(response)).toBe("bad_request");
  });

  it("returns 400 bad_request on a non-JSON body", async () => {
    const response = await call(makeEnv(), "/v1/auth/anonymous", { method: "POST", body: "deviceID=abc" });
    expect(response.status).toBe(400);
    expect(await errorCode(response)).toBe("bad_request");
  });

  it("returns 400 bad_request on unknown fields", async () => {
    const response = await postJson(makeEnv(), "/v1/auth/anonymous", { deviceID: DEVICE_ID, isPremium: true });
    expect(response.status).toBe(400);
    expect(await errorCode(response)).toBe("bad_request");
  });
});

// ---------------------------------------------------------------------------
// POST /v1/ai/generate — auth
// ---------------------------------------------------------------------------

describe("POST /v1/ai/generate — auth", () => {
  it("returns 401 unauthorized with no bearer token", async () => {
    const upstream = stubUpstream(() => anthropicSuccess("x"));
    const response = await postJson(makeEnv(), "/v1/ai/generate", chatBody());
    expect(response.status).toBe(401);
    expect(await errorCode(response)).toBe("unauthorized");
    expect(upstream).not.toHaveBeenCalled();
  });

  it("returns 401 unauthorized for a garbage token", async () => {
    const response = await postJson(makeEnv(), "/v1/ai/generate", chatBody(), "not-a-jwt");
    expect(response.status).toBe(401);
    expect(await errorCode(response)).toBe("unauthorized");
  });

  it("returns 401 unauthorized for a token signed with a different secret", async () => {
    const foreign = await issueAnonymousToken({ secret: "some-other-secret", deviceId: DEVICE_ID, premium: true });
    const response = await postJson(makeEnv(), "/v1/ai/generate", chatBody(), foreign.token);
    expect(response.status).toBe(401);
  });
});

// ---------------------------------------------------------------------------
// POST /v1/ai/generate — happy paths per kind
// ---------------------------------------------------------------------------

describe("POST /v1/ai/generate — happy paths", () => {
  it("report: 200 with text, MODEL_REPORT, max_tokens 1500, report prompt", async () => {
    const upstream = stubUpstream(() => anthropicSuccess("Your review shows a score of 78."));
    const env = makeEnv();
    const token = await mintToken(false);

    const response = await postJson(env, "/v1/ai/generate", reportBody(), token);
    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({ text: "Your review shows a score of 78.", refused: false });

    const sent = JSON.parse(String((upstream.mock.calls[0] as [unknown, RequestInit])[1].body)) as Record<string, unknown>;
    expect(sent.model).toBe("model-report");
    expect(sent.max_tokens).toBe(1500);
    expect(String(sent.system)).toContain("educational health analyst");
    expect("stream" in sent).toBe(false);
  });

  it("chat: 200 with text, MODEL_CHAT, max_tokens 700, context in system prompt", async () => {
    const upstream = stubUpstream(() => anthropicSuccess("Your score of 78 means..."));
    const env = makeEnv();
    const token = await mintToken(false);

    const response = await postJson(env, "/v1/ai/generate", chatBody(), token);
    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({ text: "Your score of 78 means...", refused: false });

    const sent = JSON.parse(String((upstream.mock.calls[0] as [unknown, RequestInit])[1].body)) as Record<string, unknown>;
    expect(sent.model).toBe("model-chat");
    expect(sent.max_tokens).toBe(700);
    expect(String(sent.system)).toContain("Health score: 78/100 (Good)");
    expect(sent.messages).toEqual([{ role: "user", content: "What does my score mean?" }]);
  });

  it("extract: 200 with text, MODEL_EXTRACT, max_tokens 800, temperature 0", async () => {
    const upstream = stubUpstream(() => anthropicSuccess('{"kind":"vital","type":"bloodPressure","value":120,"secondary":80}'));
    const env = makeEnv();
    const token = await mintToken(false);

    const response = await postJson(env, "/v1/ai/generate", extractBody(), token);
    expect(response.status).toBe(200);
    const body = (await response.json()) as { text: string; refused: boolean };
    expect(body.refused).toBe(false);
    expect(body.text).toContain('"bloodPressure"');

    const sent = JSON.parse(String((upstream.mock.calls[0] as [unknown, RequestInit])[1].body)) as Record<string, unknown>;
    expect(sent.model).toBe("model-extract");
    expect(sent.max_tokens).toBe(800);
    expect(sent.temperature).toBe(0);
    expect(String(sent.system)).toContain("2026-07-13");
  });

  it("maps an upstream refusal to 200 {text: '', refused: true}", async () => {
    stubUpstream(() => anthropicRefusal());
    const env = makeEnv();
    const token = await mintToken(false);

    const response = await postJson(env, "/v1/ai/generate", chatBody(), token);
    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({ text: "", refused: true });
  });

  it("maps an upstream failure to 502 upstream_error", async () => {
    stubUpstream(() => new Response(JSON.stringify({ error: { message: "overloaded" } }), { status: 529 }));
    const env = makeEnv();
    const token = await mintToken(false);

    const response = await postJson(env, "/v1/ai/generate", chatBody(), token);
    expect(response.status).toBe(502);
    expect(await errorCode(response)).toBe("upstream_error");
  });
});

// ---------------------------------------------------------------------------
// POST /v1/ai/generate — input validation
// ---------------------------------------------------------------------------

describe("POST /v1/ai/generate — validation rejections", () => {
  it("rejects an unknown kind with 400 bad_request, without calling upstream", async () => {
    const upstream = stubUpstream(() => anthropicSuccess("x"));
    const token = await mintToken(false);
    const response = await postJson(makeEnv(), "/v1/ai/generate", { kind: "diagnose", input: {} }, token);
    expect(response.status).toBe(400);
    expect(await errorCode(response)).toBe("bad_request");
    expect(upstream).not.toHaveBeenCalled();
  });

  it("rejects an oversize chat context with 400", async () => {
    const token = await mintToken(false);
    const body = { kind: "chat", input: { context: "x".repeat(8001), messages: [{ role: "user", text: "hi" }] } };
    const response = await postJson(makeEnv(), "/v1/ai/generate", body, token);
    expect(response.status).toBe(400);
  });

  it("rejects more than 12 chat messages with 400", async () => {
    const token = await mintToken(false);
    const messages = Array.from({ length: 13 }, (_, i) => ({ role: i % 2 === 0 ? "user" : "assistant", text: `t${i}` }));
    const response = await postJson(makeEnv(), "/v1/ai/generate", { kind: "chat", input: { context: "c", messages } }, token);
    expect(response.status).toBe(400);
  });

  it("rejects a base64-blob-shaped report field with 400", async () => {
    const token = await mintToken(false);
    const body = reportBody() as { input: { findings: Array<Record<string, unknown>> } };
    body.input.findings[0]!.detail = "A".repeat(400);
    const response = await postJson(makeEnv(), "/v1/ai/generate", body, token);
    expect(response.status).toBe(400);
    expect(await errorCode(response)).toBe("bad_request");
  });

  it("rejects a non-JSON body with 400", async () => {
    const token = await mintToken(false);
    const response = await call(makeEnv(), "/v1/ai/generate", {
      method: "POST",
      headers: { authorization: `Bearer ${token}` },
      body: "kind=report"
    });
    expect(response.status).toBe(400);
  });
});

// ---------------------------------------------------------------------------
// POST /v1/ai/generate — premium enforcement matrix
// ---------------------------------------------------------------------------

describe("POST /v1/ai/generate — premium enforcement", () => {
  it("ENFORCE_PREMIUM=false: non-premium tokens can use every kind, repeatedly", async () => {
    stubUpstream(() => anthropicSuccess("ok"));
    const env = makeEnv({ ENFORCE_PREMIUM: "false" });
    const token = await mintToken(false);

    for (const body of [reportBody(), reportBody(), chatBody(), extractBody()]) {
      const response = await postJson(env, "/v1/ai/generate", body, token);
      expect(response.status).toBe(200);
    }
  });

  it("ENFORCE_PREMIUM=true: premium tokens can use every kind, repeatedly (no free-report accounting)", async () => {
    stubUpstream(() => anthropicSuccess("ok"));
    const kv = new MemoryKV();
    const env = makeEnv({ ENFORCE_PREMIUM: "true", QUOTA_KV: kv });
    const token = await mintToken(true);

    for (const body of [reportBody(), reportBody(), chatBody(), extractBody()]) {
      const response = await postJson(env, "/v1/ai/generate", body, token);
      expect(response.status).toBe(200);
    }
    expect(kv.store.has(`free_report:${DEVICE_ID}`)).toBe(false);
  });

  it("ENFORCE_PREMIUM=true: non-premium chat and extract get 402 premium_required, upstream never called", async () => {
    const upstream = stubUpstream(() => anthropicSuccess("ok"));
    const env = makeEnv({ ENFORCE_PREMIUM: "true" });
    const token = await mintToken(false);

    for (const body of [chatBody(), extractBody()]) {
      const response = await postJson(env, "/v1/ai/generate", body, token);
      expect(response.status).toBe(402);
      expect(await errorCode(response)).toBe("premium_required");
    }
    expect(upstream).not.toHaveBeenCalled();
  });

  it("ENFORCE_PREMIUM=true: a non-premium device gets exactly one free report — first 200, second 402", async () => {
    stubUpstream(() => anthropicSuccess("your free report"));
    const env = makeEnv({ ENFORCE_PREMIUM: "true" });
    const token = await mintToken(false);

    const first = await postJson(env, "/v1/ai/generate", reportBody(), token);
    expect(first.status).toBe(200);
    expect(await first.json()).toEqual({ text: "your free report", refused: false });

    const second = await postJson(env, "/v1/ai/generate", reportBody(), token);
    expect(second.status).toBe(402);
    expect(await errorCode(second)).toBe("premium_required");
  });

  it("the free report is not consumed by an upstream error", async () => {
    stubUpstream(() => new Response("boom", { status: 500 }));
    const env = makeEnv({ ENFORCE_PREMIUM: "true" });
    const token = await mintToken(false);

    const failed = await postJson(env, "/v1/ai/generate", reportBody(), token);
    expect(failed.status).toBe(502);

    stubUpstream(() => anthropicSuccess("retry succeeded"));
    const retry = await postJson(env, "/v1/ai/generate", reportBody(), token);
    expect(retry.status).toBe(200);
    expect(await retry.json()).toEqual({ text: "retry succeeded", refused: false });
  });

  it("the free report is not consumed by a refusal", async () => {
    stubUpstream(() => anthropicRefusal());
    const env = makeEnv({ ENFORCE_PREMIUM: "true" });
    const token = await mintToken(false);

    const refused = await postJson(env, "/v1/ai/generate", reportBody(), token);
    expect(refused.status).toBe(200);
    expect(await refused.json()).toEqual({ text: "", refused: true });

    stubUpstream(() => anthropicSuccess("second try"));
    const retry = await postJson(env, "/v1/ai/generate", reportBody(), token);
    expect(retry.status).toBe(200);
    expect(await retry.json()).toEqual({ text: "second try", refused: false });
  });

  it("free reports are tracked per device, not globally", async () => {
    stubUpstream(() => anthropicSuccess("ok"));
    const env = makeEnv({ ENFORCE_PREMIUM: "true" });
    const tokenA = await mintToken(false, "aaaaaaaa-1111-4222-8333-444444444444");
    const tokenB = await mintToken(false, "bbbbbbbb-1111-4222-8333-444444444444");

    expect((await postJson(env, "/v1/ai/generate", reportBody(), tokenA)).status).toBe(200);
    expect((await postJson(env, "/v1/ai/generate", reportBody(), tokenB)).status).toBe(200);
    expect((await postJson(env, "/v1/ai/generate", reportBody(), tokenA)).status).toBe(402);
  });
});

// ---------------------------------------------------------------------------
// POST /v1/ai/generate — quota
// ---------------------------------------------------------------------------

describe("POST /v1/ai/generate — quota", () => {
  it("books usage and returns 429 quota_exceeded once the per-user daily cap is exhausted", async () => {
    stubUpstream(() => anthropicSuccess("ok"));
    // 1500 = exactly one report's reservation, so the second report must trip the cap.
    const env = makeEnv({ PER_USER_DAILY_TOKENS: 1500 });
    const token = await mintToken(false);

    const first = await postJson(env, "/v1/ai/generate", reportBody(), token);
    expect(first.status).toBe(200);

    const second = await postJson(env, "/v1/ai/generate", reportBody(), token);
    expect(second.status).toBe(429);
    expect(await errorCode(second)).toBe("quota_exceeded");
  });

  it("returns 429 quota_exceeded when the global daily cap is exhausted, upstream never called", async () => {
    const upstream = stubUpstream(() => anthropicSuccess("ok"));
    const env = makeEnv({ GLOBAL_DAILY_TOKENS: 100 });
    const token = await mintToken(false);

    const response = await postJson(env, "/v1/ai/generate", chatBody(), token);
    expect(response.status).toBe(429);
    expect(await errorCode(response)).toBe("quota_exceeded");
    expect(upstream).not.toHaveBeenCalled();
  });

  it("per-user caps are independent across devices", async () => {
    stubUpstream(() => anthropicSuccess("ok"));
    const env = makeEnv({ PER_USER_DAILY_TOKENS: 700 });
    const tokenA = await mintToken(false, "aaaaaaaa-1111-4222-8333-444444444444");
    const tokenB = await mintToken(false, "bbbbbbbb-1111-4222-8333-444444444444");

    expect((await postJson(env, "/v1/ai/generate", chatBody(), tokenA)).status).toBe(200);
    expect((await postJson(env, "/v1/ai/generate", chatBody(), tokenA)).status).toBe(429);
    expect((await postJson(env, "/v1/ai/generate", chatBody(), tokenB)).status).toBe(200);
  });
});

// ---------------------------------------------------------------------------
// Logging: metadata only, never content
// ---------------------------------------------------------------------------

describe("logging", () => {
  it("logs metadata only — no health content, prompts, or completions", async () => {
    const logSpy = vi.spyOn(console, "log").mockImplementation(() => {});
    stubUpstream(() => anthropicSuccess("Your LDL of 142 mg/dL is discussed with your doctor."));
    const env = makeEnv();
    const token = await mintToken(false);

    const response = await postJson(env, "/v1/ai/generate", reportBody(), token);
    expect(response.status).toBe(200);

    expect(logSpy).toHaveBeenCalled();
    const allLogged = logSpy.mock.calls.map((args) => args.map(String).join(" ")).join("\n");

    // Nothing from the request payload... (word-based checks — a bare number
    // like "142" could legitimately appear inside a hex hash or timestamp)
    expect(allLogged).not.toContain("LDL");
    expect(allLogged).not.toContain("Cholesterol");
    expect(allLogged).not.toContain("142 mg/dL");
    // ...nothing from the model's output...
    expect(allLogged).not.toContain("discussed with your doctor");
    // ...no prompt text, and no secrets.
    expect(allLogged).not.toContain("educational health analyst");
    expect(allLogged).not.toContain("test-upstream-key");
    // The raw device id never appears either — only its hash.
    expect(allLogged).not.toContain(DEVICE_ID);

    // And the structured entry carries exactly the metadata keys, no more.
    const entry = JSON.parse(String(logSpy.mock.calls[0]![0])) as Record<string, unknown>;
    expect(Object.keys(entry).sort()).toEqual(
      ["feature", "latencyMs", "model", "status", "timestamp", "tokensReserved", "userIdHash"].sort()
    );
    expect(entry.feature).toBe("report");
    expect(entry.model).toBe("model-report");
    expect(entry.tokensReserved).toBe(1500);
  });
});
