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
    @AppStorage(Units.weightKey) private var weightUnitRaw = WeightUnit.kilograms.rawValue
    @AppStorage(Units.temperatureKey) private var temperatureUnitRaw = TemperatureUnit.celsius.rawValue
    @AppStorage(Units.glucoseKey) private var glucoseUnitRaw = GlucoseUnit.mgdL.rawValue
    @State private var anthropicAPIKey = ""
    @AppStorage(AppLock.rememberMeKey) private var rememberMe = false
    @AppStorage(AppLock.biometricsEnabledKey) private var biometricsEnabled = true
    @EnvironmentObject private var lock: AppLock
    @State private var showingPasscodeSetup = false
    @State private var refreshToggle = false

    private var securityFooter: String {
        if !lock.canLock {
            return "Set a passcode\(AppLock.biometricsAvailable ? " or enable \(AppLock.biometryLabel)" : "") to protect your data. Everything is stored only on this device."
        }
        if rememberMe {
            return "You'll stay signed in across launches until you tap Lock Now or turn this off. All data is stored only on this device."
        }
        return "MediTrack asks you to sign in whenever it returns from the background. All data is stored only on this device."
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
                SecureField("Anthropic API key", text: $anthropicAPIKey)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onChange(of: anthropicAPIKey) { _, newValue in
                        AISummaryService.apiKey = newValue
                    }
            } header: {
                Text("AI Summary (Optional)")
            } footer: {
                Text("Add your own Anthropic API key to enable plain-language AI summaries of your Health Review. When you tap Generate, only the review text is sent to Anthropic — never your documents or database. The key is stored in the device Keychain. Leave empty to keep MediTrack fully offline.")
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
                Text("Health import copies your recent readings from Apple Health. When \"Save new vitals to Apple Health\" is on, vitals you log in MediTrack are also written to the Health app. Backups are a single passphrase-encrypted JSON file containing everything — including attachments — that you can store anywhere and restore later (reminders need re-enabling after a restore). Erasing removes all data from this device.")
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
        .sheet(isPresented: $showingExportPassphraseSheet) {
            BackupExportPassphraseSheet(onExport: performExport)
        }
        .sheet(isPresented: $showingRestorePassphraseSheet) {
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
            defaultFilename: "MediTrack Backup"
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
            Text("Everything currently in MediTrack will be replaced. This cannot be undone.")
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
    /// been entered and confirmed.
    private func performExport(passphrase: String) {
        do {
            exportDocument = BackupJSONDocument(data: try BackupService.export(from: modelContext, passphrase: passphrase))
            showingExporter = true
        } catch {
            dataMessage = "Export failed: \(error.localizedDescription)"
        }
    }

    /// Called by `BackupRestorePassphraseSheet` for each attempt. Returns an
    /// error message to display inline (and keep the sheet open) on failure,
    /// or `nil` on success (the sheet dismisses itself).
    private func attemptRestore(passphrase: String) -> String? {
        guard let data = pendingRestoreData else {
            return "No backup file selected."
        }
        do {
            let count = try BackupService.restore(from: data, passphrase: passphrase, into: modelContext)
            pendingRestoreData = nil
            Haptics.success()
            dataMessage = "Backup restored — \(count) record\(count == 1 ? "" : "s"). Medication and appointment reminders need to be re-enabled."
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
    let onExport: (String) -> Void

    @State private var passphrase = ""
    @State private var confirm = ""
    @State private var error: String?
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
                    SecureField("Confirm passphrase", text: $confirm)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } footer: {
                    if let error {
                        Text(error).foregroundStyle(.red)
                    } else {
                        Text("Choose a passphrase of at least \(Self.minimumLength) characters. You'll need it to restore this backup — MediTrack can't recover it if you forget it.")
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
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Export") { attemptExport() }
                        .disabled(!isValid)
                }
            }
            .onAppear { firstFieldFocused = true }
        }
    }

    private func attemptExport() {
        guard isValid else {
            error = "Passphrase must be at least \(Self.minimumLength) characters."
            return
        }
        guard passphrase == confirm else {
            error = "Passphrases don't match."
            confirm = ""
            return
        }
        onExport(passphrase)
        dismiss()
    }
}

/// Requests the passphrase for a restore, showing an inline error (and
/// staying open) on a wrong passphrase so the user can retry.
private struct BackupRestorePassphraseSheet: View {
    @Environment(\.dismiss) private var dismiss
    /// Returns an error message on failure, or `nil` on success.
    let attemptRestore: (String) -> String?

    @State private var passphrase = ""
    @State private var error: String?
    @FocusState private var fieldFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("Passphrase", text: $passphrase)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($fieldFocused)
                        .onSubmit(submit)
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
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Restore") { submit() }
                }
            }
            .onAppear { fieldFocused = true }
        }
    }

    private func submit() {
        if let message = attemptRestore(passphrase) {
            error = message
            passphrase = ""
        } else {
            dismiss()
        }
    }
}
