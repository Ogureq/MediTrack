> **PRICING CHANGE NOTICE (Jul 2026):** Lab report scanning is now a Premium feature (owner decision). Any line below describing scanning/OCR as free must be revised before publishing. Free tier = vitals/meds/symptoms/goals tracking + score/trends + one AI report.

# MediTrack Content Bank

Launch content executing the strategy in `docs/MARKETING.md`. Sourced from
actual shipped features in `README.md` and the "educational, not diagnostic"
stance in `CLAUDE.md`. Nothing here describes a feature the app doesn't have.

**Compliance rules applied throughout this file (see also CLAUDE.md):**
- No medical claims. Never "improves your health," "catches disease,"
  "diagnoses," "treats," "prevents," or similar. Findings are described as
  educational, and the app's own "not medical advice" disclaimer is treated
  as a fact to surface, not a legal footnote to hide.
- No hype words. "Revolutionary," "game-changing," and similar are banned;
  none appear below.
- Privacy claims are stated exactly as true: no account, on-device SwiftData
  storage, AI is opt-in and sends only the review summary (or, for Quick
  Add, the single sentence typed) through a metered relay — never documents,
  attachments, or the on-device database. One free AI report for life, then
  $19.99/mo (or yearly) for unlimited AI. Every tracking feature is free
  forever.
- No overpromising. The app is iOS-only and pre-launch. Nothing below says
  "available now" or implies Android/web support.
- **CTA convention:** every script's CTA defaults to the pre-launch reality
  — "waitlist link in bio." The bracketed launch-week variant ("free on the
  App Store") should only go live the day the app actually ships. Do not
  swap it early.

---

## A. Ten 30-second short-video scripts

Each script is a real screen recording of the shipped app plus a phone-shot
or voiceover-only cold open. Runtime budget: ~2s hook, ~24s body, ~4s CTA.

### 1. "The Scan" — *Pillar: lab literacy*

**Hook (0:00–0:02, on-screen text):** "I got my labs back. 30 numbers. Zero explanations."

**Shot list:**
1. Cold open, phone camera: a crumpled lab-draw printout on a kitchen table.
2. Cut to screen recording: open a report in MediTrack, tap "Scan for Lab Values."
3. Vision OCR runs over the photographed page (show the brief on-device scanning state).
4. Confirmation sheet appears: recognized values line up against the catalog, each with a status pill (green/yellow/red).
5. Tap into one flagged value (e.g., LDL) → LabDetailView opens: history chart with the reference-range band, plain-language "what high means" text.
6. Quick cut: Dashboard biomarker carousel showing the same marker's mini sparkline.

**Voiceover:**
- "Thirty numbers, and my doctor had eight minutes to explain them."
- "So I photographed the page instead."
- "It reads the values, matches them to a catalog, and shows me what's actually out of range — right there on my phone."
- "Free. And it never leaves my phone to do it."

**On-screen captions:** "on-device OCR" / "no upload" / "free, forever"

**CTA (0:26–0:30):** "Waitlist link in bio." *(Launch-week variant: "Free on the App Store — link in bio.")*

**Pillar:** lab literacy

---

### 2. "POV: You Finally Understand Your Thyroid Panel" — *Pillar: lab literacy*

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

### 3. "What Your LDL Number Actually Means" — *Pillar: lab literacy*

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

### 4. "I Scanned Five Years of Labs" — *Pillar: lab literacy*

**Hook (0:00–0:02, on-screen text):** "I scanned five years of lab PDFs. Found a trend my doctor never mentioned."

**Shot list:**
1. Screen recording: Reports list, several years of entries scrolling past.
2. Tap into Trends tab, select a single marker, switch the time filter from 3M to All.
3. The chart re-renders across the full history — period average line, min/max markers, trend direction visible.
4. Cut to the Health Review's trend finding: "improving / worsening / stable," generated from the linear regression over that same history.
5. Close on the same marker's card in the biomarker carousel, sparkline echoing the long view.

**Voiceover:**
- "One lab result is a data point. Five years of them is a pattern."
- "I'd been keeping these as PDFs in email — nobody, including me, was looking at them side by side."
- "The app lines them up and does the trend math — improving, worsening, or stable — so a slow drift shows up before it's a crisis."
- "It's still just describing my own data back to me. But nobody had done that before."

**On-screen captions:** "your data, your trend" / "on-device"

**CTA:** "If you've got old lab PDFs sitting in email, this is for you. Waitlist link in bio."

**Pillar:** lab literacy

---

### 5. "Sign-Up Screen Speedrun, Health App Edition" — *Pillar: privacy*

**Hook (0:00–0:02, on-screen text):** "Sign-up screen speedrun: health app edition."

**Shot list:**
1. Fast-cut montage (screen recordings, sped up, publicly available competitor sign-up flows — generic framing, no disparaging claims): email field, password field, "verify your email," terms-of-service scroll, a permissions wall — three different apps, ~2 seconds each.
2. Hard cut: MediTrack cold-launched from a fresh install, straight to the onboarding quiz, no email or password field anywhere.
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

### 6. "Rating My Health App's Privacy Policy" — *Pillar: privacy*

**Hook (0:00–0:02, on-screen text):** "Rating my health app's privacy policy vs. the top 5 trackers."

**Shot list:**
1. Creator-collab format: host on camera holding a phone, scrolling a generic privacy-policy PDF, reacting (no disparaging claims about named competitors — describe the category, not specific brands, unless pre-cleared).
2. Cut to MediTrack's in-app "Privacy & Your Data" explainer screen — scroll through it in full.
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

### 7. "AI That Only Sees a Summary" — *Pillar: privacy*

**Hook (0:00–0:02, on-screen text):** "I asked AI to explain my cholesterol. It never saw my files."

**Shot list:**
1. Screen recording: Health Review screen, tap "Generate AI Report."
2. Brief loading state, then the structured AI report renders — plain-language narrative tied to specific findings.
3. Slow zoom/hold on the screen's bottom text: **"Generated by Claude — informational only, not medical advice."**
4. Cut to a simple on-screen diagram (native SwiftUI, not a stock graphic) showing: phone icon → "review summary only" arrow → cloud icon labeled "relay" → a second arrow labeled "Anthropic API," with a crossed-out icon over "attachments / documents / database."
5. Return to app: Ask-about-your-report chat, showing a follow-up question answered in-context.

**Voiceover:**
- "This is the one AI feature in the app — an on-device engine already computed the score and the findings; the AI just explains them in plain language."
- "It only ever sees the review summary — never my attached PDFs, never the on-device database."
- "Every AI response is labeled, so it's always clear what the rule-based engine found versus what the model explained."
- "One report's free for life. After that it's part of premium — because someone has to pay for the model calls, and it isn't your data."

**On-screen captions:** "review summary only" / "no attachments sent" / "labeled every time"

**CTA:** "Waitlist link in bio — your first AI report is free."

**Pillar:** privacy

---

### 8. "Typing a Sentence Instead of Filling a Form" — *Pillar: product magic*

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
- "It parses it on-device and shows me a live preview before anything saves, so I can catch a typo."
- "Works for vitals, meds, symptoms, appointments — one sentence, structured data."

**On-screen captions:** "on-device parsing" / "confirm before it saves"

**CTA:** "Waitlist link in bio."

**Pillar:** product magic

---

### 9. "The 90-Day Report My Doctor Would Charge For" — *Pillar: product magic*

**Hook (0:00–0:02, on-screen text):** "Every 90 days my phone gives me a recap my doctor would charge a copay for."

**Shot list:**
1. Screen recording: Dashboard notification/card inviting the Quarterly Review.
2. Open it — scroll slowly through the full recap: score trajectory graph, a "what changed" section (vitals and labs called out conservatively — only clearly improved or worsened metrics labeled as such), streak and goal wins, a list of doctor-question prompts.
3. Continue scrolling to the end of the recap.
4. Tap the share action — show the ShareLink sheet opening with the plain-text summary ready to send or save.

**Voiceover:**
- "It's not a diagnosis — it's just my own data, organized, every quarter."
- "Score trend, what actually changed, and a running list of questions worth asking at my next appointment."
- "Entirely computed on the device, from records I already logged. I can share it as plain text if I want to bring it to an appointment."

**On-screen captions:** "computed on-device" / "your data, organized"

**CTA:** "Waitlist link in bio."

**Pillar:** product magic

---

### 10. "The Dashboard Row I Check First" — *Pillar: product magic*

**Hook (0:00–0:02, on-screen text):** "This is the first thing I check every morning."

**Shot list:**
1. Screen recording: Dashboard opens directly (no login screen — reinforce cold open speed).
2. Horizontal scroll through the biomarker carousel — each card: marker name, latest value, status pill, mini sparkline.
3. Tap one card through to LabDetailView for the full chart.
4. Back out, show the home-screen widget (small size) on a simulated home screen: score ring, headline, recent vitals, and the locked-state redacted view side by side.
5. Tap the widget (screen recording of the deep link) → opens straight to the Health Review.

**Voiceover:**
- "One row, every marker I track, status at a glance — tap through for the full history any time."
- "The widget mirrors it on my home screen, and it redacts the numbers automatically when my phone's locked."
- "No refreshing, no server round-trip — it's all already on the device."

**On-screen captions:** "redacted when locked" / "on-device"

**CTA:** "Waitlist link in bio."

**Pillar:** product magic

---

**Pillar tally:** lab literacy × 4 (scripts 1–4), privacy × 3 (scripts 5–7), product magic × 3 (scripts 8–10).

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

**Title:** I got tired of re-Googling my TSH every three months, so I built a thing to stop myself. Feedback welcome (I'm the dev, full disclosure).

**Body:**

> Standard disclosure up front: I'm a solo developer and I built the app I'm about to describe. I'm not here to sell anything — genuinely looking for feedback from people who live this, and happy to just talk labs if that's more useful to you than my app is.
>
> Diagnosed hypothyroid a few years back, and my pattern was: get labs, get a portal notification, open a PDF with 30 rows on it, remember that TSH is the one that matters, forget what my number was three draws ago, re-Google "TSH 4.8 meaning," get a mix of WebMD and forum panic, and show up to my endo appointment having learned nothing except how to worry.
>
> What actually helped was a plain spreadsheet where I logged TSH, free T4, and free T3 every draw so I could see the *direction*, not just the number. But keeping that spreadsheet current was its own chore, and it didn't explain anything — I still had to look up what a rising trend with normal T4 usually means.
>
> So I built an iOS app that does the parts I was doing by hand: photograph the lab report page, it reads the values off the page (on-device, nothing uploaded), matches them against a reference range, and shows history as a chart instead of a list. It's not diagnostic — it doesn't tell me anything my doctor wouldn't — it just means I walk into the appointment already knowing my TSH trend over the last year instead of re-deriving it from memory.
>
> Two questions for anyone still reading:
> 1. What do you currently do to track your panels between draws? Spreadsheet, app, nothing, the portal's own graph?
> 2. If you've used a symptom tracker for hypothyroid stuff (fatigue, weight, temperature sensitivity) alongside your labs, did tracking both together ever actually change a conversation with your doctor, or did it just generate more data to sit on?
>
> Not trying to get anyone to download anything — mostly want to know if "trend over time, in plain language, private" is actually the gap, or if I'm solving a problem that was only ever mine. If it's useful to see what I built, I'll drop a link in the comments rather than clutter the post.

---

### B2. r/PrivacyGuides — technical, local-first architecture

**Suggested flair:** Software recommendation / General Discussion (check current rules — PrivacyGuides is strict about self-promo; disclose clearly and expect mod discretion)

**Title:** Built an iOS health tracker with no account and no cloud storage — here's the actual architecture, including the one place data does leave the device (feedback and criticism both welcome)

**Body:**

> Disclosure: I'm the developer. Posting because this sub is exactly the audience that will tell me if I got the privacy model wrong, and I'd rather hear it now than after launch.
>
> The app (MediTrack, iOS 17+) tracks medical records — labs, vitals, meds, symptoms, appointments. Everything is stored on-device via SwiftData; there's no account, no sign-in, and no backend for the core app. A local numeric passcode (salted SHA-256, iOS Keychain, device-only, never synced) plus optional Face ID/Touch ID gates the app itself — that credential never leaves the device either. Backups are AES-GCM-encrypted JSON files the user exports and controls; nothing auto-uploads. Lab-value OCR runs on-device via Apple's Vision framework — a photographed lab report never leaves the phone to be read.
>
> The one deliberate exception is an optional AI explanation layer, and I want to describe exactly what it does rather than assert "it's private, trust me":
>
> - It's opt-in. With no relay/API key configured, the app makes zero network calls, full stop.
> - When enabled, the client sends only pre-computed, structured data to a Cloudflare Workers relay I run: either the rule-based review's summary (score + findings + lab values, no free text from documents), a compact chat context (for follow-up questions about that same review), or a single user-typed sentence (for the natural-language quick-entry feature). It never sends attachments, photographed documents, or the on-device database.
> - The relay holds the Anthropic API key as a Cloudflare secret (`wrangler secret put`) — it's never in the repo, never in the client binary, never in a log. The relay's own logging is metadata-only (hashed device id, token counts, latency, status) by construction, not by "we chose not to log the field this time."
> - Every AI response is verified against the input before display (the app checks that cited numbers and finding IDs actually appear in what was sent) and every refusal (`stop_reason == "refusal"` from the Anthropic API) is surfaced rather than silently swallowed.
>
> Business model, since it's relevant to the incentive structure: every tracking feature is free forever, no account required. AI is the paid tier ($19.99/mo) with one free lifetime report as a trial — so the AI relay is metered and the free local feature set was never designed as a funnel to a data-selling model, because there's no data collection to sell in the first place.
>
> Where I'd genuinely like scrutiny: is "sends only a computed summary, never raw documents" a distinction that matters to this audience, or does any outbound call to a third-party model erase the local-first story for you regardless of payload shape? And is there anything about the on-device-only OCR + Keychain-only credential design that you'd still flag as a gap? Happy to link the repo/README in a comment if that's useful context rather than promotion.

---

### B3. r/QuantifiedSelf — the quarterly review ritual + biomarker trends

**Suggested flair:** Self-Experimentation / Tools (check current flair list)

**Title:** A 90-day recap of my own labs and vitals, computed on-device — sharing the ritual, not just the app (disclosure: I built it)

**Body:**

> Disclosure: I'm the developer of the app in the screenshots below. Posting because this community cares about the *ritual* more than the tool, and I'd like to know if the ritual holds up.
>
> Background: I track blood pressure, resting heart rate, weight, glucose, and sleep daily-ish, plus lab panels a few times a year, in an app I built for myself and then turned into a real product. The part I actually want feedback on isn't the daily logging — it's what I ended up building on top of it: every 90 days, the app assembles a recap entirely from what's already been logged — score trajectory over the quarter, which vitals and labs moved and in which direction (deliberately conservative: it only labels a metric "improved" or "worsened" when the direction is medically unambiguous, everything else is just "changed"), streak/goal wins, and a running list of questions worth bringing to a doctor. All computed on-device, exportable as plain text.
>
> What I like about forcing a quarterly cadence instead of a daily dashboard: daily vitals are noisy enough that a single day tells you almost nothing, but a 90-day window is long enough to separate a real trend from a bad night's sleep or a fluke reading. It's the same instinct as looking at a moving average instead of the raw series.
>
> What I'm unsure about: is 90 days the right window for most people's QS practice, or is that specific to lab-panel cadence (insurance-covered panels tend to land every 3–6 months, which is really why I picked it)? For people tracking things that move faster (HRV, mood, sleep architecture), does a quarterly recap feel too slow to be useful, and would you want a monthly or weekly layer underneath it?
>
> Also curious whether anyone here has a self-built version of this — a script, a Notion template, an Exist.io view — that does something similar, and what cadence you landed on through trial and error rather than picking 90 days because a doctor's office happens to work that way.
>
> Happy to share the app itself in a comment for anyone who wants to see the actual recap screen, but the thing I actually want to talk about is the cadence question.

---

## C. Product Hunt listing draft

**Name:** MediTrack

**Tagline (54 chars):** Scan your labs. See trends. Nothing leaves your phone.

**Description:**

> MediTrack is a local-first iOS app for tracking your own medical records —
> lab results, vitals, medications, symptoms, and appointments — entirely
> on-device. No account, no sign-up, no cloud storage.
>
> Photograph a lab report and on-device OCR (Apple's Vision framework) reads
> the values and matches them against a built-in reference catalog, so a
> page of 30 numbers becomes a chart with a status pill on each one. A
> rule-based analysis engine (not a black box, not a diagnosis) turns your
> reports, vitals, meds, symptoms, and appointments into a 0–100 health
> score and plain-language findings — BP categories, BMI, lipid ratios,
> trend direction, medication-interaction flags — every one of them carrying
> an "ask your doctor" nudge, never a verdict.
>
> Every tracking feature — reports, OCR, the score, trends, backups — is
> free forever. The one optional paid layer is an AI explanation feature:
> Claude narrates your already-computed review in plain language, and you
> get one report free for life before it's $19.99/mo. The AI only ever sees
> a summary of your review, never your documents or your on-device
> database, and it runs through a metered relay so you never need your own
> API key.
>
> Built solo, for the people who get a lab PDF twice a year and have no idea
> what to do with it besides Google the scary parts.

**First comment from the maker:**

> Hey Product Hunt — I'm the solo developer behind MediTrack. Quick story on
> why it exists and why it's built the way it is.
>
> I kept getting lab results back as PDFs — thirty-ish numbers, no context,
> a doctor's appointment three weeks later with eight minutes to go over
> them. I'd Google each flagged value individually and land somewhere
> between WebMD and a forum thread, which is a bad way to learn about your
> own body. What I actually wanted was: read the PDF for me, show me the
> trend instead of just the latest draw, and explain what a range means
> without either sugar-coating it or scaring me.
>
> The local-first part wasn't a marketing decision, it was the actual
> requirement — this is blood work and medication data, and I didn't want
> to be the reason it ended up somewhere I couldn't account for. So there's
> no account. Everything lives in SwiftData on your device. The OCR runs
> on-device. Backups are encrypted files you control. If you never touch
> the AI feature, the app makes zero network calls, period.
>
> The one place I made an exception is the AI layer, because "explain this
> in plain English" is genuinely a better experience with a language model
> than with more rule-based text templates. But I didn't want to build a
> health app that phones home by default, so it's opt-in, it only sends a
> computed summary (never your documents), and it runs through a relay I
> pay for — which is also why it isn't free: one report free for life so
> you can see if it's worth it, then $19.99/mo. Every tracking feature you'd
> actually use daily stays free forever regardless.
>
> I'd love feedback on two things specifically: (1) does the "your first AI
> report is free, then it's paid, but tracking never is" model feel fair,
> and (2) if you've got old lab PDFs sitting in your email right now, does
> the scan-and-decode moment actually work the way I think it does? Happy
> to answer anything about the architecture, the OCR accuracy, or the
> business model — genuinely here all day.

**Gallery image captions:**

1. "Photograph a lab report — on-device OCR matches each value to a reference range and flags what's out of it."
2. "No sign-up screen. The Dashboard is the first thing you see, and it works in airplane mode."
3. "Every 90 days, a recap of what changed — computed on-device, shareable as plain text for your next appointment."

---

## D. Show HN draft

**Title (79 chars):** Show HN: MediTrack – on-device lab OCR, AI relay that never exposes the API key

**Body:**

> MediTrack is an iOS 17+ app for tracking personal medical records — labs,
> vitals, medications, symptoms, appointments — built entirely on Apple's
> own frameworks: SwiftUI, SwiftData for persistence, Swift Charts, Vision
> for OCR, LocalAuthentication for the app lock. No third-party
> dependencies, no SPM packages beyond what Apple ships.
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
> **Where the architecture gets more interesting (to me, anyway):** the one
> network-touching feature is an optional AI explanation layer, and I
> wanted the API key custody story to be airtight, not just "trust me."
> The Anthropic API key never ships in the client. It lives only as a
> Cloudflare Workers secret (`wrangler secret put`), read only by the
> deployed Worker at request time. The iOS app authenticates with a
> device-UUID-for-JWT exchange, then calls a single relay endpoint
> (`POST /v1/ai/generate`) with one of three request shapes: the
> already-computed review summary (for the structured report), a compact
> chat context (for follow-up questions about that same review), or a
> single user-typed sentence (for a natural-language quick-entry feature).
> It never sends attachments, photographed documents, or anything from the
> on-device database — the relay's request validator explicitly rejects
> unknown fields and base64-blob-shaped strings, so an accidental attachment
> field fails the request rather than silently uploading. The relay's own
> logging is metadata-only (hashed device id, token count, latency, model,
> status) by construction — there's no code path that logs request or
> response content.
>
> On the model side, every AI response is checked before it's shown: the
> app verifies numbers and finding IDs the model cites actually appear in
> what was sent, and checks `stop_reason == "refusal"` before treating any
> output as usable.
>
> **Business model:** every tracking feature (OCR scanning, the score,
> trends, backups, reminders) is free forever, no account needed. The
> optional AI layer is $19.99/month, with exactly one free lifetime report
> per device so people can judge it before paying. The relay is metered
> (per-user and global daily token caps) precisely because I'm paying for
> the underlying API usage myself and the free tier has to stay solvent.
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
>   fields (name, DOB, blood type, allergies). If you never open the AI
>   features, the app makes no network calls at all.
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
>   free reports?** Nothing yet — that's a known, documented gap (the
>   relay's App Attest integration isn't wired up). It's on the pre-GA
>   checklist before the relay takes real production traffic, not
>   something I'm pretending is solved.
>
> Feedback on the relay design, the OCR/synonym-matching approach, or the
> "summary only, never raw documents" AI boundary all genuinely welcome —
> this is exactly the audience I built the architecture to survive
> scrutiny from.

---

## E. X launch thread (build-in-public voice)

**Tweet 1/10**
Shipping day. MediTrack is live — an iOS app that turns the lab PDFs you already get from insurance-covered blood work into trends and plain-English explanations. No account. Nothing leaves your phone unless you turn on AI yourself.
🧵

**Tweet 2/10**
Backstory: I kept getting labs back as a 30-row PDF with zero context, then Googling each flagged value and landing somewhere between WebMD and a forum spiral. The doctor's follow-up was 3 weeks later and 8 minutes long. I wanted the boring part — reading the PDF — automated.

**Tweet 3/10**
[Screenshot placeholder: crumpled lab printout next to the in-app scan flow]
So: photograph the report, on-device Vision OCR reads it, matches against a built-in catalog of 40+ tests, shows each value with a status pill. The photo never leaves the phone to do this.

**Tweet 4/10**
[Screenshot placeholder: LabDetailView history chart with reference-range band]
Tap any value and you get its full history against the reference range, plus plain language on what high/low typically means. Educational, not diagnostic — every screen says so, because it's true, not because legal made me add it.

**Tweet 5/10**
[Screenshot placeholder: no-login cold open, Dashboard on first launch]
There's no sign-up screen. No account exists to create. Data lives on-device in SwiftData; the app lock is a passcode hashed into the Keychain. It works in airplane mode because it was never talking to a server.

**Tweet 6/10**
[Screenshot placeholder: Quick Add typing "bp 128/82" with live preview]
My favorite shipped feature: type one sentence — "bp 128/82," "aspirin 100mg twice daily" — and it becomes a structured record with a live preview before you confirm. Parsed on-device.

**Tweet 7/10**
The one AI feature is opt-in: Claude narrates your already-computed health review in plain language. It only ever sees the review summary — never your documents, never the database — routed through a Cloudflare relay I run so the API key never touches the app itself.

**Tweet 8/10**
[Screenshot placeholder: AI report screen with the "Generated by Claude — informational only, not medical advice" footer visible]
One AI report free for life so you can judge it yourself. After that it's $19.99/mo. Every tracking feature — OCR scanning, the score, trends, backups — stays free forever, no account, no catch.

**Tweet 9/10**
Numbers so far: pre-launch, zero revenue, solo build. Today's the actual test. Show HN and Product Hunt posts are up (links below), and I'll be replying to everything for the next 72 hours.

**Tweet 10/10**
The ask: if you've got old lab PDFs sitting in your email, try scanning one and tell me if the decoded values actually match what's on the page — that's the one thing I most want stress-tested by people who aren't me. iOS only for now. Link below.
