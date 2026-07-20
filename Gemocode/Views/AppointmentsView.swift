import SwiftUI
import SwiftData
import UIKit

struct AppointmentsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @Query(sort: \Appointment.date) private var appointments: [Appointment]

    @State private var showingAdd = false
    @State private var editingAppointment: Appointment?

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
                            Button {
                                editingAppointment = nearestUpcoming
                            } label: {
                                NextAppointmentCard(appointment: nearestUpcoming)
                            }
                            .buttonStyle(.plain)
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
/// draw" block): title, a system-localized countdown tag, doctor/location,
/// and — only when the data actually says so — a note that the day-before
/// reminder is set. No fasting/medication prep steps are shown because
/// `Appointment` has no lab-panel data to derive them from; inventing that
/// checklist would mean fabricating health guidance.
private struct NextAppointmentCard: View {
    let appointment: Appointment

    @Environment(\.colorScheme) private var colorScheme

    /// Locale-aware "in 13 days" / "через 13 дней" — built from
    /// `RelativeDateTimeFormatter` rather than a hand-rolled format string,
    /// so pluralization is always correct for the user's language without
    /// needing a new plural-variant localization key.
    private var countdownText: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: appointment.date, relativeTo: .now)
    }

    private var detailLine: String {
        [appointment.doctor, appointment.location].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private var accessibilityText: String {
        var parts = [appointment.title, appointment.date.formatted(date: .abbreviated, time: .shortened), countdownText]
        if !detailLine.isEmpty { parts.append(detailLine) }
        if appointment.reminderEnabled { parts.append(String(localized: "Reminder set for the night before")) }
        return parts.joined(separator: ", ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(appointment.title)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Editorial.ink(colorScheme))
                Spacer(minLength: 8)
                EditorialTag(verbatim: countdownText, kind: .warn)
            }
            Text(appointment.date.formatted(date: .abbreviated, time: .shortened))
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(Editorial.muted(colorScheme))
            if !detailLine.isEmpty {
                Text(detailLine)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(Editorial.muted(colorScheme))
            }
            if appointment.reminderEnabled {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Editorial.tagGood(colorScheme))
                        .accessibilityHidden(true)
                    Text("Reminder set for the night before")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(Editorial.ink(colorScheme))
                }
                .padding(.top, 4)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Editorial.insetCard(colorScheme), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .padding(.horizontal)
        .padding(.vertical, 8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
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
