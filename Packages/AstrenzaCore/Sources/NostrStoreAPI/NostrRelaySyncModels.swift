public enum NostrRelaySyncEventKind: String, Codable, Equatable, Sendable {
    case connected
    case eose
    case closed
    case reconnect
    case timeout
    case partialFailure
    case authRequired
    case paymentRequired
    case rejected
    case suspended
    case negentropy
}

public struct NostrRelaySyncEventRecord: Codable, Equatable, Sendable {
    public let accountID: String
    public let timelineKey: String
    public let relayURL: String
    public let kind: NostrRelaySyncEventKind
    public let occurredAt: Int
    public let subscriptionID: String?
    public let eventCount: Int
    public let newestCreatedAt: Int?
    public let oldestCreatedAt: Int?
    public let latencyMilliseconds: Int?
    public let message: String?

    public init(
        accountID: String,
        timelineKey: String,
        relayURL: String,
        kind: NostrRelaySyncEventKind,
        occurredAt: Int,
        subscriptionID: String? = nil,
        eventCount: Int = 0,
        newestCreatedAt: Int? = nil,
        oldestCreatedAt: Int? = nil,
        latencyMilliseconds: Int? = nil,
        message: String? = nil
    ) {
        self.accountID = accountID
        self.timelineKey = timelineKey
        self.relayURL = relayURL
        self.kind = kind
        self.occurredAt = occurredAt
        self.subscriptionID = subscriptionID
        self.eventCount = eventCount
        self.newestCreatedAt = newestCreatedAt
        self.oldestCreatedAt = oldestCreatedAt
        self.latencyMilliseconds = latencyMilliseconds
        self.message = message
    }
}
