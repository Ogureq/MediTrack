# Gemocode Marketing Playbook

Working document for taking Gemocode from zero users to a scalable business.
Grounded in strategies proven by comparable apps (Cal AI, Bearable, Flo, Levels,
Function Health, Finch) and adapted to this app's actual moats. Figures marked
*(est.)* are estimates to be replaced with real cohort data.

**Honest baseline:** solo founder, pre-App-Store, $0 revenue, no audience.
**Product moats:** (1) retest intelligence — the app remembers when each
blood test was last taken and shows when it's commonly due again, so users
stop paying for duplicates and stop missing overdue ones; (2) a full lab
history in your pocket — walk into any doctor's office without re-explaining
yourself, and nothing gets re-ordered from scratch; (3) local-first privacy —
no account, health data never leaves the device, the only such app in the
category; (4) every *tracking* feature (vitals, meds, symptoms, goals,
score, trends, Tests Due) is free forever, with one free lifetime AI
scan-and-report as the taste of Premium; (5) built-in retention mechanics
already shipped (streaks, quarterly ritual, widgets, Tests Due reminders).

**Pricing facts (Jul 2026, current):** lab report scanning and all AI
features (chat, AI-assisted entry, unlimited reports, the PDF export) are
Premium at $19.99/mo. Free users get one lifetime AI scan-and-report as a
trial — that trial is also the only way a free account ever scans a lab.
Tracking, the health score, trends, the widget, Apple Health sync, and Tests
Due retest reminders are free forever because they're on-device rule-based
computation, not AI. Nothing in this document should describe scanning/OCR
as free forever — say "free tracking" or "the free trial," never "free
scanning."

---

## 1. Market positioning

### Ideal customer profile

**Primary — "the lab binder person" (build everything for them first):**
ages 28–55, manages an ongoing condition or optimization goal — hypothyroid /
Hashimoto's, high cholesterol on statins, prediabetes, PCOS, long-recovery —
gets blood work 2–6× a year through insurance, currently keeps results as PDF
attachments in email or a paper binder, and googles each marker after every
draw. They are anxious *and* under-served: the doctor spends eight minutes on
results that took three weeks to arrive, and half the time a new provider
re-orders a panel because nobody had the old one.

**Secondary ICPs:**
- **Privacy-first health consumer** — radicalized by the 23andMe bankruptcy
  data scare and period-tracker subpoena stories; hangs out in r/PrivacyGuides
  and watches Techlore. Small but loud, and they evangelize.
- **The caregiver** — managing a parent's labs, meds, and appointments across
  fragmented portals, and picking up the bill when a test gets duplicated.
- **Biohacker-lite** — wants Function Health insights without $365/yr; already
  quantifies sleep/HRV.

### Pain points ranked by intensity
1. "I got billed again for a test I had eight weeks ago — nobody had my
   history, so it got re-ordered from scratch."
2. "I have no idea when I'm actually due for my next panel, so I either
   forget it for a year or get talked into one I don't need yet."
3. "I get a PDF of 30 numbers and nobody explains them."
4. Results scattered across Quest, Labcorp, hospital portals, and paper.
5. Eight-minute appointments; forgotten questions.
6. Googling markers produces worst-case anxiety, not trends.
7. Health apps harvest and resell data (top-of-mind for ICP #2).
8. Lab-testing subscriptions cost $199–589/yr for draws insurance already covers.

### Unique value proposition
> **Never lose a lab result. Never guess when you're due for the next one.**
> Gemocode remembers every blood test you've had and tells you — based on
> commonly recommended intervals — when you're likely due again, so you
> skip the duplicate and never miss the overdue one. Walk into any
> appointment with your full history already in your pocket. Tracking is
> free forever, with one free AI scan-and-report to try. Your health data
> never leaves your iPhone. No account.

### Positioning vs. competitors
- Function Health / InsideTracker / Superpower **sell new blood tests**; we
  monetize *understanding and timing* of tests users already get, often free
  through insurance. Never compete on testing; always frame as complementary
  ("love Function? Track those results — and know when your next one's
  actually due — privately too").
- Apple Health **stores** numbers, explains nothing, and has no concept of
  "when am I due again" or lab OCR.
- Guava Health / CareClinic sync records **to their cloud**, lean on US
  portal integrations, and don't compute a retest schedule; we are the
  private option, OCR works on any paper lab worldwide, and the app tells
  you when you're due without you doing the math.
- Positioning sentence: **"Know when you're due. Know when you're not."**
  (privacy — "the private lab tracker" — is the strong #2 line in every
  longer pitch, never dropped, never leading.)

---

## 2. Growth strategy — three engines

### Engine A: Creator-led short video (the Cal AI playbook, adapted)
Why it worked for Cal AI: an instantly demoable magic moment (photo → calories),
high-volume micro-influencer outreach (hundreds contacted, ~150 on retainer
posting ~4×/month), a ~$5 CPM price target, referral codes for creators, then
Meta/Google paid on proven creatives. Gemocode has two screen-recordable magic
moments now: the "Tests due" card lighting up red/green ("overdue" vs. "not
yet — skip it"), and scan-a-lab-PDF → decoded trends.
Adaptation: recruit micro creators (5k–100k) in chronic-illness TikTok
(#hashimotos, #pcos, #cholesterol), nurse-educator TikTok, and longevity
niches. Train a fresh TikTok account's For You page on these niches to source
creators (Cal AI's exact sourcing trick). Pay flat + referral code redeemable
as free premium months. Target ≤$5 CPM; drop creators who miss 2× in a row.

### Engine B: Community-led trust (the Bearable playbook)
Bearable (symptom tracker) grew almost entirely from Reddit by having the
founder answer questions in chronic-illness subreddits for months before ever
posting about the app. Health-anxious communities detect marketing instantly;
they reward genuine usefulness. Rule: 10 helpful comments per 1 mention of the
app; the app being free-with-no-account for tracking makes mentions land as
help, not sales.
Target subs: r/Hypothyroidism, r/Thyroid, r/Cholesterol, r/prediabetes, r/PCOS,
r/ChronicIllness, r/Biohackers, r/QuantifiedSelf, r/PrivacyGuides, r/Longevity.
Parallel: build-in-public on X and Indie Hackers (screenshots, revenue,
architecture posts) — compounding founder distribution.

### Engine C: Search capture (the Flo playbook, scaled to indie size)
Flo built a moat from thousands of medically-reviewed articles matching health
searches. Scaled-down version: (1) ASO first — own "blood test tracker",
"lab results tracker", "test reminders", "when to retest [marker]", "health
records app"; (2) one web page + one YouTube video per catalog biomarker
("What does high ALT actually mean, and how often should you retest it?") —
46 markers = a 46-piece content map that mirrors the in-app explanations
already written for LabDetailView, each one ending on the retest-cadence
question rather than just the definition.

### Acquisition funnel
Hook (creator video / Reddit answer / marker article) → App Store page
(first screenshot = the Tests Due card lighting up "overdue" vs. "not yet";
second = "No account. No cloud." privacy badge) → onboarding quiz → **activation
= first record logged or first Tests Due reminder seen within 10 minutes** →
day-2/3 prompt to spend the one free AI scan-and-report (the taste) →
Tests Due reminders + quarterly ritual hold retention → premium at the
moment they want a second scan or a second AI action.

---

## 3. Content marketing

### Pillars
1. **Money & timing** (30%) — the Tests Due card, skip-the-duplicate stories,
   walking into an appointment with full history, "commonly recommended, your
   doctor may advise differently."
2. **Privacy** (25%) — health-data-broker stories, 23andMe fallout, "no login" demos.
3. **Lab literacy** (30%) — decode markers, trends, "questions to ask your doctor."
4. **Product magic / build-in-public** (15%) — raw screen recordings of Quick
   Add, quarterly recap, and X/IndieHackers metrics-and-architecture posts.

### Hooks that map to proven formats
- "I stopped paying for a lab I already had — the app told me it wasn't due yet."
- "Your doctor spends 8 minutes on results that took 3 weeks to arrive — and
  didn't know you'd already had this test."
- "A duplicate lab panel can cost more than a month of tracking it wouldn't have. Here's the card that stops it."
- "This health app has no login button. That's the whole point."
- "POV: you finally understand your thyroid panel." (nurse-tok duet bait)
- "What your LDL number actually means — and when you actually need to retest it."
- "I asked AI to explain my cholesterol — but it only sees my summary, never my files."
- "Rating my health app's privacy policy vs. the top 5 trackers." (creator collab format)

### Three 30-second scripts (screen-record + voiceover)
1. **Tests due.** Cold open on a hand holding two lab bills. "I paid for this
   test twice — six weeks apart." Cut to the Dashboard's Tests Due card:
   Lipid Panel flagged "not due for 11 weeks," Thyroid flagged "overdue."
   "Now it just tells me." Close on the accurate framing: "commonly
   recommended — always your doctor's call."
2. **The privacy flex.** "Sign-up screen speedrun, health app edition." Show 3
   competitor sign-up walls, then Gemocode opening straight to the dashboard.
   "No account. No cloud. Airplane-mode demo. Your labs are yours."
3. **The quarterly review.** "Every 90 days my phone gives me a health recap
   my doctor would charge a copay for." Scroll trajectory → wins → doctor
   questions → ShareLink.

### Schedule
- TikTok 1/day, repurposed to Reels + Shorts (same clip, native captions).
- X: 3–5 build-in-public posts/week; one thread/week.
- Reddit: 3 value posts/week across target subs + daily comment presence.
- YouTube: 1 biomarker-explainer/week (doubles as Engine C SEO).
- FTC compliance: every paid creator post carries #ad; zero medical claims —
  educational framing only, mirroring the app's own disclaimers.

---

## 4. Launch strategy

### Pre-launch (weeks 1–4)
Landing page with the "know when you're due" lead + TestFlight waitlist
(Function Health proved scarcity works in health — use "beta invites in
batches"). Recruit ~50 beta users directly from target subreddits (they
become launch-day testimonials and App Store reviews). Bank 20 short videos
before launch day.

### Launch week
Fire everything the same week: Product Hunt (the "know when you're due"
angle historically resonates alongside privacy on PH), Hacker News "Show HN:
A health tracker where your data never leaves the phone" (local-first
architecture is HN catnip; link the repo README's privacy section),
coordinated genuine posts in 5 subreddits, 10 creator videos live,
build-in-public launch thread.

### First 1,000 users *(est.)*
~300 PH/HN, ~400 Reddit, ~300 TikTok organic. Everything hand-to-hand; reply
to every comment for 72 hours.

### 1k → 10k
Creator engine at 20–30 micros posting monthly + ASO rankings maturing +
weekly content cadence. The one free AI scan-and-report is the conversion
story: measure taste→premium.

### 10k → 50k
Apple Search Ads exact-match + TikTok Spark Ads on the top 3 organic
creatives. Pitch App Store featuring (Apple actively features privacy-forward
and accessibility-strong apps — both are true here; the VoiceOver pass is a
genuine story).

### 50k → 100k
Localize DE/JP/FR (privacy-sensitive, paper-lab-heavy markets where BYO-labs
OCR beats portal-dependent US competitors), press cycle ("the health app that
tells you when you don't need a test" to The Verge/TechCrunch/9to5Mac),
referral program fully live.

---

## 5. Paid acquisition

**Platforms in order:** (1) Apple Search Ads exact match — "blood test
tracker", "lab results app", "test reminders", competitor brand terms;
highest intent, start $20/day. (2) TikTok Spark Ads boosting proven organic
creator posts (never cold studio creative first). (3) Meta after creative
validation — note both platforms restrict health-condition targeting, so
creative does the targeting: broad audiences, condition-specific hooks.

**Ad angles:** the Tests Due card (overdue vs. skip-it); the privacy flex
("no account" speedrun); the duplicate-test cost story — phrased as a
hypothetical, never a quantified per-user savings claim (e.g., "when a
duplicate panel gets billed at an uninsured or facility rate, that single
bill can run past what a full year of Premium costs" — true in plausible
worst-case billing scenarios, never stated as "you will save $X"); the
doctor-visit prep ("walk in with your history, not a blank slate").

**Benchmarks *(est., replace with cohort data)*:** iOS health CPI $2–4;
onboarding→activation 40–55%; free-trial-use rate 25–35% of activated;
taste→premium 8–12% within 30 days. Blended CAC target ≤$25 against
$19.99/mo (payback <2 months at ~60% M1 premium retention). Kill any channel
above $40 CAC after $500 spent.

**Budget tiers:** $0 — engines A(organic)/B/C only; $1k/mo — ASA exact +
Spark boosts + 5 creator retainers; $10k/mo — Meta scale on proven creative +
25 creators (Cal AI sequencing: organic finds the winners, paid pours fuel).

---

## 6. Community & retention

Already shipped (use in marketing, don't rebuild): streaks, quarterly ritual,
score-change + Tests Due retest notifications, widgets, redacted share card.

- **Activation:** onboarding must reach "first record in 10 minutes"; the
  quiz already seeds reminders — measure and cut any step with >10% drop.
- **The taste:** prompt the free AI scan-and-report after the first lab is
  logged, not at install (data makes the report impressive, and it's the
  only way a free account ever sees the scan feature).
- **Review prompt:** trigger `SKStoreReviewController` after completing a
  quarterly review — the app's peak-delight moment.
- **Referral loop (build item):** "Give a scan, get a scan" — referred
  friend gets +1 free AI scan-and-report, referrer gets one too. COGS ≈ $0.10
  *(est.)* per report; needs a relay-side redemption flag.
- **Viral surface:** the redacted score card and quarterly recap ShareLink
  already exist — add a subtle "Tracked with Gemocode" watermark.
- **Community:** a "Lab Literacy Club" subreddit/Discord seeded from beta
  users; weekly "decode this (anonymized) panel, and when should they
  retest?" threads.
- **Churn:** cancel-flow survey, pause-month option, annual plan at 2 months
  free; win-back push when a Tests Due reminder fires post-churn.

---

## 7. Partnerships

1. **Micro-creators** (core engine): nurse educators, registered dietitians,
   "labs explained" accounts, chronic-illness advocates, longevity podcasts
   <100k. Outreach: 20 DMs/day from the trained account; offer flat fee +
   referral code; target ≤$5 CPM (Cal AI's number).
2. **Privacy ecosystem:** Techlore, PrivacyGuides, small privacy newsletters —
   they rarely get a *health* app they can endorse; a fully free tracking
   tier makes it credible.
3. **Adjacent brands, no data sharing:** at-home phlebotomy services and
   direct-to-consumer lab ordering (Ulta Lab Tests, OwnYourLabs) — their
   customers get raw PDFs and need exactly this app to track when the next
   draw is actually due; co-marketing only, never integrations that touch data.
4. **Newsletter sponsorships:** indie longevity/health-optimization
   newsletters ($50–300 placements) before podcasts ($1k+).
5. **Later:** HSA/FSA eligibility for premium; employer wellness lists.

Approach template: short, specific, show the Tests Due demo GIF, offer the
code, no exclusivity, monthly renewal only if the post clears the CPM bar.

---

## 8. Competitor breakdown

| Competitor | Price | Model | Their playbook | Their gap we exploit |
|---|---|---|---|---|
| Function Health | $365–499/yr | Sells 100+ marker panels 2×/yr | Waitlist scarcity, Mark Hyman audience, longevity press | Ignores insurance-covered labs; sells tests instead of timing them; US-only; cloud |
| InsideTracker | $149/yr + $489–589 tests | Performance testing + DNA | Athlete positioning, science-blog SEO | Expensive, athlete-narrow; no BYO records, no retest scheduling |
| Superpower | $199/yr | Panels + AI + telehealth Rx | Feature breadth, comparison landing pages | Still sells draws; data lives server-side |
| Guava Health | Freemium | Cloud PHR + portal sync | US portal integrations, records aggregation | Cloud storage; portal-dependent (fails on paper/foreign labs); no retest math |
| Bearable | Freemium | Symptom/mood tracking | Founder-led Reddit community | No labs, no OCR, no retest scheduling |
| Apple Health | Free | System record store | Default install | Stores but never explains or times anything; no lab OCR, no trends narrative |

Tactics to copy directly: Function's batched-waitlist scarcity (TestFlight),
InsideTracker's per-marker SEO library (retest-cadence angle we own that they
don't), Superpower's "X vs Y" comparison pages (rank for "Function Health
alternative"), Cal AI's creator volume + CPM discipline, Bearable's
founder-in-the-comments authenticity.

---

## 9. 90-day execution roadmap

**Weeks 1–2 — foundations.** App Store assets (screenshot 1 = Tests Due
card, screenshot 2 = privacy badge, video preview = 30s script #1); landing
page + waitlist; privacy-respecting analytics (e.g. TelemetryDeck — fits the
brand); record 6 demo videos; create the creator-sourcing TikTok account and
start training its FYP; begin daily helpful Reddit comments (no app mentions
yet). *Metrics: waitlist signups, sub karma.*

**Weeks 3–4 — beta.** 50 TestFlight users recruited from 5 subreddits; weekly
feedback calls with 5 of them; start creator outreach at 20 DMs/day; publish
first 4 biomarker explainers; 3 build-in-public posts/week.
*Metrics: activation rate ≥40%, D7 ≥25% (est. targets), 10 creator replies.*

**Weeks 5–6 — content engine on.** Daily shorts begin; sign first 10 creators
(flat + code); bank 20 videos for launch week; draft PH/HN posts; ask beta
users for launch-day support and reviews.
*Metrics: first organic installs from content, CPM per creator.*

**Weeks 7–8 — LAUNCH.** PH + Show HN + 5 subreddit posts + 10 creator videos
in one week; founder replies to everything for 72h; review prompt live;
publish "how it keeps your data on-device" technical post for the HN crowd.
*Target: 1,000 installs cumulative (est.).*

**Weeks 9–10 — double down.** Kill what didn't move installs; scale what did;
ASA exact-match at $20/day; build referral redemption; second wave of 10
creators; App Store featuring pitch submitted.
*Metrics: CAC by channel, taste rate, taste→premium.*

**Weeks 11–13 — scale + retain.** 25 active creators; Spark Ads on top 3
videos; cohort retention audit (D1/D7/D30 by acquisition channel); churn
survey live; decide localization order from organic install geography.
*Day-90 targets (est.): 2,000–5,000 installs, ≥45% activation, ≥30% taste
rate, 50–150 premium subs, one channel with CAC <$25 proven.*

**Weekly operating rhythm:** Mon plan + metrics review; Tue–Fri one short/day
+ 20 creator DMs + 30 min Reddit; Wed biomarker article; Fri build-in-public
post; Sun batch-record.

**Resources:** founder ~10 focused hrs/week on growth; $0–1,500/mo optional
spend; CapCut; a creator-tracking sheet (handle, niche, rate, views, CPM,
code redemptions); TestFlight.

**North-star metric:** weekly count of users who log a record or check their
Tests Due card — everything else follows activation.
