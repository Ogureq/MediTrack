import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import StoreKit
import UserNotifications

struct ProfileView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var profiles: [HealthProfile]

    var body: some View {
        Group {
            if let profile = profiles.first {
                ProfileForm(profile: profile)
            } else {
                ProgressView()
            }
        }
        .ambientScreen()
        .navigationTitle("Profile & Settings")
        .task {
            if profiles.isEmpty {
                modelContext.insert(HealthProfile())
            }
        }
    }
}

private struct ProfileForm: View {
    @Bindable var profile: HealthProfile
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("appLockEnabled") private var appLockEnabled = false
    @AppStorage("lastHealthImportAt") private var lastHealthImportAt: Double = 0
    @AppStorage("health.writeBackEnabled") private var healthWriteBackEnabled = false
    @AppStorage(HealthKitService.automaticSyncKey) private var automaticSyncEnabled = false
    @AppStorage(Units.weightKey) private var weightUnitRaw = WeightUnit.kilograms.rawValue
    @AppStorage(Units.temperatureKey) private var temperatureUnitRaw = TemperatureUnit.celsius.rawValue
    @AppStorage(Units.glucoseKey) private var glucoseUnitRaw = GlucoseUnit.mgdL.rawValue
    /// Timestamp of the last successful encrypted backup export, written by
    /// the `.fileExporter` completion below. No such timestamp existed
    /// before this screen's redesign — this is the only new persisted
    /// value this file introduces, and only because the export flow itself
    /// lives in this file (see the mockup's "Encrypted backup — Last: %@"
    /// row).
    @AppStorage(ProfileForm.lastBackupExportKey) private var lastBackupExportAt: Double = 0
    @State private var anthropicAPIKey = ""
    @AppStorage(AppLock.rememberMeKey) private var rememberMe = false
    @AppStorage(AppLock.biometricsEnabledKey) private var biometricsEnabled = true
    @EnvironmentObject private var lock: AppLock
    @ObservedObject private var premiumStore = PremiumStore.shared
    @ObservedObject private var settings = AppSettingsStore.shared
    @State private var showingPasscodeSetup = false
    @State private var showingPaywall = false
    @State private var showingProfileEditor = false
    @State private var refreshToggle = false

    /// Whether the OS has notification permission right now. There is no
    /// dedicated "retest reminders" toggle anywhere in the app (retest
    /// nudges piggyback on the general notification permission granted for
    /// medication/appointment reminders) — this mirrors that permission as
    /// a read-only status rather than inventing a new, disconnected setting.
    /// `nil` until the first `.task` read completes.
    @State private var notificationsAuthorized: Bool?
    /// Best-effort "<plan> · renews <date>" line for the Premium row,
    /// resolved directly from StoreKit's `Transaction.currentEntitlements`
    /// (read-only — `PremiumStore` itself only publishes `isPremium`, so
    /// this doesn't invent new published state on that type). `nil` while
    /// unresolved or for a non-premium user, in which case the row falls
    /// back to the plain "Active" badge alone.
    @State private var premiumStatusText: String?

    private var securityFooter: String {
        if !lock.canLock {
            let biometricsClause = AppLock.biometricsAvailable
                ? String(localized: " or enable \(AppLock.biometryLabel)")
                : ""
            return String(localized: "Set a passcode\(biometricsClause) to protect your data. Everything is stored only on this device.")
        }
        if rememberMe {
            return String(localized: "You'll stay signed in across launches until you tap Lock Now or turn this off. All data is stored only on this device.")
        }
        return String(localized: "Gemocode asks you to sign in whenever it returns from the background. All data is stored only on this device.")
    }
    @State private var confirmErase = false
    @State private var isImportingHealth = false
    @State private var healthImportMessage: String?
    @State private var exportDocument: BackupJSONDocument?
    @State private var showingExporter = false
    @State private var showingImporter = false
    @State private var pendingRestoreData: Data?
    @State private var confirmRestore = false
    @State private var dataMessage: String?
    @State private var showingExportPassphraseSheet = false
    @State private var showingRestorePassphraseSheet = false
    /// Set by `performExport` on success instead of `showingExporter`
    /// directly, and consumed by the export sheet's `onDismiss` — see the
    /// comment on that sheet for why the exporter can't be requested while
    /// the passphrase sheet is still covering it.
    @State private var pendingExport = false
    /// Set by `attemptRestore` on success instead of `dataMessage` directly,
    /// and consumed by the restore sheet's `onDismiss` for the same reason.
    @State private var pendingRestoreMessage: String?

    static let lastBackupExportKey = "backup.lastExportAt"

    var body: some View {
        Form {
            profileSummarySection
            privacySecuritySection
            appSection
            unitsSection
            premiumSection
            aiSummarySection
            dataManagementSection
            aboutSection
        }
        .onAppear {
            anthropicAPIKey = AISummaryService.apiKey ?? ""
        }
        .task {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                notificationsAuthorized = true
            default:
                notificationsAuthorized = false
            }
        }
        .task(id: premiumStore.isPremium) {
            await refreshPremiumStatusText()
        }
        .sheet(isPresented: $showingProfileEditor) {
            ProfileEditorSheet(profile: profile)
        }
        .sheet(isPresented: $showingPasscodeSetup) {
            PasscodeSetupSheet(lock: lock)
        }
        .sheet(isPresented: $showingPaywall) {
            PaywallView()
        }
        .sheet(isPresented: $showingExportPassphraseSheet, onDismiss: {
            // The .fileExporter below is attached to this same view, so it
            // must only be requested once this sheet has fully finished
            // dismissing — requesting it earlier (e.g. from `performExport`
            // while the sheet is still covering the screen) asks UIKit to
            // present the document picker over a sheet that's still being
            // torn down, which silently drops the presentation.
            if pendingExport {
                pendingExport = false
                showingExporter = true
            }
        }) {
            BackupExportPassphraseSheet(onExport: performExport)
        }
        .sheet(isPresented: $showingRestorePassphraseSheet, onDismiss: {
            // Same ordering issue as export: the success alert must wait
            // until the restore sheet is actually gone before it appears.
            if let message = pendingRestoreMessage {
                pendingRestoreMessage = nil
                dataMessage = message
            }
        }) {
            BackupRestorePassphraseSheet(attemptRestore: attemptRestore)
        }
        .confirmationDialog(
            "Erase all data from this device?",
            isPresented: $confirmErase,
            titleVisibility: .visible
        ) {
            Button("Erase Everything", role: .destructive) {
                SampleData.eraseAllData(in: modelContext)
                // Recreate a blank profile so this screen stays functional.
                modelContext.insert(HealthProfile())
            }
        } message: {
            Text("This cannot be undone.")
        }
        .fileExporter(
            isPresented: $showingExporter,
            document: exportDocument,
            contentType: .json,
            defaultFilename: "Gemocode Backup"
        ) { result in
            if case .success = result {
                dataMessage = String(localized: "Backup exported.")
                lastBackupExportAt = Date.now.timeIntervalSince1970
            }
        }
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: [.json]
        ) { result in
            guard case .success(let url) = result else { return }
            let accessed = url.startAccessingSecurityScopedResource()
            defer {
                if accessed { url.stopAccessingSecurityScopedResource() }
            }
            if let data = try? Data(contentsOf: url) {
                pendingRestoreData = data
                confirmRestore = true
            } else {
                dataMessage = String(localized: "Couldn't read the selected file.")
            }
        }
        .confirmationDialog(
            "Replace all current data with this backup?",
            isPresented: $confirmRestore,
            titleVisibility: .visible
        ) {
            Button("Restore Backup", role: .destructive) {
                showingRestorePassphraseSheet = true
            }
        } message: {
            Text("Everything currently in Gemocode will be replaced. This cannot be undone.")
        }
        .alert(
            "Data",
            isPresented: Binding(
                get: { dataMessage != nil },
                set: { if !$0 { dataMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(dataMessage ?? "")
        }
        .alert(
            "Apple Health",
            isPresented: Binding(
                get: { healthImportMessage != nil },
                set: { if !$0 { healthImportMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(healthImportMessage ?? "")
        }
    }

    // MARK: - Profile summary card

    private var initials: String? {
        guard !profile.name.isEmpty else { return nil }
        let letters = profile.name
            .split(separator: " ")
            .compactMap { $0.first }
            .prefix(2)
        return letters.isEmpty ? nil : String(letters).uppercased()
    }

    private var profileSummarySection: some View {
        Section {
            HStack(spacing: 12) {
                profileAvatar
                VStack(alignment: .leading, spacing: 2) {
                    Text(profile.name.isEmpty ? String(localized: "Your Name") : profile.name)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Editorial.ink(colorScheme))
                    if profile.sex != .unspecified {
                        Text("\(profile.sex.displayName) · sex-specific ranges applied")
                            .font(.system(size: 12, weight: .regular))
                            .foregroundStyle(Editorial.muted(colorScheme))
                    }
                }
                Spacer(minLength: 8)
                Button {
                    showingProfileEditor = true
                } label: {
                    Text("Edit")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(Editorial.accent(colorScheme))
                }
                .buttonStyle(.plain)
            }
            .padding(.vertical, 4)
            .accessibilityElement(children: .combine)
        }
        .listRowBackground(Editorial.insetCard(colorScheme))
        .listRowSeparatorTint(Editorial.hairline(colorScheme))
    }

    private var profileAvatar: some View {
        ZStack {
            Circle()
                .fill(Editorial.controlBorder(colorScheme))
                .frame(width: 40, height: 40)
            if let initials {
                Text(initials)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Editorial.muted(colorScheme))
            } else {
                Image(systemName: "person.fill")
                    .foregroundStyle(Editorial.muted(colorScheme))
            }
        }
        .accessibilityHidden(true)
    }

    // MARK: - Privacy & Security

    private var privacySecuritySection: some View {
        Section {
            Toggle("Face ID app lock", isOn: $appLockEnabled)
                .tint(Editorial.tagGood(colorScheme))
            if appLockEnabled {
                Button {
                    showingPasscodeSetup = true
                } label: {
                    Label(lock.hasPasscode ? "Change Passcode" : "Set Passcode", systemImage: "key.fill")
                }
                if lock.hasPasscode {
                    Button(role: .destructive) {
                        lock.removePasscode()
                        refreshToggle.toggle()
                    } label: {
                        Label("Remove Passcode", systemImage: "key.slash")
                    }
                }
                if AppLock.biometricsAvailable {
                    Toggle("Use \(AppLock.biometryLabel)", isOn: $biometricsEnabled)
                        .tint(Editorial.tagGood(colorScheme))
                }
                Toggle("Stay signed in (Remember me)", isOn: $rememberMe)
                    .tint(Editorial.tagGood(colorScheme))
                Button {
                    lock.signOut()
                } label: {
                    Label("Lock Now", systemImage: "lock.fill")
                }
            }
            Button {
                showingExportPassphraseSheet = true
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Encrypted backup")
                            .foregroundStyle(Editorial.ink(colorScheme))
                        if lastBackupExportAt > 0 {
                            Text("Last: \(Date(timeIntervalSince1970: lastBackupExportAt).formatted(date: .abbreviated, time: .shortened))")
                                .font(.footnote)
                                .foregroundStyle(Editorial.muted(colorScheme))
                        }
                    }
                    Spacer(minLength: 8)
                    Text("Export ↗")
                        .font(.footnote)
                        .foregroundStyle(Editorial.accent(colorScheme))
                }
            }
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Data")
                        .foregroundStyle(Editorial.ink(colorScheme))
                    Text("100% on-device — no account, no cloud")
                        .font(.footnote)
                        .foregroundStyle(Editorial.muted(colorScheme))
                }
                Spacer(minLength: 8)
                EditorialTag("Local", kind: .good)
            }
            .accessibilityElement(children: .combine)
        } header: {
            MicroLabel("Privacy & Security")
        } footer: {
            Text(securityFooter)
        }
        .listRowBackground(GlassRowBackground())
        .listRowSeparatorTint(Editorial.hairline(colorScheme))
    }

    // MARK: - App

    private var appSection: some View {
        Section {
            HStack {
                Text("Language")
                Spacer()
                languageChips
            }
            HStack {
                Text("Theme")
                Spacer()
                themeChips
            }
            Toggle(isOn: Binding(get: { notificationsAuthorized ?? false }, set: { _ in })) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Retest reminders")
                    Text("2 weeks before due")
                        .font(.footnote)
                        .foregroundStyle(Editorial.muted(colorScheme))
                }
            }
            .tint(Editorial.tagGood(colorScheme))
            .disabled(true)
            Toggle(isOn: $automaticSyncEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Apple Health import")
                    Text("Vitals & labs, read-only")
                        .font(.footnote)
                        .foregroundStyle(Editorial.muted(colorScheme))
                }
            }
            .tint(Editorial.tagGood(colorScheme))
            .disabled(!HealthKitService.isAvailable)
            .onChange(of: automaticSyncEnabled) { _, isEnabled in
                Task {
                    if isEnabled {
                        do {
                            try await HealthKitService.requestAuthorization()
                            await HealthKitService.startAutomaticSync(container: modelContext.container)
                        } catch {
                            automaticSyncEnabled = false
                        }
                    } else {
                        HealthKitService.stopAutomaticSync()
                    }
                }
            }
            Button {
                importFromHealth()
            } label: {
                if isImportingHealth {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Importing from Apple Health…")
                    }
                } else {
                    Label("Import from Apple Health", systemImage: "heart.fill")
                }
            }
            .disabled(!HealthKitService.isAvailable || isImportingHealth)
            Toggle("Save new vitals to Apple Health", isOn: $healthWriteBackEnabled)
                .tint(Editorial.tagGood(colorScheme))
                .disabled(!HealthKitService.isAvailable)
                .onChange(of: healthWriteBackEnabled) { _, isEnabled in
                    guard isEnabled else { return }
                    Task {
                        try? await HealthKitService.requestWriteAuthorization()
                    }
                }
            Text("Checks for new readings from your Apple Watch and other devices about once an hour, on-device.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        } header: {
            MicroLabel("App")
        } footer: {
            Text("Language changes apply immediately to most screens; restart the app to apply everywhere. Retest reminders mirror your notification permission — enable notifications in Settings to receive them.")
        }
        .listRowBackground(GlassRowBackground())
        .listRowSeparatorTint(Editorial.hairline(colorScheme))
    }

    private var languageChips: some View {
        HStack(spacing: 6) {
            languageChip(.english, label: "EN")
            languageChip(.russian, label: "РУ")
        }
        .contextMenu {
            Button {
                settings.languageChoice = .system
            } label: {
                Label("System", systemImage: "gear")
            }
        }
    }

    private func languageChip(_ choice: LanguageChoice, label: String) -> some View {
        let isSelected = settings.languageChoice == choice
        return Button {
            settings.languageChoice = choice
        } label: {
            Text(verbatim: label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(isSelected ? Editorial.canvas(colorScheme) : Editorial.muted(colorScheme))
                .padding(.horizontal, 13)
                .padding(.vertical, 6)
                .background(Capsule().fill(isSelected ? Editorial.ink(colorScheme) : Color.clear))
                .overlay(Capsule().strokeBorder(isSelected ? Color.clear : Editorial.controlBorder(colorScheme), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(choice.displayName))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private var themeChips: some View {
        HStack(spacing: 6) {
            themeChip(.light)
            themeChip(.dark)
        }
        .contextMenu {
            Button {
                settings.themeChoice = .system
            } label: {
                Label("System", systemImage: "gear")
            }
        }
    }

    private func themeChip(_ choice: ThemeChoice) -> some View {
        let isSelected = settings.themeChoice == choice
        return Button {
            settings.themeChoice = choice
        } label: {
            Text(choice.displayName)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(isSelected ? Editorial.canvas(colorScheme) : Editorial.muted(colorScheme))
                .padding(.horizontal, 13)
                .padding(.vertical, 6)
                .background(Capsule().fill(isSelected ? Editorial.ink(colorScheme) : Color.clear))
                .overlay(Capsule().strokeBorder(isSelected ? Color.clear : Editorial.controlBorder(colorScheme), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    // MARK: - Units

    private var unitsSection: some View {
        Section {
            Picker("Weight", selection: $weightUnitRaw) {
                ForEach(WeightUnit.allCases) { unit in
                    Text(unit.label).tag(unit.rawValue)
                }
            }
            Picker("Temperature", selection: $temperatureUnitRaw) {
                ForEach(TemperatureUnit.allCases) { unit in
                    Text(unit.label).tag(unit.rawValue)
                }
            }
            Picker("Blood glucose", selection: $glucoseUnitRaw) {
                ForEach(GlucoseUnit.allCases) { unit in
                    Text(unit.label).tag(unit.rawValue)
                }
            }
        } header: {
            MicroLabel("Units")
        } footer: {
            Text("Values are stored in metric and converted for display and entry.")
        }
        .listRowBackground(GlassRowBackground())
        .listRowSeparatorTint(Editorial.hairline(colorScheme))
    }

    // MARK: - Premium

    private var premiumSection: some View {
        Section {
            if premiumStore.isPremium {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Gemocode Premium")
                            .foregroundStyle(Editorial.ink(colorScheme))
                        Text(premiumStatusText ?? String(localized: "Active"))
                            .font(.footnote)
                            .foregroundStyle(Editorial.muted(colorScheme))
                    }
                    Spacer(minLength: 8)
                    activeBadge
                }
                .accessibilityElement(children: .combine)
            } else {
                Button {
                    showingPaywall = true
                } label: {
                    HStack {
                        Label("Unlock Premium", systemImage: "crown.fill")
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(Editorial.muted(colorScheme))
                    }
                }
                .foregroundStyle(Editorial.ink(colorScheme))
                HStack {
                    Label("Free AI reports used", systemImage: "sparkles")
                    Spacer()
                    Text("\(AIReportQuota.usedCount(defaults: .standard)) of \(AIReportQuota.freeLifetimeLimit)")
                        .foregroundStyle(Editorial.muted(colorScheme))
                        .monospacedDigit()
                }
                .accessibilityElement(children: .combine)
            }
        } header: {
            MicroLabel("Premium")
        } footer: {
            Text("Unlimited AI health reports and future AI features. All core tracking stays free forever.")
        }
        .listRowBackground(GlassRowBackground())
        .listRowSeparatorTint(Editorial.hairline(colorScheme))
    }

    private var activeBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: "sparkle")
                .font(.system(size: 8, weight: .semibold))
            Text("Active")
                .font(.system(size: 10, weight: .medium))
                .kerning(1.0)
                .textCase(.uppercase)
        }
        .foregroundStyle(Editorial.accent(colorScheme))
        .padding(.vertical, 4)
        .padding(.horizontal, 10)
        .overlay(Capsule().strokeBorder(Editorial.accent(colorScheme), lineWidth: 1))
        .accessibilityHidden(true)
    }

    /// Resolves the active plan name + renewal/expiration date directly
    /// from StoreKit, since `PremiumStore` only publishes `isPremium`.
    /// Read-only — does not finish or alter any transaction.
    private func refreshPremiumStatusText() async {
        guard premiumStore.isPremium else {
            premiumStatusText = nil
            return
        }
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result,
                  PremiumStore.productIDs.contains(transaction.productID),
                  transaction.revocationDate == nil else { continue }
            let plan = Self.planDisplayName(for: transaction.productID)
            if let expirationDate = transaction.expirationDate {
                premiumStatusText = String(localized: "\(plan) · renews \(expirationDate.formatted(date: .abbreviated, time: .omitted))")
            } else {
                premiumStatusText = plan
            }
            return
        }
        premiumStatusText = nil
    }

    private static func planDisplayName(for productID: String) -> String {
        switch productID {
        case PremiumStore.yearlyProductID: return String(localized: "Yearly")
        case PremiumStore.monthlyProductID: return String(localized: "Monthly")
        case PremiumStore.lifetimeProductID: return String(localized: "Lifetime")
        default: return String(localized: "Premium")
        }
    }

    // MARK: - AI Summary (BYOK)

    private var aiSummarySection: some View {
        Section {
            SecureField("Anthropic API key", text: $anthropicAPIKey)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .onChange(of: anthropicAPIKey) { _, newValue in
                    AISummaryService.apiKey = newValue
                }
        } header: {
            MicroLabel("AI Summary (Optional)")
        } footer: {
            Text("Add your own Anthropic API key to enable plain-language AI summaries of your Health Review. When you tap Generate, only the review text is sent to Anthropic — never your documents or database. The key is stored in the device Keychain. Leave empty to keep Gemocode fully offline.")
        }
        .listRowBackground(GlassRowBackground())
        .listRowSeparatorTint(Editorial.hairline(colorScheme))
    }

    // MARK: - Data management

    private var dataManagementSection: some View {
        Section {
            Button {
                showingImporter = true
            } label: {
                Label("Restore from Backup", systemImage: "square.and.arrow.down.on.square")
            }
            Button {
                SampleData.load(into: modelContext)
            } label: {
                Label("Load Sample Data", systemImage: "sparkles")
            }
            Button(role: .destructive) {
                confirmErase = true
            } label: {
                Label("Erase All Data", systemImage: "trash")
            }
        } header: {
            MicroLabel("Data Management")
        } footer: {
            Text("Health import copies your recent readings from Apple Health. When \"Save new vitals to Apple Health\" is on, vitals you log in Gemocode are also written to the Health app. Backups are a single passphrase-encrypted JSON file containing everything — including attachments — that you can store anywhere and restore later (reminders need re-enabling after a restore). Erasing removes all data from this device.")
        }
        .listRowBackground(GlassRowBackground())
        .listRowSeparatorTint(Editorial.hairline(colorScheme))
    }

    // MARK: - About

    private var aboutSection: some View {
        Section {
            NavigationLink {
                PrivacyExplainerView()
            } label: {
                Label("Privacy & Your Data", systemImage: "lock.shield")
            }
            LabeledContent("Version", value: "1.0")
            Text(HealthReview.disclaimer)
                .font(.footnote)
                .foregroundStyle(Editorial.muted(colorScheme))
        } header: {
            MicroLabel("About")
        }
        .listRowBackground(GlassRowBackground())
        .listRowSeparatorTint(Editorial.hairline(colorScheme))
    }

    /// Called by `BackupExportPassphraseSheet` once a valid passphrase has
    /// been entered and confirmed. `BackupService.export` hops off the main
    /// actor internally for the PBKDF2/AES-GCM work, so this only blocks
    /// the sheet (via its own `isExporting` state), never the whole UI.
    ///
    /// Deliberately does NOT set `showingExporter` itself — the sheet is
    /// still presented while this `await` is in flight (the sheet's own
    /// Task calls `dismiss()` right after this returns), so flipping
    /// `showingExporter` here would ask SwiftUI to present the
    /// `.fileExporter` while the passphrase sheet is still on screen. The
    /// `pendingExport` flag defers that to the sheet's `onDismiss` instead.
    private func performExport(passphrase: String) async {
        do {
            exportDocument = BackupJSONDocument(data: try await BackupService.export(from: modelContext, passphrase: passphrase))
            pendingExport = true
        } catch {
            dataMessage = String(localized: "Export failed: \(error.localizedDescription)")
        }
    }

    /// Called by `BackupRestorePassphraseSheet` for each attempt. Returns an
    /// error message to display inline (and keep the sheet open) on failure,
    /// or `nil` on success (the sheet dismisses itself).
    ///
    /// On success this stages the confirmation into `pendingRestoreMessage`
    /// rather than `dataMessage` directly, for the same reason
    /// `performExport` stages `pendingExport`: the restore sheet is still on
    /// screen when this returns, and presenting the `.alert` immediately
    /// would race its dismissal. The sheet's `onDismiss` promotes the
    /// pending message once it's actually gone.
    private func attemptRestore(passphrase: String) async -> String? {
        guard let data = pendingRestoreData else {
            return String(localized: "No backup file selected.")
        }
        do {
            let count = try await BackupService.restore(from: data, passphrase: passphrase, into: modelContext)
            pendingRestoreData = nil
            Haptics.success()
            pendingRestoreMessage = count == 1
                ? String(localized: "Backup restored — \(count) record. Medication and appointment reminders need to be re-enabled.")
                : String(localized: "Backup restored — \(count) records. Medication and appointment reminders need to be re-enabled.")
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    private func importFromHealth() {
        isImportingHealth = true
        Task {
            do {
                try await HealthKitService.requestAuthorization()
                let since = lastHealthImportAt > 0
                    ? Date(timeIntervalSince1970: lastHealthImportAt)
                    : Calendar.current.date(byAdding: .year, value: -1, to: .now) ?? .now
                let count = try await HealthKitService.importVitals(since: since, into: modelContext)
                lastHealthImportAt = Date.now.timeIntervalSince1970
                if count == 0 {
                    healthImportMessage = String(localized: "No new readings found in Apple Health.")
                } else if count == 1 {
                    healthImportMessage = String(localized: "Imported \(count) reading from Apple Health.")
                } else {
                    healthImportMessage = String(localized: "Imported \(count) readings from Apple Health.")
                }
            } catch {
                healthImportMessage = String(localized: "Import failed: \(error.localizedDescription)")
            }
            isImportingHealth = false
        }
    }
}

// MARK: - Profile editor sheet

/// The "existing editor" reached via the summary card's "Edit" link:
/// exactly the identity/medical-background/emergency fields that used to
/// sit inline at the top of this screen, now presented as a focused sheet
/// so the redesigned Settings list can stay a lean, grouped ledger. No
/// field, binding, or validation logic changed — only where it's shown.
private struct ProfileEditorSheet: View {
    @Bindable var profile: HealthProfile
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    private static let bloodTypes = ["", "A+", "A−", "B+", "B−", "AB+", "AB−", "O+", "O−"]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $profile.name)
                    if profile.dateOfBirth != nil {
                        DatePicker(
                            "Date of birth",
                            selection: Binding(
                                get: { profile.dateOfBirth ?? Date(timeIntervalSince1970: 631_152_000) },
                                set: { profile.dateOfBirth = $0 }
                            ),
                            in: ...Date.now,
                            displayedComponents: .date
                        )
                        if let age = profile.age {
                            LabeledContent("Age", value: String(localized: "\(age) years"))
                        }
                    } else {
                        Button("Add Date of Birth") {
                            profile.dateOfBirth = Date(timeIntervalSince1970: 631_152_000)
                        }
                    }
                    Picker("Biological sex", selection: $profile.sex) {
                        ForEach(BiologicalSex.allCases) { sex in
                            Text(sex.displayName).tag(sex)
                        }
                    }
                    TextField("Height (cm)", text: heightBinding)
                        .keyboardType(.decimalPad)
                    Picker("Blood type", selection: $profile.bloodType) {
                        ForEach(Self.bloodTypes, id: \.self) { type in
                            Text(type.isEmpty ? String(localized: "Unknown") : type).tag(type)
                        }
                    }
                } header: {
                    MicroLabel("About You")
                } footer: {
                    Text("Biological sex is used to pick the correct reference ranges for lab tests. Height enables BMI calculation.")
                }
                .listRowBackground(GlassRowBackground())
                .listRowSeparatorTint(Editorial.hairline(colorScheme))

                Section {
                    TextField("Allergies", text: $profile.allergies, axis: .vertical)
                        .lineLimit(1...3)
                    TextField("Existing conditions", text: $profile.conditions, axis: .vertical)
                        .lineLimit(1...3)
                } header: {
                    MicroLabel("Medical Background")
                }
                .listRowBackground(GlassRowBackground())
                .listRowSeparatorTint(Editorial.hairline(colorScheme))

                Section {
                    TextField("Contact name", text: $profile.emergencyContactName)
                    TextField("Relationship", text: $profile.emergencyContactRelation)
                    TextField("Phone number", text: $profile.emergencyContactPhone)
                        .keyboardType(.phonePad)
                    Picker("Organ donor", selection: $profile.organDonorStatus) {
                        Text("Unknown").tag("")
                        Text("Yes").tag("yes")
                        Text("No").tag("no")
                    }
                } header: {
                    MicroLabel("Emergency")
                } footer: {
                    Text("Shown on your Medical ID card for quick reference in an emergency.")
                }
                .listRowBackground(GlassRowBackground())
                .listRowSeparatorTint(Editorial.hairline(colorScheme))
            }
            .ambientScreen()
            .navigationTitle("Edit Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var heightBinding: Binding<String> {
        Binding(
            get: {
                guard let heightCm = profile.heightCm else { return "" }
                return heightCm.compactFormatted
            },
            set: {
                profile.heightCm = Double($0.replacingOccurrences(of: ",", with: "."))
            }
        )
    }
}

// MARK: - Backup passphrase sheets

/// Requests and confirms a new passphrase before exporting a backup.
private struct BackupExportPassphraseSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    let onExport: (String) async -> Void

    @State private var passphrase = ""
    @State private var confirm = ""
    @State private var error: String?
    /// True while `onExport` (PBKDF2 + AES-GCM over the whole store) is
    /// running. Gates the fields/buttons so the sheet can't be double-tapped
    /// mid-export the way the old synchronous call site could be.
    @State private var isExporting = false
    @FocusState private var firstFieldFocused: Bool

    private static let minimumLength = 8

    private var isValid: Bool {
        passphrase.count >= Self.minimumLength
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("Passphrase", text: $passphrase)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($firstFieldFocused)
                        .disabled(isExporting)
                    SecureField("Confirm passphrase", text: $confirm)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .disabled(isExporting)
                    if isExporting {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("Encrypting your backup…")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .combine)
                    }
                } footer: {
                    if let error {
                        Text(error).foregroundStyle(Editorial.tagBad(colorScheme))
                    } else {
                        Text("Choose a passphrase of at least \(Self.minimumLength) characters. You'll need it to restore this backup — Gemocode can't recover it if you forget it.")
                    }
                }
                .listRowBackground(GlassRowBackground())
                .listRowSeparatorTint(Editorial.hairline(colorScheme))
            }
            .ambientScreen()
            .navigationTitle("Encrypt Backup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isExporting)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Export") { attemptExport() }
                        .disabled(!isValid || isExporting)
                }
            }
            .onAppear { firstFieldFocused = true }
        }
    }

    private func attemptExport() {
        guard !isExporting else { return }
        guard isValid else {
            error = String(localized: "Passphrase must be at least \(Self.minimumLength) characters.")
            return
        }
        guard passphrase == confirm else {
            error = String(localized: "Passphrases don't match.")
            confirm = ""
            return
        }
        error = nil
        isExporting = true
        Task {
            await onExport(passphrase)
            isExporting = false
            dismiss()
        }
    }
}

/// Requests the passphrase for a restore, showing an inline error (and
/// staying open) on a wrong passphrase so the user can retry.
private struct BackupRestorePassphraseSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    /// Returns an error message on failure, or `nil` on success.
    let attemptRestore: (String) async -> String?

    @State private var passphrase = ""
    @State private var error: String?
    /// True while `attemptRestore` (AES-GCM open + PBKDF2 + the delete/apply
    /// pass over the store) is running. Gates the field/buttons so the sheet
    /// can't be double-tapped mid-restore.
    @State private var isRestoring = false
    @FocusState private var fieldFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("Passphrase", text: $passphrase)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($fieldFocused)
                        .disabled(isRestoring)
                        .onSubmit(submit)
                    if isRestoring {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("Restoring your backup…")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .combine)
                    }
                } footer: {
                    if let error {
                        Text(error).foregroundStyle(Editorial.tagBad(colorScheme))
                    } else {
                        Text("Enter the passphrase you used when this backup was exported. Older, unencrypted backups don't need one — leave this blank and tap Restore.")
                    }
                }
                .listRowBackground(GlassRowBackground())
                .listRowSeparatorTint(Editorial.hairline(colorScheme))
            }
            .ambientScreen()
            .navigationTitle("Restore Backup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isRestoring)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Restore") { submit() }
                        .disabled(isRestoring)
                }
            }
            .onAppear { fieldFocused = true }
        }
    }

    private func submit() {
        guard !isRestoring else { return }
        isRestoring = true
        Task {
            let message = await attemptRestore(passphrase)
            isRestoring = false
            if let message {
                error = message
                passphrase = ""
            } else {
                dismiss()
            }
        }
    }
}
