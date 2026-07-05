import SwiftUI
import SwiftData

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
    @State private var confirmErase = false

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
                Text("Sample data fills the app with a realistic demo history so you can explore every feature. Erasing removes all reports, vitals, medications, and your profile from this device.")
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
            }
        } message: {
            Text("This cannot be undone.")
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
