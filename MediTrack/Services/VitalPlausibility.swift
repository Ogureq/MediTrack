//
//  VitalPlausibility.swift
//  MediTrack
//
//  Single source of truth for "is this vital reading physiologically
//  plausible" bounds. Before this file existed, the same eight ranges were
//  hand-copied in two places — `QuickAddParser`'s inline `guard` clauses and
//  `QuickAddAIService.isPlausible` — with no shared table, so the two paths
//  could silently drift apart. Both now call through here, so a
//  deterministic mis-parse and an AI hallucination are rejected identically.
//
//  Values are always canonical metric units (see `Support/Units.swift`):
//  kg, °C, mg/dL, %, breaths/min, hours. Conversion from display units
//  (lb, °F) happens before these bounds are checked, never after.
//

import Foundation

enum VitalPlausibility {

    /// Plausible range for the primary value of `type`, in canonical metric units.
    static func range(for type: VitalType) -> ClosedRange<Double> {
        switch type {
        case .bloodPressure: 60...260      // systolic, mmHg
        case .weight: 20...300             // kg
        case .heartRate: 25...250          // bpm
        case .temperature: 25...45         // °C
        case .bloodGlucose: 30...600       // mg/dL
        case .oxygenSaturation: 50...100   // %
        case .respiratoryRate: 4...60      // breaths/min
        case .sleepHours: 0...24           // hours
        }
    }

    /// Plausible range for the secondary value, when `type` uses one.
    /// Today that's only blood pressure's diastolic reading; every other
    /// vital type has no secondary value and returns nil.
    static func secondaryRange(for type: VitalType) -> ClosedRange<Double>? {
        switch type {
        case .bloodPressure: 30...200      // diastolic, mmHg
        default: nil
        }
    }

    /// True when `value` falls within `range(for: type)` and, for vitals
    /// that use one (blood pressure), `secondary` is non-nil and falls
    /// within `secondaryRange(for: type)`. Every other vital type ignores
    /// `secondary` entirely, so passing `nil` is always safe for them.
    static func isPlausible(_ value: Double, secondary: Double?, for type: VitalType) -> Bool {
        guard range(for: type).contains(value) else { return false }
        if let secondaryRange = secondaryRange(for: type) {
            guard let secondary, secondaryRange.contains(secondary) else { return false }
        }
        return true
    }
}
