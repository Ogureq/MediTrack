import SwiftUI

/// A calm, read-only explainer of Gemocode's on-device-only data model.
///
/// Every claim on this screen must stay true to the actual behavior in
/// `AISummaryService` and `BackupService` — this is read as a trust
/// statement, so it deliberately does not overclaim: the AI summary
/// feature *does* send structured health values (score, findings, trends,
/// including the specific numbers behind them) when the user opts in, and
/// this screen says so rather than pretending nothing leaves.
struct PrivacyExplainerView: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                heroCard

                section(title: "What's Stored", systemImage: "internaldrive", tint: Editorial.ink(colorScheme)) {
                    bullet("Reports, lab results, vitals, medications, symptoms, appointments, and goals all live in an on-device SwiftData database.")
                    bullet("There's no Gemocode account, server, or sync. Nothing is uploaded automatically — ever.")
                }

                section(title: "What's Protected", systemImage: "lock.shield", tint: Editorial.accent(colorScheme)) {
                    bullet("An optional app passcode — plus Face ID or Touch ID where your device supports it — keeps the app locked when you step away.")
                    bullet("Backups you export are encrypted with AES-GCM using a key derived from a passphrase only you know. Gemocode can't open a backup without it, and neither can anyone else.")
                }

                section(title: "What Leaves the Device — Only When You Ask", systemImage: "arrow.up.right.square", tint: Editorial.tagWarn(colorScheme)) {
                    bullet("The AI Summary feature in Profile & Settings is opt-in and off by default. When you tap Generate, Gemocode sends the health review it already built for you — your score, findings, and trends, including the specific lab and vital values behind them — to Anthropic's API, using your own API key.")
                    bullet("Your name, date of birth, blood type, allergies, Medical ID, and original documents are never included in that request.")
                    bullet("This is the only network call Gemocode ever makes. Leave the API key blank to keep the app fully offline.")
                }

                section(title: "What Never Leaves", systemImage: "shield.lefthalf.filled", tint: Editorial.tagGood(colorScheme)) {
                    bullet("Attachments — scanned photos and PDFs of your reports — are never transmitted anywhere by the app itself.")
                    bullet("Your Medical ID is for on-device viewing. It only leaves your phone if you personally tap Share on that screen or export a backup — Gemocode never sends it on its own.")
                }

                section(title: "Erasing Everything", systemImage: "trash", tint: Editorial.tagBad(colorScheme)) {
                    bullet("Profile & Settings → Data → Erase All Data removes every record from this device immediately. This can't be undone, so export a backup first if you want to keep a copy.")
                }

                Text("This screen describes Gemocode's current behavior. If that ever changes, this page — and the disclaimers throughout the app — change with it.")
                    .font(.caption)
                    .foregroundStyle(Editorial.muted(colorScheme))
                    .padding(.horizontal, 4)
            }
            .padding()
        }
        .ambientScreen()
        .navigationTitle("Privacy & Your Data")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: Hero

    private var heroCard: some View {
        VStack(spacing: 10) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 40))
                .foregroundStyle(Editorial.ink(colorScheme))
                .accessibilityHidden(true)
            Text("Your data stays on your phone")
                .font(.system(size: 20, weight: .regular))
                .tracking(-0.3)
                .foregroundStyle(Editorial.ink(colorScheme))
                .multilineTextAlignment(.center)
            Text("Gemocode is local-first: everything you enter is stored on this device, not in the cloud.")
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(Editorial.muted(colorScheme))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .padding()
        .background(Editorial.insetCard(colorScheme), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    // MARK: Section builder

    @ViewBuilder
    private func section<Content: View>(
        title: LocalizedStringKey,
        systemImage: String,
        tint: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 8) {
                content()
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Editorial.canvas(colorScheme), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Editorial.hairline(colorScheme), lineWidth: 1)
        )
    }

    private func bullet(_ text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(Editorial.muted(colorScheme).opacity(0.5))
                .frame(width: 5, height: 5)
                .padding(.top, 7)
                .accessibilityHidden(true)
            Text(text)
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(Editorial.ink(colorScheme))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

#Preview {
    NavigationStack {
        PrivacyExplainerView()
    }
}
