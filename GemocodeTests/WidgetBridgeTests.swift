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

    // MARK: - Extended contract: dueTests / nextDrawDateISO (optional)

    /// The extended fields round-trip byte-for-byte, mirroring
    /// `testSnapshotRoundTripPreservesAllFields` above but with the
    /// schedule data populated — this is the shape `WidgetBridge.update`
    /// writes once `retestItems` is passed, and the shape the widget
    /// extension's own (duplicated) `WidgetSnapshot` must also decode.
    func testSnapshotRoundTripPreservesNewOptionalFields() throws {
        let updatedAt = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-07-10T12:00:00Z"))
        let nextDrawDate = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-08-02T00:00:00Z"))
        let snapshot = WidgetSnapshot(
            score: 78,
            headline: "Good",
            updatedAt: updatedAt,
            vitals: [],
            dueTests: [
                WidgetDueTest(name: "HbA1c", dueLabel: "Overdue", isOverdue: true),
                WidgetDueTest(name: "LDL", dueLabel: "2 wks", isOverdue: false),
            ],
            nextDrawDateISO: nextDrawDate
        )

        let decoded = try decoder.decode(WidgetSnapshot.self, from: encoder.encode(snapshot))

        XCTAssertEqual(decoded.dueTests?.count, 2)
        XCTAssertEqual(decoded.dueTests?.first?.name, "HbA1c")
        XCTAssertEqual(decoded.dueTests?.first?.dueLabel, "Overdue")
        XCTAssertEqual(decoded.dueTests?.first?.isOverdue, true)
        XCTAssertEqual(decoded.dueTests?.last?.isOverdue, false)
        XCTAssertEqual(decoded.nextDrawDateISO, nextDrawDate)
    }

    /// A snapshot JSON written by an OLDER app build — no `dueTests` or
    /// `nextDrawDateISO` keys at all — must still decode successfully, with
    /// both new fields resolving to `nil`. This is the backward-compat
    /// guarantee CLAUDE.md requires for any new model/contract field.
    func testSnapshotDecodesLegacyJSONWithoutNewFields() throws {
        let json = """
        {
            "score": 92,
            "headline": "Excellent",
            "updatedAt": "2026-07-10T09:30:00Z",
            "vitals": []
        }
        """

        let decoded = try decoder.decode(WidgetSnapshot.self, from: Data(json.utf8))

        XCTAssertEqual(decoded.score, 92)
        XCTAssertNil(decoded.dueTests)
        XCTAssertNil(decoded.nextDrawDateISO)
    }

    /// Hand-written fixture for the EXTENDED wire format — locks the exact
    /// key names (`dueTests`, `name`, `dueLabel`, `isOverdue`,
    /// `nextDrawDateISO`) the widget extension's duplicated struct must
    /// keep matching.
    func testSnapshotDecodesTheExactExtendedWireFormat() throws {
        let json = """
        {
            "score": 78,
            "headline": "Good",
            "updatedAt": "2026-07-10T09:30:00Z",
            "vitals": [],
            "dueTests": [
                { "name": "HbA1c", "dueLabel": "Overdue", "isOverdue": true },
                { "name": "LDL", "dueLabel": "2 wks", "isOverdue": false }
            ],
            "nextDrawDateISO": "2026-08-02T00:00:00Z"
        }
        """

        let decoded = try decoder.decode(WidgetSnapshot.self, from: Data(json.utf8))

        XCTAssertEqual(decoded.dueTests?.count, 2)
        XCTAssertEqual(decoded.dueTests?[0].name, "HbA1c")
        XCTAssertEqual(decoded.dueTests?[0].isOverdue, true)
        XCTAssertEqual(decoded.dueTests?[1].dueLabel, "2 wks")
        XCTAssertNotNil(decoded.nextDrawDateISO)
    }
}
