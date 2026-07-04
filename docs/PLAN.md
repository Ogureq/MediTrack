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

- [x] Optional Face ID / Touch ID app lock via `BiometricLock.swift` (LocalAuthentication)
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

## Future Milestones

Not part of the current plan; captured here for future scoping:

- HealthKit import
- OCR of report PDFs via the Vision framework
- iCloud sync via SwiftData CloudKit mirroring
- Medication reminders via local notifications
- PDF export of reviews
