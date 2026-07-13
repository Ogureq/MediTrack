// Entry point: wires the fixed wire contract's two routes (POST
// /v1/auth/anonymous, POST /v1/ai/generate) plus /health onto the
// hand-rolled Router, gates the AI relay behind JWT + premium enforcement +
// quota, and applies CORS. Kept intentionally thin — all the interesting
// logic lives in auth.ts / quota.ts / generate.ts / relay.ts and is
// unit-tested there; this file is mostly plumbing.

import { Router, type RouteContext } from "./router";
import type { Env } from "./env";
import {
  issueAnonymousToken,
  verifyAnonymousToken,
  verifyAppTransactionPlaceholder,
  AuthError
} from "./auth";
import { checkQuota, recordUsage, hasUsedFreeReport, markFreeReportUsed, type QuotaLimits } from "./quota";
import { validateGenerateRequest, maxTokensForKind, callAnthropic, type GenerateKind } from "./generate";
import { hashUserId, buildUsageLogEntry } from "./logging";

// CORS is permissive here because the only caller is a native iOS client
// (which does not send an `Origin` header at all) rather than a browser
// page — the wildcard exists mainly so the endpoints are also reachable from
// browser-based tooling (Wrangler's dev playground, manual testing) during
// development. Revisit if a web client is ever added.
const CORS_HEADERS: Record<string, string> = {
  "access-control-allow-origin": "*",
  "access-control-allow-methods": "GET,POST,OPTIONS",
  "access-control-allow-headers": "authorization,content-type",
  "access-control-max-age": "86400"
};

// Wire-contract-shaped UUID check for `deviceID` — deliberately
// version-agnostic (accepts the general 8-4-4-4-12 hex-with-dashes shape
// rather than strictly validating the version nibble) since it only needs
// to catch "missing or malformed", not police RFC 4122 minutiae.
const UUID_PATTERN = /^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$/;

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json" }
  });
}

/** Every non-200 response on this relay uses this one `{"error": {"code", "message"}}` shape, per the fixed wire contract. */
function errorResponse(status: number, code: string, message: string): Response {
  return json({ error: { code, message } }, status);
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

function modelForKind(kind: GenerateKind, env: Env): string {
  switch (kind) {
    case "report":
      return env.MODEL_REPORT;
    case "chat":
      return env.MODEL_CHAT;
    case "extract":
      return env.MODEL_EXTRACT;
  }
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

const router = new Router<Env>();

router.get("/health", () => json({ status: "ok" }));

// POST /v1/auth/anonymous — exchange a deviceID for a 24h JWT. No App Attest
// gate on this endpoint yet (see README.md's GA checklist item (b)); the
// `premium` claim is resolved from an optional `appTransaction`, which today
// always resolves to `false` (see `verifyAppTransactionPlaceholder`'s doc
// comment in auth.ts — this is a documented TODO, not a bug).
router.post("/v1/auth/anonymous", async ({ request, env }: RouteContext<Env>) => {
  const body = await readJsonBody(request);
  if (!body) return errorResponse(400, "bad_request", "Request body must be a JSON object.");

  for (const key of Object.keys(body)) {
    if (key !== "deviceID" && key !== "appTransaction") {
      return errorResponse(400, "bad_request", `Unknown field: ${key}`);
    }
  }

  const deviceID = body.deviceID;
  if (typeof deviceID !== "string" || !UUID_PATTERN.test(deviceID)) {
    return errorResponse(400, "bad_request", "deviceID is required and must be a UUID.");
  }

  const appTransaction = typeof body.appTransaction === "string" ? body.appTransaction : null;
  const premium = verifyAppTransactionPlaceholder(appTransaction);

  const issued = await issueAnonymousToken({ secret: env.JWT_SECRET, deviceId: deviceID, premium });
  return json({ token: issued.token, expiresInSeconds: issued.expiresInSeconds });
});

// POST /v1/ai/generate — JWT + premium + quota gated, non-streaming relay to
// Anthropic for all three kinds ("report", "chat", "extract"). See
// src/generate.ts for validation/prompt/model-selection and README.md for
// the full premium-enforcement behavior matrix, including the
// one-lifetime-free-report allowance for "report".
router.post("/v1/ai/generate", async ({ request, env }: RouteContext<Env>) => {
  const token = bearerToken(request);
  if (!token) return errorResponse(401, "unauthorized", "Missing bearer token.");

  let claims;
  try {
    claims = await verifyAnonymousToken(env.JWT_SECRET, token);
  } catch (err) {
    const code = err instanceof AuthError ? err.code : "unauthorized";
    return errorResponse(401, "unauthorized", `Token verification failed: ${code}.`);
  }

  const rawBody = await readJsonBody(request);
  if (!rawBody) return errorResponse(400, "bad_request", "Request body must be a JSON object.");

  const validation = validateGenerateRequest(rawBody);
  if (!validation.ok) {
    return errorResponse(400, "bad_request", validation.errors.join("; "));
  }

  const enforcePremium = env.ENFORCE_PREMIUM === "true";
  // Product rule (see README.md "Premium enforcement"): a non-premium device
  // gets exactly one lifetime free "report" generation as a taste of the
  // feature; "chat" and "extract" always require premium once enforcement is
  // on. `grantsFreeReport` is computed once here and re-checked after the
  // Anthropic call succeeds (and only then) to decide whether to consume it.
  const grantsFreeReport = enforcePremium && !claims.premium && validation.kind === "report";
  if (enforcePremium && !claims.premium) {
    if (validation.kind !== "report") {
      return errorResponse(
        402,
        "premium_required",
        "AI chat and quick-add extraction require an active MediTrack Premium subscription."
      );
    }
    if (await hasUsedFreeReport(env.QUOTA_KV, claims.sub)) {
      return errorResponse(
        402,
        "premium_required",
        "You've used your one free AI report. Upgrade to Premium for unlimited AI features."
      );
    }
  }

  const now = new Date();
  const tokensReserved = maxTokensForKind(validation.kind);
  // Reserve the request's full max_tokens budget against the ledger up
  // front (a conservative pre-flight check) rather than trying to intercept
  // Anthropic's real usage numbers — see README.md's "known simplifications"
  // for why a true-up pass using actual input/output token counts is
  // follow-up work, not a v1 requirement.
  const check = await checkQuota(env.QUOTA_KV, claims.sub, tokensReserved, quotaLimits(env), now);
  if (!check.allowed) {
    return errorResponse(429, "quota_exceeded", "Daily AI usage limit reached.");
  }

  const model = modelForKind(validation.kind, env);
  const startedAt = Date.now();
  const result = await callAnthropic({
    anthropicApiKey: env.ANTHROPIC_API_KEY,
    model,
    spec: validation.request
  });

  const userIdHash = await hashUserId(claims.sub);
  // Metadata only — see logging.ts's module doc comment. Never log
  // `rawBody`/`validation.request`/anything from the model's response text.
  console.log(
    JSON.stringify(
      buildUsageLogEntry({
        userIdHash,
        feature: validation.kind,
        model,
        tokensReserved,
        latencyMs: Date.now() - startedAt,
        status: result.ok ? 200 : result.status
      })
    )
  );

  if (!result.ok) {
    return errorResponse(502, "upstream_error", result.message);
  }

  // Only a genuinely successful, non-refused generation consumes the
  // one-lifetime free report — an upstream error never reaches this line
  // (it returns above), and a safety refusal is explicitly excluded too.
  if (grantsFreeReport && !result.result.refused) {
    await markFreeReportUsed(env.QUOTA_KV, claims.sub);
  }

  await recordUsage(env.QUOTA_KV, claims.sub, tokensReserved, now);

  return json({ text: result.result.text, refused: result.result.refused });
});

export default {
  async fetch(request: Request, env: Env, execCtx: ExecutionContext): Promise<Response> {
    if (request.method === "OPTIONS") {
      return withCors(new Response(null, { status: 204 }));
    }
    const response = await router.handle(request, env, execCtx);
    return withCors(response ?? errorResponse(404, "not_found", "No such route."));
  }
} satisfies ExportedHandler<Env>;
