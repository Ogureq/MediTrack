// Pure quota logic: per-user daily token ledger arithmetic, plus a global
// daily cap, keyed by UTC calendar day. Storage lives behind the minimal
// `KVLike` interface below (a subset of Cloudflare's `KVNamespace` shape)
// so tests can swap in a plain in-memory Map — no real KV, no network, no
// Workers runtime required to exercise this file. See docs/ROADMAP.md
// Part 4 §1.3–§1.4 and §4.3 for the product requirements this implements
// (per-user rate/spend limits, a global "emergency brake" cap).

/**
 * The minimal storage shape this module needs. A real Cloudflare
 * `KVNamespace` binding satisfies this structurally — its `get`/`put`
 * methods accept a strict superset of what's used here — so the same code
 * runs against production KV and an in-memory test double unmodified.
 */
export interface KVLike {
  get(key: string): Promise<string | null>;
  put(key: string, value: string, options?: { expirationTtl?: number }): Promise<void>;
}

export interface QuotaLimits {
  perUserDailyTokens: number;
  globalDailyTokens: number;
}

export interface QuotaStatus {
  userTokensUsed: number;
  userTokensRemaining: number;
  globalTokensUsed: number;
  globalTokensRemaining: number;
}

export type QuotaExceededReason = "user_exceeded" | "global_exceeded";

export interface QuotaCheckResult extends QuotaStatus {
  allowed: boolean;
  reason?: QuotaExceededReason;
}

export interface UsageTotals {
  userTokensUsed: number;
  globalTokensUsed: number;
}

const SECONDS_PER_DAY = 86400;
// Ledger keys auto-expire two UTC days after the day they belong to, so a
// KV binding with no other lifecycle policy doesn't accumulate rows
// forever. This is a storage-hygiene detail, not part of the reset logic
// itself — the reset happens because each UTC day gets its own key.
const KEY_TTL_SECONDS = 2 * SECONDS_PER_DAY;

/** The UTC calendar day (`YYYY-MM-DD`) a timestamp falls on. `Date#toISOString` is always UTC, so this needs no timezone handling. */
export function utcDayKey(now: Date): string {
  return now.toISOString().slice(0, 10);
}

function userLedgerKey(userId: string, day: string): string {
  return `usage:user:${userId}:${day}`;
}

function globalLedgerKey(day: string): string {
  return `usage:global:${day}`;
}

async function readCount(storage: KVLike, key: string): Promise<number> {
  const raw = await storage.get(key);
  if (raw === null) return 0;
  const parsed = Number(raw);
  return Number.isFinite(parsed) && parsed >= 0 ? parsed : 0;
}

/** Current usage + remaining headroom for a user, for the given moment. Read-only — does not mutate the ledger. */
export async function getUsageStatus(
  storage: KVLike,
  userId: string,
  limits: QuotaLimits,
  now: Date
): Promise<QuotaStatus> {
  const day = utcDayKey(now);
  const [userTokensUsed, globalTokensUsed] = await Promise.all([
    readCount(storage, userLedgerKey(userId, day)),
    readCount(storage, globalLedgerKey(day))
  ]);
  return {
    userTokensUsed,
    userTokensRemaining: Math.max(0, limits.perUserDailyTokens - userTokensUsed),
    globalTokensUsed,
    globalTokensRemaining: Math.max(0, limits.globalDailyTokens - globalTokensUsed)
  };
}

/**
 * Would spending `tokensRequested` right now fit under both the per-user
 * and global daily caps? Read-only — callers that get `allowed: true` must
 * separately call `recordUsage` after the request completes (or, for a
 * conservative pre-flight reservation, before dispatch) to actually book
 * the tokens; this function alone never mutates the ledger, so it's safe
 * to call speculatively.
 */
export async function checkQuota(
  storage: KVLike,
  userId: string,
  tokensRequested: number,
  limits: QuotaLimits,
  now: Date
): Promise<QuotaCheckResult> {
  const status = await getUsageStatus(storage, userId, limits, now);
  if (status.userTokensUsed + tokensRequested > limits.perUserDailyTokens) {
    return { ...status, allowed: false, reason: "user_exceeded" };
  }
  if (status.globalTokensUsed + tokensRequested > limits.globalDailyTokens) {
    return { ...status, allowed: false, reason: "global_exceeded" };
  }
  return { ...status, allowed: true };
}

/** Books `tokensUsed` against both the user's and the global daily ledgers for the UTC day `now` falls on. */
export async function recordUsage(
  storage: KVLike,
  userId: string,
  tokensUsed: number,
  now: Date
): Promise<UsageTotals> {
  const day = utcDayKey(now);
  const uKey = userLedgerKey(userId, day);
  const gKey = globalLedgerKey(day);
  const [userTokensUsed, globalTokensUsed] = await Promise.all([
    readCount(storage, uKey),
    readCount(storage, gKey)
  ]);
  const newUserTokensUsed = userTokensUsed + tokensUsed;
  const newGlobalTokensUsed = globalTokensUsed + tokensUsed;
  await Promise.all([
    storage.put(uKey, String(newUserTokensUsed), { expirationTtl: KEY_TTL_SECONDS }),
    storage.put(gKey, String(newGlobalTokensUsed), { expirationTtl: KEY_TTL_SECONDS })
  ]);
  return { userTokensUsed: newUserTokensUsed, globalTokensUsed: newGlobalTokensUsed };
}

// ---------------------------------------------------------------------------
// One-lifetime-free-report allowance (product decision, see README.md): a
// non-premium device may generate exactly one "report" kind via
// `/v1/ai/generate` before `ENFORCE_PREMIUM` starts returning
// `402 premium_required` for it. This flag lives in the same KV namespace as
// the daily ledgers above but is a lifetime flag, not a per-day one — it
// deliberately carries no `expirationTtl`, so it persists until the device
// (i.e. the KV key) is manually cleared.
// ---------------------------------------------------------------------------

function freeReportKey(deviceId: string): string {
  return `free_report:${deviceId}`;
}

/** Whether this device has already consumed its one lifetime free "report" kind generation. */
export async function hasUsedFreeReport(storage: KVLike, deviceId: string): Promise<boolean> {
  return (await storage.get(freeReportKey(deviceId))) !== null;
}

/**
 * Marks this device's one lifetime free report as consumed. Callers must
 * only call this after a genuinely successful, non-refused generation — see
 * src/index.ts's `/v1/ai/generate` handler, which calls this only when the
 * upstream call succeeded and the model did not refuse. A failed upstream
 * call or a safety refusal must not cost the device its one free try.
 */
export async function markFreeReportUsed(storage: KVLike, deviceId: string): Promise<void> {
  await storage.put(freeReportKey(deviceId), "1");
}
