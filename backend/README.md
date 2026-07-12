# meditrack-relay

A stateless AI relay for MediTrack (Cloudflare Workers), scaffolded per
[`docs/ROADMAP.md` Part 4](../docs/ROADMAP.md). It forwards the app's
already-computed, structured report data (score, findings, flagged lab
values, deltas — never attachments, never free-text notes, never the
Medical ID fields) to the Anthropic Messages API under the owner's key, and
streams the answer back over SSE. It persists nothing but a metadata-only
daily token ledger.

**Status: NOT deployed. This is a P1 scaffold only.** No Cloudflare account
resources (KV namespace, secrets) have been provisioned, and nothing in this
directory assumes any exist — every account-specific value is either an
environment secret set at deploy time or a placeholder in `wrangler.toml`
with instructions to fill it in. The owner actions required to actually
stand this up are listed below.

**The iOS client is unaffected.** MediTrack's AI summary feature keeps
working via the existing BYO-key path
(`MediTrack/Services/AISummaryService.swift`, user-supplied Anthropic API
key in Profile & Settings) until this relay is deployed *and* the client is
migrated to call it (a separate, not-yet-done change described in
`docs/ROADMAP.md` Part 4 §3). Nothing in this scaffold touches iOS code.

## What's here

```
backend/
  src/
    index.ts    — route wiring: auth, quota gate, relay, CORS
    router.ts   — tiny hand-rolled router (no framework)
    auth.ts     — anonymous JWT issue/verify/refresh (jose, HS256);
                  App Attest + Sign in with Apple P1 stubs
    quota.ts    — pure per-user + global daily token ledger arithmetic
    relay.ts    — request-schema validation, Anthropic request building,
                  SSE re-framing, the report-summary relay itself
    logging.ts  — metadata-only (never content) usage log entries
    env.ts      — the `Env` bindings/vars/secrets interface
  test/         — vitest: quota, auth, schema validation, SSE mapping,
                  router, logging — all pure, no network, no real KV
  wrangler.toml — Worker config; secrets and the KV namespace ID are
                  deliberately NOT filled in (see "Deploying" below)
  package.json / tsconfig.json / vitest.config.ts
```

## Local development

```bash
cd backend
npm install
npm run typecheck   # tsc --noEmit
npm test            # vitest run — pure logic only, no network required
```

For `npm run dev` (running the Worker locally against real network calls),
create a `backend/.dev.vars` file (already gitignored — never commit it)
with:

```
ANTHROPIC_API_KEY=<your Anthropic API key, from console.anthropic.com>
JWT_SECRET=<any long random string>
```

## Deploying (owner action required)

This scaffold intentionally stops short of being deployable out of the box
— there is no Cloudflare account tied to this repo. To actually ship it:

1. **Install the CLI and authenticate**, if not already done:
   ```bash
   cd backend
   npx wrangler login
   ```
2. **Provision the quota-ledger KV namespace:**
   ```bash
   npx wrangler kv namespace create QUOTA_KV
   ```
   Paste the `id` it prints into the commented-out `[[kv_namespaces]]` block
   in `wrangler.toml` and uncomment it.
3. **Set the two secrets** (never put these in `wrangler.toml` or in code):
   ```bash
   npx wrangler secret put ANTHROPIC_API_KEY
   npx wrangler secret put JWT_SECRET
   ```
   Generate `JWT_SECRET` with something like `openssl rand -base64 32` — it
   only needs to be long and random, there's no format requirement.
4. **Review `wrangler.toml`'s `[vars]`** (`PER_USER_DAILY_TOKENS`,
   `GLOBAL_DAILY_TOKENS`, `MODEL_REPORT`) and bump `compatibility_date` to a
   current date.
5. **Deploy:**
   ```bash
   npm run deploy
   ```
6. **Smoke test** `GET /health` returns `{"status":"ok"}`, then a full
   `POST /v1/auth/anonymous` → `POST /v1/ai/report-summary` round trip with a
   known-shape payload before considering the deploy good (see
   `docs/ROADMAP.md` Part 4 §5.2 for why this should eventually be an
   automated post-deploy CI step, not a manual check).
7. **Point the iOS client at the deployed Worker.** Not yet implemented —
   `AISummaryService.swift`'s migration to call this relay instead of
   Anthropic directly is tracked separately in `docs/ROADMAP.md` Part 4 §3.

## Known P1 simplifications (read before extending)

- **App Attest is a placeholder.** `auth.ts#verifyAppAttestPlaceholder` only
  checks that *some* non-empty assertion string was sent — it does not
  verify a real Apple App Attest assertion against Apple's root CA, a
  server-issued nonce, or a sign-counter. Until the real verification
  described in that function's doc comment is implemented, `POST
  /v1/auth/anonymous` is a free JWT mint for anyone who can call it. **Do
  not point production traffic at this deploy until that's fixed.**
- **Sign in with Apple is not implemented** (`auth.ts#verifyAppleIdentityToken`
  throws `apple_signin_not_implemented`). Cross-device quota recovery and
  the App Store subscription linkage described in the roadmap depend on it;
  it's P2 scope.
- **No persistent user table.** The relay is deliberately stateless: a
  "user" is just the opaque id inside a valid JWT, deterministically
  derived from the client's device id (`auth.ts#deriveUserId`). This is
  enough for anonymous quota tracking but not for the P2 entitlements/
  StoreKit2 linkage work, which will need real persistence (`docs/ROADMAP.md`
  Part 4 §2.3's `entitlements` table).
- **Quota is reserved pre-flight at the request's `max_tokens` budget**, not
  true-up'd against Anthropic's actual reported input/output token counts
  after the stream completes (see the comment at the `checkQuota`/
  `recordUsage` call sites in `src/index.ts`). This over-reserves on every
  request (worst case, not actual, usage) — safe but conservative. A true-up
  pass reading the terminal `message_delta.usage` from the SSE stream is
  natural follow-up work once this is live and real usage data exists.
- **CORS is wide open (`*`)** because the primary caller is a native iOS
  client, which doesn't send an `Origin` header at all; the wildcard exists
  for browser-based dev tooling. Tighten this if a web client is ever added.

## Key custody and rotation runbook

**Custody (non-negotiable):**

- `ANTHROPIC_API_KEY` and `JWT_SECRET` live **only** in Cloudflare Workers'
  secret store (`wrangler secret put`). Never in this repo, never in a
  client binary, never returned in any API response, never printed in logs
  — `src/logging.ts` logs metadata only (hashed user id, token counts,
  latency, model, status), by construction never the key or request/
  response content.
- Only the deployed Worker's runtime can read these secrets — no CI job, no
  developer laptop, no debugging tool needs them once initial setup is
  done.

**Rotation:**

- **Scheduled:** quarterly, regardless of any incident.
- **Immediate rotation triggers:** suspected leak (key appears in a log, a
  support ticket, a public repo scan), offboarding of anyone who had Console
  access, or an unexplained spend spike that doesn't correlate with traffic
  metrics.
- **Procedure:**
  1. Generate the new key in the Anthropic Console (for `ANTHROPIC_API_KEY`)
     or generate a new random value (for `JWT_SECRET`).
  2. `wrangler secret put <NAME>` to set the new value.
  3. `wrangler deploy` to pick it up.
  4. Verify a synthetic `POST /v1/ai/report-summary` request succeeds
     against the new key.
  5. For `ANTHROPIC_API_KEY`: revoke the old key in the Anthropic Console,
     then confirm a request using the old key now fails (401) within the
     propagation window.
  6. For `JWT_SECRET`: rotating it invalidates every previously-issued
     access/refresh token immediately (there's no dual-key grace period in
     this scaffold) — every signed-in client will need to re-authenticate
     via `/v1/auth/anonymous` (or `/v1/auth/apple` once implemented). Only
     rotate `JWT_SECRET` outside of a real incident with that in mind, or
     add dual-secret verification support first if forced re-auth for all
     users becomes unacceptable.

Keep this as a short, rehearsed runbook — not a from-scratch process each
time.

## Abuse-response flow

1. **Detect:** a spend-rate or per-user-request-rate anomaly alert fires.
   (This scaffold logs the metadata needed for such an alert —
   `src/logging.ts` — but does not yet wire up the alerting itself; see
   `docs/ROADMAP.md` Part 4 §5.3 for the minimum alert set to build before
   relying on this flow in production.)
2. **Contain:** the global daily cap (`GLOBAL_DAILY_TOKENS` in
   `wrangler.toml`, enforced in `quota.ts`) is the immediate backstop — it
   throttles the *entire* relay to the on-device-fallback behavior the
   client should implement for a `503` response, with no deploy needed. For
   a single bad actor rather than a global spike, the offending user's
   per-user cap (`checkQuota`'s `user_exceeded` path) already limits them
   independently of the global cap.
3. **Rotate:** if the incident involves a suspected key leak (as opposed to
   just abusive-but-legitimate-key usage), follow the key-rotation runbook
   above immediately rather than waiting for the next scheduled rotation.
4. **Postmortem:** update quota limits (`PER_USER_DAILY_TOKENS`/
   `GLOBAL_DAILY_TOKENS`), the App Attest verification once implemented, or
   this runbook itself based on what the incident revealed. This is a
   living document, not something written once and never revisited.

**Never "temporarily" raise or disable `GLOBAL_DAILY_TOKENS` to unblock a
pressured support request.** That cap exists precisely for the moment
someone is under pressure to bypass it. If a specific legitimate user
genuinely needs more headroom, that's a per-user tier change
(`PER_USER_DAILY_TOKENS`/a future per-tier override), on a case-by-case,
logged basis — not a change to the global backstop.

## Endpoints

| Endpoint | Method | Auth | Purpose |
|---|---|---|---|
| `/health` | GET | none | Liveness check |
| `/v1/auth/anonymous` | POST | App Attest assertion (placeholder, see above) | Issue an anonymous access+refresh JWT pair |
| `/v1/auth/refresh` | POST | refresh token in body | Rotate an expiring JWT pair |
| `/v1/ai/report-summary` | POST | `Authorization: Bearer <JWT>` | Quota-gated streaming relay to Anthropic for the report-summary feature |
| `/v1/usage/me` | GET | `Authorization: Bearer <JWT>` | Current UTC-day usage + remaining quota for the caller |

`POST /v1/auth/apple` (Sign in with Apple) is specified in the roadmap but
not yet wired into `src/index.ts` — `auth.ts#verifyAppleIdentityToken`
exists as a stub for it.
