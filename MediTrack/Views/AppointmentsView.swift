import SwiftUI
import SwiftData

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

    var body: some View {
        HStack(spacing: 12) {
            VStack(spacing: 0) {
                Text(appointment.date.formatted(.dateTime.month(.abbreviated)))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(appointment.date.formatted(.dateTime.day()))
                    .font(.title3.bold())
                    .foregroundStyle(isUpcoming ? Color.accentColor : .secondary)
            }
            .frame(width: 44, height: 44)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Glass.bevelStroke, lineWidth: 1)
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
                Text(appointment.date.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !appointment.doctor.isEmpty || !appointment.location.isEmpty {
                    Text([appointment.doctor, appointment.location].filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 2)
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

    init(appointment: Appointment? = nil) {
        existingAppointment = appointment
        _title = State(initialValue: appointment?.title ?? "")
        _doctor = State(initialValue: appointment?.doctor ?? "")
        _location = State(initialValue: appointment?.location ?? "")
        _date = State(initialValue: appointment?.date
            ?? Calendar.current.date(byAdding: .day, value: 7, to: .now) ?? .now)
        _notes = State(initialValue: appointment?.notes ?? "")
        _reminderEnabled = State(initialValue: appointment?.reminderEnabled ?? true)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Appointment") {
                    TextField("Title (e.g. Cardiology Follow-up)", text: $title)
                    TextField("Doctor", text: $doctor)
                    TextField("Location", text: $location)
                    if existingAppointment == nil {
                        DatePicker("Date & time", selection: $date, in: Date.now...)
                    } else {
                        DatePicker("Date & time", selection: $date)
                    }
                }
                .listRowBackground(GlassRowBackground())
                .listRowSeparator(.hidden)

                Section {
                    Toggle("Remind me the day before", isOn: $reminderEnabled)
                } footer: {
                    Text("MediTrack sends a local notification 24 hours before the appointment.")
                }
                .listRowBackground(GlassRowBackground())
                .listRowSeparator(.hidden)

                Section("Notes") {
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(2...4)
                }
                .listRowBackground(GlassRowBackground())
                .listRowSeparator(.hidden)
            }
            .ambientScreen()
            .navigationTitle(existingAppointment == nil ? "Add Appointment" : "Edit Appointment")
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
