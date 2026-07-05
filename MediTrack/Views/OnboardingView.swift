import SwiftUI

// MARK: - Onboarding

/// First-run walkthrough: what MediTrack does, how the on-device analysis
/// works, and the privacy/disclaimer page the user must see before entering
/// the app.
struct OnboardingView: View {
    let onFinish: () -> Void

    @State private var pageIndex = 0

    var body: some View {
        ZStack {
            AmbientBackground()

            TabView(selection: $pageIndex) {
                OnboardingPage(
                    systemImage: "heart.text.square.fill",
                    title: "Your Health, In One Place",
                    description: "Log medical reports, lab results, and prescriptions as they come in. Attach the original documents so everything stays organized and easy to find later."
                ) {
                    withAnimation { pageIndex += 1 }
                }
                .tag(0)

                OnboardingPage(
                    systemImage: "stethoscope",
                    title: "Detailed Health Reviews",
                    description: "MediTrack analyzes your reports on-device, giving you a health score, findings explained in plain language, and checks against normal reference ranges."
                ) {
                    withAnimation { pageIndex += 1 }
                }
                .tag(1)

                OnboardingPage(
                    systemImage: "chart.line.uptrend.xyaxis",
                    title: "Spot Trends Early",
                    description: "Track your vitals and lab values over time with simple charts, so you can see what's improving and what's drifting before it becomes a problem."
                ) {
                    withAnimation { pageIndex += 1 }
                }
                .tag(2)

                PrivacyPage(onFinish: onFinish)
                    .tag(3)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))

            if pageIndex < 3 {
                VStack {
                    HStack {
                        Spacer()
                        Button("Skip") {
                            withAnimation { pageIndex = 3 }
                        }
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.trailing, 20)
                        .padding(.top, 8)
                    }
                    Spacer()
                }
            }
        }
    }
}

// MARK: - Feature page

private struct OnboardingPage: View {
    let systemImage: String
    let title: String
    let description: String
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 28) {
            Spacer()

            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .overlay(
                        Circle().strokeBorder(Glass.bevelStroke, lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.14), radius: 12, x: 0, y: 6)
                    .frame(width: 110, height: 110)

                Image(systemName: systemImage)
                    .font(.system(size: 54, weight: .semibold))
                    .foregroundStyle(Glass.accentGradient)
            }

            VStack(spacing: 12) {
                Text(title)
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)

                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
            }

            Spacer()

            Button("Continue", action: onContinue)
                .buttonStyle(GlassProminentButtonStyle())
                .frame(maxWidth: 280)
                .padding(.bottom, 40)
        }
        .padding(.top, 60)
    }
}

// MARK: - Privacy / disclaimer page

private struct PrivacyPage: View {
    let onFinish: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .overlay(
                        Circle().strokeBorder(Glass.bevelStroke, lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.14), radius: 12, x: 0, y: 6)
                    .frame(width: 110, height: 110)

                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 54, weight: .semibold))
                    .foregroundStyle(Glass.accentGradient)
            }

            VStack(spacing: 12) {
                Text("Private by Design")
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)

                Text("Everything stays on this device, protected by Face ID.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
            }

            ScrollView {
                Text(HealthReview.disclaimer)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .padding()
            }
            .frame(maxHeight: 180)
            .glassCard(cornerRadius: 16)
            .padding(.horizontal, 24)

            Spacer()

            Button("I Understand — Get Started", action: onFinish)
                .buttonStyle(GlassProminentButtonStyle())
                .frame(maxWidth: 300)
                .padding(.bottom, 40)
        }
        .padding(.top, 60)
    }
}

#Preview {
    OnboardingView(onFinish: {})
}
