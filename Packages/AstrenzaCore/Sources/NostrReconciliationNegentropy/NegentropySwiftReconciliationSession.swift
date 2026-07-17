import Negentropy
import NostrReconciliationAPI

public struct NegentropySwiftReconciliationSessionFactory: NostrReconciliationSessionCreating {
    public init() {}

    public func makeSession(
        records: [NostrReconciliationRecord],
        frameSizeLimit: Int
    ) throws -> any NostrReconciliationSession {
        let storage = NegentropyStorageVector(capacity: records.count)
        for record in records {
            guard record.id.count == 32 else {
                throw NostrReconciliationError.invalidRecordIDByteCount(record.id.count)
            }
            try storage.insert(timestamp: record.timestamp, id: Id(bytes: record.id))
        }
        try storage.seal()
        return try NegentropySwiftReconciliationSession(
            storage: storage,
            frameSizeLimit: frameSizeLimit
        )
    }
}

private final class NegentropySwiftReconciliationSession: NostrReconciliationSession {
    private let negentropy: Negentropy<NegentropyStorageVector>

    init(storage: NegentropyStorageVector, frameSizeLimit: Int) throws {
        negentropy = try Negentropy(storage: storage, frameSizeLimit: frameSizeLimit)
    }

    func initiate() throws -> [UInt8] {
        try negentropy.initiate()
    }

    func reconcile(_ message: [UInt8]) throws -> NostrReconciliationResult {
        var haveIDs: [Id] = []
        var needIDs: [Id] = []
        let nextMessage = try negentropy.reconcile(
            message,
            haveIds: &haveIDs,
            needIds: &needIDs
        )
        return NostrReconciliationResult(
            haveIDs: haveIDs.map { $0.toBytes() },
            needIDs: needIDs.map { $0.toBytes() },
            nextMessage: nextMessage
        )
    }
}
