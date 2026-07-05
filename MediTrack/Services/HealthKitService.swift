import Foundation
import HealthKit
import SwiftData

/// Imports vitals from Apple Health into the local SwiftData store.
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

    static func requestAuthorization() async throws {
        try await store.requestAuthorization(toShare: [], read: readTypes)
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
