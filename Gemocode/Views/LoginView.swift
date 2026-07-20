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
    @Environment(\.colorScheme) private var colorScheme

    private var canSubmit: Bool { passcode.count >= 4 }

    var body: some View {
        ZStack {
            AmbientBackground()

            VStack(spacing: 20) {
                VStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .strokeBorder(Editorial.controlBorder(colorScheme), lineWidth: 1.5)
                            .frame(width: 76, height: 76)
                        Image(systemName: "cross.case.fill")
                            .font(.system(size: 32, weight: .medium))
                            .foregroundStyle(Editorial.ink(colorScheme))
                    }
                    .accessibilityHidden(true)

                    Text("Welcome Back")
                        .font(.system(size: 26, weight: .regular))
                        .tracking(-0.4)
                        .foregroundStyle(Editorial.ink(colorScheme))
                    Text("Sign in to view your medical data.")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(Editorial.muted(colorScheme))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 250)
                }

                if lock.hasPasscode {
                    passcodeField
                }

                // Ticks every second so the countdown text and the disabled
                // Unlock button both clear on their own once the lockout
                // expires, without requiring another user action.
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    let remaining = lock.lockoutRemainingSeconds

                    if remaining > 0 {
                        Text("Too many attempts. Try again in \(remaining)s.")
                            .font(.caption)
                            .foregroundStyle(Editorial.tagBad(colorScheme))
                            .transition(.opacity)
                    } else if let error = lock.lastError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(Editorial.tagBad(colorScheme))
                            .transition(.opacity)
                    }

                    Toggle(isOn: $rememberMe) {
                        Label("Remember me", systemImage: "checkmark.shield")
                            .font(.subheadline)
                    }
                    .tint(Editorial.tagGood(colorScheme))

                    if lock.hasPasscode {
                        Button {
                            submitPasscode()
                        } label: {
                            Label("Unlock", systemImage: "lock.open.fill")
                        }
                        .buttonStyle(GlassButtonStyle())
                        .disabled(!canSubmit || remaining > 0)
                    }
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
                    .buttonStyle(GlassButtonStyle())
                }
            }
            .padding(24)
            .frame(maxWidth: 340)
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
            .background(Editorial.insetCard(colorScheme), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Glass.bevelStroke(for: colorScheme), lineWidth: 1)
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

// MARK: - Passcode setup

/// Set or change the numeric passcode. Requires the code to be entered twice.
struct PasscodeSetupSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
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
                        Text(error).foregroundStyle(Editorial.tagBad(colorScheme))
                    } else {
                        Text("Choose a 4–8 digit passcode. It is stored securely in the device Keychain and never leaves your device.")
                    }
                }
                .listRowBackground(GlassRowBackground())
                .listRowSeparatorTint(Editorial.hairline(colorScheme))
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
            error = String(localized: "Passcode must be 4–8 digits.")
            return
        }
        guard passcode == confirm else {
            error = String(localized: "Passcodes don't match.")
            confirm = ""
            return
        }
        lock.setPasscode(passcode)
        Haptics.success()
        dismiss()
    }
}
