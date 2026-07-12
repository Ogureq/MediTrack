# MediTrack Development Plan

This document records the phased plan executed to build MediTrack, a privacy-first, on-device iOS health-tracking app.

## Phase 1 — Project Scaffolding

- [x] Create Xcode 16 project targeting iOS 17.0+, Swift 5.9, SwiftUI lifecycle
- [x] Configure file-system-synchronized groups (`MediTrack/Models`, `MediTrack/Services`, `MediTrack/Views`)
- [x] Set bundle identifier, deployment target, and app icon placeholder
- [x] Confirm zero third-party dependencies (no SPM packages, no CocoaPods)
- [x] Initialize git repository and `.gitignore` for Xcode/Swift projects
- [x] Initial commit: full project scaffold with root `TabView`

## Phase 2 — Data Layer

- [x] Define SwiftData `@Model` classes: `HealthProfile`, `MedicalReport`, `LabResult`, `ReportAttachment`, `VitalSample`, `Medication`
- [x] Model relationships (report → lab results, report → attachments) and cascade delete rules
- [x] Build `LabCatalog.swift` — static catalog of 40+ common lab tests (CBC, lipid panel, metabolic panel, liver, kidney, thyroid, vitamins, inflammation markers) with standard adult reference ranges
- [x] Support custom lab tests with user-defined reference ranges
- [x] Wire on-device attachment storage for PDFs and photos (no network upload)
- [x] Configure SwiftData `ModelContainer` for local-only persistence

## Phase 3 — Analysis Engine

- [x] Design `HealthReview` value type as the stable output of the analysis pipeline
- [x] Implement `AnalysisEngine.swift` as pure, deterministic functions (no side effects, no network)
- [x] Out-of-range and critical lab flagging using sex-specific reference ranges
- [x] Blood-pressure classification per ACC/AHA categories
- [x] BMI calculation from profile height and latest weight sample
- [x] Trend analysis via linear regression per lab test / vital, classified improving / worsening / stable
- [x] Data-gap nudges (e.g., no recent checkup, stale vitals)
- [x] Overall health score (0–100) aggregated from findings
- [x] Findings grouped by severity: critical / attention / info, each with plain-language explanation and suggestion
- [x] Embed "not medical advice" disclaimer in every generated review

## Phase 4 — UI

- [x] Root `TabView` with Dashboard, Reports, Review, Trends, and More tabs
- [x] **Dashboard** — summary of latest score, recent findings, quick stats
- [x] **Reports** — list, detail, and add flows for medical reports, including attachment picker and lab-result entry from the catalog
- [x] **Review** — full Detailed Health Review presentation with severity grouping and disclaimer
- [x] **Trends** — per-metric history charts (Swift Charts) with reference-range band overlays
- [x] **More** — nested access to Vitals, Medications, and Profile screens
- [x] **Vitals** — entry and charting for weight, blood pressure, resting heart rate, blood glucose, SpO2, body temperature
- [x] **Medications** — active/past medication tracking with dosage, frequency, and dates
- [x] **Profile** — DOB, biological sex, height, blood type, allergies, conditions
- [x] Share sheet integration for exporting a review as text

## Phase 5 — Privacy & Polish

- [x] Local passcode (salted SHA-256 hash in Keychain) plus optional Face ID / Touch ID and Remember me app lock, implemented in `AppLock.swift` / `KeychainStore.swift`
- [x] Audit for any network calls or analytics and confirm none exist
- [x] Add "not medical advice" disclaimer to Review screen and README
- [x] Empty states for Reports, Vitals, Medications, and Trends when no data exists
- [x] Accessibility pass (Dynamic Type, VoiceOver labels on charts and findings)
- [x] Visual polish pass on Dashboard and Review layouts

## Phase 6 — Docs & Release Prep

- [x] Write `README.md` — features, architecture, privacy, requirements, roadmap, medical disclaimer
- [x] Write `docs/PLAN.md` (this document)
- [x] Verify build from a clean checkout via `MediTrack.xcodeproj`
- [x] Final review of privacy claims and disclaimer language before repository goes live

## Phase 7 — Glassmorphic UI Refresh

- [x] Build glass design system in `Theme.swift` — beveled edge strokes, ambient gradient background, glass card/chip modifiers, and button styles
- [x] Restyle Dashboard with glass cards and a glowing gradient health-score ring
- [x] Convert Health Review into floating glass finding cards tinted by severity
- [x] Apply ambient backgrounds and glass chip rows across all lists, forms, and sheets
- [x] Restyle the app lock screen with the glass design system

## Phase 8 — Feature Expansion

- [x] Onboarding flow — 4-page glassmorphic welcome (track reports / detailed reviews / trends / privacy) ending with mandatory medical-disclaimer acknowledgement, shown on first launch (`OnboardingView.swift`)
- [x] Report editing — edit an existing report's fields, remove lab results or attachments, and add new ones via an Edit button on the report detail screen
- [x] PDF export — export the Health Review as a formatted PDF (header, score, findings by severity, trends, lab table, disclaimer) via `ReviewPDFExporter.swift`, alongside plain-text sharing
- [x] Medication reminders — optional daily local-notification reminder per medication at a chosen time, auto-cancelled when the medication is deleted or marked ended (`NotificationService.swift`)
- [x] Health-score history — `ScoreSnapshot` SwiftData model records at most one score snapshot per day; Dashboard shows a "Score History" gradient area chart
- [x] Trends time ranges — 3M / 6M / 1Y / All segmented filter on the Trends screen, with statistics and trend classification respecting the selected range
- [x] Sample data & data management — Profile Data section with "Load Sample Data" (realistic 14-month demo history: 5 reports, 27 lab results, 28 vitals, 3 medications, created only alongside a non-destructive demo profile) and "Erase All Data" with confirmation (`SampleData.swift`)
- [x] App icon — generated gradient icon (teal→blue with white medical cross and pulse line)

## Phase 9 — Health Import & Report Scanning

- [x] HealthKit entitlement configured in the Xcode project, plus `HealthKitService.swift` for importing vitals
- [x] Profile Data-section import UI — one-tap "Import from Apple Health" action with incremental since-last-import fetching (first import covers the past year; later imports fetch only readings since the last import)
- [x] On-device Vision OCR pipeline over report photo/PDF attachments (`LabScanService.swift`)
- [x] Lab synonym dictionary (`LabSynonyms.swift`, 41 aliases) with longest-match word-boundary matching against the lab catalog
- [x] Scan-results confirmation sheet (`ScannedResultsSheet.swift`) with review-before-add before detected values are added to the report

## Phase 10 — Health Features & UI Polish

- [x] Symptoms journal — log symptoms with a 1–10 severity slider, quick-pick chips for common symptoms, notes, and date (`Views/SymptomsView.swift`); entries from the last two weeks feed the Health Review — a severity-8+ entry raises a needs-attention finding, and 3+ recent entries produce an informational summary
- [x] Appointments — track upcoming/past appointments with doctor and location, an optional local-notification reminder 24h before, a "Next Appointment" card on the Dashboard, and an informational finding in the Health Review (`Views/AppointmentsView.swift`)
- [x] New vitals — Respiratory Rate (typical 12–20 breaths/min) and Sleep (7–9 h), each with engine checks (short sleep <6h raises attention; out-of-range respiratory rate raises attention) and available in charts/trends alongside existing vitals
- [x] Derived lipid insights — engine computes the total-to-HDL cholesterol ratio (ideal <3.5, target <5; ≥5 raises attention) and non-HDL cholesterol (≥160 mg/dL raises attention) whenever both labs are present
- [x] Medical ID — emergency info card under More (name, DOB/age, sex, blood type prominently, height, allergies, conditions, active medications) with a shareable plain-text summary (`Views/MedicalIDView.swift`)
- [x] UI polish — app-wide rounded type design; health-score ring animates on appear with numeric content transitions; Trends charts support touch scrubbing with a frosted-glass value tooltip; haptic feedback on saves; lock screen prompts Face ID immediately; Dashboard date header and next-appointment card; More tab reorganized (Vitals/Symptoms/Medications/Appointments + Medical ID/Profile)

## Phase 11 — Data Ownership & Hardening

- [x] Lab test detail screens — tapping any lab value in the Health Review or a report's detail opens a dedicated screen (`Views/LabDetailView.swift`) with the latest value and status, a full history chart with the reference-range band, what the test measures, plain-language meaning of high and low values, typical range/unit/category details, and every recorded entry with per-entry status
- [x] Backup & restore — Profile → Data "Export Backup" (one JSON file containing profile, reports with lab results and attachments, vitals, medications, symptoms, appointments, and score history) and "Restore from Backup" (replace-all with confirmation; reminders must be re-enabled afterward), implemented in `Services/BackupService.swift` with a versioned Codable payload
- [x] Dashboard sparklines — each vital tile on the Dashboard shows a mini 12-point trend sparkline
- [x] Full codebase audit — two-agent sweep of all models, services, views, and the Xcode project file for compile errors, API mismatches, SwiftData pitfalls, and crash-level bugs; fixed an invalid SF Symbol name for the temperature vital icon and a Profile-screen hang after "Erase All Data" by recreating a blank profile

## Phase 12 — Goals, Units, Editing & Optional AI

- [x] Health goals — `HealthGoal` model with progress from start value to target, Goals screen, Dashboard progress card, backup/sample-data/erase coverage
- [x] Unit preferences — kg/lb, °C/°F, mg/dL vs mmol/L conversion layer (`Support/Units.swift`) applied to entry sheets, charts, trends, tiles, and engine texts
- [x] Medication and appointment editing — tap-to-edit sheets with in-place updates and notification rescheduling
- [x] Optional AI plain-language summaries — bring-your-own Anthropic API key (`Services/AISummaryService.swift`), review-text-only payload, refusal and error handling, glass AI card on the Review screen
- [x] Structural verification pass across all Swift sources (brace/paren balance)

## Phase 13 — Login & Remember Me

- [x] Local numeric passcode (4–8 digits) stored as a salted SHA-256 hash in the iOS Keychain, plus optional Face ID / Touch ID login, implemented in `Services/AppLock.swift` (lock coordinator) and `Services/KeychainStore.swift` (Keychain wrapper)
- [x] Login panel (`Views/LoginView.swift`) with passcode field, "Unlock with Face ID/Touch ID" button, and a "Remember me" toggle that keeps the session signed in across launches until Lock Now is tapped or the toggle is turned off; without Remember me, the app requires login whenever it returns from the background
- [x] Profile → "Login & Security" section — require-login toggle, Set/Change/Remove Passcode, Use Face ID/Touch ID toggle, Stay-signed-in (Remember me) toggle, and a Lock Now button
- [x] Fail-open safety — the lock never locks the user out: if no passcode is set and biometrics are unavailable, the app remains accessible

## Phase 14 — Hardening

- [x] Medication interaction warnings — a curated, educational checker (~20 drug classes, 20 well-established interaction rules) that flags risky combinations among active medications, surfaced in the Medications screen and Health Review findings. Educational only, not exhaustive — users are prompted to confirm with a pharmacist.
- [x] Passcode & biometric login finalization — comprehensive on-device authentication (salted SHA-256 in Keychain, Face ID / Touch ID, Remember me toggle) hardening the app's security posture against unauthorized access
- [x] XCTest unit-test suite — tests covering the analysis engine, services, and data models, implemented in `MediTrackTests/` with comprehensive coverage of critical paths
- [x] GitHub Actions CI — automated testing workflow (.github/workflows/ci.yml) running `xcodebuild test` on macOS for every push, ensuring all tests pass before merge

## Phase 15 — Widgets & Deeper Health Integration

- [x] HealthKit write-back — implemented opt-in toggle in Profile to save logged vitals (blood pressure as systolic/diastolic correlation) back to Apple Health, extending the bidirectional health data flow
- [x] Richer trend charts — enhanced Trends visualization with healthy-range band, period average line, min/max markers, gradient fill, and dual-series blood-pressure charting for deeper trend analysis
- [x] Home-screen widget extension — created Health Score widget (small & medium sizes) displaying latest score ring, headline, and recent vitals via a shared app-group snapshot, enabling quick health status glance from home screen

## Phase 16 — Roadmap P1: Activation, Trust, and the AI Analyst

- [x] Personalized onboarding quiz — enhanced onboarding flow that gathers health profile basics and preferences before the welcome tour
- [x] Today dashboard — dedicated daily view with personalized supplement and habit reminders, completion tracking, multi-day streaks, and optional daily notifications
- [x] AI Health Analyst structured report — enhanced AI summary feature that narrates findings with verified citations to your data; engine computes numbers and findings, AI provides narrative structure; falls back to rule-based review
- [x] Deterministic health timeline — chronological view of all health events (labs, vitals, symptoms, medications, appointments) with consistent, reproducible ordering
- [x] Passphrase-encrypted backups (AES-GCM) — backup export now uses AES-GCM encryption with user-supplied passphrase, improving security of exported files
- [x] Login attempt lockout — automatic lockout after repeated failed login attempts to prevent brute-force passcode guessing
- [x] Shareable redacted score card — generate health-score summary with trends and vitals, omitting sensitive details, suitable for sharing with healthcare providers
- [x] Privacy & Your Data explainer — dedicated educational screen documenting on-device storage, data protection, data ownership, and control
- [x] Re-test and score-change notifications — optional push notifications alert on lab re-test recommendations (90-day intervals) and meaningful score changes

## Phase 17 — Roadmap P2 Wave 1: Effortless Data Entry

- [x] Quick Add — a Dashboard sheet where the user types one natural sentence ("aspirin 100mg twice daily", "bp 128/82", "dentist tomorrow 3pm") and a deterministic on-device parser (`Services/QuickAddParser.swift`, 43 unit tests) turns it into a live-previewed draft medication, vital, symptom, appointment, or reminder — confirm to save
- [x] AI-assist fill (optional) — when the deterministic parser can't read a genuine attempt and an API key is configured, a "Fill with AI" button sends the sentence to a small model under a strict single-JSON-object contract; the response is re-validated against the same plausibility bounds as the parser (20 networking-free unit tests) and labeled "AI-filled — please double-check"
- [x] Modernized add/edit sheets — all six add sheets (medications, vitals, symptoms, appointments, goals, reminders) redesigned from dense forms into scrollable glass-card layouts with one-tap suggestion chips, icon-chip pickers, and an auto-expanding "Add details" disclosure for secondary fields; save and validation logic unchanged

## Phase 18 — Roadmap P2 Wave 2: AI Companion & Premium

- [x] "Ask about this report" AI chat — a chat sheet on the Health Review (`Services/AIChatService.swift`, `Views/AIChatView.swift`) constrained to the current score and findings; conversation memory is client-held only, answers carry educational framing with doctor/pharmacist nudges, and only the review summary ever leaves the device
- [x] Premium scaffolding — StoreKit 2 `PremiumStore` (monthly/yearly subscriptions, verified entitlements) with a glassmorphic `PaywallView` reached from Profile; degrades honestly to a "purchases aren't available in this build" state until a developer account is connected
- [x] Free AI-report quota — 3 lifetime AI reports free (pure, unit-tested `AIReportQuota`), spent only on successful generation; premium unlocks unlimited reports while every local tracking feature stays free forever
- [x] Widget lock-screen privacy — the home-screen widget's score and vitals are `privacySensitive` and render redacted while the device is locked

## Future Milestones

Not part of the current plan; captured here for future scoping:

- iCloud sync via SwiftData CloudKit mirroring
