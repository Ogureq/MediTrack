import XCTest
@testable import Gemocode

/// The widget extension duplicates the snapshot Codable types and decodes
/// whatever `WidgetBridge` wrote, so this locks down the JSON contract:
/// field names, the ISO-8601 date strategy, and round-trip fidelity.
final class WidgetBridgeTests: XCTestCase {

    private var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    func testSnapshotRoundTripPreservesAllFields() throws {
        let date = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-07-10T12:00:00Z"))
        let snapshot = WidgetSnapshot(
            score: 87,
            headline: "Good",
            updatedAt: date,
            vitals: [
                WidgetVital(name: "Heart Rate", value: "72 bpm", systemImage: "heart.fill"),
                WidgetVital(name: "Weight", value: "70 kg", systemImage: "scalemass.fill"),
            ]
        )

        let decoded = try decoder.decode(WidgetSnapshot.self, from: encoder.encode(snapshot))

        XCTAssertEqual(decoded.score, 87)
        XCTAssertEqual(decoded.headline, "Good")
        XCTAssertEqual(decoded.updatedAt, date)
        XCTAssertEqual(decoded.vitals.count, 2)
        XCTAssertEqual(decoded.vitals.first?.name, "Heart Rate")
        XCTAssertEqual(decoded.vitals.first?.value, "72 bpm")
        XCTAssertEqual(decoded.vitals.first?.systemImage, "heart.fill")
    }

    /// Decoding a hand-written fixture guards against accidental renames —
    /// the widget extension expects exactly these keys.
    func testSnapshotDecodesTheExactWireFormat() throws {
        let json = """
        {
            "score": 92,
            "headline": "Excellent",
            "updatedAt": "2026-07-10T09:30:00Z",
            "vitals": [
                { "name": "Blood Pressure", "value": "118/76", "systemImage": "waveform.path.ecg" }
            ]
        }
        """

        let decoded = try decoder.decode(WidgetSnapshot.self, from: Data(json.utf8))

        XCTAssertEqual(decoded.score, 92)
        XCTAssertEqual(decoded.headline, "Excellent")
        XCTAssertEqual(decoded.vitals.count, 1)
        XCTAssertEqual(decoded.vitals.first?.name, "Blood Pressure")
    }

    func testContractConstantsAreStable() {
        XCTAssertEqual(WidgetBridge.appGroupID, "group.com.ogureq.gemocode")
        XCTAssertEqual(WidgetBridge.snapshotKey, "widget.snapshot")
    }
}
