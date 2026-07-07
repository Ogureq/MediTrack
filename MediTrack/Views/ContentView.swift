import SwiftUI

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("appLockEnabled") private var appLockEnabled = false
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @StateObject private var lock = AppLock()
    @State private var showingOnboarding = false

    var body: some View {
        TabView {
            DashboardView()
                .tabItem { Label("Dashboard", systemImage: "house.fill") }
            ReportsListView()
                .tabItem { Label("Reports", systemImage: "doc.text.fill") }
            NavigationStack { ReviewScreen() }
                .tabItem { Label("Review", systemImage: "heart.text.square.fill") }
            TrendsView()
                .tabItem { Label("Trends", systemImage: "chart.line.uptrend.xyaxis") }
            MoreView()
                .tabItem { Label("More", systemImage: "ellipsis.circle.fill") }
        }
        .environmentObject(lock)
        .overlay {
            if appLockEnabled && lock.isLocked {
                LoginView(lock: lock)
                    .transition(.opacity)
            }
        }
        .task {
            if !hasCompletedOnboarding {
                showingOnboarding = true
            }
            lock.evaluate(lockEnabled: appLockEnabled)
        }
        .fullScreenCover(isPresented: $showingOnboarding) {
            OnboardingView {
                hasCompletedOnboarding = true
                showingOnboarding = false
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background {
                lock.lockOnBackground(lockEnabled: appLockEnabled)
            }
        }
    }
}

struct MoreView: View {
    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        VitalsView()
                    } label: {
                        Label("Vitals", systemImage: "waveform.path.ecg")
                    }
                    NavigationLink {
                        SymptomsView()
                    } label: {
                        Label("Symptoms", systemImage: "list.bullet.clipboard")
                    }
                    NavigationLink {
                        MedicationsView()
                    } label: {
                        Label("Medications", systemImage: "pills.fill")
                    }
                    NavigationLink {
                        AppointmentsView()
                    } label: {
                        Label("Appointments", systemImage: "calendar")
                    }
                    NavigationLink {
                        GoalsView()
                    } label: {
                        Label("Goals", systemImage: "target")
                    }
                }
                .listRowBackground(GlassRowBackground())
                .listRowSeparator(.hidden)

                Section {
                    NavigationLink {
                        MedicalIDView()
                    } label: {
                        Label("Medical ID", systemImage: "cross.case.fill")
                    }
                    NavigationLink {
                        ProfileView()
                    } label: {
                        Label("Profile & Settings", systemImage: "person.crop.circle")
                    }
                }
                .listRowBackground(GlassRowBackground())
                .listRowSeparator(.hidden)
            }
            .ambientScreen()
            .navigationTitle("More")
        }
    }
}

#Preview {
    ContentView()
}
