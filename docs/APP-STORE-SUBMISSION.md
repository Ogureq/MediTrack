# App Store Submission Guide — Gemocode

Every step from "enrollment approved" to "live on the App Store," specific
to this app. Work top to bottom; each step says where you do it (Mac/Xcode,
App Store Connect website, or phone). Companion docs:
docs/marketing/app-store-listing.md (all paste-ready listing copy),
docs/EXECUTION.md (the day-by-day schedule this slots into).

Already done in this repo, no action needed: app icon (light/dark/tinted),
privacy policy & terms live at gemocode.com/privacy.html and /terms.html,
medical disclaimers in-app, listing copy written, bundle id decided
(com.ogureq.gemocode), StoreKit client code (PremiumStore).

---

## STEP 0 — Prerequisites (blockers if skipped)

1. **Apple Developer Program approved** (the $99 enrollment). Status shows
   in the Apple Developer app / developer.apple.com/account.
2. **Agreements, Tax, and Banking** — REQUIRED before subscriptions can
   even be created. appstoreconnect.apple.com → Business (or "Agreements,
   Tax, and Banking"):
   - Accept the **Paid Applications Agreement**.
   - Add your **bank account** (IBAN works for Türkiye).
   - Fill the **tax forms** (for a Türkiye individual: the standard
     questionnaire + W-8BEN for US sales — it's guided, ~10 min).
   Without all three, subscription products stay stuck in "Missing
   Metadata" and the app can't make money.

## STEP 1 — Signing & capabilities (Mac, Xcode, ~10 min)

1. Open the project → select the **Gemocode** target → Signing &
   Capabilities → Team: pick your (now paid) team. Repeat for the
   **GemocodeWidgetsExtension** target. Keep "Automatically manage
   signing" on — Xcode registers the bundle ids
   (com.ogureq.gemocode + .widgets), the app group
   (group.com.ogureq.gemocode), and HealthKit entitlements for you.
2. Build & run once on your device from this signed state to confirm
   nothing broke (widget should now show data too, since the app group is
   real).

## STEP 2 — Create the app record (App Store Connect, ~10 min)

appstoreconnect.apple.com → My Apps → "+" → New App:
- Platform: iOS. Name: **Gemocode: Lab & Health Diary** (28 chars, from
  the listing kit; if taken, fall back to "Gemocode — Lab & Health Diary").
- Primary language: English (U.S.). Bundle ID: pick
  **com.ogureq.gemocode** from the dropdown (appears after Step 1's first
  signed build; if missing, register it at developer.apple.com/account →
  Identifiers). SKU: `gemocode-ios` (internal, never shown).

## STEP 3 — Archive & upload the build (Mac, Xcode, ~15 min)

1. `git pull` first — always ship the latest verified code.
2. In Xcode: select destination **Any iOS Device (arm64)** (not a
   simulator — Archive is greyed out otherwise).
3. Menu: **Product → Archive**. Wait for the Organizer window.
4. In Organizer: **Distribute App → App Store Connect → Upload** → accept
   defaults (upload symbols: yes; auto signing: yes).
5. Wait 10–30 min for processing (email arrives). The build then appears
   in App Store Connect → your app → **TestFlight** tab.
6. First build only: answer the **Export Compliance** question — the app
   uses only standard HTTPS/Apple crypto → answer "Yes, uses encryption /
   exempt" (standard exemption). To skip the question on every future
   build, ask Claude to add `ITSAppUsesNonExemptEncryption = NO` to the
   project — do this once you're tired of clicking.

## STEP 4 — TestFlight beta (do this BEFORE the store submission)

1. TestFlight tab → the processed build → fill "What to Test" (paste the
   promo text from the listing kit).
2. **Internal testing**: add yourself → instant, no review.
3. **External testing**: create group "Beta" → add the build → answer the
   beta review questions (contact info; notes: "Tap Profile → Data → Load
   Sample Data to explore with demo data") → wait for beta review
   (usually <24 h, only the first build) → enable **Public Link**.
4. Send me the public link — I flip gemocode.com's beta button from email
   to TestFlight in one line.
5. Run the beta per docs/EXECUTION.md Phase 1 (20 testers, crash-free
   week) before submitting to the store.

## STEP 5 — Subscriptions (App Store Connect, ~30 min)

Your app → Monetization → **Subscriptions** → Create Subscription Group:
"Gemocode Premium". Inside it create:
1. **Monthly**: reference name "Premium Monthly", product ID
   `com.ogureq.gemocode.premium.monthly`, price **$19.99** (pick the tier;
   Apple auto-converts other currencies).
2. **Yearly**: `com.ogureq.gemocode.premium.yearly` — recommended
   **$149.99** (~37% off, standard yearly anchor).
Each needs: localized display name + description (one sentence: "Unlimited
lab scanning, AI reports, chat, and AI-assisted entry."), and a **review
screenshot** (screenshot of the paywall screen from your phone).

⚠️ The product IDs must match what PremiumStore expects — tell Claude the
exact IDs you created (or use the ones above) so the code and store agree;
mismatch = empty paywall, App Review rejection 2.1.

Also create the **Lifetime** non-consumable ONLY if you want it visible;
it's deliberately dormant in the app — skip it.

## STEP 6 — The listing (App Store Connect → App Store tab, ~45 min)

Copy everything from docs/marketing/app-store-listing.md verbatim:
- **Name / Subtitle / Promotional text / Description / Keywords** — all
  pre-written and within limits there.
- **Screenshots**: required size is the 6.9" iPhone set (1320×2868) — an
  iPhone 16 Pro/Pro Max screenshot uploads directly; the kit's 7-shot
  plan says exactly which screens to capture, in order. Take them on your
  phone with sample data loaded, AirDrop to the Mac, upload. One size is
  enough (Apple scales the rest).
- **App Privacy** (the nutrition label): "Data Not Collected" for
  everything EXCEPT → add **Health & Fitness** data, purpose **App
  Functionality**, **Not linked to identity**, **No tracking** — this
  covers the AI request's review summary through your relay. This label
  matches what the app actually does; don't overclaim or underclaim.
- **Age rating** questionnaire: answer "Medical/Treatment Information:
  Infrequent/Mild" → lands at 12+.
- **Category**: Primary Medical, Secondary Health & Fitness.
- **Privacy Policy URL**: https://gemocode.com/privacy.html
- **Support URL**: https://gemocode.com
- **App Review Information**: contact = your real phone/email (private to
  Apple). Notes — paste:
  "Gemocode is an educational health tracker; it does not diagnose (see
  in-app disclaimers). To explore with demo data: Profile → Data → Load
  Sample Data. AI features route through our relay service; the free tier
  includes one AI report, further use requires the Premium subscription.
  No account or login exists — all data is on-device."

## STEP 7 — Submit for review

1. App Store tab → version 1.0 → select the build from Step 3.
2. **Release option: choose "Manually release this version"** — so
  approval doesn't auto-launch you before launch day (docs/EXECUTION.md
  Phase 2/3 timing).
3. Attach the subscription products to this version (they're reviewed
   together the first time).
4. Submit. Typical wait: 24–72 h.

**Likely rejection points & the answers (medical category):**
- 1.4.1 "medical advice" → point to the in-app disclaimers on the Review
  screen, PDF, onboarding, and every interaction list ("educational, not
  diagnostic; consult your doctor"). They're already everywhere.
- 2.1 "can't find feature X" → reply with the Load Sample Data path and,
  if it's about premium, a note that the reviewer sandbox can purchase the
  subscription for free.
- 3.1.2 "subscription terms" → the paywall already links Privacy + Terms
  in-app; if flagged, also paste both URLs into the App Description field.
- 5.1.1 "data collection" → the privacy label says Not Collected; explain
  the relay receives a transient text summary, stores nothing
  identifiable, and there are no accounts.
Rejections arrive as messages in App Store Connect — reply there, fix
only what's named, resubmit same day. One round is NORMAL (~40% of first
submissions); don't panic, forward the text to Claude.

## STEP 8 — Approved → launch

1. Status "Pending Developer Release" — hold until launch morning
   (Tuesday per the playbook).
2. Press **Release This Version**. Propagation: 1–24 h worldwide.
3. Tell Claude → beta.html + site switch to the App Store link, marketing
   assets go out per EXECUTION.md Phase 3.
4. Buy Premium yourself with a real card as the final smoke test (refund
   after via reportaproblem.apple.com).

## STEP 9 — Post-launch hardening (first quiet day after launch)

- Ask Claude for the App Store **server-side receipt verification** in the
  relay, then set `ENFORCE_PREMIUM = "true"` in wrangler.toml and
  `npm run deploy` — closes the door on free AI abuse for good.
- Raise `GLOBAL_DAILY_TOKENS` back to a launch-sized value (e.g. 5000000)
  once real users are paying.
- Turn on App Store Connect email notifications for reviews; reply to
  every review from day one.
