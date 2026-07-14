import SwiftUI
import SwiftData

struct MedicalIDView: View {
    @Query private var profiles: [HealthProfile]
    @Query(sort: \Medication.startDate, order: .reverse) private var medications: [Medication]
    @Query(sort: \VitalSample.date, order: .reverse) private var vitals: [VitalSample]

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
                heroCard
                infoRowsCard
                allergiesSection
                emergencyContactCard
                Text("Keep this at hand in an emergency — and consider adding it to Apple Health's Medical ID, which can appear on your Lock Screen.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)
            }
            .padding()
        }
        .ambientScreen()
        .navigationTitle("Medical ID")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                ShareLink(item: shareText) {
                    Image(systemName: "square.and.arrow.up")
                }
                .accessibilityLabel("Share medical ID")
            }
        }
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

    private var heroCard: some View {
        HStack(spacing: 14) {
            avatarView
            VStack(alignment: .leading, spacing: 2) {
                if let profile, !profile.name.isEmpty {
                    Text(profile.name)
                        .font(.title3.weight(.bold))
                } else {
                    Text("Add your name in Profile")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                if let dateOfBirth = profile?.dateOfBirth {
                    Group {
                        if let age = profile?.age {
                            Text("\(dateOfBirth.formatted(date: .abbreviated, time: .omitted)) · \(age) years old")
                        } else {
                            Text(dateOfBirth.formatted(date: .abbreviated, time: .omitted))
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            if let bloodType = profile?.bloodType, !bloodType.isEmpty {
                bloodTypeChip(bloodType)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
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
                .frame(width: 56, height: 56)
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

    private func bloodTypeChip(_ value: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 26, weight: .heavy))
                .foregroundStyle(.red)
            Text("BLOOD")
                .font(.system(size: 9, weight: .bold))
                .tracking(0.8)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .tintedGlassCard(.red, cornerRadius: 14)
    }

    // MARK: - Info rows

    private var infoRows: [(label: String, value: String)] {
        var rows: [(String, String)] = []
        if let heightCm = profile?.heightCm {
            rows.append(("Height", "\(heightCm.compactFormatted) cm"))
        }
        if let latestWeightSample {
            rows.append(("Weight", latestWeightSample.formattedValue))
        }
        if let conditions = profile?.conditions, !conditions.isEmpty {
            rows.append(("Conditions", conditions))
        }
        if !activeMedicationNames.isEmpty {
            rows.append(("Medications", activeMedicationNames))
        }
        if let status = profile?.organDonorStatus, !status.isEmpty {
            rows.append(("Organ donor", status == "yes" ? "Yes" : "No"))
        }
        return rows
    }

    @ViewBuilder
    private var infoRowsCard: some View {
        if !infoRows.isEmpty {
            VStack(spacing: 0) {
                ForEach(Array(infoRows.enumerated()), id: \.offset) { index, row in
                    if index > 0 {
                        Divider().opacity(0.3)
                    }
                    HStack {
                        Text(row.label)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(row.value)
                            .font(.subheadline.weight(.semibold))
                            .multilineTextAlignment(.trailing)
                    }
                    .padding(.vertical, 8)
                    .accessibilityElement(children: .combine)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard()
        }
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
                Text("ALLERGIES")
                    .font(.system(size: 13, weight: .semibold))
                    .tracking(0.4)
                    .foregroundStyle(.secondary)
                FlowLayout(spacing: 8) {
                    ForEach(allergyChips, id: \.self) { allergy in
                        Text(allergy)
                            .font(.system(size: 12.5, weight: .semibold))
                            .padding(.horizontal, 13)
                            .padding(.vertical, 7)
                            .foregroundStyle(.orange)
                            .background(Color.orange.opacity(0.14), in: Capsule())
                            .overlay(Capsule().strokeBorder(Color.orange.opacity(0.3), lineWidth: 1))
                    }
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Allergies: \(allergyChips.joined(separator: ", "))")
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
                Text("EMERGENCY CONTACT")
                    .font(.system(size: 13, weight: .semibold))
                    .tracking(0.4)
                    .foregroundStyle(.secondary)
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(profile.emergencyContactName)
                            .font(.subheadline.weight(.bold))
                        let caption = [profile.emergencyContactRelation, profile.emergencyContactPhone]
                            .filter { !$0.isEmpty }
                            .joined(separator: " · ")
                        if !caption.isEmpty {
                            Text(caption)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    if let emergencyContactPhoneURL {
                        Link(destination: emergencyContactPhoneURL) {
                            Image(systemName: "phone.fill")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.green)
                                .frame(width: 40, height: 40)
                                .background(Color.green.opacity(0.16), in: Circle())
                                .overlay(Circle().strokeBorder(Color.green.opacity(0.35), lineWidth: 1))
                        }
                        .accessibilityLabel("Call \(profile.emergencyContactName)")
                    }
                }
                .accessibilityElement(children: .combine)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard()
        } else {
            HStack(spacing: 10) {
                Image(systemName: "person.crop.circle.badge.plus")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text("Add an emergency contact in Profile → Emergency")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard()
        }
    }

    // MARK: - Share text

    private var shareText: String {
        var lines = ["Medical ID"]

        if let profile {
            lines.append(profile.name.isEmpty ? "Name: —" : "Name: \(profile.name)")
            if let dateOfBirth = profile.dateOfBirth {
                if let age = profile.age {
                    lines.append("Date of birth: \(dateOfBirth.formatted(date: .abbreviated, time: .omitted)) (\(age) years)")
                } else {
                    lines.append("Date of birth: \(dateOfBirth.formatted(date: .abbreviated, time: .omitted))")
                }
            }
            if profile.sex != .unspecified {
                lines.append("Biological sex: \(profile.sex.displayName)")
            }
            if let heightCm = profile.heightCm {
                lines.append("Height: \(heightCm.compactFormatted) cm")
            }
            if let latestWeightSample {
                lines.append("Weight: \(latestWeightSample.formattedValue)")
            }
            lines.append("Blood type: \(profile.bloodType.isEmpty ? "Unknown" : profile.bloodType)")
            if !profile.allergies.isEmpty {
                lines.append("Allergies: \(profile.allergies)")
            }
            if !profile.conditions.isEmpty {
                lines.append("Medical conditions: \(profile.conditions)")
            }
            if !profile.organDonorStatus.isEmpty {
                lines.append("Organ donor: \(profile.organDonorStatus == "yes" ? "Yes" : "No")")
            }
        }

        if !activeMedications.isEmpty {
            lines.append("Active medications:")
            for medication in activeMedications {
                let detail = [medication.dosage, medication.frequency]
                    .filter { !$0.isEmpty }
                    .joined(separator: " · ")
                lines.append(detail.isEmpty ? "- \(medication.name)" : "- \(medication.name) (\(detail))")
            }
        }

        if let profile, !profile.emergencyContactName.isEmpty {
            let caption = [profile.emergencyContactRelation, profile.emergencyContactPhone]
                .filter { !$0.isEmpty }
                .joined(separator: " · ")
            lines.append(caption.isEmpty ? "Emergency contact: \(profile.emergencyContactName)" : "Emergency contact: \(profile.emergencyContactName) (\(caption))")
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
            let size = subview.sizeThatFits(.unspecified)
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
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
