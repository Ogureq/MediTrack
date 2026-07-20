import SwiftUI

// MARK: - Editorial component kit
//
// Shared building blocks for the paper-and-ink "editorial" design system:
// flat surfaces, hairline dividers, one accent, and the range-bar grammar
// that replaces gauges/gradients everywhere a value sits inside a
// reference range. Every color comes from the `Editorial` token enum in
// `Theme.swift` so light/dark mode stay correct automatically. See
// `<scratchpad>/EDITORIAL-TOKENS.md` for the full spec this file implements.

// MARK: - Range bar

/// Which segment of a `RangeBar` a zone represents.
enum RangeZoneKind {
    case out
    case inRange
    case optimal
}

/// A thin, capsule-clipped, segmented bar showing where a value sits inside
/// a reference range — the shared "range-bar" grammar used for the health
/// score, lab rows, and vitals throughout the editorial design system.
///
/// Six points tall; a 2.5pt marker overlay shows the current value's
/// position along the axis. Purely decorative on its own (the adjacent row
/// text usually already states the value/status), so it hides itself from
/// VoiceOver unless an `accessibilityLabel` is supplied.
struct RangeBar: View {
    let zones: [(fraction: CGFloat, kind: RangeZoneKind)]
    let marker: CGFloat
    let accessibilityText: Text?

    @Environment(\.colorScheme) private var colorScheme

    init(
        zones: [(fraction: CGFloat, kind: RangeZoneKind)],
        marker: CGFloat,
        accessibilityLabel: Text? = nil
    ) {
        self.zones = zones
        self.marker = min(1, max(0, marker))
        self.accessibilityText = accessibilityLabel
    }

    /// Convenience initializer for lab-style rows: builds an out/in/out
    /// three-zone layout from a reference range (`lower`...`upper`) within
    /// an overall axis (`min`...`max`), with the marker placed at `value`'s
    /// position. This is what lab result rows use.
    init(
        lower: Double,
        upper: Double,
        min: Double,
        max: Double,
        value: Double,
        accessibilityLabel: Text? = nil
    ) {
        let axisSpan = Swift.max(max - min, .ulpOfOne)
        func fraction(_ x: Double) -> CGFloat {
            CGFloat(Swift.min(Swift.max((x - min) / axisSpan, 0), 1))
        }
        let lowerFraction = fraction(lower)
        let upperFraction = fraction(upper)
        let rangeStart = Swift.min(lowerFraction, upperFraction)
        let rangeEnd = Swift.max(lowerFraction, upperFraction)

        self.zones = [
            (fraction: rangeStart, kind: .out),
            (fraction: rangeEnd - rangeStart, kind: .inRange),
            (fraction: 1 - rangeEnd, kind: .out),
        ]
        self.marker = fraction(value)
        self.accessibilityText = accessibilityLabel
    }

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            let markerWidth: CGFloat = 2.5

            ZStack(alignment: .leading) {
                HStack(spacing: 0) {
                    ForEach(Array(zones.enumerated()), id: \.offset) { _, zone in
                        color(for: zone.kind)
                            .frame(width: width * max(0, zone.fraction), height: height)
                    }
                }
                Editorial.barMarker(colorScheme)
                    .frame(width: markerWidth, height: height)
                    .offset(x: min(max(0, width * marker), max(0, width - markerWidth)))
            }
        }
        .frame(height: 6)
        .clipShape(Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityHidden(accessibilityText == nil)
        .accessibilityLabel(accessibilityText ?? Text(""))
    }

    private func color(for kind: RangeZoneKind) -> Color {
        switch kind {
        case .out: Editorial.zoneOut(colorScheme)
        case .inRange: Editorial.zoneIn(colorScheme)
        case .optimal: Editorial.zoneOptimal(colorScheme)
        }
    }
}

// MARK: - Status tag

/// Which status color an `EditorialTag` renders.
enum TagKind {
    case good
    case warn
    case bad
}

/// Small uppercase status pill — "High", "Low", "Overdue", "Good" — the
/// editorial replacement for `StatusPill`. 9pt semibold uppercase with
/// wide tracking on a solid color capsule; the visible text itself is
/// what VoiceOver reads, so no separate accessibility label is required.
struct EditorialTag: View {
    private let text: Text
    let kind: TagKind

    @Environment(\.colorScheme) private var colorScheme

    init(_ text: LocalizedStringKey, kind: TagKind) {
        self.text = Text(text)
        self.kind = kind
    }

    init(verbatim text: String, kind: TagKind) {
        self.text = Text(verbatim: text)
        self.kind = kind
    }

    var body: some View {
        text
            .font(.system(size: 9, weight: .semibold))
            .kerning(0.72)
            .textCase(.uppercase)
            .foregroundStyle(.white)
            .padding(.vertical, 3)
            .padding(.horizontal, 8)
            .background(fill, in: Capsule())
    }

    private var fill: Color {
        switch kind {
        case .good: Editorial.tagGood(colorScheme)
        case .warn: Editorial.tagWarn(colorScheme)
        case .bad: Editorial.tagBad(colorScheme)
        }
    }
}

// MARK: - Micro label

/// Uppercase section-header style used everywhere the old section header
/// text style used to appear ("NEEDS ATTENTION · 3", "IN THIS DRAW").
/// 10pt semibold, wide tracking, muted color.
struct MicroLabel: View {
    private let text: Text

    @Environment(\.colorScheme) private var colorScheme

    init(_ text: LocalizedStringKey) {
        self.text = Text(text)
    }

    init(verbatim text: String) {
        self.text = Text(verbatim: text)
    }

    var body: some View {
        text
            .font(.system(size: 10, weight: .semibold))
            .kerning(1.6)
            .textCase(.uppercase)
            .foregroundStyle(Editorial.muted(colorScheme))
    }
}

// MARK: - Buttons

/// The one big-button style in the editorial system: a full-width outlined
/// pill (e.g. "Scan a report"). Never filled — accent fill is reserved for
/// small inline actions.
struct OutlinedPillButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme

    func makeBody(configuration: Configuration) -> some View {
        let ink = Editorial.ink(colorScheme)
        return configuration.label
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(ink)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .fill(configuration.isPressed ? ink.opacity(0.06) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .strokeBorder(ink, lineWidth: 1)
            )
    }
}

/// Small filled accent capsule for inline primary actions only (e.g.
/// "Book") — never used as a full-width CTA.
struct AccentPillButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.white)
            .padding(.vertical, 9)
            .padding(.horizontal, 16)
            .background(
                Capsule()
                    .fill(Editorial.accent(colorScheme))
                    .opacity(configuration.isPressed ? 0.75 : 1)
            )
    }
}

// MARK: - Ledger row

private struct LedgerRowModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .padding(.vertical, 13)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(Editorial.hairline(colorScheme))
                    .frame(height: 0.5)
                    .accessibilityHidden(true)
            }
    }
}

extension View {
    /// Flat "ledger" list row: vertical padding plus a hairline bottom
    /// divider, no card background. Lists in the editorial system are flat
    /// ledgers, not floating cards.
    func ledgerRow() -> some View {
        modifier(LedgerRowModifier())
    }
}

// MARK: - Pill tab bar

/// Capsule tab bar used for the primary navigation (Today / Markers /
/// Reports / Schedule / More). Fill/text invert together with color
/// scheme: `Editorial.ink` is already black in light mode and near-white
/// in dark mode, `Editorial.canvas` is the mirror image of that, so using
/// them directly for fill/text reproduces the spec's "light: black bg
/// white text; dark: light bg dark text" without any hardcoded colors.
struct PillTabBar: View {
    let items: [(label: LocalizedStringKey, icon: String, tag: Int)]
    @Binding var selection: Int

    @Environment(\.colorScheme) private var colorScheme

    init(items: [(label: LocalizedStringKey, icon: String, tag: Int)], selection: Binding<Int>) {
        self.items = items
        self._selection = selection
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(items, id: \.tag) { item in
                let isSelected = item.tag == selection

                Button {
                    selection = item.tag
                } label: {
                    Text(item.label)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .opacity(isSelected ? 1 : 0.55)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
                .accessibilityLabel(Text(item.label))
            }
        }
        .foregroundStyle(Editorial.canvas(colorScheme))
        .padding(.vertical, 13)
        .padding(.horizontal, 24)
        .background(Editorial.ink(colorScheme), in: Capsule())
    }
}
