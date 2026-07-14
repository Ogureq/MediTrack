import XCTest
@testable import Gemocode

final class UnitsTests: XCTestCase {

    override func setUp() {
        super.setUp()
        clearUnitDefaults()
    }

    override func tearDown() {
        clearUnitDefaults()
        super.tearDown()
    }

    private func clearUnitDefaults() {
        UserDefaults.standard.removeObject(forKey: Units.weightKey)
        UserDefaults.standard.removeObject(forKey: Units.temperatureKey)
        UserDefaults.standard.removeObject(forKey: Units.glucoseKey)
    }

    // MARK: Weight (kg <-> lb)

    func testWeightDefaultsToKilogramsUnchanged() {
        XCTAssertEqual(Units.weight, .kilograms)
        XCTAssertEqual(Units.display(70, for: .weight), 70, accuracy: 0.01)
        XCTAssertEqual(Units.canonical(70, for: .weight), 70, accuracy: 0.01)
    }

    func testWeightKilogramsToPoundsConversion() {
        UserDefaults.standard.set(WeightUnit.pounds.rawValue, forKey: Units.weightKey)
        XCTAssertEqual(Units.weight, .pounds)
        let displayed = Units.display(70, for: .weight)
        XCTAssertEqual(displayed, 70 * 2.204_62, accuracy: 0.01)
    }

    func testWeightRoundTripKilogramsToPoundsAndBack() {
        UserDefaults.standard.set(WeightUnit.pounds.rawValue, forKey: Units.weightKey)
        let canonicalKg = 82.5
        let displayedLb = Units.display(canonicalKg, for: .weight)
        let backToKg = Units.canonical(displayedLb, for: .weight)
        XCTAssertEqual(backToKg, canonicalKg, accuracy: 0.01)
    }

    // MARK: Temperature (°C <-> °F)

    func testTemperatureDefaultsToCelsiusUnchanged() {
        XCTAssertEqual(Units.temperature, .celsius)
        XCTAssertEqual(Units.display(37, for: .temperature), 37, accuracy: 0.01)
    }

    func testTemperatureCelsiusToFahrenheitConversion() {
        UserDefaults.standard.set(TemperatureUnit.fahrenheit.rawValue, forKey: Units.temperatureKey)
        XCTAssertEqual(Units.display(0, for: .temperature), 32, accuracy: 0.01)
        XCTAssertEqual(Units.display(100, for: .temperature), 212, accuracy: 0.01)
    }

    func testTemperatureRoundTripCelsiusToFahrenheitAndBack() {
        UserDefaults.standard.set(TemperatureUnit.fahrenheit.rawValue, forKey: Units.temperatureKey)
        let canonicalC = 37.2
        let displayedF = Units.display(canonicalC, for: .temperature)
        let backToC = Units.canonical(displayedF, for: .temperature)
        XCTAssertEqual(backToC, canonicalC, accuracy: 0.01)
    }

    // MARK: Blood glucose (mg/dL <-> mmol/L)

    func testGlucoseDefaultsToMgdLUnchanged() {
        XCTAssertEqual(Units.glucose, .mgdL)
        XCTAssertEqual(Units.display(100, for: .bloodGlucose), 100, accuracy: 0.01)
    }

    func testGlucoseMgdLToMmolLConversion() {
        UserDefaults.standard.set(GlucoseUnit.mmolL.rawValue, forKey: Units.glucoseKey)
        let displayed = Units.display(100, for: .bloodGlucose)
        XCTAssertEqual(displayed, 100 / 18.018, accuracy: 0.01)
    }

    func testGlucoseRoundTripMgdLToMmolLAndBack() {
        UserDefaults.standard.set(GlucoseUnit.mmolL.rawValue, forKey: Units.glucoseKey)
        let canonicalMgdL = 140.0
        let displayedMmolL = Units.display(canonicalMgdL, for: .bloodGlucose)
        let backToMgdL = Units.canonical(displayedMmolL, for: .bloodGlucose)
        XCTAssertEqual(backToMgdL, canonicalMgdL, accuracy: 0.01)
    }

    // MARK: Range conversion

    func testDisplayRangeConvertsAndOrdersBounds() {
        UserDefaults.standard.set(GlucoseUnit.mmolL.rawValue, forKey: Units.glucoseKey)
        let range = Units.displayRange(70...180, for: .bloodGlucose)
        XCTAssertLessThanOrEqual(range.lowerBound, range.upperBound)
        XCTAssertEqual(range.lowerBound, 70 / 18.018, accuracy: 0.01)
        XCTAssertEqual(range.upperBound, 180 / 18.018, accuracy: 0.01)
    }

    // MARK: Label

    func testLabelReflectsSelectedUnit() {
        UserDefaults.standard.set(WeightUnit.pounds.rawValue, forKey: Units.weightKey)
        XCTAssertEqual(Units.label(for: .weight), "lb")
        UserDefaults.standard.set(WeightUnit.kilograms.rawValue, forKey: Units.weightKey)
        XCTAssertEqual(Units.label(for: .weight), "kg")
    }
}
