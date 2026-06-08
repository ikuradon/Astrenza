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

public struct NostrRelayTrafficMeter: Equatable, Sendable {
    public var accountID: String
    public var relayURL: String
    public var policy: NostrSyncPolicy
    private var receivedBytes: Int = 0
    private var sentBytes: Int = 0
    private var receivedMessages: Int = 0
    private var sentMessages: Int = 0

    public init(accountID: String, relayURL: String, policy: NostrSyncPolicy) {
        self.accountID = accountID
        self.relayURL = relayURL
        self.policy = policy
    }

    public mutating func recordReceived(_ textFrame: String) {
        receivedBytes += textFrame.utf8.count
        receivedMessages += 1
    }

    public mutating func recordSent(_ textFrame: String) {
        sentBytes += textFrame.utf8.count
        sentMessages += 1
    }

    public mutating func flush(occurredAt: Int) -> [NostrRelayTrafficDelta] {
        guard receivedBytes > 0 || sentBytes > 0 || receivedMessages > 0 || sentMessages > 0 else {
            return []
        }
        let delta = NostrRelayTrafficDelta(
            accountID: accountID,
            relayURL: relayURL,
            occurredAt: occurredAt,
            networkType: policy.networkType,
            syncMode: policy.mode,
            receivedBytes: receivedBytes,
            sentBytes: sentBytes,
            receivedMessages: receivedMessages,
            sentMessages: sentMessages
        )
        receivedBytes = 0
        sentBytes = 0
        receivedMessages = 0
        sentMessages = 0
        return [delta]
    }
}
