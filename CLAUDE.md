# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Gemocode — a local-first iOS 17.0+ medical tracker (SwiftUI + SwiftData, Swift 5 mode, zero third-party dependencies). **Health records never leave the device**: all data lives on-device in SwiftData, secrets in the Keychain, no accounts. The one deliberate exception is AI: `backend/` is a Cloudflare Workers relay (TypeScript, vitest, own CI via `backend-ci.yml`) fronting the owner's Anthropic API key — that key exists ONLY as a wrangler secret, never in this repo, the client, chat logs, or worker logs. Keep both invariants unless the user asks otherwise. Business model: every local feature is free; AI is premium ($19.99/mo) with exactly one free lifetime AI report as a trial.

## Build & test

Requires Xcode 16+ on macOS (the project is `objectVersion 77` — older Xcode cannot open it). In cloud/Linux sessions there is **no Swift toolchain**: CI is the only real compiler, so push to get a verdict; a `python3` bracket-balance check (strip comments/strings, count `(){}[]`) is the only local sanity check.

```bash
# Full build + test (what CI runs)
xcodebuild test -project Gemocode.xcodeproj -scheme Gemocode \
  -destination 'platform=iOS Simulator,name=iPhone 16' CODE_SIGNING_ALLOWED=NO

# Single test class / single test
xcodebuild test ... -only-testing:GemocodeTests/AnalysisEngineTests
xcodebuild test ... -only-testing:GemocodeTests/AnalysisEngineTests/testHealthyProfileScoresFull
```

CI (`.github/workflows/ci.yml`) runs on `macos-15`, uses the runner's **default Xcode** (pinning an older one fails — the image only ships simulator runtimes for the newest SDKs) and picks a simulator by parsing `simctl list --json` (never parse simctl text output; device names contain parentheses).

Because CI builds with `CODE_SIGNING_ALLOWED=NO`, the **Keychain rejects writes on CI**. `AppLockTests` probes the keychain in `setUpWithError` and skips when unavailable — follow that pattern for any new keychain-touching test.

## Targets & project file

Three targets: `Gemocode` (app), `GemocodeTests` (unit tests, runs in the app as TEST_HOST), `GemocodeWidgetsExtension` (WidgetKit, embedded in the app so it always compiles with it).

The `project.pbxproj` is **hand-written** and uses `PBXFileSystemSynchronizedRootGroup` folders:
- Adding a `.swift` file under `Gemocode/`, `GemocodeTests/`, or `GemocodeWidgets/` requires **no project-file edit** — it is picked up automatically.
- Object IDs follow the convention `A1000000000000000000AA__` (app), `AB__` (tests), `AC__` (widgets). New targets need a full hand-written object block; continue the pattern.
- A file inside a synchronized folder that must not be a build member (e.g. the widget's `Info.plist`) needs a `PBXFileSystemSynchronizedBuildFileExceptionSet` — otherwise the build fails with "Multiple commands produce Info.plist".
- After any pbxproj edit, verify brace/paren balance and that every referenced ID is defined exactly once.

## Architecture

- **Models** (`Gemocode/Models/Models.swift`): all 10 `@Model` classes in one file (MedicalReport, LabResult, ReportAttachment, VitalSample, Medication, HealthProfile, ScoreSnapshot, SymptomEntry, Appointment, HealthGoal). Enums are stored as raw strings. A new model must also be registered in the `Schema` in `GemocodeApp.swift`, in `SampleData.eraseAllData`, in `BackupService` (backup payload fields are **optional** for backward compatibility — never add a required field), and in the in-memory `ModelContainer` lists in tests.
- **AnalysisEngine** (`Services/AnalysisEngine.swift`): pure, rule-based `generateReview(profile:reports:vitals:medications:symptoms:appointments:now:)` → `HealthReview` with a 0–100 score and severity-graded `Finding`s (ACC/AHA BP categories, BMI, lipid ratios, linear-regression trends, drug interactions via `MedicationInteractions`). It takes `now` as a parameter — keep it deterministic and unit-testable; no `Date()` inside.
- **Units** (`Support/Units.swift`): storage is always canonical metric (kg, °C, mg/dL); conversion happens only at display time. `HealthKitService` import and write-back mappings must stay in sync with each other (including the ×100 oxygen-saturation scaling).
- **Lab knowledge** (`Models/LabCatalog.swift`, `LabSynonyms.swift`): 46 reference tests with sex-specific ranges + alias matcher used by the OCR scanner (`Services/LabScanService.swift`, whose `parse(lines:)` is static and tested against synthetic OCR lines).
- **App lock** (`Services/AppLock.swift` + `KeychainStore.swift`): salted SHA-256 passcode in Keychain, constant-time compare, Face ID via LocalAuthentication, "Remember me" persisted **only on successful unlock**. Fails open when no credential exists (`canLock`).
- **AI services** (`Services/AISummaryService.swift` structured report, `AIChatService.swift` report chat, `QuickAddAIService.swift` natural-language entry, unified transport in `AITransport.swift`): the only network code in the app. BYOK key lives in the **Keychain** (account "anthropic.apiKey"; the old UserDefaults `anthropicAPIKey` is a read-once migration source only); when a relay base URL is configured, calls route through the backend relay instead. Every path checks `stop_reason == "refusal"` before using content, and report output is verified against the input data (numbers-echo + finding-ID checks) before display.
- **Widget contract**: the widget target **cannot import the app module**. `Services/WidgetBridge.swift` (app) and `GemocodeWidgets/HealthScoreWidget.swift` (extension) intentionally duplicate the `WidgetSnapshot`/`WidgetVital` Codable structs — keep both in sync. Wire format: app group `group.com.ogureq.gemocode`, key `widget.snapshot`, JSON with `.iso8601` dates. `WidgetBridgeTests` locks this contract; a rename on either side should fail it. Widget taps deep-link via `gemocode://review` / `gemocode://trends`, routed by `onOpenURL` in `ContentView`.
- **Design system** (`Support/Theme.swift`, `UIHelpers.swift`): glassmorphic — `.glassCard()`, `.tintedGlassCard()`, `.ambientScreen()`, `GlassRowBackground()` on list rows, `Glass.bevelStroke`/`Glass.accentGradient`, `StatusPill`, `Haptics`. New screens must use these modifiers rather than ad-hoc materials; app-wide font is `.rounded`.

## Conventions

- Medical content is **educational, not diagnostic**: findings/interactions carry recommendation text ("ask your doctor/pharmacist"), and `MedicationInteractions.disclaimer` must accompany interaction lists in UI.
- Tests use fixed dates built from `DateComponents`, no force-unwraps except `XCTUnwrap`, and the in-memory `ModelConfiguration(isStoredInMemoryOnly: true)` pattern from `AnalysisEngineTests`. Tests that touch UserDefaults/Keychain reset the exact keys in both `setUp` and `tearDown`.
- Accessibility is a maintained feature: icon-only buttons get `.accessibilityLabel`, decorative art `.accessibilityHidden(true)`, composite rows are combined elements whose label includes the color-coded state.
- App groups/HealthKit entitlements require a signing team; first local build needs a team selected for both the app and widget targets, or the widget shows its empty state.

## Docs

`docs/PLAN.md` is the phase-by-phase build log (currently through Phase 15) — append a phase when shipping a feature wave, and keep README feature bullets current.
