import SwiftUI
import SwiftData

@main
struct MediTrackApp: App {
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
            ContentView()
                .fontDesign(.rounded)
                .task {
                    // No-op unless the user has opted in to Automatic Sync
                    // in Profile, and unavailable on the Simulator/CI —
                    // `HealthKitService.isAvailable` guards both.
                    HealthKitService.startAutomaticSyncIfEnabled(container: sharedModelContainer)
                }
        }
        .modelContainer(sharedModelContainer)
    }
}
