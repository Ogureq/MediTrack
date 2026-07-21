import SwiftUI
import SwiftData

/// Sheet opened by the "Book" pill on both the Dashboard's next-draw card
/// (`DashboardView.nextDrawInsetCard`) and the Schedule screen's next-draw
/// card (`RetestScheduleView.nextDrawCard`) — on both screens "Book" used to
/// be a dead, no-op button. This sheet turns the suggested `DrawBundle` into
/// a real `Appointment`, mirroring `AppointmentsView.AddAppointmentSheet`'s
/// save/reminder conventions rather than inventing a new one.
///
/// Deliberately short — no explainer paragraphs: a date (seeded at 8:30 AM
/// on the bundle's own due date), the bundled test names as a read-only chip
/// row, a location field, a reminder toggle, and one primary CTA.
struct BookDrawSheet: View {
    let bundle: DrawBundle
    /// Pre-fill hook for a facility name captured elsewhere — e.g. a future
    /// scan-based clinic-name extractor another agent is building. Always
    /// `nil` today, since nothing upstream produces this yet; when set, it
    /// seeds the location field.
    var suggestedFacility: String?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme

    @State private var date: Date
    @State private var location: String
    @State private var remindMeNightBefore = true
    /// Guards `addAppointment()` against a double tap firing two inserts
    /// before the confirmation alert has appeared — same convention as
    /// `AddAppointmentSheet.isSaving`.
    @State private var isSaving = false
    @State private var showingConfirmation = false

    init(bundle: DrawBundle, suggestedFacility: String? = nil) {
        self.bundle = bundle
        self.suggestedFacility = suggestedFacility
        _date = State(initialValue: Self.defaultDate(for: bundle.date))
        _location = State(initialValue: suggestedFacility ?? "")
    }

    /// Seeds the date picker at 8:30 AM on the bundle's own due date — most
    /// outpatient labs are open by then, and a fixed default time beats
    /// making the user also pick a time for what's usually a walk-in visit.
    ///
    /// Rolled forward a day when that lands in the past (an overdue bundle's
    /// `date` is `.now` itself — see `RetestSchedule.nextDraw` — so its own
    /// 8:30 AM has typically already passed today), since the picker below
    /// is bounded to `Date.now...` and must never be seeded outside it.
    private static func defaultDate(for day: Date) -> Date {
        var components = Calendar.current.dateComponents([.year, .month, .day], from: day)
        components.hour = 8
        components.minute = 30
        let candidate = Calendar.current.date(from: components) ?? day
        if candidate > .now { return candidate }
        return Calendar.current.date(byAdding: .day, value: 1, to: candidate) ?? Date.now
    }

    /// Fixed Apple Maps search query for a nearby blood-test lab — not a
    /// personalized or geocoded result, just a map search the user can
    /// refine themselves.
    private static let nearbyLabsURL = URL(string: "https://maps.apple.com/?q=blood+test+laboratory")!

    private var confirmationMessage: String {
        remindMeNightBefore
            ? String(localized: "We'll remind you the night before.")
            : String(localized: "It's on your calendar of appointments.")
    }

    /// Bundled test names, comma-joined — stored on the created
    /// `Appointment.notes` so the visit's contents stay on record even after
    /// the schedule itself has moved on.
    private var testNamesNote: String {
        bundle.items.map(\.displayName).joined(separator: ", ")
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    SheetHeader(
                        icon: "testtube.2",
                        tint: .blue,
                        title: "Book This Draw",
                        subtitle: "One visit covers it all."
                    )

                    VStack(alignment: .leading, spacing: 12) {
                        SheetFieldLabel("Date & Time")
                        DatePicker("Date & time", selection: $date, in: Date.now...)
                            .labelsHidden()
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassCard()

                    VStack(alignment: .leading, spacing: 10) {
                        SheetFieldLabel("In This Draw")
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(bundle.items) { item in
                                    Text(verbatim: item.displayName)
                                        .font(.subheadline.weight(.semibold))
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 8)
                                        .background(.ultraThinMaterial, in: Capsule())
                                        .overlay(Capsule().strokeBorder(Glass.bevelStroke(for: colorScheme), lineWidth: 1))
                                }
                            }
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel(String(format: String(localized: "Tests: %@"), testNamesNote))
                        if bundle.requiresFasting {
                            EditorialTag("Fasting Required", kind: .warn)
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassCard()

                    VStack(alignment: .leading, spacing: 14) {
                        SheetFieldLabel("Location")
                        TextField("Location", text: $location)
                            .font(.body)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassCard()

                    Toggle("Remind me the night before", isOn: $remindMeNightBefore)
                        .font(.body.weight(.semibold))
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .glassCard()

                    Button {
                        addAppointment()
                    } label: {
                        Text("Add Appointment")
                    }
                    .buttonStyle(GlassProminentButtonStyle())
                    .disabled(isSaving)

                    Link(destination: Self.nearbyLabsURL) {
                        Text("Find a Lab Nearby")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Editorial.accent(colorScheme))
                    }
                    .accessibilityHint("Opens Apple Maps to search nearby blood test laboratories.")
                }
                .padding()
            }
            .ambientScreen()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .alert("Appointment Added", isPresented: $showingConfirmation) {
                Button("OK", role: .cancel) { dismiss() }
            } message: {
                Text(confirmationMessage)
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(.ultraThinMaterial)
    }

    private func addAppointment() {
        guard !isSaving else { return }
        isSaving = true

        let appointment = Appointment(
            title: String(localized: "Blood Draw"),
            location: location.trimmingCharacters(in: .whitespaces),
            date: date,
            notes: testNamesNote,
            reminderEnabled: remindMeNightBefore
        )
        modelContext.insert(appointment)

        // Same "night before" scheduling convention as
        // `AddAppointmentSheet.save()` — a local notification only. No
        // `cancelReminder` call first: this sheet only ever creates a fresh
        // appointment (with a fresh `reminderID`), never edits one, so
        // there's never a stale prior notification to clear.
        if remindMeNightBefore && date > .now {
            let id = appointment.reminderID
            let body = [
                appointment.title,
                String(format: String(localized: "at %@"), date.formatted(date: .omitted, time: .shortened)),
            ].joined(separator: " ")
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
        showingConfirmation = true
    }
}

// MARK: - Shared sheet UI
//
// Duplicated per-file rather than shared, matching every other Add*Sheet in
// this app (see e.g. `AppointmentsView.SheetHeader`/`SheetFieldLabel`) — each
// sheet file defines its own file-private copies rather than importing a
// shared type.

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
