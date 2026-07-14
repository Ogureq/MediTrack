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

    /// Simple quantity types → (HealthKit identifier, vital type, unit, scale).
    /// Shared by `importVitals` (manual + automatic sync both funnel through
    /// it) and `observedSampleTypes` (automatic sync's observer list), so the
    /// two can never drift apart.
    private static let quantityImportMappings: [(HKQuantityTypeIdentifier, VitalType, HKUnit, Double)] = [
        (.bodyMass, .weight, .gramUnit(with: .kilo), 1),
        (.heartRate, .heartRate, HKUnit.count().unitDivided(by: .minute()), 1),
        (.bloodGlucose, .bloodGlucose, HKUnit(from: "mg/dL"), 1),
        (.oxygenSaturation, .oxygenSaturation, .percent(), 100),
        (.bodyTemperature, .temperature, .degreeCelsius(), 1),
    ]

    /// Imports samples recorded after `since` and returns how many were
    /// added. This is the shared incremental-import core: the manual
    /// "Import from Apple Health" button in ProfileView and the automatic
    /// background sync observer (`runIncrementalSync`) both call this same
    /// function rather than duplicating the fetch/mapping/dedupe logic.
    @MainActor
    static func importVitals(since: Date, into context: ModelContext) async throws -> Int {
        var imported = 0
        let note = "Imported from Apple Health"

        for (identifier, vitalType, unit, scale) in quantityImportMappings {
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

    // MARK: Automatic Sync

    /// UserDefaults key persisting whether automatic background sync is on.
    /// Opt-in and off by default, matching the app's privacy stance: nothing
    /// talks to Apple Health on its own until the user asks it to.
    static let automaticSyncKey = "healthkit.automaticSync"

    /// UserDefaults key for the incremental-import high-water mark, shared
    /// between the manual "Import from Apple Health" button (ProfileView's
    /// `lastHealthImportAt` @AppStorage) and automatic sync, so neither path
    /// re-imports what the other already pulled in.
    private static let lastImportDefaultsKey = "lastHealthImportAt"

    /// Sample types automatic sync observes — derived from the same mapping
    /// table `importVitals` uses, plus the blood-pressure correlation, so
    /// there is exactly one list of "types this app knows how to import" to
    /// keep in sync.
    private static var observedSampleTypes: [HKSampleType] {
        var types: [HKSampleType] = []
        for (identifier, _, _, _) in quantityImportMappings {
            if let type = HKObjectType.quantityType(forIdentifier: identifier) {
                types.append(type)
            }
        }
        if let correlationType = HKObjectType.correlationType(forIdentifier: .bloodPressure) {
            types.append(correlationType)
        }
        return types
    }

    @MainActor
    private static var observerQueries: [HKObserverQuery] = []

    /// Registers HealthKit observer queries + hourly background delivery for
    /// every sample type `importVitals` knows how to map, if automatic sync
    /// is turned on and HealthKit is available. Call this once at app
    /// launch (see `MediTrackApp`) — it is a cheap no-op when the toggle is
    /// off.
    ///
    /// Honest limits: background delivery needs a real device with the
    /// HealthKit entitlement + a provisioning profile applied; it is
    /// silently inert in the Simulator and in CI (`isAvailable` guards
    /// that — this never crashes there, it just does nothing). Even on
    /// device, HealthKit only wakes a *suspended* MediTrack process for new
    /// data — a fully terminated app still needs the user to relaunch it,
    /// or a foreground/background refresh, before the next observer fire.
    static func startAutomaticSyncIfEnabled(container: ModelContainer) {
        guard isAvailable, UserDefaults.standard.bool(forKey: automaticSyncKey) else { return }
        Task { await startObservers(container: container) }
    }

    /// Starts automatic sync unconditionally (HealthKit availability
    /// permitting). Call after authorization has been granted, e.g. from
    /// the Profile toggle's `onChange` handler when it turns on.
    static func startAutomaticSync(container: ModelContainer) async {
        guard isAvailable else { return }
        await startObservers(container: container)
    }

    /// Stops automatic sync: tears down observer queries and disables
    /// background delivery so HealthKit stops waking MediTrack for this
    /// data. Safe to call even if sync was never started.
    static func stopAutomaticSync() {
        guard isAvailable else { return }
        Task { @MainActor in
            for query in observerQueries {
                store.stop(query)
            }
            observerQueries.removeAll()
            store.disableAllBackgroundDelivery { _, _ in }
        }
    }

    @MainActor
    private static func startObservers(container: ModelContainer) async {
        for query in observerQueries {
            store.stop(query)
        }
        observerQueries.removeAll()

        for type in observedSampleTypes {
            let query = HKObserverQuery(sampleType: type, predicate: nil) { _, completionHandler, error in
                Task {
                    defer { completionHandler() }
                    guard error == nil else { return }
                    await runIncrementalSync(container: container)
                }
            }
            store.execute(query)
            observerQueries.append(query)
            store.enableBackgroundDelivery(for: type, frequency: .hourly) { _, _ in
                // Best-effort: background delivery can fail to register
                // without a provisioning profile (Simulator, unsigned CI
                // builds). Observers still fire while the app is running
                // either way, so we don't surface this to the user.
            }
        }
    }

    /// Runs the shared `importVitals` core against a context created from
    /// `container` (background-safe: no dependency on any view's live
    /// `ModelContext`), then advances the shared high-water mark. Always
    /// completes without throwing — the observer that calls this must
    /// invoke HealthKit's completion handler no matter what happens here,
    /// or HealthKit backs off future delivery.
    @MainActor
    private static func runIncrementalSync(container: ModelContainer) async {
        let context = ModelContext(container)
        let since = lastImportDate()
        do {
            _ = try await importVitals(since: since, into: context)
            try context.save()
            setLastImportDate(.now)
        } catch {
            // Best-effort background sync: leave the high-water mark alone
            // so the next observer fire (or a manual import) retries the
            // same window instead of silently losing readings.
        }
    }

    private static func lastImportDate() -> Date {
        let stored = UserDefaults.standard.double(forKey: lastImportDefaultsKey)
        if stored > 0 {
            return Date(timeIntervalSince1970: stored)
        }
        return Calendar.current.date(byAdding: .year, value: -1, to: .now) ?? .now
    }

    private static func setLastImportDate(_ date: Date) {
        UserDefaults.standard.set(date.timeIntervalSince1970, forKey: lastImportDefaultsKey)
    }
}
