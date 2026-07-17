import NostrProtocol
import NostrReconciliationAPI
import NostrSync
import Testing

@Suite("sync reconciliation boundary")
struct NostrSyncTests {
    @Test("NIP-77 session delegates byte reconciliation through the API")
    func delegatesReconciliation() throws {
        let session = try NIP77SyncSession(
            localEvents: [],
            reconciliationFactory: ReconciliationFactory()
        )

        let openFrame = try session.openMessage(
            subscriptionID: "gap",
            filter: NostrRelayFilter(kinds: [1])
        ).textFrame()
        let result = try session.reconcile("61")

        #expect(openFrame.contains(#""6100""#))
        #expect(result.missingEventIDs == [String(repeating: "ab", count: 32)])
        #expect(result.nextMessageHex == nil)
    }
}

private struct ReconciliationFactory: NostrReconciliationSessionCreating {
    func makeSession(
        records: [NostrReconciliationRecord],
        frameSizeLimit: Int
    ) throws -> any NostrReconciliationSession {
        ReconciliationSession()
    }
}

private final class ReconciliationSession: NostrReconciliationSession {
    func initiate() throws -> [UInt8] {
        [0x61, 0x00]
    }

    func reconcile(_ message: [UInt8]) throws -> NostrReconciliationResult {
        NostrReconciliationResult(
            haveIDs: [],
            needIDs: [Array(repeating: 0xab, count: 32)],
            nextMessage: nil
        )
    }
}
