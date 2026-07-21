import SwiftUI
import SwiftData

/// The dedicated supplements page: a ledger of every supplement-classified
/// `Medication` — most from `SupplementPlanApplier`'s auto-add (see
/// `ScanReportView`'s post-save stage and `ActionPlanView`'s "Add Plan + Set
/// Reminders"), but this view shows any medication that classifies as a
/// supplement regardless of how it was added, mirroring
/// `MedicationsView`'s own "Supplements — from your plan" section (which
/// this view intentionally duplicates the classification rule from, rather
/// than editing that read-only file).
///
/// Reachable from `ActionPlanView`'s "View Supplements" link; other entry
/// points (a "More" grid tile, a dashboard shortcut, ...) are wired by
/// whichever pass owns those files — this type is left with a plain,
/// argument-less initializer specifically so any of them can construct
/// `SupplementsView()` directly.
struct SupplementsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @Query(sort: \Medication.startDate, order: .reverse) private var medications: [Medication]
    @Query(sort: \MedicalReport.date, order: .reverse) private var reports: [MedicalReport]

    init() {}

    // MARK: - Classification (mirrors MedicationsView.isSupplement — read-only reference)
    //
    // Duplicated rather than shared: `MedicationsView.swift` is owned by a
    // different pass in this same wave and is read-only here. Kept
    // byte-identical in spirit — same drug-key check, same keyword list — so
    // a medication that shows under "Supplements — from your plan" there
    // also shows up here, and nowhere else.

    private static let supplementKeywordTokens: [String] = [
        "vitamin", "витамин", "supplement", "добавка", "добавки",
        "iron", "железо", "magnesium", "магний",
        "folate", "folic", "фолиев", "фолат",
        "calcium", "кальций", "zinc", "цинк",
        "omega", "омега", "fish oil", "рыбий жир",
        "probiotic", "пробиотик", "multivitamin", "мультивитамин",
    ]

    private static func isSupplement(_ medication: Medication) -> Bool {
        if let key = MedicationLabLinks.drugKey(for: medication.name),
           key == "ironSupplement" || key == "vitaminDSupplement" {
            return true
        }
        let lower = medication.name.lowercased()
        return supplementKeywordTokens.contains { lower.contains($0) }
    }

    /// Active supplement-classified medications only — a page about
    /// "what am I currently taking and when's the retest" has nothing
    /// useful to say about a supplement that's already ended.
    private var supplements: [Medication] {
        medications.filter { $0.isActive && Self.isSupplement($0) }
    }

    /// Full retest schedule (not just overdue/due-soon) — this page wants
    /// "next retest date" for every linked lab regardless of urgency.
    private var retestItems: [RetestItem] {
        RetestSchedule.items(reports: reports, now: .now)
    }

    var body: some View {
        Group {
            if supplements.isEmpty {
                ContentUnavailableView(
                    "Scan bloodwork — needed supplements are added automatically.",
                    systemImage: "pills"
                )
            } else {
                let items = retestItems
                List {
                    Section {
                        ForEach(supplements) { medication in
                            supplementRow(medication, retestItems: items)
                        }
                        .onDelete(perform: delete)
                    } footer: {
                        Text(ActionPlan.disclaimer)
                            .font(.system(size: 13))
                    }
                    .listRowBackground(GlassRowBackground())
                    .listRowSeparator(.hidden)
                }
                .listStyle(.plain)
            }
        }
        .ambientScreen()
        .navigationTitle("Supplements")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Row

    private func supplementRow(_ medication: Medication, retestItems: [RetestItem]) -> some View {
        let linkedLabID = MedicationLabLinks.link(for: medication.name)?.primaryLabID
        let retestDate = linkedLabID.flatMap { labID in
            retestItems.first { $0.id.caseInsensitiveCompare(labID) == .orderedSame }?.dueDate
        }

        return HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                Text(medication.name)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Editorial.ink(colorScheme))
                if !medication.dosage.isEmpty || !medication.frequency.isEmpty {
                    Text([medication.dosage, medication.frequency].filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.system(size: 13))
                        .foregroundStyle(Editorial.muted(colorScheme))
                }
                HStack(spacing: 8) {
                    if let linkedLabID {
                        labChip(linkedLabID)
                    }
                    if let retestDate {
                        Text("Retest \(retestDate.formatted(date: .abbreviated, time: .omitted))")
                            .font(.system(size: 13))
                            .foregroundStyle(Editorial.muted(colorScheme))
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            reminderBellToggle(medication)
        }
        .ledgerRow()
        .accessibilityElement(children: .combine)
    }

    /// The linked-lab accent chip — CareLinks' (`Services/CareLinks.swift`)
    /// `MedicationLabLinks.link(for:)` resolved once by the caller, styled
    /// as a small filled-accent capsule (rather than the plain underlined
    /// link `MedicationsView.labChipText` uses) so it reads as a genuine
    /// chip on this page, and pushes to the same `LabDetailView` every other
    /// lab chip in the app opens.
    private func labChip(_ linkedLabID: String) -> some View {
        let shortName = LabCatalog.reference(for: linkedLabID)?.shortName ?? linkedLabID
        return NavigationLink {
            LabDetailView(seriesKey: linkedLabID)
        } label: {
            Text("\(shortName) ↗")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Editorial.accent(colorScheme))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Editorial.accent(colorScheme).opacity(0.12), in: Capsule())
        }
        .accessibilityLabel("View \(shortName) lab detail")
    }

    /// Per-row reminder toggle — the existing reminder mechanics
    /// (`Medication.reminderEnabled`/`reminderTime`, `NotificationService`'s
    /// authorize-then-schedule pattern, `cancelReminder` on turn-off) as a
    /// single tap instead of opening the edit sheet.
    private func reminderBellToggle(_ medication: Medication) -> some View {
        Button {
            toggleReminder(medication)
        } label: {
            Image(systemName: medication.reminderEnabled ? "bell.fill" : "bell.slash")
                .font(.system(size: 15))
                .foregroundStyle(medication.reminderEnabled ? Editorial.accent(colorScheme) : Editorial.muted(colorScheme))
                .frame(width: 32, height: 32)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(medication.reminderEnabled ? Text("Reminder on") : Text("Reminder off"))
        // Two full, separately-localizable strings rather than one string
        // interpolating a raw "off"/"on" substring — a translator needs to
        // see and translate the whole sentence in each state, not have an
        // untranslated English word spliced into an otherwise-localized one.
        .accessibilityHint(medication.reminderEnabled
            ? Text("Double tap to turn the daily reminder off.")
            : Text("Double tap to turn the daily reminder on."))
    }

    private func toggleReminder(_ medication: Medication) {
        medication.reminderEnabled.toggle()
        NotificationService.cancelReminder(id: medication.reminderID)
        guard medication.reminderEnabled else { return }

        if medication.reminderTime == nil {
            medication.reminderTime = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: .now) ?? .now
        }
        let id = medication.reminderID
        let name = medication.name
        let dosage = medication.dosage
        let time = medication.reminderTime ?? .now
        Task {
            if await NotificationService.requestAuthorization() {
                NotificationService.scheduleDailyReminder(id: id, medicationName: name, dosage: dosage, at: time)
            }
        }
    }

    private func delete(_ offsets: IndexSet) {
        let rows = supplements
        for index in offsets {
            NotificationService.cancelReminder(id: rows[index].reminderID)
            modelContext.delete(rows[index])
        }
    }
}
