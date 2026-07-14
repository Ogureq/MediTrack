import Foundation

// MARK: - Unit preferences
//
// Vitals are stored canonically (kg, °C, mg/dL). These helpers convert to and
// from the user's preferred display units, chosen in Profile & Settings.

enum WeightUnit: String, CaseIterable, Identifiable {
    case kilograms
    case pounds

    var id: String { rawValue }

    var label: String {
        switch self {
        case .kilograms: "kg"
        case .pounds: "lb"
        }
    }
}

enum TemperatureUnit: String, CaseIterable, Identifiable {
    case celsius
    case fahrenheit

    var id: String { rawValue }

    var label: String {
        switch self {
        case .celsius: "°C"
        case .fahrenheit: "°F"
        }
    }
}

enum GlucoseUnit: String, CaseIterable, Identifiable {
    case mgdL
    case mmolL

    var id: String { rawValue }

    var label: String {
        switch self {
        case .mgdL: "mg/dL"
        case .mmolL: "mmol/L"
        }
    }
}

enum Units {
    static let weightKey = "unit.weight"
    static let temperatureKey = "unit.temperature"
    static let glucoseKey = "unit.glucose"

    static var weight: WeightUnit {
        WeightUnit(rawValue: UserDefaults.standard.string(forKey: weightKey) ?? "") ?? .kilograms
    }

    static var temperature: TemperatureUnit {
        TemperatureUnit(rawValue: UserDefaults.standard.string(forKey: temperatureKey) ?? "") ?? .celsius
    }

    static var glucose: GlucoseUnit {
        GlucoseUnit(rawValue: UserDefaults.standard.string(forKey: glucoseKey) ?? "") ?? .mgdL
    }

    /// Canonical → display units.
    static func display(_ value: Double, for type: VitalType) -> Double {
        switch type {
        case .weight:
            weight == .pounds ? value * 2.204_62 : value
        case .temperature:
            temperature == .fahrenheit ? value * 9 / 5 + 32 : value
        case .bloodGlucose:
            glucose == .mmolL ? value / 18.018 : value
        default:
            value
        }
    }

    /// Display units → canonical.
    static func canonical(_ value: Double, for type: VitalType) -> Double {
        switch type {
        case .weight:
            weight == .pounds ? value / 2.204_62 : value
        case .temperature:
            temperature == .fahrenheit ? (value - 32) * 5 / 9 : value
        case .bloodGlucose:
            glucose == .mmolL ? value * 18.018 : value
        default:
            value
        }
    }

    /// Display unit label for a vital type (falls back to the canonical unit).
    static func label(for type: VitalType) -> String {
        switch type {
        case .weight: weight.label
        case .temperature: temperature.label
        case .bloodGlucose: glucose.label
        default: type.unit
        }
    }

    /// Value formatted in the user's display units, with the unit label.
    static func formatted(_ value: Double, for type: VitalType) -> String {
        "\(display(value, for: type).compactFormatted) \(label(for: type))"
    }

    /// Range converted to display units (handles order inversion safely).
    static func displayRange(_ range: ClosedRange<Double>, for type: VitalType) -> ClosedRange<Double> {
        let a = display(range.lowerBound, for: type)
        let b = display(range.upperBound, for: type)
        return min(a, b)...max(a, b)
    }
}
