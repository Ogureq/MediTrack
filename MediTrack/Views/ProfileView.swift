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
    @State private var confirmErase = false
    @State private var isImportingHealth = false
    @State private var healthImportMessage: String?
    @State private var exportDocument: BackupJSONDocument?
    @State private var showingExporter = false
    @State private var showingImporter = false
    @State private var pendingRestoreData: Data?
    @State private var confirmRestore = false
    @State private var dataMessage: String?

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
                Toggle("Require Face ID / Passcode", isOn: $appLockEnabled)
                    .disabled(!BiometricLock.isAvailable)
            } header: {
                Text("Privacy")
            } footer: {
                if BiometricLock.isAvailable {
                    Text("When enabled, MediTrack locks whenever the app goes to the background. All data is stored only on this device.")
                } else {
                    Text("Set up Face ID, Touch ID, or a passcode on this device to enable the app lock.")
                }
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
                Button {
                    exportBackup()
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
                Text("Health import copies your recent readings from Apple Health. Backups are a single JSON file containing everything — including attachments — that you can store anywhere and restore later (reminders need re-enabling after a restore). Erasing removes all data from this device.")
            }
            .listRowBackground(GlassRowBackground())
            .listRowSeparator(.hidden)

            Section {
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
                restoreBackup()
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

    private func exportBackup() {
        do {
            exportDocument = BackupJSONDocument(data: try BackupService.export(from: modelContext))
            showingExporter = true
        } catch {
            dataMessage = "Export failed: \(error.localizedDescription)"
        }
    }

    private func restoreBackup() {
        guard let data = pendingRestoreData else { return }
        pendingRestoreData = nil
        do {
            let count = try BackupService.restore(from: data, into: modelContext)
            Haptics.success()
            dataMessage = "Backup restored — \(count) record\(count == 1 ? "" : "s"). Medication and appointment reminders need to be re-enabled."
        } catch {
            dataMessage = error.localizedDescription
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
