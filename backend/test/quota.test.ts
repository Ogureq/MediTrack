import { describe, expect, it } from "vitest";
import { checkQuota, getUsageStatus, recordUsage, utcDayKey, type KVLike, type QuotaLimits } from "../src/quota";

/** In-memory stand-in for a Cloudflare KV namespace — satisfies `KVLike` with a plain Map, no network, no Wrangler runtime. */
class MemoryKV implements KVLike {
  private readonly store = new Map<string, string>();

  async get(key: string): Promise<string | null> {
    return this.store.has(key) ? (this.store.get(key) as string) : null;
  }

  async put(key: string, value: string): Promise<void> {
    this.store.set(key, value);
  }
}

const LIMITS: QuotaLimits = { perUserDailyTokens: 1000, globalDailyTokens: 1_000_000 };

describe("utcDayKey", () => {
  it("returns the UTC calendar day regardless of local timezone offsets baked into the Date", () => {
    expect(utcDayKey(new Date("2026-07-12T23:59:59.000Z"))).toBe("2026-07-12");
    expect(utcDayKey(new Date("2026-07-13T00:00:00.000Z"))).toBe("2026-07-13");
  });
});

describe("recordUsage / getUsageStatus (consume)", () => {
  it("accumulates tokens for a user across multiple calls on the same day", async () => {
    const kv = new MemoryKV();
    const now = new Date("2026-07-12T10:00:00.000Z");

    await recordUsage(kv, "user-1", 100, now);
    await recordUsage(kv, "user-1", 250, now);

    const status = await getUsageStatus(kv, "user-1", LIMITS, now);
    expect(status.userTokensUsed).toBe(350);
    expect(status.userTokensRemaining).toBe(650);
  });

  it("tracks separate users independently", async () => {
    const kv = new MemoryKV();
    const now = new Date("2026-07-12T10:00:00.000Z");

    await recordUsage(kv, "user-1", 400, now);
    await recordUsage(kv, "user-2", 10, now);

    const status1 = await getUsageStatus(kv, "user-1", LIMITS, now);
    const status2 = await getUsageStatus(kv, "user-2", LIMITS, now);
    expect(status1.userTokensUsed).toBe(400);
    expect(status2.userTokensUsed).toBe(10);
  });

  it("also accumulates into the global counter alongside the per-user counter", async () => {
    const kv = new MemoryKV();
    const now = new Date("2026-07-12T10:00:00.000Z");

    await recordUsage(kv, "user-1", 300, now);
    await recordUsage(kv, "user-2", 200, now);

    const status = await getUsageStatus(kv, "user-1", LIMITS, now);
    expect(status.globalTokensUsed).toBe(500);
  });
});

describe("checkQuota — per-user exhaustion", () => {
  it("allows a request that fits under the per-user daily cap", async () => {
    const kv = new MemoryKV();
    const now = new Date("2026-07-12T10:00:00.000Z");
    await recordUsage(kv, "user-1", 500, now);

    const result = await checkQuota(kv, "user-1", 400, LIMITS, now);
    expect(result.allowed).toBe(true);
    expect(result.reason).toBeUndefined();
  });

  it("rejects a request that would push the user over their daily cap (exhaust)", async () => {
    const kv = new MemoryKV();
    const now = new Date("2026-07-12T10:00:00.000Z");
    await recordUsage(kv, "user-1", 900, now);

    const result = await checkQuota(kv, "user-1", 200, LIMITS, now);
    expect(result.allowed).toBe(false);
    expect(result.reason).toBe("user_exceeded");
    // checkQuota is read-only: the ledger must be unchanged by a rejected check.
    const status = await getUsageStatus(kv, "user-1", LIMITS, now);
    expect(status.userTokensUsed).toBe(900);
  });

  it("allows a request that exactly fills the remaining budget (boundary)", async () => {
    const kv = new MemoryKV();
    const now = new Date("2026-07-12T10:00:00.000Z");
    await recordUsage(kv, "user-1", 900, now);

    const result = await checkQuota(kv, "user-1", 100, LIMITS, now);
    expect(result.allowed).toBe(true);
  });
});

describe("checkQuota — global cap", () => {
  it("rejects a request that would exceed the global cap even when the user has headroom", async () => {
    const kv = new MemoryKV();
    const now = new Date("2026-07-12T10:00:00.000Z");
    const tightGlobalLimits: QuotaLimits = { perUserDailyTokens: 100_000, globalDailyTokens: 100 };

    await recordUsage(kv, "user-1", 80, now);

    const result = await checkQuota(kv, "user-2", 50, tightGlobalLimits, now);
    expect(result.allowed).toBe(false);
    expect(result.reason).toBe("global_exceeded");
  });

  it("checks the user cap before the global cap when both would be exceeded", async () => {
    const kv = new MemoryKV();
    const now = new Date("2026-07-12T10:00:00.000Z");
    const bothTight: QuotaLimits = { perUserDailyTokens: 10, globalDailyTokens: 10 };

    const result = await checkQuota(kv, "user-1", 20, bothTight, now);
    expect(result.allowed).toBe(false);
    expect(result.reason).toBe("user_exceeded");
  });
});

describe("midnight UTC reset", () => {
  it("does not count a previous UTC day's usage against the current day", async () => {
    const kv = new MemoryKV();
    const lastMinuteOfDay1 = new Date("2026-07-12T23:59:00.000Z");
    const firstMinuteOfDay2 = new Date("2026-07-13T00:01:00.000Z");

    await recordUsage(kv, "user-1", 900, lastMinuteOfDay1);

    const day1Status = await getUsageStatus(kv, "user-1", LIMITS, lastMinuteOfDay1);
    expect(day1Status.userTokensUsed).toBe(900);

    const day2Status = await getUsageStatus(kv, "user-1", LIMITS, firstMinuteOfDay2);
    expect(day2Status.userTokensUsed).toBe(0);
    expect(day2Status.userTokensRemaining).toBe(LIMITS.perUserDailyTokens);

    // A request that would have been rejected on day 1 is allowed fresh on day 2.
    const day1Check = await checkQuota(kv, "user-1", 200, LIMITS, lastMinuteOfDay1);
    expect(day1Check.allowed).toBe(false);
    const day2Check = await checkQuota(kv, "user-1", 200, LIMITS, firstMinuteOfDay2);
    expect(day2Check.allowed).toBe(true);
  });

  it("resets the global counter at midnight UTC too", async () => {
    const kv = new MemoryKV();
    const tight: QuotaLimits = { perUserDailyTokens: 100_000, globalDailyTokens: 100 };
    const day1 = new Date("2026-07-12T12:00:00.000Z");
    const day2 = new Date("2026-07-13T12:00:00.000Z");

    await recordUsage(kv, "user-1", 100, day1);
    expect((await checkQuota(kv, "user-2", 1, tight, day1)).allowed).toBe(false);
    expect((await checkQuota(kv, "user-2", 1, tight, day2)).allowed).toBe(true);
  });
});
