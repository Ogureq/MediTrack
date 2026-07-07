import SwiftUI

/// The lock / login panel shown over the app when the lock is engaged.
/// Offers passcode entry, Face ID, and a "Remember me" option.
struct LoginView: View {
    @ObservedObject var lock: AppLock

    @AppStorage("app.rememberMePreference") private var rememberPreference = false
    @State private var rememberMe = false
    @State private var passcode = ""
    @State private var shake = false
    @FocusState private var passcodeFocused: Bool

    private var canSubmit: Bool { passcode.count >= 4 }

    var body: some View {
        ZStack {
            AmbientBackground()
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                VStack(spacing: 10) {
                    Image(systemName: "cross.case.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(Glass.accentGradient)
                    Text("Welcome Back")
                        .font(.title2.bold())
                    Text("Sign in to view your medical data.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                if lock.hasPasscode {
                    passcodeField
                }

                if let error = lock.lastError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .transition(.opacity)
                }

                Toggle(isOn: $rememberMe) {
                    Label("Remember me", systemImage: "checkmark.shield")
                        .font(.subheadline)
                }
                .tint(.teal)

                if lock.hasPasscode {
                    Button {
                        submitPasscode()
                    } label: {
                        Label("Unlock", systemImage: "lock.open.fill")
                    }
                    .buttonStyle(GlassProminentButtonStyle())
                    .disabled(!canSubmit)
                }

                if lock.biometricsEnabled && AppLock.biometricsAvailable {
                    Button {
                        Task { await lock.authenticateWithBiometrics(remember: rememberMe) }
                    } label: {
                        Label(
                            "Unlock with \(AppLock.biometryLabel)",
                            systemImage: AppLock.biometryLabel == "Touch ID" ? "touchid" : "faceid"
                        )
                    }
                    .buttonStyle(lock.hasPasscode ? AnyButtonStyle(GlassButtonStyle()) : AnyButtonStyle(GlassProminentButtonStyle()))
                }
            }
            .padding(24)
            .frame(maxWidth: 340)
            .glassCard()
            .padding()
            .offset(x: shake ? -8 : 0)
            .animation(.default, value: lock.lastError != nil)
        }
        .onAppear {
            rememberMe = rememberPreference
            // Auto-prompt biometrics when enabled (matches banking-app behavior);
            // the passcode field stays available as a fallback.
            if AppLock.biometricsAvailable && lock.biometricsEnabled {
                Task { await lock.authenticateWithBiometrics(remember: rememberMe) }
            } else if lock.hasPasscode {
                passcodeFocused = true
            }
        }
    }

    private var passcodeField: some View {
        SecureField("Passcode", text: $passcode)
            .keyboardType(.numberPad)
            .textContentType(.password)
            .multilineTextAlignment(.center)
            .font(.title3.weight(.semibold))
            .focused($passcodeFocused)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Glass.bevelStroke, lineWidth: 1)
            )
            .onSubmit(submitPasscode)
    }

    private func submitPasscode() {
        guard canSubmit else { return }
        if lock.unlock(passcode: passcode, remember: rememberMe) {
            rememberPreference = rememberMe
            Haptics.success()
        } else {
            passcode = ""
            withAnimation(.spring(response: 0.2, dampingFraction: 0.3)) { shake = true }
            withAnimation(.spring(response: 0.2, dampingFraction: 0.3).delay(0.1)) { shake = false }
        }
    }
}

/// Type-erased button style so the biometric button can switch between the
/// prominent and plain glass styles depending on whether a passcode exists.
struct AnyButtonStyle: ButtonStyle {
    private let makeBodyClosure: (Configuration) -> AnyView

    init<S: ButtonStyle>(_ style: S) {
        makeBodyClosure = { AnyView(style.makeBody(configuration: $0)) }
    }

    func makeBody(configuration: Configuration) -> some View {
        makeBodyClosure(configuration)
    }
}

// MARK: - Passcode setup

/// Set or change the numeric passcode. Requires the code to be entered twice.
struct PasscodeSetupSheet: View {
    @Environment(\.dismiss) private var dismiss
    let lock: AppLock

    @State private var passcode = ""
    @State private var confirm = ""
    @State private var error: String?
    @FocusState private var firstFieldFocused: Bool

    private var isValid: Bool {
        passcode.count >= 4 && passcode.count <= 8 && passcode.allSatisfy(\.isNumber)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("New passcode", text: $passcode)
                        .keyboardType(.numberPad)
                        .focused($firstFieldFocused)
                    SecureField("Confirm passcode", text: $confirm)
                        .keyboardType(.numberPad)
                } footer: {
                    if let error {
                        Text(error).foregroundStyle(.red)
                    } else {
                        Text("Choose a 4–8 digit passcode. It is stored securely in the device Keychain and never leaves your device.")
                    }
                }
                .listRowBackground(GlassRowBackground())
                .listRowSeparator(.hidden)
            }
            .ambientScreen()
            .navigationTitle(lock.hasPasscode ? "Change Passcode" : "Set Passcode")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!isValid)
                }
            }
            .onAppear { firstFieldFocused = true }
        }
    }

    private func save() {
        guard isValid else {
            error = "Passcode must be 4–8 digits."
            return
        }
        guard passcode == confirm else {
            error = "Passcodes don't match."
            confirm = ""
            return
        }
        lock.setPasscode(passcode)
        Haptics.success()
        dismiss()
    }
}
