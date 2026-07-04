import SwiftUI

// MARK: - Glass design system
//
// Frosted-glass surfaces floating over a soft ambient gradient. Every card
// is an ultra-thin material with a "bevel" stroke — light catches the
// top-left edge, shade falls on the bottom-right — plus a soft drop shadow.

enum Glass {
    static let cardRadius: CGFloat = 22
    static let chipRadius: CGFloat = 14

    /// Bevel edge: bright on the top-left, shaded on the bottom-right.
    static var bevelStroke: LinearGradient {
        LinearGradient(
            colors: [
                .white.opacity(0.55),
                .white.opacity(0.10),
                .black.opacity(0.16),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static var accentGradient: LinearGradient {
        LinearGradient(
            colors: [.teal, .blue],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

// MARK: - Ambient background

/// Soft gradient with blurred color orbs — gives the glass something to refract.
struct AmbientBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            LinearGradient(
                colors: colorScheme == .dark
                    ? [Color(red: 0.06, green: 0.08, blue: 0.13), Color(red: 0.02, green: 0.03, blue: 0.07)]
                    : [Color(red: 0.93, green: 0.96, blue: 1.0), Color(red: 0.87, green: 0.91, blue: 0.97)],
                startPoint: .top,
                endPoint: .bottom
            )
            Circle()
                .fill(Color.teal.opacity(colorScheme == .dark ? 0.30 : 0.34))
                .frame(width: 320, height: 320)
                .blur(radius: 80)
                .offset(x: -130, y: -250)
            Circle()
                .fill(Color.blue.opacity(colorScheme == .dark ? 0.26 : 0.28))
                .frame(width: 300, height: 300)
                .blur(radius: 90)
                .offset(x: 150, y: -40)
            Circle()
                .fill(Color.purple.opacity(0.20))
                .frame(width: 360, height: 360)
                .blur(radius: 100)
                .offset(x: 70, y: 330)
        }
        .ignoresSafeArea()
    }
}

// MARK: - Glass surfaces

private struct GlassCardModifier: ViewModifier {
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Glass.bevelStroke, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.16), radius: 14, x: 0, y: 8)
    }
}

private struct TintedGlassCardModifier: ViewModifier {
    let tint: Color
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .background(tint.opacity(0.18), in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [tint.opacity(0.55), tint.opacity(0.15)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: tint.opacity(0.20), radius: 10, x: 0, y: 5)
    }
}

extension View {
    /// Frosted, beveled glass card.
    func glassCard(cornerRadius: CGFloat = Glass.cardRadius) -> some View {
        modifier(GlassCardModifier(cornerRadius: cornerRadius))
    }

    /// Glass card washed with a tint color — used for alerts and findings.
    func tintedGlassCard(_ tint: Color, cornerRadius: CGFloat = Glass.chipRadius) -> some View {
        modifier(TintedGlassCardModifier(tint: tint, cornerRadius: cornerRadius))
    }

    /// Hides the system list/form background and puts the ambient gradient behind it.
    func ambientScreen() -> some View {
        self
            .scrollContentBackground(.hidden)
            .background(AmbientBackground())
    }
}

/// Row background for `List`/`Form`: each row floats as a frosted glass chip.
struct GlassRowBackground: View {
    var cornerRadius: CGFloat = Glass.chipRadius

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Glass.bevelStroke, lineWidth: 1)
            )
            .padding(.vertical, 3)
    }
}

// MARK: - Buttons

struct GlassProminentButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.vertical, 13)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Glass.accentGradient)
                    .opacity(configuration.isPressed ? 0.75 : 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Glass.bevelStroke, lineWidth: 1)
            )
            .shadow(color: .blue.opacity(0.35), radius: 10, x: 0, y: 5)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(duration: 0.2), value: configuration.isPressed)
    }
}

struct GlassButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .padding(.vertical, 13)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Glass.bevelStroke, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.12), radius: 8, x: 0, y: 4)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(duration: 0.2), value: configuration.isPressed)
    }
}
