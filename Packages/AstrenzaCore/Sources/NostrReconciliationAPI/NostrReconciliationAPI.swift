public struct NostrReconciliationRecord: Equatable, Sendable {
    public let timestamp: UInt64
    public let id: [UInt8]

    public init(timestamp: UInt64, id: [UInt8]) {
        self.timestamp = timestamp
        self.id = id
    }
}

public struct NostrReconciliationResult: Equatable, Sendable {
    public let haveIDs: [[UInt8]]
    public let needIDs: [[UInt8]]
    public let nextMessage: [UInt8]?

    public init(haveIDs: [[UInt8]], needIDs: [[UInt8]], nextMessage: [UInt8]?) {
        self.haveIDs = haveIDs
        self.needIDs = needIDs
        self.nextMessage = nextMessage
    }
}

public enum NostrReconciliationError: Error, Equatable {
    case invalidRecordIDByteCount(Int)
}

public protocol NostrReconciliationSession: AnyObject {
    func initiate() throws -> [UInt8]
    func reconcile(_ message: [UInt8]) throws -> NostrReconciliationResult
}

public protocol NostrReconciliationSessionCreating: Sendable {
    func makeSession(
        records: [NostrReconciliationRecord],
        frameSizeLimit: Int
    ) throws -> any NostrReconciliationSession
}
