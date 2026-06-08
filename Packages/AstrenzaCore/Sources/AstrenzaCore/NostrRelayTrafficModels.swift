import Foundation

public struct NostrRelayTrafficDelta: Equatable, Sendable {
    public var accountID: String
    public var relayURL: String
    public var occurredAt: Int
    public var networkType: NostrNetworkType
    public var syncMode: NostrSyncMode
    public var receivedBytes: Int
    public var sentBytes: Int
    public var receivedMessages: Int
    public var sentMessages: Int

    public init(
        accountID: String,
        relayURL: String,
        occurredAt: Int,
        networkType: NostrNetworkType,
        syncMode: NostrSyncMode,
        receivedBytes: Int,
        sentBytes: Int,
        receivedMessages: Int,
        sentMessages: Int
    ) {
        self.accountID = accountID
        self.relayURL = relayURL
        self.occurredAt = occurredAt
        self.networkType = networkType
        self.syncMode = syncMode
        self.receivedBytes = receivedBytes
        self.sentBytes = sentBytes
        self.receivedMessages = receivedMessages
        self.sentMessages = sentMessages
    }
}

public struct NostrRelayTrafficTotals: Equatable, Sendable {
    public var receivedBytes: Int
    public var sentBytes: Int
    public var receivedMessages: Int
    public var sentMessages: Int

    public init(
        receivedBytes: Int,
        sentBytes: Int,
        receivedMessages: Int,
        sentMessages: Int
    ) {
        self.receivedBytes = receivedBytes
        self.sentBytes = sentBytes
        self.receivedMessages = receivedMessages
        self.sentMessages = sentMessages
    }

    public static let zero = NostrRelayTrafficTotals(
        receivedBytes: 0,
        sentBytes: 0,
        receivedMessages: 0,
        sentMessages: 0
    )
}
