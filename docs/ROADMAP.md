# Gemocode Upgrade Roadmap

Produced by a six-role product team review (product, UX, backend, AI, security, growth) of the
existing codebase. Each role's full report follows the executive synthesis. Every recommendation
carries an effort tag (S/M/L) and a phase (P1 = 0–6 weeks, P2 = 6–16 weeks, P3 = later).

## Executive synthesis

Gemocode today is a complete, CI-verified, local-first iOS tracker whose differentiator is
architectural: a deterministic, unit-tested analysis engine computes every number and severity,
and the AI layer only narrates. The upgrade direction — serving AI to all users from an
owner-held Anthropic key — is a pivot to a thin backend, and the whole team converged on the
same shape for it:

**The backend is a stateless AI relay. Health data stays on-device.** Only engine-derived,
structured JSON (score, flagged biomarkers, deltas, findings) ever crosses the wire. Medical ID,
attachments, and free-text notes never do. The server persists a metadata-only usage ledger —
never health content. This preserves the app's strongest marketing claim, keeps GDPR exposure
minimal, and makes account deletion trivial.

### Decisions adopted (cross-team, reconciled)

1. **Rule engine stays client-side, always.** Server-side scoring changes without a test gate are
   a liability nightmare for an educational-not-diagnostic product. (PM, AI)
2. **BYO-key survives as an opt-in fallback**, off by default for new users. Cheap to keep,
   protects the privacy-maximalist segment, and is the offline/budget-exhausted story. (PM, Backend)
3. **Monetize only the new AI layer.** Everything free today stays free — OCR scanning, the
   score, interactions, tracking. Free tier includes 3 lifetime AI reports; Premium at
   $9.99/mo / $59.99/yr (7-day trial on annual) unlocks unlimited reports, chat, and timeline.
   Lifetime purchases cover local features only, never metered AI. (Growth, PM)
4. **Stack: Cloudflare Workers + Neon Postgres + Durable Objects**, App Attest-gated anonymous
   JWT auth upgradeable via Sign in with Apple; StoreKit 2 for entitlements. Fly.io reserved as
   the P3 heavy-compute fallback. No microservices, no CloudKit, no custom auth, no vector DB. (Backend)
5. **The flagship AI report is structured JSON, not prose**, rendered natively by the app, with
   two verification guards — every number in the output must exist in the input, and every risk
   indicator must reference a real engine finding — falling back to the rule-based narrative on
   any failure or refusal. Model split: Opus 4.8 for reports, Sonnet 5 for chat, Haiku 4.5 for
   timeline captions. (AI)
6. **Quiz and reminders ship on-device in P1 with zero backend dependency.** The quiz's real job
   is fixing activation: `HealthProfile` currently starts blank, so day-one users see an empty
   score ring. The quiz populates it and ends on a personalized preview — that is the wow moment. (UX, PM)
7. **Killed or reshaped**: voice assistant, nutrition/meal/sleep/fitness recommendations
   (drift toward personalized medical advice), predictive forecasting (reshaped to narrate-only),
   a 6th tab, cloud family sync (reshaped to on-device multi-profile, P3), guilt-based streak
   mechanics, and any paywalling of currently free features. (AI, UX, Growth)
8. **Security debts fixed in P1 regardless of the pivot**: passphrase-encrypted backup
   (AES-GCM + PBKDF2), user API key moved from UserDefaults to Keychain, passcode attempt
   backoff, widget redaction when app-lock is on (P2), and a consent/privacy-policy rewrite that
   must land *before* the backend ships, since the backend breaks the current "nothing leaves
   the device" claim. (Security)
9. **The owner's API key** lives only in the backend secret store — never in the repo, client,
   or logs — with quarterly-plus-triggered rotation and per-user + global spend caps enforced at
   the edge. App Attest is the load-bearing control against non-app clients draining the key. (Security, Backend)
10. **Aggregate-only analytics (TelemetryDeck-class) sequence before the paywall** — nothing else
    can be validated without it, and the event enum must structurally exclude health content. (Growth)

### Unified phase plan

**P1 (0–6 weeks) — activation, trust, and the relay.**
On-device: onboarding quiz populating HealthProfile; "Today" dashboard v1 with the
Reminder/ReminderCompletion system; encrypted backup; key→Keychain; lock hardening;
score-change and 90-day re-test notifications; shareable redacted score card; analytics; privacy
explainer screen. Platform: backend proxy v1 (auth, streaming report relay, usage endpoint,
spend caps); AISummaryService migrates to JWT + streaming; consent UI. AI: flagship structured
report v1 with echo-checks and fallback; deterministic timeline events with template captions;
OCR plausibility guard; golden-set eval fixtures in CI.

**P2 (6–16 weeks) — premium and conversation.**
StoreKit 2 tiers and the paywall (shown after the first AI report preview, never before); AI
chat grounded in structured data with tappable citations and client-held memory; habit streaks
and the quarterly review ritual; tiered quotas wired to entitlements; usage dashboard; widget
upgrade + lock-screen redaction; biomarker carousel and timeline UI; Haiku caption polish.

**P3 (later) — scale and breadth.**
Multi-region routing, queued batch analysis, model routing under load; on-device multi-profile
("family"); document organizer; Local Lifetime tier; EU rollout with GDPR consent flows.

### Cost reality

≈ $0.15/user/month Anthropic ceiling at realistic engaged usage (4 reports + 30 chat turns) —
healthy margin under a $9.99 premium, but it makes free-tier caps and model routing
non-optional at scale. Prompt caching only pays once the system prompt embeds the static lab
reference context (today's short prompt is below the cacheable minimum) — do that as part of
the P1 report redesign.

---

# Part 1 — Product management: audit & prioritization

# Gemocode — Product Audit & Roadmap for the AI/Backend Pivot

**Prepared by:** PM review (analysis only, no repo changes)
**Date:** 2026-07-12
**Scope:** Audit current product, competitive positioning, gap analysis vs. owner's 7 focus areas, prioritized roadmap, sequencing, and pushback on the direction where warranted.

---

## 0. What I verified before writing this

Spot-checked against the actual code, not just the brief:

- `docs/PLAN.md` confirms 15 shipped phases; feature set matches the brief exactly.
- `GemocodeTests/` has **92 `func test` cases across 10 files** — matches the claimed count, and it's real coverage (engine, edge cases, catalog, scanning, interactions, models, units, backup, widget bridge, app lock).
- `Services/AISummaryService.swift`: BYOK is real — key lives in `UserDefaults` under `anthropicAPIKey`, and critically, **only `review.shareText` (the already-computed, deterministic summary) is sent to Anthropic — never raw documents, attachments, or the database.** The system prompt explicitly forbids diagnosis/treatment suggestions and mandates a "discuss with your clinician" close. This is a real architectural decision, not incidental.
- README already states the intent: *"The analysis engine is rule-based and deterministic — no cloud AI is involved. It is designed so that an LLM-powered summarizer could be added later behind the same `HealthReview` interface without disturbing the rest of the app."* — the current architecture was **built to anticipate exactly this pivot**, which de-risks it more than a typical "bolt AI onto a static app" migration.
- `Models/Models.swift`: `Medication` has no supplement/OTC distinction (just name/dosage/frequency/purpose), `HealthProfile` has only DOB/sex/height/blood type/allergies/conditions as free text — **no lifestyle, goals, or quiz-shaped fields exist today.** Onboarding (`OnboardingView.swift`) is a static 4-page tutorial ending in a disclaimer acknowledgement; it collects zero data.
- No `StoreKit`, `IAP`, `Purchase`, or `subscription` references anywhere in the repo — **monetization is fully greenfield.** No paywall, no entitlement model, no receipt validation.
- No accounts, no auth, no backend, no multi-device sync of any kind (README roadmap lists iCloud/CloudKit as *considered, not implemented*).

Everything below is built on this ground truth, not just the brief.

---

## 1. Audit: what's genuinely strong, what's weak

### The moat (don't break this)

1. **Deterministic engine as an AI hallucination guard.** `AnalysisEngine.swift` (798 lines, pure functions, `now:` injected, zero `Date()` calls, 92 tests) computes the score and findings from a 46-reference-range lab catalog with sex-specific bounds, ACC/AHA BP categories, and real linear-regression trend classification. The *existing* AI feature never lets an LLM touch raw numbers — it only paraphrases output that's already correct and already tested. That is a genuinely uncommon design and it is the single most defensible thing in this codebase.
2. **On-device-first privacy, demonstrated not just claimed.** Passcode is salted SHA-256 in Keychain with constant-time compare, Face ID is additive, HealthKit is opt-in both directions, OCR runs on-device via Vision. The README's privacy section is currently 100% true. That's rare in this category and it's a marketing asset, not just an engineering property.
3. **Real utility beyond "chat about your PDF."** OCR-to-structured-data (synonym matching, confirm-before-add), a widget, PDF export, Medical ID, an actual (if intentionally non-exhaustive) drug-interaction checker, medication/appointment reminders. These are sticky, everyday-use features that a pure analysis/chat product doesn't have reason to build.
4. **Engineering discipline at odds with the "indie health app" stereotype.** CI-gated 92-test suite, deterministic test fixtures, hand-maintained pbxproj kept internally consistent — this lowers the risk of the pivot breaking core functionality, provided the same discipline is demanded of the new backend/AI code.

### What's weak or missing (be blunt)

1. **No accounts. At all.** This is not a checkbox — it's the load-bearing gap under nearly every item in the owner's wishlist (metering, chat memory, cross-device state, subscription management, support/refunds). The owner's brief treats "backend with server-side key" as one line item; it is actually the *smallest* part of the real lift. Auth + account lifecycle + entitlement state is the bigger one.
2. **No multi-device story.** A user who pays for "premium" on their iPhone and later reinstalls or gets a new phone has no path back to their data or their AI conversation history unless sync is built. Shipping monetization before sync is a support-ticket generator.
3. **Onboarding collects nothing.** "Personalized onboarding quiz" sounds like a UI task; it's actually a data-model task first (no lifestyle/goals/activity fields exist anywhere) and a personalization-logic task second (nothing currently reads such fields).
4. **"Habit reminders" has no home in the data model.** `Medication` conflates prescriptions and would-be supplements with no `kind` flag; a habit isn't a medication at all (no dose, no interaction relevance) — this wants a new lightweight model, not a repurposed one.
5. **Zero monetization primitives.** No StoreKit, no entitlement layer, no paywall pattern anywhere. Whatever ships first will set the precedent for how gating is done everywhere after — worth designing once, deliberately, not per-feature.
6. **The privacy promise is about to become false unless it's handled explicitly.** The README says "nothing leaves the device" and "no account and no server" today. The pivot breaks that sentence. This isn't a reason not to pivot — it's a reason the *messaging and consent design* is itself a P1 deliverable, not an afterthought bolted onto the backend ticket.
7. **Compliance groundwork is invisible in the repo (as expected — it's not code) but must be tracked as work.** Once real lab values or AI conversation content about a user's health data cross the network to a server the owner controls, this stops being "a local app that happens to call an API with the user's own key" and starts being a service that stores/processes PHI-adjacent data. That has implications for Anthropic's commercial terms (confirm BAA/PHI-handling terms directly with Anthropic before routing real health data server-side — do not assume the consumer API terms that cover today's BYOK feature extend to a server-side, multi-tenant integration), App Store health-data nutrition labels, and a privacy policy rewrite. None of this shows up as a "feature" on a roadmap, which is exactly why it gets skipped — flag it explicitly (see §5).

---

## 2. Competitive positioning

**Against Function Health / Docus-style "understand my blood work" products:** those products are fundamentally *lab-ordering + interpretation* businesses — the interpretation is a wrapper around getting you to buy more panels, and your data lives on their servers by default because ordering labs requires an account and a lab relationship. Gemocode doesn't sell labs; it ingests whatever the user already has (a photo of a paper report from any doctor, insurer-covered panel, or hospital portal). That's a **lower-friction, lower-COGS, broader-applicability** position — no lab-partner logistics, no test-menu maintenance, works with the 100% of users who already have reports sitting in a drawer or a Health app export. This is worth stating explicitly in marketing: "we don't sell you tests, we make sense of the ones you already paid for."

**Against generic AI-chat-with-your-PDF apps (ChatGPT/Claude used ad hoc, or thin wrapper apps):** those have no grounding. The LLM is trusted to both *recall* what a normal ALT or LDL range is *and* to reason over it correctly, with no deterministic check and no persistent structured history. Gemocode inverts this: the 46-test reference catalog and rule engine compute the numbers; the LLM's job is reduced to *paraphrasing already-correct output into a warmer tone*. That is a materially safer architecture for a category where a wrong "normal range" recall is a real harm, and it's not something a thin AI-chat wrapper can retrofit without rebuilding a reference-range catalog and trend engine from scratch — which is exactly what already exists here (865-line `LabCatalog.swift` with sex-specific ranges, 15 catalog tests). **This "AI you can audit" vs. "AI you have to trust" framing is the single best differentiation angle available and should be foregrounded in both product messaging and the technical design of every new AI feature** (see §4, item AI-1 and the chat guardrail note).

**Against Apple Health itself:** Health is a passive data lake — no reference ranges, no scoring, no OCR of paper reports, no interaction checking, no doctor-shareable output. Gemocode is correctly positioned as an *interpretation and action layer on top of* HealthKit (it already reads and writes to it), not a competitor to it. Keep that co-existence story; do not let the pivot tempt a rebuild of vitals tracking that duplicates what Health already does well.

**Net assessment:** the on-device-deterministic-engine-plus-optional-AI-narrator hybrid is genuinely unusual and defensible — copying it requires building a tested reference-range catalog and rule engine, not just calling an LLM API, which is a multi-month engineering investment competitors building "AI wrapper" products won't have made. The pivot's risk is **diluting this exact differentiator** by moving toward "yet another AI-chat health app" if the new features (AI chat especially) are built as generic LLM-over-raw-data rather than LLM-over-vetted-structured-output. Preserve the pattern.

---

## 3. Feature gap analysis vs. the owner's 7 focus areas — kill/reshape calls

| Owner ask | Verdict | Why |
|---|---|---|
| Backend with owner's key, server-side, usage metering, cost control | **Keep, but resequence.** This is infrastructure, not a feature — it unlocks everything else but has zero user-facing value alone. Do not treat "ship the backend" as a milestone with its own launch; ship it paired with the first feature that needs it. | See §5 sequencing. |
| Richer AI reports w/ historical comparison | **Keep, reshape.** Most of the hard part (score history, `ScoreSnapshot`, trend regression) already exists on-device. The "AI" part should be a paraphrase/narration layer over deterministic deltas the engine already computes — not a new AI capability from scratch. Can ship a BYOK version in P1 before the backend exists. | Low new-engineering, high perceived value. |
| AI health timeline | **Keep, reshape as mostly-deterministic.** A chronological feed of score/vital/symptom/report events is a UI + query problem the app already has the data for; AI's role should be limited to short narrative captions on top, same grounding principle as above. | Don't let this become "LLM freeform summarizes your whole history" — keep it event-driven and grounded. |
| Personalized onboarding quiz | **Keep, but ship the on-device personalization first, before any server dependency.** Quiz answers should shape Dashboard defaults and goal suggestions using existing deterministic logic patterns (like `AnalysisEngine`), not require a network round-trip. Sending quiz/lifestyle answers to a server is a privacy-nutrition-label event — treat consent design as part of this ticket, not the backend ticket. | Cheap, high-signal, no backend blocker if scoped correctly. |
| Supplement/habit reminders on dashboard | **Keep as-is, ship immediately, no backend needed.** Needs a new lightweight model (not a repurposed `Medication`) and reuses the existing `NotificationService` pattern. This is the single best "ship this week" item in the whole list — real retention value, zero AI/backend risk. | Independent of every other item on this list. |
| Premium dashboard | **Reshape — reject as a standalone feature.** "Premium dashboard" as prettier UI is not a real wedge: the app already has a strong, consistent glassmorphic design system: visual polish is not the gap. Only build a paid dashboard tier once there's *new, genuinely gated capability* to put in it (AI timeline, AI chat, cross-device sync, deeper correlation views) — otherwise it reads as repackaging free functionality behind a paywall, which actively damages trust with an existing user base that adopted this app *because* it wasn't monetized. | See monetization pushback in §6. |
| AI chat about your reports | **Keep, but this is the highest-risk item on the whole list and needs the most guardrails.** Free-form chat is the easiest place to accidentally cross from "educational" into "diagnostic" — a single bad multi-turn response undermines the app's entire stance and the CLAUDE.md non-negotiable. Constrain it: ground responses only in the user's own structured findings/history (same data-minimization principle as today's AI summary — never raw documents), keep the mandatory disclaimer visible every session, and add refusal/redirect behavior for diagnosis/treatment/dosage questions and any crisis-adjacent language ("call your doctor" / emergency-number redirect). This is real product-safety engineering, not a config flag. | See AI-4 in roadmap; sequence last among the AI features, not first. |
| Monetization | **Keep, resequence to follow value, not precede it.** See §6 for the specific pushback on what to gate and what to leave free. | |

---

## 4. Prioritized roadmap (RICE-style)

Reach = portion of active users the feature touches (1–5). Impact = per-user value (0.5 minimal / 1 low / 2 medium / 3 massive). Confidence = execution confidence (%). Effort = S (1–3 person-wks) / M (4–8) / L (9+). Score is directional (Reach × Impact × Confidence ÷ Effort-midpoint-weeks), for relative ranking only — not a promise.

| # | Feature | Reach | Impact | Conf. | Effort | Phase | RICE (rel.) | Retention/revenue rationale |
|---|---|---|---|---|---|---|---|---|
| 1 | **Supplement/habit reminders** (new lightweight model + Dashboard card, reuses `NotificationService`) | 4 | 2 | 90% | S (2wk) | **P1** | ~3.6 | Cheapest, lowest-risk win on the list; daily-open driver independent of AI/backend; ships this sprint. |
| 2 | **Backend API + server-side Anthropic key + usage metering/rate limiting** | 5 | 3 | 90% | L (10wk) | **P1** | ~1.35 | Pure infrastructure but blocks every shared-key AI feature; the real cost-control lever the owner is asking for lives here, not in any single feature. |
| 3 | **Hybrid key model: keep BYOK, add metered server-key as default for new users** | 5 | 3 | 80% | M (5wk, mostly entitlement logic on top of #2) | **P1** | ~2.4 | Prevents the unit-economics risk of forcing every AI call onto the owner's bill immediately; preserves the zero-marginal-cost privacy story as an option/marketing angle. **This is a reshape of the owner's ask, not the ask as stated — see §6.** |
| 4 | **Accounts (Sign in with Apple, minimal profile)** | 5 | 2 | 90% | M (6wk) | **P1** | ~1.5 | Doesn't monetize directly but is the prerequisite for metering-per-user, cross-device restore, chat memory, and subscription support/refunds. |
| 5 | **On-device "explain this finding" deterministic Q&A** (tap a finding → structured explanation from existing `LabDetailView`-style content, no LLM call) | 3 | 1 | 90% | S (1–2wk) | **P1** | ~2.7 | Cheap trust-builder; reduces load on the future chat feature by answering the most common questions for free, offline, instantly. |
| 6 | **Personalized onboarding quiz (on-device personalization only)** | 5 | 2 | 70% | S/M (3wk) | **P1** | ~2.3 | Touches 100% of new users; seeds Dashboard defaults/goal suggestions immediately — no backend dependency if scoped to on-device logic. |
| 7 | **Proactive trend/symptom watchlist nudges on Dashboard** (extends existing engine, mostly deterministic) | 3 | 2 | 80% | S/M (3wk) | **P1/P2** | ~1.6 | Retention lever that ships independent of the whole AI pivot; reuses the regression/symptom logic that already exists and is tested. |
| 8 | **Monetization infra: StoreKit 2 subscription + entitlement gating + paywall pattern** | 5 | 3 | 80% | M (5wk) | **P2** | ~2.4 | Build once, deliberately — but *gate it to the first real premium feature's launch*, don't ship a paywall with nothing behind it. |
| 9 | **AI Report v2: historical comparison narrative** (paraphrase over existing score/trend deltas) | 3 | 2 | 70% | M (4wk) | **P1/P2** | ~1.05 | Reuses `ScoreSnapshot`/trend regression already in the engine; can ship on BYOK before the backend lands, then migrate to metered. |
| 10 | **AI health timeline** (event feed + short AI captions, grounded) | 3 | 2 | 60% | M (5–6wk) | **P2** | ~0.65 | Good "wow" surface for premium tier; keep AI role narrow (captions only) to protect the grounding principle. |
| 11 | **Premium dashboard** (correlation views, deeper historical charts, richer export) — gated behind items 9/10, not shipped standalone | 3 | 2 | 60% | M (6wk) | **P2** | ~0.6 | Only build once items 9/10 exist to put in it; otherwise it's repackaging free functionality (see §6). |
| 12 | **AI chat about your reports** (grounded in structured data only, guardrailed, disclaimer-persistent) | 3 | 3 | 50% | L (8–10wk) | **P2/P3** | ~0.5 | Highest ceiling *and* highest risk item; sequence after the grounding pattern is proven in items 9/10, not before. |
| 13 | **Cross-device sync** (CloudKit or backend-based, tied to accounts) | 3 | 2 | 60% | L (8wk) | **P2/P3** | ~0.45 | Becomes an expectation once anything is paid; don't ship subscriptions before this exists or reinstall/device-change churn will spike support load. |
| 14 | **Backend-triggered push notifications** ("your AI insight is ready", nudges) | 3 | 1 | 70% | M (4wk) | **P2/P3** | ~0.5 | Needs accounts + backend already in place; low standalone value, bundle with timeline/chat launch. |
| 15 | **Doctor-share structured export** (richer PDF / structured summary for premium tier) | 2 | 1 | 70% | M (4wk) | **P3** | ~0.35 | Legitimate differentiator vs. Function-Health-style consumer-only tools ("bring this to your next appointment"), but not urgent — nice-to-have once the core AI layer is stable. |

---

## 5. Sequencing dependencies (explicit)

- **Accounts before:** shared-key AI metering-per-user, cross-device sync, chat conversation persistence, clean subscription restore/refund handling. Technically StoreKit subscriptions don't *require* an account, but tying entitlement to an identity is what makes support, refunds, and "why did I lose my premium after reinstalling" tickets tractable — don't skip it to save time.
- **Backend + metering before:** any feature that removes the BYOK requirement (items 9, 10, 12, 14 above). Shipping shared-key AI to real users *before* rate limiting/quota exists is the fastest way to turn "richer AI reports" into an uncapped line item on the owner's Anthropic bill.
- **Onboarding quiz before/alongside:** any "personalization" claim in Dashboard or AI reports — there is currently no data source for personalization to draw on; the quiz *is* that data source, so it can't trail the features that depend on it.
- **Habit/supplement reminders have no dependency** — ship first, this sprint, independent of the whole pivot.
- **The AI-grounding pattern from item 9 (paraphrase over deterministic deltas) should be proven before item 12 (chat)** — chat is the highest-risk surface for drifting off the "educational, not diagnostic" stance, and it's far cheaper to validate the grounding approach on a single-shot report feature than on an open-ended multi-turn conversation.
- **Monetization (item 8) should trail, not lead, the first premium-worthy feature.** Building the paywall infrastructure can happen in parallel, but flipping it on before there's a feature that justifies it converts existing free users into a "why am I suddenly being asked to pay" moment — bad sequencing given the app's local-first, no-accounts brand to date.
- **Cross-device sync should land at or before general availability of any paid tier** — paying users expect their purchase to survive a device change; this is a support-cost and churn risk if skipped.

---

## 6. Where I'd push back on the owner

1. **Don't kill BYOK — make it the fallback, not the thing you replace.** The brief frames the pivot as *"server-side key for all users"* as if BYOK is being retired. That throws away the one feature that currently makes AI cost-free and privacy-maximal for the app's most trust-sensitive users (the same users this app's entire positioning has been built to attract). Keep both: server-key metered as the frictionless default for mainstream users, BYOK preserved as an option that also happens to make the "your data never has to leave your control" pitch still literally true for anyone who wants it. This is strictly better positioning against the "AI you have to trust" competitors and costs relatively little engineering (item 3 above is mostly entitlement-flag logic on top of the backend that has to exist anyway).

2. **Don't move the deterministic AnalysisEngine to the server.** Nothing in the brief explicitly proposes this, but "backend" projects have a gravitational pull toward "just compute everything server-side." Resist it. The rule engine's value is that it's *versioned, tested (92 cases), reviewable, and reproducible* — a server-side hotfix to scoring logic that silently changes what "your health score" means for every user, without going through the same test/CI gate the client code has, is a much bigger liability surface for a product whose entire legal position rests on "deterministic, rule-based, not diagnostic." Keep the engine on-device; let the backend be a thin proxy for the LLM call and the metering, nothing else.

3. **Don't build "AI chat about your reports" as chat-over-raw-documents.** The easy implementation — hand the LLM the OCR'd PDF text or the raw lab table and let it answer freely — throws away the grounding property that's the app's actual differentiator and meaningfully increases the odds of a wrong-range or quasi-diagnostic response landing in front of a user. Build it as retrieval over the *already-computed, already-tested* structured findings and history, same pattern as today's summary feature, with hard refusals on diagnosis/treatment/dosage questions.

4. **Don't paywall existing functionality.** The 12 features already shipped (reports, OCR scanning, vitals, trends, medications + interactions, symptoms, appointments, goals, Medical ID, PDF export, backup, widget, lock) were built and marketed as a free, local-first app. Retroactively gating any of that behind a subscription is a trust break with the existing user base and contradicts the "local-first, no accounts" identity that's the whole reason this codebase exists. Monetize the *new* AI-hybrid layer (comparison reports, timeline, chat, sync) — leave the on-device core free forever. This is also simply the more defensible freemium wedge: free tier is a fully useful health tracker on its own (unusual and valuable), paid tier is the AI layer on top.

5. **Treat the privacy-messaging rewrite as a P1 deliverable, not a footnote.** The README currently makes an absolute claim ("100% on-device... nothing leaves the device... no account and no server") that becomes false the moment the backend ships to any user. This needs an explicit, honest, opt-in consent flow and updated App Store privacy nutrition labels *before* the backend features reach the App Store — not a quiet contradiction discovered by a user or a reviewer later. Recommend scoping this alongside item 2/3 in the roadmap, not as a separate "docs" ticket that slips.

6. **Confirm Anthropic's data-handling/BAA terms for the server-side, multi-tenant use case before routing real health data through the owner's key.** The existing BYOK feature already sends data to Anthropic today, but under the user's own account and their own agreement with Anthropic. A backend that proxies many users' health-adjacent content through one owner-controlled key is a materially different arrangement and its own commercial-terms conversation — worth a definitive answer before, not after, scaling AI report/chat volume.

---

## 7. Summary of net-new engineering surface (sanity check on scope)

For calibration: the owner's brief reads like ~8 feature bullets, but the actual net-new surfaces are:
- an auth/account system (doesn't exist),
- a backend service with rate limiting/metering (doesn't exist),
- a subscription/entitlement/paywall system (doesn't exist),
- at least one new data model for habits (doesn't cleanly fit `Medication`),
- new data model/fields for quiz/lifestyle personalization (doesn't exist on `HealthProfile`),
- a cross-device sync layer (explicitly deferred today),
- a privacy-policy/consent/App-Store-nutrition-label rewrite (not code, but real work with a hard deadline tied to the backend's ship date),
- and a materially harder AI-safety design problem (multi-turn chat vs. one-shot paraphrase) layered on top of a codebase whose current AI footprint is 134 lines and one HTTP call.

None of this invalidates the pivot — the deterministic-engine-plus-AI-narrator architecture is a genuinely strong foundation for it, and the app was, per the README, explicitly designed to make this addition possible without disturbing the rest of the system. But this is a full platform expansion (single-device local app → accounts + backend + billing + conversational AI), not an incremental feature wave, and should be scoped/staffed/timelined as such rather than squeezed into the cadence of a solo-dev, phase-a-month project like the one that got the app this far.

---

# Part 2 — UX/UI: onboarding quiz, Today dashboard, premium polish

# Gemocode — Premium UX Upgrade: Onboarding Quiz, "Today" Dashboard, Reminders, AI Chat

Prepared as a design spec grounded in the current codebase (`Gemocode/Views/DashboardView.swift`, `OnboardingView.swift`, `ReviewScreen.swift`, `TrendsView.swift`, `Support/Theme.swift`, `Support/UIHelpers.swift`, `Models/Models.swift`, `Views/ContentView.swift`, `Services/NotificationService.swift`, `Services/AISummaryService.swift`, `Services/MedicationInteractions.swift`, `Services/BackupService.swift`, `docs/PLAN.md`). No repo files were modified — analysis and specs only.

Effort: **S** (<1 wk eng), **M** (1–3 wks), **L** (3+ wks). Phase: **P1** (0–6 wks), **P2** (6–16 wks), **P3** (later).

---

## 0. Grounding notes (what actually exists today)

- Tabs (`ContentView.swift`): Dashboard, Reports, Review, Trends, More. More fans out to Vitals, Symptoms, Medications, Appointments, Goals, Medical ID, Profile — 11 total destinations.
- `DashboardView.navigationTitle` already computes `"Hi, \(firstName)"` from `HealthProfile.name` — the "Good morning, User" ask is **80% built**; it just isn't time-of-day-aware and isn't a scroll-content element (it's the nav bar large title).
- `HealthProfile` today only carries `name, dateOfBirth, sexRaw, heightCm, bloodType, allergies, conditions` — and is only lazily created as a **blank** record the first time the user visits Profile & Settings (`ProfileView.swift:19-23`). Nothing populates it at first run. This is the root cause of the "no wow moment" problem: `AnalysisEngine` can't compute BMI, age-aware findings, etc. until the user manually fills a settings form they have no reason to visit.
- Onboarding today (`OnboardingView.swift`) is 3 feature-carousel pages + 1 mandatory privacy/disclaimer page, ending in an **empty Dashboard** (`ContentUnavailableView` + Add Report/Add Vital buttons). Zero data collected, zero personalization, zero score to show.
- Reminders already exist in miniature: `Medication.reminderEnabled/reminderTime/reminderID` + `NotificationService.scheduleDailyReminder` / `AppointmentsView`'s one-shot 24h-before reminder. There is no completion/streak tracking anywhere — reminders today only *fire*, they don't get *checked off*.
- The AI surface (`AISummaryService.swift`) already establishes the house pattern for anything AI-touched: opt-in BYO Anthropic key stored under `anthropicAPIKey`, `sparkles` icon + `Glass.accentGradient`, explicit "only X is sent" disclosure text, `stop_reason == "refusal"` check before trusting content. Every new AI surface should extend this pattern, not invent a new one.
- Design system primitives available for reuse (no new visual language needed): `.glassCard()`, `.tintedGlassCard(color)`, `.ambientScreen()`, `GlassRowBackground()`, `Glass.bevelStroke`, `Glass.accentGradient`, `StatusPill`, `GlassProminentButtonStyle`/`GlassButtonStyle`, `Haptics.success()`, `ScoreRing`, `ContentUnavailableView` empty states, `contentTransition(.numericText())`.

---

## 1. Honest critique of current UX

| Area | Finding | Severity |
|---|---|---|
| **Information architecture** | 5 tabs + a 7-item "More" junk-drawer = 11 primary destinations for a habit-forming health app. Dashboard and Review already duplicate the score ring, headline, and top findings (`DashboardView.scoreCard` vs `ReviewScreen.headerCard`) — the split exists but isn't earning its keep. | Medium |
| **First-run experience** | Onboarding explains the app but collects *nothing*. User lands on a literal empty state. There is no reason for `HealthProfile` to exist until someone opens Settings on purpose — most users never will, which silently degrades BMI/age-based findings for the app's entire lifetime. | High |
| **Empty states** | Consistent (`ContentUnavailableView` everywhere) but generic — default SF Symbol glyphs, no motion, no connection to the onboarding visual language (the frosted circle+icon badge used in `OnboardingPage`/`PrivacyPage` never resurfaces). Functionally fine, emotionally flat. | Medium |
| **The "wow" moment** | Doesn't exist. `ScoreRing`'s appear-animation (`ScoreRing.onAppear`, easeOut 0.9s) is genuinely nice motion work — but it only plays once real data exists, which for a fresh install is never on day one. The AI Summary card is buried behind a settings trip to paste an API key before anyone sees it. | High |
| **Premium feel gaps** | Glassmorphism itself reads premium (bevel strokes, ambient orbs, accent gradient) — the shell is good. What's missing is *personalization* (nothing addresses the user by context/time), *momentum* (no streaks, no "you improved" callouts, no daily reason to open the app), and *guidance* (findings are reactive/clinical in tone, never proactive/coaching in tone). | High |

**Bottom line**: the visual design system is already premium-grade; the product currently gives users nothing to look at on day one and no daily reason to return. The quiz + Today dashboard + reminders directly fix that — but only if the quiz actually seeds real data instead of being a decorative wizard.

---

## 2. Onboarding quiz design

### Challenge to the brief

> "ends on a personalized preview, not a signup wall"

Gemocode has no accounts, ever (CLAUDE.md: "no backend, no API layer, no accounts"). There is structurally no signup wall to avoid — this isn't a constraint to design around, it's a genuine competitive advantage over every quiz-then-paywall wellness app. Lean into it explicitly: the CTA at the end of the quiz should say something like **"Everything above stays on this device — let's go"**, turning the privacy stance itself into part of the reward, not a footnote.

### Structure (replaces + extends the current 4-page `OnboardingView`)

Total user-facing steps: **2 intro + 6 quiz + 1 preview = 9 screens**, but only 6 are the "quiz" proper (within the ≤8 budget), each independently skippable via the existing top-right "Skip" pattern already in `OnboardingView.swift:54`. A single "Skip setup" on step 1 jumps straight to the privacy page, preserving the current zero-friction path for people who just want to explore.

| # | Screen | Collects | Writes to | Effort |
|---|---|---|---|---|
| 1 | **Welcome** (consolidated) | — | — | Replaces today's 3-page feature carousel with **1** screen (icon + 3-line value prop + "Continue"). Cuts onboarding length even before the quiz starts. | S |
| 2 | **About you** | Name, date of birth, biological sex | `HealthProfile.name/dateOfBirth/sex` (fields already exist) | S |
| 3 | **Body basics** | Height, current weight (respecting the existing `Units.weightKey` preference) | `HealthProfile.heightCm` (exists) + seeds one `VitalSample(type: .weight)` dated today | S |
| 4 | **Daily rhythm** | 3 chip groups on one screen: sleep (hrs/night bucket), activity level (sedentary/light/moderate/active), diet pattern (omnivore/vegetarian/vegan/low-carb/other) | Sleep → seeds one `VitalSample(type: .sleepHours)` (feeds Trends/AnalysisEngine immediately, no duplicate field). Activity + diet → **new** `HealthProfile.activityLevelRaw` / `dietPatternRaw` (new enums, default `.unspecified`) | M |
| 5 | **Health goals** | Multi-select intent chips: lose weight, build muscle, better sleep, lower blood pressure, manage a condition, more energy, general wellness | **New** `HealthProfile.primaryGoalsRaw` (comma-separated tag string) — see "Challenge" below on why this does *not* auto-create numeric goals | S |
| 6 | **Anything we should know** | Reuses existing free-text `allergies`/`conditions` fields + a chip-select of common concerns (blood pressure, cholesterol, blood sugar, thyroid, stress, digestion) | `HealthProfile.allergies/conditions` (existing) + **new** `HealthProfile.concernsRaw` | S |
| 7 | **Supplements & habits** | Chip-add from common presets (Vitamin D, Magnesium, Omega-3, Multivitamin, Iron, B12, Probiotic, Hydration, custom) | Creates **new** `Reminder` rows, `isAISuggested = false` (see §4) | M |
| 8 | **Privacy** (existing, unchanged, non-skippable) | Disclaimer acknowledgment | — | — |
| → | **Personalized preview** (activation moment, not a "step") | Nothing collected — this is the payoff screen | Reads back what was just entered | M |

### The activation moment (step "→")

Instead of dropping the user into an empty Dashboard, run `AnalysisEngine.generateReview(...)` immediately against whatever was just entered (even partial: weight+height alone yields a BMI finding; sleep alone yields a sleep finding) and show a **preview card built from the exact same `ScoreRing` + `glassCard()` the real Dashboard uses** — no new component, just the real one rendered one screen early. Underneath, a short recap: "Your reminders are set: Vitamin D, Magnesium, Hydration" and a single prominent `GlassProminentButtonStyle()` button: **"Enter Gemocode"**. This is the "wow" moment the brief asks for, and it costs almost nothing extra to build because it's assembled entirely from existing pieces. **Effort M, P1.**

### Data model changes (spec, not implemented)

Per CLAUDE.md's model-registration checklist, every new field/model touches four places: `Schema` in `GemocodeApp.swift`, `SampleData.eraseAllData`, `BackupService` (fields **optional**, matching the existing `goals: [BackupGoal]? = []` backward-compat pattern), and in-memory `ModelContainer` lists in tests.

- `HealthProfile` gains: `activityLevelRaw: String`, `dietPatternRaw: String`, `primaryGoalsRaw: String`, `concernsRaw: String` — all defaulted, all optional in `BackupProfile`. No new `@Model`, so no `Schema` change needed for this part.
- New `Reminder` + `ReminderCompletion` `@Model`s — full checklist item, see §4.

### Challenge: don't auto-create numeric goals from quiz answers

If step 5 ("lose weight") directly creates a `HealthGoal(targetValue: currentWeight * 0.95, ...)`, Gemocode would be inventing a clinical target with no basis — this is exactly the kind of prescriptive behavior the app's "educational, not diagnostic" stance exists to avoid, and it's a bad guess besides (5% is arbitrary). Instead: store the **intent tag** only, and surface a one-tap prompt card on the Dashboard/Goals screen — *"Set a weight goal → tap to configure"* — that deep-links into the existing, already-well-designed `AddGoalSheet` (`GoalsView.swift:136`) with the vital type pre-selected. The user supplies the actual number. **This is a case where the owner's implied "auto-personalize everything" instinct actively hurts UX/trust — propose the lighter-touch version.**

---

## 3. "Today" dashboard layout spec

All components below are either the *existing* `DashboardView` sections reused as-is, or new sections built strictly from `glassCard()` / `tintedGlassCard()` / `StatusPill` / `Glass.accentGradient` / the existing row idioms already present in `DashboardView.swift`, `ReviewScreen.swift`, and `GoalsView.swift`. Nothing here requires a new visual primitive.

```
[Custom header row — NOT the nav bar]
  "Good morning, {firstName}"        .title2.bold()      ← time-of-day aware, extends existing "Hi, {firstName}" logic
  Wed, July 12                        .subheadline .secondary  ← existing Date.now header, unchanged

[Hero card — restructured scoreCard, same glassCard()]
  ScoreRing(score)  +  "Health Overview"  +  scoreLabel
  "Today's reminders: 2 of 3 done"   ← new StatusPill-style capsule, teal when 100%
  (taps through to ReviewScreen — unchanged behavior)

[Today's Reminders — NEW card]
  Row per reminder: ○/✓ toggle · title · streak flame (only if streak ≥2) · "Suggested" StatusPill if AI-sourced
  Empty state inline: "No reminders yet — Add one"

[AI-suggested for you — NEW, only when a pending suggestion exists]
  tintedGlassCard(.purple), sparkles+accentGradient icon (same language as AI Summary card)
  "Vitamin D was flagged low in your last panel — some people discuss a supplement with their doctor."
  [Add reminder]  [Not now]

[Score History — existing scoreHistoryCard, unchanged]

[Biomarker cards — NEW, horizontal scroll]
  Reuses review.labSnapshots (already computed in ReviewScreen.labValuesCard) as compact glassCard() tiles:
  name · value · StatusPill(status) · tiny sparkline (same Chart-in-a-tile pattern as vitalsGrid)

[Today's Actions — NEW, personalized nudges]
  tintedGlassCard(color) rows, same shape as existing alertsSection, but proactive not reactive:
  "Log today's blood pressure" · "3 days since your last symptom check-in"
  Sourced from AnalysisEngine findings + gaps, not a new engine

[Needs Your Attention — existing alertsSection, unchanged]
[Next Appointment — existing appointmentCard, unchanged]
[Latest Vitals — existing vitalsGrid, unchanged]
[Goals — existing goalsCard, unchanged]

[Your Timeline — NEW entry point]
  Single glassCard() row, same shape as recentReportsSection rows: "See your full timeline →"
  Teaser: last 2-3 mixed events (report added, vital logged, reminder streak milestone)

[Recent Reports — existing recentReportsSection, unchanged for P1]
```

**Toolbar**: extend the existing `+` menu (`DashboardView.swift:64-80`, currently Add Report / Add Vital) with **Add Reminder** and reuse the existing Vision-OCR scan flow (`LabScanService.swift`) as a labeled "Scan a Report" entry — this *is* the "upload button" the brief asks for; it already exists, it just needs one more menu item. **Effort S, P1.**

### Density warning

That's up to 10 cards on one scroll. Recommend shipping Hero + Reminders + Alerts + Vitals + Goals + Timeline-teaser in **P1**, and holding Biomarker-cards-carousel + Today's-Actions for **P2** once real usage data shows which cards get engagement — premature density is itself an anti-premium trait (compare to Oura's intentionally sparse Today tab). Effort/phase for each new card is broken out in the table below.

| Component | Effort | Phase |
|---|---|---|
| Time-aware greeting header (replace nav-bar title with in-scroll header) | S | P1 |
| Hero card restructure (score + reminder completion capsule) | S | P1 |
| Today's Reminders card | M | P1 |
| AI-suggested-for-you card | M | P1 (depends on §4 suggestion source) |
| Biomarker horizontal carousel | M | P2 |
| Today's Actions (proactive nudges) | M | P2 |
| Timeline entry point (teaser only) | S | P1 |
| Full Timeline screen | L | P2 |
| Toolbar: Add Reminder + Scan a Report menu items | S | P1 |

---

## 4. Reminder system UX

### Data model (spec)

Reuse-vs-new decision: **do not** bolt supplements onto `Medication`. Medications carry dosage/frequency/pharmacological weight and feed `MedicationInteractions` (`Services/MedicationInteractions.swift`) — a real drug-drug interaction checker. Running "Hydration goal" or a 10-minute-walk habit through that engine either does nothing (harmless but confusing) or, worse, could imply a supplement was interaction-checked when it wasn't. Keep them separate:

- **New `Reminder` `@Model`**: `title`, `category` (supplement/hydration/habit/custom), `scheduleTime`, `isAISuggested: Bool`, `sourceLabKey: String?` (traceability — which biomarker triggered a suggestion), `createdAt`, `isArchived`, `reminderID` (mirrors `Medication.reminderID` for `NotificationService`).
- **New `ReminderCompletion` `@Model`**: `reminderID`, `date`, `completedAt` — a pure log, mirroring the existing `ScoreSnapshot` "at most one per day" pattern (`ScoreSnapshot`, `ReviewScreen.recordSnapshot`). Streaks are just a query over this table, not a stored counter.
- Both register in `Schema` (`GemocodeApp.swift`), `SampleData.eraseAllData`, `BackupService` (new optional `reminders: [BackupReminder]? = []` / `reminderCompletions: [...]? = []`, following the exact `goals: [BackupGoal]? = []` precedent already in `BackupService.swift:19`), and test `ModelContainer` lists.
- Notification scheduling reuses `NotificationService.scheduleDailyReminder` — recommend generalizing its `(medicationName:dosage:)` parameters to `(title:body:)` so both `Medication` and `Reminder` share one code path instead of duplicating the scheduling logic (engineering note, not a UX requirement).

### Creation flow

`AddReminderSheet`, a `Form` matching the existing `AddMedicationSheet`/`AddGoalSheet` shape exactly (Section "Reminder" → title picker with common-supplement chips + "Custom…" → Section "Schedule" → existing Toggle+DatePicker daily-reminder idiom, byte-for-byte the pattern already in `AddMedicationSheet.swift:232-243`). Entry points: `+` on the new Reminders card, and pre-filled from the onboarding quiz (§2 step 7) or from an accepted AI suggestion. **Effort M, P1.**

### Streaks & progress

- Reminder row: leading circular toggle (tap → `Haptics.success()` + insert/delete today's `ReminderCompletion`), trailing streak badge (`flame.fill` + count) shown only once streak ≥ 2 — showing "0" or "1" reads as pressure, not encouragement.
- Tapping a reminder opens a lightweight detail view: 4-week dot grid (7×4 `Circle()`s, filled = completed, empty outline = missed) — a small custom view built from primitives already in use, not a new charting dependency. Missed days render neutral gray, **never red** — this is a wellness/habit surface, not a compliance dashboard, and shaming imagery is a real health-anxiety risk in a medical-adjacent app.
- Aggregate completion shown once, on the Hero card ("2 of 3 done today"), not repeated per-card.

**Effort M, P1** (dot-grid detail view can slip to P2 if time-constrained; the checklist + streak badge is the P1-critical piece).

### AI-suggested vs. user-created — visual distinction

Extend the **existing** AI visual convention rather than inventing one: the AI Summary card (`ReviewScreen.aiSummaryCard`) already uses `sparkles` + `Glass.accentGradient` to mean "AI touched this." Reuse it:
- AI-suggested reminder row: leading icon badge uses `sparkles` + `Glass.accentGradient`, trailing `StatusPill(text: "Suggested", color: .purple)`.
- User-created reminder row: leading icon is the category glyph (pill/drop/figure.walk) in plain `.secondary`, no pill.
- Tapping the "i" on a suggested row reveals the *why*: "Suggested based on your last Vitamin D result (18 ng/mL, low)" plus the standard disclaimer line below.

### Disclaimer treatment

Never prescriptive. Match the tone already established in `Finding.recommendation` and `MedicationInteractions.disclaimer` — "ask your doctor/pharmacist," never "take X." Concretely:
- AI-suggested card copy: *"Vitamin D was flagged low in your last panel — some people discuss a supplement with their doctor. This is not medical advice."*
- A persistent, non-modal section footer on the full Reminders screen (same footer-under-Section pattern as `MedicationsView`'s "Possible Interactions" section, `MedicationsView.swift:45`), not a repeated per-toggle alert — footers earn trust by being present without nagging.

---

## 5. Premium polish checklist (ranked by perceived-value-per-effort)

| Rank | Item | Effort | Phase | Why it's high-leverage |
|---|---|---|---|---|
| 1 | Time-of-day personalized greeting header | S | P1 | Reuses existing `firstName` logic; purely a presentation change |
| 2 | Onboarding quiz ending on live `ScoreRing` preview | M | P1 | Single highest-impact activation-moment fix; assembled from existing components |
| 3 | Extend sparkles+accentGradient "AI-touched" language to reminders/suggestions | S | P1 | Zero new visual system, immediate consistency |
| 4 | Reminder-toggle haptic (light impact, distinct from existing `Haptics.success()`) | S | P1 | One new `Haptics` case; makes the daily-checklist interaction feel tactile |
| 5 | Warmer empty states reusing the onboarding frosted-circle+icon badge | S/M | P1 | Ties first-run visual language back into every empty state instead of default `ContentUnavailableView` glyphs |
| 6 | Segmented capsule progress bar for the quiz | S | P1 | Built from existing `Capsule`/`accentGradient`, replaces default page-dots |
| 7 | Pre-permission "soft ask" screen before the system notification prompt | S/M | P1 | Standard pattern to raise opt-in rates without feeling pushy; needed anyway once reminders exist |
| 8 | Dark-mode contrast pass on new purple "AI suggested" tint | S | P1 | `AmbientBackground` already branches on `colorScheme` — verify new tints match |
| 9 | Weekly dot-streak detail view per reminder | M | P2 | Real value, but secondary to the checklist itself |
| 10 | Biomarker horizontal carousel | M | P2 | Reuses `review.labSnapshots`, mostly a restyle |
| 11 | Health Timeline (full screen) | L | P2 | High value, high build cost — merges reports/vitals/symptoms/reminders into one feed |
| 12 | Score-improvement / streak-milestone micro-celebration | M | P2 | Delight, but must be scoped carefully — see Challenge below |
| 13 | Widget deep-link into Reminders | M | P2 | Must keep `WidgetSnapshot`/`WidgetVital` structs in the app and extension in sync per CLAUDE.md's widget contract note |
| 14 | Full dashboard card reordering/customization | L | P3 | Nice-to-have, not urgent pre-launch |
| 15 | Custom illustrated icon pack | — | Rejected | See Challenge below |

**Challenge: celebratory motion (confetti, etc.) must be scoped to wellness-only triggers** — score crossing into a better bracket, a reminder streak milestone. Never trigger celebratory animation adjacent to a *critical* finding context (e.g., don't let a streak-complete confetti fire on the same screen as a new critical lab flag) — would read as tone-deaf in a medical-adjacent app.

**Challenge: reject a custom illustrated icon pack.** CLAUDE.md is explicit about "zero third-party dependencies," and Gemocode's icon language today is 100% SF Symbols. A bespoke icon set adds asset-pipeline overhead and drifts from that constraint for a cosmetic gain. SF Symbols already support hierarchical/multicolor rendering modes that can add richness (e.g., `flame.fill` in `.hierarchical` for streaks) without breaking the dependency-free posture.

---

## 6. AI chat surface (P2 spec)

### Entry points

Do **not** add a 6th tab. The existing AI Summary card is inline and opt-in-gated (`ReviewScreen.aiSummaryCard`, only rendered `if !anthropicAPIKey.isEmpty`) — chat should follow the same pattern: a card on the Today dashboard (below the AI-suggested-reminders card) and/or a toolbar affordance on `ReviewScreen`, both opening a `.sheet`. If no key is configured, show a "Set up AI features" prompt linking to Profile & Settings, exactly like the existing gating.

### Message UI

Reuse `glassCard()` for assistant bubbles (left-aligned, `sparkles`+`Glass.accentGradient` avatar badge — the established "AI touched this" marker) and a lighter `tintedGlassCard(.blue)` or plain right-aligned text for user messages. Stream tokens progressively; apply the same `stop_reason == "refusal"` check already implemented in `AISummaryService.swift:121` before rendering content — on refusal, show a calm inline bubble ("I can't help with that — worth asking your doctor directly") rather than a raw error string.

### Citation-of-your-own-data pattern (the differentiating feature)

Whenever the assistant references a specific value, render it as a tappable inline chip styled like `StatusPill` (e.g., `Vitamin D · 18 ng/mL · Low`) that deep-links to the existing `LabDetailView`/`VitalsView` for that metric — exactly mirroring how `ReviewScreen.labValuesCard` rows already push to `LabDetailView`. This grounds every claim in a value the user can independently verify on-device, which matters more for trust in a medical-adjacent chat than in a generic assistant. Treat this as a **hard requirement** for P2 chat, not a stretch goal — an AI chat over health data with no verifiable grounding is a credibility risk for the whole app.

### Challenge: don't send raw report attachments/OCR text by default

The brief says "AI chat about your reports." Taken literally, that risks piping raw PDFs/photos (and their OCR'd text, which can include provider names, facility addresses, etc. beyond what's medically relevant) to a third-party API. `AISummaryService` today deliberately sends only structured review text, never documents (`ProfileView.swift:146`: "only the review text is sent to Anthropic — never your documents or database"). The chat surface must preserve that boundary: it should operate over the same structured data the engine already extracts (`LabResult` values, `VitalSample`s, `Finding`s), never raw attachment bytes, unless a user explicitly attaches one specific report to one specific message with a visible per-message consent affordance. Extend, don't loosen, the existing privacy posture.

### Additional spec notes

- **Persistence**: new local-only `ChatSession`/`ChatMessage` `@Model`s (never uploaded except as the per-message API call itself), included in `Schema`, `SampleData.eraseAllData`, and `BackupService` per the standard checklist — consistent with the app's local-first philosophy of not silently dropping user content on relaunch.
- **System prompt**: extend `AISummaryService.systemPrompt`'s guardrails (`AISummaryService.swift:40-48`) — never diagnose, never suggest medication/treatment changes, always close with a discuss-with-clinician reminder — into the chat system prompt as well.
- **One-time disclosure sheet** before first chat use, listing exactly what's sent per message, matching the transparency bar already set for AI Summary.

**Effort L, Phase P2** (entry points + basic Q&A M; citation-chip grounding + attachment-consent flow is what pushes it to L).

---

## Summary table: everything by phase

**P1 (0–6 wks)**: consolidated 1-page welcome, 6-step quiz seeding real `HealthProfile`/`VitalSample`/`Reminder` data, live-score activation preview, time-aware greeting, Hero card restructure, Today's Reminders checklist + streak badges, AI-suggested-reminder card (visual language only — suggestion *source* logic can be a simple rule off existing `Finding`s), Timeline entry-point teaser, toolbar Add Reminder/Scan menu items, haptic/empty-state/dark-mode polish items.

**P2 (6–16 wks)**: full Health Timeline screen, biomarker carousel, Today's Actions nudges, weekly dot-streak detail, score/streak micro-celebration (scoped), widget reminder deep-link, AI chat (entry point, streaming, citation chips, attachment-consent flow, local persistence).

**P3 (later)**: dashboard card customization/reordering, any IA consolidation of the 5-tab/More structure (flagged as a real option — e.g. merging Trends into Review under a segmented control to free a tab slot — but deferred: it touches the `gemocode://review` / `gemocode://trends` widget deep-link routes in `ContentView.onOpenURL` and shouldn't be bundled with the reminders/quiz launch).

---

# Part 3 — AI engineering: the Health Analyst pipeline

# Gemocode AI Roadmap — "AI Health Analyst" Pipeline Design

**Author:** AI engineering analysis (design-only, no repo files modified)
**Scope:** Owner's new AI direction for Gemocode (iOS 17+, local-first, SwiftUI + SwiftData)
**Grounding:** `Gemocode/Services/AISummaryService.swift`, `Gemocode/Services/AnalysisEngine.swift`, `Gemocode/Models/LabCatalog.swift`, `Gemocode/Models/Models.swift`

---

## 0. Where we start from (current state, precisely)

- `AISummaryService.swift` today: opt-in, user-supplied API key (`UserDefaults` key `anthropicAPIKey`), calls `POST /v1/messages` directly from the app with `model = "claude-opus-4-8"`, `max_tokens = 1024`, a single system prompt, and **one user message containing `review.shareText`** — a pre-formatted plain-text blob (score, findings, trends, disclaimer already joined with `\n`). The model is asked to rewrite that blob as free prose. There is no structured output, no prompt caching, no numeric verification, and the "structure" the app renders is whatever markdown-free text comes back. It does correctly check `stop_reason == "refusal"` before reading `content` — that pattern carries forward.
- `AnalysisEngine.generateReview(...)` is the deterministic core and already computes almost everything the new AI features need as *facts*: `HealthReview` (score 0–100, `scoreLabel`, `findings: [Finding]`, `trends: [TrendInsight]`, `labSnapshots: [LabSnapshot]`), ACC/AHA `BloodPressureCategory`, BMI category, lipid ratios, and a least-squares `trend(points:range:)` classifier (`improving`/`worsening`/`stable`/`rising`/`falling`, needs ≥3 points, 5% stability band). `Finding` carries `severity` (`info`/`attention`/`critical`), `category` (`labs`/`vitals`/`trends`/`medications`/`general`), `title`, `detail`, and an optional `recommendation`. None of this is currently serialized to JSON anywhere — it only feeds SwiftUI views and the flattened `shareText`.
- `LabCatalog.swift` / `LabSynonyms.swift`: 46 `LabReference` entries with sex-specific ranges, `criticalLow`/`criticalHigh`, and plain-language `lowMeaning`/`highMeaning`/`about` strings — this is a ready-made, already-vetted "lab reference context" block that can be reused verbatim in prompts (no need to have the LLM explain what ALT or eGFR *is* from its own knowledge — the app already has curated text for that).
- `HealthProfile` has `sex`, `age` (computed from `dateOfBirth`), `heightCm`, `bloodType`, `allergies` (free text), `conditions` (free text) — thin but sufficient for the schema below.
- **Governing principle for everything that follows:** the deterministic engine is the source of every number and every clinical judgment (severity, category, direction); the LLM's job is narration, synthesis, and organization only. If the AI call fails for *any* reason — network, refusal, malformed JSON, failed verification — the app falls back to the existing rule-based `shareText`-style narrative, which must keep working with zero AI dependency, exactly as today.

---

## 1. Flagship "AI Health Analyst Report" pipeline

### 1.1 Structured input schema (JSON sent to Claude)

Replace the single `review.shareText` string with a typed payload assembled by a new `AIReportContextBuilder` (pure function, same testability pattern as `AnalysisEngine` — takes a `HealthReview` + history + `now`, returns `Codable` structs, no `Date()` inside). Every field traces to an existing model/engine type:

```json
{
  "schema_version": "1.0",
  "generated_at": "2026-07-12T00:00:00Z",
  "profile": {
    "age": 42,
    "sex": "male",
    "height_cm": 178.0,
    "conditions": ["hypertension"],
    "allergies": ["penicillin"]
  },
  "score": { "value": 78, "label": "Good" },
  "biomarkers": [
    {
      "id": "totalCholesterol",
      "name": "Total Cholesterol",
      "short_name": "TC",
      "category": "lipidPanel",
      "value": 210.0,
      "unit": "mg/dL",
      "date": "2026-06-01",
      "status": "high",
      "range": { "low": 125.0, "high": 200.0 },
      "is_critical": false,
      "previous": {
        "value": 195.0,
        "date": "2025-12-01",
        "percent_change": 7.7,
        "status_changed": false,
        "crossed_boundary": true
      }
    }
  ],
  "vitals": [
    { "type": "bloodPressure", "systolic": 132.0, "diastolic": 84.0,
      "category": "stage1", "date": "2026-06-01" }
  ],
  "trends": [
    { "metric": "totalCholesterol", "unit": "mg/dL", "direction": "worsening",
      "percent_change": 7.7, "point_count": 4 }
  ],
  "findings": [
    { "id": "f1", "severity": "attention", "category": "labs",
      "title": "Total Cholesterol Elevated",
      "detail": "210 mg/dL, above the 200 mg/dL reference ceiling.",
      "recommendation": "Discuss lipid management with your doctor." }
  ],
  "medications": [
    { "name": "Lisinopril", "dosage": "10mg", "frequency": "daily", "active": true }
  ],
  "interactions": [],
  "symptoms_recent": [],
  "timeline_events": [ /* see §2 */ ]
}
```

Notes that matter for the guards in §1.3:

- **`findings[].id` must be a request-scoped ordinal (`"f1"`, `"f2"`, …), not `Finding.id` (a Swift `UUID` regenerated on every `generateReview()` call).** The current `UUID` is meaningless across requests; a stable per-request string ID is what lets the model *cite* a finding rather than restate it, and lets the app verify the citation.
- `biomarkers[].id` is the existing `LabReference.id` / `catalogID` (or a slugified `customName` for non-catalog entries) — already a stable string key in `LabResult.catalogReference`.
- `previous` is only present when a prior reading of the same `seriesKey` exists — absent, not `null`, so the schema (and the LLM) can't hallucinate a delta that doesn't exist.
- The payload intentionally contains **no OCR text, no attachment bytes, no free-text report notes** — this is a structural anti-prompt-injection property, not just a privacy one (see §6).

**Effort: M · Phase: P1.** Mostly a serialization layer over existing `AnalysisEngine` output; no new clinical logic.

### 1.2 System prompt design

Persona and hard rails (draft, to be refined with legal/clinical review before shipping — flag this explicitly to the owner):

> You are the user's personal AI health analyst inside Gemocode, a local-first health tracker. You will receive a JSON object containing the user's profile, biomarker values, vital signs, medications, and a set of findings **already computed by a deterministic clinical rules engine** — you did not compute these, and you must not recompute, re-derive, or contradict them.
>
> Hard rules:
> 1. **Never diagnose.** Do not state or imply the user has a specific condition. Describe values relative to reference ranges only ("above the typical range for X"), never as "this means you have Y."
> 2. **Never prescribe or adjust treatment.** Do not recommend starting, stopping, or changing a dose of any medication.
> 3. **Every number you write must appear in the input JSON**, unchanged. Do not compute new percentages, averages, or projections.
> 4. **Every risk indicator you produce must cite a `findings[].id` from the input.** Do not introduce a risk indicator that has no corresponding engine finding.
> 5. Always close with a "Questions for your doctor" section containing at least 3 specific, personalized questions.
> 6. Use warm, plain-language, non-alarmist tone. This is educational, not diagnostic — and the disclaimer already displayed in the app applies to everything you write.
> 7. If asked (via any surrounding context) to diagnose, prescribe, or predict a specific future medical outcome, decline that part and redirect to "ask your doctor," continuing to answer the parts of the request that are in scope.

Required output sections (enforced by the schema in §1.3, not by prompt text alone): `overall_summary`, `biomarker_explanations[]`, `risk_indicators[]`, `personalized_recommendations[]`, `doctor_questions[]` (min 3), `whats_new_since_last_test[]` (present only if `biomarkers[].previous` exists anywhere in input).

**Effort: S · Phase: P1.**

### 1.3 Output contract — structured JSON, not a markdown blob

Use `output_config.format` (`json_schema`, GA on Opus 4.8, Sonnet 5, Haiku 4.5, Fable 5) so formatting is fully app-controlled — the app renders each section with its own SwiftUI view (a "Biomarker Explanation" card, a "Questions for Your Doctor" list row, etc.), matching the existing `.glassCard()` / `StatusPill` design system rather than dumping prose into a `Text` view. Sketch of the schema (trimmed):

```json
{
  "type": "object",
  "additionalProperties": false,
  "required": ["overall_summary", "biomarker_explanations", "risk_indicators",
               "personalized_recommendations", "doctor_questions"],
  "properties": {
    "overall_summary": { "type": "string" },
    "biomarker_explanations": {
      "type": "array",
      "items": {
        "type": "object",
        "additionalProperties": false,
        "required": ["biomarker_id", "explanation"],
        "properties": {
          "biomarker_id": { "type": "string" },
          "explanation": { "type": "string" }
        }
      }
    },
    "risk_indicators": {
      "type": "array",
      "items": {
        "type": "object",
        "additionalProperties": false,
        "required": ["source_finding_id", "plain_language_summary"],
        "properties": {
          "source_finding_id": { "type": "string" },
          "plain_language_summary": { "type": "string" }
        }
      }
    },
    "personalized_recommendations": { "type": "array", "items": { "type": "string" } },
    "doctor_questions": { "type": "array", "items": { "type": "string" } },
    "whats_new_since_last_test": { "type": "array", "items": { "type": "string" } }
  }
}
```

`risk_indicators[].source_finding_id` is the load-bearing field: it forces every risk statement to be traceable to an engine-computed `Finding`, turning "does not diagnose" from a prompt request into a structurally checkable contract.

**Effort: M · Phase: P1.**

### 1.4 Refusal & hallucination guards

1. **Refusal check** (already the pattern in `AISummaryService`): branch on `stop_reason == "refusal"` before reading `content`; on refusal, fall back (see §1.5). Read `stop_details.category` for local (non-PII) logging only.
2. **Structural echo-check:** every `risk_indicators[].source_finding_id` must exist in the request's `findings[]` array. Any indicator citing an unknown ID → reject the whole response (don't silently drop one field — a partial contract violation signals the model didn't follow the input, and per-field patching risks shipping a half-hallucinated report).
3. **Numeric echo-check:** extract every numeric token from `overall_summary`, `biomarker_explanations[].explanation`, `risk_indicators[].plain_language_summary`, and `whats_new_since_last_test[]`; build the allow-set from every number present in the input JSON (biomarker values, ranges, percent changes, score, ages, medication counts), rounded to the same precision the app displays (e.g. one decimal). Reject any output number not in the allow-set, with small tolerance for legitimate rounding (210.0 in input, "210" in output — fine; "215" — reject). This is a cheap regex + set-membership pass, no second model call needed.
4. **Schema/shape validation:** `doctor_questions.count >= 3`; every array section non-empty (an empty `risk_indicators` is valid when there are truly no findings — but that must match `findings.isEmpty`, another structural check).
5. **On any guard failure:** fall back to the existing deterministic `HealthReview.shareText`-derived narrative (today's non-AI experience). Never show a partially-verified AI report. Log (locally, non-content) which guard tripped, for the golden-set eval in §4 to catch drift.

**Effort: M · Phase: P1** (guards are pure Swift, testable exactly like `AnalysisEngineTests` — feed synthetic `HealthReview` + a mocked malformed response, assert fallback triggers).

---

## 2. Historical comparison & timeline

### 2.1 What the client computes locally (deterministic, already 80% present)

- **Per-biomarker series:** `AnalysisEngine` already groups `LabResult` by `seriesKey` and sorts by date (`generateReview`'s lab-results block) and has `slopePerDay` / `trend(points:range:)` (≥3 points, 5% stability band, distance-from-range comparison for improving/worsening). Reuse this unchanged for the timeline's trend arrows — no new regression logic needed.
- **Significant-change detection** — new, concrete thresholds to add to the engine (pure functions, unit-testable the same way `bloodPressureCategory`/`bmiCategory` are):
  1. **Boundary crossing** — `LabStatus` differs between the two most recent readings of the same series (e.g. `.normal → .high`). Always significant, regardless of magnitude.
  2. **Critical crossing** — new status is `.criticalLow`/`.criticalHigh` and previous wasn't. Always significant; always surfaces even if §1's numeric echo-check would otherwise suppress a small delta.
  3. **Relative shift** — `>20%` change vs. the prior reading of the same series (reuses `AnalysisEngine.trend`'s existing `percentChange` calculation), *even when still in-range*. Guard against near-zero baselines the same way `trend()` already does (`abs(first.value) > 1e-9`) — suppress the percent-shift rule below that epsilon and fall back to boundary-crossing only.
  4. **New flag** — previous status was `.normal`/`.unknown`, latest is any out-of-range status. (Overlaps rule 1 but stated separately because it's the most product-relevant framing: "first time this has been flagged.")
  5. **Vitals — category crossing, not %.** For blood pressure specifically, the clinically meaningful "significant change" is an ACC/AHA category boundary crossing (`elevated → stage1`, etc. via `AnalysisEngine.bloodPressureCategory`), not a raw percent change on the number.
- **Timeline events** — a new `TimelineEvent` type merging: lab significant-changes (above), medication start/stop (`Medication.startDate`/`endDate`), appointments (`Appointment.date`), score deltas (`ScoreSnapshot` history — already recorded, "at most one per day"), and symptom spikes (`SymptomEntry.severity` jump). Each event is `{date, type, subject, from_value?, to_value?, direction, severity}` — fully deterministic, renders with a template caption **even with zero AI availability** (e.g. "Total Cholesterol rose from 195 to 210 mg/dL (+7.7%), crossing into High range" — string-templated from the event struct, no LLM required).

**Effort: M · Phase: P1** (thresholds + `TimelineEvent` type + template captions — no AI dependency, ships value standalone).

### 2.2 What the LLM narrates

Only the **caption tone/framing** for each already-computed `TimelineEvent`, plus an optional "narrative connective tissue" summary across the merged timeline (e.g. noticing that a medication start correlates with a lab improvement two months later). This is a *smaller* structured-output call (reuse the same numeric-echo-check machinery from §1.4 — the allow-set is just the timeline events' own numbers) — one caption per event, or a batched call captioning the last N events at once to save round-trips. **Use Haiku here** (§4) — captions are short, low-stakes, high-volume.

**Effort: S · Phase: P2** (depends on §2.1 shipping first; the deterministic timeline is the P1 deliverable, AI captions are the enhancement layer).

---

## 3. AI chat about your reports

### 3.1 Retrieval without a vector DB

The corpus is genuinely tiny — a power user with years of data has, at most, low hundreds of lab results and a few dozen reports. This does not need embeddings, chunking, or a vector store; it needs **context stuffing** with a size cap:

- **Static context block** (cached, see §4): profile + one row per unique biomarker (latest value/status/range) + last ~5 `HealthReview` scores/summaries + active medications + recent symptoms + open (non-resolved) findings. For nearly all users this is well under 5–10K tokens.
- **On-demand deep-dive tool** for the long tail: a client-side tool `get_biomarker_history(biomarker_id)` that returns the *full* time series for one test, only called when the user's question needs it (e.g. "how has my cholesterol trended over the last 3 years"). This is the cheap non-vector-DB substitute for retrieval — the model decides what it needs and asks for it, instead of the app guessing what to stuff up front. Bounds token growth for the rare heavy-history user without penalizing the common case.
- Everything served from this tool is still deterministic engine output (the same `LabSnapshot`/series data as §1–2) — the chat feature inherits the hybrid-pattern guarantee, it never becomes a free-text-in-free-text-out surface.

**Effort: M · Phase: P2.**

### 3.2 Conversation memory policy

- Scope memory to the **current chat session only**, stored locally (SwiftData, same on-device-only model as everything else in the app — no server-side memory store, which would require retention infrastructure the app deliberately doesn't have per `CLAUDE.md`).
- No cross-session memory by default (a new chat starts fresh); if the owner wants continuity, expose it as an explicit "reference my last conversation" action rather than silent persistence, keeping the local-first / no-hidden-state posture.
- Cap transcript length (e.g. ~20 turns) and prune the oldest turns rather than building a compaction/summarization pipeline — at this conversation scale, pruning is simpler and cheap; revisit only if usage data shows long sessions are common.

**Effort: S · Phase: P2.**

### 3.3 Scope guard

System-prompt rule: the assistant may only discuss the user's own data present in context (or fetchable via the history tool); general medical-knowledge questions unrelated to the user's data get redirected to "ask your doctor / pharmacist" framing rather than answered from the model's general training. This is a policy choice worth flagging explicitly to the owner: it trades away some of the "helpful health chatbot" appeal for a materially lower liability surface, consistent with the app's existing educational-not-diagnostic stance. Recommend keeping the guard strict for P2 launch; loosen only with legal sign-off.

**Effort: S · Phase: P2.**

### 3.4 Cost per conversation

Using Sonnet 5 introductory pricing ($2/$10 per MTok input/output through 2026-08-31; $3/$15 standard) with prompt caching on the static context block:

| Turn | Input tokens | Output tokens | Approx. cost |
|---|---|---|---|
| First turn (cache write) | ~1.5–3K | ~300–500 | ~$0.01 |
| Subsequent turns (cache read) | ~1.5–3K (mostly cached @ ~0.1×) + new question | ~300–500 | ~$0.002–0.004 |
| 10-turn conversation | — | — | ~$0.02–0.05 |

**Effort: —, informational.**

---

## 4. Model & cost strategy

| Feature | Model | Why |
|---|---|---|
| Flagship AI Health Analyst Report (§1) | `claude-opus-4-8` | Highest-stakes, run infrequently (per new report / on-demand), needs the strongest synthesis quality over 10–20 biomarkers plus multi-finding reasoning. Use adaptive thinking + `output_config.effort: "high"` (Opus 4.8's default and sweet spot — no need for `xhigh`/`max` on a well-specified, schema-constrained task). |
| Chat about reports (§3) | `claude-sonnet-5` | Near-Opus quality at ~⅓ the price, appropriate for conversational latency and volume; supports the full `low`–`max` effort range and structured outputs. |
| Timeline captions (§2.2) | `claude-haiku-4-5` (alias `claude-haiku-4-5`; pin the dated ID `claude-haiku-4-5-20251001` only if the eval harness in §4.3 needs snapshot reproducibility across model updates) | High-volume, low-stakes, short outputs — Haiku's cost/latency profile is the only one that makes per-event captioning affordable at scale. |

### 4.1 Prompt caching strategy

The highest-leverage caching decision is architectural, not a `cache_control` placement detail: **route all AI calls through the backend proxy (already on the roadmap per the backend track), not directly from each device.** A per-device call (today's `AISummaryService` pattern) can only cache within one user's own session; a backend proxy funnels every user through the same Anthropic account, so the **system prompt + the static LabCatalog reference block is byte-identical across all users on a given app build** and its cache entry is reused organization-wide, not just per-user. That turns caching from a marginal per-user optimization into the dominant cost lever for the whole feature.

- Cache breakpoint 1 (5-min or 1-hour TTL, tune to observed request cadence): system prompt (§1.2) + a condensed reference sheet drawn from `LabCatalog` (only the `about`/`lowMeaning`/`highMeaning` text for tests appearing across the fleet's common panels — or the full 46-entry catalog if it comfortably clears the ~4K-token minimum cacheable prefix for Opus-tier models).
- Everything per-user (the §1.1 JSON payload) goes **after** the breakpoint — it must never be interpolated into the cached prefix (matches the general caching rule: stable content first, volatile content last).
- Chat (§3): cache the static context block per session; the free-form question always goes after the breakpoint.

### 4.2 Token budgets (draft)

| Call | Cached (system+reference) | Uncached (per-request) | Output |
|---|---|---|---|
| Flagship report | ~2–3K | ~0.8–1.5K | ~1.5–2.5K (structured JSON) |
| Chat turn | ~1–2K | ~0.05–0.2K | ~0.3–0.5K |
| Timeline caption (batched) | ~0.5K | ~0.2–0.5K | ~0.1–0.3K |

### 4.3 Streaming

Because the flagship report's output is schema-validated structured JSON, partial/streamed JSON is not independently renderable mid-stream — stream primarily to avoid the SDK's non-streaming timeout guard on large `max_tokens`, not for progressive text reveal. The better UX lever is the hybrid architecture itself: **the deterministic score/findings/trends render instantly with zero AI latency** (they're already computed locally), and the AI narrative sections populate asynchronously into the same screen once the call completes — the user is never blocked on the network for the core experience, only for the narrative enhancement layer.

### 4.4 Golden-set eval (CI quality gate)

Mirrors the project's existing "CI is the only real compiler" posture (`CLAUDE.md`) — a live-model eval can't run per-PR (cost, latency, non-determinism), so the practical gate is **recorded-fixture replay**:

- Build ~30 synthetic `HealthReview` profiles covering: healthy baseline, borderline lipids, diabetic-pattern glucose/A1c, hypertension stages 1–3 (crisis included), renal-impairment markers, thyroid abnormal (hyper/hypo), anemia, elevated inflammation markers, drug-interaction scenarios (reuse `MedicationInteractions` fixtures), multi-condition combinations, sparse-data edge cases (single report, no prior history), and adversarial/garbage OCR-derived values (see §6).
- Assert **properties**, not exact text: numeric echo-check passes; structural echo-check passes (every `risk_indicators[].source_finding_id` resolves); `doctor_questions.count >= 3`; no diagnostic-verb patterns for any condition ("you have," "this indicates you are diabetic"); disclaimer field present; response references every `findings[]` entry from the input at least once (coverage, not fabrication).
- Record real API responses once per fixture, replay them in per-PR CI (deterministic, free, fast); re-run **live** against the current model on a scheduled cadence (e.g. weekly) to catch model-behavior drift, flagged to a human rather than auto-failing PRs.

**Effort: L · Phase: P1** (the fixture set + property assertions are the bulk of the work; wire into CI as a new job alongside `xcodebuild test`).

---

## 5. Ranking the owner's speculative features

| Feature | Verdict | Reasoning | Effort | Phase |
|---|---|---|---|---|
| AI chat about your reports | **Keep** | Natural extension of the hybrid architecture; tiny corpus means no vector-DB investment; scope-guarded to the user's own data. | M | P2 |
| Predictive trends | **Reshape** | Kill literal forecasting — extrapolating a future lab value from 2–4 points/year is statistically unjustified and reads as a medical prediction (real liability risk if wrong). Keep the *existing* deterministic `AnalysisEngine.trend()`/`slopePerDay` regression; let the LLM only narrate an already-established trend ("if this trend continues, ask your doctor whether more frequent monitoring makes sense") — never project a numeric future value. | S (mostly copy/prompt work, reuses existing engine) | P2 |
| Nutrition / meal suggestions | **Kill (for now)** | Value only exists if advice is personalized to specific abnormal biomarkers (e.g. "your sodium is high, eat less salt") — but that's exactly where it drifts into personalized medical/dietary prescription, and is actively dangerous if wrong for conditions like CKD or diabetes. Generic, non-personalized wellness tips have low differentiation and don't need an LLM at all. Revisit only with a registered-dietitian content review process behind it. | — | Not before P3, contingent on clinical review |
| Sleep / fitness suggestions | **Kill (for now)** | Same failure mode as nutrition — conditioning recommendations on lab values (cardiac markers, thyroid, etc.) drifts into personalized medical guidance; generic version has even lower differentiation than nutrition. | — | Not before P3, contingent on clinical review |
| Voice assistant | **Kill / defer indefinitely** | High build cost (new input modality, transcription, latency, accessibility QA) for unclear incremental value over the text chat (§3) — and voice specifically raises the risk of a misheard critical value or medication name in a health context, where the text chat lets the user visually verify before sending. If demand emerges, the right shape is dictation-to-text-then-review on top of the existing chat, not a full voice conversation loop. | — | Not scheduled |
| Document organizer (AI auto-categorize/tag imports) | **Keep / reshape** | Best value/effort ratio of the speculative list: sits inside the existing OCR + `LabScanService` pipeline, is deterministic-friendly (dates, provider names, category classification from document structure — the same "curated, testable" pattern as `LabCatalog`), and is organizational metadata, not clinical narrative, so the risk profile is low. Ship the deterministic heuristic classifier first; an optional Haiku-assisted classification pass for ambiguous cases is a cheap P2 add-on, not a prerequisite. | S (deterministic) / S (AI-assisted add-on) | P1 (heuristic) → P2 (AI-assisted) |

---

## 6. Safety & quality

### 6.1 Adversarial inputs

- **OCR garbage / absurd values.** Every value entering the AI pipeline already passed through `AnalysisEngine.status(value:range:criticalLow:criticalHigh:)`, so a badly-OCR'd value (e.g. a stray digit inflating glucose to `9999`) already surfaces as an extreme `.criticalHigh` flag — good, but the engine currently has no concept of *physiological implausibility* distinct from *clinically critical*. Add a `plausibilityRange` to `LabReference` (a wide outer bound clearly beyond any real clinical presentation, e.g. glucose > 2000 mg/dL) so the engine — and by extension the AI pipeline — can flag "this value looks like a data-entry or scan error, please verify" instead of the LLM narrating a wildly wrong number as clinical fact. This belongs in the deterministic layer, not as an LLM instruction: the numeric echo-check (§1.4) stops the model from *inventing* a different number, but does nothing to stop it from narrating a garbage-but-present number as meaningful — only an upstream plausibility gate does that.
- **Prompt injection via document text.** The flagship report pipeline structurally cannot be injected through a malicious/glitched OCR'd document, because the LLM is never shown raw document/OCR text — only the engine's numeric/categorical output (§1.1). Call this out as a security property of the hybrid architecture itself, in contrast to a naive "send the whole document to Claude" design. The one surface where this protection doesn't automatically extend is a *future* chat feature that lets a user ask about a specific document's raw text — flag that as an open risk to design for explicitly if/when it's built (e.g. treat fetched document text as low-trust data, not instructions, via the same discipline used for any untrusted tool output).

**Effort: S (plausibility range) · Phase: P1.**

### 6.2 Disclaimer placement

`HealthReview.disclaimer` already exists and is appended once, at the bottom of the flattened `shareText`. Promote it to a first-class, app-rendered element (not LLM-generated, not just export-time text) that's contractually present on every AI-touched surface: report view, chat view, timeline view, share sheet, PDF export. Concretely: a persistent header banner ("AI-assisted educational content, not medical advice") plus the full disclaimer footer, driven by a local string resource the AI response schema doesn't even carry — removing any dependency on the model to remember to include it.

**Effort: S · Phase: P1.**

### 6.3 Logging policy

No health content in logs, matching the app's local-first ethos even as a backend proxy is introduced. Concretely: log only structural signals — timestamp, model used, token counts, latency, HTTP status, `stop_reason`, whether the numeric/structural echo-check passed, whether fallback triggered. Never log biomarker values, chat message text, or LLM response text, in either the client or the backend proxy, in debug builds or crash/analytics reporting. If/when the backend proxy ships, it should be a pure relay — forward the already-built request, don't persist request/response bodies beyond the ephemeral handling needed to serve the call — so introducing a backend doesn't quietly turn "no backend, no accounts, all data on-device" into "no backend, no accounts, except the AI logs."

**Effort: S · Phase: P1** (policy + a short allowlist of loggable fields, enforced in code review / a lint rule if the codebase has one).

---

## Summary table — effort × phase

| # | Item | Effort | Phase |
|---|---|---|---|
| 1.1 | Structured input schema (`AIReportContextBuilder`) | M | P1 |
| 1.2 | System prompt + hard safety rails | S | P1 |
| 1.3 | Structured output contract (`output_config.format`) | M | P1 |
| 1.4 | Refusal / structural / numeric guards + fallback | M | P1 |
| 2.1 | Significant-change thresholds + deterministic timeline | M | P1 |
| 2.2 | AI timeline captions (Haiku) | S | P2 |
| 3.1 | Chat context stuffing + history tool | M | P2 |
| 3.2 | Conversation memory policy (session-scoped, capped) | S | P2 |
| 3.3 | Chat scope guard | S | P2 |
| 4.4 | Golden-set eval (30 fixtures, CI replay) | L | P1 |
| 5 | Predictive trends (reshape, no forecasting) | S | P2 |
| 5 | Document organizer (deterministic → AI-assisted) | S / S | P1 → P2 |
| 5 | Nutrition, sleep/fitness, voice assistant | — (kill/defer) | Not before P3 / not scheduled |
| 6.1 | Lab-value plausibility range | S | P1 |
| 6.2 | First-class disclaimer placement | S | P1 |
| 6.3 | No-health-content logging policy | S | P1 |

---

# Part 4 — Backend: the AI relay, auth, metering, scale

# Gemocode AI Proxy Backend — Architecture & Roadmap

**Author context:** Backend/platform design for pivoting Gemocode's AI layer from
BYO-key/on-device-only to an owner-funded, server-relayed model, while preserving
the app's local-first health-data guarantee. Analysis only — no repo files were
modified. Two files were read to ground this design in the actual client
implementation: `Gemocode/Services/AISummaryService.swift` and
`Gemocode/Models/Models.swift`.

**What the current code already does right** (worth knowing before proposing
changes): `AISummaryService.summarize(_:)` does **not** send the raw SwiftData
graph or attachments to Anthropic. It sends `HealthReview.shareText` — a
plain-text rendering the on-device `AnalysisEngine` already computed (score,
severity-graded findings with title/detail/recommendation, trend summaries,
disclaimer). The score/findings/trends are *derived*, not raw free text. That's
most of the way to the "structured payload, not raw documents" principle this
plan asks for — the remaining gap is that `shareText` is a flattened string
built for human reading, not a typed JSON payload the server fully controls
(more on this in §2/§3). The engine's `stop_reason == "refusal"` check
(`AISummaryError.refused`) is also already correct and should carry forward
unchanged into the proxy design.

---

## 0. Executive summary of the shape of the system

```
┌─────────────┐   HTTPS + JWT    ┌────────────────────┐   HTTPS + owner's    ┌──────────────┐
│  Gemocode   │ ───────────────▶│  Stateless AI relay │ ───────────────────▶│  Anthropic    │
│  iOS client  │◀─── SSE stream ─│  (Cloudflare Worker) │◀── SSE stream ──────│  Messages API │
└─────────────┘                  └─────────┬──────────┘                      └──────────────┘
                                            │
                                  ┌─────────▼──────────┐
                                  │  Postgres (Neon)    │
                                  │  usage ledger,       │
                                  │  entitlements,        │
                                  │  ephemeral chat ctx    │
                                  └────────────────────┘
```

The backend is a **relay, not a data store**. It sees one request's worth of
structured biomarker data at a time, forwards it to Anthropic under the
owner's key, streams the answer back, and persists only *metadata* (token
counts, cost, timestamps) plus, for the future chat feature, a short-lived
session context that auto-expires. No health record ever lands in Postgres.

---

## 1. AI proxy backend — phased design

### 1.1 Stack decision

**Primary: Cloudflare Workers + Neon (serverless Postgres via Hyperdrive) + Durable Objects.**
**Fallback: Fly.io (Machines) + Fly Postgres**, adopted only if/when P3 workloads
need long-running processes Workers can't do cleanly (queue-consumer batch
jobs, WebSocket-heavy multi-agent sessions).

Rationale for Cloudflare Workers as primary:

- **Streaming is native.** A Worker's `fetch` handler can open a
  `ReadableStream` to `api.anthropic.com/v1/messages` (`stream: true`) and
  pipe it straight through to the client `Response` — no buffering, no
  separate WebSocket layer, minimal added latency. This is the single
  highest-value property for this proxy, since every AI feature in scope
  (report summary today, chat and richer reports tomorrow) is a streaming UX.
- **Multi-region is the default, not a P3 project.** Workers run at the edge
  in 300+ locations automatically. The "P3: multi-region" line item on a
  traditional VM/container stack becomes a non-item on Cloudflare — call this
  out explicitly, because it removes real P3 scope.
- **Durable Objects are a natural fit for per-user rate limiting.** One DO
  instance per user ID gives you strongly-consistent, low-latency counters
  with no external cache/Redis dependency — exactly the "per-user rate
  limits" and "per-user spend caps" requirement, without inventing a
  distributed rate limiter.
- **Cost scales from hundreds to millions without a re-platform.** Workers
  billing is per-request/per-CPU-ms; there's no fleet to size for "hundreds
  of users" that then needs re-architecting at "millions." This directly
  answers the "scales from day-1 hundreds to eventually millions" requirement
  with one stack, not a migration.
- **Hyperdrive** lets a Worker hold pooled, low-latency connections to a
  normal Postgres instance (Neon) despite Workers' no-long-lived-TCP-socket
  model — so "keep it boring: Postgres" (§5) doesn't fight the compute choice.

Why not the alternatives as primary:

- **Fly.io** is a fine *fallback*, but for P1/P2 it's more infrastructure than
  needed — you'd be managing machine sizing and regions yourself for a
  workload that Workers gives you for free. Reserve it for P3 batch-queue
  workers or if the team later wants a persistent multi-agent session host
  (Claude's Managed Agents-style workload) that genuinely needs a container,
  not a request/response function.
- **Supabase Edge Functions** (Deno-based) are close in spirit to Workers but
  couple you to Supabase's Postgres + Auth stack more tightly than this app
  needs — Gemocode's auth is Sign in with Apple + an anonymous device path,
  not Supabase Auth's password/OAuth flows, so the main draw (bundled auth)
  doesn't apply. Workers + a standalone Postgres keeps the pieces
  independently swappable.

**Effort: M. Phase: P1.**

### 1.2 Auth: Sign in with Apple → anonymous-friendly JWT

No passwords, ever — matches the app's existing App Lock design ethos
(Keychain-backed, biometric-first).

- **Bootstrap (first AI use, no sign-in required):** client requests an
  anonymous session by presenting a **DeviceCheck / App Attest** assertion.
  The backend verifies the attestation with Apple, mints a short-lived JWT
  (RS256, backend-held signing key) bound to an opaque `device_id`, and
  returns it. No email, no name, no Apple ID touches the server at this
  point. This is the anti-abuse gate that makes "anonymous-friendly" safe —
  without App Attest, an anonymous-JWT endpoint is a free API-key mint for
  anyone who can call it.
- **Upgrade (App Store subscription, cross-reinstall quota recovery):**
  client can later exchange a Sign in with Apple identity token for a JWT
  that links to the same backend user record, merging the anonymous device's
  usage ledger by `device_id`. Sign in with Apple's main job here isn't
  identity for its own sake — it's the anchor StoreKit 2 entitlement
  notifications need (App Store subscription receipts are tied to an Apple
  ID) and the mechanism for restoring quota after a reinstall/device change.
- **JWT contents:** `sub` (opaque user id, not Apple's `sub` directly —
  re-mint your own internal ID so Anthropic-facing logs never carry an Apple
  identifier), `tier`, `exp` (short, e.g. 1h), `device_id`. Refresh via a
  `/v1/auth/refresh` endpoint gated by a longer-lived refresh token stored in
  Keychain (same pattern the app already uses for App Lock credentials).
- **Client storage:** JWT + refresh token in Keychain via the existing
  `KeychainStore.swift` pattern — do not put them in UserDefaults (that's
  where the BYO API key lives today, and UserDefaults is the wrong tier for
  anything auth-adjacent).

**Effort: M. Phase: P1.**

### 1.3 P1 endpoints (0–6 weeks, minimal viable proxy)

| Endpoint | Method | Purpose |
|---|---|---|
| `/v1/auth/anonymous` | POST | Exchange App Attest assertion → anonymous JWT |
| `/v1/auth/apple` | POST | Exchange Sign in with Apple identity token → JWT, links/upgrades device record |
| `/v1/auth/refresh` | POST | Rotate an expiring JWT using the refresh token |
| `/v1/ai/report-summary` | POST | Streaming SSE relay for the existing "plain-language summary" feature |
| `/v1/usage/me` | GET | Current period usage + remaining quota (for the client to show "3 of 4 summaries left this month") |
| `/v1/health` | GET | Liveness/readiness for uptime checks |

`/v1/ai/report-summary` request body — a **typed** structured payload replacing
the free-text `shareText` string (see §2/§3 for why):

```json
{
  "generated_at": "2026-07-12T14:03:00Z",
  "score": 78,
  "findings": [
    {"severity": "attention", "category": "labs", "title": "LDL Cholesterol Elevated",
     "detail": "LDL 142 mg/dL, above the 130 mg/dL reference high.",
     "recommendation": "Discuss lipid management with your doctor."}
  ],
  "trends": [
    {"metric": "weight", "direction": "falling", "percent_change": -3.2, "point_count": 6}
  ]
}
```

Response: Server-Sent Events proxied straight from Anthropic's streaming
response, re-framed to a minimal client-facing event shape
(`{"type":"delta","text":"..."}` / `{"type":"done"}` / `{"type":"refused"}` /
`{"type":"error","code":...}`) so the client never has to parse Anthropic's
wire format directly — that keeps the Anthropic-specific shape entirely on
the server side, which matters for §6 (model swaps shouldn't require a client
release).

**Per-user rate limits:** one Durable Object per `user_id`, holding a sliding
window token bucket (e.g. 10 requests/hour, tunable per tier). Checked before
the Anthropic call; a 429 is returned immediately, no Anthropic spend
incurred.

**Per-user + global spend caps:** the ledger (§2.3) tracks cumulative cost
per user per billing period; check the running total against the tier's cap
*before* dispatch. A separate **global daily spend counter** (Durable Object
singleton or a Postgres row with `SELECT ... FOR UPDATE` at low QPS) is
checked on every request; when it trips, the proxy returns a `503
budget_exhausted` and the **client falls back to the on-device rule-based
review with no AI paraphrase** — see §4's cost-lever section for why this
fallback is nearly free to implement given the existing `AnalysisEngine`.

**Streaming:** pass-through `ReadableStream`, no buffering. `max_tokens: 1024`
(matches current client value) is plenty for a ≤180-word summary and keeps
worst-case worker CPU time low.

**Retry/refusal handling:** the server-side call uses the SDK's default retry
behavior (429/5xx, exponential backoff, `max_retries: 2`) so transient
Anthropic errors don't surface to the client as failures. Refusal detection
mirrors the existing client logic exactly, just relocated: inspect
`stop_reason` (non-streaming) or the terminal `message_delta.stop_reason`
(streaming) — if `"refusal"`, emit `{"type":"refused"}` to the client instead
of partial/empty text, which the client renders via the same
`AISummaryError.refused` string it already has.

**Effort: L (this is the P1 core deliverable). Phase: P1.**

### 1.4 P2: usage dashboard, tiered quotas, prompt-injection-resistant shaping

- **Tiered quotas via StoreKit 2 Server Notifications V2** (not RevenueCat —
  see §6 for why). Gemocode is iOS-only today; App Store Server Notifications
  give subscription state changes (renewal, cancellation, refund) pushed to a
  webhook (`POST /v1/webhooks/appstore`), which the backend uses to update the
  `entitlements` table (§5). RevenueCat becomes worth the added dependency
  only if the product expands beyond Apple's ecosystem — note it as the
  documented fallback, not a P1/P2 build.
- **Usage dashboard:** start with read-only SQL views over the ledger
  (per-tier MAU, avg cost/user, refusal rate, cache hit rate) surfaced through
  whatever lightweight BI tool the team already uses (Metabase/Retool) rather
  than building custom internal UI — this is explicitly a "don't build" per
  §6.
- **Prompt-injection-resistant request shaping — formalize what §1.3 already
  started.** Deprecate the free-text `shareText` wire format entirely (it's a
  good *display* format, wrong *transport* format) in favor of the typed JSON
  shown above for every AI feature, including the new ones:
  - **Report summary:** the JSON shown in §1.3 — structured findings, not
    prose.
  - **Historical comparison:** structured deltas only —
    `{"metric": "weight", "from": {"value": 82.1, "date": "..."}, "to": {"value": 79.4, "date": "..."}, "percent_change": -3.3}`
    — never two raw report bodies for the model to diff itself.
  - **Chat:** the user's free-text question is unavoidably free text (that's
    the feature), but *everything else in the turn* — the report context the
    question is "about" — stays structured. The system prompt should treat
    the structured context block and the user's question as separately
    trusted: instructions live in `system`, biomarker context is clearly
    delimited data, and the user's question is explicitly framed as data to
    answer, not instructions to follow. This is the standard prompt-injection
    mitigation for RAG-shaped inputs, and it's exactly what "server controls
    prompt construction" buys you that a client-built prompt string doesn't.
  - Fields like `MedicalReport.notes`, `SymptomEntry.notes`, and
    `Medication.notes` (free text the user typed) are **excluded from AI
    payloads by default**. If a future feature wants to include them (e.g.
    "ask about my symptom notes"), that's an explicit, separately-scoped
    opt-in per field, clearly labeled to the user, not a blanket "send
    everything."

**Effort: M (dashboard) + M (StoreKit2 webhook + entitlements) + S (payload
schema migration, since the server already controls the schema from P1).
Phase: P2.**

### 1.5 P3: multi-region, queue-based batch analysis, model routing

- **Multi-region:** effectively already solved by Cloudflare's edge network
  (§1.1). The only P3-specific work is regionalizing the **database** read
  path if write latency to a single-region Postgres becomes the bottleneck —
  Neon read replicas or a move to a globally-distributed Postgres-compatible
  store (e.g. CockroachDB) only if metrics actually show DB latency
  dominating, not preemptively.
- **Queue-based batch analysis:** nightly/weekly digest and historical
  comparison generation is not latency-sensitive — perfect fit for
  Anthropic's **Message Batches API at 50% of standard pricing**. Cloudflare
  Cron Triggers enqueue jobs (Cloudflare Queues), a consumer batches all due
  users' requests into one `messages.batches.create()` call, polls for
  completion, and pushes results via APNs when ready (background
  notification, not a live request). This is a genuinely good cost lever,
  not just a nice-to-have — see §4.
- **Model routing (cheap vs. strong):** a lightweight classifier decides per
  turn/request which model tier serves it. Concretely:

  | Workload | Model | Why |
  |---|---|---|
  | Chat small talk, greetings, "what does LDL mean" style lookups | `claude-haiku-4-5` ($1/$5 per MTok) | Cheapest tier; no clinical reasoning required |
  | General chat about the user's own reports, most turns | `claude-sonnet-5` ($3/$15, intro $2/$10 through 2026-08-31) | Near-Opus quality on the reasoning this needs, at a third of Opus's price |
  | Full report synthesis / plain-language summary (today's feature) | `claude-opus-4-8` ($5/$25) | Matches the model already in production (`AISummaryService.model`); highest-stakes single output per session, worth the premium |
  | Multi-report longitudinal reasoning (deep historical analysis, P3 stretch) | `claude-opus-4-8`, `claude-fable-5` only if Opus proves insufficient | Fable 5 is priced above Opus ($10/$50) — reserve for a proven capability gap, not a default |

  The router itself can be a cheap heuristic first (message length + keyword
  match against a "clinical question" list) before reaching for an actual
  classifier call — don't spend a model call to decide which model to call
  unless the heuristic's error rate is demonstrably a problem.
- **Worth a later look, not a P1–P3 commitment:** Anthropic's **Managed
  Agents** surface (server-hosted agent loop + sandbox) is a plausible home
  for an eventual tool-using "chat that can pull specific historical data on
  demand" feature. It's explicitly flagged here as a *future evaluation*, not
  a recommendation to build now — it adds session/container infrastructure
  this proxy doesn't need for P1–P3's scope, and the mandate's own
  anti-overengineering instinct (§6) argues against reaching for it before a
  simple structured-context chat proves insufficient.

**Effort: L (batch pipeline) + M (routing logic) + S (multi-region is mostly
free). Phase: P3.**

---

## 2. Data-boundary architecture

**Crown-jewel principle, restated concretely for this app:** health data
lives in SwiftData on-device; the backend is a stateless relay that sees the
minimum structured payload per request, logs metadata (not content), and
retains request bodies nowhere.

### 2.1 What crosses the wire, per feature

| Feature | Crosses the wire | Never crosses the wire |
|---|---|---|
| **Report summary** (existing) | Structured `{score, findings[], trends[]}` (see §1.3 JSON) — engine-derived, not raw fields | `MedicalReport.notes`, attachments, `HealthProfile` (name, DOB, blood type, allergies, conditions), raw `LabResult` rows beyond what the engine already flagged |
| **Historical comparison** (new) | Structured deltas between `ScoreSnapshot`/`LabSnapshot` pairs (metric, from-value, to-value, % change, date range) | Full report bodies for either endpoint of the comparison, attachments from either report |
| **Chat about your reports** (new) | User's free-text question + the structured context of the report(s) the question references (same shape as report-summary payload, possibly multiple) | Attachments, `HealthProfile` Medical ID fields, any report the user hasn't explicitly brought into the conversation |
| **Personalized recommendations** (future) | Structured findings + active `Medication` list (name/dosage/frequency only — not `Medication.notes`) for interaction-aware phrasing | `Medication.notes`, prescriber/pharmacy info if ever added |

Two fields deserve explicit callouts because they're the ones most likely to
get accidentally included by a future contributor reaching for "just send the
whole object": **`HealthProfile`** (blood type, allergies, conditions — this
is literally the emergency Medical ID data) and **`ReportAttachment.data`**
(raw PDF/image bytes). Neither has a route to Anthropic in any P1–P3 feature
in this plan. If a future feature genuinely needs allergy/condition context
(e.g. "flag interactions considering my allergies"), send a specific derived
boolean/enum ("has documented penicillin allergy: true"), never the free-text
`HealthProfile.allergies` string.

### 2.2 Where server-side persistence genuinely becomes necessary

Two things, and only two:

1. **Usage ledger** — required for spend caps, tiered quotas, and abuse
   response. This is metadata about requests, not their content.
2. **Chat session context** — a genuine exception to "retains nothing."
   Multi-turn chat needs the prior turns available to the model, and
   re-sending the full structured context on every turn from the client is
   both wasteful and defeats prompt caching (§4). The pragmatic answer:
   server-side session storage **scoped to an active chat session with a
   short TTL (e.g., 1 hour of inactivity), auto-expired, and containing only
   the structured payloads already deemed safe to leave the device** (§2.1)
   — never attachments, never Medical ID. This is explicitly *not* a
   permanent chat history store; if the product later wants persistent chat
   history across app launches, that's a deliberate, separately-scoped
   decision with its own retention policy, not a side effect of session
   caching.

### 2.3 Minimal schema for the two persistence needs

```sql
-- Usage ledger: metadata only, never request/response content
CREATE TABLE usage_events (
  id            BIGSERIAL PRIMARY KEY,
  user_id       UUID NOT NULL REFERENCES users(id),
  feature       TEXT NOT NULL,           -- 'report_summary' | 'chat' | 'comparison'
  model         TEXT NOT NULL,           -- 'claude-opus-4-8' etc.
  input_tokens  INTEGER NOT NULL,
  output_tokens INTEGER NOT NULL,
  cache_read_tokens INTEGER NOT NULL DEFAULT 0,
  cost_cents    INTEGER NOT NULL,        -- computed from token counts at write time
  stop_reason   TEXT,                    -- 'end_turn' | 'refusal' | 'max_tokens' | ...
  anthropic_request_id TEXT,             -- for cross-referencing with Anthropic support
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX ON usage_events (user_id, created_at);

-- Entitlements: tier + StoreKit2 linkage
CREATE TABLE entitlements (
  user_id       UUID PRIMARY KEY REFERENCES users(id),
  tier          TEXT NOT NULL DEFAULT 'free',
  apple_original_transaction_id TEXT,
  quota_period_start TIMESTAMPTZ NOT NULL,
  renewed_at    TIMESTAMPTZ
);

-- Ephemeral chat session context — TTL'd, never a permanent history store
CREATE TABLE chat_sessions (
  session_id    UUID PRIMARY KEY,
  user_id       UUID NOT NULL REFERENCES users(id),
  context       JSONB NOT NULL,          -- structured payloads only, per §2.1
  expires_at    TIMESTAMPTZ NOT NULL,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);
-- Background job (or Postgres TTL via pg_cron) deletes rows past expires_at
```

Note what's absent: no `report_text`, no `attachment_url`, no
`raw_prompt` columns anywhere. If a future engineer's instinct is "let's log
the full prompt for debugging," that's the one thing this schema should make
structurally awkward to add casually — debugging should lean on
`anthropic_request_id` plus reproducing the structured payload from the
client's local data, not a server-side prompt log.

**Effort: S (schema) + M (TTL enforcement + session lifecycle). Phase: P1
(ledger/entitlements skeleton) / P2 (chat_sessions, once chat ships).**

---

## 3. Client-side changes

### 3.1 `AISummaryService` migration

- **Replace** the direct `URLRequest` to `https://api.anthropic.com/v1/messages`
  with a request to the proxy's `/v1/ai/report-summary`. Swap `x-api-key: <key>`
  for `Authorization: Bearer <JWT>` (JWT from Keychain, refreshed via
  `/v1/auth/refresh` as needed).
- **Replace the request body.** Today: `RequestBody{model, maxTokens, system,
  messages: [{role: "user", content: review.shareText}]}` — model, system
  prompt, and token budget are all client-controlled. After migration: the
  client sends the structured JSON from §1.3, and **model choice, system
  prompt, and token budget move entirely server-side.** This is a meaningful
  simplification for the client (delete `RequestBody`, `RequestMessage`, the
  hardcoded `model`/`systemPrompt` constants) and it means a prompt tweak or
  model upgrade no longer requires an App Store release.
- **Response handling switches to streaming.** Replace the single
  `URLSession.shared.data(for:)` call with a byte-stream reader
  (`URLSession.bytes(for:)`) parsing the proxy's SSE events, appending text
  deltas to a `@Published` string the UI can render incrementally — this is
  a genuine UX upgrade over today's "wait for the whole response" behavior,
  not just a backend implementation detail.
- **Refusal handling carries over unchanged in spirit:** `AISummaryError.refused`
  stays; it now triggers on the proxy's `{"type":"refused"}` event instead of
  a client-side `stop_reason` check, but the user-facing string and the
  guard-before-reading-content discipline (`AISummaryError` doc comment
  already models this correctly) don't change.
- **New error cases to add:** `.quotaExceeded` (proxy 429 from the per-user
  rate limiter or spend cap), `.authRequired` (JWT expired/missing and
  refresh failed — prompt re-auth), `.serviceUnavailable` (global spend cap
  tripped — see §3.3 for what the UI should do here, which is *not* just show
  an error).

### 3.2 BYO-key: keep it, demoted to power-user/fallback mode

**Recommendation: keep BYO-key as an opt-in advanced setting, off by default
for new users.** Rationale:

- It's a real safety valve if the proxy has an outage, if a power user wants
  zero rate limits, or if a user is uncomfortable with *any* server relay
  even a metadata-only one — all legitimate positions for a health app to
  respect.
- It costs little to keep: the existing direct-to-Anthropic code path
  (`AISummaryService`'s current implementation, essentially unchanged) can
  live behind a `Settings → Advanced → Use my own Anthropic API key` toggle,
  fully separate from the proxy path, sharing only the UI layer.
- It should be **clearly framed as the exception, not the default**, in the
  UI copy — most users should never need to know it exists. New installs
  default to the owner-funded proxy; the BYO toggle is discoverable but not
  surfaced during onboarding.

### 3.3 Offline behavior

The app is local-first for everything except this one feature — offline
behavior should make that obvious rather than surprising:

- Core app (all SwiftData-backed screens, the rule-based `AnalysisEngine`
  score/findings, medication reminders, appointments) works **fully offline**,
  unchanged.
- The AI paraphrase layer degrades gracefully: no network → immediately show
  the existing rule-based review (score + findings + recommendations, already
  computed on-device, zero cost) with a small "AI summary unavailable
  offline" note, rather than a spinner-then-error. This is the same fallback
  behavior recommended for a tripped global spend cap (§1.3, §4) — **one
  fallback path serves both offline and budget-exhausted cases**, which is a
  nice property to design for deliberately rather than end up with by
  accident.

### 3.4 Migration path for existing users

Three populations, three behaviors:

1. **Users who never configured an API key.** On first post-update AI-feature
   tap, silently use the proxy with a lazily-created anonymous JWT (App
   Attest bootstrap, §1.2) — no interruption, no forced sign-in. Offer Sign
   in with Apple only if/when they hit a subscription paywall or want
   cross-device quota continuity.
2. **Users who already set a BYO key.** Keep them on the direct-to-Anthropic
   path unchanged by default — don't silently switch their traffic through
   the proxy. Show a one-time, dismissible banner: *"AI summaries are now
   included for everyone — no key required."* with a toggle to switch, and a
   "keep using my key" option that just dismisses it. Never auto-migrate a
   user off a path they explicitly configured.
3. **Existing App Store subscribers (if any subscription tier already
   exists).** StoreKit 2 entitlement sync (§1.4) upgrades their proxy quota
   automatically once they're signed in — no manual action needed beyond the
   Sign in with Apple prompt.

**Effort: M (client networking rewrite to streaming) + S (new error cases) +
S (BYO toggle relocation) + S (migration banner). Phase: P1 (core rewrite) /
P2 (StoreKit2-aware migration for case 3).**

---

## 4. Cost model

### 4.1 Per-feature token budgets and per-user monthly estimate

Using current published pricing (Opus 4.8 $5/$25 per MTok in/out; Sonnet 5
$3/$15, intro $2/$10 through 2026-08-31; Haiku 4.5 $1/$5) and the realistic
usage the mandate specifies — **4 report analyses + 30 chat turns/month**:

| Item | Tokens (typical) | Model | Est. cost |
|---|---|---|---|
| Report summary (×4/mo) | ~300 tok system + ~500 tok structured findings in; ~350 tok out | `claude-opus-4-8` | 4 × (~$0.004 in + ~$0.009 out) ≈ **$0.05/mo** |
| Chat, small-talk turns (~40% of 30) | ~150 in / ~150 out | `claude-haiku-4-5` | 12 × (~$0.0002 + ~$0.0008) ≈ **$0.01/mo** |
| Chat, substantive turns (~60% of 30) | ~350 in / ~450 out, with growing-history caching (§4.2) | `claude-sonnet-5` (intro pricing) | 18 × (~$0.0005 blended-with-cache + ~$0.0045) ≈ **$0.09/mo** |
| **Total, per active user/month** | | | **≈ $0.15/mo gross Anthropic spend** |

This is deliberately a *ceiling* estimate assuming full engagement every
month. Real blended cost across a free-tier population will be well below
this since most free users won't hit 4 reports + 30 chats monthly — but size
infrastructure and caps against the ceiling, not the average, so a burst of
engaged users doesn't blow the global budget.

At "hundreds" scale (P1): ~500 active users × $0.15 ≈ **$75/month** — trivial,
well within a reasonable owner-funded budget, no cap tuning urgency.

At "millions" scale (P3, illustrative): 2,000,000 active users × $0.15 ≈
**$300,000/month if every user is fully engaged** — this is the number that
makes tiered quotas, model routing, and caching non-optional rather than nice
architecture. Free-tier quotas should be sized so the *realistic* blended cost
(accounting for actual engagement rates, not the ceiling) stays well under
whatever budget the business sets, with paid tiers absorbing power users.

### 4.2 Caching strategy — and where it genuinely helps here

**Important nuance specific to this app's current prompt shape:** Anthropic's
prompt cache has a **minimum cacheable prefix** — 4,096 tokens on the
Opus/Haiku 4.5 tier, 1,024 tokens on Sonnet. The existing system prompt in
`AISummaryService.swift` is ~150 tokens. **Caching that system prompt alone,
on Opus, does nothing** — it's an order of magnitude below the minimum and
will silently show `cache_creation_input_tokens: 0` / `cache_read_input_tokens: 0`
forever. Don't ship a cache_control breakpoint on the report-summary system
prompt as-is and declare victory; it won't save anything until the prompt is
substantially larger.

Two places where caching *is* a genuine win for this app:

1. **If/when the "richer AI reports" roadmap item enriches the system prompt
   with static reference material** — e.g. embedding `LabCatalog`'s ~46 test
   reference ranges and `LabSynonyms` alias data so the model can reason
   about lab context itself rather than relying entirely on client-computed
   findings — that static block will comfortably exceed the 1,024–4,096 token
   minimum and becomes genuinely cacheable across every user's request. This
   is the concrete trigger condition for "add prompt caching to report
   summary": *when the system prompt grows to carry that reference data, not
   before.*
2. **Chat, structurally, almost immediately.** Multi-turn conversations are
   the textbook caching case regardless of system-prompt size: place the
   cache breakpoint on the last block of each turn, and the entire prior
   conversation (which grows past the Sonnet 1,024-token minimum within a
   couple of turns) is served from cache on every subsequent turn. This is
   the single highest-leverage caching win in this plan — implement it from
   chat's first release (P2), not as a later optimization pass.

### 4.3 Levers when costs spike

In rough order of speed-to-effect:

1. **Trip the global spend cap → fall back to the on-device rule-based
   review, AI paraphrase disabled app-wide.** This is the emergency brake,
   and it's nearly free to have ready because the `AnalysisEngine` already
   produces a complete score+findings review with zero AI cost — the AI layer
   is strictly an enhancement on top of an already-functional feature. No
   other app-breaking outage mode exists here; lean on that.
2. **Tighten free-tier monthly quotas** (report count, chat turn count) —
   config change, no deploy.
3. **Shift more chat traffic to Haiku 4.5** by widening the small-talk
   classifier's match criteria — config change.
4. **Route non-urgent work to the Batch API** (50% off) — nightly
   comparisons/digests are natural batch candidates and shouldn't be running
   at interactive pricing in the first place.
5. **Verify cache hit rates aren't silently zero** (§4.2's minimum-prefix
   trap) — a caching regression is an easy way to double spend without any
   traffic change.
6. **Per-user hard caps** (already in place from P1) contain any single bad
   actor or runaway client bug regardless of the above.

**Effort: S (spend-cap fallback is mostly already implied by keeping
AnalysisEngine as the base layer) + S (quota config) + M (batch pipeline, if
not already built per §1.5). Phase: P1 (cap + fallback) / P3 (batch lever).**

---

## 5. Database & scaling, CI/CD, observability

### 5.1 Database: Postgres (Neon), and why it's the boring right choice

The workload here — an append-mostly usage ledger, a small entitlements
table, a TTL'd session cache — is exactly what relational databases have
solved for decades. There's no graph, no full-text search, no vector
similarity requirement anywhere in P1–P3. Reaching for anything more exotic
(a document store "because JSON," a dedicated time-series DB "because it's
metrics") would be solving a scaling problem this workload doesn't have yet.
**Neon** specifically because it pairs cleanly with Cloudflare Workers via
Hyperdrive (pooled connections, no cold-start-per-request TCP handshake
penalty) and gives branch-per-PR databases for CI without extra tooling. Fly
Postgres is the equivalent if the team ends up on the Fly.io fallback stack
instead.

Scaling posture: a single primary is sufficient through P2. At P3 scale,
consider a read replica for the usage-dashboard query path (§1.4) before
considering anything more drastic — the ledger's write pattern (append-only,
small rows) will comfortably outscale most other parts of the system.

### 5.2 CI/CD

- GitHub Actions, mirroring the pattern already established for the iOS app's
  own CI (`.github/workflows/ci.yml`) rather than introducing a new tool.
- `wrangler deploy` with a preview environment per PR (Cloudflare Workers'
  built-in feature) so a reviewer can hit a live, isolated instance before
  merge.
- Database migrations as plain versioned SQL files run by a small script (or
  Drizzle Kit if the team wants schema-in-TypeScript) — applied to a Neon
  branch in CI before applying to staging/prod, so a bad migration fails in
  CI, not in production.
- **Secrets never touch the repo or CI logs.** `ANTHROPIC_API_KEY` and the JWT
  signing key are set via `wrangler secret put` (or Fly's secrets store on
  the fallback stack), injected as runtime env vars, referenced by name only
  in code and workflow files.
- Post-deploy smoke test: one synthetic request to `/v1/health` and one
  authenticated synthetic request to `/v1/ai/report-summary` with a
  known-shape payload, asserting a 200 and a well-formed SSE stream, before a
  deploy is considered successful.

### 5.3 Observability minimums

- **Structured JSON logs** per request: `request_id`, hashed `user_id` (never
  raw), `feature`, `model`, `input_tokens`, `output_tokens`,
  `cache_read_tokens`, `latency_ms`, `stop_reason`, `anthropic_request_id`.
  Never log request/response *content* (§2.3's schema discipline extends to
  logs, not just the database).
- **Metrics:** request rate, error rate, p50/p95/p99 latency, spend
  rate ($/hour, compared against the global cap), cache hit rate, refusal
  rate.
- **Alerts, minimum set:**
  - Spend rate crossing 50%/80%/100% of the daily global cap (page before
    the hard cutoff, not at it).
  - Error rate spike (Anthropic 5xx/529, or proxy-side 5xx).
  - Refusal rate spike — this one is a security/product signal as much as a
    reliability one: a sudden jump can mean a jailbreak/prompt-injection
    attempt against the chat endpoint, or a broken client build sending
    malformed structured payloads that the model is (correctly) declining.
  - Auth failure spike (App Attest verification failures, JWT forgery
    attempts) — the earliest signal of credential-stuffing-style abuse
    against the anonymous bootstrap endpoint.

**Effort: S (Postgres choice, no build) + M (CI/CD pipeline) + M
(observability wiring). Phase: P1 (logs, core metrics, deploy pipeline) / P2
(dashboards, refined alert thresholds).**

---

## 6. What NOT to build yet (overengineering traps)

Called out explicitly because each of these is a plausible "while we're at it"
addition that would slow P1 down for no P1-relevant benefit:

- **No CloudKit dependency for this.** The proxy is a stateless relay, not a
  sync backend — it must not become the thing that quietly reintroduces a
  cloud dependency for health data the app's entire design philosophy has
  kept local. If cross-device sync is ever wanted, that's a separate,
  explicitly-scoped decision with its own privacy review — not a side effect
  of building an AI proxy.
- **No custom auth (passwords, email/password reset flows, email
  verification).** Sign in with Apple + App Attest-gated anonymous JWTs cover
  every auth need in this plan. Building a password system here would be pure
  surface area with no corresponding requirement.
- **No microservices.** One Worker service handles auth, relay, and usage
  through P2. Splitting auth/relay/usage into separate deployed services
  before there's an operational reason to (independent scaling needs,
  different teams owning different pieces) adds deploy coordination and
  network hops for no benefit at this scale.
- **No RevenueCat for P1/P2.** StoreKit 2 Server Notifications V2 fully cover
  a single-platform (iOS-only) subscription model. RevenueCat earns its
  dependency only if Gemocode expands to Android/web and needs
  cross-platform entitlement reconciliation — document it as the documented
  fallback, don't build against it speculatively.
- **No vector DB / RAG pipeline for chat.** The "chat about your reports"
  feature's context needs (§2.1) are fully served by structured payloads the
  client assembles from data it already has locally. Standing up embeddings
  and a retrieval layer before the simple structured-context approach has
  been shown insufficient is solving a problem the feature doesn't have yet.
- **No client-exposed model picker.** Model routing (§1.5) should be entirely
  server-side and invisible to the user. A settings toggle to "pick your
  model" complicates cost control, support, and the refusal-handling
  contract for no user-facing benefit this app's users would actually want.
- **No hand-rolled distributed rate limiter.** Durable Objects (Cloudflare)
  or the equivalent platform primitive on the fallback stack already solve
  per-user rate limiting correctly; building a Redis-backed token bucket from
  scratch duplicates a solved problem.
- **No self-managed servers/Kubernetes.** Both the primary (Workers) and
  fallback (Fly Machines) stacks are managed compute. Provisioning and
  patching your own VM fleet for a relay service this size is pure
  operational burden with no corresponding benefit.
- **No custom internal admin UI in P1/P2.** Read-only SQL views + an existing
  BI tool (§1.4) cover the usage-dashboard need until there's a concrete,
  specific workflow that generic tooling can't express.
- **No Managed Agents / agentic tool-use infrastructure before it's needed.**
  Flagged in §1.5 as worth *evaluating* later for a tool-using chat feature —
  explicitly not a P1–P3 build. It brings session/container infrastructure
  this plan's stateless-relay design doesn't need for anything in scope.

---

## Appendix: API key custody, rotation, and abuse-response runbook

**Custody (non-negotiable):**
- `ANTHROPIC_API_KEY` lives **only** in the backend secret store (Cloudflare
  Workers Secrets, or the fallback stack's equivalent). It is never in the
  repo, never in a client binary, never returned in any API response, never
  printed in logs (structured logs carry `anthropic_request_id`, not the
  key), never passed as a build-time env var baked into a committed config
  file.
- Only the relay service's runtime process can read it — no CI job, no
  developer laptop, no debugging tool needs it once initial setup is done.

**Rotation:**
- Scheduled rotation: quarterly, regardless of any incident.
- Immediate rotation triggers: suspected leak (key appears in a log, a
  support ticket, a public repo scan), offboarding of anyone who had Console
  access, or an unexplained spend spike that doesn't correlate with traffic
  metrics.
- Procedure: generate the new key in the Anthropic Console → set it as the
  new secret value → redeploy → verify a synthetic request succeeds against
  the new key → revoke the old key in Console → confirm a request using the
  old key now 401s within the propagation window. Keep this as a short,
  rehearsed runbook, not a from-scratch process each time.

**Abuse response:**
1. **Detect:** spend-rate or per-user-request-rate anomaly alert (§5.3) fires.
2. **Contain:** flag the offending `user_id`/`device_id` in its Durable
   Object; the per-user rate limiter and spend cap immediately throttle it to
   zero without needing a deploy.
3. **Investigate:** pull structured logs (metadata only, per §2.3/§5.3) for
   that `user_id` — request rate, refusal rate, `anthropic_request_id`s for
   cross-reference with Anthropic if the pattern looks like a
   jailbreak/prompt-injection attempt against the chat endpoint.
4. **Remediate:** revoke the user's JWT, force re-authentication; if the
   account is an App Store-verified subscriber abusing a generous tier,
   consider tier downgrade before outright ban.
5. **Never "temporarily" raise or disable the global spend cap to unblock a
   pressured support request.** Raise that specific user's *per-user* cap
   instead, on a case-by-case, logged basis — the global backstop exists
   precisely for the moment someone is under pressure to bypass it.
6. **Postmortem:** update rate limits, spend caps, or refusal-pattern
   detection based on what the incident revealed; this is a living runbook,
   not a document written once and never revisited.

---

# Part 5 — Security & privacy

# Gemocode — Security & Privacy Section, Upgrade Roadmap

**Scope:** current-state findings against the local-first app as it exists today (spot-checked `Services/AppLock.swift`, `KeychainStore.swift`, `AISummaryService.swift`, `WidgetBridge.swift`, `BackupService.swift`, `Gemocode.entitlements`, `GemocodeWidgets.entitlements`, `project.pbxproj`), plus the security/privacy architecture needed for the owner's new direction: backend AI proxy on the owner's Anthropic key, accounts, AI chat over blood work, and an onboarding quiz collecting sensitive lifestyle data.

Every item is tagged **Severity/Priority**, **Effort** (S/M/L), **Phase** (P1 = 0–6wks, P2, P3).

---

## 1. Current-state findings (ranked by severity)

### 1.1 — HIGH — API key stored in `UserDefaults`, not Keychain
`AISummaryService.apiKeyDefaultsKey = "anthropicAPIKey"` (`Services/AISummaryService.swift:31`), read/written via plain `@AppStorage` in `ProfileView.swift:36` and `ReviewScreen.swift:15`. `UserDefaults` is an unencrypted plist under the app's sandbox container — readable from an unencrypted iTunes/Finder backup, by anything with filesystem access on a jailbroken device, and it is not protected by the device passcode/biometric gate the way Keychain items are. Today this only exposes the *user's own* key (their problem to rotate), so it's High rather than Critical — but it's a bad pattern to carry into the account/backend era, and every user with this key set is one unencrypted-backup-restore-on-another-device away from key leakage.

**This becomes moot once the backend proxy ships** (§2) — the client stops holding an Anthropic key entirely once Direct-to-Anthropic calls are replaced by proxy calls. Fix it anyway in the interim because the proxy migration is P2, and this is a one-file P1 fix.

**Fix spec:**
- Add `KeychainStore` methods for a generic secret (the existing enum already has `set/get/delete` keyed by `service` = `"com.ogureq.gemocode.lock"`; add a second service or account key, e.g. account `"anthropic.apikey"`, same `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`).
- Replace the two `@AppStorage(AISummaryService.apiKeyDefaultsKey)` bindings with a small `ObservableObject` wrapper (`@Published var apiKey: String?` backed by Keychain get/set) since `@AppStorage` doesn't bind to Keychain directly — SwiftUI needs a manual publisher.
- Migration step: on first launch after upgrade, read the old UserDefaults value if present, write it to Keychain, delete the UserDefaults key (`UserDefaults.standard.removeObject`).
- Add to `AppLockTests`-style pattern: skip Keychain-touching tests when unavailable (CI has no Keychain, per CLAUDE.md).

**Severity:** High · **Effort:** S · **Phase:** P1

### 1.2 — HIGH — Unencrypted JSON backup export
`BackupService.export` (`Services/BackupService.swift:129`) serializes the *entire* store — profile (name, DOB, sex, height, blood type, allergies, conditions), all lab results, **raw attachment bytes** (`BackupAttachment.data: Data` — PDFs/photos of real lab reports, `Services/BackupService.swift:52-56`), medications, symptoms, appointments, score history — as plaintext JSON to a user-chosen file via `BackupJSONDocument` (a `FileDocument`, so it goes through the system file picker — iCloud Drive, Files app, AirDrop, email attachment, etc. are all one tap away). This is the single largest exposure surface in the app: a lost USB drive, a shared family iCloud Drive folder, or an accidentally-AirDropped-to-the-wrong-person file discloses complete medical history including document images.

**Fix spec (passphrase-encrypted export):**
- **Format:** wrap the existing JSON payload in an envelope: `{ version, salt, kdfParams, nonce, ciphertext }` (a new top-level container, keep `BackupPayload` unchanged as the plaintext-then-encrypted inner blob so existing decode logic is reused).
- **KDF:** PBKDF2-HMAC-SHA256 via `CryptoKit`'s `SymmetricKey` derivation is not built in (`CryptoKit` has no PBKDF2) — use `CommonCrypto`'s `CCKeyDerivationPBKDF` (still first-party, no dependency) or implement via `Security` framework. Practical target: PBKDF2-HMAC-SHA256, **310,000 iterations** (OWASP 2023 recommendation for PBKDF2-SHA256), 16-byte random salt per export. If scrypt is preferred instead (no first-party Apple API — would require vendoring, which conflicts with the zero-dependency rule), stick with PBKDF2 to honor "zero third-party dependencies."
- **Cipher:** `CryptoKit.AES.GCM` — 256-bit key derived from the passphrase, random 12-byte nonce per export, authenticated (GCM tag) so tampering/corruption is detected on restore, not silently misread.
- **UX:** export flow asks for a passphrase (with confirmation field + strength meter, min length e.g. 10 chars) — separate from the app-lock passcode, since the file may outlive the device. Restore flow prompts for the passphrase; wrong passphrase fails the GCM tag check with a clear "incorrect passphrase or corrupted file" error (reuse the existing `BackupError.unreadableFile` shape, add `.wrongPassphrase`).
- **Back-compat:** detect old-format (bare `BackupPayload` JSON, no envelope) on restore and continue to support importing legacy unencrypted backups, but *stop producing* unencrypted exports by default. Keep an "export unencrypted (not recommended)" escape hatch behind a confirmation dialog for power users who understand the risk (e.g. moving to a password manager–free workflow), not the default button.

**Severity:** High · **Effort:** M · **Phase:** P1

### 1.3 — MEDIUM (assessed, largely defensible) — Fail-open lock semantics
`AppLock.canLock` (`Services/AppLock.swift:56`) is `hasPasscode || biometricsAvailable`; `evaluate(lockEnabled:)` (line 119) skips locking entirely when `canLock` is false. Two things compound this:
1. `appLockEnabled` itself defaults to **`false`** (`ContentView.swift:9`, `@AppStorage("appLockEnabled") = false`) — the lock is opt-in, not opt-out.
2. Even when opted in, if the user never set a passcode and has no biometrics enrolled, the app fails open rather than blocking.

**Assessment: this is a reasonable product default, not a vulnerability, but it should be made more visible.** Forcing a lock on every user of a local-first app with no account recovery story is a support-ticket generator (lost passcode = lost data, no server-side reset possible) — fail-open is the correct posture *for this app's model*. The gap is discoverability: a user who never sees a prompt to enable the lock may not realize their data — now including onboarding-quiz health answers and chat history if P2 stores any client-side cache — is unprotected at the OS level beyond the device passcode itself.

**Harden (don't replace) with:**
- A one-time onboarding nudge (not a hard gate) recommending app lock, similar to how Health/banking apps prompt post-setup.
- Surface lock status on the Privacy screen (§6) — "App Lock: Off" as a visible, tappable state rather than a buried settings toggle.
- When the account layer (§5) ships, treat account sign-in and app-lock as orthogonal — do not let Sign in with Apple session persistence substitute for the local passcode/biometric gate on a shared device.

**Severity:** Medium (assessed/defend) · **Effort:** S (nudge + privacy screen copy) · **Phase:** P1

### 1.4 — LOW-MEDIUM — Widget snapshot exposure surface
`WidgetBridge.update` (`Services/WidgetBridge.swift:37`) writes `WidgetSnapshot` (score, headline, ISO8601 timestamp, up to a few `WidgetVital` name/value/icon triples) to `UserDefaults(suiteName: "group.com.ogureq.gemocode")`, key `widget.snapshot` — and `WidgetKit` renders it on the home/lock screen. This is a deliberate, bounded disclosure (a numeric health score + a short headline + vital names/values), but:
- It is **not gated by app-lock at all** — if the user has app-lock enabled specifically to keep the passcode/biometric wall up, the widget on the home screen (and, depending on widget family, the **lock screen**) still shows score + headline + vitals to anyone who glances at the phone. This is a scope mismatch: the user's threat model when they turn on app-lock ("don't show my health data to someone who picks up my phone") is not fully honored by the widget.
- The app-group container (`group.com.ogureq.gemocode`, both `Gemocode.entitlements` and `GemocodeWidgets.entitlements` declare it) is shared, unencrypted `UserDefaults` storage — any other app signed with the same team/app-group (none exist today, but worth noting for the account-layer era if a companion app is ever added) could read it.

**Fix spec:**
- Add a "Show on Lock Screen / Home Screen widget" privacy toggle (default matches current behavior, but make it explicit) and/or a "hide values, show only 'Tap to view'" redacted widget state when app-lock is enabled — mirrors how Messages/Mail redact previews when the phone is locked.
- No change needed to the app-group entitlement itself; this is a display-policy fix, not a storage fix.

**Severity:** Low-Medium · **Effort:** S · **Phase:** P2 (P1 if user testing flags it sooner)

### 1.5 — LOW — Additional spot-check notes
- `KeychainStore` (`Services/KeychainStore.swift`) correctly uses `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` for the passcode hash/salt — good, no `Synchronizable` flag, so it won't leak to iCloud Keychain. No change needed.
- `AppLock.verify` uses a manual constant-time XOR-accumulate compare (`Services/AppLock.swift:155-162`) — correct in intent; note for reviewers that this is fine but double-check it isn't optimized away by the compiler in Release builds (Swift generally won't fold this away, but if paranoia is warranted, migrate to `CryptoKit`'s or a documented constant-time compare when touching this file next). Not a real-world exploitable gap given the passcode is also rate-limited only by UI (no explicit lockout counter today) — see next bullet.
- **No brute-force lockout/backoff on the local passcode.** `AppLock.verify` has no attempt counter or exponential backoff; an attacker with the unlocked device (or repeated foreground/background cycling) can retry a short numeric passcode indefinitely. Recommend adding a simple attempt counter (e.g., 5 wrong attempts → 30s cooldown, escalating) stored alongside the hash in Keychain. **Severity: Medium · Effort: S · Phase: P1/P2.**
- `AISummaryService` sends only `review.shareText` (the rule-based, already-on-device-generated summary) to Anthropic today, never raw attachments/documents — this is good practice and should be explicitly preserved as a design invariant when the proxy and chat features ship (§3).
- Report attachments (`ReportAttachment.data`) are stored as raw `Data` blobs directly in SwiftData with no additional at-rest encryption beyond the OS's default Data Protection class for the app container — acceptable given `NSFileProtectionComplete`-equivalent default behavior for app data on iOS, but confirm the SwiftData store's file protection class explicitly rather than relying on the default (no evidence of an explicit override; flag as a P2 verification task, not a known bug).

---

## 2. API-key protection architecture (owner's shared Anthropic key)

The single biggest step-change in risk from this roadmap: today a leaked key costs one user their own money; post-launch, a leaked key is the owner's bill, shared across every user, with no per-user isolation unless built deliberately.

### 2.1 Server-side secret store
- **Never** in the repo, client binary, client-side config, build logs, or crash reports. Store in the backend host's secret manager (e.g. AWS Secrets Manager / GCP Secret Manager / Fly.io secrets / whatever host is chosen) with access limited to the proxy service's runtime role — no human/CI has standing read access, only inject-at-deploy.
- Client never sees an Anthropic key at all post-migration — client authenticates to *your* proxy (via the account/Sign-in-with-Apple session token, §5), proxy authenticates to Anthropic with the owner's key. This is the whole point of the proxy and eliminates finding 1.1 by construction for new installs.
- CI must never echo the secret; add it as a masked/protected GitHub Actions secret scoped to the deploy job only, not exposed to PR-triggered workflows from forks.

**Severity:** Critical (get this right from day one — the entire cost-control model depends on it) · **Effort:** M · **Phase:** P1 (must land with the very first backend deploy, not retrofitted)

### 2.2 Key rotation runbook
- Rotate on a fixed cadence (e.g. every 90 days) plus immediately on any suspected exposure.
- Runbook: (1) generate new key in Anthropic console, (2) write to secret manager under a new version, (3) rolling-restart proxy instances to pick up new version with zero downtime (blue/green or simple restart since this is a low-traffic consumer app), (4) confirm new key serving traffic via a canary request + dashboard check, (5) revoke old key in Anthropic console, (6) log the rotation event (who/when/why) in an internal audit log — not in the app, in ops tooling.
- Keep this runbook as an actual checklist doc the on-call person can execute without guessing (a P1 deliverable alongside the proxy itself, even if just a few paragraphs in ops docs — not part of this app's repo per CLAUDE.md's "no backend in this repo" stance, so track it wherever the new backend service's repo/docs live).

**Severity:** High · **Effort:** S (process, not code) · **Phase:** P1

### 2.3 Abuse detection & anomaly caps
- **Per-user caps:** token/request budget per account per day (and a hard monthly ceiling), enforced server-side before the Anthropic call is made — reject with a friendly "daily limit reached" rather than silently degrading.
- **Global caps:** a circuit breaker on aggregate daily spend across all users; alert (and optionally auto-throttle new requests) when spend crosses a threshold — protects against a slow-burn distributed abuse pattern that no single per-user cap would catch.
- **Device attestation:** use **App Attest** (`DeviceCheck` framework) to bind requests to a genuine, unmodified instance of the app running on genuine Apple hardware — attach an attestation assertion to each proxy request (or periodically re-attest and issue a short-lived proxy session token). This is the concrete mechanism to "stop non-app clients from draining the key": without it, anyone who reverse-engineers the proxy's request shape can script against it directly, bypassing your UI-level rate limiting entirely. App Attest key generation + attestation happens once per install; per-request assertions are cheap.
- **Anomaly signals to log (metadata only, see §3):** request rate per user, request rate per device, unusual geographic/IP dispersion for a single account, failed-attestation rate.

**Severity:** Critical (this is the mechanism that makes "owner's key for everyone" viable at all) · **Effort:** L (App Attest integration + server-side verification + rate-limit infra is real engineering) · **Phase:** P1 for basic per-user/global caps and App Attest scaffolding; refine anomaly thresholds in P2 once real usage data exists.

### 2.4 What to do when someone tries to farm the endpoint
Assume it will happen — plan the response, not just the prevention:
1. **Detect:** alert fires from the anomaly caps (§2.3) — spike in per-account or global request volume, or a burst of failed App Attest verifications (signature of a scripted client).
2. **Contain:** auto-suspend the offending account's proxy access (not the Anthropic key) immediately; global caps prevent any single actor from exhausting the shared budget before a human looks at it.
3. **Investigate:** check whether it's a compromised/shared account (credential-stuffing pattern) vs. a reverse-engineered client hitting the proxy directly without a valid app instance (App Attest failure pattern) vs. a legitimate power user hitting a cap that's set too low.
4. **Respond:** ban device+account pair for scripted abuse; for compromised accounts, force re-authentication; for legitimate-but-heavy users, consider a paid tier rather than a hard wall.
5. **Post-incident:** if the pattern reveals a gap (e.g., App Attest wasn't actually being verified server-side, or a specific endpoint had no cap), fix and add a regression check before re-enabling.
6. Keep the Anthropic key itself out of the blast radius at every step — rotation (§2.2) is the last resort, not the first response, since the whole design goal is that individual abuse doesn't require rotating anything.

**Severity:** High (have the runbook ready before launch, not written during the first incident) · **Effort:** M · **Phase:** P1 (runbook) / ongoing

---

## 3. Health-data-over-the-wire policy (AI chat + summary features)

### 3.1 Data minimization
- Send **structured biomarkers only** to the AI (lab values + reference ranges + trend deltas — the same shape `AnalysisEngine`/`HealthReview.shareText` already produces today, per the existing `AISummaryService` pattern at `Services/AISummaryService.swift:83-103`). This is a good existing invariant — preserve it explicitly as a contract when building the chat feature, not just the one-shot summary.
- **Strip identifiers** before the payload leaves the device: no name, no DOB (send age or age-band if age-relevant context is needed), no free-text notes fields unless the user explicitly opts a specific note into a chat turn, no provider/facility names.
- **Medical ID and attachments (documents/photos) NEVER leave the device** — this must be enforced as a hard client-side invariant (literally: the chat-context builder function should have no code path that touches `ReportAttachment.data` or the Medical ID fields), not just a policy on paper. Add a unit test asserting the outbound payload builder's output never contains attachment bytes, mirroring the existing `WidgetBridgeTests` "contract lock" pattern from CLAUDE.md.
- Onboarding-quiz answers (age/sex/height/weight/lifestyle/sleep/diet/goals/concerns/supplements) are themselves sensitive (GDPR special-category health data, see §4) — apply the same minimization: only include quiz fields in an AI prompt when they're relevant to the specific question being asked, not as a standing full-profile dump on every chat turn.

**Severity:** Critical (this is the core trust promise of the product) · **Effort:** M · **Phase:** P2 (ships with the chat feature)

### 3.2 No server-side persistence of health content by default
- The proxy should be a **stateless relay**: receive request → forward to Anthropic → return response → do not write the health-content portion of the request/response to any database or log by default.
- If server-side chat history is ever considered for a "sync across devices" feature, that must be a separate, explicit, opt-in decision with its own encryption-at-rest spec — not a byproduct of building the proxy. Recommend punting this entirely (see 3.3).

**Severity:** Critical · **Effort:** M (requires discipline in the proxy's logging middleware — easy to accidentally log full request bodies) · **Phase:** P2

### 3.3 Should chat context be stored server-side? — Recommend: No
Keep chat context **client-held**. The client maintains the running conversation (SwiftData, on-device, same trust model as everything else in this app) and re-sends the relevant slice of context with each new turn to the stateless proxy. Rationale:
- Consistent with the app's entire local-first identity — CLAUDE.md is explicit that this is deliberate and should be kept "unless the user asks otherwise"; the owner's brief asks for a proxy, not a database of health conversations.
- Eliminates an entire class of breach risk (server-side chat-history database is the single juiciest target a backend could have — don't create it).
- Multi-device sync, if ever wanted, can be solved later via CloudKit/iCloud with end-to-end encryption (Apple's own account, not the app's) rather than the app's own server.
- Cost: slightly more bytes on the wire per chat turn (re-sending context) — negligible compared to the risk reduction.

**Severity:** High (architectural decision, get it right before building) · **Effort:** — (this is a "don't build X" recommendation) · **Phase:** P2 (decide before or at chat-feature kickoff)

### 3.4 TLS & certificate pinning
- TLS 1.2+ (iOS defaults already enforce this via ATS) for all client-proxy and proxy-Anthropic traffic — no exceptions/ATS carve-outs in the client `Info.plist`.
- **Certificate pinning:** recommend pinning the client-to-*your-proxy* connection (you control both ends and rotate on your own schedule) but **not** pinning client-to-Anthropic directly — that path goes away once the proxy ships (§2), and pinning a third party's cert you don't control is an availability risk if they rotate. If pinning is added, pin the proxy's leaf or intermediate CA with a documented rotation process (stale pins = app-breaking outage), and always ship a kill-switch (remote config flag) to disable pinning enforcement if a pin goes stale in production.

**Severity:** Medium · **Effort:** M · **Phase:** P2

### 3.5 Logging policy
- **Metadata yes:** request timestamp, user ID (hashed/pseudonymous where possible), endpoint hit, latency, HTTP status, token counts (for cost accounting), App Attest verification result.
- **Content no:** never log request/response bodies, prompt text, or any biomarker values in application logs, error-tracking tools (Sentry/Crashlytics-equivalent), or APM traces. Explicitly scrub/redact body fields in the logging middleware rather than trusting call sites to remember — put the redaction at the framework layer.
- Extend this policy to client-side crash/diagnostic logging too if any is added later — no health values in on-device logs that might be attached to a support email.

**Severity:** High · **Effort:** S-M · **Phase:** P1 (policy + middleware scaffold should exist from the proxy's first commit)

### 3.6 Retention
**Zero** retention of health content server-side — consistent with 3.2/3.3. Metadata (3.5) can follow a normal ops retention window (e.g. 30-90 days for debugging, then purged) since it carries no health content.

---

## 4. Compliance & platform reality check

### 4.1 HIPAA — does not apply, say so plainly
Gemocode is a direct-to-consumer app with no "covered entity" (no health plan, no healthcare clearinghouse, no healthcare provider transmitting on the app's behalf) and no "business associate" relationship — HIPAA's applicability turns on that entity relationship, not on the sensitivity of the data itself. **This remains true after the backend proxy ships**, as long as the owner doesn't enter into a data-sharing arrangement with an actual covered entity (e.g., don't pipe data to/from a clinic's EHR on their behalf). State this plainly in user-facing materials to avoid both over-promising ("HIPAA-compliant!" — a claim with no legal grounding here) and under-selling the real privacy posture the app does have.

### 4.2 GDPR / UK-GDPR — applies if distributed in the EU/UK, and it's special-category data
Health data (Art. 9 GDPR "special category data") triggers a higher bar than ordinary personal data the moment an EU/UK user installs the app (distribution, not company location, is what matters for extraterritorial reach under Art. 3).
- **Consent basis:** explicit, specific, opt-in consent (Art. 9(2)(a)) for processing health data — the onboarding quiz and AI chat features need a clear, separate consent step (not bundled into a generic ToS checkbox) before collecting lifestyle/health answers or sending biomarkers to the proxy.
- **Right to erasure is trivial when data is on-device** — for the local-only data (which remains the bulk of it even post-backend, since attachments/Medical ID never leave the device per §3.1), "delete" is just deleting the SwiftData store, which the app already effectively does via `SampleData.eraseAllData` per CLAUDE.md. **Turn this into a marketing asset**: "Delete your account and your data is gone — instantly, verifiably, because most of it was never on our servers to begin with" is a genuinely differentiated claim versus competitors who store everything server-side. Pair with §6.
- For the account-layer server-side data (user ID, entitlement, and — if 3.3's "no" recommendation is followed — no chat history), erasure is a simple row-delete; document the SLA (e.g. "within 30 days," though same-day is achievable given how little exists to delete).
- Appoint/designate a data controller contact and, if processing at meaningful EU scale, evaluate whether a Data Protection Officer or EU representative (Art. 27) is triggered — likely not at indie-app scale, but flag for legal review once user counts are known.

**Severity:** High (legal exposure, not just best practice) · **Effort:** M (consent UI + erasure-flow documentation) · **Phase:** P2 (must be resolved before EU launch of the account/AI features — the current fully-local app has minimal GDPR surface since there's no processing by the app-maker at all)

### 4.3 App Store Review Guideline 5.1.3 (health data)
- No use of health data for advertising/marketing purposes, and no third-party sharing of health data — the current app already complies (no ads, no analytics, no third parties at all). The new proxy backend must preserve this: Anthropic is a data *processor* acting on the app's instructions under its own usage policies, not a data *purchaser* — do not add any other third-party data recipient (ad networks, analytics SDKs, data brokers) without re-reviewing 5.1.3 exposure.
- HealthKit-sourced data specifically has extra 5.1.3 restrictions (already using HealthKit read/write per `Gemocode.entitlements` and `HealthKitService.swift`) — confirm the App Store Connect health-data disclosure questionnaire is answered accurately when the account/backend features ship, since "does your app transmit health data off-device" flips from No to Yes.
- Account deletion requirement (Guideline 5.1.1(v)) intersects here too — see §5.

**Severity:** High (App Store rejection risk if guideline drifts) · **Effort:** S (review checklist item) · **Phase:** P2 (re-certify before submitting the version that adds accounts/backend)

### 4.4 Anthropic usage policies for medical-adjacent products
The app already complies with the relevant posture: `AISummaryService`'s system prompt (`Services/AISummaryService.swift:40-48`) explicitly frames output as educational, forbids diagnosis/treatment/medication-change suggestions, and closes with a clinician-referral line; the code checks `stop_reason == "refusal"` before using content (line 121) rather than silently swallowing a safety refusal.
**What must stay true as chat is added:**
- Keep the "educational, not diagnostic" framing in the chat system prompt too — this is easy to lose when moving from a one-shot summary to an open-ended chat UI where users will inevitably ask "do I have X" or "should I take Y."
- Keep the refusal-handling pattern (check `stop_reason`, surface a graceful in-app message, don't retry-and-strip-safety-language).
- Continue to disclose AI involvement clearly in the UI (don't let the chat feel like it's a licensed clinician).
- Re-review Anthropic's usage policies at chat-feature kickoff (policies evolve) rather than assuming the one-shot-summary review still covers a materially different, more open-ended feature.

**Severity:** Medium (currently compliant; risk is regression, not current violation) · **Effort:** S · **Phase:** P2

---

## 5. Account layer risks

- **Sign in with Apple: recommended**, as the brief already leans toward — no password database to breach, built-in "Hide My Email" relay option, and it satisfies Guideline 4.8 (any app offering third-party login must also offer Sign in with Apple) without extra work since it'd likely be the *only* login method.
- **Identity data to store: minimize hard.** Store only: (1) the stable, opaque Sign-in-with-Apple user identifier (`sub` claim — not the relay email unless actually needed for support/receipts), (2) entitlement/subscription state, (3) usage-cap counters (§2.3). Do **not** store name, real email, or any onboarding-quiz answer server-side — those stay client-side/on-device per §3.1's minimization stance, sent to the AI proxy only as needed per-request, never persisted into an account record.
- **Deletion flow:** App Store Guideline 5.1.1(v) requires in-app account deletion, not just deactivation-then-contact-support. Implement: an in-app "Delete Account" action that (1) revokes the Sign-in-with-Apple token server-side, (2) deletes the account row + entitlement + usage-counter rows from the backend, (3) locally wipes the on-device store (reuse `SampleData.eraseAllData` pattern), (4) shows a confirmation that this is permanent, no recovery. Given §3.3's "no server-side chat context" decision, step 2 is a small, fast, auditable operation — a real advantage to lean into in the deletion-flow UX copy ("we don't have much to delete because most of it was never on our servers").

**Severity:** High (App Store requirement, not optional) · **Effort:** M · **Phase:** P2 (ships with accounts)

---

## 6. "Trust as a feature"

This app's local-first architecture is a genuine differentiator versus every cloud-first health app on the market — the roadmap should market it, not just implement it defensively.

- **Privacy nutrition label accuracy:** App Store's "Privacy Nutrition Label" (App Privacy details in App Store Connect) must be kept honest and current as data practices change — today it should show "Data Not Collected" or very close to it; once the backend/accounts/AI-chat ship, it needs an honest update (health data linked to identity: yes, for the proxy call; used for tracking: no; sold: no). Treat label accuracy as a release-gate checklist item for any PR that touches network code, not a one-time setup task — mislabeling is itself an App Store policy violation and an FTC-relevant misrepresentation risk in the US.
- **In-app privacy explainer screen:** a dedicated, plain-language screen (reachable from Settings/Profile) that states, in the app's own voice: what stays on-device (everything, until you opt into AI features), what leaves the device and when (only structured biomarkers, only when you ask the AI a question, never attachments/Medical ID), who sees it (Anthropic, as a processor, under a no-training/no-retention-by-default posture — confirm this contractually since it's a specific claim), what's stored server-side for accounts (a user ID and entitlement, nothing else), and how to delete everything (§4.2, §5). This is the natural home for surfacing app-lock status too (§1.3) and the widget-visibility toggle (§1.4).
- **Open documentation of what leaves the device:** publish this as a short, versioned, linkable doc (could live in the same explainer screen or as a public webpage linked from the App Store description) — e.g. a simple data-flow diagram: on-device store → [nothing, by default] vs. on-device store → minimized biomarker slice → proxy → Anthropic → response → back to device, never persisted. Making this *checkable* (not just asserted) — e.g., open-sourcing the minimization/redaction code path, or at minimum being precise enough that a security-conscious user or journalist could verify the claim — turns the architecture into a credible trust signal rather than a marketing slogan.

**Severity:** Medium priority as a security item, **High priority as a product/marketing lever** · **Effort:** M (design + copy + one settings screen) · **Phase:** P2 (ship alongside the account/AI features it explains — a privacy screen with nothing new to explain is less compelling)

---

## Summary table

| # | Finding / Recommendation | Severity | Effort | Phase |
|---|---|---|---|---|
| 1.1 | Move Anthropic API key from UserDefaults to Keychain | High | S | P1 |
| 1.2 | Passphrase-encrypted backup export (AES-GCM + PBKDF2) | High | M | P1 |
| 1.3 | Harden fail-open lock: onboarding nudge + visible status | Medium | S | P1 |
| 1.4 | Widget lock-screen/home-screen redaction toggle | Low-Medium | S | P2 |
| 1.5 | Add passcode attempt lockout/backoff | Medium | S | P1/P2 |
| 2.1 | Server-side secret store for owner's Anthropic key | Critical | M | P1 |
| 2.2 | Key rotation runbook | High | S | P1 |
| 2.3 | Per-user/global caps + App Attest | Critical | L | P1 |
| 2.4 | Abuse-response runbook | High | M | P1 |
| 3.1 | Data minimization for AI payloads (biomarkers only, no attachments/Medical ID) | Critical | M | P2 |
| 3.2 | No server-side health-content persistence (stateless proxy) | Critical | M | P2 |
| 3.3 | Client-held chat context (recommend: no server storage) | High | — | P2 |
| 3.4 | TLS + pin client↔proxy only | Medium | M | P2 |
| 3.5 | Metadata-only logging policy | High | S-M | P1 |
| 4.1 | State plainly: HIPAA does not apply | — | — | Doc only |
| 4.2 | GDPR consent + erasure flow; market instant on-device erasure | High | M | P2 |
| 4.3 | Re-certify App Store 5.1.3 compliance at launch | High | S | P2 |
| 4.4 | Preserve educational/no-diagnosis framing in chat | Medium | S | P2 |
| 5 | Sign in with Apple, minimal identity storage, in-app deletion | High | M | P2 |
| 6 | Privacy label accuracy, in-app explainer, public data-flow doc | Medium (High as marketing) | M | P2 |

---

# Part 6 — Growth: monetization, retention, distribution

# Gemocode — Growth Strategy

**Scope:** Positioning, monetization, retention, growth surfaces, activation funnel, and a kill/counter list for an existing, shipped, privacy-first local iOS health tracker. Analysis only — no repo files changed.

**Grounding notes from the codebase** (spot-checked, matches brief):
- Zero network calls except opt-in AI summary (`AISummaryService.swift`), which sends *review text only*, bring-your-own key stored in `UserDefaults["anthropicAPIKey"]`, checks `stop_reason == "refusal"`.
- No analytics, no accounts, no backend today — `docs/PLAN.md` runs through Phase 15; README explicitly states "No network calls by default, no analytics, no account or sign-in."
- `AnalysisEngine.HealthReview.disclaimer` and `MedicationInteractions.disclaimer` are structurally embedded in every review/PDF export — the "educational, not diagnostic" stance is load-bearing in the code, not just marketing copy.
- Widget (`WidgetBridge.swift` / `HealthScoreWidget.swift`), app-group `group.com.ogureq.gemocode`, key `widget.snapshot`, deep-links `gemocode://review` and `gemocode://trends` — already a daily-touchpoint asset, currently underused for growth.
- 46-test lab reference catalog + on-device Vision OCR (`LabScanService.swift`) + synonym matcher (`LabSynonyms.swift`) is the hardest-to-replicate technical asset in the app.

---

## 1. Positioning & Differentiation

### The wedge
**"Your blood work, explained — without your data ever leaving your phone."**

Alternate frames to test in ASO/App Store copy:
- "The lab-report app that doesn't need your data to work."
- "Understand your blood test in 60 seconds. No account. No cloud."

### Competitive map

| Competitor category | Example shape | What they do well | Where Gemocode wins |
|---|---|---|---|
| AI-chat health wrappers (generic ChatGPT-wrapper apps) | Upload a PDF, chat with a general LLM about it | Flexible, conversational | No deterministic score, no structured catalog, health data routinely sent to a general-purpose model with no medical-specific validation; positioning is "chat," not "understand" |
| Lab-analysis subscription services (e.g. consumer lab-interpretation SaaS) | Upload labs, get a report, usually cloud-processed, subscription-gated from day one | Polished report design, some are physician-reviewed | Data leaves device on *every* use, not just AI features; no free rule-based tier — Gemocode's local engine is free forever and works with zero uploads |
| Apple Health / Apple Health app | Native aggregation of HK data, no interpretation | Ubiquitous, free, deep OS integration | Apple deliberately avoids interpretation/diagnosis-adjacent scoring; Gemocode is complementary (imports from HealthKit) not competitive — pitch as "what Apple Health won't tell you" |
| General health trackers (weight/symptom loggers) | Broad but shallow | Habit loops, wide feature set | No lab-specific domain modeling (reference ranges, sex-specific ranges, drug interactions) |

### What's actually defensible
1. **Architecture as trust signal, not just claim.** Every competitor "says" privacy; Gemocode's is verifiable by the fact that the rule-based score and 46-test catalog work fully offline with zero account — this is a product truth, not a marketing claim, and it's expensive for cloud-native competitors to retrofit (their business model depends on server-side processing).
2. **Deterministic score as the moat, AI as a feature on top.** Because the 0–100 score and severity findings come from `AnalysisEngine` (pure functions, ACC/AHA BP categories, lipid ratios, regression trends, curated drug-interaction rules) rather than an LLM, the core value proposition survives even if AI costs make the AI tier get capped or removed. Competitors built AI-native have no fallback if unit economics get worse — Gemocode does.
3. **Domain depth**: sex-specific reference ranges, drug-interaction rules, lipid-ratio derivations, OCR synonym matching tuned to real lab report formats. This is unglamorous, slow-to-build catalog work that's hard to copy quickly and doesn't show up in a demo screenshot — but it is why the OCR scan actually works on real report photos.
4. **Regulatory headroom.** Staying explicitly "educational, not diagnostic" keeps Gemocode out of FDA/CE medical-device regulatory scope. This is a *feature* for positioning ("we're not a black box giving you a diagnosis") and a business-continuity requirement — do not let AI-report copy or in-app language drift toward "diagnosis" or "risk prediction," which is the fastest way to trigger regulatory reclassification and also the fastest way to erode the trust wedge.

**Non-negotiable in all growth copy**: never claim "diagnose," "predict your risk of X," or imply clinical-grade certainty. The wedge *is* the disclaimer discipline — competitors chasing engagement will over-claim, and that's the trust gap Gemocode occupies.

---

## 2. Monetization

### Constraint framing
AI inference (owner-key Anthropic API, per the backend track) is a real marginal cost per use. Everything else — OCR scan, score, trends, vitals, medications, symptoms, goals, widget, Medical ID, backup — runs entirely on-device at zero marginal cost. This is an unusually clean cost structure: **gate the metered feature, not the product.** Free tier can be generous on local features without hurting margin.

### Recommended model: Freemium with metered-AI paywall, monthly/annual subscription

**Free tier (forever free, no time limit):**
- Full local tracking: reports, vitals, medications, symptoms, appointments, goals, Medical ID
- Unlimited OCR scans against the 46-test catalog
- Full deterministic 0–100 health score + severity findings + drug-interaction warnings (this is the core trust-building product — never gate it, see Kill List §6)
- HealthKit import/write-back, PDF export, backup/restore, passcode/FaceID, widget
- **3 AI report summaries lifetime** (not monthly — see below) as a taste, clearly labeled "3 of 3 free AI reports remaining"

**Premium — "Gemocode Plus":**
- Unlimited AI health-analyst reports (the planned historical-comparison + timeline feature)
- AI chat about your reports (planned)
- Priority/faster AI generation if inference queuing is ever needed
- Price points (US market anchor, health/wellness app norms as of 2026 — comparable single-purpose health apps price monthly $7.99–$12.99, annual $39.99–$79.99):
  - **Monthly: $9.99/mo**
  - **Annual: $59.99/yr** (≈ $5/mo, a 40% discount vs. monthly — standard anchor-to-annual conversion lever)
- **7-day free trial on annual only** (Apple's standard intro-offer mechanism), not on monthly — this pushes trial-takers toward the higher-LTV plan and is the App Store norm for subscription apps avoiding low-intent monthly churn.

**Why 3 *lifetime* free AI reports, not N/month:** a monthly free allowance recurs forever as a cost with no conversion pressure (users who need "just enough" free AI every month never pay). A lifetime cap creates a clear, one-time "you've used your free look, here's what's next" moment tied to genuine value already delivered (they've seen a real AI report on their real data), which is a much stronger conversion trigger than an arbitrary decay-based allowance. Effort: **S**, Phase: **P1** (ships with the backend/accounts track since it needs server-side metering) — expected impact: this is the single highest-leverage monetization decision, directly determines whether the AI feature is profitable from day one.

### Paywall placement moments (in priority order)
1. **After first OCR scan succeeds, before the AI report offer** — do NOT paywall the scan or the rule-based score. Let the free score/findings render fully, unblocked. This is the activation moment (see §5) and must stay completely free — gating it here kills the funnel before trust is established.
2. **After first AI report preview** — show the full AI summary once (uses 1 of 3 free credits), then present the paywall *after* value is delivered, not before, framed as "Generate unlimited AI reports + chat" rather than "pay to see this." This is the primary conversion moment.
3. **On 3rd AI credit consumption** — a soft warning ("2 free reports left") should already appear on credit #2 so the 3rd doesn't feel like a trap; this is a trust move, not just UX polish, and directly protects the privacy-brand positioning (surprise paywalls read as dark-pattern, which contradicts the trust wedge).
4. **AI chat entry point** (when shipped) — chat is inherently higher AI cost per session than a single report, so it should be Premium-only from day one with no free-chat allowance; use a single free "preview message" at most, not a message quota.
5. **Quarterly health-review ritual** (see §3) — a natural upsell surface for lapsed free users ("Your 90-day comparison is ready — Premium members see the full trend story").

### Lifetime purchase — evaluate honestly
**Verdict: bad fit for the AI features, reasonable for local-only features.**
- A true lifetime-unlimited-AI purchase is a liability: Anthropic API costs are ongoing and per-use; a $99 lifetime buyer who chats daily for five years costs far more in inference than they paid. This is the single most common way indie/wellness apps blow up their own unit economics.
- **Alternative to propose**: **"Gemocode Local Lifetime" — a one-time purchase (e.g., $29.99–$39.99) that unlocks any *local-only* premium features that emerge (e.g., unlimited goals, advanced trend exports, extra widget configurations, custom lab catalog entries) but explicitly does NOT include AI reports/chat**, which stay subscription-only regardless of lifetime status. Market it honestly: "Own the local features forever. AI reports are metered separately because each one costs us real money to generate — that's the tradeoff for privacy-first AI you can trust." This honesty is itself consistent with the trust positioning and pre-empts the inevitable App Store review complaints about a lifetime tier that later excludes new AI features.
- Effort: **S** (mostly App Store Connect config + paywall copy), Phase: **P2** (after the subscription tier is validated — don't split the offer surface before Premium has product-market fit) — impact: incremental revenue from privacy purists who refuse subscriptions, low volume but reinforces brand trust.

### What NOT to do
- Do not gate the deterministic score, OCR scan count, or drug-interaction warnings — these are safety-adjacent and free-tier-defining; gating them contradicts "full local tracking is free forever" and would be the fastest way to look like every other health-app bait-and-switch. (See Kill List.)
- Do not sell data or offer any "anonymized data sharing for a discount" tier — directly contradicts the core differentiator and would be an existential trust risk if ever reported on.

---

## 3. Retention Loops

Ranked by expected retention impact (High/Medium/Low), each mapped to the feature/system that powers it.

| Rank | Loop | Powered by | Mechanism | Effort | Phase |
|---|---|---|---|---|---|
| 1 (High) | **Widget as daily touchpoint** | `WidgetBridge.swift` / `HealthScoreWidget.swift`, existing app group | Score ring + recent vitals visible on home screen without opening the app; already deep-links to Review/Trends. Currently passive — upgrade to show streak count or "2 meds due today" to convert glance into tap. | S (extends existing widget payload) | P1 |
| 2 (High) | **Score-change notifications** | `AnalysisEngine` score delta between snapshots + `NotificationService.swift` (already used for med/appointment reminders — same pattern) | Local notification when a new `ScoreSnapshot` differs meaningfully from the prior one ("Your score moved from 78 to 84 after your latest labs — see what changed"). Entirely on-device, no new privacy surface since `ScoreSnapshot` already exists. | M | P1 |
| 3 (High) | **Re-test cadence loop** | New: scheduled local notification + `MedicalReport`/`LabResult` dates already tracked | "It's been 90 days since your last CBC — re-scan or add new results to see your trend" — ties directly into the existing Trends charts and regression-based trend classification, which only get more valuable with more data points. This is the loop most likely to turn one-time scanners into repeat users, since the OCR scan is the app's most differentiated action. | M | P1 |
| 4 (Medium-High) | **Habit system: daily reminders/streaks on dashboard** | New dashboard component + `NotificationService.swift` pattern; supplement/habit reminders per the other track | Daily-open habit loop (streak counter for "logged a vital today" or "took today's meds") — standard consumer-habit mechanic, proven category-wide, but must stay tasteful given the medical context (avoid game-ified pressure that trivializes a health app: no guilt-based streak-loss messaging). | M | P2 (depends on the habit-system track landing first) |
| 5 (Medium) | **Quarterly "health review" ritual** | `AnalysisEngine` + PDF export + (planned) AI historical comparison/timeline | A seasonal nudge ("Q3 review is ready") that packages score history + trends + AI comparison into one shareable/printable artifact — good for the "bring to my doctor" use case and a natural Premium upsell surface (item 5 in paywall placements). Lower frequency than other loops so ranked below daily/90-day mechanics for raw retention impact, but high for perceived-value and conversion. | M | P2 |
| 6 (Medium) | **Medication/appointment reminders (existing)** | `NotificationService.swift` (shipped) | Already shipped and already a retention asset — not a new build, but worth explicitly counting in the loop inventory since it's the app's only currently-live recurring notification surface. | — (already shipped) | — |

**Sequencing rationale**: score-change notifications and the re-test cadence loop both reuse the *existing* `ScoreSnapshot`/`NotificationService` infrastructure (no new subsystem), so they're the cheapest high-impact wins and should land before the more novel habit-streak system, which needs its own UI and depends on the separate habit/supplement-reminder feature track.

---

## 4. Viral / Growth Surfaces (privacy-respecting, no default health-data sharing)

| Surface | Description | Privacy design | Effort | Phase | Notes |
|---|---|---|---|---|---|
| **Shareable redacted "score card" image** | Auto-generated image card: score ring + headline + app branding, explicitly *without* any lab values, vital numbers, or condition names — think "Duolingo streak share" not "here's my cholesterol." | Opt-in share action only; redaction is structural (the share-image generator simply never has access to raw values, not a toggle a user could misconfigure) | S | P1 | Cheapest, highest-leverage viral surface; reuses existing score-ring rendering from Dashboard. ASO-adjacent too — "I use an app that scores my health without uploading anything." |
| **Family accounts (caring-for-parents use case)** | Multiple profiles/reviews accessible to one adult child managing an aging parent's labs. Strong category fit — "caregiver managing a parent's meds/labs" is a well-documented, underserved segment. | Must NOT become a cloud-sync/multi-device feature by default — the honest way to do this without breaking the local-first promise is **on-device multi-profile support** (already partially possible since `HealthProfile` exists) plus an explicit, opt-in, end-to-end-encrypted share mechanism (e.g., AirDrop/iCloud Drive of an encrypted backup file, not a live server sync) if cross-device caregiving is needed. Recommend scoping P3 to on-device multi-profile only; defer any network-based family sync until there's a real backend/accounts foundation and a specific encryption design reviewed separately. | L | P3 | Evaluated honestly: strong demand signal, but "family accounts" as commonly understood (shared cloud access) is in tension with local-first unless carefully scoped. Don't let the feature name imply cloud sync it doesn't have. |
| **Referral: give/get AI credits** | "Invite a friend, you both get +3 AI reports" — reuses the AI-credit metering already needed for the paywall, so it's a free-tier extension mechanism, not a new subsystem. | No health data in the referral flow — just a code/link and credit grants | S | P2 | Needs the backend/accounts track (referral requires a server-side identity to attribute credits) — sequence after owner-key backend ships. Directly reduces CAC and reinforces the "AI is the metered, valuable thing" framing from §2. |
| **App Store Optimization** | Target search terms at the intersection of privacy and lab-literacy: "understand blood test," "lab results explained," "private health tracker," "blood work app no account." Screenshots should visually contrast "no login screen" against competitors' signup walls. | N/A (ASO copy, not a feature) | S | P1 | Cheap, no engineering dependency — can start immediately with current app. The "no account required" first-run screenshot is a differentiator competitors structurally can't copy without abandoning their own business model. |

**What to explicitly avoid on this axis**: any default social feed, any "compare your score to friends" leaderboard using real values, any auto-post-on-milestone behavior. All sharing must be a deliberate, single tap by the user, every time — no persistent opt-in toggle that silently shares future score updates.

---

## 5. Activation Funnel

### The aha moment
**First scanned lab report → instant flagged results against the 46-test catalog → AI explanation preview.**
This is the correct aha moment because it's the fastest path to a "this app understands something specific about me" reaction, it exercises the two hardest-to-replicate assets (OCR+catalog, deterministic engine) in one flow, and it naturally previews the paywall-relevant AI feature without gating the free value first. Onboarding (per the other track) should be redesigned around getting a user to this moment as fast as possible — ideally within the first session, not after profile setup friction.

### Funnel stages to instrument
1. Install → first launch → onboarding complete (disclaimer ack is already mandatory per `OnboardingView.swift` — keep it, but don't let it block a fast path to scanning)
2. First report created
3. First OCR scan attempted → **scan succeeded** (this is the activation event)
4. First Health Review generated (score computed)
5. First AI report preview shown (uses free credit 1 of 3)
6. Paywall viewed
7. Trial started
8. Trial → paid conversion
9. W1 retained (opened app again within 7 days)
10. W4 retained
11. Scans per user per month (a proxy for ongoing engagement with the differentiated feature, not just app opens)
12. Re-test-cadence notification → re-scan completion (closes loop #3 from §3)

### Metric set worth tracking
- **Activation rate**: % of new installs reaching "first scan succeeded" within session 1
- **W1 / W4 retention**: standard cohort retention, segmented by whether the user hit activation
- **Scans per active user / month**: differentiator-specific engagement metric, more meaningful than generic session count for this app
- **Paywall funnel**: view → trial start → trial-to-paid conversion, tracked as a strict funnel with drop-off at each step
- **Free AI credit exhaustion rate**: % of activated users who use all 3 free credits (signals paywall-readiness and validates the "3 lifetime" design choice)
- **Notification-driven re-engagement**: re-test-cadence nudge sent → app opened within 48h → new scan completed (validates loop #3's actual retention contribution, not just its existence)

### Minimum analytics stack recommendation
**Recommend: aggregate-only, privacy-preserving analytics (TelemetryDeck-class) — not Firebase/Amplitude/Mixpanel.**
- TelemetryDeck (or equivalent: e.g. Aptabase) hashes device identifiers client-side, never transmits PII or health content, and is explicitly positioned for exactly this "privacy-first app that still needs product metrics" niche — using it is itself a positioning-consistent choice worth naming in a privacy page ("we use TelemetryDeck; here's exactly what it collects and doesn't").
- **Hard rule**: analytics events must carry *only* funnel/behavioral signals (screen names, button taps, counts, booleans like "scan succeeded") — never lab values, vital numbers, condition/allergy text, medication names, or free-text symptom notes. This should be enforced structurally (a typed event enum with no string-payload fields for health content) rather than by convention, mirroring how `AISummaryService` already restricts its payload to review-text-only.
- Ship an in-app, plain-language disclosure of exactly what's tracked (mirrors the existing AI-summary transparency pattern) — this is a trust-reinforcing surface, not just a legal requirement.
- Effort: **S–M** (SDK integration + typed event enum + disclosure copy), Phase: **P1** — this should land *before* or alongside the monetization/paywall work, since none of §2's paywall-placement decisions can be validated without funnel data, and it's currently completely absent (README confirms "no analytics" today).

---

## 6. Kill / Counter List

Specific owner-idea patterns that would hurt growth or trust in this category, each with the concrete alternative.

| Kill this | Why it hurts growth/trust | Do this instead |
|---|---|---|
| **Gating the rule-based score or OCR scan count behind Premium** | The deterministic score is the free-tier trust anchor and the primary activation moment (§5); gating it converts the app from "privacy-first tool that also sells AI" into "another paywalled health app," destroying the wedge in one release. Also: users who can't get a free score can't be activated, so it directly shrinks the top of the paywall funnel it's meant to grow. | Keep score/findings/interactions/OCR unlimited and free forever; gate only the metered AI layer (§2). |
| **"Free trial requires credit card" dark pattern for the AI tier** | Standard subscription-app friction, but for a privacy-positioned app it reads as especially hypocritical — "we protect your data but we'll trap you in a subscription." Directly undermines trust-based ASO/reviews, which are the app's cheapest growth channel. | Use Apple's standard 7-day free trial on the annual plan with a clear pre-trial-end reminder notification (Apple sends these automatically for App Store subscriptions) — no dark patterns needed since the native subscription flow already handles cancellation cleanly. |
| **Cloud-syncing health data "to enable family accounts" or "for backup convenience"** | Directly reverses the core on-device-only claim; even framed as opt-in, adding a server-side health-data store creates a permanent new attack surface, new compliance exposure (HIPAA-adjacent scrutiny risk despite not being a covered entity), and a talking point competitors/press could use against the app the moment it ships. | On-device multi-profile + user-controlled encrypted file export/AirDrop for cross-device/family sharing (§4); if true sync is ever needed, scope it as an explicit, clearly-labeled, separately-consented feature — never silently bundled into "family accounts" or "backup." |
| **Selling or "anonymizing and sharing" aggregate health data for revenue** | Even fully anonymized, this is the single fastest way to convert a trust-based differentiator into a liability if ever disclosed — health data resale is a uniquely sensitive category for press/regulatory attention, disproportionate to whatever revenue it would generate for an app this size. | Don't. Monetize the AI-inference cost gap (§2) and referrals (§4) instead — both are transparent, defensible, and don't touch the privacy claim. |
| **AI features that drift into diagnostic or risk-prediction language** ("your risk of diabetes is X%", "this indicates you may have...") | Crosses from educational into diagnostic/medical-device-adjacent territory, which risks regulatory reclassification (FDA SaMD scrutiny) and directly contradicts the CLAUDE.md-level non-negotiable stance; also a real harm risk if users act on a false-confidence AI claim from a general-purpose LLM. | Keep AI output framed as "here's what these numbers typically mean" with the existing disclaimer pattern (`HealthReview.disclaimer`, `MedicationInteractions.disclaimer`) mechanically attached to every AI report and chat response, same as it's attached to the rule-based review and PDF export today. |
| **Engagement-maximizing streak/guilt mechanics** ("Don't break your streak!" push copy, red badge pressure) borrowed wholesale from generic habit apps | A health-anxiety-adjacent audience (people tracking blood work, symptoms, medications) is more vulnerable to guilt-driven engagement patterns than a generic fitness-app audience; aggressive streak pressure risks real user harm and reads as manipulative given the trust positioning. | Frame habit loops (§3, item 4) around supportive framing ("Welcome back — here's what's new" rather than "You lost your streak"), and make streak mechanics fully optional/dismissible. |
| **Metering or throttling the drug-interaction checker** (e.g., "premium gets more thorough interaction checking") | Interaction warnings are safety-adjacent; creating a two-tier safety feature (better warnings for paying users) is both an ethical problem and a reputational one — "app hides drug interaction warnings behind a paywall" is a guaranteed negative-press headline in this category. | `MedicationInteractions` stays fully free and identical across tiers, no exceptions, regardless of future catalog expansion. |
| **Growth-hacking via default-on data sharing toggles** (e.g., pre-checked "help us improve Gemocode by sharing anonymized health trends" during onboarding) | Dark-pattern opt-in during onboarding is exactly the move that erodes trust fastest and is increasingly an App Store review/regulatory target (App Tracking Transparency precedent shows Apple scrutinizes exactly this pattern). | Any data-sharing toggle (including the recommended aggregate analytics in §5) must be off by default, or scoped to non-health behavioral events only with explicit, un-pre-checked opt-in and a one-tap disclosure of exactly what's sent. |

---

## Summary Table: Effort × Phase × Impact

| Initiative | Section | Effort | Phase | Expected impact |
|---|---|---|---|---|
| 3 lifetime free AI reports + metered paywall | 2 | S | P1 | Revenue — primary monetization mechanism |
| Paywall after AI preview (not before) | 2 | S | P1 | Conversion rate, trust preservation |
| 7-day trial on annual only | 2 | S | P1 | LTV, conversion mix toward annual |
| "Gemocode Local Lifetime" (local-only) | 2 | S | P2 | Incremental revenue, brand reinforcement |
| Score-change notifications | 3 | M | P1 | Retention — high, reuses existing infra |
| Re-test cadence loop (90-day nudge) | 3 | M | P1 | Retention — high, drives repeat scans |
| Widget upgrade (streak/med-due) | 3 | S | P1 | Retention — daily touchpoint amplification |
| Habit/streak dashboard system | 3 | M | P2 | Retention — medium, depends on other track |
| Quarterly health-review ritual | 3 | M | P2 | Retention + Premium upsell surface |
| Shareable redacted score card | 4 | S | P1 | Viral/CAC — cheap, high-leverage |
| ASO copy/screenshot refresh | 4 | S | P1 | CAC — immediate, no engineering dependency |
| Referral (give/get AI credits) | 4 | S | P2 | CAC — needs backend/accounts first |
| Family accounts (on-device multi-profile) | 4 | L | P3 | New-segment growth, scope carefully |
| Aggregate-only analytics (TelemetryDeck-class) | 5 | S–M | P1 | Enables measuring everything else — sequence first |

**Bottom line sequencing**: P1 should ship analytics instrumentation, the metered-AI paywall design, the two cheapest high-impact retention loops (score-change + re-test notifications), and the shareable score card + ASO refresh — all before or alongside the backend/accounts track, since several of these (referral, family sync evaluation) explicitly depend on it landing first.
