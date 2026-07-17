# Gemocode Execution Playbook — solo founder, 90 minutes/day

Operating manual from today (post-build, pre-beta) to first paying customers,
then 10 → 100 → 1,000. Written against the REAL current state:

- DONE: app built & running on device, relay live, site live at gemocode.com,
  App Store listing copy (docs/marketing/app-store-listing.md), 11 video
  scripts (docs/marketing/content-bank.md), creator kit, Reddit/PH/HN drafts,
  pricing ($19.99/mo Premium, one free AI scan-and-report).
- BLOCKED ON OWNER: Apple Developer enrollment (in progress), relay
  ANTHROPIC_API_KEY re-put, ENFORCE_PREMIUM flip before launch.
- FROZEN: no new features until Phase 4 says so. The app is v1-complete.

## The one rule

Every day has 90 minutes. The split is always roughly:
**60 min = the single gating task** (the thing blocking the next phase),
**30 min = audience building** (one piece of content or 5 conversations).
Never invert this. Never spend the 60 on polish nobody asked for.

## Channel decision (made once, now)

For a consumer iOS health app with $0 budget, the highest-ROI channel mix is:
1. **Short-form video** (TikTok + Instagram Reels + YouTube Shorts, same
   video all three) — health/self-tracking content has organic reach there,
   the scan→values demo is inherently visual, and scripts already exist.
2. **Reddit personal-story posts** (r/Biohackers, r/QuantifiedSelf,
   r/Hypothyroidism, r/diabetes_t2, condition subs) — where the ICP already
   discusses lab results. Story-first, never link-first.
3. **App Store SEO** — the listing kit already targets "blood test tracker /
   lab results / retest" cluster; this compounds passively.

Deliberately SKIPPED (low ROI for this product/time budget): LinkedIn,
Facebook groups, cold email to consumers, paid ads, Discord community
building, SEO blogging beyond the 4 existing articles, Product Hunt as a
main bet (it's a one-day spike for consumer iOS; we do it, but as a Tuesday
side-quest, not the strategy). Hacker News only via the existing Show HN
draft — the privacy architecture angle is genuinely HN-worthy, but treat
front-page as a lottery ticket.

---

## PHASE 0 — Unblock (Days 1–3)

**Objective:** beta installable by a stranger.
**Why:** every marketing minute before an installable link is half-wasted.
**Success criteria:** TestFlight public link works on a friend's phone; AI
report generates on your phone.

### Day 1 (90 min)
- 0–15: Fix the AI key: console.anthropic.com → new API key → in
  backend/: `npx wrangler secret put ANTHROPIC_API_KEY` → paste → test a
  report in the app on your phone.
- 15–45: Apple enrollment: enable 2FA on your Apple ID, then enroll from
  the **Apple Developer app on your iPhone** (Account → Enroll Now, scan
  your ID). Pay the $99.
- 45–75: While Apple reviews: `git pull` on the Mac, rebuild, confirm the
  three fixed screens (onboarding box, goals chips, review overlap) on
  your phone.
- 75–90: Send a test email to info@gemocode.com; confirm the forward works.
  Post nothing today.

### Day 2 (90 min)
- 0–30: Use the app for real: scan an actual lab report of yours (or the
  sample from Load Sample Data), generate the AI report, export the PDF.
  Write down every moment that annoyed you (bugs list, not wishlist).
- 30–60: File the top 3 annoyances as issues for Claude to fix. Only
  crashes and confusions count — no feature ideas.
- 60–90: Record raw footage #1: 60 seconds of screen recording of the scan
  → decoded values flow on your phone (Settings → Control Center → Screen
  Recording). No editing yet. This is the raw material for the first video.

### Day 3 (90 min) — assumes Apple approval landed (usually 24–48h)
- 0–30: App Store Connect: create the app record: name "Gemocode: Lab &
  Health Diary", bundle id com.ogureq.gemocode, primary language English.
- 30–60: In Xcode: Product → Archive → Distribute → App Store Connect →
  Upload. (First time: let Xcode manage signing.)
- 60–90: App Store Connect → TestFlight tab → fill in beta description
  (paste the promo text from the listing kit) → enable external testing →
  create the **public link**. Send the link to Claude to wire into
  beta.html. Install via TestFlight on your own phone to verify.

If Apple approval is still pending on Day 3, swap in Day 4's tasks.

## PHASE 1 — Private beta (Days 4–14)

**Objective:** 20 real testers, 10 pieces of feedback, zero crash reports
for 3 consecutive days.
**Why:** strangers find what you can't; testimonials for launch come from
here; App Review rejects broken apps and you get one bad first impression.
**Common mistake:** building features testers ask for. Log everything, fix
only breakage and confusion.
**Success criteria:** 20+ installs, a crash-free week, 3 testers who said
something quotable, App Store screenshots done.

### Day 4 (90 min)
- 0–20: Text/DM the TestFlight link personally to 10 people you know with
  any health tracking habit (family with conditions count double). Message:
  "I built an app that reads your blood test PDFs and tells you when
  you're due for the next one. 2-min install, would love your eyes on it:
  [link]".
- 20–50: Edit raw footage #1 into video #1 using CapCut (free, phone):
  follow content-bank script #1 (scan demo). Captions on, no voiceover
  needed, 25–35 seconds.
- 50–80: Create TikTok + Instagram + YouTube accounts @gemocodeapp (same
  handle everywhere). Bio: "Scan your labs. Know when you're due. Private
  by design." Link: gemocode.com.
- 80–90: Post video #1 to all three. Best posting window: 18:00–21:00
  local. Reply to every comment within 24h, always ending with a question.

### Day 5 (90 min)
- 0–30: Reddit: post the prepared r/QuantifiedSelf story (content-bank
  Reddit post #1) — personal story first person, mention the beta link only
  in a comment when asked, never in the post body (subreddit rules).
- 30–60: Fix day: give Claude the tester feedback that came in; pull,
  rebuild, push a TestFlight build update if anything shipped.
- 60–90: Record raw footage #2 (Tests Due dashboard walkthrough — the
  "know when you're due" moment; content-bank script "Tests Due").

### Days 6–14 pattern (repeat, 90 min each)
- 0–30: Feedback loop: read TestFlight feedback + comments on every
  platform, reply to all, forward bugs to Claude, ship fixes every 2–3 days.
- 30–60: One growth action, rotating: (a) edit+post next video from the
  script bank — every 2nd day; (b) one Reddit story post in ONE new
  subreddit — every 3rd day, never the same sub twice in 10 days; (c) DM 5
  micro-creators (5k–50k) from the creator kit with its outreach message —
  every 3rd day.
- 60–90: App Store prep, one asset per day: screenshots per the listing
  kit's 7-shot plan (use your real phone + real sample data), preview
  video, privacy nutrition labels, age rating questionnaire, review notes.

By Day 14 you should have: ~6 videos posted, 3 subreddit posts, 15
creator DMs, all App Store assets ready.

## PHASE 2 — Submission & launch prep (Days 15–21)

**Objective:** app approved and dormant on the App Store; launch assets
staged; ENFORCE_PREMIUM on.
**Why:** approval takes 1–3 days and sometimes a rejection round; you want
approval BEFORE launch day so launch is a button, not a prayer.
**Common mistakes:** launching the moment it's approved (you lose the
coordinated push); leaving the relay unmetered (free AI for the world).
**Success criteria:** "Pending Developer Release" status; StoreKit
subscription approved; relay enforcing premium; launch posts drafted.

Daily 90-min split:
- Day 15: Create the $19.99/mo subscription + yearly in App Store Connect
  (App → Subscriptions). Fill App Review notes: demo instructions ("Profile
  → Data → Load Sample Data"), explain the one-free-scan model. Submit for
  review with "Manual release".
- Day 16: Ask Claude to implement App Store server verification + flip
  ENFORCE_PREMIUM (the one remaining backend task). Test premium gating on
  TestFlight with a sandbox account.
- Day 17: Draft launch-day posts from the content bank (PH draft, Show HN
  draft, 3 subreddit launch posts, X thread). Stage, don't post.
- Day 18: Generate 5 StoreKit **offer codes** (1 month free) for your best
  beta testers; message them: "you were here first — launch is Tuesday,
  here's Premium free for a month. If it's been useful, an App Store review
  on day one would mean everything."
- Day 19–21: Buffer for App Review rejection fixes (statistically ~40% of
  first submissions get one round). If approved early: record 2 more
  videos, rest the queue.

## PHASE 3 — Launch week (Days 22–28)

**Objective:** first paying customer.
**Why this works:** you're not launching cold — you have testers, an
audience seed, and staged content.
**Launch day = Tuesday** (best PH/press day; weekend is the worst).

- Day 22 (Mon): Press "Release" in App Store Connect evening-time so it
  propagates overnight. Claude flips beta.html's button to the App Store
  link. Final smoke test: buy Premium yourself with a real card, refund via
  reportaproblem.apple.com after.
- Day 23 (Tue, launch): 0–20: Product Hunt post goes live (schedule 00:01
  PT); 20–40: Show HN post ("Show HN: I built a lab-report tracker where
  your data never leaves the phone") — architecture-first comment ready;
  40–60: the 3 subreddit launch posts; 60–90: reply to everything
  everywhere; post launch video on TikTok/Reels/Shorts.
- Day 24–28: 0–45 replying/fixing (respond to every App Store review, PH
  comment, Reddit thread — this IS marketing), 45–90 next video + DM the
  creators who answered ("app's live now, code inside").

**First-customer playbook:** your first 1–5 paying users come from beta
testers converting + launch-week viewers. Ask every free user who scans
their one free report, in-app moment already does it (paywall). Ask every
paying user personally (email via info@): "what almost stopped you from
subscribing?" — that answer is your next week's fix list.

## PHASE 4 — 10 → 100 customers (Weeks 5–12)

**Objective:** 100 paying subscribers ≈ $2K MRR.
**The weekly rhythm (7 × 90 min):**
- 2 days: video content (scripts rotate through the content bank; refresh
  hooks from real user quotes).
- 1 day: one Reddit story post OR one collab with a responding creator.
- 1 day: ship day — fixes from the week's feedback (Claude builds, you
  test on device, release).
- 1 day: App Store optimization: check keyword rankings (free tier of
  AppFigures/Astro), iterate promo text (editable without review), respond
  to every review.
- 1 day: talk to 5 users (email or Reddit DM). Ask only: "what did you
  hope it would do that it didn't?"
- 1 day: metrics + rest (see dashboard below).

**Feature policy:** ship ONLY what ≥3 paying users independently asked
for. Everything else goes in a "later" list, unexamined. Wishlist items
from free users count 1/3.

**When to add the referral program:** at ~50 paying users, ask Claude for
"give a month, get a month" via StoreKit offer codes. Not before — referral
programs amplify existing pull, they don't create it.

## PHASE 5 — 100 → 1,000 (Months 4+)

Only three levers matter now; check monthly, do the biggest gap:
1. **Conversion** (free scan → paid): if <5%, the paywall moment is the
   problem — improve the free report's ending, not the app.
2. **Retention** (month-2 subscriber survival): if <70%, the Tests Due
   loop isn't hooking — invest in reminder quality, not new features.
3. **Top of funnel** (installs/week): if flat 3 weeks running, double
   video output for a month and add localized keywords (German/Japanese
   per the marketing plan) before any paid spend.
Paid ads only after: >8% conversion, >75% retention, and >$3K MRR to fund
them. Apple Search Ads on your own brand + "blood test tracker" exact
match, $10/day cap, kill if trial-install cost exceeds one month's price.

## Metrics dashboard (check twice a week, 10 minutes, no more)

| Metric | Where | Healthy |
|---|---|---|
| Installs/week | App Store Connect | growing any % |
| Free scan used | relay logs (KV count) | >40% of installs |
| Scan → paid conversion | App Store Connect | >5% |
| Month-2 retention | subscriptions report | >70% |
| Crash-free sessions | Xcode Organizer | >99.5% |
| MRR | App Store Connect | up and to the right |

**Pivot triggers (honest ones):** if after 8 weeks of consistent execution
installs grow but conversion stays <2% → the price or the paywall moment is
wrong (test $9.99 before concluding anything). If installs themselves stay
<50/week despite 20+ videos → the pitch is wrong, not the product: re-test
positioning angles (money-saving vs privacy vs AI) in video hooks and let
view-through rates vote.

## What NOT to do (standing bans)

- No new features during Phases 0–3. None.
- No Android, no web app, no "quick" iPad optimization.
- No paid ads before the Phase 5 gate.
- No custom analytics SDK — App Store Connect + relay logs are enough and
  keep the privacy story clean.
- No newsletters, blogs, or "community building" — you have 90 minutes.
- No redesigns. The design is done.
- Never argue with a negative review or comment; thank, fix, follow up.
- Never paste API keys anywhere but Cloudflare's secret prompt.

## Automation & delegation map

- Claude (this session): all code, site updates, copy revisions, App Store
  metadata iterations, log analysis — treat as your CTO; batch requests.
- CapCut auto-captions: video editing ≤20 min/video.
- Buffer (free tier): schedule the week's posts in one sitting.
- Cloudflare dashboards: relay usage & abuse watch, 2 min/week.
- TestFlight/App Store Connect emails: the only notifications allowed to
  interrupt your day.
