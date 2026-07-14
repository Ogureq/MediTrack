import XCTest
import SwiftData
@testable import Gemocode

/// Exercises the v2 encryption envelope added around `BackupService`'s
/// export/restore pair: PBKDF2-SHA256 key derivation (CommonCrypto) into an
/// AES-GCM seal (CryptoKit). Pure crypto — no Keychain involved anywhere in
/// this path, so unlike `AppLockTests` these never need to skip on CI.
@MainActor
final class BackupCryptoTests: XCTestCase {

    private let fixedNow = Date(timeIntervalSince1970: 1_700_000_000)
    private let correctPassphrase = "correct horse battery staple"

    private static func makeInMemoryContainer() throws -> ModelContainer {
        try ModelContainer(
            for: HealthProfile.self,
                 MedicalReport.self,
                 LabResult.self,
                 ReportAttachment.self,
                 VitalSample.self,
                 Medication.self,
                 HealthGoal.self,
                 SymptomEntry.self,
                 Appointment.self,
                 ScoreSnapshot.self,
                 Reminder.self,
                 ReminderCompletion.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    // Each test binds the container itself, not just its `mainContext`:
    // the container owns the store and only caches the context, so a
    // discarded temporary container tears the store down mid-test and
    // crashes the process on newer runtimes.

    /// Seeds a profile plus one non-profile record (the restore record count
    /// only tallies non-profile rows) so round trips have something to check.
    private func seedMinimalData(in context: ModelContext, name: String = "Jane Doe") {
        let profile = HealthProfile()
        profile.name = name
        context.insert(profile)
        context.insert(VitalSample(type: .weight, value: 70, date: fixedNow))
    }

    // MARK: Round trip

    func testEncryptDecryptRoundTripWithCorrectPassphrase() async throws {
        let sourceContainer = try Self.makeInMemoryContainer()
        let sourceContext = sourceContainer.mainContext
        seedMinimalData(in: sourceContext)
        try sourceContext.save()

        let data = try await BackupService.export(from: sourceContext, passphrase: correctPassphrase)

        // Confirm this really is the v2 envelope, not a plaintext fallback.
        let envelope = try JSONDecoder().decode(BackupEnvelope.self, from: data)
        XCTAssertEqual(envelope.version, 2)
        XCTAssertEqual(envelope.kdf, "pbkdf2-sha256")
        XCTAssertEqual(envelope.iterations, 310_000)
        XCTAssertFalse(envelope.salt.isEmpty)
        XCTAssertFalse(envelope.sealed.isEmpty)

        let destinationContainer = try Self.makeInMemoryContainer()
        let destinationContext = destinationContainer.mainContext
        let restoredCount = try await BackupService.restore(from: data, passphrase: correctPassphrase, into: destinationContext)
        XCTAssertGreaterThan(restoredCount, 0)

        let restoredProfiles = try destinationContext.fetch(FetchDescriptor<HealthProfile>())
        XCTAssertEqual(restoredProfiles.first?.name, "Jane Doe")

        let restoredVitals = try destinationContext.fetch(FetchDescriptor<VitalSample>())
        XCTAssertEqual(restoredVitals.first?.value, 70)
    }

    // MARK: Wrong passphrase

    func testWrongPassphraseThrowsTypedError() async throws {
        let sourceContainer = try Self.makeInMemoryContainer()
        let sourceContext = sourceContainer.mainContext
        seedMinimalData(in: sourceContext)
        try sourceContext.save()

        let data = try await BackupService.export(from: sourceContext, passphrase: correctPassphrase)

        let destinationContainer = try Self.makeInMemoryContainer()
        let destinationContext = destinationContainer.mainContext
        // XCTAssertThrowsError's expression is a non-async autoclosure, so
        // an `await`-ing call can't be passed to it directly; do/catch is
        // the standard substitute for async-throwing expectations.
        do {
            _ = try await BackupService.restore(from: data, passphrase: "totally wrong passphrase", into: destinationContext)
            XCTFail("Expected BackupError.wrongPassphrase")
        } catch {
            XCTAssertEqual(error as? BackupError, .wrongPassphrase)
        }
    }

    // MARK: Legacy plaintext fallback

    func testLegacyPlaintextPayloadStillRestoresRegardlessOfPassphrase() async throws {
        // Mirrors a pre-encryption (v1) backup file: a bare `BackupPayload`
        // JSON with no envelope wrapper at all.
        let legacyJSON = """
        {
            "version": 1,
            "exportedAt": "2023-11-14T22:13:20Z",
            "profile": {
                "name": "Legacy Jane",
                "sex": "\(BiologicalSex.female.rawValue)",
                "bloodType": "",
                "allergies": "",
                "conditions": ""
            },
            "reports": [],
            "vitals": [
                {"type": "\(VitalType.weight.rawValue)", "value": 70, "date": "2023-11-14T22:13:20Z", "note": ""}
            ],
            "medications": [],
            "symptoms": [],
            "appointments": [],
            "scoreSnapshots": []
        }
        """

        let container = try Self.makeInMemoryContainer()
        let context = container.mainContext
        // The passphrase is deliberately nonsense here: legacy payloads
        // aren't encrypted, so it must be ignored rather than rejected.
        let restoredCount = try await BackupService.restore(
            from: Data(legacyJSON.utf8),
            passphrase: "this passphrase is never checked",
            into: context
        )
        XCTAssertEqual(restoredCount, 1)

        let profiles = try context.fetch(FetchDescriptor<HealthProfile>())
        XCTAssertEqual(profiles.first?.name, "Legacy Jane")
    }

    // MARK: Tampered ciphertext

    func testTamperedCiphertextThrows() async throws {
        let sourceContainer = try Self.makeInMemoryContainer()
        let sourceContext = sourceContainer.mainContext
        seedMinimalData(in: sourceContext)
        try sourceContext.save()

        let data = try await BackupService.export(from: sourceContext, passphrase: correctPassphrase)

        var envelope = try JSONDecoder().decode(BackupEnvelope.self, from: data)
        var sealedBytes = try XCTUnwrap(Data(base64Encoded: envelope.sealed))
        XCTAssertFalse(sealedBytes.isEmpty)
        // Flip a single byte in the middle of the sealed blob (nonce +
        // ciphertext + tag) so AES-GCM authentication fails on open.
        let flipIndex = sealedBytes.count / 2
        sealedBytes[flipIndex] ^= 0xFF
        envelope.sealed = sealedBytes.base64EncodedString()
        let tamperedData = try JSONEncoder().encode(envelope)

        let destinationContainer = try Self.makeInMemoryContainer()
        let destinationContext = destinationContainer.mainContext
        do {
            _ = try await BackupService.restore(from: tamperedData, passphrase: correctPassphrase, into: destinationContext)
            XCTFail("Expected a BackupError")
        } catch {
            XCTAssertTrue(error is BackupError)
        }
    }

    // MARK: Corrupt / unreadable data

    func testGarbageDataThrowsUnreadableFile() async throws {
        let container = try Self.makeInMemoryContainer()
        let context = container.mainContext
        do {
            _ = try await BackupService.restore(from: Data("not a backup".utf8), passphrase: "whatever", into: context)
            XCTFail("Expected BackupError.unreadableFile")
        } catch {
            XCTAssertEqual(error as? BackupError, .unreadableFile)
        }
    }
}
