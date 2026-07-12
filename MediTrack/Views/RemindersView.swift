import SwiftUI
import SwiftData

/// Full list of reminders — active and inactive — reachable from the
/// dashboard's "Today" card via its "Manage" link. Supports adding, editing,
/// swipe-to-delete, and pausing/resuming (`isActive`), keeping local
/// notifications in sync via `NotificationService` at every mutation point.
struct RemindersView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Reminder.createdAt) private var reminders: [Reminder]

    @State private var showingAdd = false
    @State private var editingReminder: Reminder?

    private var activeReminders: [Reminder] {
        reminders.filter(\.isActive)
    }

    private var inactiveReminders: [Reminder] {
        reminders.filter { !$0.isActive }
    }

    var body: some View {
        Group {
            if reminders.isEmpty {
                ContentUnavailableView {
                    Label("No Reminders", systemImage: "bell.badge")
                } description: {
                    Text("Add a reminder for medications, checkups, or healthy habits you want to keep track of.")
                } actions: {
                    Button("Add Reminder") { showingAdd = true }
                        .buttonStyle(GlassProminentButtonStyle())
                        .frame(maxWidth: 220)
                }
            } else {
                List {
                    if !activeReminders.isEmpty {
                        Section("Active") {
                            ForEach(activeReminders) { reminder in
                                ReminderListRow(
                                    reminder: reminder,
                                    streak: ReminderStreak.current(for: reminder),
                                    onTap: { editingReminder = reminder },
                                    onToggleActive: { setActive(reminder, isActive: $0) }
                                )
                            }
                            .onDelete { offsets in
                                delete(offsets, from: activeReminders)
                            }
                        }
                        .listRowBackground(GlassRowBackground())
                        .listRowSeparator(.hidden)
                    }
                    if !inactiveReminders.isEmpty {
                        Section("Inactive") {
                            ForEach(inactiveReminders) { reminder in
                                ReminderListRow(
                                    reminder: reminder,
                                    streak: ReminderStreak.current(for: reminder),
                                    onTap: { editingReminder = reminder },
                                    onToggleActive: { setActive(reminder, isActive: $0) }
                                )
                            }
                            .onDelete { offsets in
                                delete(offsets, from: inactiveReminders)
                            }
                        }
                        .listRowBackground(GlassRowBackground())
                        .listRowSeparator(.hidden)
                    }
                }
            }
        }
        .ambientScreen()
        .navigationTitle("Reminders")
        .toolbar {
            Button {
                showingAdd = true
            } label: {
                Image(systemName: "plus")
            }
            .accessibilityLabel("Add reminder")
        }
        .sheet(isPresented: $showingAdd) { AddReminderSheet() }
        .sheet(item: $editingReminder) { reminder in
            AddReminderSheet(reminder: reminder)
        }
    }

    private func delete(_ offsets: IndexSet, from list: [Reminder]) {
        for index in offsets {
            NotificationService.cancelReminder(id: list[index].reminderID)
            modelContext.delete(list[index])
        }
    }

    /// Pauses or resumes a reminder. Pausing always cancels its pending
    /// notification; resuming reschedules it only when a time-of-day is set.
    private func setActive(_ reminder: Reminder, isActive: Bool) {
        reminder.isActive = isActive
        NotificationService.cancelReminder(id: reminder.reminderID)
        guard isActive, let timeOfDay = reminder.timeOfDay else { return }
        let id = reminder.reminderID
        let title = reminder.title
        let body = reminder.detail.isEmpty ? "Time for \(reminder.title)." : reminder.detail
        Task {
            if await NotificationService.requestAuthorization() {
                NotificationService.scheduleDailyReminder(id: id, title: title, body: body, at: timeOfDay)
            }
        }
    }
}

/// Consecutive-day completion streak for a reminder, computed with
/// `Calendar` day math only (never wall-clock string comparisons) so it
/// stays correct across time zones and DST. If the reference day hasn't
/// been completed yet, counting starts from the day before so an
/// in-progress day doesn't zero out an otherwise intact streak.
enum ReminderStreak {
    static func current(for reminder: Reminder, asOf referenceDate: Date = .now, calendar: Calendar = .current) -> Int {
        var day = referenceDate
        if !reminder.isCompleted(on: day, calendar: calendar) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: day) else { return 0 }
            day = yesterday
        }
        var streak = 0
        while reminder.isCompleted(on: day, calendar: calendar) {
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
        return streak
    }
}

struct ReminderListRow: View {
    let reminder: Reminder
    let streak: Int
    let onTap: () -> Void
    let onToggleActive: (Bool) -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onTap) {
                HStack(spacing: 12) {
                    Image(systemName: reminder.systemImage)
                        .foregroundStyle(Glass.accentGradient)
                        .frame(width: 36, height: 36)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(Glass.bevelStroke, lineWidth: 1)
                        )
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(reminder.title)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                            if reminder.isAISuggested {
                                Image(systemName: "sparkles")
                                    .font(.caption2)
                                    .foregroundStyle(Glass.accentGradient)
                                    .accessibilityHidden(true)
                            }
                        }
                        if !reminder.detail.isEmpty {
                            Text(reminder.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        HStack(spacing: 6) {
                            if let timeOfDay = reminder.timeOfDay {
                                Label(timeOfDay.formatted(date: .omitted, time: .shortened), systemImage: "bell.fill")
                                    .font(.caption2)
                                    .foregroundStyle(Color.accentColor)
                            }
                            if streak >= 2 {
                                StatusPill(text: "\(streak)-day streak", color: .teal)
                            }
                        }
                        if reminder.isAISuggested && !reminder.suggestionReason.isEmpty {
                            Text(reminder.suggestionReason)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(accessibilityLabel)

            Toggle("", isOn: Binding(
                get: { reminder.isActive },
                set: onToggleActive
            ))
            .labelsHidden()
            .accessibilityLabel("\(reminder.title) active")
        }
        .padding(.vertical, 2)
    }

    private var accessibilityLabel: String {
        var text = reminder.title
        if reminder.isAISuggested { text += ", AI suggested" }
        if let timeOfDay = reminder.timeOfDay {
            text += ", \(timeOfDay.formatted(date: .omitted, time: .shortened))"
        }
        if streak >= 2 {
            text += ", \(streak) day streak"
        }
        return text
    }
}

struct AddReminderSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    private let existingReminder: Reminder?

    @State private var title: String
    @State private var detail: String
    @State private var systemImage: String
    @State private var reminderEnabled: Bool
    @State private var reminderTime: Date

    /// Curated icon choices — kept small and health/habit-relevant rather
    /// than exposing the entire SF Symbols catalog.
    private static let iconOptions = [
        "pills.fill", "bell.fill", "drop.fill", "figure.walk",
        "bed.double.fill", "heart.fill", "cup.and.saucer.fill", "stethoscope",
    ]

    init(reminder: Reminder? = nil) {
        existingReminder = reminder
        _title = State(initialValue: reminder?.title ?? "")
        _detail = State(initialValue: reminder?.detail ?? "")
        _systemImage = State(initialValue: reminder?.systemImage ?? "bell.fill")
        _reminderEnabled = State(initialValue: reminder?.timeOfDay != nil)
        _reminderTime = State(initialValue: reminder?.timeOfDay
            ?? Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: .now) ?? .now)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Reminder") {
                    TextField("Title (e.g. Take Vitamin D)", text: $title)
                    TextField("Detail (optional)", text: $detail, axis: .vertical)
                        .lineLimit(2...4)
                }
                .listRowBackground(GlassRowBackground())
                .listRowSeparator(.hidden)

                Section("Icon") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 12) {
                        ForEach(Self.iconOptions, id: \.self) { icon in
                            iconButton(icon)
                        }
                    }
                    .padding(.vertical, 6)
                }
                .listRowBackground(GlassRowBackground())
                .listRowSeparator(.hidden)

                Section {
                    Toggle("Daily notification", isOn: $reminderEnabled)
                    if reminderEnabled {
                        DatePicker("Time", selection: $reminderTime, displayedComponents: .hourAndMinute)
                    }
                } footer: {
                    Text("MediTrack sends a local notification every day at this time while the reminder is active.")
                }
                .listRowBackground(GlassRowBackground())
                .listRowSeparator(.hidden)

                if let existingReminder, existingReminder.isAISuggested, !existingReminder.suggestionReason.isEmpty {
                    Section {
                        Label(existingReminder.suggestionReason, systemImage: "sparkles")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } header: {
                        Text("Why AI Suggested This")
                    } footer: {
                        Text("This is an educational suggestion, not medical advice — worth discussing with your doctor before changing your routine.")
                    }
                    .listRowBackground(GlassRowBackground())
                    .listRowSeparator(.hidden)
                }
            }
            .ambientScreen()
            .navigationTitle(existingReminder == nil ? "Add Reminder" : "Edit Reminder")
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

    private func iconButton(_ icon: String) -> some View {
        let isSelected = icon == systemImage
        return Button {
            systemImage = icon
        } label: {
            Image(systemName: icon)
                .font(.title3)
                .frame(width: 44, height: 44)
                .foregroundStyle(isSelected ? .white : Color.accentColor)
                .background(
                    Circle().fill(isSelected ? AnyShapeStyle(Glass.accentGradient) : AnyShapeStyle(.ultraThinMaterial))
                )
                .overlay(Circle().strokeBorder(Glass.bevelStroke, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(icon.replacingOccurrences(of: ".", with: " "))
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private func save() {
        let reminder: Reminder
        if let existingReminder {
            reminder = existingReminder
            reminder.title = title.trimmingCharacters(in: .whitespaces)
            reminder.detail = detail.trimmingCharacters(in: .whitespaces)
            reminder.systemImage = systemImage
        } else {
            reminder = Reminder(
                title: title.trimmingCharacters(in: .whitespaces),
                detail: detail.trimmingCharacters(in: .whitespaces),
                systemImage: systemImage
            )
            modelContext.insert(reminder)
        }
        reminder.timeOfDay = reminderEnabled ? reminderTime : nil

        // Reschedule from scratch so edits never leave a stale notification.
        NotificationService.cancelReminder(id: reminder.reminderID)
        if reminderEnabled && reminder.isActive {
            let id = reminder.reminderID
            let notificationTitle = reminder.title
            let body = reminder.detail.isEmpty ? "Time for \(reminder.title)." : reminder.detail
            let time = reminderTime
            Task {
                if await NotificationService.requestAuthorization() {
                    NotificationService.scheduleDailyReminder(id: id, title: notificationTitle, body: body, at: time)
                }
            }
        }
        Haptics.success()
        dismiss()
    }
}
