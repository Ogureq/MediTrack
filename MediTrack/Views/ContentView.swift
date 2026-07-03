import SwiftUI

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("appLockEnabled") private var appLockEnabled = false
    @StateObject private var lock = BiometricLock()

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
            if appLockEnabled {
                await lock.unlock()
            } else {
                lock.isLocked = false
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
        ZStack {
            Rectangle()
                .fill(.regularMaterial)
                .ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(.secondary)
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
                        .padding(.horizontal, 8)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
    }
}

struct MoreView: View {
    var body: some View {
        NavigationStack {
            List {
                NavigationLink {
                    VitalsView()
                } label: {
                    Label("Vitals", systemImage: "waveform.path.ecg")
                }
                NavigationLink {
                    MedicationsView()
                } label: {
                    Label("Medications", systemImage: "pills.fill")
                }
                NavigationLink {
                    ProfileView()
                } label: {
                    Label("Profile & Settings", systemImage: "person.crop.circle")
                }
            }
            .navigationTitle("More")
        }
    }
}

#Preview {
    ContentView()
}
