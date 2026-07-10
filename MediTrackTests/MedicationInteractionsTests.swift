import XCTest
@testable import MediTrack

final class MedicationInteractionsTests: XCTestCase {

    func testWarfarinPlusIbuprofenProducesOneMajorInteraction() {
        let results = MedicationInteractions.check(medicationNames: ["Warfarin", "Ibuprofen"])
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.severity, .major)
    }

    func testEmptyListProducesNoInteractions() {
        let results = MedicationInteractions.check(medicationNames: [])
        XCTAssertTrue(results.isEmpty)
    }

    func testSameClassPairProducesNoInteraction() {
        // Two statins share the same class key, so no rule should fire between them.
        let results = MedicationInteractions.check(medicationNames: ["Atorvastatin", "Simvastatin"])
        XCTAssertTrue(results.isEmpty)
    }

    func testBrandNameMatching() {
        // "Coumadin" -> warfarin, "Advil" -> nsaid, matching the same major rule.
        let results = MedicationInteractions.check(medicationNames: ["Coumadin 5mg", "Advil"])
        XCTAssertEqual(results.count, 1)
        let interaction = try? XCTUnwrap(results.first)
        XCTAssertEqual(interaction?.severity, .major)
        XCTAssertEqual(interaction?.drugA, "Coumadin 5mg")
        XCTAssertEqual(interaction?.drugB, "Advil")
    }

    func testResultsAreSortedMajorFirst() {
        // warfarin+nsaid -> major, ace_inhibitor+nsaid -> moderate.
        let results = MedicationInteractions.check(
            medicationNames: ["Warfarin", "Lisinopril", "Ibuprofen"]
        )
        XCTAssertEqual(results.count, 2)
        for index in 1..<results.count {
            XCTAssertGreaterThanOrEqual(results[index - 1].severity, results[index].severity)
        }
        XCTAssertEqual(results.first?.severity, .major)
    }

    func testCaseInsensitivity() {
        let lower = MedicationInteractions.check(medicationNames: ["warfarin", "ibuprofen"])
        let upper = MedicationInteractions.check(medicationNames: ["WARFARIN", "IBUPROFEN"])
        let mixed = MedicationInteractions.check(medicationNames: ["WarFarin", "IbuProfen"])

        XCTAssertEqual(lower.count, 1)
        XCTAssertEqual(upper.count, 1)
        XCTAssertEqual(mixed.count, 1)
        XCTAssertEqual(lower.first?.severity, .major)
        XCTAssertEqual(upper.first?.severity, .major)
        XCTAssertEqual(mixed.first?.severity, .major)
    }

    func testUnrecognizedMedicationsProduceNoInteractions() {
        let results = MedicationInteractions.check(medicationNames: ["Vitamin Gummy", "Herbal Tea"])
        XCTAssertTrue(results.isEmpty)
    }

    func testSingleMedicationProducesNoInteractions() {
        let results = MedicationInteractions.check(medicationNames: ["Warfarin"])
        XCTAssertTrue(results.isEmpty)
    }
}
