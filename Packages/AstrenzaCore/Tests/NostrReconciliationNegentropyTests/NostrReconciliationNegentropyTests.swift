import NostrReconciliationAPI
import NostrReconciliationNegentropy
import Testing

@Suite("negentropy-swift reconciliation contract")
struct NostrReconciliationNegentropyTests {
    @Test("factory creates a NIP-77 initiator from byte records")
    func createsInitiator() throws {
        let session = try NegentropySwiftReconciliationSessionFactory().makeSession(
            records: [
                NostrReconciliationRecord(timestamp: 100, id: Array(repeating: 0x11, count: 32)),
                NostrReconciliationRecord(timestamp: 200, id: Array(repeating: 0x22, count: 32))
            ],
            frameSizeLimit: 60_000
        )

        let initialMessage = try session.initiate()

        #expect(initialMessage.first == 0x61)
        #expect(initialMessage.count > 1)
    }

    @Test("factory rejects records with invalid identity width")
    func rejectsInvalidIdentityWidth() {
        #expect(throws: NostrReconciliationError.invalidRecordIDByteCount(1)) {
            _ = try NegentropySwiftReconciliationSessionFactory().makeSession(
                records: [NostrReconciliationRecord(timestamp: 100, id: [0x11])],
                frameSizeLimit: 60_000
            )
        }
    }
}
