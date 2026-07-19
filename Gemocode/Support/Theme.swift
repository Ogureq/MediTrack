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
    ///
    /// Unchanged — this is the value every existing call site across the
    /// app (`Glass.bevelStroke`, no arguments) still resolves to, so dark
    /// mode renders byte-identically to before this file gained light-mode
    /// support. Use `bevelStroke(for:)` below for scheme-aware call sites.
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

    /// Scheme-aware bevel edge for the shared surfaces below
    /// (`glassCard`/`tintedGlassCard`/`GlassRowBackground`/glass button
    /// styles). Dark mode returns exactly `bevelStroke` (untouched); light
    /// mode drops the bright top-left highlight — invisible against a pale
    /// background — for a flat hairline border instead.
    static func bevelStroke(for colorScheme: ColorScheme) -> LinearGradient {
        switch colorScheme {
        case .light:
            LinearGradient(
                colors: [.black.opacity(0.08)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        default:
            bevelStroke
        }
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

/// Soft gradient with glowing color orbs — gives the glass something to
/// refract. The orbs are radial gradients rather than `.blur`-ed circles:
/// a live Gaussian blur is re-composited by the GPU whenever the content
/// above it scrolls, which reads as jank on real devices, while a radial
/// falloff renders once and looks the same.
struct AmbientBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    private func orb(_ color: Color, opacity: Double, size: CGFloat) -> some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [color.opacity(opacity), color.opacity(opacity * 0.55), color.opacity(0)],
                    center: .center,
                    startRadius: 0,
                    endRadius: size * 0.62
                )
            )
            .frame(width: size * 1.25, height: size * 1.25)
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: colorScheme == .dark
                    ? [Color(red: 0.06, green: 0.08, blue: 0.13), Color(red: 0.02, green: 0.03, blue: 0.07)]
                    : [Color(red: 0.93, green: 0.96, blue: 1.0), Color(red: 0.87, green: 0.91, blue: 0.97)],
                startPoint: .top,
                endPoint: .bottom
            )
            orb(.teal, opacity: colorScheme == .dark ? 0.30 : 0.34, size: 320)
                .offset(x: -130, y: -250)
            orb(.blue, opacity: colorScheme == .dark ? 0.26 : 0.28, size: 300)
                .offset(x: 150, y: -40)
            orb(.purple, opacity: 0.20, size: 360)
                .offset(x: 70, y: 330)
        }
        .ignoresSafeArea()
    }
}

// MARK: - Glass surfaces

private struct GlassCardModifier: ViewModifier {
    let cornerRadius: CGFloat
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .background {
                // `.ultraThinMaterial` alone reads slightly gray on a light
                // background, so light mode washes a translucent white fill
                // underneath it. Dark mode adds nothing here — identical to
                // before this modifier gained light-mode support.
                if colorScheme == .light {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(Color.white.opacity(0.65))
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Glass.bevelStroke(for: colorScheme), lineWidth: 1)
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
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(.ultraThinMaterial)
            .background {
                // Same light-mode-only white wash as `GlassCardModifier`;
                // dark mode is unaffected.
                if colorScheme == .light {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(Color.white.opacity(0.65))
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Glass.bevelStroke(for: colorScheme), lineWidth: 1)
            )
            .padding(.vertical, 3)
    }
}

// MARK: - Buttons

struct GlassProminentButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme

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
                    .strokeBorder(Glass.bevelStroke(for: colorScheme), lineWidth: 1)
            )
            .shadow(color: .blue.opacity(0.35), radius: 10, x: 0, y: 5)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(duration: 0.2), value: configuration.isPressed)
    }
}

struct GlassButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .padding(.vertical, 13)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Glass.bevelStroke(for: colorScheme), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.12), radius: 8, x: 0, y: 4)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(duration: 0.2), value: configuration.isPressed)
    }
}
