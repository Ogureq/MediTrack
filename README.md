# MediTrack

A privacy-first native iOS app that keeps all your medical data on-device and generates a detailed, rule-based health review.

## Features

- **Onboarding** — A personalized onboarding quiz shown on first launch that gathers health profile basics and preferences, followed by a 4-page glassmorphic welcome flow introducing report tracking, detailed reviews, trends, and privacy, ending with a mandatory medical-disclaimer acknowledgement.
- **Medical reports** — Log lab reports, imaging, prescriptions, consultations, and vaccinations. Attach PDFs and photos of the original report, stored entirely on-device. Add structured lab results by picking from a built-in catalog of 40+ common lab tests (CBC, lipid panel, metabolic panel, liver, kidney, thyroid, vitamins, inflammation markers) with standard adult reference ranges, or define custom tests with custom ranges. When a report has attachments, a "Scan for Lab Values" button runs on-device Vision text recognition over the attached photos and PDF pages, matches recognized lines against the lab catalog using a synonym dictionary of common report-form aliases (Hgb, SGPT, A1C, LDL-C, sed rate, etc.), and presents the detected values in a confirmation sheet for review before they're added to the report — recognition happens fully on-device. Existing reports can be edited afterward — update fields, remove lab results or attachments, or add new ones — via an Edit button on the report detail screen. Tapping any lab value — whether in a report's detail screen or in the Health Review — opens a dedicated lab detail screen (`Views/LabDetailView.swift`) with the latest value and status, a full history chart overlaying the reference-range band, what the test measures, a plain-language explanation of what high and low results mean, typical range/unit/category details, and every recorded entry with its own status.
- **Detailed Health Review** — An on-device, rule-based analysis engine that produces:
  - An overall health score (0–100)
  - Findings grouped by severity (critical / attention / info) with plain-language explanations and suggestions
  - Out-of-range and critical lab flags using sex-specific reference ranges
  - Blood-pressure classification per ACC/AHA categories
  - BMI calculated from profile height and latest weight
  - Derived lipid insights — total-to-HDL cholesterol ratio (ideal <3.5, target <5; ≥5 flagged for attention) and non-HDL cholesterol (≥160 mg/dL flagged for attention), computed whenever both labs are present
  - Symptom and appointment awareness — a severity-8+ symptom logged in the last two weeks raises a needs-attention finding, 3+ recent symptom entries produce an informational summary, and upcoming appointments surface an informational finding
  - Trend analysis — linear regression over each lab test and vital, classified as improving / worsening / stable
  - Data-gap nudges (e.g., no recent checkup)

  Every review carries a clear "not medical advice" disclaimer.
- **Score history** — The app records at most one health-score snapshot per day, and the Dashboard shows a "Score History" gradient area chart of the score over time.
- **Vitals tracking** — Weight, blood pressure, resting heart rate, blood glucose, SpO2, body temperature, respiratory rate (typical 12–20 breaths/min), and sleep (7–9 h), with Swift Charts visualizations that include healthy-range bands. Each vital's Dashboard tile also shows a mini 12-point trend sparkline.
- **Symptoms journal** — Log symptoms with a 1–10 severity slider, quick-pick chips for common symptoms, notes, and date (`Views/SymptomsView.swift`); entries from the last two weeks feed the Health Review as described above.
- **Medications** — Track active and past medications with dosage, frequency, start/end dates, and notes. Optionally schedule a daily local-notification reminder at a chosen time for a medication; reminders are automatically cancelled if the medication is deleted or marked ended.
- **Medication interaction warnings** — A curated, educational checker (~20 drug classes, 20 well-established interaction rules) that flags risky combinations among active medications, surfaced both in the Medications screen and in the Health Review findings. Educational only, not exhaustive — always confirm with a pharmacist.
- **Appointments** — Track upcoming and past appointments with doctor and location, with an optional local-notification reminder 24 hours before, a "Next Appointment" card on the Dashboard, and an informational finding in the Health Review (`Views/AppointmentsView.swift`).
- **Trends** — Per-metric history charts with reference-range band overlays, filterable by a 3M / 6M / 1Y / All segmented time range that also drives the underlying statistics and trend classification.
- **Deterministic health timeline** — A chronological view of all health events — lab results, vitals, symptoms, medications, and appointments — showing the complete history of your health record with a consistent, reproducible ordering that enables transparent health tracking and review.
- **Health profile** — Date of birth, biological sex (used to resolve sex-specific reference ranges), height, blood type, allergies, and conditions.
- **Medical ID** — An emergency info card under More surfacing name, date of birth/age, sex, blood type, height, allergies, conditions, and active medications — with blood type shown prominently — plus a shareable plain-text summary (`Views/MedicalIDView.swift`).
- **Shareable redacted score card** — Generate a redacted health-score summary suitable for sharing with healthcare providers, showing your overall score, key trends, and vital signs while omitting sensitive details like lab values, medications, and symptoms. Helps you prepare for doctor visits and communicate your health status privately.
- **Apple Health import** — A one-tap "Import from Apple Health" action under Profile → Data copies recent vitals — weight, resting heart rate, blood glucose, SpO2, body temperature, and blood-pressure readings (systolic/diastolic correlations) — into the app. The first import covers the past year; subsequent imports only fetch readings since the last import. Requires the HealthKit entitlement. Implemented in `HealthKitService.swift`; imported samples are tagged "Imported from Apple Health".
- **HealthKit write-back** — Optionally save vitals you log back to Apple Health (blood pressure as a systolic/diastolic correlation); opt-in toggle in Profile.
- **Richer trend charts** — Healthy-range band, period average line, min/max markers, gradient fill, and dual-series blood pressure visualization for deeper trend analysis.
- **Home-screen widget** — A Health Score widget (small & medium) showing your latest score ring, headline, and recent vitals via a shared app group.
- **Share/export** — Share a generated review as plain text via the iOS share sheet, or export it as a formatted PDF document (header, score, findings by severity, trends, lab table, and disclaimer).
- **Health goals** — Set a target for any vital (goal weight, nightly sleep hours, ...) with progress tracked from your starting value as new readings arrive; active/completed lists, achieved badges, optional target dates, and a Goals progress card on the Dashboard.
- **Today dashboard** — A dedicated daily view showing personalized supplement and habit reminders with completion tracking, multi-day streaks, and optional daily notifications to encourage consistent self-care routines.
- **Unit preferences** — kg/lb, °C/°F, and mg/dL / mmol/L pickers in Profile; vitals are stored in metric and converted at display and entry across tiles, charts, trends, and review text.
- **AI Health Analyst (optional)** — Bring your own Anthropic API key to have Claude generate a structured report that narrates the health review findings with plain-language insights and verified citations to your data. The analysis engine computes all numbers and findings; the AI provides educational context and narrative structure. Falls back to the rule-based review if AI is unavailable. Strictly opt-in: only the review text is sent (never documents or the database), the key stays on-device, and leaving it empty keeps the app fully offline.
- **Full editing** — Reports, medications, and appointments can all be edited after creation; reminder notifications are rescheduled automatically when times change.
- **Sample data & data management** — A Data section on the Profile screen offers "Load Sample Data" (a realistic 14-month demo history — 5 reports, 27 lab results, 28 vitals, 3 medications — created only alongside a new, non-destructive demo profile) and "Erase All Data" with a confirmation prompt.
- **Backup & restore** — Profile → Data also offers "Export Backup", which writes a single passphrase-encrypted JSON file (AES-GCM) containing everything — profile, reports with lab results and attachments, vitals, medications, symptoms, appointments, and score history — and "Restore from Backup", which replaces all app data with a confirmation prompt (reminders must be re-enabled afterward). Backups remain entirely on-device under your control. Implemented in `Services/BackupService.swift` using a versioned Codable payload.
- **Login & Security** — Set a local numeric passcode (4–8 digits), stored as a salted SHA-256 hash in the iOS Keychain (device-only, never synced), with optional Face ID / Touch ID unlock and automatic lockout after repeated failed login attempts. A dedicated login panel (`Views/LoginView.swift`) appears whenever the app is locked, offering the passcode field, an "Unlock with Face ID/Touch ID" button, and a "Remember me" toggle that keeps you signed in across launches until you tap Lock Now or turn it off; with Remember me off, the app requires login whenever it returns from the background. Profile → "Login & Security" lets you require login, set/change/remove the passcode, toggle Face ID/Touch ID, toggle Remember me, and lock the app immediately. Authentication is entirely on-device — there's no account and no server.

## Design

MediTrack uses a glassmorphic design system built entirely with native SwiftUI materials — no third-party UI libraries. Frosted ultra-thin-material cards carry beveled edge strokes, with light catching the top-left edge and shade falling along the bottom-right, giving each surface a sense of depth. Lists and forms are presented as floating glass chip rows, while health findings and alerts appear as tinted glass cards colored by severity. Every screen sits over an ambient gradient backdrop of blurred teal, blue, and purple orbs that adapts automatically to light and dark mode. The Dashboard's health score is shown in a glowing gradient ring, and primary actions use glass gradient buttons throughout. The system is implemented as a set of reusable modifiers and styles in `MediTrack/Support/Theme.swift` (`glassCard`, `tintedGlassCard`, `ambientScreen`, `GlassRowBackground`, and glass button styles). The app icon carries the same identity forward: a teal-to-blue gradient with a white medical cross and pulse line. Type is set in a rounded system design throughout for a softer, friendlier feel. The Dashboard's health-score ring animates into place on appear with numeric content transitions, Trends charts support touch scrubbing with a frosted-glass value tooltip, and key actions such as saves are confirmed with haptic feedback.

## Screenshots

_Screenshots coming soon._

| Dashboard | Reports | Review | Trends |
| --- | --- | --- | --- |
| _placeholder_ | _placeholder_ | _placeholder_ | _placeholder_ |

## Requirements & Building

- Xcode 16 or later
- iOS 17.0+ simulator or device
- Swift 5.9
- No third-party dependencies — no Swift Package Manager, no CocoaPods

To build and run:

1. Open `MediTrack.xcodeproj` in Xcode.
2. Select the **MediTrack** scheme.
3. Choose an iOS 17+ simulator or a connected device.
4. Run (`Cmd+R`).

**Note:** Widgets require an App Group; select your signing team for both the app and widget targets in Xcode the first time you build.

## Architecture

MediTrack is a single-target SwiftUI app built entirely on Apple frameworks — SwiftUI for UI, SwiftData for persistence, Swift Charts for visualization, and LocalAuthentication for the optional app lock.

| Folder | Contents |
| --- | --- |
| `MediTrack/Models/` | SwiftData `@Model` classes — `MedicalReport`, `LabResult`, `ReportAttachment`, `VitalSample`, `Medication`, `HealthProfile` — plus `LabCatalog.swift`, the static reference catalog of common lab tests and ranges, and `LabSynonyms.swift`, a dictionary of common report-form aliases used to match scanned text against the lab catalog. |
| `MediTrack/Services/` | `AnalysisEngine.swift`, a set of pure functions that produce a `HealthReview` value from stored data; `AppLock.swift` and `KeychainStore.swift` for login/passcode/biometrics handling; `ReviewPDFExporter.swift` for rendering a Health Review as a formatted PDF; `NotificationService.swift` for scheduling and cancelling medication reminder notifications; `HealthKitService.swift` for importing vitals from Apple Health; `LabScanService.swift` for running on-device Vision OCR over report attachments to detect lab values; and `BackupService.swift` for exporting and restoring a full JSON backup of app data. |
| `MediTrack/Views/` | `Dashboard`, `Reports` (list/detail/add), `Review`, `Trends`, `Vitals`, `Symptoms`, `Medications`, `Appointments`, `MedicalID`, `Profile`, `LabDetailView` (per-test detail with history chart), the onboarding flow, and the root `TabView`. |
| `MediTrack/Support/` | `Theme.swift`, the glassmorphic design system (glass card and chip modifiers, ambient backgrounds, button styles), `UIHelpers.swift`, and `SampleData.swift` for seeding a demo history or erasing all app data. |

The analysis engine is rule-based and deterministic — no cloud AI is involved. It is designed so that an LLM-powered summarizer could be added later behind the same `HealthReview` interface without disturbing the rest of the app.

## Privacy

- **Privacy & Your Data explainer** — A dedicated educational screen in the app explaining exactly what data is stored on-device, how it is protected, what is never shared, and how you maintain full ownership and control. Written in plain language to build trust and transparency about data handling.
- 100% on-device storage via SwiftData — nothing leaves the device.
- App lock via a local numeric passcode (4–8 digits), stored as a salted SHA-256 hash in the iOS Keychain (device-only, never synced), plus optional Face ID / Touch ID and a "Remember me" stay-signed-in toggle — the entire login system runs on-device, with no account and no server.
- No network calls by default, no analytics, no account or sign-in. The optional AI summary feature is the single exception: if you add your own Anthropic API key, the review text (and nothing else) is sent to Anthropic's API when you tap Generate.
- Apple Health data is only read with the user's explicit permission and never leaves the device; OCR lab scanning runs entirely on-device via the Vision framework.
- Backups are passphrase-encrypted (AES-GCM) JSON files the user controls — exported to a location of their choosing and never uploaded anywhere.

## Testing & CI

- Unit tests live in `MediTrackTests/` using XCTest and cover the analysis engine, services, and data models.
- GitHub Actions runs `xcodebuild test` on macOS for every push via `.github/workflows/ci.yml`, ensuring all tests pass before code is merged.

## Roadmap

The following are under consideration for future releases and are **not** implemented today:

- iCloud sync via SwiftData CloudKit mirroring

## Medical Disclaimer

**MediTrack is for informational and educational purposes only. It is not a medical device and does not provide medical advice.** The Detailed Health Review is generated by a deterministic, rule-based engine and does not diagnose, treat, cure, or prevent any disease or condition. It is not a substitute for professional medical judgment.

Always consult a qualified healthcare professional regarding any questions you may have about a medical condition, lab result, medication, or vital sign reading. Never disregard professional medical advice or delay seeking it because of information from this app. If you believe you are experiencing a medical emergency, call your local emergency number immediately.
