import SwiftUI
import SwiftData

@main
struct GemocodeApp: App {
    @StateObject private var settings = AppSettingsStore.shared

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            MedicalReport.self,
            LabResult.self,
            ReportAttachment.self,
            VitalSample.self,
            Medication.self,
            HealthProfile.self,
            ScoreSnapshot.self,
            SymptomEntry.self,
            Appointment.self,
            HealthGoal.self,
            Reminder.self,
            ReminderCompletion.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            rootView
        }
        .modelContainer(sharedModelContainer)
    }

    /// `ContentView` plus the app-wide modifiers, split out so the optional
    /// `\.locale` override can be applied conditionally — SwiftUI has no
    /// "environment override, unless nil" shorthand, so `languageChoice ==
    /// .system` (the default) skips the `.environment(\.locale, _)` call
    /// entirely rather than passing some "current" placeholder.
    @ViewBuilder
    private var rootView: some View {
        let content = ContentView()
            .task {
                // No-op unless the user has opted in to Automatic Sync
                // in Profile, and unavailable on the Simulator/CI —
                // `HealthKitService.isAvailable` guards both.
                HealthKitService.startAutomaticSyncIfEnabled(container: sharedModelContainer)
            }
            .environmentObject(settings)
            .preferredColorScheme(settings.themeChoice.colorScheme)

        if let localeOverride = settings.languageChoice.localeOverride {
            content.environment(\.locale, localeOverride)
        } else {
            content
        }
    }
}
