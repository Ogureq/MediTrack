import type { KVLike } from "./quota";

/**
 * Cloudflare Workers environment bindings for the relay.
 *
 * `QUOTA_KV` is typed against our own minimal `KVLike` interface rather
 * than `@cloudflare/workers-types`' `KVNamespace` — a real bound KV
 * namespace satisfies `KVLike` structurally at runtime (it has `get`/`put`
 * methods with compatible signatures), and keeping the declared type
 * narrow is what lets `test/quota.test.ts` swap in a plain in-memory Map
 * implementation with zero mocking.
 *
 * `PER_USER_DAILY_TOKENS` / `GLOBAL_DAILY_TOKENS` are declared as unquoted
 * numbers in `wrangler.toml`'s `[vars]`, which Wrangler passes through as
 * JS numbers (not strings) at runtime.
 */
export interface Env {
  /** Quota ledger storage — see wrangler.toml for provisioning instructions. */
  QUOTA_KV: KVLike;

  /** Runtime configuration, set in wrangler.toml's [vars]. */
  PER_USER_DAILY_TOKENS: number;
  GLOBAL_DAILY_TOKENS: number;
  MODEL_REPORT: string;

  /**
   * Secrets. Never set in wrangler.toml or anywhere in code — provisioned
   * via `wrangler secret put <NAME>`. See README.md for the rotation
   * runbook.
   */
  ANTHROPIC_API_KEY: string;
  JWT_SECRET: string;
}
