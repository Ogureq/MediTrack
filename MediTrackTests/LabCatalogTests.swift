import XCTest
@testable import MediTrack

final class LabCatalogTests: XCTestCase {

    func testReferenceFindsKnownTestByID() throws {
        let hemoglobin = try XCTUnwrap(LabCatalog.reference(for: "hemoglobin"))
        XCTAssertEqual(hemoglobin.name, "Hemoglobin")
        XCTAssertEqual(hemoglobin.shortName, "Hgb")
        XCTAssertEqual(hemoglobin.category, .hematology)
    }

    func testReferenceIsCaseInsensitive() throws {
        let mixedCase = try XCTUnwrap(LabCatalog.reference(for: "HeMoGlObIn"))
        XCTAssertEqual(mixedCase.id, "hemoglobin")
    }

    func testReferenceReturnsNilForUnknownID() {
        XCTAssertNil(LabCatalog.reference(for: "not_a_real_test"))
    }

    func testSearchByPartialName() {
        let results = LabCatalog.search("gluc")
        XCTAssertTrue(results.contains { $0.id == "fastingGlucose" })
    }

    func testSearchByShortName() {
        let results = LabCatalog.search("hgb")
        XCTAssertTrue(results.contains { $0.id == "hemoglobin" })
    }

    func testSearchWithEmptyQueryReturnsAllTests() {
        let results = LabCatalog.search("")
        XCTAssertEqual(results.count, LabCatalog.tests.count)
    }

    func testSearchWithNoMatchesReturnsEmpty() {
        let results = LabCatalog.search("zzzznonexistent")
        XCTAssertTrue(results.isEmpty)
    }

    func testAllRangesAreSaneWhereBothBoundsExist() {
        for test in LabCatalog.tests {
            if let common = test.commonRange {
                XCTAssertLessThanOrEqual(common.lowerBound, common.upperBound, "commonRange for \(test.id)")
            }
            if let male = test.maleRange {
                XCTAssertLessThanOrEqual(male.lowerBound, male.upperBound, "maleRange for \(test.id)")
            }
            if let female = test.femaleRange {
                XCTAssertLessThanOrEqual(female.lowerBound, female.upperBound, "femaleRange for \(test.id)")
            }
        }
    }

    func testTestsInCategoryFiltersCorrectly() {
        let hematologyTests = LabCatalog.tests(in: .hematology)
        XCTAssertFalse(hematologyTests.isEmpty)
        XCTAssertTrue(hematologyTests.allSatisfy { $0.category == .hematology })
    }

    func testReferenceRangeForSexFallsBackToCommonRange() throws {
        let glucose = try XCTUnwrap(LabCatalog.reference(for: "fastingGlucose"))
        XCTAssertEqual(glucose.referenceRange(for: .male), glucose.commonRange)
        XCTAssertEqual(glucose.referenceRange(for: .female), glucose.commonRange)
        XCTAssertEqual(glucose.referenceRange(for: .unspecified), glucose.commonRange)
    }

    func testReferenceRangeForSexUsesSexSpecificRangeWhenAvailable() throws {
        let hemoglobin = try XCTUnwrap(LabCatalog.reference(for: "hemoglobin"))
        XCTAssertEqual(hemoglobin.referenceRange(for: .male), hemoglobin.maleRange)
        XCTAssertEqual(hemoglobin.referenceRange(for: .female), hemoglobin.femaleRange)
    }

    // MARK: LabSynonyms

    func testSynonymsMatchAliasedLowercasedLine() throws {
        let match = try XCTUnwrap(LabSynonyms.match(in: "a1c 5.4 %"))
        XCTAssertEqual(match.reference.id, "hba1c")
    }

    func testSynonymsMatchCatalogShortName() throws {
        let match = try XCTUnwrap(LabSynonyms.match(in: "hgb 13.5 g/dl"))
        XCTAssertEqual(match.reference.id, "hemoglobin")
    }

    func testSynonymsMatchReturnsNilWhenNothingMatches() {
        XCTAssertNil(LabSynonyms.match(in: "patient name: john doe"))
    }

    func testSynonymsRespectsWordBoundaries() {
        // "iron" should not match inside "environment".
        XCTAssertNil(LabSynonyms.match(in: "environment report"))
    }
}
