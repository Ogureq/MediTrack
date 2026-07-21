import SwiftUI

/// The lock / login panel shown over the app when the lock is engaged.
///
/// Face ID (or Touch ID) is the primary path when enabled and available: a
/// filled "Unlock with Face ID" pill re-triggers biometrics, with a quiet
/// "Enter Passcode" link below as a fallback that reveals the manual
/// passcode field. Devices without usable biometrics show the passcode
/// field as the primary (and only) path instead, with the same filled pill
/// now labeled "Enter Passcode" and acting as the submit button.
///
/// A small "Medical ID" link at the bottom presents the read-only emergency
/// card in a sheet — first responders can reach it without unlocking the
/// app. All lockout/attempt/"Remember me" semantics live in `AppLock` and
/// are untouched here; this file only changes presentation.
struct LoginView: View {
    @ObservedObject var lock: AppLock

    @AppStorage("app.rememberMePreference") private var rememberPreference = false
    @State private var rememberMe = false
    @State private var passcode = ""
    @State private var shake = false
    /// True once the user taps the quiet "Enter Passcode" fallback link
    /// while Face ID/Touch ID is the primary path shown — reveals the
    /// passcode field and switches to the passcode-submit CTA.
    @State private var showPasscodeFallback = false
    @State private var showingMedicalID = false
    @FocusState private var passcodeFocused: Bool
    @Environment(\.colorScheme) private var colorScheme

    private var canSubmit: Bool { passcode.count >= 4 }

    /// True when biometrics is the primary unlock path on first appearance
    /// — the passcode field is a fallback in that case. False (passcode is
    /// primary) when biometrics is off or unavailable on this device.
    private var biometricsPrimary: Bool {
        lock.biometricsEnabled && AppLock.biometricsAvailable
    }

    /// Whichever path is actually being presented right now.
    private var isPasscodeMode: Bool {
        !biometricsPrimary || showPasscodeFallback
    }

    private var glyphSystemImage: String {
        guard biometricsPrimary else { return "lock.fill" }
        return AppLock.biometryLabel == "Touch ID" ? "touchid" : "faceid"
    }

    private var lockAuthWord: String {
        biometricsPrimary ? AppLock.biometryLabel : String(localized: "your passcode")
    }

    private var lockSubtitle: LocalizedStringKey {
        "Your health records stay behind \(lockAuthWord)."
    }

    var body: some View {
        ZStack {
            AmbientBackground()

            VStack(spacing: 20) {
                VStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .strokeBorder(Editorial.controlBorder(colorScheme), lineWidth: 1.5)
                            .frame(width: 76, height: 76)
                        Image(systemName: glyphSystemImage)
                            .font(.system(size: 32, weight: .medium))
                            .foregroundStyle(Editorial.ink(colorScheme))
                    }
                    .accessibilityHidden(true)

                    Text("Gemocode is locked")
                        .font(.system(size: 26, weight: .regular))
                        .tracking(-0.4)
                        .foregroundStyle(Editorial.ink(colorScheme))
                    Text(lockSubtitle)
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(Editorial.muted(colorScheme))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 250)
                }
                .accessibilityElement(children: .combine)

                if isPasscodeMode, lock.hasPasscode {
                    passcodeField
                }

                // Ticks every second so the countdown text and the disabled
                // submit button both clear on their own once the lockout
                // expires, without requiring another user action.
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    let remaining = lock.lockoutRemainingSeconds

                    VStack(spacing: 14) {
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

                        if isPasscodeMode {
                            if lock.hasPasscode {
                                Button {
                                    submitPasscode()
                                } label: {
                                    Text("Enter Passcode")
                                }
                                .buttonStyle(LockUnlockButtonStyle())
                                .disabled(!canSubmit || remaining > 0)
                            }
                        } else {
                            Button {
                                Task { await lock.authenticateWithBiometrics(remember: rememberMe) }
                            } label: {
                                Text("Unlock with \(AppLock.biometryLabel)")
                            }
                            .buttonStyle(LockUnlockButtonStyle())

                            if lock.hasPasscode {
                                Button {
                                    showPasscodeFallback = true
                                    passcodeFocused = true
                                } label: {
                                    Text("Enter Passcode")
                                        .font(.system(size: 13, weight: .medium))
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(Editorial.muted(colorScheme))
                            }
                        }

                        Toggle(isOn: $rememberMe) {
                            Label("Remember me", systemImage: "checkmark.shield")
                                .font(.subheadline)
                        }
                        .tint(Editorial.tagGood(colorScheme))
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: 340)
            .offset(x: shake ? -8 : 0)
            .animation(.default, value: lock.lastError != nil)

            VStack {
                Spacer()
                Button {
                    showingMedicalID = true
                } label: {
                    Text("Medical ID")
                        .font(.system(size: 12, weight: .regular))
                        .underline()
                }
                .buttonStyle(.plain)
                .foregroundStyle(Editorial.muted(colorScheme))
                .accessibilityHint("Opens read-only emergency medical information without unlocking Gemocode.")
                .padding(.bottom, 20)
            }
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
        .sheet(isPresented: $showingMedicalID) {
            NavigationStack {
                MedicalIDView()
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

/// The one filled CTA on the lock screen: `Editorial.ink` fill with
/// `Editorial.canvas` text (black-on-white in light mode, light-on-dark in
/// dark mode) — the same "ink fill / canvas text" chrome `PillTabBar`
/// already uses elsewhere. This is a deliberate, mockup-driven exception to
/// the app-wide "outlined buttons only" rule (`GlassButtonStyle`); it is
/// intentionally NOT accent-colored.
private struct LockUnlockButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(Editorial.canvas(colorScheme))
            .multilineTextAlignment(.center)
            .padding(.vertical, 14)
            .padding(.horizontal, 32)
            .background(
                Capsule(style: .continuous)
                    .fill(Editorial.ink(colorScheme))
                    .opacity(configuration.isPressed ? 0.85 : 1)
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(duration: 0.2), value: configuration.isPressed)
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
