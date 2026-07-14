import SwiftUI

/// MediTrack's two in-app legal documents — Terms of Service and Privacy
/// Policy — required by App Store Review Guideline 3.1.2 for apps that
/// offer auto-renewable subscriptions. Rendered natively so they read
/// fully offline, matching MediTrack's local-first design, with hosted
/// copies at `site/privacy.html` and `site/terms.html` for the landing
/// page kept in substantive sync with the text below.
///
/// Every claim here must stay true to the app's actual, shipped behavior —
/// see `PrivacyExplainerView`, `README.md`, and `backend/README.md`. Where
/// a common boilerplate privacy-policy claim doesn't fit MediTrack's
/// architecture (e.g. "we may share data with service providers"), this
/// document says what's actually true instead.
enum LegalDocument: Identifiable, Hashable {
    case privacyPolicy
    case termsOfService

    var id: Self { self }

    var title: String {
        switch self {
        case .privacyPolicy: return "Privacy Policy"
        case .termsOfService: return "Terms of Service"
        }
    }

    var systemImage: String {
        switch self {
        case .privacyPolicy: return "lock.shield.fill"
        case .termsOfService: return "doc.text.fill"
        }
    }

    var summary: String {
        switch self {
        case .privacyPolicy:
            return "What MediTrack stores, what it never collects, and the one opt-in exception for AI features."
        case .termsOfService:
            return "The rules for using MediTrack, including its educational (not medical) nature and how Premium billing works."
        }
    }

    static let effectiveDate = "Effective July 2026"

    var sections: [LegalSection] {
        switch self {
        case .privacyPolicy: return LegalSection.privacyPolicySections
        case .termsOfService: return LegalSection.termsOfServiceSections
        }
    }
}

/// One heading + body pair within a legal document.
struct LegalSection: Identifiable {
    let id = UUID()
    let heading: String
    let body: String
}

// MARK: - Privacy Policy content

extension LegalSection {
    static let privacyPolicySections: [LegalSection] = [
        LegalSection(
            heading: "The Short Version",
            body: "MediTrack is built local-first: your medical reports, lab results, vitals, medications, symptoms, appointments, and health profile are stored only on your iPhone, in the app's on-device database. There is no MediTrack account, no sign-up, and no server that holds your health records. We don't run analytics, we don't track you across apps or websites, we don't show ads, and we never sell data — because we don't have any to sell. The only exception is the optional AI features described below, which you must actively choose to use."
        ),
        LegalSection(
            heading: "What We Never Collect",
            body: "We do not collect or receive your medical reports, photos, PDFs, lab values, vitals, medication lists, symptom entries, appointments, or Medical ID. We do not collect your name, date of birth, email address, or any other identity information — MediTrack has no account system, so there is nothing to attach your data to even if we wanted to. We do not use analytics or crash-reporting tools that phone home, we do not run advertising, and we do not track you across other apps or the web. Everything you enter lives in the app's local database on your device, protected by your device's own security and, if you choose to set one, MediTrack's own app passcode with optional Face ID or Touch ID unlock."
        ),
        LegalSection(
            heading: "The One Exception: Optional AI Features",
            body: "MediTrack's AI features — generating a narrated health report, chatting about your results, or using \"Fill with AI\" to parse a Quick Add sentence — are opt-in and do nothing unless you tap them. When you use one, MediTrack sends a text summary to make the AI request: for a health report, that's the score, findings, and lab or vital values your on-device analysis engine already computed; for chat, it's your typed questions plus that same summary; for Quick Add, it's the single sentence you typed. That text goes to our relay service, which forwards it to Anthropic's API to generate a response and returns the answer to the app. Your original documents, scanned photos and PDFs, your full database, and identity fields like your name, date of birth, blood type, allergies, and Medical ID are never included in these requests, regardless of which AI feature you use. Our relay does not store the content of your requests or the AI's replies — it logs only operational metadata (timestamps and token counts) needed to run the service and enforce fair-use limits. Each device generates its own random, anonymous identifier — not your Apple ID, not linked to your identity — that the relay uses to apply rate limits and track your one free lifetime AI report; deleting and reinstalling the app resets this identifier. If you instead add your own Anthropic API key in Profile & Settings, your device talks directly to Anthropic's API using that key — our relay, its metadata logging, and the anonymous identifier aren't involved at all in that case. If you never tap an AI feature, MediTrack makes no network calls of any kind."
        ),
        LegalSection(
            heading: "Apple Services — Purchases & Health",
            body: "MediTrack Premium subscriptions are sold and processed entirely through Apple's App Store using StoreKit. We never see or store your payment method, billing address, or card details — Apple handles all of that under its own privacy policy; we only learn whether a purchase succeeded. Separately, if you turn on the optional \"Import from Apple Health\" or \"Save new vitals to Apple Health\" features in Profile, MediTrack reads or writes vitals only after you grant permission through Apple's own system prompt, and that exchange happens directly between MediTrack and the Health app on your device — it never passes through our servers."
        ),
        LegalSection(
            heading: "Backups",
            body: "The \"Export Backup\" feature creates a single JSON file containing your data, encrypted with AES-GCM using a key derived from a passphrase you choose. MediTrack can't open that file without your passphrase, and neither can we — we never see it, because it isn't sent anywhere by the app. Where you store or share that file afterward (iCloud Drive, email, a USB drive) is entirely up to you and outside MediTrack's control."
        ),
        LegalSection(
            heading: "Deleting Your Data",
            body: "Because everything lives on your device, deleting MediTrack from your iPhone deletes your data with it. You can also use \"Erase All Data\" in Profile → Data to wipe everything immediately while keeping the app installed. There is no MediTrack server copy to separately request deletion of. The only server-side records tied to AI use are the relay's transient, metadata-only logs described above and an anonymous per-device flag marking whether your free report has been used — neither contains health content, and neither is linked to your identity."
        ),
        LegalSection(
            heading: "Children",
            body: "MediTrack is not directed at children under 13, and we do not knowingly collect information from them. Because MediTrack has no account system and no server-side health data collection, there is no personal information for us to identify as belonging to a child in the first place, and the AI relay's anonymous metadata carries no age or identity signal either."
        ),
        LegalSection(
            heading: "Changes to This Policy",
            body: "If MediTrack's data practices change, this policy and the in-app \"Privacy & Your Data\" screen (Profile → About) will be updated together, and the effective date below will change. Material changes — like a new feature that sends different data off-device — will be called out in the app's release notes."
        ),
        LegalSection(
            heading: "Contact",
            body: "Questions about this policy can be sent to support@meditrack.app (TODO: replace with the owner's actual support address before submission)."
        ),
    ]

    static let termsOfServiceSections: [LegalSection] = [
        LegalSection(
            heading: "Agreement",
            body: "These Terms of Service govern your use of MediTrack (the \"App\"). By downloading, installing, or using MediTrack, you agree to these terms. If you don't agree, please don't use the App."
        ),
        LegalSection(
            heading: "Educational Information, Not Medical Advice",
            body: "MediTrack provides educational information only. The Detailed Health Review, health score, findings, trend analysis, and any AI-generated narration are produced by a rule-based analysis engine — and, optionally, a large language model — working from data you entered yourself. None of it is medical advice, a diagnosis, or a treatment recommendation, and MediTrack is not a medical device. Always consult a qualified healthcare professional — your doctor, pharmacist, or other licensed provider — about any question involving a medical condition, lab result, medication, or symptom. Never disregard professional medical advice or delay seeking it because of something MediTrack showed you. MediTrack is not for emergencies: if you believe you are experiencing a medical emergency, call your local emergency number immediately."
        ),
        LegalSection(
            heading: "AI-Generated Content May Contain Errors",
            body: "MediTrack's optional AI features — the narrated health report, report chat, and AI-assisted Quick Add — use a large language model to generate text. We verify AI report output against your underlying data, cross-checking the numbers and findings it cites, before showing it to you, and Quick Add's AI-filled fields are re-validated on-device before you can save them — but these safeguards reduce, not eliminate, the chance of an error. AI output can still misstate, omit, or misinterpret something. Always double-check AI-generated content against your original lab reports, documents, and your own records before relying on it, and treat it with the same ask-your-doctor caution as the rest of MediTrack's educational content."
        ),
        LegalSection(
            heading: "Subscriptions & Billing",
            body: "MediTrack Premium is an auto-renewable subscription — $19.99/month, or a discounted yearly option; exact current prices are shown in the app before you purchase — that unlocks unlimited AI health reports, report chat, and AI-assisted Quick Add. Every local tracking feature — reports, OCR lab scanning, health score, trend charts, interaction checks, backups — is free forever and never requires a subscription. Every user, subscribed or not, gets one AI health report free for the lifetime of the device as a trial. Subscriptions are billed and managed entirely through your Apple ID via the App Store: payment is charged to your Apple ID account at confirmation of purchase, and the subscription renews automatically unless auto-renew is turned off at least 24 hours before the end of the current period. You can manage or cancel your subscription anytime in your device's Settings → [your name] → Subscriptions. We don't handle billing directly and can't process refunds ourselves — refund requests go through Apple."
        ),
        LegalSection(
            heading: "Acceptable Use",
            body: "You agree not to misuse MediTrack's AI features — for example, by using them to generate content unrelated to your own health tracking, attempting to extract, abuse, or overload the relay service, or sending it anything other than the health information the feature is designed to process. You agree not to reverse-engineer, decompile, or attempt to bypass the AI relay's authentication or rate limits, or to interfere with its operation for other users."
        ),
        LegalSection(
            heading: "Disclaimer of Warranties; Limitation of Liability",
            body: "MediTrack is provided \"as is\" and \"as available,\" without warranties of any kind, express or implied, including fitness for a particular purpose, merchantability, accuracy, or non-infringement. We don't warrant that the App, its analysis engine, or its AI features will be uninterrupted, error-free, or produce results suitable for your specific situation. To the maximum extent permitted by applicable law, we disclaim all liability for damages — direct, indirect, incidental, or consequential — arising from your use of MediTrack, including decisions made based on its health score, findings, or AI-generated content."
        ),
        LegalSection(
            heading: "Your Data & Backups Are Your Responsibility",
            body: "Because MediTrack stores data only on your device with no server-side copy, you are responsible for backing up your own data using the \"Export Backup\" feature and for safeguarding your backup passphrase. If you lose that passphrase, we cannot recover the file's contents; if you lose your device without a backup, your data is gone. Uninstalling the App or using \"Erase All Data\" permanently deletes your on-device records."
        ),
        LegalSection(
            heading: "Governing Law",
            body: "These terms are governed by the laws of [TODO: owner to specify jurisdiction], without regard to its conflict-of-law principles, except where local consumer-protection law provides otherwise."
        ),
        LegalSection(
            heading: "Changes to These Terms",
            body: "We may update these terms as MediTrack's features change. Continued use of the App after an update means you accept the revised terms; material changes will be noted in the app's release notes."
        ),
        LegalSection(
            heading: "Contact",
            body: "Questions about these terms can be sent to support@meditrack.app (TODO: replace with the owner's actual support address before submission)."
        ),
    ]
}

// MARK: - View

/// Full-screen (sheeted) reader for a `LegalDocument`. Offline, native,
/// glass-styled to match the rest of MediTrack.
struct LegalView: View {
    let document: LegalDocument

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    heroCard
                    ForEach(document.sections) { section in
                        sectionCard(section)
                    }
                    Text("This document describes MediTrack's actual, current behavior. It is not a substitute for independent legal advice.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 4)
                }
                .padding()
            }
            .ambientScreen()
            .navigationTitle(document.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .fontDesign(.rounded)
    }

    private var heroCard: some View {
        VStack(spacing: 10) {
            Image(systemName: document.systemImage)
                .font(.system(size: 36))
                .foregroundStyle(Glass.accentGradient)
                .accessibilityHidden(true)
            Text(document.title)
                .font(.title3.weight(.bold))
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            Text(document.summary)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Text(LegalDocument.effectiveDate)
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .padding()
        .glassCard()
        .accessibilityElement(children: .combine)
    }

    private func sectionCard(_ section: LegalSection) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(section.heading)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .accessibilityAddTraits(.isHeader)
            Text(section.body)
                .font(.subheadline)
                .foregroundStyle(.primary.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(cornerRadius: Glass.chipRadius)
    }
}

#Preview("Privacy Policy") {
    LegalView(document: .privacyPolicy)
}

#Preview("Terms of Service") {
    LegalView(document: .termsOfService)
}
