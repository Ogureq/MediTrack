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
  /** Quota ledger storage (also holds the one-lifetime-free-report flag, see quota.ts) — see wrangler.toml for provisioning instructions. */
  QUOTA_KV: KVLike;

  /** Runtime configuration, set in wrangler.toml's [vars]. */
  PER_USER_DAILY_TOKENS: number;
  GLOBAL_DAILY_TOKENS: number;

  /** Model used for each `/v1/ai/generate` kind — see src/generate.ts. */
  MODEL_REPORT: string;
  MODEL_CHAT: string;
  MODEL_EXTRACT: string;

  /**
   * Model for the vision-based bloodwork-photo extraction endpoint (POST
   * /v1/extract-labs, src/extractLabs.ts) — deliberately a separate knob
   * from `MODEL_EXTRACT` above, which is dedicated to the unrelated
   * free-text Quick Add parsing kind on `/v1/ai/generate`.
   */
  MODEL_EXTRACT_LABS: string;

  /**
   * "true" or "false" (a Wrangler `[vars]` string, not a TOML boolean — kept
   * as a string so the comparison at the call site, `env.ENFORCE_PREMIUM ===
   * "true"`, is explicit and grep-able rather than relying on truthy
   * coercion). Gates `/v1/ai/generate` on the JWT's `premium` claim — see
   * README.md for the full enforcement behavior, including the
   * one-lifetime-free-report allowance for the "report" kind.
   */
  ENFORCE_PREMIUM: string;

  /**
   * Secrets. Never set in wrangler.toml or anywhere in code — provisioned
   * via `wrangler secret put <NAME>`. See README.md for the rotation
   * runbook.
   */
  ANTHROPIC_API_KEY: string;
  JWT_SECRET: string;
}
