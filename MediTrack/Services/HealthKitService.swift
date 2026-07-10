import Foundation
import HealthKit
import SwiftData

/// Imports vitals from Apple Health into the local SwiftData store, and
/// optionally writes newly logged vitals back to Apple Health.
enum HealthKitService {

    static var isAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    private static let store = HKHealthStore()

    private static var readTypes: Set<HKObjectType> {
        let identifiers: [HKQuantityTypeIdentifier] = [
            .bodyMass,
            .heartRate,
            .bloodGlucose,
            .oxygenSaturation,
            .bodyTemperature,
            .bloodPressureSystolic,
            .bloodPressureDiastolic,
        ]
        var types = Set<HKObjectType>()
        for identifier in identifiers {
            if let type = HKObjectType.quantityType(forIdentifier: identifier) {
                types.insert(type)
            }
        }
        return types
    }

    /// Quantity types this service knows how to write, mirroring the vital
    /// types accepted by `write(sample:)`.
    private static var writeTypes: Set<HKSampleType> {
        let identifiers: [HKQuantityTypeIdentifier] = [
            .bodyMass,
            .heartRate,
            .bloodGlucose,
            .oxygenSaturation,
            .bodyTemperature,
            .respiratoryRate,
            .bloodPressureSystolic,
            .bloodPressureDiastolic,
        ]
        var types = Set<HKSampleType>()
        for identifier in identifiers {
            if let type = HKObjectType.quantityType(forIdentifier: identifier) {
                types.insert(type)
            }
        }
        if let correlationType = HKObjectType.correlationType(forIdentifier: .bloodPressure) {
            types.insert(correlationType)
        }
        return types
    }

    static func requestAuthorization() async throws {
        try await store.requestAuthorization(toShare: [], read: readTypes)
    }

    /// Requests permission to write vitals to Apple Health. Safe to call
    /// repeatedly — HealthKit only prompts the user once per type.
    static func requestWriteAuthorization() async throws {
        try await store.requestAuthorization(toShare: writeTypes, read: [])
    }

    /// Whether `write(sample:)` can represent this vital type in Apple Health.
    /// `sleepHours` is excluded: HealthKit models sleep as category samples
    /// with per-stage time ranges, which this app doesn't collect, so a
    /// plain duration can't be written back faithfully.
    static func isWritable(_ type: VitalType) -> Bool {
        switch type {
        case .weight, .bloodPressure, .heartRate, .bloodGlucose, .oxygenSaturation, .temperature, .respiratoryRate:
            return true
        case .sleepHours:
            return false
        }
    }

    /// Writes a single logged vital to Apple Health. Does nothing for types
    /// `isWritable` reports as unsupported.
    static func write(sample: VitalSample) async throws {
        guard isWritable(sample.type) else { return }

        if sample.type == .bloodPressure {
            try await writeBloodPressure(sample)
            return
        }

        guard let mapping = quantityMapping(for: sample.type),
              let quantityType = HKObjectType.quantityType(forIdentifier: mapping.identifier) else {
            return
        }
        let quantity = HKQuantity(unit: mapping.unit, doubleValue: sample.value / mapping.scale)
        let hkSample = HKQuantitySample(type: quantityType, quantity: quantity, start: sample.date, end: sample.date)
        try await store.save(hkSample)
    }

    /// Maps a writable vital type to its HealthKit identifier, unit, and the
    /// scale factor applied on import (kept in sync with `importVitals`).
    private static func quantityMapping(for type: VitalType) -> (identifier: HKQuantityTypeIdentifier, unit: HKUnit, scale: Double)? {
        switch type {
        case .weight:
            return (.bodyMass, .gramUnit(with: .kilo), 1)
        case .heartRate:
            return (.heartRate, HKUnit.count().unitDivided(by: .minute()), 1)
        case .bloodGlucose:
            return (.bloodGlucose, HKUnit(from: "mg/dL"), 1)
        case .oxygenSaturation:
            return (.oxygenSaturation, .percent(), 100)
        case .temperature:
            return (.bodyTemperature, .degreeCelsius(), 1)
        case .respiratoryRate:
            return (.respiratoryRate, HKUnit.count().unitDivided(by: .minute()), 1)
        case .bloodPressure, .sleepHours:
            return nil
        }
    }

    private static func writeBloodPressure(_ sample: VitalSample) async throws {
        guard let secondaryValue = sample.secondaryValue,
              let correlationType = HKObjectType.correlationType(forIdentifier: .bloodPressure),
              let systolicType = HKObjectType.quantityType(forIdentifier: .bloodPressureSystolic),
              let diastolicType = HKObjectType.quantityType(forIdentifier: .bloodPressureDiastolic) else {
            return
        }
        let systolic = HKQuantitySample(
            type: systolicType,
            quantity: HKQuantity(unit: .millimeterOfMercury(), doubleValue: sample.value),
            start: sample.date,
            end: sample.date
        )
        let diastolic = HKQuantitySample(
            type: diastolicType,
            quantity: HKQuantity(unit: .millimeterOfMercury(), doubleValue: secondaryValue),
            start: sample.date,
            end: sample.date
        )
        let correlation = HKCorrelation(
            type: correlationType,
            start: sample.date,
            end: sample.date,
            objects: [systolic, diastolic]
        )
        try await store.save(correlation)
    }

    /// Imports samples recorded after `since` and returns how many were added.
    @MainActor
    static func importVitals(since: Date, into context: ModelContext) async throws -> Int {
        var imported = 0
        let note = "Imported from Apple Health"

        // Simple quantity types → (HealthKit identifier, vital type, unit, scale).
        let mappings: [(HKQuantityTypeIdentifier, VitalType, HKUnit, Double)] = [
            (.bodyMass, .weight, .gramUnit(with: .kilo), 1),
            (.heartRate, .heartRate, HKUnit.count().unitDivided(by: .minute()), 1),
            (.bloodGlucose, .bloodGlucose, HKUnit(from: "mg/dL"), 1),
            (.oxygenSaturation, .oxygenSaturation, .percent(), 100),
            (.bodyTemperature, .temperature, .degreeCelsius(), 1),
        ]

        for (identifier, vitalType, unit, scale) in mappings {
            guard let quantityType = HKObjectType.quantityType(forIdentifier: identifier) else { continue }
            let samples = try await quantitySamples(of: quantityType, since: since)
            for sample in samples {
                let raw = sample.quantity.doubleValue(for: unit) * scale
                let value = (raw * 10).rounded() / 10
                context.insert(VitalSample(type: vitalType, value: value, date: sample.startDate, note: note))
                imported += 1
            }
        }

        // Blood pressure arrives as a correlation of systolic + diastolic.
        if let correlationType = HKObjectType.correlationType(forIdentifier: .bloodPressure),
           let systolicType = HKObjectType.quantityType(forIdentifier: .bloodPressureSystolic),
           let diastolicType = HKObjectType.quantityType(forIdentifier: .bloodPressureDiastolic) {
            let correlations = try await correlationSamples(of: correlationType, since: since)
            for correlation in correlations {
                guard let systolic = correlation.objects(for: systolicType).first as? HKQuantitySample,
                      let diastolic = correlation.objects(for: diastolicType).first as? HKQuantitySample else {
                    continue
                }
                context.insert(VitalSample(
                    type: .bloodPressure,
                    value: systolic.quantity.doubleValue(for: .millimeterOfMercury()).rounded(),
                    secondaryValue: diastolic.quantity.doubleValue(for: .millimeterOfMercury()).rounded(),
                    date: correlation.startDate,
                    note: note
                ))
                imported += 1
            }
        }

        return imported
    }

    // MARK: Queries

    private static func quantitySamples(of type: HKQuantityType, since: Date) async throws -> [HKQuantitySample] {
        let predicate = HKQuery.predicateForSamples(withStart: since, end: nil, options: .strictStartDate)
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: 500,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: (samples as? [HKQuantitySample]) ?? [])
                }
            }
            store.execute(query)
        }
    }

    private static func correlationSamples(of type: HKCorrelationType, since: Date) async throws -> [HKCorrelation] {
        let predicate = HKQuery.predicateForSamples(withStart: since, end: nil, options: .strictStartDate)
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: 500,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: (samples as? [HKCorrelation]) ?? [])
                }
            }
            store.execute(query)
        }
    }
}
