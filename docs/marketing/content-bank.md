# Gemocode Content Bank

Launch content executing the strategy in `docs/MARKETING.md`. Sourced from
actual shipped features in `README.md` and the "educational, not diagnostic"
stance in `CLAUDE.md`. Nothing here describes a feature the app doesn't have.
Lead message: never lose a lab result, know exactly when your next one is
due — and when it isn't — and walk into any appointment with your full
history so nothing gets re-ordered from scratch. Privacy is the strong #2,
never dropped, never leading.

**Compliance rules applied throughout this file (see also CLAUDE.md):**
- No medical claims. Never "improves your health," "catches disease,"
  "diagnoses," "treats," "prevents," or similar. Findings are described as
  educational, and the app's own "not medical advice" disclaimer is treated
  as a fact to surface, not a legal footnote to hide.
- Retest intervals are always "commonly recommended" — every mention of the
  Tests Due feature or a specific retest cadence carries "your doctor may
  advise differently," never phrased as a guarantee or a schedule to follow
  blindly.
- No hype words. "Revolutionary," "game-changing," and similar are banned;
  none appear below.
- Privacy claims are stated exactly as true: no account, on-device SwiftData
  storage, AI is opt-in and sends only the review summary (or, for
  AI-assisted Quick Add, the single sentence typed) through a metered relay —
  never documents, attachments, or the on-device database.
- **Pricing stated exactly as true, everywhere:** tracking (vitals, meds,
  symptoms, goals, health score, trends, the Tests Due retest schedule,
  Quarterly Review, widget, Apple Health sync) is free forever — and so is
  Quick Add's typed shorthand ("bp 128/82", "dentist tomorrow 3pm"), which
  parses on-device with no AI. Lab report scanning, AI reports, AI chat,
  and the AI button inside Quick Add (whole messy sentences with several
  items, extracted in one go) are Premium at $19.99/mo. Free accounts get
  exactly one lifetime AI scan-and-report as a trial — that trial is the
  only time a free account ever scans a lab. Never say "free scanning" or
  "OCR is free" — scanning is Premium, full stop.
- No overpromising. The app is iOS-only and pre-launch. Nothing below says
  "available now" or implies Android/web support.
- Money comparisons stay honest and non-quantified per user: never invent a
  "$X saved" figure. Hypothetical comparisons are fine when phrased as
  hypotheticals and kept plausible — e.g., "a single out-of-pocket lab panel
  can easily cost more than a month of Premium" (true of nearly any real
  cash-pay panel) — never a blanket promise of savings.
- **CTA convention:** every script's CTA defaults to the pre-launch reality
  — "waitlist link in bio." The bracketed launch-week variant ("free on the
  App Store") should only go live the day the app actually ships. Do not
  swap it early.

---

## A. Eleven 30-second short-video scripts

Each script is a real screen recording of the shipped app plus a phone-shot
or voiceover-only cold open. Runtime budget: ~2s hook, ~24s body, ~4s CTA.
Ordered by pillar priority: money & timing leads, privacy is a strong
second, lab literacy and product magic follow.

### 1. "The Card That Says Not Yet" — *Pillar: money & timing*

**Hook (0:00–0:02, on-screen text):** "I almost got billed for a lab I'd already had six weeks earlier."

**Shot list:**
1. Cold open, phone camera: two lab-draw receipts on a kitchen counter, dates six weeks apart, same panel name circled.
2. Cut to screen recording: Dashboard, tap into the "Tests due" card.
3. Card shows two rows: Lipid Panel — "not due for 11 weeks" (muted/green), Thyroid Panel — "overdue by 3 weeks" (amber/red).
4. Phone-camera reenactment: at a front desk, showing the Tests Due card to a receptionist instead of shrugging and saying "I think I had that recently?"
5. Back to screen recording: tap into the Lipid Panel row — shows the last-drawn date and the commonly recommended interval it used to calculate "not due yet."
6. Close on the small print at the bottom of the card: "commonly recommended — your doctor may advise differently."

**Voiceover:**
- "I almost got billed for a lipid panel I'd already had six weeks earlier."
- "Now my phone just tells me: this one's not due for eleven weeks, this one's actually overdue."
- "It's not telling me what to do — it's using commonly recommended intervals, and it says so every time."
- "I just stopped guessing, and stopped paying for guesses."

**On-screen captions:** "commonly recommended" / "your doctor's call" / "skip the duplicate"

**CTA (0:26–0:30):** "Waitlist link in bio." *(Launch-week variant: "Free on the App Store — link in bio.")*

**Pillar:** money & timing

---

### 2. "Walk In With Five Years of History" — *Pillar: money & timing*

**Hook (0:00–0:02, on-screen text):** "New doctor. First question: 'Do you have any recent labs?' I had five years of them, right there."

**Shot list:**
1. Screen recording: Reports list, several years of entries scrolling past.
2. Tap into Trends tab, select a single marker, switch the time filter from 3M to All.
3. The chart re-renders across the full history — period average line, min/max markers, trend direction visible.
4. Cut to the Health Review's trend finding: "improving / worsening / stable," generated from the linear regression over that same history.
5. Cut to the Tests Due card for the same marker's test type: shows when it's next commonly due, based on the last logged draw.
6. Close on a phone-camera reenactment: handing the phone to a new provider at check-in instead of saying "let me check my email."

**Voiceover:**
- "New doctor's office, same first question every time: 'do you have any recent labs?'"
- "I used to say 'I think so, let me check my email.' Now I just hand them the phone."
- "Five years of draws, side by side — so a slow drift shows up before it's a crisis instead of getting re-tested to find out."
- "And it tells me which of those tests I'm actually due to repeat, so the next draw isn't a guess either."

**On-screen captions:** "your data, your trend" / "on-device" / "nothing re-ordered from scratch"

**CTA:** "If you've got old lab PDFs sitting in email, this is for you. Waitlist link in bio."

**Pillar:** money & timing

---

### 3. "Sign-Up Screen Speedrun, Health App Edition" — *Pillar: privacy*

**Hook (0:00–0:02, on-screen text):** "Sign-up screen speedrun: health app edition."

**Shot list:**
1. Fast-cut montage (screen recordings, sped up, publicly available competitor sign-up flows — generic framing, no disparaging claims): email field, password field, "verify your email," terms-of-service scroll, a permissions wall — three different apps, ~2 seconds each.
2. Hard cut: Gemocode cold-launched from a fresh install, straight to the onboarding quiz, no email or password field anywhere.
3. Show completing onboarding into the Dashboard within seconds.
4. Toggle Airplane Mode on-screen, then continue using the app normally — add a vital, open a report — to visually demonstrate no network dependency.

**Voiceover:**
- "Every health app wants an account before it'll even show you the demo."
- "This one doesn't have one. There's no sign-up screen to speedrun."
- "It works in airplane mode, because it isn't talking to a server in the first place — your data lives on your phone."

**On-screen captions:** "no account" / "no cloud" / "airplane-mode demo"

**CTA:** "No login, ever. Waitlist link in bio."

**Pillar:** privacy

---

### 4. "Rating My Health App's Privacy Policy" — *Pillar: privacy*

**Hook (0:00–0:02, on-screen text):** "Rating my health app's privacy policy vs. the top 5 trackers."

**Shot list:**
1. Creator-collab format: host on camera holding a phone, scrolling a generic privacy-policy PDF, reacting (no disparaging claims about named competitors — describe the category, not specific brands, unless pre-cleared).
2. Cut to Gemocode's in-app "Privacy & Your Data" explainer screen — scroll through it in full.
3. Screen recording: Profile → Login & Security, showing the local passcode setup and Face ID toggle.
4. Screen recording: Profile → Data → Export Backup, showing the passphrase prompt before the encrypted file is written.
5. Return to host on camera for the verdict.

**Voiceover:**
- "Most health apps bury 'we may share data with partners' on page 9. This one's privacy screen is one page, in plain language, because there's less to disclose."
- "No account. No login means no password to leak. Your local passcode never leaves the Keychain on your phone."
- "Even backups are encrypted with a passphrase only you have, and you choose where the file goes — nothing auto-uploads."
- "The only thing that ever leaves the device is a summary of your review, and only if you turn on the AI feature yourself."

**On-screen captions:** "on-device" / "no account" / "AI is opt-in"

**CTA:** "Read the actual privacy screen yourself — waitlist link in bio."

**Pillar:** privacy

---

### 5. "AI That Only Sees a Summary" — *Pillar: privacy*

**Hook (0:00–0:02, on-screen text):** "I asked AI to explain my cholesterol. It never saw my files."

**Shot list:**
1. Screen recording: Health Review screen, tap "Generate AI Report."
2. Brief loading state, then the structured AI report renders — plain-language narrative tied to specific findings.
3. Slow zoom/hold on the screen's bottom text: **"Generated by Claude — informational only, not medical advice."**
4. Cut to a simple on-screen diagram (native SwiftUI, not a stock graphic) showing: phone icon → "review summary only" arrow → cloud icon labeled "relay" → a second arrow labeled "Anthropic API," with a crossed-out icon over "attachments / documents / database."
5. Return to app: Ask-about-your-report chat, showing a follow-up question answered in-context.

**Voiceover:**
- "This is the paid AI feature — an on-device engine already computed the score and the findings; the AI just explains them in plain language."
- "It only ever sees the review summary — never my attached PDFs, never the on-device database."
- "Every AI response is labeled, so it's always clear what the rule-based engine found versus what the model explained."
- "One scan and one report are free for life, so you can see it before you pay. After that it's part of Premium — because someone has to pay for the model calls, and it isn't your data."

**On-screen captions:** "review summary only" / "no attachments sent" / "one free trial"

**CTA:** "Waitlist link in bio — your first AI report is free."

**Pillar:** privacy

---

### 6. "The Scan" — *Pillar: lab literacy*

**Hook (0:00–0:02, on-screen text):** "I got my labs back. 30 numbers. Zero explanations."

**Shot list:**
1. Cold open, phone camera: a crumpled lab-draw printout on a kitchen table.
2. Cut to screen recording: open a report in Gemocode, tap "Scan for Lab Values."
3. Vision OCR runs over the photographed page (show the brief on-device scanning state).
4. Confirmation sheet appears: recognized values line up against the catalog, each with a status pill (green/yellow/red).
5. Tap into one flagged value (e.g., LDL) → LabDetailView opens: history chart with the reference-range band, plain-language "what high means" text.
6. Quick cut: Dashboard biomarker carousel showing the same marker's mini sparkline, next to the Tests Due card showing when the next lipid panel is commonly due.

**Voiceover:**
- "Thirty numbers, and my doctor had eight minutes to explain them."
- "So I photographed the page instead."
- "It reads the values on-device, matches them to a catalog, and shows me what's actually out of range — the photo never leaves my phone to do it."
- "My first scan was free. After that it's part of Premium — but by then I already knew it was worth it."

**On-screen captions:** "on-device OCR" / "no upload" / "first scan free"

**CTA (0:26–0:30):** "Waitlist link in bio." *(Launch-week variant: "Free on the App Store — link in bio.")*

**Pillar:** lab literacy

---

### 7. "POV: You Finally Understand Your Thyroid Panel" — *Pillar: lab literacy*

**Hook (0:00–0:02, on-screen text):** "POV: you finally understand your thyroid panel."

**Shot list:**
1. Nurse-tok-style direct-to-camera open, no app yet: "If you've ever stared at 'TSH: 6.2' and had no idea if that's bad—"
2. Cut to screen recording: LabDetailView for TSH — current value, status pill, the "what this test measures" text, and the plain-language high/low explanation.
3. Scroll to the history chart — several draws over time, reference band overlaid.
4. Cut to the Health Review screen: the same marker appears as a Finding, grouped by severity, with a suggestion to bring it up with a clinician.
5. Close on Dashboard biomarker carousel scrolling past TSH, LDL, HbA1c cards.

**Voiceover:**
- "TSH doesn't mean anything on its own — it's a signal, and this shows you the range, not just the number."
- "High, low, in range — it's all labeled, in plain English, next to your own history."
- "It doesn't diagnose anything. It just gives you the vocabulary to ask your doctor a sharper question."

**On-screen captions:** "educational, not diagnostic" / "ask your doctor" (paired with disclaimer text at bottom third)

**CTA:** "Duet this with your own confusing lab result. Waitlist link in bio."

**Pillar:** lab literacy

---

### 8. "What Your LDL Number Actually Means" — *Pillar: lab literacy*

**Hook (0:00–0:02, on-screen text):** "What your LDL number actually means (no fear-mongering)."

**Shot list:**
1. Screen recording opens directly on LabDetailView for LDL Cholesterol.
2. Show the reference-range band on the history chart — narrate what "under 100" represents as a commonly used reference point, not a verdict.
3. Scroll to the plain-language "about" and "what a high result means" text.
4. Cut to Health Review: the derived lipid finding (total-to-HDL ratio) — show how the app connects two lab values into one plain-English insight.
5. End on the disclaimer line at the bottom of the Review screen.

**Voiceover:**
- "LDL gets called 'bad cholesterol,' which isn't wrong, but it's not the whole story either."
- "This shows you the reference range, your own trend, and what a high or low result typically means — plainly, no worst-case spiral."
- "It also does the math your eye skips — total cholesterol over HDL — because two numbers together tell you more than either alone."
- "Still not a diagnosis. Just the numbers, explained, so the appointment isn't the first time you're thinking about them."

**On-screen captions:** "educational only" / "bring this to your doctor"

**CTA:** "Full breakdown of LDL, TSH, HbA1c, and Vitamin D — waitlist link in bio."

**Pillar:** lab literacy

---

### 9. "Typing a Sentence Instead of Filling a Form" — *Pillar: product magic*

**Hook (0:00–0:02, on-screen text):** "I typed one sentence instead of filling out a form."

**Shot list:**
1. Screen recording: Dashboard, tap into Quick Add.
2. Type live, letter by letter: "bp 128/82."
3. Live preview renders as it's typed: a Blood Pressure vital card, systolic/diastolic filled in, today's date.
4. Tap confirm — haptic-style checkmark animation, card appears on the vitals list.
5. Quick second example, sped up: type "dentist tomorrow 3pm" → live preview becomes an Appointment card → confirm.
6. Close on the Dashboard's "Next Appointment" card and the new BP reading's sparkline updating.

**Voiceover:**
- "No dropdowns, no five-field form — just what I'd actually say out loud."
- "This parses right on the phone — free, no AI, works in airplane mode. I see a live preview before anything saves, so I can catch a typo."
- "Works for vitals, meds, symptoms, appointments — one line, structured data. Premium adds an AI button for the messy version: a whole sentence with three things in it, filed all at once."

**On-screen captions:** "Quick Add — free, parsed on-device" / "confirm before it saves"

**CTA:** "Waitlist link in bio."

**Pillar:** product magic

---

### 10. "The 90-Day Report My Doctor Would Charge For" — *Pillar: product magic*

**Hook (0:00–0:02, on-screen text):** "Every 90 days my phone gives me a recap my doctor would charge a copay for."

**Shot list:**
1. Screen recording: Dashboard notification/card inviting the Quarterly Review.
2. Open it — scroll slowly through the full recap: score trajectory graph, a "what changed" section (vitals and labs called out conservatively — only clearly improved or worsened metrics labeled as such), streak and goal wins, a list of doctor-question prompts.
3. Continue scrolling to the end of the recap.
4. Tap the share action — show the ShareLink sheet opening with the plain-text summary ready to send or save.

**Voiceover:**
- "It's not a diagnosis — it's just my own data, organized, every quarter."
- "Score trend, what actually changed, and a running list of questions worth asking at my next appointment."
- "Entirely computed on the device, from records I already logged, free, no account. I can share it as plain text if I want to bring it to an appointment."

**On-screen captions:** "computed on-device" / "free, no account"

**CTA:** "Waitlist link in bio."

**Pillar:** product magic

---

### 11. "The Dashboard Row I Check First" — *Pillar: product magic*

**Hook (0:00–0:02, on-screen text):** "This is the first thing I check every morning."

**Shot list:**
1. Screen recording: Dashboard opens directly (no login screen — reinforce cold open speed).
2. Horizontal scroll through the biomarker carousel — each card: marker name, latest value, status pill, mini sparkline — next to the Tests Due card.
3. Tap one card through to LabDetailView for the full chart.
4. Back out, show the home-screen widget (small size) on a simulated home screen: score ring, headline, recent vitals, and the locked-state redacted view side by side.
5. Tap the widget (screen recording of the deep link) → opens straight to the Health Review.

**Voiceover:**
- "One row, every marker I track, status at a glance — and right next to it, what's due and what isn't."
- "The widget mirrors it on my home screen, and it redacts the numbers automatically when my phone's locked."
- "No refreshing, no server round-trip — it's all already on the device."

**On-screen captions:** "redacted when locked" / "on-device"

**CTA:** "Waitlist link in bio."

**Pillar:** product magic

---

**Pillar tally:** money & timing × 2 (scripts 1–2), privacy × 3 (scripts 3–5), lab literacy × 3 (scripts 6–8), product magic × 3 (scripts 9–11).

---

## B. Three Reddit posts

Each is written in the founder's own voice, disclosing the "I built this"
relationship up front, offering the app as context for the conversation
rather than a pitch, and explicitly inviting critique. No links pasted into
the body beyond what a mod would allow for a disclosed self-promo post —
adapt the exact link placement to each subreddit's self-promo rule (some
want it in a comment, not the post).

### B1. r/Hypothyroidism — chronic-illness sub, lab-tracking pain

**Suggested flair:** Discussion / Vent-Support (per sub norms — check current flair list before posting)

**Title:** I got tired of re-Googling my TSH every three months, so I built a thing to stop myself (and stop getting re-tested early). Feedback welcome (I'm the dev, full disclosure).

**Body:**

> Standard disclosure up front: I'm a solo developer and I built the app I'm about to describe. I'm not here to sell anything — genuinely looking for feedback from people who live this, and happy to just talk labs if that's more useful to you than my app is.
>
> Diagnosed hypothyroid a few years back, and my pattern was: get labs, get a portal notification, open a PDF with 30 rows on it, remember that TSH is the one that matters, forget what my number was three draws ago, re-Google "TSH 4.8 meaning," get a mix of WebMD and forum panic, and show up to my endo appointment having learned nothing except how to worry. The other half of the pattern: I genuinely couldn't remember when my last panel was, so I either let it slide past when it should've been redrawn, or a new provider ordered it again "just to be safe" when I'd had it eight weeks earlier.
>
> What actually helped was a plain spreadsheet where I logged TSH, free T4, and free T3 every draw so I could see the *direction*, not just the number. But keeping that spreadsheet current was its own chore, it didn't explain anything, and it definitely didn't tell me when I was due again.
>
> So I built an iOS app that does the parts I was doing by hand: photograph the lab report page, it reads the values off the page (on-device, nothing uploaded), matches them against a reference range, shows history as a chart instead of a list, and — the part I actually use most — tracks when each test was last drawn and shows when it's commonly due again, so I stop either forgetting or over-testing. It's not diagnostic — it doesn't tell me anything my doctor wouldn't, and it's always explicit that a doctor might advise a different interval than the commonly recommended one — it just means I walk into the appointment already knowing my TSH trend and my retest timing instead of re-deriving both from memory.
>
> Two questions for anyone still reading:
> 1. What do you currently do to track your panels between draws? Spreadsheet, app, nothing, the portal's own graph? And do you ever actually know when you're "due" versus just waiting for the office to tell you?
> 2. If you've used a symptom tracker for hypothyroid stuff (fatigue, weight, temperature sensitivity) alongside your labs, did tracking both together ever actually change a conversation with your doctor, or did it just generate more data to sit on?
>
> Not trying to get anyone to download anything — mostly want to know if "know your trend, know your timing, private" is actually the gap, or if I'm solving a problem that was only ever mine. If it's useful to see what I built, I'll drop a link in the comments rather than clutter the post.

---

### B2. r/PrivacyGuides — technical, local-first architecture

**Suggested flair:** Software recommendation / General Discussion (check current rules — PrivacyGuides is strict about self-promo; disclose clearly and expect mod discretion)

**Title:** Built an iOS health tracker with no account and no cloud storage — here's the actual architecture, including the one place data does leave the device (feedback and criticism both welcome)

**Body:**

> Disclosure: I'm the developer. Posting because this sub is exactly the audience that will tell me if I got the privacy model wrong, and I'd rather hear it now than after launch.
>
> The app (Gemocode, iOS 17+) tracks medical records — labs, vitals, meds, symptoms, appointments — and computes when each type of blood test is commonly due again based on your own logged history. Everything is stored on-device via SwiftData; there's no account, no sign-in, and no backend for the core app. A local numeric passcode (salted SHA-256, iOS Keychain, device-only, never synced) plus optional Face ID/Touch ID gates the app itself — that credential never leaves the device either. Backups are AES-GCM-encrypted JSON files the user exports and controls; nothing auto-uploads. The retest-schedule computation and the health score are both plain rule-based logic running entirely on-device — no network call involved.
>
> The one deliberate exception is an optional AI layer (report scanning/OCR, the AI-narrated report, chat about your results, and AI-assisted natural-language entry), and I want to describe exactly what it does rather than assert "it's private, trust me":
>
> - It's opt-in and it's the paid tier. With no relay/API key configured, or if you've used your one free lifetime scan-and-report trial and haven't subscribed, the app makes zero network calls for anything beyond that trial.
> - When enabled, the client sends only pre-computed, structured data to a Cloudflare Workers relay I run: either the rule-based review's summary (score + findings + lab values, no free text from documents), a compact chat context (for follow-up questions about that same review), or a single user-typed sentence (for the natural-language quick-entry feature). It never sends attachments, photographed documents, or the on-device database.
> - The relay holds the Anthropic API key as a Cloudflare secret (`wrangler secret put`) — it's never in the repo, never in the client binary, never in a log. The relay's own logging is metadata-only (hashed device id, token counts, latency, status) by construction, not by "we chose not to log the field this time."
> - Every AI response is verified against the input before display (the app checks that cited numbers and finding IDs actually appear in what was sent) and every refusal (`stop_reason == "refusal"` from the Anthropic API) is surfaced rather than silently swallowed.
>
> Business model, since it's relevant to the incentive structure: tracking, the health score, trends, and the retest-schedule card are free forever, no account required. Lab scanning and every other AI feature are the paid tier ($19.99/mo), with one free lifetime scan-and-report as a trial — so the AI relay is metered and the free local feature set was never designed as a funnel to a data-selling model, because there's no data collection to sell in the first place.
>
> Where I'd genuinely like scrutiny: is "sends only a computed summary, never raw documents" a distinction that matters to this audience, or does any outbound call to a third-party model erase the local-first story for you regardless of payload shape? And is there anything about the on-device-only retest math + Keychain-only credential design that you'd still flag as a gap? Happy to link the repo/README in a comment if that's useful context rather than promotion.

---

### B3. r/QuantifiedSelf — the retest cadence + quarterly review ritual

**Suggested flair:** Self-Experimentation / Tools (check current flair list)

**Title:** I made my phone tell me when I'm actually due for my next blood panel, instead of guessing — sharing the logic, not just the app (disclosure: I built it)

**Body:**

> Disclosure: I'm the developer of the app in the screenshots below. Posting because this community cares about the *system* more than the tool, and I'd like to know if the logic holds up.
>
> Background: I track blood pressure, resting heart rate, weight, glucose, and sleep daily-ish, plus lab panels a few times a year, in an app I built for myself and then turned into a real product. Two things I ended up building on top of the daily logging, and I want feedback on both:
>
> First, a "Tests due" card: for each test type I've logged, it remembers the last draw date and shows when it's commonly due again, using widely published recommended intervals (e.g., a lipid panel roughly every 4–6 months for someone on statins, a thyroid panel roughly every 6–12 months once stable) — always labeled "commonly recommended, your doctor may advise differently," never a hard rule. It exists because I kept either forgetting a panel for a year or getting a new provider to re-order one I'd had six weeks earlier.
>
> Second, a 90-day recap: every quarter, the app assembles what changed from what's already logged — score trajectory, which vitals and labs moved and in which direction (deliberately conservative: it only labels a metric "improved" or "worsened" when the direction is medically unambiguous, everything else is just "changed"), streak/goal wins, and a running list of doctor questions. All computed on-device, exportable as plain text.
>
> What I like about the two systems together: daily vitals are noisy enough that a single day tells you almost nothing, a 90-day window is long enough to separate a real trend from a bad night's sleep, and the retest-cadence layer underneath both means I'm not accidentally re-testing something I already know the answer to just because I lost track of when I last checked.
>
> What I'm unsure about: are the "commonly recommended" intervals I'm using close enough to what people actually see from their own doctors, or does this vary enough by provider/insurer that a single default interval per test type is the wrong model? And for people tracking things that move faster (HRV, mood, sleep architecture), does a quarterly recap feel too slow, and would you want a monthly or weekly layer underneath the retest-timing layer too?
>
> Also curious whether anyone here has a self-built version of this — a script, a Notion template, an Exist.io view — that tracks "when am I due again" specifically, separate from the general trend-tracking most QS tools already do.
>
> Happy to share the app itself in a comment for anyone who wants to see the actual Tests Due card, but the thing I actually want to talk about is whether the interval logic is right.

---

## C. Product Hunt listing draft

**Name:** Gemocode

**Tagline (54 chars):** Know when you're due for your next blood test. Or not.

**Description:**

> Gemocode is a local-first iOS app for tracking your own medical records —
> lab results, vitals, medications, symptoms, and appointments — entirely
> on-device. No account, no sign-up, no cloud storage.
>
> The part people actually message me about: a "Tests due" card that
> remembers when each type of blood test was last drawn and shows when
> it's commonly due again, so you skip the duplicate panel and never miss
> the overdue one — always labeled "commonly recommended, your doctor may
> advise differently," never a hard rule. Walk into any appointment with
> your full history already in your pocket, instead of a new provider
> re-ordering something you already have.
>
> Tracking, the health score, trends, the Tests Due card, and the
> Quarterly Review are free forever, no account needed. The paid layer is
> lab scanning and AI: photograph a report and on-device OCR (Apple's
> Vision framework) reads the values and matches them against a built-in
> reference catalog, Claude narrates your already-computed review in plain
> language, you can chat about your results, and AI-assisted entry turns a
> typed sentence into a structured record. You get one scan-and-report free
> for life before it's $19.99/mo — a single out-of-pocket lab panel can
> easily cost more than that first month, which is part of why the free
> trial exists.
>
> Built solo, for the people who get a lab PDF twice a year and have no
> idea when they're actually supposed to get the next one.

**First comment from the maker:**

> Hey Product Hunt — I'm the solo developer behind Gemocode. Quick story on
> why it exists and why it's built the way it is.
>
> I kept getting lab results back as PDFs — thirty-ish numbers, no context,
> a doctor's appointment three weeks later with eight minutes to go over
> them — and separately, I kept either forgetting when I was due for the
> next panel or having a new provider re-order one I'd had six weeks
> earlier because nobody had the history. What I actually wanted was: read
> the PDF for me, show me the trend instead of just the latest draw, and
> tell me when I'm actually due again instead of guessing.
>
> The local-first part wasn't a marketing decision, it was the actual
> requirement — this is blood work and medication data, and I didn't want
> to be the reason it ended up somewhere I couldn't account for. So there's
> no account. Everything lives in SwiftData on your device. The retest-due
> math and the health score are both plain on-device logic — no network
> call involved. Backups are encrypted files you control. If you never
> touch the paid AI features, the app makes zero network calls, period.
>
> The paid layer is the AI stuff: scanning a lab report, the AI-narrated
> report, chat about your results, and AI-assisted entry. I didn't want a
> health app that phones home by default, so it's opt-in, it only sends a
> computed summary (never your documents), and it runs through a relay I
> pay for — which is also why it isn't free: one scan-and-report free for
> life so you can see if it's worth it, then $19.99/mo. Tracking, the
> score, trends, and the Tests Due card stay free forever regardless.
>
> I'd love feedback on two things specifically: (1) does the "one free
> scan-and-report, then paid, but tracking and timing never are" model feel
> fair, and (2) does the "when are you actually due" card solve a real
> problem for you, or is timing something your provider already handles
> well enough that this is solving nothing? Happy to answer anything about
> the architecture, the OCR accuracy, or the business model — genuinely
> here all day.

**Gallery image captions:**

1. "The Tests Due card: what's overdue, what isn't — so you never pay for a duplicate or miss the real one."
2. "No sign-up screen. The Dashboard is the first thing you see, and it works in airplane mode."
3. "Photograph a lab report — on-device OCR matches each value to a reference range and flags what's out of it. (Premium, one scan free.)"

---

## D. Show HN draft

**Title (79 chars):** Show HN: Gemocode – tracks when you're due for a blood test, all on-device

**Body:**

> Gemocode is an iOS 17+ app for tracking personal medical records — labs,
> vitals, medications, symptoms, appointments — built entirely on Apple's
> own frameworks: SwiftUI, SwiftData for persistence, Swift Charts, Vision
> for OCR, LocalAuthentication for the app lock. No third-party
> dependencies, no SPM packages beyond what Apple ships.
>
> **The part I actually want feedback on:** a "Tests due" feature that
> tracks, per test type, when it was last drawn and computes when it's
> commonly due again, using published recommended intervals as defaults —
> always surfaced as "commonly recommended, your doctor may advise
> differently," never a hard schedule. It's plain deterministic logic
> (same `now`-as-parameter pattern as the scoring engine below, no ML, no
> network call) — the interesting part is less the code and more the
> product bet: that "know when you're due, and know when you're not" is a
> bigger unlock than another dashboard of numbers.
>
> **The local-first part:** everything lives in SwiftData on-device. There's
> no account and no backend for the core app — the login system is a
> salted SHA-256 passcode hash in the iOS Keychain (device-only, never
> synced) plus optional biometrics. Photographed lab reports are read by
> Vision's on-device text recognition, matched against a ~46-entry lab
> reference catalog via a synonym dictionary (report forms abbreviate
> "Hemoglobin A1c" as "A1C," "HbA1c," "Hgb A1c," etc.), and the recognized
> values go into a confirmation sheet before anything is saved — the photo
> never leaves the device to be read. A rule-based analysis engine (linear
> regression for trends, ACC/AHA blood-pressure categories, BMI, lipid
> ratios, a curated drug-interaction table) computes a 0–100 score and
> severity-graded findings deterministically, with no cloud AI in that path
> at all — it takes a fixed `now` parameter instead of calling `Date()`
> internally, specifically so it stays unit-testable and reproducible.
>
> **Where the architecture gets more interesting (to me, anyway):** the
> network-touching features are an optional AI layer — lab scanning's OCR
> confirmation flow doesn't need network, but the AI-narrated report, chat,
> and AI-assisted entry do — and I wanted the API key custody story to be
> airtight, not just "trust me." The Anthropic API key never ships in the
> client. It lives only as a Cloudflare Workers secret (`wrangler secret
> put`), read only by the deployed Worker at request time. The iOS app
> authenticates with a device-UUID-for-JWT exchange, then calls a single
> relay endpoint (`POST /v1/ai/generate`) with one of three request shapes:
> the already-computed review summary (for the structured report), a
> compact chat context (for follow-up questions about that same review), or
> a single user-typed sentence (for the natural-language quick-entry
> feature). It never sends attachments, photographed documents, or anything
> from the on-device database — the relay's request validator explicitly
> rejects unknown fields and base64-blob-shaped strings, so an accidental
> attachment field fails the request rather than silently uploading. The
> relay's own logging is metadata-only (hashed device id, token count,
> latency, model, status) by construction — there's no code path that logs
> request or response content.
>
> On the model side, every AI response is checked before it's shown: the
> app verifies numbers and finding IDs the model cites actually appear in
> what was sent, and checks `stop_reason == "refusal"` before treating any
> output as usable.
>
> **Business model:** tracking (vitals, meds, symptoms, goals, the health
> score, trends, the Tests Due card, backups, reminders) is free forever,
> no account needed. Lab scanning and every AI feature (the narrated
> report, chat, AI-assisted entry) are $19.99/month, with exactly one free
> lifetime scan-and-report per device so people can judge it before paying.
> The relay is metered (per-user and global daily token caps) precisely
> because I'm paying for the underlying API usage myself and the free tier
> has to stay solvent.
>
> Repo isn't public yet (see below on why), but the architecture doc and
> full README are what this post is drawn from, and I'm happy to paste any
> specific file's contents in comments if that's more useful than
> prose describing it.
>
> **Anticipated questions, answered honestly:**
>
> - **Why not open source?** Mainly unreadiness, not principle — it's a
>   solo project and I haven't done the pass needed to open-source
>   responsibly (license choice, contribution process, making sure nothing
>   in git history is embarrassing rather than secret, since the actual
>   secrets were never committed in the first place). It's not ruled out
>   long-term; I'd rather do it properly once than rush it for launch day.
> - **What exactly does the AI see, and what doesn't it see?** Only the
>   computed review summary, a compact chat context derived from that same
>   review, or a single typed sentence for quick-entry — never the
>   attached lab photos/PDFs, never the SwiftData store, never Medical ID
>   fields (name, DOB, blood type, allergies). If you never open the paid
>   AI features, the app makes no network calls at all.
> - **How were the "commonly recommended" retest intervals chosen?** From
>   widely published general guidance per test type, used only as a
>   default the app surfaces — it's explicitly not a substitute for a
>   clinician's own recommendation, and the UI says so every time the
>   interval is shown, not just in a settings footnote.
> - **Why iOS only?** Solo developer, finite hours, and iOS gave me
>   SwiftData, Vision OCR, and the Keychain as first-party building blocks
>   with no third-party dependency risk. An Android or web version would
>   mean re-deriving all of that trust story on a different stack, which
>   isn't a decision I want to make casually. No timeline to share; it's
>   not in progress right now.
> - **Isn't "the AI sees a summary, not raw data" still a privacy
>   compromise?** Yes, honestly — it's an opt-in exception to an otherwise
>   fully offline app, made because the alternative (no AI feature at all,
>   or a worse one built from rule-based text templates) seemed like a
>   worse trade for users who want it. It's off by default and every
>   response is labeled so it's never confused with the on-device engine's
>   output.
> - **What stops someone from just minting new device IDs to get infinite
>   free scans?** Nothing yet — that's a known, documented gap (the
>   relay's App Attest integration isn't wired up). It's on the pre-GA
>   checklist before the relay takes real production traffic, not
>   something I'm pretending is solved.
>
> Feedback on the relay design, the retest-interval defaults, the
> OCR/synonym-matching approach, or the "summary only, never raw documents"
> AI boundary all genuinely welcome — this is exactly the audience I built
> the architecture to survive scrutiny from.

---

## E. X launch thread (build-in-public voice)

**Tweet 1/10**
Shipping day. Gemocode is live — an iOS app that tracks every blood test you've had and tells you when you're commonly due for the next one, so you skip the duplicate and never miss the overdue one. No account. Nothing leaves your phone unless you turn on AI yourself.
🧵

**Tweet 2/10**
Backstory: I kept either forgetting when I was due for a panel, or a new provider re-ordered one I'd had six weeks earlier because nobody had the history. Add the classic problem too — a 30-row PDF, zero context, an 8-minute appointment 3 weeks later. I wanted both fixed.

**Tweet 3/10**
[Screenshot placeholder: Dashboard "Tests due" card, one row overdue in red, one row "not due for 11 weeks" in green]
So: a Tests Due card, computed on-device from your own logged draws against commonly recommended intervals. Always labeled "your doctor may advise differently" — it's a nudge, not a prescription.

**Tweet 4/10**
[Screenshot placeholder: crumpled lab printout next to the in-app scan flow]
Lab scanning: photograph the report, on-device Vision OCR reads it, matches against a built-in catalog of 40+ tests, shows each value with a status pill. The photo never leaves the phone to do this. It's a paid feature — your first scan is free for life.

**Tweet 5/10**
[Screenshot placeholder: LabDetailView history chart with reference-range band]
Tap any value and you get its full history against the reference range, plus plain language on what high/low typically means. Educational, not diagnostic — every screen says so, because it's true, not because legal made me add it.

**Tweet 6/10**
[Screenshot placeholder: no-login cold open, Dashboard on first launch]
There's no sign-up screen. No account exists to create. Data lives on-device in SwiftData; the app lock is a passcode hashed into the Keychain. It works in airplane mode because it was never talking to a server.

**Tweet 7/10**
The AI layer (report narration, chat, AI-assisted entry) is opt-in and paid: it only ever sees the review summary — never your documents, never the database — routed through a Cloudflare relay I run so the API key never touches the app itself.

**Tweet 8/10**
[Screenshot placeholder: AI report screen with the "Generated by Claude — informational only, not medical advice" footer visible]
One scan-and-report free for life so you can judge it yourself. After that it's $19.99/mo. Tracking, the health score, trends, and the Tests Due card stay free forever, no account, no catch — a single out-of-pocket lab panel alone can cost more than a month of Premium.

**Tweet 9/10**
Numbers so far: pre-launch, zero revenue, solo build. Today's the actual test. Show HN and Product Hunt posts are up (links below), and I'll be replying to everything for the next 72 hours.

**Tweet 10/10**
The ask: if you've got old lab PDFs sitting in your email, try scanning one and tell me if the decoded values actually match what's on the page — and tell me if the "commonly recommended" retest interval it shows matches what your own doctor's actually told you. iOS only for now. Link below.
