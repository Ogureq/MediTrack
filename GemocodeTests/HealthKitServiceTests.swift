import XCTest
@testable import Gemocode

/// First coverage for `HealthKitService` — limited to its pure parts, since
/// the import paths themselves need a live HealthKit store. `importKey` is
/// the content-dedup key that keeps the 7-day re-scan overlap (and any
/// manual-import/observer race) from double-inserting readings, so its
/// shape is worth pinning: two samples collide exactly when type, date, and
/// stored values all match.
final class HealthKitServiceTests: XCTestCase {

    private let date = Date(timeIntervalSince1970: 1_700_000_000)

    func testIdenticalReadingsCollide() {
        XCTAssertEqual(
            HealthKitService.importKey(type: .weight, value: 82.5, secondary: nil, date: date),
            HealthKitService.importKey(type: .weight, value: 82.5, secondary: nil, date: date)
        )
    }

    func testDifferentTypeValueDateOrSecondaryAllDiffer() {
        let base = HealthKitService.importKey(type: .weight, value: 82.5, secondary: nil, date: date)
        XCTAssertNotEqual(base, HealthKitService.importKey(type: .heartRate, value: 82.5, secondary: nil, date: date))
        XCTAssertNotEqual(base, HealthKitService.importKey(type: .weight, value: 82.6, secondary: nil, date: date))
        XCTAssertNotEqual(base, HealthKitService.importKey(type: .weight, value: 82.5, secondary: nil, date: date.addingTimeInterval(1)))
        XCTAssertNotEqual(base, HealthKitService.importKey(type: .weight, value: 82.5, secondary: 80, date: date))
    }

    func testBloodPressureCollidesOnlyWithMatchingDiastolic() {
        let reading = HealthKitService.importKey(type: .bloodPressure, value: 128, secondary: 82, date: date)
        XCTAssertEqual(reading, HealthKitService.importKey(type: .bloodPressure, value: 128, secondary: 82, date: date))
        XCTAssertNotEqual(reading, HealthKitService.importKey(type: .bloodPressure, value: 128, secondary: 84, date: date))
    }

    func testOverlapWindowIsSevenDays() {
        XCTAssertEqual(HealthKitService.importOverlap, 7 * 24 * 3600)
    }
}
