import SwiftUI
import SwiftData

struct MedicalIDView: View {
    @Query private var profiles: [HealthProfile]
    @Query(sort: \Medication.startDate, order: .reverse) private var medications: [Medication]
    @Query(sort: \VitalSample.date, order: .reverse) private var vitals: [VitalSample]

    @Environment(\.colorScheme) private var colorScheme

    private var profile: HealthProfile? { profiles.first }

    private var activeMedications: [Medication] {
        medications.filter(\.isActive)
    }

    /// Comma-joined active medication names — same pattern used for the
    /// medication interaction summary in `AnalysisEngine`.
    private var activeMedicationNames: String {
        activeMedications.map(\.name).joined(separator: ", ")
    }

    private var latestWeightSample: VitalSample? {
        vitals.first { $0.type == .weight }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                screenHeader
                heroCard
                allergiesSection
                medicationsSection
                conditionsSection
                emergencyContactCard
                Text("Keep this at hand in an emergency — and consider adding it to Apple Health's Medical ID, which can appear on your Lock Screen.")
                    .font(.caption)
                    .foregroundStyle(Editorial.muted(colorScheme))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)
            }
            .padding()
        }
        .ambientScreen()
        .navigationTitle("Medical ID")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                ShareLink(item: shareText) {
                    Image(systemName: "square.and.arrow.up")
                }
                .accessibilityLabel("Share medical ID")
            }
        }
    }

    // MARK: - Screen header

    /// Large in-content title (the system nav bar is `.inline` above) plus
    /// the "Emergency" tag and the lock-screen-reachability subtitle from
    /// the redesign — this card is meant to read as a first-responder
    /// document, not just another settings screen.
    private var screenHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("Medical ID")
                    .font(.system(size: 28, weight: .regular))
                    .tracking(-0.4)
                    .foregroundStyle(Editorial.ink(colorScheme))
                EditorialTag("Emergency", kind: .bad)
            }
            Text("Available from the lock screen for first responders — even when the app is locked.")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(Editorial.muted(colorScheme))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Hero card

    private var initials: String? {
        guard let name = profile?.name, !name.isEmpty else { return nil }
        let letters = name
            .split(separator: " ")
            .compactMap { $0.first }
            .prefix(2)
        return String(letters).uppercased()
    }

    /// Small identity facts rendered as outlined pills below the name —
    /// blood type, a combined height/weight reading, and organ-donor status
    /// (shown only when it's an affirmative "yes", matching how the
    /// allergies list only ever states what *does* apply).
    private var identityChips: [String] {
        var chips: [String] = []
        if let bloodType = profile?.bloodType, !bloodType.isEmpty {
            chips.append(String(localized: "\(bloodType) blood"))
        }
        let heightPart = profile?.heightCm.map { "\($0.compactFormatted) cm" }
        let weightPart = latestWeightSample?.formattedValue
        let bodyParts = [heightPart, weightPart].compactMap { $0 }
        if !bodyParts.isEmpty {
            chips.append(bodyParts.joined(separator: " · "))
        }
        if profile?.organDonorStatus == "yes" {
            chips.append(String(localized: "Organ donor"))
        }
        return chips
    }

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                avatarView
                VStack(alignment: .leading, spacing: 2) {
                    if let profile, !profile.name.isEmpty {
                        Text(profile.name)
                            .font(.system(size: 18, weight: .medium))
                            .tracking(-0.2)
                            .foregroundStyle(Editorial.ink(colorScheme))
                    } else {
                        Text("Add your name in Profile")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Editorial.muted(colorScheme))
                    }
                    if let dateOfBirth = profile?.dateOfBirth {
                        Group {
                            if let age = profile?.age {
                                Text("\(dateOfBirth.formatted(date: .abbreviated, time: .omitted)) · \(age) years old")
                            } else {
                                Text(dateOfBirth.formatted(date: .abbreviated, time: .omitted))
                            }
                        }
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(Editorial.muted(colorScheme))
                    }
                }
                Spacer(minLength: 0)
            }

            if !identityChips.isEmpty {
                FlowLayout(spacing: 8) {
                    ForEach(identityChips, id: \.self) { chip in
                        Text(chip)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Editorial.ink(colorScheme))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Editorial.canvas(colorScheme), in: Capsule())
                            .overlay(Capsule().strokeBorder(Editorial.controlBorder(colorScheme), lineWidth: 1))
                    }
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Editorial.insetCard(colorScheme), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    /// Reuses the More-screen profile-header avatar treatment (teal → green
    /// gradient, dark initials). `MoreTint` in ContentView.swift is a private
    /// enum this file can't reference, so the same values are intentionally
    /// duplicated here — keep both in sync if the More-screen gradient changes.
    private var avatarView: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [MedicalIDAvatarTint.start, MedicalIDAvatarTint.end],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 52, height: 52)
            if let initials, !initials.isEmpty {
                Text(initials)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(MedicalIDAvatarTint.text)
            } else {
                Image(systemName: "person.fill")
                    .font(.title3)
                    .foregroundStyle(MedicalIDAvatarTint.text)
            }
        }
        .accessibilityHidden(true)
    }

    // MARK: - Allergies

    private var allergyChips: [String] {
        guard let allergies = profile?.allergies, !allergies.isEmpty else { return [] }
        return allergies
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    @ViewBuilder
    private var allergiesSection: some View {
        if !allergyChips.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                // Deliberately not the shared `MicroLabel` component: allergies
                // are the one section that reads as urgent/red rather than the
                // usual muted section-header color, matching the emergency-card
                // mockup's red "Allergies" header.
                Text("ALLERGIES")
                    .font(.system(size: 10, weight: .semibold))
                    .kerning(1.6)
                    .textCase(.uppercase)
                    .foregroundStyle(Editorial.tagBad(colorScheme))
                FlowLayout(spacing: 8) {
                    ForEach(allergyChips, id: \.self) { allergy in
                        EditorialTag(verbatim: allergy, kind: .bad)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Allergies: \(allergyChips.joined(separator: ", "))")
        }
    }

    // MARK: - Medications

    @ViewBuilder
    private var medicationsSection: some View {
        if !activeMedications.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                MicroLabel("Medications")
                    .padding(.bottom, 6)
                ForEach(activeMedications) { medication in
                    medicationRow(medication)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func medicationRow(_ medication: Medication) -> some View {
        let title = [medication.name, medication.dosage]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        let sinceText = String(localized: "since \(medication.startDate.formatted(.dateTime.month(.abbreviated).year()))")
        let subtitle = [medication.frequency, sinceText]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")

        return HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Editorial.ink(colorScheme))
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(Editorial.muted(colorScheme))
                }
            }
            Spacer(minLength: 8)
        }
        .ledgerRow()
        .accessibilityElement(children: .combine)
    }

    // MARK: - Conditions

    private var conditionChips: [String] {
        guard let conditions = profile?.conditions, !conditions.isEmpty else { return [] }
        return conditions
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    @ViewBuilder
    private var conditionsSection: some View {
        if !conditionChips.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                MicroLabel("Conditions")
                FlowLayout(spacing: 8) {
                    ForEach(conditionChips, id: \.self) { condition in
                        Text(condition)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Editorial.ink(colorScheme))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .overlay(Capsule().strokeBorder(Editorial.controlBorder(colorScheme), lineWidth: 1))
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Conditions: \(conditionChips.joined(separator: ", "))")
        }
    }

    // MARK: - Emergency contact

    private var emergencyContactPhoneURL: URL? {
        guard let phone = profile?.emergencyContactPhone, !phone.isEmpty else { return nil }
        let digits = phone.filter { $0.isNumber || $0 == "+" }
        guard !digits.isEmpty else { return nil }
        return URL(string: "tel:\(digits)")
    }

    @ViewBuilder
    private var emergencyContactCard: some View {
        if let profile, !profile.emergencyContactName.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                MicroLabel("EMERGENCY CONTACT")
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(profile.emergencyContactName)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Editorial.ink(colorScheme))
                        let caption = [profile.emergencyContactRelation, profile.emergencyContactPhone]
                            .filter { !$0.isEmpty }
                            .joined(separator: " · ")
                        if !caption.isEmpty {
                            Text(caption)
                                .font(.system(size: 12, weight: .regular))
                                .foregroundStyle(Editorial.muted(colorScheme))
                        }
                    }
                    Spacer()
                    if let emergencyContactPhoneURL {
                        Link(destination: emergencyContactPhoneURL) {
                            Image(systemName: "phone.fill")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white)
                                .frame(width: 34, height: 34)
                                .background(Editorial.tagGood(colorScheme), in: Circle())
                        }
                        .accessibilityLabel("Call emergency contact")
                    }
                }
                .accessibilityElement(children: .combine)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .ledgerRow()
        } else {
            HStack(spacing: 10) {
                Image(systemName: "person.crop.circle.badge.plus")
                    .foregroundStyle(Editorial.muted(colorScheme))
                    .accessibilityHidden(true)
                Text("Add an emergency contact in Profile → Emergency")
                    .font(.footnote)
                    .foregroundStyle(Editorial.muted(colorScheme))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .ledgerRow()
        }
    }

    // MARK: - Share text

    private var shareText: String {
        var lines = [String(localized: "Medical ID")]

        if let profile {
            lines.append(
                profile.name.isEmpty
                    ? String(localized: "Name: —")
                    : String(localized: "Name: \(profile.name)")
            )
            if let dateOfBirth = profile.dateOfBirth {
                if let age = profile.age {
                    lines.append(String(localized: "Date of birth: \(dateOfBirth.formatted(date: .abbreviated, time: .omitted)) (\(age) years)"))
                } else {
                    lines.append(String(localized: "Date of birth: \(dateOfBirth.formatted(date: .abbreviated, time: .omitted))"))
                }
            }
            if profile.sex != .unspecified {
                lines.append(String(localized: "Biological sex: \(profile.sex.displayName)"))
            }
            if let heightCm = profile.heightCm {
                lines.append(String(localized: "Height: \(heightCm.compactFormatted) cm"))
            }
            if let latestWeightSample {
                lines.append(String(localized: "Weight: \(latestWeightSample.formattedValue)"))
            }
            lines.append(String(localized: "Blood type: \(profile.bloodType.isEmpty ? String(localized: "Unknown") : profile.bloodType)"))
            if !profile.allergies.isEmpty {
                lines.append(String(localized: "Allergies: \(profile.allergies)"))
            }
            if !profile.conditions.isEmpty {
                lines.append(String(localized: "Medical conditions: \(profile.conditions)"))
            }
            if !profile.organDonorStatus.isEmpty {
                lines.append(String(localized: "Organ donor: \(profile.organDonorStatus == "yes" ? String(localized: "Yes") : String(localized: "No"))"))
            }
        }

        if !activeMedications.isEmpty {
            lines.append(String(localized: "Active medications:"))
            for medication in activeMedications {
                let detail = [medication.dosage, medication.frequency]
                    .filter { !$0.isEmpty }
                    .joined(separator: " · ")
                lines.append(
                    detail.isEmpty
                        ? String(localized: "- \(medication.name)")
                        : String(localized: "- \(medication.name) (\(detail))")
                )
            }
        }

        if let profile, !profile.emergencyContactName.isEmpty {
            let caption = [profile.emergencyContactRelation, profile.emergencyContactPhone]
                .filter { !$0.isEmpty }
                .joined(separator: " · ")
            lines.append(
                caption.isEmpty
                    ? String(localized: "Emergency contact: \(profile.emergencyContactName)")
                    : String(localized: "Emergency contact: \(profile.emergencyContactName) (\(caption))")
            )
        }

        return lines.joined(separator: "\n")
    }
}

/// Mirrors `MoreTint.avatarStart` / `.avatarEnd` / `.avatarText` in
/// ContentView.swift's `MoreView` profile-header avatar. Duplicated rather
/// than shared because that enum is file-private to ContentView.swift.
private enum MedicalIDAvatarTint {
    static let start = Color(red: 0.2510, green: 0.7843, blue: 0.8784)
    static let end = Color(red: 0.4941, green: 0.9098, blue: 0.6902)
    static let text = Color(red: 0.0431, green: 0.0627, blue: 0.1255)
}

/// Wraps chips left-to-right, moving to a new row on overflow. Local
/// duplicate of the equivalent (also file-private) layout in
/// OnboardingView.swift, used here for the allergy chip row.
private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var rowWidth: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalWidth: CGFloat = 0
        var totalHeight: CGFloat = 0

        for subview in subviews {
            // Clamp to the proposal's width before asking for a size so a
            // single very long chip (e.g. an unusually long allergy name)
            // wraps inside itself instead of measuring wider than the
            // available row and running off-screen.
            let unclamped = subview.sizeThatFits(.unspecified)
            let clampedWidth = min(unclamped.width, maxWidth)
            let size = subview.sizeThatFits(ProposedViewSize(width: clampedWidth, height: nil))
            if rowWidth > 0, rowWidth + spacing + size.width > maxWidth {
                totalHeight += rowHeight + spacing
                totalWidth = max(totalWidth, rowWidth)
                rowWidth = 0
                rowHeight = 0
            }
            rowWidth += (rowWidth > 0 ? spacing : 0) + size.width
            rowHeight = max(rowHeight, size.height)
        }
        totalHeight += rowHeight
        totalWidth = max(totalWidth, rowWidth)
        return CGSize(width: totalWidth, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let maxWidth = bounds.width
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            // Same clamp as `sizeThatFits`, and the clamped width (not the
            // unclamped measured size) is what gets proposed when placing,
            // so the subview actually wraps to it rather than overflowing
            // the row it was placed in.
            let unclamped = subview.sizeThatFits(.unspecified)
            let clampedWidth = min(unclamped.width, maxWidth)
            let size = subview.sizeThatFits(ProposedViewSize(width: clampedWidth, height: nil))
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(width: clampedWidth, height: nil))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
