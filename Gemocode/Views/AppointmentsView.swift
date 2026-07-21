import SwiftUI
import SwiftData
import UIKit
import UniformTypeIdentifiers
import CoreTransferable

struct AppointmentsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @Query(sort: \Appointment.date) private var appointments: [Appointment]
    @Query(sort: \MedicalReport.date, order: .reverse) private var reports: [MedicalReport]
    @Query private var medications: [Medication]

    @State private var showingAdd = false
    @State private var editingAppointment: Appointment?

    /// The next-draw bundle — used to decide whether the featured
    /// appointment's prep checklist should include a fasting note (see
    /// `NextAppointmentCard`). Cached the same way `DashboardView`/
    /// `RetestScheduleView` cache their own copy: rebuilding it flattens
    /// every report's lab results, wasted work to redo on every render.
    @State private var drawBundle: DrawBundle?

    private var retestSignature: String {
        "\(reports.count)-\(reports.reduce(0) { $0 + $1.labResults.count })"
    }

    private var activeMedications: [Medication] {
        medications.filter(\.isActive)
    }

    private var upcoming: [Appointment] {
        appointments.filter(\.isUpcoming)
    }

    /// The single nearest upcoming appointment, featured as an inset card
    /// (7p's "next draw" block) — everything else upcoming moves to the
    /// flat "Later" ledger below it.
    private var nearestUpcoming: Appointment? {
        upcoming.first
    }

    private var laterUpcoming: [Appointment] {
        Array(upcoming.dropFirst())
    }

    private var past: [Appointment] {
        appointments.filter { !$0.isUpcoming }.reversed()
    }

    var body: some View {
        Group {
            if appointments.isEmpty {
                ContentUnavailableView {
                    Label("No Appointments", systemImage: "calendar.badge.plus")
                } description: {
                    Text("Keep track of checkups and follow-ups, with an optional reminder the day before.")
                } actions: {
                    Button("Add Appointment") { showingAdd = true }
                        .buttonStyle(GlassProminentButtonStyle())
                        .frame(maxWidth: 220)
                }
            } else {
                List {
                    if let nearestUpcoming {
                        Section {
                            NextAppointmentCard(
                                appointment: nearestUpcoming,
                                drawBundle: drawBundle,
                                activeMedications: activeMedications,
                                onEdit: { editingAppointment = nearestUpcoming }
                            )
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    deleteOne(nearestUpcoming)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets())
                    }
                    if !laterUpcoming.isEmpty {
                        Section {
                            ForEach(laterUpcoming) { appointment in
                                Button {
                                    editingAppointment = appointment
                                } label: {
                                    AppointmentRow(appointment: appointment, isUpcoming: true)
                                        .ledgerRow()
                                }
                                .buttonStyle(.plain)
                            }
                            .onDelete { offsets in
                                delete(offsets, from: laterUpcoming)
                            }
                        } header: {
                            MicroLabel("Later")
                        }
                        .listRowBackground(GlassRowBackground())
                        .listRowSeparator(.hidden)
                    }
                    if !past.isEmpty {
                        Section {
                            ForEach(past) { appointment in
                                Button {
                                    editingAppointment = appointment
                                } label: {
                                    AppointmentRow(appointment: appointment, isUpcoming: false)
                                        .ledgerRow()
                                }
                                .buttonStyle(.plain)
                            }
                            .onDelete { offsets in
                                delete(offsets, from: past)
                            }
                        } header: {
                            MicroLabel("Past")
                        }
                        .listRowBackground(GlassRowBackground())
                        .listRowSeparator(.hidden)
                    }
                }
                .listStyle(.plain)
            }
        }
        .ambientScreen()
        .navigationTitle("Appointments")
        .toolbar {
            Button {
                showingAdd = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(Editorial.ink(colorScheme))
                    .frame(width: 28, height: 28)
                    .overlay(Circle().strokeBorder(Editorial.controlBorder(colorScheme), lineWidth: 1))
            }
            .accessibilityLabel("Add appointment")
        }
        .sheet(isPresented: $showingAdd) { AddAppointmentSheet() }
        .sheet(item: $editingAppointment) { appointment in
            AddAppointmentSheet(appointment: appointment)
        }
        .task(id: retestSignature) {
            let items = RetestSchedule.items(reports: reports, now: .now)
            drawBundle = RetestSchedule.nextDraw(items: items, now: .now)
        }
    }

    private func delete(_ offsets: IndexSet, from list: [Appointment]) {
        for index in offsets {
            NotificationService.cancelReminder(id: list[index].reminderID)
            modelContext.delete(list[index])
        }
    }

    private func deleteOne(_ appointment: Appointment) {
        NotificationService.cancelReminder(id: appointment.reminderID)
        modelContext.delete(appointment)
    }
}

/// Featured inset card for the nearest upcoming appointment (7p's "next
/// draw" block): title, a countdown tag/plain label, doctor/location, a
/// prep checklist computed from real data (fasting + per-medication timing
/// notes, only when they actually apply — see `prepLines`), and an "Add to
/// calendar" CTA wired to `CalendarService`.
private struct NextAppointmentCard: View {
    let appointment: Appointment
    /// The current next-draw bundle, if any — used only to decide whether
    /// this appointment coincides with a fasting blood draw (see
    /// `fastingNoteNeeded`) and which bundled labs an active medication
    /// might be linked to (see `medicationPrepLines`). `nil` when there's
    /// no tracked lab data yet.
    let drawBundle: DrawBundle?
    let activeMedications: [Medication]
    /// Opens the edit sheet — called only from the tappable header block,
    /// never from the "Add to calendar" CTA below it.
    let onEdit: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    @State private var calendarState: CalendarAddState = .idle
    @State private var showingCalendarFallback = false
    @State private var calendarErrorMessage = ""

    private enum CalendarAddState: Equatable {
        case idle
        case adding
        case added
    }

    /// Locale-aware "in 13 days" / "через 13 дней" — built from
    /// `RelativeDateTimeFormatter` rather than a hand-rolled format string,
    /// so pluralization is always correct for the user's language without
    /// needing a new plural-variant localization key.
    private var countdownText: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: appointment.date, relativeTo: .now)
    }

    /// Whole calendar days from today to the appointment (via `startOfDay`,
    /// like `RetestSchedule`'s own day-difference math) — used only to pick
    /// the countdown tag's urgency, not to re-derive its text.
    private var daysUntil: Int {
        Calendar.current.dateComponents(
            [.day],
            from: Calendar.current.startOfDay(for: .now),
            to: Calendar.current.startOfDay(for: appointment.date)
        ).day ?? 0
    }

    private var detailLine: String {
        [appointment.doctor, appointment.location].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    /// `true` only when the bundle actually requires fasting AND this
    /// appointment falls within a day of the bundle's own draw date — a
    /// same-day-ish coincidence, not just "there's some fasting test due
    /// eventually."
    private var fastingNoteNeeded: Bool {
        guard let drawBundle, drawBundle.requiresFasting else { return false }
        let days = Calendar.current.dateComponents(
            [.day],
            from: Calendar.current.startOfDay(for: appointment.date),
            to: Calendar.current.startOfDay(for: drawBundle.date)
        ).day ?? Int.max
        return abs(days) <= 1
    }

    private var bundledLabIDs: Set<String> {
        Set((drawBundle?.items ?? []).map { $0.id.lowercased() })
    }

    /// "Ask your doctor when to take X around the draw" — one line per
    /// active medication whose `CareLinks.MedicationLabLinks` monitoring
    /// lab is actually in this bundle. Read-only lookup: never mutates or
    /// caches anything, matching `MedicationLabLinks`'s pure/deterministic
    /// contract.
    private var medicationPrepLines: [String] {
        guard !bundledLabIDs.isEmpty else { return [] }
        return activeMedications.compactMap { medication in
            guard let link = MedicationLabLinks.link(for: medication.name),
                  link.labIDs.contains(where: { bundledLabIDs.contains($0.lowercased()) }) else { return nil }
            return String(format: String(localized: "Ask your doctor when to take %@ around the draw"), medication.name)
        }
    }

    /// The full checklist, in mockup order: fasting, then medication
    /// timing notes, then the existing reminder line.
    private var prepLines: [String] {
        var lines: [String] = []
        if fastingNoteNeeded {
            lines.append(String(localized: "Fast 10–12 hours — water is fine"))
        }
        lines.append(contentsOf: medicationPrepLines)
        if appointment.reminderEnabled {
            lines.append(String(localized: "Reminder set for the night before"))
        }
        return lines
    }

    private var icsNotes: String? {
        prepLines.isEmpty ? nil : prepLines.joined(separator: "\n")
    }

    private var accessibilityText: String {
        var parts = [appointment.title, appointment.date.formatted(date: .abbreviated, time: .shortened), countdownText]
        if !detailLine.isEmpty { parts.append(detailLine) }
        parts.append(contentsOf: prepLines)
        return parts.joined(separator: ", ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(action: onEdit) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(appointment.title)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(Editorial.ink(colorScheme))
                        Spacer(minLength: 8)
                        countdownTag
                    }
                    Text(appointment.date.formatted(date: .abbreviated, time: .shortened))
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(Editorial.muted(colorScheme))
                    if !detailLine.isEmpty {
                        Text(detailLine)
                            .font(.system(size: 12, weight: .regular))
                            .foregroundStyle(Editorial.muted(colorScheme))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityText)
            .accessibilityHint("Opens this appointment for editing.")

            if !prepLines.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(prepLines, id: \.self) { line in
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Editorial.tagGood(colorScheme))
                                .accessibilityHidden(true)
                            Text(verbatim: line)
                                .font(.system(size: 13, weight: .regular))
                                .foregroundStyle(Editorial.ink(colorScheme))
                        }
                        .padding(.vertical, 3)
                    }
                }
                .accessibilityHidden(true) // already read via `accessibilityText` above
            }

            calendarButton
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Editorial.insetCard(colorScheme), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .padding(.horizontal)
        .padding(.vertical, 8)
        .confirmationDialog(
            calendarErrorMessage,
            isPresented: $showingCalendarFallback,
            titleVisibility: .visible
        ) {
            ShareLink(item: ICSFile(data: icsData), preview: SharePreview(appointment.title)) {
                Text("Export as Calendar File")
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    /// Warm/urgent tag inside 14 days, plain muted text otherwise — the
    /// same countdown text either way, just a quieter presentation once
    /// it's not imminent.
    @ViewBuilder
    private var countdownTag: some View {
        if daysUntil <= 14 {
            EditorialTag(verbatim: countdownText, kind: .warn)
        } else {
            Text(verbatim: countdownText)
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(Editorial.muted(colorScheme))
        }
    }

    @ViewBuilder
    private var calendarButton: some View {
        switch calendarState {
        case .added:
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Editorial.tagGood(colorScheme))
                    .accessibilityHidden(true)
                Text("Added")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Editorial.ink(colorScheme))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Added to calendar"))
        case .idle, .adding:
            Button {
                addToCalendar()
            } label: {
                if calendarState == .adding {
                    ProgressView()
                        .tint(.white)
                        .frame(maxWidth: .infinity)
                } else {
                    Text("Add to Calendar")
                }
            }
            .buttonStyle(GlassProminentButtonStyle())
            .disabled(calendarState == .adding)
        }
    }

    private var icsData: Data {
        CalendarService.icsData(
            title: appointment.title,
            date: appointment.date,
            notes: icsNotes,
            location: appointment.location.isEmpty ? nil : appointment.location
        )
    }

    private func addToCalendar() {
        calendarState = .adding
        Task {
            do {
                let added = try await CalendarService.addEvent(
                    title: appointment.title,
                    date: appointment.date,
                    notes: icsNotes,
                    location: appointment.location.isEmpty ? nil : appointment.location
                )
                calendarState = added ? .added : .idle
            } catch let error as CalendarService.CalendarError {
                calendarState = .idle
                calendarErrorMessage = error.errorDescription ?? String(localized: "The event could not be saved to your calendar.")
                showingCalendarFallback = true
            } catch {
                calendarState = .idle
            }
        }
    }
}

// MARK: - ICS ShareLink fallback

/// Lets a `ShareLink` hand `CalendarService.icsData` to any calendar app —
/// the fallback offered when `CalendarService.addEvent` throws `.denied`/
/// `.restricted`. Data is available synchronously (no lazy rendering
/// needed, unlike `ScoreShareImage`'s PNG export).
private struct ICSFile: Transferable {
    let data: Data

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .icsCalendarFile) { file in
            file.data
        }
        .suggestedFileName("appointment.ics")
    }
}

private extension UTType {
    /// `.ics` isn't one of Foundation's built-in `UTType` constants, so
    /// it's resolved from the system-registered file-extension UTI (every
    /// iOS version in this app's deployment target recognizes ".ics").
    static var icsCalendarFile: UTType {
        UTType(filenameExtension: "ics") ?? .data
    }
}

struct AppointmentRow: View {
    let appointment: Appointment
    let isUpcoming: Bool

    @Environment(\.colorScheme) private var colorScheme

    private var detailLine: String {
        var parts = [appointment.date.formatted(date: .abbreviated, time: .omitted)]
        if !appointment.doctor.isEmpty { parts.append(appointment.doctor) }
        if !appointment.location.isEmpty { parts.append(appointment.location) }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(appointment.title)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Editorial.ink(colorScheme))
                    if isUpcoming && appointment.reminderEnabled {
                        Image(systemName: "bell.fill")
                            .font(.caption2)
                            .foregroundStyle(Editorial.accent(colorScheme))
                            .accessibilityLabel("Reminder on")
                    }
                }
                Text(detailLine)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(Editorial.muted(colorScheme))
            }

            Spacer(minLength: 8)

            if isUpcoming {
                Text(appointment.date.formatted(date: .omitted, time: .shortened))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Editorial.muted(colorScheme))
            } else {
                EditorialTag("Done", kind: .good)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct AddAppointmentSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    private let existingAppointment: Appointment?

    @State private var title: String
    @State private var doctor: String
    @State private var location: String
    @State private var date: Date
    @State private var notes: String
    @State private var reminderEnabled: Bool
    @State private var showingDetails: Bool
    /// Guards `save()` against a double tap firing two inserts before the
    /// sheet has dismissed — checked and set at the top of `save()`, and
    /// mirrored onto the Save button's `disabled` state.
    @State private var isSaving = false

    private static let quickDateOptions: [(label: String, days: Int)] = [
        ("Tomorrow", 1), ("In 3 Days", 3), ("Next Week", 7),
    ]

    init(appointment: Appointment? = nil) {
        existingAppointment = appointment
        _title = State(initialValue: appointment?.title ?? "")
        _doctor = State(initialValue: appointment?.doctor ?? "")
        _location = State(initialValue: appointment?.location ?? "")
        _date = State(initialValue: appointment?.date
            ?? Calendar.current.date(byAdding: .day, value: 7, to: .now) ?? .now)
        _notes = State(initialValue: appointment?.notes ?? "")
        _reminderEnabled = State(initialValue: appointment?.reminderEnabled ?? true)
        _showingDetails = State(initialValue: !(appointment?.doctor ?? "").isEmpty
            || !(appointment?.location ?? "").isEmpty
            || !(appointment?.notes ?? "").isEmpty)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    SheetHeader(
                        icon: "calendar.badge.plus",
                        tint: .purple,
                        title: existingAppointment == nil ? "Add Appointment" : "Edit Appointment",
                        subtitle: "Keep track of checkups and follow-ups."
                    )

                    VStack(alignment: .leading, spacing: 14) {
                        SheetFieldLabel("Title")
                        TextField("e.g. Cardiology Follow-up", text: $title)
                            .font(.body)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassCard()

                    VStack(alignment: .leading, spacing: 12) {
                        SheetFieldLabel("Date & Time")
                        if existingAppointment == nil {
                            DatePicker("Date & time", selection: $date, in: Date.now...)
                                .labelsHidden()
                        } else {
                            DatePicker("Date & time", selection: $date)
                                .labelsHidden()
                        }
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(Self.quickDateOptions, id: \.label) { option in
                                    SuggestionChip(label: option.label, isSelected: false) {
                                        quickDate(addingDays: option.days)
                                    }
                                }
                            }
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassCard()

                    VStack(alignment: .leading, spacing: 10) {
                        Toggle("Remind me the day before", isOn: $reminderEnabled)
                            .font(.body.weight(.semibold))
                        Text("Gemocode sends a local notification 24 hours before the appointment.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassCard()

                    DisclosureGroup("Add details", isExpanded: $showingDetails) {
                        VStack(alignment: .leading, spacing: 14) {
                            SheetFieldLabel("Doctor")
                            TextField("Doctor", text: $doctor)
                                .font(.body)

                            SheetFieldLabel("Location")
                            TextField("Location", text: $location)
                                .font(.body)

                            SheetFieldLabel("Notes")
                            TextField("Notes", text: $notes, axis: .vertical)
                                .font(.body)
                                .lineLimit(2...4)
                        }
                        .padding(.top, 12)
                    }
                    .font(.subheadline.weight(.semibold))
                    .tint(.primary)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassCard()
                }
                .padding()
            }
            .ambientScreen()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(.ultraThinMaterial)
    }

    /// Sets the date to N days from now, preserving today's time-of-day —
    /// matching the same convention the default `date` initializer uses.
    private func quickDate(addingDays days: Int) {
        SheetHaptics.selection()
        date = Calendar.current.date(byAdding: .day, value: days, to: .now) ?? .now
    }

    private func save() {
        guard !isSaving else { return }
        isSaving = true
        let appointment: Appointment
        if let existingAppointment {
            appointment = existingAppointment
            appointment.title = title.trimmingCharacters(in: .whitespaces)
            appointment.doctor = doctor.trimmingCharacters(in: .whitespaces)
            appointment.location = location.trimmingCharacters(in: .whitespaces)
            appointment.date = date
            appointment.notes = notes
            appointment.reminderEnabled = reminderEnabled
        } else {
            appointment = Appointment(
                title: title.trimmingCharacters(in: .whitespaces),
                doctor: doctor.trimmingCharacters(in: .whitespaces),
                location: location.trimmingCharacters(in: .whitespaces),
                date: date,
                notes: notes,
                reminderEnabled: reminderEnabled
            )
            modelContext.insert(appointment)
        }

        // Reschedule from scratch so edits never leave a stale notification.
        NotificationService.cancelReminder(id: appointment.reminderID)
        if reminderEnabled && date > .now {
            let id = appointment.reminderID
            let body = [
                appointment.title,
                appointment.doctor.isEmpty ? nil : String(format: String(localized: "with %@"), appointment.doctor),
                String(format: String(localized: "at %@"), date.formatted(date: .omitted, time: .shortened)),
            ].compactMap { $0 }.joined(separator: " ")
            let fireDate = date.addingTimeInterval(-86_400)
            Task {
                if await NotificationService.requestAuthorization() {
                    NotificationService.scheduleOneTime(
                        id: id,
                        title: String(localized: "Appointment Tomorrow"),
                        body: body,
                        at: fireDate
                    )
                }
            }
        }
        Haptics.success()
        dismiss()
    }
}

// MARK: - Shared sheet UI

/// Friendly header shown at the top of the add/edit sheet: a tinted icon
/// tile plus a bold title and one-line subtitle, replacing a bare nav title.
private struct SheetHeader: View {
    let icon: String
    let tint: Color
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 52, height: 52)
                .background(tint.gradient, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.title2.bold())
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// Small uppercase caption used above a field inside a glass block.
private struct SheetFieldLabel: View {
    let text: LocalizedStringKey

    init(_ text: LocalizedStringKey) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .textCase(.uppercase)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
    }
}

/// Tappable capsule chip used to fill a field without typing.
private struct SuggestionChip: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button {
            SheetHaptics.selection()
            action()
        } label: {
            Text(label)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(.ultraThinMaterial, in: Capsule())
                .background(isSelected ? Editorial.accent(colorScheme).opacity(0.22) : Color.clear, in: Capsule())
                .overlay(
                    Capsule().strokeBorder(
                        isSelected ? Editorial.accent(colorScheme).opacity(0.7) : Editorial.controlBorder(colorScheme),
                        lineWidth: 1
                    )
                )
                .foregroundStyle(isSelected ? Editorial.accent(colorScheme) : Editorial.ink(colorScheme))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

/// Light selection feedback for chip taps — UIHelpers only defines the
/// success notification haptic, so this stays local to each sheet file.
private enum SheetHaptics {
    static func selection() {
        UISelectionFeedbackGenerator().selectionChanged()
    }
}
