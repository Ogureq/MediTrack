import SwiftUI
import SwiftData

struct MedicalIDView: View {
    @Query private var profiles: [HealthProfile]
    @Query(sort: \Medication.startDate, order: .reverse) private var medications: [Medication]

    private var profile: HealthProfile? { profiles.first }

    private var activeMedications: [Medication] {
        medications.filter(\.isActive)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                identityCard
                bloodTypeCard
                if let profile, !profile.allergies.isEmpty {
                    allergiesCard(profile.allergies)
                }
                if let profile, !profile.conditions.isEmpty {
                    conditionsCard(profile.conditions)
                }
                if !activeMedications.isEmpty {
                    medicationsCard
                }
                Text("Keep this information up to date in Profile & Settings. In an emergency, first responders may need it.")
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

    // MARK: - Identity card

    private var identityCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(Glass.accentGradient)
                        .frame(width: 60, height: 60)
                    if let initials, !initials.isEmpty {
                        Text(initials)
                            .font(.title2.weight(.bold))
                            .foregroundStyle(.white)
                    } else {
                        Image(systemName: "person.fill")
                            .font(.title2)
                            .foregroundStyle(.white)
                    }
                }
                .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    if let profile, !profile.name.isEmpty {
                        Text(profile.name)
                            .font(.title2.weight(.bold))
                    } else {
                        Text("Add your name in Profile")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if let profile {
                VStack(spacing: 10) {
                    if let dateOfBirth = profile.dateOfBirth {
                        LabeledContent("Date of birth") {
                            if let age = profile.age {
                                Text("\(dateOfBirth.formatted(date: .abbreviated, time: .omitted)) · \(age) years")
                            } else {
                                Text(dateOfBirth.formatted(date: .abbreviated, time: .omitted))
                            }
                        }
                    }
                    if profile.sex != .unspecified {
                        LabeledContent("Biological sex", value: profile.sex.displayName)
                    }
                    if let heightCm = profile.heightCm {
                        LabeledContent("Height", value: "\(heightCm.compactFormatted) cm")
                    }
                }
                .font(.subheadline)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private var initials: String? {
        guard let name = profile?.name, !name.isEmpty else { return nil }
        let letters = name
            .split(separator: " ")
            .compactMap { $0.first }
            .prefix(2)
        return String(letters).uppercased()
    }

    // MARK: - Blood type card

    private var bloodTypeCard: some View {
        HStack(spacing: 16) {
            Image(systemName: "drop.fill")
                .font(.title2)
                .foregroundStyle(.red)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text("Blood Type")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                if let bloodType = profile?.bloodType, !bloodType.isEmpty {
                    Text(bloodType)
                        .font(.system(size: 40, weight: .bold))
                } else {
                    Text("Unknown")
                        .font(.system(size: 40, weight: .bold))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .tintedGlassCard(.red)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Allergies card

    private func allergiesCard(_ allergies: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Allergies", systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.orange)
            Text(allergies)
                .font(.body)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .tintedGlassCard(.orange)
    }

    // MARK: - Conditions card

    private func conditionsCard(_ conditions: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Medical Conditions")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(conditions)
                .font(.body)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    // MARK: - Medications card

    private var medicationsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Active Medications")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 8) {
                ForEach(activeMedications) { medication in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(medication.name)
                            .font(.subheadline.weight(.semibold))
                        let detail = [medication.dosage, medication.frequency]
                            .filter { !$0.isEmpty }
                            .joined(separator: " · ")
                        if !detail.isEmpty {
                            Text(detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
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
            lines.append("Blood type: \(profile.bloodType.isEmpty ? "Unknown" : profile.bloodType)")
            if !profile.allergies.isEmpty {
                lines.append("Allergies: \(profile.allergies)")
            }
            if !profile.conditions.isEmpty {
                lines.append("Medical conditions: \(profile.conditions)")
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

        return lines.joined(separator: "\n")
    }
}
