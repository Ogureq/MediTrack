// Entry point: wires the six P1 routes from docs/ROADMAP.md Part 4 §1.3
// onto the hand-rolled Router, gates the AI relay behind JWT + quota, and
// applies CORS. Kept intentionally thin — all the interesting logic lives
// in auth.ts / quota.ts / relay.ts and is unit-tested there; this file is
// mostly plumbing.

import { Router, type RouteContext } from "./router";
import type { Env } from "./env";
import {
  issueTokenPair,
  verifyAccessToken,
  rotateFromRefreshToken,
  verifyAppAttestPlaceholder,
  deriveUserId,
  AuthError
} from "./auth";
import { checkQuota, recordUsage, getUsageStatus, type QuotaLimits } from "./quota";
import { validateReportSummaryRequest, relayReportSummary, REPORT_SUMMARY_MAX_TOKENS } from "./relay";
import { hashUserId, buildUsageLogEntry } from "./logging";

// CORS is permissive here because this endpoint is called by a native iOS
// client (which does not send an `Origin` header at all) rather than a
// browser page — the wildcard exists mainly so the endpoints are also
// reachable from browser-based tooling (Wrangler's dev playground, manual
// testing) during development. Revisit if a web client is ever added.
const CORS_HEADERS: Record<string, string> = {
  "access-control-allow-origin": "*",
  "access-control-allow-methods": "GET,POST,OPTIONS",
  "access-control-allow-headers": "authorization,content-type",
  "access-control-max-age": "86400"
};

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json" }
  });
}

function withCors(response: Response): Response {
  const headers = new Headers(response.headers);
  for (const [key, value] of Object.entries(CORS_HEADERS)) {
    headers.set(key, value);
  }
  return new Response(response.body, { status: response.status, statusText: response.statusText, headers });
}

function quotaLimits(env: Env): QuotaLimits {
  return { perUserDailyTokens: env.PER_USER_DAILY_TOKENS, globalDailyTokens: env.GLOBAL_DAILY_TOKENS };
}

function bearerToken(request: Request): string | null {
  const header = request.headers.get("authorization");
  if (!header?.startsWith("Bearer ")) return null;
  const token = header.slice("Bearer ".length).trim();
  return token.length > 0 ? token : null;
}

async function readJsonBody(request: Request): Promise<Record<string, unknown> | null> {
  try {
    const parsed: unknown = await request.json();
    return typeof parsed === "object" && parsed !== null && !Array.isArray(parsed)
      ? (parsed as Record<string, unknown>)
      : null;
  } catch {
    return null;
  }
}

function authErrorResponse(err: unknown): Response {
  if (err instanceof AuthError) return json({ error: err.code }, 401);
  return json({ error: "auth_failed" }, 401);
}

const router = new Router<Env>();

router.get("/health", () => json({ status: "ok" }));

// POST /v1/auth/anonymous — exchange an App Attest assertion for an
// anonymous JWT. See auth.ts's `verifyAppAttestPlaceholder` doc comment:
// the App Attest check here is a P1 placeholder, not production-ready.
router.post("/v1/auth/anonymous", async ({ request, env }: RouteContext<Env>) => {
  const body = await readJsonBody(request);
  if (!body) return json({ error: "invalid_json" }, 400);

  const deviceId = body.deviceId;
  if (typeof deviceId !== "string" || deviceId.trim().length === 0) {
    return json({ error: "device_id_required" }, 400);
  }

  const assertion = typeof body.appAttestAssertion === "string" ? body.appAttestAssertion : null;
  if (!verifyAppAttestPlaceholder(assertion)) {
    return json({ error: "app_attest_required" }, 401);
  }

  const userId = await deriveUserId(deviceId);
  const pair = await issueTokenPair({ secret: env.JWT_SECRET, userId, deviceId });
  return json(pair, 201);
});

// POST /v1/auth/refresh — rotate an expiring JWT using the refresh token.
router.post("/v1/auth/refresh", async ({ request, env }: RouteContext<Env>) => {
  const body = await readJsonBody(request);
  const refreshToken = body && typeof body.refreshToken === "string" ? body.refreshToken : null;
  if (!refreshToken) return json({ error: "refresh_token_required" }, 400);

  try {
    const pair = await rotateFromRefreshToken({ secret: env.JWT_SECRET, refreshToken });
    return json(pair);
  } catch (err) {
    return authErrorResponse(err);
  }
});

// GET /v1/usage/me — current period usage + remaining quota.
router.get("/v1/usage/me", async ({ request, env }: RouteContext<Env>) => {
  const token = bearerToken(request);
  if (!token) return json({ error: "auth_required" }, 401);

  let claims;
  try {
    claims = await verifyAccessToken(env.JWT_SECRET, token);
  } catch (err) {
    return authErrorResponse(err);
  }

  const status = await getUsageStatus(env.QUOTA_KV, claims.sub, quotaLimits(env), new Date());
  return json({ tier: claims.tier, ...status });
});

// POST /v1/ai/report-summary — JWT + quota gated streaming relay.
router.post("/v1/ai/report-summary", async ({ request, env }: RouteContext<Env>) => {
  const token = bearerToken(request);
  if (!token) return json({ error: "auth_required" }, 401);

  let claims;
  try {
    claims = await verifyAccessToken(env.JWT_SECRET, token);
  } catch (err) {
    return authErrorResponse(err);
  }

  const rawBody = await readJsonBody(request);
  if (!rawBody) return json({ error: "invalid_json" }, 400);

  const validation = validateReportSummaryRequest(rawBody);
  if (!validation.ok || !validation.value) {
    return json({ error: "invalid_request", details: validation.errors }, 422);
  }

  const now = new Date();
  // Reserve the request's full max_tokens budget against the ledger
  // up front (a conservative pre-flight check) rather than trying to
  // intercept Anthropic's real usage numbers from inside the SSE tail —
  // see README.md's "known simplifications" section for why a true-up
  // pass using actual input/output token counts is follow-up work, not a
  // P1 requirement.
  const check = await checkQuota(env.QUOTA_KV, claims.sub, REPORT_SUMMARY_MAX_TOKENS, quotaLimits(env), now);
  if (!check.allowed) {
    // A tripped global cap is the "emergency brake" (docs/ROADMAP.md Part 4
    // §4.3): 503 signals the client should fall back to the always-available
    // on-device rule-based review, not just retry. A tripped per-user cap is
    // an ordinary 429.
    const status = check.reason === "global_exceeded" ? 503 : 429;
    return json({ error: check.reason ?? "quota_exceeded" }, status);
  }

  const startedAt = Date.now();
  const response = await relayReportSummary({
    anthropicApiKey: env.ANTHROPIC_API_KEY,
    input: validation.value,
    model: env.MODEL_REPORT
  });

  const userIdHash = await hashUserId(claims.sub);
  // Metadata only — see logging.ts's module doc comment. Never log
  // `rawBody`/`validation.value`/anything from `response`'s content.
  console.log(
    JSON.stringify(
      buildUsageLogEntry({
        userIdHash,
        feature: "report_summary",
        model: env.MODEL_REPORT,
        tokensReserved: REPORT_SUMMARY_MAX_TOKENS,
        latencyMs: Date.now() - startedAt,
        status: response.status
      })
    )
  );
  await recordUsage(env.QUOTA_KV, claims.sub, REPORT_SUMMARY_MAX_TOKENS, now);

  return response;
});

export default {
  async fetch(request: Request, env: Env, execCtx: ExecutionContext): Promise<Response> {
    if (request.method === "OPTIONS") {
      return withCors(new Response(null, { status: 204 }));
    }
    const response = await router.handle(request, env, execCtx);
    return withCors(response ?? json({ error: "not_found" }, 404));
  }
} satisfies ExportedHandler<Env>;
