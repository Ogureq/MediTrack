// Metadata-only request logging. Per docs/ROADMAP.md Part 4 §5.3: structured
// JSON logs may carry request/response *metadata* (hashed user id, token
// counts, latency, model, stop reason) but must NEVER carry request or
// response *content* — no health data, no prompt text, no model output.
// This file exists to make that boundary a typed, testable shape rather
// than an ad-hoc `console.log(...)` call at each call site.

export interface UsageLogEntry {
  userIdHash: string;
  feature: string;
  model: string;
  tokensReserved: number;
  latencyMs: number;
  status: number;
  timestamp: string;
}

/**
 * One-way hash of an internal user id for logs. Note this hashes the
 * already-opaque internal id (see `auth.ts#deriveUserId`), not any Apple
 * or device identifier — logs are two steps removed from anything a
 * client or Apple could recognize.
 */
export async function hashUserId(userId: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(userId));
  return [...new Uint8Array(digest)].map((byte) => byte.toString(16).padStart(2, "0")).join("");
}

/** Builds a metadata-only log entry. Deliberately has no field for prompt/response text — see module doc comment. */
export function buildUsageLogEntry(opts: {
  userIdHash: string;
  feature: string;
  model: string;
  tokensReserved: number;
  latencyMs: number;
  status: number;
  now?: Date;
}): UsageLogEntry {
  return {
    userIdHash: opts.userIdHash,
    feature: opts.feature,
    model: opts.model,
    tokensReserved: opts.tokensReserved,
    latencyMs: opts.latencyMs,
    status: opts.status,
    timestamp: (opts.now ?? new Date()).toISOString()
  };
}
