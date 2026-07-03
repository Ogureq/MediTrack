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

/// Small colored capsule used for lab statuses and severities.
struct StatusPill: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }
}
