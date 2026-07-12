import SwiftUI

enum AppTab: Hashable {
    case dashboard, reports, review, trends, more
}

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("appLockEnabled") private var appLockEnabled = false
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @StateObject private var lock = AppLock()
    @State private var showingOnboarding = false
    @State private var selectedTab: AppTab = .dashboard

    var body: some View {
        TabView(selection: $selectedTab) {
            DashboardView()
                .tabItem { Label("Dashboard", systemImage: "house.fill") }
                .tag(AppTab.dashboard)
            ReportsListView()
                .tabItem { Label("Reports", systemImage: "doc.text.fill") }
                .tag(AppTab.reports)
            NavigationStack { ReviewScreen() }
                .tabItem { Label("Review", systemImage: "heart.text.square.fill") }
                .tag(AppTab.review)
            TrendsView()
                .tabItem { Label("Trends", systemImage: "chart.line.uptrend.xyaxis") }
                .tag(AppTab.trends)
            MoreView()
                .tabItem { Label("More", systemImage: "ellipsis.circle.fill") }
                .tag(AppTab.more)
        }
        .environmentObject(lock)
        .onOpenURL { url in
            // Deep link from the home-screen widget (meditrack://review).
            guard url.scheme == "meditrack" else { return }
            switch url.host {
            case "review": selectedTab = .review
            case "trends": selectedTab = .trends
            default: break
            }
        }
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
                    NavigationLink {
                        DocumentsView()
                    } label: {
                        Label("Documents", systemImage: "folder.fill")
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
