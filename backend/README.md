# gemocode-relay

The AI relay for Gemocode (Cloudflare Workers). It fronts the **owner's**
Anthropic API key so premium subscribers can use Gemocode's AI features
without bringing their own key: the iOS app sends already-computed,
structured data (the rule-based review, a compact chat context, or a single
user-typed Quick Add line — never attachments, never raw documents, never
the Medical ID fields) to `POST /v1/ai/generate`, and the relay calls the
Anthropic Messages API server-side and returns the answer as a single JSON
response. It persists nothing but a metadata-only daily token ledger and a
per-device "free report used" flag.

**Business model:** every local Gemocode feature is free; AI is premium
(**$19.99/month**, which is what funds the owner-paid Anthropic usage this
relay performs) — with exactly **one free lifetime AI report** per device as
a trial. Enforcement ships behind the `ENFORCE_PREMIUM` flag (default
`"false"`) so the deployed relay can be tested end-to-end before App Store
subscriptions and App Attest are live — see the GA checklist below.

## Wire contract

All error responses (any non-200) share one shape:

```json
{ "error": { "code": "unauthorized", "message": "human-readable detail" } }
```

with codes: `401 unauthorized`, `402 premium_required`, `429 quota_exceeded`,
`400 bad_request`, `413 payload_too_large` (POST /v1/extract-labs only),
`502 upstream_error`, `502 invalid_model_output` (POST /v1/extract-labs
only) (plus `404 not_found` for unknown routes, and a last-resort
`500 internal_error` if a handler throws unexpectedly instead of returning
one of the structured errors above — see `src/index.ts`'s top-level
try/catch around route dispatch).

### `POST /v1/auth/anonymous`

Exchange a client-generated device UUID for a 24-hour JWT.

```json
// request
{ "deviceID": "6f1e1c1a-2b3c-4d5e-8f90-112233445566" }

// request (optionally claiming premium — see "Premium enforcement" below)
{ "deviceID": "6f1e1c1a-…", "appTransaction": "<base64 App Store transaction JWS>" }

// 200 response
{ "token": "<jwt>", "expiresInSeconds": 86400 }
```

- The JWT's `sub` is the `deviceID`; it also carries a boolean `premium`
  claim, fixed at issuance time.
- `400 bad_request` on a missing/malformed (non-UUID) `deviceID`, a
  non-JSON body, or unknown fields.
- There is no refresh flow: when the token expires, call this endpoint
  again with the same `deviceID`.
- **`appTransaction` is currently never verified and never grants
  `premium: true`** — see the GA checklist. The relay fails closed rather
  than fake-verifying.

### `POST /v1/ai/generate`

`Authorization: Bearer <jwt>`. One endpoint, three kinds — the server owns
every system prompt and model choice (ported from the app's original
BYO-key services: `AISummaryService.swift`, `AIChatService.swift`,
`QuickAddAIService.swift`, keeping their educational-not-diagnostic rails,
only-discuss-provided-data rules, and strict-JSON output instructions).

```json
// request — "report": the structured review JSON the app already builds
{ "kind": "report", "input": { "score": 78, "scoreLabel": "Good",
  "profileSummary": null,
  "findings": [{ "id": "f0", "severity": "attention", "category": "labs",
                 "title": "LDL Cholesterol Elevated", "detail": "LDL 142 mg/dL…" }],
  "labValues": [{ "id": "lv0", "name": "LDL Cholesterol", "value": 142,
                  "unit": "mg/dL", "status": "high" }],
  "deltas": [] } }

// request — "chat": context ≤8000 chars; ≤12 messages, each ≤2000 chars,
// roles "user"/"assistant" only, first message must be "user"
{ "kind": "chat", "input": { "context": "Health score: 78/100 (Good)…",
  "messages": [{ "role": "user", "text": "What does my LDL finding mean?" }] } }

// request — "extract": text ≤1000 chars, today = YYYY-MM-DD
{ "kind": "extract", "input": { "text": "bp 120 over 80 this morning",
  "today": "2026-07-13" } }

// 200 response (all kinds)
{ "text": "<model output text>", "refused": false }

// 200 response when Anthropic ends with stop_reason == "refusal"
{ "text": "", "refused": true }
```

Per-kind handling (non-streaming for all three; see "Known simplifications"):

| kind | model (env var, default) | max_tokens | temperature |
|---|---|---|---|
| `report` | `MODEL_REPORT` (`claude-opus-4-8`) | 1500 | default |
| `chat` | `MODEL_CHAT` (`claude-sonnet-5`) | 700 | default |
| `extract` | `MODEL_EXTRACT` (`claude-haiku-4-5-20251001`) | 800 | 0 |

Validation rejects (400): unknown `kind`s, unknown fields anywhere (top
level, nested — an `attachment`/`imageData` field fails the request rather
than being dropped), oversized fields or payloads (`report` input is capped
at ~32KB total), and base64-blob-shaped strings in any text field.

### `POST /v1/extract-labs`

`Authorization: Bearer <jwt>`. Extracts lab values from a photographed lab
report via a vision-capable Anthropic model — a premium AI fallback that
complements (does not replace) the on-device deterministic OCR path
(`Gemocode/Services/LabScanService.swift`). The server owns the entire
extraction prompt: the request accepts only an `image` field, so there is no
way for a client to supply or override any prompt content.

```json
// request
{ "image": { "media_type": "image/jpeg", "data": "<base64, ~4MB decoded max>" } }

// 200 response ("facility" is additive/optional — omitted when the report
// doesn't clearly print a clinic/lab name, so older clients are unaffected)
{ "values": [
    { "name": "Fasting Glucose", "value": 95, "unit": "mg/dL", "sourceText": "Fasting Glucose 95 mg/dL" }
  ], "facility": "Quest Diagnostics", "refused": false }

// 200 response when Anthropic ends with stop_reason == "refusal"
{ "values": [], "refused": true }
```

- `media_type` must be exactly `"image/jpeg"` or `"image/png"` (400
  otherwise); `data` must be valid base64 (400 if malformed) and decode to
  ~4MB or less (`413 payload_too_large` otherwise — checked before the
  base64-shape check, so an oversized garbage string is reported as "too
  large" rather than "malformed"). For payloads over ~256KB, the base64
  charset check samples the first/last 4KB rather than scanning the whole
  string (a deliberate CPU-time-limit tradeoff — see `isValidBase64Charset`
  in `src/extractLabs.ts`); Anthropic's own decode remains the authoritative
  validator for anything outside that sampled window.
- Model: `MODEL_EXTRACT_LABS` (default `claude-sonnet-5`; a harder
  perception task than `MODEL_EXTRACT`'s free-text parsing, so it defaults to
  a stronger model despite the extra cost — a misread lab value has real
  correctness stakes). `max_tokens` 2000, `temperature` 0.
- If Anthropic's response text doesn't parse into `{"values": [...]}` (even
  after tolerantly stripping code fences / wrapper prose), the relay returns
  `502 invalid_model_output` rather than passing through garbage.
- `facility` is an optional top-level string: the printed name of the clinic
  or laboratory that issued the report (from its letterhead/header/footer),
  when one is clearly printed — never invented or inferred. Omitted from the
  response entirely when the model didn't return one.
- Premium gating mirrors `chat`/`extract` exactly — **no** one-lifetime-free
  allowance (that's scoped to the `report` kind only).
- Token accounting for this endpoint books Anthropic's *actual*
  `usage.input_tokens + usage.output_tokens` against the daily ledger
  (falling back to a fixed pre-flight estimate only if that field is
  missing), rather than `/v1/ai/generate`'s fixed per-kind reservation —
  image input-token cost varies too widely by photo size to fixed-budget.

## Premium enforcement

`ENFORCE_PREMIUM` (wrangler `[vars]`, string `"true"`/`"false"`, default
`"false"`) gates `/v1/ai/generate` on the JWT's `premium` claim:

| `ENFORCE_PREMIUM` | `premium` claim | `report` | `chat` | `extract` |
|---|---|---|---|---|
| `"false"` | any | allowed | allowed | allowed |
| `"true"` | `true` | allowed | allowed | allowed |
| `"true"` | `false` | **one lifetime free**, then `402` | `402` | `402` |

The one-lifetime-free-report allowance implements the product's trial ("one
free lifetime AI report"): a non-premium device's first successful `report`
generation is allowed; after that, `402 premium_required`. The flag is
stored in `QUOTA_KV` (`free_report:<deviceID>`, no TTL) and is **only
consumed by a genuinely successful, non-refused generation** — an upstream
error (502) or a safety refusal does not cost the device its free try.

Because the `premium` claim is fixed at token-issuance time and
`appTransaction` verification is unimplemented, turning `ENFORCE_PREMIUM`
on today means **every** device is non-premium (fail closed) — useful for
end-to-end testing the 402 paths, not for GA.

### GA checklist (owner actions before real production traffic)

1. **Implement App Store transaction verification**
   (`src/auth.ts#verifyAppTransactionPlaceholder`): verify the
   `appTransaction` JWS against Apple's App Store Server API, check the
   bundle ID and subscription product/expiry, and only then issue
   `premium: true` tokens. Do **not** shortcut this — the placeholder
   deliberately always returns `false`.
2. **Implement App Attest** (`src/auth.ts#verifyAppAttestPlaceholder` has
   the full requirements list): without it, `/v1/auth/anonymous` is a free
   JWT mint, and nothing stops a caller from generating a fresh `deviceID`
   per request to re-claim the free report or reset their per-user quota.
3. **Set `ENFORCE_PREMIUM = "true"`** in `wrangler.toml` and redeploy.

## What's here

```
backend/
  src/
    index.ts      — route wiring: auth, premium gate, quota gate, relay, CORS
    router.ts     — tiny hand-rolled router (no framework)
    auth.ts       — anonymous JWT issue/verify (jose, HS256); App Attest,
                    Sign in with Apple, and App Store transaction
                    verification are clearly-marked fail-closed stubs
    quota.ts      — pure per-user + global daily token ledger arithmetic,
                    plus the lifetime free-report flag
    generate.ts   — /v1/ai/generate: kind dispatch, chat/extract schemas +
                    prompts, non-streaming Anthropic call + refusal mapping
    relay.ts      — the "report" kind's request schema + system prompt
    extractLabs.ts — /v1/extract-labs: image request validation, the
                    vision-extraction system prompt, the Anthropic call
                    (image content block), and tolerant response sanity
                    parsing (code-fence stripping, values[] shape check)
    validation.ts — shared field validators (unknown-key + base64-blob rejection)
    logging.ts    — metadata-only (never content) usage log entries
    env.ts        — the `Env` bindings/vars/secrets interface
  test/           — vitest: quota, auth, schema validation, generate
                    dispatch/prompts/response mapping, full route-level
                    tests with an in-memory KV and stubbed upstream fetch,
                    router, logging — no network, no real KV
  wrangler.toml   — Worker config; secrets and the KV namespace ID are
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

There is no Cloudflare account tied to this repo. To actually ship it:

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
   `GLOBAL_DAILY_TOKENS`, `MODEL_REPORT`, `MODEL_CHAT`, `MODEL_EXTRACT`,
   `ENFORCE_PREMIUM`) and bump `compatibility_date` to a current date.
5. **Deploy:**
   ```bash
   npm run deploy
   ```
6. **Smoke test** `GET /health` returns `{"status":"ok"}`, then a full
   `POST /v1/auth/anonymous` → `POST /v1/ai/generate` round trip for each
   of the three kinds with known-shape payloads before considering the
   deploy good (see `docs/ROADMAP.md` Part 4 §5.2 for why this should
   eventually be an automated post-deploy CI step, not a manual check).

Then point the iOS client at the deployed Worker (the app's relay base URL
setting — see `Gemocode/Services/AITransport.swift`).

## Known simplifications (read before extending)

- **Non-streaming responses.** All three kinds return one JSON body after
  the model finishes. This is the simplest reliable v1; streaming chat
  (SSE) is a natural later upgrade and the old SSE re-framing design it
  would build on is in this repo's git history.
- **`appTransaction` is never verified** — see the GA checklist. Until item
  (1) lands, no token ever carries `premium: true`, so `ENFORCE_PREMIUM =
  "true"` locks out chat/extract entirely and limits every device to the
  one free report. This is deliberate fail-closed behavior, not a bug.
- **App Attest is not wired to `/v1/auth/anonymous`.**
  `auth.ts#verifyAppAttestPlaceholder` documents what real verification
  requires; until then the endpoint is a free JWT mint for anyone who can
  call it, and per-device accounting (quota, the free report) can be reset
  by minting a new `deviceID`. **Do not point production traffic at this
  deploy until the GA checklist is done.**
- **Sign in with Apple is not implemented** (`auth.ts#verifyAppleIdentityToken`
  throws `apple_signin_not_implemented`). Cross-device quota/entitlement
  recovery depends on it; it's P2 scope.
- **No persistent user table.** The relay is stateless: a "user" is the
  `deviceID` inside a valid JWT. This is enough for anonymous quota
  tracking but not for the P2 entitlements/StoreKit2 linkage work
  (`docs/ROADMAP.md` Part 4 §2.3's `entitlements` table).
- **Quota is reserved pre-flight at each kind's `max_tokens` budget**
  (1500/700/800), not true-up'd against Anthropic's actual reported token
  counts. This over-reserves on every request — safe but conservative. A
  true-up pass reading the response's `usage` field is natural follow-up
  work once real usage data exists.
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
  4. Verify a synthetic `POST /v1/ai/generate` request succeeds against the
     new key.
  5. For `ANTHROPIC_API_KEY`: revoke the old key in the Anthropic Console,
     then confirm a request using the old key now fails (401) within the
     propagation window.
  6. For `JWT_SECRET`: rotating it invalidates every previously-issued
     token immediately (there's no dual-key grace period). Clients recover
     automatically by re-calling `/v1/auth/anonymous`, which needs no user
     interaction — so unlike a login-based system this is cheap, but it
     still momentarily 401s in-flight sessions.

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
   client implements for a `429 quota_exceeded` response, with no deploy
   needed. For a single bad actor rather than a global spike, the offending
   user's per-user cap already limits them independently of the global cap.
3. **Rotate:** if the incident involves a suspected key leak (as opposed to
   just abusive-but-legitimate usage), follow the key-rotation runbook
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
| `/v1/auth/anonymous` | POST | none (App Attest is a GA-checklist item) | Exchange a `deviceID` for a 24h JWT with a `premium` claim |
| `/v1/ai/generate` | POST | `Authorization: Bearer <JWT>` | Premium- and quota-gated non-streaming relay to Anthropic (`report`/`chat`/`extract`) |
| `/v1/extract-labs` | POST | `Authorization: Bearer <JWT>` | Premium- and quota-gated relay that extracts lab values from a photographed lab report |

The earlier scaffold's `/v1/auth/refresh`, `/v1/usage/me`, and streaming
`/v1/ai/report-summary` routes were replaced by this contract (clients
re-auth instead of refreshing; usage introspection can return as a
follow-up). Their underlying token-pair helpers remain in `src/auth.ts`
(tested, unwired).

## Environment variables

| Name | Where | Meaning |
|---|---|---|
| `PER_USER_DAILY_TOKENS` | `[vars]` | Per-device daily token cap (pre-flight reservations) |
| `GLOBAL_DAILY_TOKENS` | `[vars]` | Global daily cap — the emergency brake |
| `MODEL_REPORT` | `[vars]` | Model for `kind: "report"` (default `claude-opus-4-8`) |
| `MODEL_CHAT` | `[vars]` | Model for `kind: "chat"` (default `claude-sonnet-5`) |
| `MODEL_EXTRACT` | `[vars]` | Model for `kind: "extract"` (default `claude-haiku-4-5-20251001`) |
| `MODEL_EXTRACT_LABS` | `[vars]` | Model for `/v1/extract-labs` (default `claude-sonnet-5`) |
| `ENFORCE_PREMIUM` | `[vars]` | `"true"`/`"false"` — gate `/v1/ai/generate` and `/v1/extract-labs` on the `premium` claim |
| `ANTHROPIC_API_KEY` | secret | Owner's Anthropic key — `wrangler secret put` only |
| `JWT_SECRET` | secret | HS256 signing key — `wrangler secret put` only |
