import XCTest
import SwiftData
@testable import MediTrack

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

    private func makeContext() throws -> ModelContext {
        try Self.makeInMemoryContainer().mainContext
    }

    /// Seeds a profile plus one non-profile record (the restore record count
    /// only tallies non-profile rows) so round trips have something to check.
    private func seedMinimalData(in context: ModelContext, name: String = "Jane Doe") {
        let profile = HealthProfile()
        profile.name = name
        context.insert(profile)
        context.insert(VitalSample(type: .weight, value: 70, date: fixedNow))
    }

    // MARK: Round trip

    func testEncryptDecryptRoundTripWithCorrectPassphrase() throws {
        let sourceContext = try makeContext()
        seedMinimalData(in: sourceContext)
        try sourceContext.save()

        let data = try BackupService.export(from: sourceContext, passphrase: correctPassphrase)

        // Confirm this really is the v2 envelope, not a plaintext fallback.
        let envelope = try JSONDecoder().decode(BackupEnvelope.self, from: data)
        XCTAssertEqual(envelope.version, 2)
        XCTAssertEqual(envelope.kdf, "pbkdf2-sha256")
        XCTAssertEqual(envelope.iterations, 310_000)
        XCTAssertFalse(envelope.salt.isEmpty)
        XCTAssertFalse(envelope.sealed.isEmpty)

        let destinationContext = try makeContext()
        let restoredCount = try BackupService.restore(from: data, passphrase: correctPassphrase, into: destinationContext)
        XCTAssertGreaterThan(restoredCount, 0)

        let restoredProfiles = try destinationContext.fetch(FetchDescriptor<HealthProfile>())
        XCTAssertEqual(restoredProfiles.first?.name, "Jane Doe")

        let restoredVitals = try destinationContext.fetch(FetchDescriptor<VitalSample>())
        XCTAssertEqual(restoredVitals.first?.value, 70)
    }

    // MARK: Wrong passphrase

    func testWrongPassphraseThrowsTypedError() throws {
        let sourceContext = try makeContext()
        seedMinimalData(in: sourceContext)
        try sourceContext.save()

        let data = try BackupService.export(from: sourceContext, passphrase: correctPassphrase)

        let destinationContext = try makeContext()
        XCTAssertThrowsError(
            try BackupService.restore(from: data, passphrase: "totally wrong passphrase", into: destinationContext)
        ) { error in
            XCTAssertEqual(error as? BackupError, .wrongPassphrase)
        }
    }

    // MARK: Legacy plaintext fallback

    func testLegacyPlaintextPayloadStillRestoresRegardlessOfPassphrase() throws {
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

        let context = try makeContext()
        // The passphrase is deliberately nonsense here: legacy payloads
        // aren't encrypted, so it must be ignored rather than rejected.
        let restoredCount = try BackupService.restore(
            from: Data(legacyJSON.utf8),
            passphrase: "this passphrase is never checked",
            into: context
        )
        XCTAssertEqual(restoredCount, 1)

        let profiles = try context.fetch(FetchDescriptor<HealthProfile>())
        XCTAssertEqual(profiles.first?.name, "Legacy Jane")
    }

    // MARK: Tampered ciphertext

    func testTamperedCiphertextThrows() throws {
        let sourceContext = try makeContext()
        seedMinimalData(in: sourceContext)
        try sourceContext.save()

        let data = try BackupService.export(from: sourceContext, passphrase: correctPassphrase)

        var envelope = try JSONDecoder().decode(BackupEnvelope.self, from: data)
        var sealedBytes = try XCTUnwrap(Data(base64Encoded: envelope.sealed))
        XCTAssertFalse(sealedBytes.isEmpty)
        // Flip a single byte in the middle of the sealed blob (nonce +
        // ciphertext + tag) so AES-GCM authentication fails on open.
        let flipIndex = sealedBytes.count / 2
        sealedBytes[flipIndex] ^= 0xFF
        envelope.sealed = sealedBytes.base64EncodedString()
        let tamperedData = try JSONEncoder().encode(envelope)

        let destinationContext = try makeContext()
        XCTAssertThrowsError(
            try BackupService.restore(from: tamperedData, passphrase: correctPassphrase, into: destinationContext)
        ) { error in
            XCTAssertTrue(error is BackupError)
        }
    }

    // MARK: Corrupt / unreadable data

    func testGarbageDataThrowsUnreadableFile() throws {
        let context = try makeContext()
        XCTAssertThrowsError(
            try BackupService.restore(from: Data("not a backup".utf8), passphrase: "whatever", into: context)
        ) { error in
            XCTAssertEqual(error as? BackupError, .unreadableFile)
        }
    }
}
