# MediTrack

A privacy-first native iOS app that keeps all your medical data on-device and generates a detailed, rule-based health review.

## Features

- **Onboarding** — A 4-page glassmorphic welcome flow shown on first launch, introducing report tracking, detailed reviews, trends, and privacy, ending with a mandatory medical-disclaimer acknowledgement.
- **Medical reports** — Log lab reports, imaging, prescriptions, consultations, and vaccinations. Attach PDFs and photos of the original report, stored entirely on-device. Add structured lab results by picking from a built-in catalog of 40+ common lab tests (CBC, lipid panel, metabolic panel, liver, kidney, thyroid, vitamins, inflammation markers) with standard adult reference ranges, or define custom tests with custom ranges. When a report has attachments, a "Scan for Lab Values" button runs on-device Vision text recognition over the attached photos and PDF pages, matches recognized lines against the lab catalog using a synonym dictionary of common report-form aliases (Hgb, SGPT, A1C, LDL-C, sed rate, etc.), and presents the detected values in a confirmation sheet for review before they're added to the report — recognition happens fully on-device. Existing reports can be edited afterward — update fields, remove lab results or attachments, or add new ones — via an Edit button on the report detail screen.
- **Detailed Health Review** — An on-device, rule-based analysis engine that produces:
  - An overall health score (0–100)
  - Findings grouped by severity (critical / attention / info) with plain-language explanations and suggestions
  - Out-of-range and critical lab flags using sex-specific reference ranges
  - Blood-pressure classification per ACC/AHA categories
  - BMI calculated from profile height and latest weight
  - Trend analysis — linear regression over each lab test and vital, classified as improving / worsening / stable
  - Data-gap nudges (e.g., no recent checkup)

  Every review carries a clear "not medical advice" disclaimer.
- **Score history** — The app records at most one health-score snapshot per day, and the Dashboard shows a "Score History" gradient area chart of the score over time.
- **Vitals tracking** — Weight, blood pressure, resting heart rate, blood glucose, SpO2, and body temperature, with Swift Charts visualizations that include healthy-range bands.
- **Medications** — Track active and past medications with dosage, frequency, start/end dates, and notes. Optionally schedule a daily local-notification reminder at a chosen time for a medication; reminders are automatically cancelled if the medication is deleted or marked ended.
- **Trends** — Per-metric history charts with reference-range band overlays, filterable by a 3M / 6M / 1Y / All segmented time range that also drives the underlying statistics and trend classification.
- **Health profile** — Date of birth, biological sex (used to resolve sex-specific reference ranges), height, blood type, allergies, and conditions.
- **Apple Health import** — A one-tap "Import from Apple Health" action under Profile → Data copies recent vitals — weight, resting heart rate, blood glucose, SpO2, body temperature, and blood-pressure readings (systolic/diastolic correlations) — into the app. The first import covers the past year; subsequent imports only fetch readings since the last import. Requires the HealthKit entitlement. Implemented in `HealthKitService.swift`; imported samples are tagged "Imported from Apple Health".
- **Share/export** — Share a generated review as plain text via the iOS share sheet, or export it as a formatted PDF document (header, score, findings by severity, trends, lab table, and disclaimer).
- **Sample data & data management** — A Data section on the Profile screen offers "Load Sample Data" (a realistic 14-month demo history — 5 reports, 27 lab results, 28 vitals, 3 medications — created only alongside a new, non-destructive demo profile) and "Erase All Data" with a confirmation prompt.

## Design

MediTrack uses a glassmorphic design system built entirely with native SwiftUI materials — no third-party UI libraries. Frosted ultra-thin-material cards carry beveled edge strokes, with light catching the top-left edge and shade falling along the bottom-right, giving each surface a sense of depth. Lists and forms are presented as floating glass chip rows, while health findings and alerts appear as tinted glass cards colored by severity. Every screen sits over an ambient gradient backdrop of blurred teal, blue, and purple orbs that adapts automatically to light and dark mode. The Dashboard's health score is shown in a glowing gradient ring, and primary actions use glass gradient buttons throughout. The system is implemented as a set of reusable modifiers and styles in `MediTrack/Support/Theme.swift` (`glassCard`, `tintedGlassCard`, `ambientScreen`, `GlassRowBackground`, and glass button styles). The app icon carries the same identity forward: a teal-to-blue gradient with a white medical cross and pulse line.

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

## Architecture

MediTrack is a single-target SwiftUI app built entirely on Apple frameworks — SwiftUI for UI, SwiftData for persistence, Swift Charts for visualization, and LocalAuthentication for the optional app lock.

| Folder | Contents |
| --- | --- |
| `MediTrack/Models/` | SwiftData `@Model` classes — `MedicalReport`, `LabResult`, `ReportAttachment`, `VitalSample`, `Medication`, `HealthProfile` — plus `LabCatalog.swift`, the static reference catalog of common lab tests and ranges, and `LabSynonyms.swift`, a dictionary of common report-form aliases used to match scanned text against the lab catalog. |
| `MediTrack/Services/` | `AnalysisEngine.swift`, a set of pure functions that produce a `HealthReview` value from stored data; `BiometricLock.swift` for Face ID / Touch ID app-lock handling; `ReviewPDFExporter.swift` for rendering a Health Review as a formatted PDF; `NotificationService.swift` for scheduling and cancelling medication reminder notifications; `HealthKitService.swift` for importing vitals from Apple Health; and `LabScanService.swift` for running on-device Vision OCR over report attachments to detect lab values. |
| `MediTrack/Views/` | `Dashboard`, `Reports` (list/detail/add), `Review`, `Trends`, `Vitals`, `Medications`, `Profile`, the onboarding flow, and the root `TabView`. |
| `MediTrack/Support/` | `Theme.swift`, the glassmorphic design system (glass card and chip modifiers, ambient backgrounds, button styles), `UIHelpers.swift`, and `SampleData.swift` for seeding a demo history or erasing all app data. |

The analysis engine is rule-based and deterministic — no cloud AI is involved. It is designed so that an LLM-powered summarizer could be added later behind the same `HealthReview` interface without disturbing the rest of the app.

## Privacy

- 100% on-device storage via SwiftData — nothing leaves the device.
- Optional Face ID / Touch ID app lock via LocalAuthentication.
- No network calls, no analytics, no account or sign-in.
- Apple Health data is only read with the user's explicit permission and never leaves the device; OCR lab scanning runs entirely on-device via the Vision framework.

## Roadmap

The following are under consideration for future releases and are **not** implemented today:

- iCloud sync via SwiftData CloudKit mirroring

## Medical Disclaimer

**MediTrack is for informational and educational purposes only. It is not a medical device and does not provide medical advice.** The Detailed Health Review is generated by a deterministic, rule-based engine and does not diagnose, treat, cure, or prevent any disease or condition. It is not a substitute for professional medical judgment.

Always consult a qualified healthcare professional regarding any questions you may have about a medical condition, lab result, medication, or vital sign reading. Never disregard professional medical advice or delay seeking it because of information from this app. If you believe you are experiencing a medical emergency, call your local emergency number immediately.
