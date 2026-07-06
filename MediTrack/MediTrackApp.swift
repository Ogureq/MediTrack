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
        }
        .modelContainer(sharedModelContainer)
    }
}
