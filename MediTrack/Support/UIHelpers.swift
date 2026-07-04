import SwiftUI

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

/// Small frosted-glass capsule used for lab statuses and severities.
struct StatusPill: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(.ultraThinMaterial, in: Capsule())
            .background(color.opacity(0.22), in: Capsule())
            .overlay(Capsule().strokeBorder(color.opacity(0.45), lineWidth: 1))
            .foregroundStyle(color)
    }
}
