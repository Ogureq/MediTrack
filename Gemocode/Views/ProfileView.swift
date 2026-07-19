import SwiftUI
import SwiftData
import UniformTypeIdentifiers

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
    @AppStorage("appLockEnabled") private var appLockEnabled = false
    @AppStorage("lastHealthImportAt") private var lastHealthImportAt: Double = 0
    @AppStorage("health.writeBackEnabled") private var healthWriteBackEnabled = false
    @AppStorage(HealthKitService.automaticSyncKey) private var automaticSyncEnabled = false
    @AppStorage(Units.weightKey) private var weightUnitRaw = WeightUnit.kilograms.rawValue
    @AppStorage(Units.temperatureKey) private var temperatureUnitRaw = TemperatureUnit.celsius.rawValue
    @AppStorage(Units.glucoseKey) private var glucoseUnitRaw = GlucoseUnit.mgdL.rawValue
    @State private var anthropicAPIKey = ""
    @AppStorage(AppLock.rememberMeKey) private var rememberMe = false
    @AppStorage(AppLock.biometricsEnabledKey) private var biometricsEnabled = true
    @EnvironmentObject private var lock: AppLock
    @ObservedObject private var premiumStore = PremiumStore.shared
    @ObservedObject private var settings = AppSettingsStore.shared
    @State private var showingPasscodeSetup = false
    @State private var showingPaywall = false
    @State private var refreshToggle = false

    private var securityFooter: String {
        if !lock.canLock {
            return "Set a passcode\(AppLock.biometricsAvailable ? " or enable \(AppLock.biometryLabel)" : "") to protect your data. Everything is stored only on this device."
        }
        if rememberMe {
            return "You'll stay signed in across launches until you tap Lock Now or turn this off. All data is stored only on this device."
        }
        return "Gemocode asks you to sign in whenever it returns from the background. All data is stored only on this device."
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

    private static let bloodTypes = ["", "A+", "A−", "B+", "B−", "AB+", "AB−", "O+", "O−"]

    var body: some View {
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
                        LabeledContent("Age", value: "\(age) years")
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
                        Text(type.isEmpty ? "Unknown" : type).tag(type)
                    }
                }
            } header: {
                Text("About You")
            } footer: {
                Text("Biological sex is used to pick the correct reference ranges for lab tests. Height enables BMI calculation.")
            }
            .listRowBackground(GlassRowBackground())
            .listRowSeparator(.hidden)

            Section("Medical Background") {
                TextField("Allergies", text: $profile.allergies, axis: .vertical)
                    .lineLimit(1...3)
                TextField("Existing conditions", text: $profile.conditions, axis: .vertical)
                    .lineLimit(1...3)
            }
            .listRowBackground(GlassRowBackground())
            .listRowSeparator(.hidden)

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
                Text("Emergency")
            } footer: {
                Text("Shown on your Medical ID card for quick reference in an emergency.")
            }
            .listRowBackground(GlassRowBackground())
            .listRowSeparator(.hidden)

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
                Text("Units")
            } footer: {
                Text("Values are stored in metric and converted for display and entry.")
            }
            .listRowBackground(GlassRowBackground())
            .listRowSeparator(.hidden)

            Section {
                Picker("Theme", selection: $settings.themeChoice) {
                    ForEach(ThemeChoice.allCases, id: \.self) { choice in
                        Text(choice.displayName).tag(choice)
                    }
                }
                Picker("Language", selection: $settings.languageChoice) {
                    ForEach(LanguageChoice.allCases, id: \.self) { choice in
                        Text(choice.displayName).tag(choice)
                    }
                }
            } header: {
                Text("Appearance & Language")
            } footer: {
                Text("Language changes apply immediately to most screens; restart the app to apply everywhere.")
            }
            .listRowBackground(GlassRowBackground())
            .listRowSeparator(.hidden)

            Section {
                SecureField("Anthropic API key", text: $anthropicAPIKey)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onChange(of: anthropicAPIKey) { _, newValue in
                        AISummaryService.apiKey = newValue
                    }
            } header: {
                Text("AI Summary (Optional)")
            } footer: {
                Text("Add your own Anthropic API key to enable plain-language AI summaries of your Health Review. When you tap Generate, only the review text is sent to Anthropic — never your documents or database. The key is stored in the device Keychain. Leave empty to keep Gemocode fully offline.")
            }
            .listRowBackground(GlassRowBackground())
            .listRowSeparator(.hidden)

            Section {
                Button {
                    showingPaywall = true
                } label: {
                    HStack {
                        Label("Gemocode Premium", systemImage: "crown.fill")
                        Spacer()
                        if premiumStore.isPremium {
                            StatusPill(text: "Active", color: .green)
                        } else {
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .foregroundStyle(.primary)
                if !premiumStore.isPremium {
                    HStack {
                        Label("Free AI reports used", systemImage: "sparkles")
                        Spacer()
                        Text("\(AIReportQuota.usedCount(defaults: .standard)) of \(AIReportQuota.freeLifetimeLimit)")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    .accessibilityElement(children: .combine)
                }
            } footer: {
                Text("Unlimited AI health reports and future AI features. All core tracking stays free forever.")
            }
            .listRowBackground(GlassRowBackground())
            .listRowSeparator(.hidden)

            Section {
                Toggle("Require login", isOn: $appLockEnabled)
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
                    }
                    Toggle("Stay signed in (Remember me)", isOn: $rememberMe)
                    Button {
                        lock.signOut()
                    } label: {
                        Label("Lock Now", systemImage: "lock.fill")
                    }
                }
            } header: {
                Text("Login & Security")
            } footer: {
                Text(securityFooter)
            }
            .listRowBackground(GlassRowBackground())
            .listRowSeparator(.hidden)

            Section {
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
                    .disabled(!HealthKitService.isAvailable)
                    .onChange(of: healthWriteBackEnabled) { _, isEnabled in
                        guard isEnabled else { return }
                        Task {
                            try? await HealthKitService.requestWriteAuthorization()
                        }
                    }
                Toggle("Automatic Sync from Apple Health", isOn: $automaticSyncEnabled)
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
                Text("Checks for new readings from your Apple Watch and other devices about once an hour, on-device.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button {
                    showingExportPassphraseSheet = true
                } label: {
                    Label("Export Backup", systemImage: "square.and.arrow.up.on.square")
                }
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
                Text("Data")
            } footer: {
                Text("Health import copies your recent readings from Apple Health. When \"Save new vitals to Apple Health\" is on, vitals you log in Gemocode are also written to the Health app. Backups are a single passphrase-encrypted JSON file containing everything — including attachments — that you can store anywhere and restore later (reminders need re-enabling after a restore). Erasing removes all data from this device.")
            }
            .listRowBackground(GlassRowBackground())
            .listRowSeparator(.hidden)

            Section {
                NavigationLink {
                    PrivacyExplainerView()
                } label: {
                    Label("Privacy & Your Data", systemImage: "lock.shield")
                }
                LabeledContent("Version", value: "1.0")
                Text(HealthReview.disclaimer)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } header: {
                Text("About")
            }
            .listRowBackground(GlassRowBackground())
            .listRowSeparator(.hidden)
        }
        .onAppear {
            anthropicAPIKey = AISummaryService.apiKey ?? ""
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
                dataMessage = "Backup exported."
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
                dataMessage = "Couldn't read the selected file."
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
            dataMessage = "Export failed: \(error.localizedDescription)"
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
            return "No backup file selected."
        }
        do {
            let count = try await BackupService.restore(from: data, passphrase: passphrase, into: modelContext)
            pendingRestoreData = nil
            Haptics.success()
            pendingRestoreMessage = "Backup restored — \(count) record\(count == 1 ? "" : "s"). Medication and appointment reminders need to be re-enabled."
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
                healthImportMessage = count == 0
                    ? "No new readings found in Apple Health."
                    : "Imported \(count) reading\(count == 1 ? "" : "s") from Apple Health."
            } catch {
                healthImportMessage = "Import failed: \(error.localizedDescription)"
            }
            isImportingHealth = false
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
                        Text(error).foregroundStyle(.red)
                    } else {
                        Text("Choose a passphrase of at least \(Self.minimumLength) characters. You'll need it to restore this backup — Gemocode can't recover it if you forget it.")
                    }
                }
                .listRowBackground(GlassRowBackground())
                .listRowSeparator(.hidden)
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
            error = "Passphrase must be at least \(Self.minimumLength) characters."
            return
        }
        guard passphrase == confirm else {
            error = "Passphrases don't match."
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
                        Text(error).foregroundStyle(.red)
                    } else {
                        Text("Enter the passphrase you used when this backup was exported. Older, unencrypted backups don't need one — leave this blank and tap Restore.")
                    }
                }
                .listRowBackground(GlassRowBackground())
                .listRowSeparator(.hidden)
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
