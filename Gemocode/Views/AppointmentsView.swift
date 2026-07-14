import SwiftUI
import SwiftData
import UIKit

struct AppointmentsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Appointment.date) private var appointments: [Appointment]

    @State private var showingAdd = false
    @State private var editingAppointment: Appointment?

    private var upcoming: [Appointment] {
        appointments.filter(\.isUpcoming)
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
                    if !upcoming.isEmpty {
                        Section("Upcoming") {
                            ForEach(upcoming) { appointment in
                                Button {
                                    editingAppointment = appointment
                                } label: {
                                    AppointmentRow(appointment: appointment, isUpcoming: true)
                                }
                                .buttonStyle(.plain)
                            }
                            .onDelete { offsets in
                                delete(offsets, from: upcoming)
                            }
                        }
                        .listRowBackground(GlassRowBackground())
                        .listRowSeparator(.hidden)
                    }
                    if !past.isEmpty {
                        Section("Past") {
                            ForEach(past) { appointment in
                                Button {
                                    editingAppointment = appointment
                                } label: {
                                    AppointmentRow(appointment: appointment, isUpcoming: false)
                                }
                                .buttonStyle(.plain)
                            }
                            .onDelete { offsets in
                                delete(offsets, from: past)
                            }
                        }
                        .listRowBackground(GlassRowBackground())
                        .listRowSeparator(.hidden)
                    }
                }
            }
        }
        .ambientScreen()
        .navigationTitle("Appointments")
        .toolbar {
            Button {
                showingAdd = true
            } label: {
                Image(systemName: "plus")
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
}

struct AppointmentRow: View {
    let appointment: Appointment
    let isUpcoming: Bool

    /// Rotating date-chip tints — cycles deterministically per appointment so
    /// the list reads as a set of distinct cards. The color carries no
    /// semantic meaning (unlike vitals, where tint encodes reading type).
    private static let tintPalette: [Color] = [
        Color(red: 0x5E / 255, green: 0x5C / 255, blue: 0xE6 / 255), // indigo
        Color(red: 0x40 / 255, green: 0xC8 / 255, blue: 0xE0 / 255), // teal
        Color(red: 0x0A / 255, green: 0x84 / 255, blue: 0xFF / 255), // blue
        Color(red: 0xBF / 255, green: 0x5A / 255, blue: 0xF2 / 255), // purple
    ]

    private var tint: Color {
        Self.tintPalette[stableIndex(appointment.reminderID, count: Self.tintPalette.count)]
    }

    var body: some View {
        HStack(spacing: 13) {
            VStack(spacing: 2) {
                Text(appointment.date.formatted(.dateTime.day()))
                    .font(.title3.weight(.heavy))
                    .foregroundStyle(tint)
                Text(appointment.date.formatted(.dateTime.month(.abbreviated)))
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(tint)
                    .textCase(.uppercase)
            }
            .frame(width: 48, height: 52)
            .background(tint.opacity(0.16), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(tint.opacity(0.32), lineWidth: 1)
            )
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(appointment.title)
                        .font(.subheadline.weight(.semibold))
                    if isUpcoming && appointment.reminderEnabled {
                        Image(systemName: "bell.fill")
                            .font(.caption2)
                            .foregroundStyle(Color.accentColor)
                            .accessibilityLabel("Reminder on")
                    }
                }
                if !appointment.doctor.isEmpty {
                    Text(appointment.doctor)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if !appointment.location.isEmpty {
                    Text(appointment.location)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer(minLength: 8)

            Text(appointment.date.formatted(date: .omitted, time: .shortened))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
        .opacity(isUpcoming ? 1 : 0.55)
        .accessibilityElement(children: .combine)
    }
}

/// Deterministic (non-randomized) index into a fixed-size palette. Swift's
/// `String.hashValue` uses a per-process random seed, so it would make the
/// assigned tint drift between app launches for the same appointment — this
/// stays stable for the life of the record.
private func stableIndex(_ text: String, count: Int) -> Int {
    var hash = 5381
    for scalar in text.unicodeScalars {
        hash = ((hash << 5) &+ hash) &+ Int(scalar.value)
    }
    return abs(hash) % count
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
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
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
                appointment.doctor.isEmpty ? nil : "with \(appointment.doctor)",
                "at \(date.formatted(date: .omitted, time: .shortened))",
            ].compactMap { $0 }.joined(separator: " ")
            let fireDate = date.addingTimeInterval(-86_400)
            Task {
                if await NotificationService.requestAuthorization() {
                    NotificationService.scheduleOneTime(
                        id: id,
                        title: "Appointment Tomorrow",
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
    let title: String
    let subtitle: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.title2.weight(.semibold))
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
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text.uppercased())
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
    }
}

/// Tappable capsule chip used to fill a field without typing.
private struct SuggestionChip: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

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
                .background(isSelected ? Color.accentColor.opacity(0.22) : Color.clear, in: Capsule())
                .overlay(
                    Capsule().strokeBorder(
                        isSelected ? Color.accentColor.opacity(0.7) : Color.primary.opacity(0.12),
                        lineWidth: 1
                    )
                )
                .foregroundStyle(isSelected ? Color.accentColor : .primary)
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
