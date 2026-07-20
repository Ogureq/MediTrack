import SwiftUI
import UIKit

/// Lightweight haptics wrapper used by the save actions across the app.
enum Haptics {
    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}

extension Severity {
    var color: Color {
        switch self {
        case .critical: .red
        case .attention: .orange
        case .info: .blue
        }
    }
}

extension LabStatus {
    var color: Color {
        switch self {
        case .criticalLow, .criticalHigh: .red
        case .low, .high: .orange
        case .normal: .green
        case .unknown: .gray
        }
    }
}

extension TrendDirection {
    var color: Color {
        switch self {
        case .improving: .green
        case .worsening: .red
        case .stable: .gray
        case .rising, .falling: .blue
        }
    }
}

/// Small solid-fill capsule used for lab statuses and severities — the
/// editorial "tag" style: 9pt semibold uppercase white text on a solid
/// color capsule. `color` is mapped to the nearest editorial tag token
/// (green-family → good, orange/yellow → warn, red → bad) so callers that
/// still pass a system color (`.green`, `.orange`, `.red`, from the
/// `Severity`/`LabStatus`/`TrendDirection` extensions above) render with
/// exact editorial hex values; any other color passes through unchanged.
struct StatusPill: View {
    let text: String
    let color: Color

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Text(text)
            .font(.system(size: 9, weight: .semibold))
            .kerning(0.72)
            .textCase(.uppercase)
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(fill, in: Capsule())
    }

    private var fill: Color {
        switch color {
        case .green, .mint:
            Editorial.tagGood(colorScheme)
        case .orange, .yellow:
            Editorial.tagWarn(colorScheme)
        case .red:
            Editorial.tagBad(colorScheme)
        default:
            color
        }
    }
}
