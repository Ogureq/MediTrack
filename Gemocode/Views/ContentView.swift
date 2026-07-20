import SwiftUI
import SwiftData

enum AppTab: Hashable {
    case dashboard, reports, review, trends, more, schedule
}

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("appLockEnabled") private var appLockEnabled = false
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @StateObject private var lock = AppLock()
    @State private var showingOnboarding = false
    @State private var selectedTab: AppTab = .dashboard
    /// Presents `ReviewScreen` as a full-screen cover — Review is no longer
    /// a `TabView` page (see `AppTab`'s doc comment below), so both the
    /// dashboard's score header and the widget's `gemocode://review` deep
    /// link route through `presentReview()` instead of switching tabs.
    @State private var showingReview = false

    /// Bottom pill-tab-bar order (Today / Markers / Reports / Schedule /
    /// More), mapped to the `Int` tags `PillTabBar` expects. `.review` is
    /// deliberately absent from this list — kept on `AppTab` itself only
    /// for source compatibility.
    private static let tabBarOrder: [AppTab] = [.dashboard, .trends, .reports, .schedule, .more]

    private var tabBarSelection: Binding<Int> {
        Binding(
            get: { Self.tabBarOrder.firstIndex(of: selectedTab) ?? 0 },
            set: { index in
                guard Self.tabBarOrder.indices.contains(index) else { return }
                selectedTab = Self.tabBarOrder[index]
            }
        )
    }

    private var tabBarItems: [(label: LocalizedStringKey, icon: String, tag: Int)] {
        [
            (label: "Today", icon: "house.fill", tag: 0),
            (label: "Markers", icon: "chart.line.uptrend.xyaxis", tag: 1),
            (label: "Reports", icon: "doc.text.fill", tag: 2),
            (label: "Schedule", icon: "calendar.badge.clock", tag: 3),
            (label: "More", icon: "ellipsis.circle.fill", tag: 4),
        ]
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            DashboardView(onOpenReview: presentReview)
                .tabItem { Label("Today", systemImage: "house.fill") }
                .toolbar(.hidden, for: .tabBar)
                .tag(AppTab.dashboard)
            TrendsView()
                .tabItem { Label("Markers", systemImage: "chart.line.uptrend.xyaxis") }
                .toolbar(.hidden, for: .tabBar)
                .tag(AppTab.trends)
            ReportsListView()
                .tabItem { Label("Reports", systemImage: "doc.text.fill") }
                .toolbar(.hidden, for: .tabBar)
                .tag(AppTab.reports)
            NavigationStack { RetestScheduleView() }
                .tabItem { Label("Schedule", systemImage: "calendar.badge.clock") }
                .toolbar(.hidden, for: .tabBar)
                .tag(AppTab.schedule)
            MoreView()
                .tabItem { Label("More", systemImage: "ellipsis.circle.fill") }
                .toolbar(.hidden, for: .tabBar)
                .tag(AppTab.more)
        }
        .tint(Editorial.accent(.light))
        .environmentObject(lock)
        .safeAreaInset(edge: .bottom) {
            PillTabBar(items: tabBarItems, selection: tabBarSelection)
                .padding(.horizontal, 24)
        }
        .onOpenURL { url in
            // Deep link from the home-screen widget (gemocode://review) —
            // host strings are the widget's contract with the app and must
            // not change.
            guard url.scheme == "gemocode" else { return }
            switch url.host {
            case "review": presentReview()
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
        .fullScreenCover(isPresented: $showingReview) {
            NavigationStack { ReviewScreen() }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background {
                lock.lockOnBackground(lockEnabled: appLockEnabled)
            }
        }
    }

    /// Selects the Today tab and presents `ReviewScreen` as a full-screen
    /// cover — the shared target for the dashboard's score header tap and
    /// the widget's `gemocode://review` deep link.
    private func presentReview() {
        selectedTab = .dashboard
        showingReview = true
    }
}

/// Tints for the More-screen feature grid and avatar gradient. Deliberate
/// per-card hues from the design spec, not the system palette.
private enum MoreTint {
    static let vitals = Color(red: 0.2510, green: 0.7843, blue: 0.8784)
    static let symptoms = Color(red: 1.0, green: 0.6980, blue: 0.4000)
    static let medications = Color(red: 0.4941, green: 0.9098, blue: 0.6902)
    static let appointments = Color(red: 0.6588, green: 0.5882, blue: 1.0)
    static let goals = Color(red: 1.0, green: 0.8392, blue: 0.4000)
    static let documents = Color(red: 0.4706, green: 0.7451, blue: 1.0)
    static let medicalID = Color(red: 1.0, green: 0.4118, blue: 0.4706)
    static let medicalIDIcon = Color(red: 1.0, green: 0.4784, blue: 0.5333)
    static let avatarStart = vitals
    static let avatarEnd = medications
    static let avatarText = Color(red: 0.0431, green: 0.0627, blue: 0.1255)
}

/// Subtle press-down scale, matching the amount/curve `GlassButtonStyle`
/// uses, without imposing its own material background — the feature cards
/// already draw their own `glassCard`/`tintedGlassCard` surface.
private struct CardPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(duration: 0.2), value: configuration.isPressed)
    }
}

struct MoreView: View {
    @Query private var profiles: [HealthProfile]
    @Query private var medications: [Medication]
    @Query(sort: \Appointment.date) private var appointments: [Appointment]
    @Query private var goals: [HealthGoal]
    @Query private var reports: [MedicalReport]

    private var profile: HealthProfile? { profiles.first }

    private var profileInitials: String {
        let name = profile?.name.trimmingCharacters(in: .whitespaces) ?? ""
        guard !name.isEmpty else { return "MT" }
        let letters = name.split(separator: " ").compactMap { $0.first }.prefix(2)
        let initials = String(letters).uppercased()
        return initials.isEmpty ? "MT" : initials
    }

    private var profileTitle: String {
        let name = profile?.name.trimmingCharacters(in: .whitespaces) ?? ""
        return name.isEmpty ? String(localized: "Your Profile") : name
    }

    private var activeMedicationCount: Int {
        medications.filter(\.isActive).count
    }

    private var medicationsSubtitle: String {
        String(format: String(localized: "%lld active"), activeMedicationCount)
    }

    private var nextAppointment: Appointment? {
        appointments.first(where: \.isUpcoming)
    }

    private var appointmentsSubtitle: String {
        guard let date = nextAppointment?.date else { return String(localized: "None scheduled") }
        return String(format: String(localized: "Next: %@"), date.formatted(.dateTime.month(.abbreviated).day()))
    }

    private var goalsInProgressCount: Int {
        goals.filter(\.isActive).count
    }

    private var goalsSubtitle: String {
        String(format: String(localized: "%lld in progress"), goalsInProgressCount)
    }

    /// Cached instead of a plain computed property — `.attachments` faults
    /// each report's relationship, and this view's five `@Query`s can each
    /// retrigger a render, so recomputing on every render would repeatedly
    /// fault every report. Rebuilt only when `reports.count` changes.
    @State private var documentsCount = 0

    private var documentsSubtitle: String {
        String(format: String(localized: "%lld files"), documentsCount)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    profileHeaderCard

                    Text("HEALTH RECORDS")
                        .font(.system(size: 12, weight: .bold))
                        .tracking(1.2)
                        .foregroundStyle(.primary.opacity(0.42))
                        .accessibilityAddTraits(.isHeader)
                        .padding(.horizontal, 4)

                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible())], spacing: 14) {
                        featureCard(icon: "waveform.path.ecg", tint: MoreTint.vitals, title: "Vitals", subtitle: String(localized: "BP, heart rate, SpO₂")) {
                            VitalsView()
                        }
                        featureCard(icon: "list.bullet.clipboard", tint: MoreTint.symptoms, title: "Symptoms", subtitle: String(localized: "Log & track patterns")) {
                            SymptomsView()
                        }
                        featureCard(icon: "pills.fill", tint: MoreTint.medications, title: "Medications", subtitle: medicationsSubtitle) {
                            MedicationsView()
                        }
                        featureCard(icon: "calendar", tint: MoreTint.appointments, title: "Appointments", subtitle: appointmentsSubtitle) {
                            AppointmentsView()
                        }
                        featureCard(icon: "target", tint: MoreTint.goals, title: "Goals", subtitle: goalsSubtitle) {
                            GoalsView()
                        }
                        featureCard(icon: "folder.fill", tint: MoreTint.documents, title: "Documents", subtitle: documentsSubtitle) {
                            DocumentsView()
                        }
                    }

                    medicalIDCard
                }
                .padding()
            }
            .ambientScreen()
            .navigationTitle("More")
        }
        .task(id: reports.count) {
            documentsCount = reports.reduce(0) { $0 + $1.attachments.count }
        }
    }

    // MARK: - Profile header

    private var profileHeaderCard: some View {
        NavigationLink {
            ProfileView()
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [MoreTint.avatarStart, MoreTint.avatarEnd],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 46, height: 46)
                    Text(profileInitials)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(MoreTint.avatarText)
                }
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(profileTitle)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.primary)
                    Text("Profile, settings & data")
                        .font(.system(size: 12.5))
                        .foregroundStyle(.primary.opacity(0.5))
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary.opacity(0.28))
                    .accessibilityHidden(true)
            }
            .padding(14)
            .glassCard(cornerRadius: 16)
        }
        .buttonStyle(CardPressStyle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(profileTitle), Profile, settings and data")
    }

    // MARK: - Feature grid

    private func featureCard<Destination: View>(
        icon: String,
        tint: Color,
        title: LocalizedStringKey,
        subtitle: String,
        @ViewBuilder destination: () -> Destination
    ) -> some View {
        NavigationLink {
            destination()
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    iconChip(icon: icon, tint: tint, size: 36, radius: 11)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary.opacity(0.28))
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 14.5, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.primary.opacity(0.45))
                        .lineLimit(1)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard(cornerRadius: 16)
        }
        .buttonStyle(CardPressStyle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(title) + Text(verbatim: ", ") + Text(subtitle))
    }

    private func iconChip(icon: String, tint: Color, size: CGFloat, radius: CGFloat, iconColor: Color? = nil) -> some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(tint.opacity(0.16))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(tint.opacity(0.32), lineWidth: 1)
            )
            .frame(width: size, height: size)
            .overlay(
                Image(systemName: icon)
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundStyle(iconColor ?? tint)
            )
            .accessibilityHidden(true)
    }

    // MARK: - Medical ID

    private var medicalIDCard: some View {
        NavigationLink {
            MedicalIDView()
        } label: {
            HStack(spacing: 14) {
                iconChip(icon: "cross.case.fill", tint: MoreTint.medicalID, size: 38, radius: 12, iconColor: MoreTint.medicalIDIcon)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Medical ID")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.primary)
                    Text("Emergency info at a glance")
                        .font(.system(size: 12))
                        .foregroundStyle(.primary.opacity(0.5))
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary.opacity(0.28))
                    .accessibilityHidden(true)
            }
            .padding(14)
            .tintedGlassCard(MoreTint.medicalID, cornerRadius: 16)
        }
        .buttonStyle(CardPressStyle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Medical ID, Emergency info at a glance")
    }
}

#Preview {
    ContentView()
}
