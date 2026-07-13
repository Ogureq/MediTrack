# MediTrack Marketing Playbook

Working document for taking MediTrack from zero users to a scalable business.
Grounded in strategies proven by comparable apps (Cal AI, Bearable, Flo, Levels,
Function Health, Finch) and adapted to this app's actual moats. Figures marked
*(est.)* are estimates to be replaced with real cohort data.

**Honest baseline:** solo founder, pre-App-Store, $0 revenue, no audience.
**Product moats:** (1) local-first privacy — no account, health data never
leaves the device, the only such app in the category; (2) every tracking
feature free forever; (3) bring-your-own-labs OCR — decodes the lab PDFs users
already have instead of selling new $365–589/yr blood panels; (4) AI
explanation layer at $19.99/mo with one free lifetime report as the taste;
(5) built-in retention mechanics already shipped (streaks, quarterly ritual,
widgets, re-test notifications).

---

## 1. Market positioning

### Ideal customer profile

**Primary — "the lab binder person" (build everything for them first):**
ages 28–55, manages an ongoing condition or optimization goal — hypothyroid /
Hashimoto's, high cholesterol on statins, prediabetes, PCOS, long-recovery —
gets blood work 2–6× a year through insurance, currently keeps results as PDF
attachments in email or a paper binder, and googles each marker after every
draw. They are anxious *and* under-served: the doctor spends eight minutes on
results that took three weeks to arrive.

**Secondary ICPs:**
- **Privacy-first health consumer** — radicalized by the 23andMe bankruptcy
  data scare and period-tracker subpoena stories; hangs out in r/PrivacyGuides
  and watches Techlore. Small but loud, and they evangelize.
- **The caregiver** — managing a parent's labs, meds, and appointments across
  fragmented portals.
- **Biohacker-lite** — wants Function Health insights without $365/yr; already
  quantifies sleep/HRV.

### Pain points ranked by intensity
1. "I get a PDF of 30 numbers and nobody explains them."
2. Results scattered across Quest, Labcorp, hospital portals, and paper.
3. Eight-minute appointments; forgotten questions.
4. Googling markers produces worst-case anxiety, not trends.
5. Health apps harvest and resell data (top-of-mind for ICP #2).
6. Lab-testing subscriptions cost $199–589/yr for draws insurance already covers.

### Unique value proposition
> **Your labs, decoded — on your phone, not our servers.**
> MediTrack turns the lab PDFs you already have into trends, plain-English
> explanations, and questions for your doctor. Every tracking feature is free
> forever. No account. Your health data never leaves your iPhone.

### Positioning vs. competitors
- Function Health / InsideTracker / Superpower **sell new blood tests**; we
  monetize *understanding* of tests users already get free. Never compete on
  testing; always frame as complementary ("love Function? Track those PDFs
  privately too").
- Apple Health **stores** numbers, explains nothing, has no lab OCR.
- Guava Health / CareClinic sync records **to their cloud** and lean on US
  portal integrations; we are the private option and OCR works on any paper
  lab worldwide.
- Positioning sentence: **"The private lab tracker — bring your own labs."**

---

## 2. Growth strategy — three engines

### Engine A: Creator-led short video (the Cal AI playbook, adapted)
Why it worked for Cal AI: an instantly demoable magic moment (photo → calories),
high-volume micro-influencer outreach (hundreds contacted, ~150 on retainer
posting ~4×/month), a ~$5 CPM price target, referral codes for creators, then
Meta/Google paid on proven creatives. MediTrack's scan-a-lab-PDF → decoded
trends moment is equally screen-recordable.
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
app; the app being free-with-no-account makes mentions land as help, not sales.
Target subs: r/Hypothyroidism, r/Thyroid, r/Cholesterol, r/prediabetes, r/PCOS,
r/ChronicIllness, r/Biohackers, r/QuantifiedSelf, r/PrivacyGuides, r/Longevity.
Parallel: build-in-public on X and Indie Hackers (screenshots, revenue,
architecture posts) — compounding founder distribution.

### Engine C: Search capture (the Flo playbook, scaled to indie size)
Flo built a moat from thousands of medically-reviewed articles matching health
searches. Scaled-down version: (1) ASO first — own "lab results tracker",
"blood test tracker", "blood test results explained", "health records app";
(2) one web page + one YouTube video per catalog biomarker ("What does high
ALT actually mean?") — 46 markers = a 46-piece content map that mirrors the
in-app explanations already written for LabDetailView.

### Acquisition funnel
Hook (creator video / Reddit answer / marker article) → App Store page
(first screenshot = scan→decoded demo; second = "No account. No cloud."
privacy badge) → onboarding quiz → **activation = first lab scanned or first
Quick Add within 10 minutes** → day-2/3 prompt to run the one free AI report
(the taste) → quarterly ritual + retest notifications hold retention →
premium at the moment they try a second AI action.

---

## 3. Content marketing

### Pillars
1. **Lab literacy** (60%) — decode markers, trends, "questions to ask your doctor".
2. **Privacy** (15%) — health-data-broker stories, 23andMe fallout, "no login" demos.
3. **Product magic** (15%) — raw screen recordings of scan→decode, Quick Add sentence→record, quarterly recap.
4. **Build-in-public** (10%, X/IndieHackers) — metrics, decisions, architecture.

### Hooks that map to proven formats
- "Your doctor spends 8 minutes on results that took 3 weeks to arrive."
- "I scanned five years of lab PDFs and found a trend my doctor never mentioned."
- "This health app has no login button. That's the whole point."
- "POV: you finally understand your thyroid panel." (nurse-tok duet bait)
- "Stop paying $365/year to understand blood work your insurance already covers."
- "What your LDL number actually means (no fear-mongering)."
- "I asked AI to explain my cholesterol — but it only sees my summary, never my files."
- "Rating my health app's privacy policy vs. the top 5 trackers." (creator collab format)

### Three 30-second scripts (screen-record + voiceover)
1. **The scan.** Cold open on a crumpled lab printout. "Got my labs back.
   Thirty numbers, zero explanations. Watch this." Photograph it in-app → values
   appear with status pills → tap LDL → range chart + plain-English meaning →
   "Free, and it never leaves my phone."
2. **The privacy flex.** "Sign-up screen speedrun, health app edition." Show 3
   competitor sign-up walls, then MediTrack opening straight to the dashboard.
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
Landing page with privacy-first copy + TestFlight waitlist (Function Health
proved scarcity works in health — use "beta invites in batches"). Recruit ~50
beta users directly from target subreddits (they become launch-day
testimonials and App Store reviews). Bank 20 short videos before launch day.

### Launch week
Fire everything the same week: Product Hunt (privacy angle historically wins
PH), Hacker News "Show HN: A health tracker where your data never leaves the
phone" (local-first architecture is HN catnip; link the repo README's privacy
section), coordinated genuine posts in 5 subreddits, 10 creator videos live,
build-in-public launch thread.

### First 1,000 users *(est.)*
~300 PH/HN, ~400 Reddit, ~300 TikTok organic. Everything hand-to-hand; reply
to every comment for 72 hours.

### 1k → 10k
Creator engine at 20–30 micros posting monthly + ASO rankings maturing +
weekly content cadence. The one free AI report is the conversion story:
measure taste→premium.

### 10k → 50k
Apple Search Ads exact-match + TikTok Spark Ads on the top 3 organic
creatives. Pitch App Store featuring (Apple actively features privacy-forward
and accessibility-strong apps — both are true here; the VoiceOver pass is a
genuine story).

### 50k → 100k
Localize DE/JP/FR (privacy-sensitive, paper-lab-heavy markets where BYO-labs
OCR beats portal-dependent US competitors), press cycle ("the health app that
can't sell your data" to The Verge/TechCrunch/9to5Mac), referral program
fully live.

---

## 5. Paid acquisition

**Platforms in order:** (1) Apple Search Ads exact match — "blood test
tracker", "lab results app", competitor brand terms; highest intent, start
$20/day. (2) TikTok Spark Ads boosting proven organic creator posts (never
cold studio creative first). (3) Meta after creative validation — note both
platforms restrict health-condition targeting, so creative does the targeting:
broad audiences, condition-specific hooks.

**Ad angles:** the scan demo; the privacy flex ("no account" speedrun);
price-anchor ("$365/yr testing subscriptions vs. the labs you already have");
the doctor-visit prep ("walk in with questions, not anxiety").

**Benchmarks *(est., replace with cohort data)*:** iOS health CPI $2–4;
onboarding→activation 40–55%; free-report taste rate 25–35% of activated;
taste→premium 8–12% within 30 days. Blended CAC target ≤$25 against
$19.99/mo (payback <2 months at ~60% M1 premium retention). Kill any channel
above $40 CAC after $500 spent.

**Budget tiers:** $0 — engines A(organic)/B/C only; $1k/mo — ASA exact +
Spark boosts + 5 creator retainers; $10k/mo — Meta scale on proven creative +
25 creators (Cal AI sequencing: organic finds the winners, paid pours fuel).

---

## 6. Community & retention

Already shipped (use in marketing, don't rebuild): streaks, quarterly ritual,
score-change + 90-day retest notifications, widgets, redacted share card.

- **Activation:** onboarding must reach "first record in 10 minutes"; the
  quiz already seeds reminders — measure and cut any step with >10% drop.
- **The taste:** prompt the free AI report after the first lab scan, not at
  install (data makes the report impressive).
- **Review prompt:** trigger `SKStoreReviewController` after completing a
  quarterly review — the app's peak-delight moment.
- **Referral loop (build item):** "Give a report, get a report" — referred
  friend gets +1 free AI report, referrer gets one too. COGS ≈ $0.10 *(est.)*
  per report; needs a relay-side redemption flag.
- **Viral surface:** the redacted score card and quarterly recap ShareLink
  already exist — add a subtle "Tracked with MediTrack" watermark.
- **Community:** a "Lab Literacy Club" subreddit/Discord seeded from beta
  users; weekly "decode this (anonymized) panel" threads.
- **Churn:** cancel-flow survey, pause-month option, annual plan at 2 months
  free; win-back push when a retest reminder fires post-churn.

---

## 7. Partnerships

1. **Micro-creators** (core engine): nurse educators, registered dietitians,
   "labs explained" accounts, chronic-illness advocates, longevity podcasts
   <100k. Outreach: 20 DMs/day from the trained account; offer flat fee +
   referral code; target ≤$5 CPM (Cal AI's number).
2. **Privacy ecosystem:** Techlore, PrivacyGuides, small privacy newsletters —
   they rarely get a *health* app they can endorse; free feature-complete tier
   makes it credible.
3. **Adjacent brands, no data sharing:** at-home phlebotomy services and
   direct-to-consumer lab ordering (Ulta Lab Tests, OwnYourLabs) — their
   customers get raw PDFs and need exactly this app; co-marketing only,
   never integrations that touch data.
4. **Newsletter sponsorships:** indie longevity/health-optimization
   newsletters ($50–300 placements) before podcasts ($1k+).
5. **Later:** HSA/FSA eligibility for premium; employer wellness lists.

Approach template: short, specific, show the scan demo GIF, offer the code,
no exclusivity, monthly renewal only if the post clears the CPM bar.

---

## 8. Competitor breakdown

| Competitor | Price | Model | Their playbook | Their gap we exploit |
|---|---|---|---|---|
| Function Health | $365–499/yr | Sells 100+ marker panels 2×/yr | Waitlist scarcity, Mark Hyman audience, longevity press | Ignores insurance-covered labs; US-only; cloud |
| InsideTracker | $149/yr + $489–589 tests | Performance testing + DNA | Athlete positioning, science-blog SEO | Expensive, athlete-narrow; no BYO records |
| Superpower | $199/yr | Panels + AI + telehealth Rx | Feature breadth, comparison landing pages | Still sells draws; data lives server-side |
| Guava Health | Freemium | Cloud PHR + portal sync | US portal integrations, records aggregation | Cloud storage; portal-dependent (fails on paper/foreign labs) |
| Bearable | Freemium | Symptom/mood tracking | Founder-led Reddit community | No labs, no OCR, no AI explanation |
| Apple Health | Free | System record store | Default install | Stores but never explains; no lab OCR, no trends narrative |

Tactics to copy directly: Function's batched-waitlist scarcity (TestFlight),
InsideTracker's per-marker SEO library, Superpower's "X vs Y" comparison
pages (rank for "Function Health alternative"), Cal AI's creator volume + CPM
discipline, Bearable's founder-in-the-comments authenticity.

---

## 9. 90-day execution roadmap

**Weeks 1–2 — foundations.** App Store assets (screenshot 1 = scan demo,
screenshot 2 = privacy badge, video preview = 30s script #1); landing page +
waitlist; privacy-respecting analytics (e.g. TelemetryDeck — fits the brand);
record 6 demo videos; create the creator-sourcing TikTok account and start
training its FYP; begin daily helpful Reddit comments (no app mentions yet).
*Metrics: waitlist signups, sub karma.*

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

**North-star metric:** weekly count of users who scan or add a record —
everything else follows activation.
