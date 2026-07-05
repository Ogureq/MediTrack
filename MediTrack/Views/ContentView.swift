import SwiftUI

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("appLockEnabled") private var appLockEnabled = false
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @StateObject private var lock = BiometricLock()
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
        .overlay {
            if appLockEnabled && lock.isLocked {
                LockScreenView(lock: lock)
            }
        }
        .task {
            if !hasCompletedOnboarding {
                showingOnboarding = true
            }
            if appLockEnabled {
                await lock.unlock()
            } else {
                lock.isLocked = false
            }
        }
        .fullScreenCover(isPresented: $showingOnboarding) {
            OnboardingView {
                hasCompletedOnboarding = true
                showingOnboarding = false
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background && appLockEnabled {
                lock.lock()
            }
        }
    }
}

struct LockScreenView: View {
    @ObservedObject var lock: BiometricLock

    var body: some View {
        lockContent
            .task {
                // Prompt for Face ID immediately instead of waiting for a tap.
                await lock.unlock()
            }
    }

    private var lockContent: some View {
        ZStack {
            AmbientBackground()
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(Glass.accentGradient)
                Text("MediTrack is Locked")
                    .font(.title3.weight(.semibold))
                Text("Your medical data is protected.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if let error = lock.lastError {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
                Button {
                    Task { await lock.unlock() }
                } label: {
                    Label("Unlock", systemImage: "faceid")
                }
                .buttonStyle(GlassProminentButtonStyle())
            }
            .padding(24)
            .frame(maxWidth: 320)
            .glassCard()
            .padding()
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
