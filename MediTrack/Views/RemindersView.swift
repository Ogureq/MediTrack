import SwiftUI
import SwiftData
import UIKit

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

    @State private var showingDetails: Bool

    private static let timePresets: [(label: String, hour: Int, minute: Int)] = [
        ("Morning 8:00", 8, 0), ("Noon", 12, 0), ("Evening 20:00", 20, 0),
    ]

    init(reminder: Reminder? = nil) {
        existingReminder = reminder
        _title = State(initialValue: reminder?.title ?? "")
        _detail = State(initialValue: reminder?.detail ?? "")
        _systemImage = State(initialValue: reminder?.systemImage ?? "bell.fill")
        _reminderEnabled = State(initialValue: reminder?.timeOfDay != nil)
        _reminderTime = State(initialValue: reminder?.timeOfDay
            ?? Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: .now) ?? .now)
        _showingDetails = State(initialValue: !(reminder?.detail ?? "").isEmpty)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    SheetHeader(
                        icon: systemImage,
                        tint: .indigo,
                        title: existingReminder == nil ? "Add Reminder" : "Edit Reminder",
                        subtitle: "Keep track of medications, checkups, or habits."
                    )

                    VStack(alignment: .leading, spacing: 14) {
                        SheetFieldLabel("Title")
                        TextField("e.g. Take Vitamin D", text: $title)
                            .font(.body)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassCard()

                    VStack(alignment: .leading, spacing: 12) {
                        SheetFieldLabel("Icon")
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 12) {
                            ForEach(Self.iconOptions, id: \.self) { icon in
                                iconButton(icon)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassCard()

                    VStack(alignment: .leading, spacing: 12) {
                        Toggle("Daily notification", isOn: $reminderEnabled.animation())
                            .font(.body.weight(.semibold))
                        if reminderEnabled {
                            DatePicker("Time", selection: $reminderTime, displayedComponents: .hourAndMinute)
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(Self.timePresets, id: \.label) { preset in
                                        SuggestionChip(label: preset.label, isSelected: false) {
                                            setTime(hour: preset.hour, minute: preset.minute)
                                        }
                                    }
                                }
                            }
                        }
                        Text("MediTrack sends a local notification every day at this time while the reminder is active.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassCard()

                    if let existingReminder, existingReminder.isAISuggested, !existingReminder.suggestionReason.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Why AI Suggested This", systemImage: "sparkles")
                                .font(.subheadline.weight(.semibold))
                            Text(existingReminder.suggestionReason)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            Text("This is an educational suggestion, not medical advice — worth discussing with your doctor before changing your routine.")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .tintedGlassCard(.purple, cornerRadius: Glass.cardRadius)
                    }

                    DisclosureGroup("Add details", isExpanded: $showingDetails) {
                        VStack(alignment: .leading, spacing: 10) {
                            SheetFieldLabel("Detail")
                            TextField("Detail (optional)", text: $detail, axis: .vertical)
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
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(.ultraThinMaterial)
    }

    private func setTime(hour: Int, minute: Int) {
        SheetHaptics.selection()
        reminderTime = Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: .now) ?? reminderTime
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
