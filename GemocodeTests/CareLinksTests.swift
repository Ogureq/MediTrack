import XCTest
@testable import Gemocode

/// Coverage for `CareLinks.swift`: `MedicationLabLinks` (medication -> lab
/// link resolution + monitor status), `SymptomLabHints` (symptom -> lab
/// hints gated on out-of-range data), and `RxNameMatcher` (prescription-line
/// drug/dose/frequency extraction). None of these need a `ModelContainer` —
/// `Medication` is read-only here and can be instantiated standalone, same
/// as `ModelsTests` and `MedicationInteractionsTests`. Fixed dates are built
/// from `DateComponents`, no force-unwraps besides `XCTUnwrap`.
final class CareLinksTests: XCTestCase {

    /// Deterministic "today" used across status tests: 2025-07-15.
    private var fixedNow: Date!

    override func setUpWithError() throws {
        try super.setUpWithError()
        fixedNow = try date(year: 2025, month: 7, day: 15)
    }

    override func tearDownWithError() throws {
        fixedNow = nil
        try super.tearDownWithError()
    }

    private func date(year: Int, month: Int, day: Int, hour: Int = 9) throws -> Date {
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = day
        comps.hour = hour
        return try XCTUnwrap(Calendar.current.date(from: comps))
    }

    private func daysAgo(_ days: Int, from reference: Date) -> Date {
        reference.addingTimeInterval(-Double(days) * 86_400)
    }

    private func snapshot(id: String, status: LabStatus, date: Date) -> LabSnapshot {
        LabSnapshot(id: id, name: id, unit: "", value: 0, date: date, status: status, range: nil, reference: nil)
    }

    private func retestItem(id: String, status: RetestStatus, dueDate: Date) -> RetestItem {
        RetestItem(id: id, displayName: id, lastTestedAt: dueDate, intervalMonths: 6, dueDate: dueDate, status: status)
    }

    // MARK: - MedicationLabLinks: name resolution

    func testMetforminResolvesToHbA1cPrimaryAndFastingGlucoseSecondary() {
        let link = MedicationLabLinks.link(for: "Metformin 500mg")
        XCTAssertEqual(link?.labIDs, ["hba1c", "fastingGlucose"])
        XCTAssertNil(link?.vital)
    }

    func testStatinBrandAndGenericNamesResolveToTheSameLink() {
        let brand = MedicationLabLinks.link(for: "Lipitor")
        let generic = MedicationLabLinks.link(for: "Atorvastatin 20 mg")
        XCTAssertEqual(brand?.labIDs, ["ldlCholesterol", "totalCholesterol", "alt"])
        XCTAssertEqual(generic?.labIDs, brand?.labIDs)
    }

    func testAllFourStatinsShareTheSameDrugKey() {
        XCTAssertEqual(MedicationLabLinks.drugKey(for: "Atorvastatin"), "statin")
        XCTAssertEqual(MedicationLabLinks.drugKey(for: "Rosuvastatin"), "statin")
        XCTAssertEqual(MedicationLabLinks.drugKey(for: "Simvastatin"), "statin")
        XCTAssertEqual(MedicationLabLinks.drugKey(for: "Pravastatin"), "statin")
    }

    func testLevothyroxineResolvesToTshAndFreeT4() {
        let link = MedicationLabLinks.link(for: "Synthroid 75mcg")
        XCTAssertEqual(link?.labIDs, ["tsh", "freeT4"])
    }

    func testAceInhibitorAndArbShareThePotassiumCreatinineLink() {
        let ace = MedicationLabLinks.link(for: "Lisinopril 10mg")
        let arb = MedicationLabLinks.link(for: "Losartan 50mg")
        XCTAssertEqual(ace?.labIDs, ["potassium", "creatinine"])
        XCTAssertEqual(arb?.labIDs, ace?.labIDs)
    }

    func testAmlodipineIsVitalOnlyWithNoLinkedLab() {
        let link = MedicationLabLinks.link(for: "Amlodipine 5mg")
        XCTAssertEqual(link?.labIDs, [])
        XCTAssertEqual(link?.vital, .bloodPressure)
        XCTAssertNil(link?.primaryLabID)
    }

    func testWarfarinHasNoLabLinkBecauseInrIsNotInTheCatalog() {
        XCTAssertNil(MedicationLabLinks.drugKey(for: "Warfarin"))
        XCTAssertNil(MedicationLabLinks.link(for: "Warfarin 5mg"))
    }

    func testAllopurinolResolvesToUricAcid() {
        XCTAssertEqual(MedicationLabLinks.link(for: "Allopurinol")?.labIDs, ["uricAcid"])
    }

    func testIronSupplementResolvesToFerritinAndHemoglobin() {
        XCTAssertEqual(MedicationLabLinks.link(for: "Ferrous Sulfate 325mg")?.labIDs, ["ferritin", "hemoglobin"])
    }

    func testVitaminDSupplementResolvesToVitaminD() {
        XCTAssertEqual(MedicationLabLinks.link(for: "Vitamin D3 2000 IU")?.labIDs, ["vitaminD"])
    }

    func testPpiResolvesToB12AndMagnesium() {
        XCTAssertEqual(MedicationLabLinks.link(for: "Omeprazole 20mg")?.labIDs, ["vitaminB12", "magnesium"])
    }

    func testSpironolactoneResolvesToPotassium() {
        XCTAssertEqual(MedicationLabLinks.link(for: "Spironolactone 25mg")?.labIDs, ["potassium"])
    }

    func testCorticosteroidResolvesToGlucose() {
        XCTAssertEqual(MedicationLabLinks.link(for: "Prednisone 10mg")?.labIDs, ["fastingGlucose"])
    }

    func testUnrecognizedMedicationHasNoLink() {
        XCTAssertNil(MedicationLabLinks.link(for: "Vitamin Gummy"))
    }

    // MARK: - MedicationLabLinks: Russian/Turkish aliases

    func testRussianAliasMatchesMetformin() {
        XCTAssertEqual(MedicationLabLinks.drugKey(for: "Метформин"), "metformin")
    }

    func testRussianAliasMatchesAtorvastatin() {
        XCTAssertEqual(MedicationLabLinks.drugKey(for: "Аторвастатин 20 мг"), "statin")
    }

    func testRussianAliasMatchesLevothyroxine() {
        XCTAssertEqual(MedicationLabLinks.drugKey(for: "Левотироксин"), "levothyroxine")
    }

    func testTurkishAliasMatchesLevothyroxine() {
        // Turkish spelling differs from English ("levotiroksin"); metformin
        // and atorvastatin are already Latin-spelled the same way in Turkish.
        XCTAssertEqual(MedicationLabLinks.drugKey(for: "Levotiroksin"), "levothyroxine")
    }

    func testTurkishAndEnglishMetforminBothMatch() {
        XCTAssertEqual(MedicationLabLinks.drugKey(for: "Metformin"), "metformin")
    }

    // MARK: - MedicationLabLinks.status(for:...) — working / not improving

    func testStatusWorkingWhenLatestValueInRangeOnOrAfterStart() throws {
        let started = daysAgo(60, from: fixedNow)
        let measuredAt = daysAgo(5, from: fixedNow)
        let medication = Medication(name: "Metformin", startDate: started)
        let snapshots = [snapshot(id: "hba1c", status: .normal, date: measuredAt)]

        let status = try XCTUnwrap(
            MedicationLabLinks.status(for: medication, snapshots: snapshots, retestItems: [], now: fixedNow)
        )

        switch status {
        case let .working(labID, sinceDate):
            XCTAssertEqual(labID, "hba1c")
            XCTAssertEqual(sinceDate, measuredAt)
        default:
            XCTFail("expected .working, got \(status)")
        }
    }

    func testStatusNotImprovingWhenLatestValueOutOfRange() {
        let started = daysAgo(60, from: fixedNow)
        let measuredAt = daysAgo(5, from: fixedNow)
        let medication = Medication(name: "Metformin", startDate: started)
        let snapshots = [snapshot(id: "hba1c", status: .high, date: measuredAt)]

        let status = MedicationLabLinks.status(for: medication, snapshots: snapshots, retestItems: [], now: fixedNow)
        XCTAssertEqual(status, .notImproving(labID: "hba1c"))
    }

    func testStatusCheckOverdueTakesPriorityOverAnInRangeSnapshot() {
        let started = daysAgo(400, from: fixedNow)
        let measuredAt = daysAgo(200, from: fixedNow)
        let dueDate = daysAgo(20, from: fixedNow) // in the past -> overdue
        let medication = Medication(name: "Metformin", startDate: started)
        let snapshots = [snapshot(id: "hba1c", status: .normal, date: measuredAt)]
        let retestItems = [retestItem(id: "hba1c", status: .overdue, dueDate: dueDate)]

        let status = MedicationLabLinks.status(for: medication, snapshots: snapshots, retestItems: retestItems, now: fixedNow)
        XCTAssertEqual(status, .checkOverdue(labID: "hba1c", dueDate: dueDate))
    }

    func testStatusCheckOverdueAlsoFiresForDueSoon() {
        let started = daysAgo(200, from: fixedNow)
        let dueDate = fixedNow.addingTimeInterval(5 * 86_400) // due soon, not yet overdue
        let medication = Medication(name: "Metformin", startDate: started)
        let retestItems = [retestItem(id: "hba1c", status: .dueSoon, dueDate: dueDate)]

        let status = MedicationLabLinks.status(for: medication, snapshots: [], retestItems: retestItems, now: fixedNow)
        XCTAssertEqual(status, .checkOverdue(labID: "hba1c", dueDate: dueDate))
    }

    func testStatusNoDataWhenNothingIsKnownAboutTheLinkedLab() {
        let medication = Medication(name: "Metformin", startDate: daysAgo(60, from: fixedNow))
        let status = MedicationLabLinks.status(for: medication, snapshots: [], retestItems: [], now: fixedNow)
        XCTAssertEqual(status, .noData(labID: "hba1c"))
    }

    func testStatusNoDataWhenOnlyASnapshotBeforeMedicationStartExists() {
        // The only known value predates treatment, so it can't confirm the
        // medication is working — this must not report `.working`.
        let started = daysAgo(10, from: fixedNow)
        let measuredAt = daysAgo(60, from: fixedNow)
        let medication = Medication(name: "Metformin", startDate: started)
        let snapshots = [snapshot(id: "hba1c", status: .normal, date: measuredAt)]

        let status = MedicationLabLinks.status(for: medication, snapshots: snapshots, retestItems: [], now: fixedNow)
        XCTAssertEqual(status, .noData(labID: "hba1c"))
    }

    func testStatusIsNilForAVitalOnlyMedication() {
        let medication = Medication(name: "Amlodipine", startDate: daysAgo(60, from: fixedNow))
        let status = MedicationLabLinks.status(for: medication, snapshots: [], retestItems: [], now: fixedNow)
        XCTAssertNil(status)
    }

    func testStatusIsNilForAnUnrecognizedMedication() {
        let medication = Medication(name: "Vitamin Gummy", startDate: daysAgo(60, from: fixedNow))
        let status = MedicationLabLinks.status(for: medication, snapshots: [], retestItems: [], now: fixedNow)
        XCTAssertNil(status)
    }

    // MARK: - MedicationLabLinks.status(for:...) — long-term gating (PPI)

    func testPpiStatusIsNilBeforeTheLongTermThresholdIsReached() {
        let medication = Medication(name: "Omeprazole", startDate: daysAgo(10, from: fixedNow))
        let snapshots = [snapshot(id: "vitaminB12", status: .low, date: daysAgo(1, from: fixedNow))]

        let status = MedicationLabLinks.status(for: medication, snapshots: snapshots, retestItems: [], now: fixedNow)
        XCTAssertNil(status)
    }

    func testPpiStatusEvaluatesNormallyAfterTheLongTermThreshold() {
        let medication = Medication(name: "Omeprazole", startDate: daysAgo(100, from: fixedNow))
        let snapshots = [snapshot(id: "vitaminB12", status: .low, date: daysAgo(1, from: fixedNow))]

        let status = MedicationLabLinks.status(for: medication, snapshots: snapshots, retestItems: [], now: fixedNow)
        XCTAssertEqual(status, .notImproving(labID: "vitaminB12"))
    }

    // MARK: - SymptomLabHints

    func testFatigueWithLowFerritinProducesAHint() throws {
        let snapshots = [snapshot(id: "ferritin", status: .low, date: fixedNow)]
        let hints = SymptomLabHints.hints(for: "Fatigue", snapshots: snapshots)
        XCTAssertEqual(hints.count, 1)
        XCTAssertEqual(hints.first?.symptomID, "fatigue")
        XCTAssertEqual(hints.first?.labID, "ferritin")
        let status = try XCTUnwrap(hints.first?.status)
        switch status {
        case .low: break
        default: XCTFail("expected a low status, got \(status)")
        }
    }

    func testFatigueWithNormalFerritinProducesNoHint() {
        // Same symptom, but the lab is actually in range — must never be
        // surfaced speculatively.
        let snapshots = [snapshot(id: "ferritin", status: .normal, date: fixedNow)]
        let hints = SymptomLabHints.hints(for: "Fatigue", snapshots: snapshots)
        XCTAssertTrue(hints.isEmpty)
    }

    func testFatigueWithNoSnapshotDataProducesNoHint() {
        let hints = SymptomLabHints.hints(for: "Fatigue", snapshots: [])
        XCTAssertTrue(hints.isEmpty)
    }

    func testFatigueCanProduceMultipleHintsWhenSeveralLabsAreOutOfRange() {
        let snapshots = [
            snapshot(id: "ferritin", status: .low, date: fixedNow),
            snapshot(id: "tsh", status: .low, date: fixedNow),
            snapshot(id: "hemoglobin", status: .normal, date: fixedNow),
        ]
        let hints = SymptomLabHints.hints(for: "fatigue", snapshots: snapshots)
        XCTAssertEqual(Set(hints.map { $0.labID }), ["ferritin", "tsh"])
    }

    func testRussianAliasNormalizesToFatigueAndStillGatesOnOutOfRange() {
        XCTAssertEqual(SymptomLabHints.normalizedSymptomID(for: "Усталость"), "fatigue")
        let lowHints = SymptomLabHints.hints(for: "усталость", snapshots: [snapshot(id: "ferritin", status: .low, date: fixedNow)])
        XCTAssertEqual(lowHints.first?.labID, "ferritin")

        let normalHints = SymptomLabHints.hints(for: "усталость", snapshots: [snapshot(id: "ferritin", status: .normal, date: fixedNow)])
        XCTAssertTrue(normalHints.isEmpty)
    }

    func testDizzinessWithLowHemoglobinProducesAHintAndCarriesABloodPressureVitalAssociation() {
        let hints = SymptomLabHints.hints(for: "dizziness", snapshots: [snapshot(id: "hemoglobin", status: .low, date: fixedNow)])
        XCTAssertEqual(hints.first?.labID, "hemoglobin")
        XCTAssertEqual(SymptomLabHints.linkedVital(for: "dizziness"), .bloodPressure)
        XCTAssertNil(SymptomLabHints.linkedVital(for: "fatigue"))
    }

    func testMuscleCrampsGatedOnLowMagnesiumPotassiumOrCalcium() {
        let snapshots = [
            snapshot(id: "magnesium", status: .low, date: fixedNow),
            snapshot(id: "potassium", status: .normal, date: fixedNow),
            snapshot(id: "calcium", status: .criticalLow, date: fixedNow),
        ]
        let hints = SymptomLabHints.hints(for: "muscle cramps", snapshots: snapshots)
        XCTAssertEqual(Set(hints.map { $0.labID }), ["magnesium", "calcium"])
    }

    func testBoneOrJointPainGatedOnLowVitaminD() {
        let low = SymptomLabHints.hints(for: "joint pain", snapshots: [snapshot(id: "vitaminD", status: .low, date: fixedNow)])
        XCTAssertEqual(low.first?.labID, "vitaminD")

        let normal = SymptomLabHints.hints(for: "bone pain", snapshots: [snapshot(id: "vitaminD", status: .normal, date: fixedNow)])
        XCTAssertTrue(normal.isEmpty)
    }

    func testBruisingGatedOnLowPlatelets() {
        let hints = SymptomLabHints.hints(for: "bruising", snapshots: [snapshot(id: "platelets", status: .low, date: fixedNow)])
        XCTAssertEqual(hints.first?.labID, "platelets")
    }

    func testFrequentUrinationGatedOnHighGlucoseOrHbA1c() {
        let snapshots = [
            snapshot(id: "fastingGlucose", status: .high, date: fixedNow),
            snapshot(id: "hba1c", status: .normal, date: fixedNow),
        ]
        let hints = SymptomLabHints.hints(for: "frequent urination", snapshots: snapshots)
        XCTAssertEqual(hints.map { $0.labID }, ["fastingGlucose"])
    }

    func testColdIntoleranceGatedOnHighTsh() {
        let hints = SymptomLabHints.hints(for: "cold intolerance", snapshots: [snapshot(id: "tsh", status: .high, date: fixedNow)])
        XCTAssertEqual(hints.first?.labID, "tsh")

        let lowTshHints = SymptomLabHints.hints(for: "cold intolerance", snapshots: [snapshot(id: "tsh", status: .low, date: fixedNow)])
        XCTAssertTrue(lowTshHints.isEmpty)
    }

    func testHairLossHasNoDirectionMismatch() {
        let hints = SymptomLabHints.hints(
            for: "hair loss",
            snapshots: [
                snapshot(id: "ferritin", status: .low, date: fixedNow),
                snapshot(id: "tsh", status: .high, date: fixedNow),
            ]
        )
        XCTAssertEqual(Set(hints.map { $0.labID }), ["ferritin", "tsh"])
    }

    func testHeadacheNormalizesButHasNoHintRule() {
        XCTAssertEqual(SymptomLabHints.normalizedSymptomID(for: "headache"), "headache")
        let hints = SymptomLabHints.hints(for: "headache", snapshots: [snapshot(id: "tsh", status: .high, date: fixedNow)])
        XCTAssertTrue(hints.isEmpty)
    }

    func testUnknownSymptomProducesNoHints() {
        XCTAssertNil(SymptomLabHints.normalizedSymptomID(for: "purple elbows"))
        XCTAssertTrue(SymptomLabHints.hints(for: "purple elbows", snapshots: [snapshot(id: "tsh", status: .high, date: fixedNow)]).isEmpty)
    }

    // MARK: - RxNameMatcher

    func testDetectsRussianMetforminWithDoseAndFrequency() throws {
        let results = RxNameMatcher.detect(lines: ["Метформин 500 мг 2 раза в день"])
        let match = try XCTUnwrap(results.first)
        XCTAssertEqual(match.drugKey, "metformin")
        XCTAssertEqual(match.matchedName, "Метформин")
        XCTAssertEqual(match.doseValue, 500)
        XCTAssertEqual(match.doseUnit, "mg")
        XCTAssertEqual(match.frequencyHint, "2 раза в день")
        XCTAssertEqual(match.sourceLine, "Метформин 500 мг 2 раза в день")
    }

    func testDetectsEnglishAtorvastatinWithDoseAndFrequency() throws {
        let results = RxNameMatcher.detect(lines: ["Atorvastatin 20 mg nightly"])
        let match = try XCTUnwrap(results.first)
        XCTAssertEqual(match.drugKey, "statin")
        XCTAssertEqual(match.matchedName, "Atorvastatin")
        XCTAssertEqual(match.doseValue, 20)
        XCTAssertEqual(match.doseUnit, "mg")
        XCTAssertEqual(match.frequencyHint, "nightly")
    }

    func testDetectsMcgDoseForLevothyroxine() throws {
        let results = RxNameMatcher.detect(lines: ["Levothyroxine 75 mcg daily"])
        let match = try XCTUnwrap(results.first)
        XCTAssertEqual(match.drugKey, "levothyroxine")
        XCTAssertEqual(match.doseValue, 75)
        XCTAssertEqual(match.doseUnit, "mcg")
        XCTAssertEqual(match.frequencyHint, "daily")
    }

    func testDetectsIuDoseForVitaminD() throws {
        let results = RxNameMatcher.detect(lines: ["Vitamin D3 2000 IU once daily"])
        let match = try XCTUnwrap(results.first)
        XCTAssertEqual(match.drugKey, "vitaminDSupplement")
        XCTAssertEqual(match.doseValue, 2000)
        XCTAssertEqual(match.doseUnit, "iu")
    }

    func testMirroredMedicationInteractionsDrugIsAlsoDetected() throws {
        // Not part of MedicationLabLinks.table, but still a recognized drug
        // via the mirrored MedicationInteractions token set.
        let results = RxNameMatcher.detect(lines: ["Ibuprofen 200 mg twice daily"])
        let match = try XCTUnwrap(results.first)
        XCTAssertEqual(match.drugKey, "nsaid")
        XCTAssertEqual(match.doseValue, 200)
        XCTAssertEqual(match.doseUnit, "mg")
    }

    func testNoMatchLineProducesNoResult() {
        let results = RxNameMatcher.detect(lines: ["Take twice daily with food"])
        XCTAssertTrue(results.isEmpty)
    }

    func testBareIronWordIsNotMistakenForIronSupplement() {
        // False-positive guard: a bare "iron" token is deliberately excluded
        // from the synonym table, so ordinary text containing the word must
        // not be misread as a medication.
        let results = RxNameMatcher.detect(lines: ["Iron Man movie night with the kids"])
        XCTAssertTrue(results.isEmpty)
    }

    func testFrequencyCountWithoutAUnitIsNotMisreadAsADose() {
        // "2" here is a frequency count, not a dose — there's no recognized
        // unit token immediately after it, so doseValue must stay nil and
        // the whole remainder becomes the frequency hint.
        let results = RxNameMatcher.detect(lines: ["Metformin 2 times daily"])
        let match = results.first
        XCTAssertNil(match?.doseValue)
        XCTAssertNil(match?.doseUnit)
        XCTAssertEqual(match?.frequencyHint, "2 times daily")
    }

    func testDrugNameWithNoDoseOrFrequencyStillMatches() throws {
        let results = RxNameMatcher.detect(lines: ["Losartan"])
        let match = try XCTUnwrap(results.first)
        XCTAssertEqual(match.drugKey, "aceArb")
        XCTAssertNil(match.doseValue)
        XCTAssertNil(match.frequencyHint)
    }

    func testEachLineIsParsedIndependently() {
        let results = RxNameMatcher.detect(lines: [
            "Метформин 500 мг 2 раза в день",
            "Take twice daily with food",
            "Atorvastatin 20 mg nightly",
        ])
        XCTAssertEqual(results.count, 2)
        XCTAssertEqual(results.map { $0.drugKey }, ["metformin", "statin"])
    }

    func testShortLinesAreIgnored() {
        let results = RxNameMatcher.detect(lines: ["Rx", ""])
        XCTAssertTrue(results.isEmpty)
    }

    func testEmptyLinesArrayProducesNoResults() {
        XCTAssertTrue(RxNameMatcher.detect(lines: []).isEmpty)
    }
}
