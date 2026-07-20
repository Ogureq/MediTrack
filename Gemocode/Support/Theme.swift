import SwiftUI

// MARK: - Editorial design system
//
// Paper-and-ink editorial: flat surfaces, hairline dividers, a single
// accent color. No glass materials, no ambient orbs, no gradients in
// chrome. Every color used anywhere in the app should resolve through the
// `Editorial` token enum below so light/dark values stay centralized and
// in sync with the token spec (`<scratchpad>/EDITORIAL-TOKENS.md`).
//
// The legacy `Glass` namespace, `.glassCard()`/`.tintedGlassCard()`/
// `GlassRowBackground`/`AmbientBackground` names, and the `GlassButtonStyle`
// / `GlassProminentButtonStyle` button styles are kept byte-for-byte on the
// public surface (same types, same signatures) so every existing call
// site keeps compiling — but they now render the flat editorial surfaces
// described above instead of frosted glass. New code should prefer the
// dedicated editorial components in `Support/EditorialComponents.swift`
// (`RangeBar`, `EditorialTag`, `MicroLabel`, `OutlinedPillButtonStyle`,
// `AccentPillButtonStyle`, `ledgerRow()`, `PillTabBar`) over these legacy
// names.

/// Editorial color tokens — the single source of truth for every color in
/// the app. Each token is a function of `ColorScheme` so light/dark values
/// stay together and in sync; views should never spell out a `Color`
/// literal themselves.
enum Editorial {
    /// Screen background.
    static func canvas(_ colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color(red: 0.058824, green: 0.066667, blue: 0.078431) // #0F1114
            : Color(red: 1.0, green: 1.0, blue: 1.0) // #FFFFFF
    }

    /// Primary text, icons, range-bar marker (light mode).
    static func ink(_ colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color(red: 0.933333, green: 0.941176, blue: 0.949020) // #EEF0F2
            : Color(red: 0.0, green: 0.0, blue: 0.0) // #000000
    }

    /// Secondary text, micro-labels.
    static func muted(_ colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color(red: 0.552941, green: 0.576471, blue: 0.611765) // #8D939C
            : Color(red: 0.560784, green: 0.560784, blue: 0.560784) // #8F8F8F
    }

    /// Row dividers.
    static func hairline(_ colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color(red: 0.156863, green: 0.168627, blue: 0.192157) // #282B31
            : Color(red: 0.941176, green: 0.941176, blue: 0.941176) // #F0F0F0
    }

    /// 1px borders on circular/secondary controls.
    static func controlBorder(_ colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color(red: 0.2, green: 0.215686, blue: 0.243137) // #33373E
            : Color(red: 0.878431, green: 0.878431, blue: 0.878431) // #E0E0E0
    }

    /// Soft inset card fill (radius 18) — one featured block per screen.
    static func insetCard(_ colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color(red: 0.101961, green: 0.113725, blue: 0.133333) // #1A1D22
            : Color(red: 0.964706, green: 0.964706, blue: 0.956863) // #F6F6F4
    }

    /// The one filled accent — small pill buttons only (e.g. "Book").
    /// Identical in both color schemes; still scheme-shaped for a
    /// consistent call pattern with the rest of this enum.
    static func accent(_ colorScheme: ColorScheme) -> Color {
        Color(red: 0.039216, green: 0.517647, blue: 1.0) // #0A84FF
    }

    /// Status tag fill — good/normal. Identical in both color schemes.
    static func tagGood(_ colorScheme: ColorScheme) -> Color {
        Color(red: 0.184314, green: 0.560784, blue: 0.356863) // #2F8F5B
    }

    /// Status tag fill — high/borderline/due soon. Identical in both
    /// color schemes.
    static func tagWarn(_ colorScheme: ColorScheme) -> Color {
        Color(red: 0.725490, green: 0.513725, blue: 0.090196) // #B98317
    }

    /// Status tag fill — low/overdue/critical. Identical in both color
    /// schemes.
    static func tagBad(_ colorScheme: ColorScheme) -> Color {
        Color(red: 0.811765, green: 0.247059, blue: 0.184314) // #CF3F2F
    }

    /// Range-bar out-of-range zone.
    static func zoneOut(_ colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color(red: 0.301961, green: 0.239216, blue: 0.156863) // #4D3D28
            : Color(red: 0.909804, green: 0.788235, blue: 0.658824) // #E8C9A8
    }

    /// Range-bar in-range zone.
    static func zoneIn(_ colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color(red: 0.152941, green: 0.266667, blue: 0.203922) // #274434
            : Color(red: 0.749020, green: 0.890196, blue: 0.803922) // #BFE3CD
    }

    /// Range-bar optimal zone (score bar's third segment).
    static func zoneOptimal(_ colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color(red: 0.207843, green: 0.376471, blue: 0.282353) // #356048
            : Color(red: 0.623529, green: 0.831373, blue: 0.705882) // #9FD4B4
    }

    /// 2.5pt range-bar position marker.
    static func barMarker(_ colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color(red: 1.0, green: 1.0, blue: 1.0) // #FFFFFF
            : Color(red: 0.0, green: 0.0, blue: 0.0) // #000000
    }
}

// MARK: - Legacy `Glass` namespace (rewired to editorial values)

enum Glass {
    /// `glassCard()`'s default corner radius.
    static let cardRadius: CGFloat = 18
    /// `tintedGlassCard()`'s default corner radius, also used standalone
    /// by a handful of call sites for chip-sized surfaces.
    static let chipRadius: CGFloat = 14

    /// Hairline stroke with no `ColorScheme` to read, for call sites that
    /// haven't migrated to reading `@Environment(\.colorScheme)` and
    /// calling `bevelStroke(for:)` themselves. Resolves to the light-mode
    /// `controlBorder` — light is the app-wide default theme now — so an
    /// un-migrated call site still renders a correct hairline in the
    /// common case; it under/over-shoots slightly only when the user has
    /// switched to Dark. Prefer `bevelStroke(for:)` at any new call site.
    static var bevelStroke: LinearGradient {
        bevelStroke(for: .light)
    }

    /// Scheme-aware hairline stroke: a single-color gradient of
    /// `Editorial.controlBorder`. Kept as a `LinearGradient` (rather than
    /// a plain `Color`) purely so existing call sites — which pass this to
    /// `strokeBorder(_:lineWidth:)` — keep compiling unchanged.
    static func bevelStroke(for colorScheme: ColorScheme) -> LinearGradient {
        LinearGradient(
            colors: [Editorial.controlBorder(colorScheme)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    /// Solid accent, kept as a `LinearGradient` (single color) so existing
    /// call sites keep compiling unchanged.
    static var accentGradient: LinearGradient {
        LinearGradient(
            colors: [Editorial.accent(.light)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

// MARK: - Ambient background

/// Flat screen background — the editorial system has no ambient glow, so
/// this is now just `Editorial.canvas`. The type is kept (rather than
/// inlining a `Color` at each `ambientScreen()` call site) so the one
/// place that reads the environment's color scheme stays centralized.
struct AmbientBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Editorial.canvas(colorScheme)
            .ignoresSafeArea()
    }
}

// MARK: - Editorial surfaces (legacy "glass" names)

private struct GlassCardModifier: ViewModifier {
    let cornerRadius: CGFloat
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .background(Editorial.canvas(colorScheme), in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Editorial.controlBorder(colorScheme), lineWidth: 1)
            )
            .shadow(
                color: colorScheme == .light ? Color.black.opacity(0.06) : .clear,
                radius: colorScheme == .light ? 30 : 0,
                x: 0,
                y: colorScheme == .light ? 8 : 0
            )
    }
}

private struct TintedGlassCardModifier: ViewModifier {
    let tint: Color
    let cornerRadius: CGFloat
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        // `.background` layers each subsequent call further behind, so the
        // low-opacity tint must come first (nearer the content) with the
        // opaque `insetCard` fill behind it — otherwise the opaque fill
        // would sit on top and hide the translucent tint entirely.
        content
            .background(tint.opacity(0.06), in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .background(Editorial.insetCard(colorScheme), in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

extension View {
    /// Flat editorial card: `Editorial.canvas` fill, hairline
    /// `controlBorder` stroke, and — in light mode only — a soft drop
    /// shadow (dark mode relies on the border alone).
    func glassCard(cornerRadius: CGFloat = Glass.cardRadius) -> some View {
        modifier(GlassCardModifier(cornerRadius: cornerRadius))
    }

    /// Quiet inset card: `Editorial.insetCard` fill with the tint blended
    /// in at very low opacity. Surfaces stay quiet in the editorial
    /// system — the tint no longer drives a visible border or shadow.
    func tintedGlassCard(_ tint: Color, cornerRadius: CGFloat = Glass.chipRadius) -> some View {
        modifier(TintedGlassCardModifier(tint: tint, cornerRadius: cornerRadius))
    }

    /// Hides the system list/form background and puts the flat editorial
    /// canvas behind it.
    func ambientScreen() -> some View {
        self
            .scrollContentBackground(.hidden)
            .background(AmbientBackground())
    }
}

/// Row background for `List`/`Form`: rows read as flat ledger entries, not
/// floating cards, so this now draws nothing. Dividers between rows come
/// from the list's own separators (or, for editorial-native rows, the
/// `ledgerRow()` modifier in `EditorialComponents.swift`) rather than from
/// this background.
struct GlassRowBackground: View {
    var cornerRadius: CGFloat = Glass.chipRadius

    var body: some View {
        Color.clear
    }
}

// MARK: - Buttons

/// Full-width filled accent CTA — the one "primary action for this
/// screen" button (e.g. "Save", "Add plan + set reminders"). Solid
/// `Editorial.accent` fill, white text, a soft accent-tinted shadow; no
/// border.
struct GlassProminentButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme

    func makeBody(configuration: Configuration) -> some View {
        let accent = Editorial.accent(colorScheme)
        return configuration.label
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
            .padding(.vertical, 15)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity)
            .background(
                Capsule(style: .continuous)
                    .fill(accent)
                    .opacity(configuration.isPressed ? 0.75 : 1)
            )
            .shadow(color: accent.opacity(0.30), radius: 20, x: 0, y: 14)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(duration: 0.2), value: configuration.isPressed)
    }
}

/// Full-width outlined pill — the quiet, secondary counterpart to
/// `GlassProminentButtonStyle` (e.g. "Ask about this plan", "Cancel"
/// alongside a prominent "Save"). 1px `ink` border, transparent fill.
struct GlassButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme

    func makeBody(configuration: Configuration) -> some View {
        let ink = Editorial.ink(colorScheme)
        return configuration.label
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(ink)
            .multilineTextAlignment(.center)
            .padding(.vertical, 13)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity)
            .background(
                Capsule(style: .continuous)
                    .fill(configuration.isPressed ? ink.opacity(0.06) : Color.clear)
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(ink, lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(duration: 0.2), value: configuration.isPressed)
    }
}
