import Foundation

public struct NostrOutboxEventRecord: Codable, Equatable, Sendable {
    public let localID: String
    public let accountID: String
    public let eventID: String?
    public let event: NostrEvent
    public let status: String
    public let createdAt: Int
    public let nextRetryAt: Int?
    public let lastError: String?

    public init(
        localID: String,
        accountID: String,
        eventID: String?,
        event: NostrEvent,
        status: String,
        createdAt: Int,
        nextRetryAt: Int?,
        lastError: String?
    ) {
        self.localID = localID
        self.accountID = accountID
        self.eventID = eventID
        self.event = event
        self.status = status
        self.createdAt = createdAt
        self.nextRetryAt = nextRetryAt
        self.lastError = lastError
    }
}

public struct NostrOutboxRelayRecord: Codable, Equatable, Sendable {
    public let localID: String
    public let relayURL: String
    public let status: String
    public let lastAttemptAt: Int?
    public let okMessage: String?
    public let attemptCount: Int

    public init(
        localID: String,
        relayURL: String,
        status: String,
        lastAttemptAt: Int?,
        okMessage: String?,
        attemptCount: Int = 0
    ) {
        self.localID = localID
        self.relayURL = relayURL
        self.status = status
        self.lastAttemptAt = lastAttemptAt
        self.okMessage = okMessage
        self.attemptCount = attemptCount
    }
}

public enum NostrOutboxStatus {
    public static let pending = "pending"
    public static let publishing = "publishing"
    public static let published = "published"
    public static let partial = "partial"
    public static let failed = "failed"
    public static let rejected = "rejected"
}

public enum NostrPublishDestinationResolver {
    public static func relayDestinations(
        accountWriteRelays: [String],
        taggedUserReadRelays: [String],
        fallbackRelays: [String],
        limit: Int = 12
    ) -> [String] {
        dedupe(accountWriteRelays + taggedUserReadRelays + fallbackRelays)
            .prefix(limit)
            .map { $0 }
    }

    private static func dedupe(_ relays: [String]) -> [String] {
        var seen = Set<String>()
        return relays.compactMap { relay in
            guard let normalized = normalizeRelayURL(relay),
                  seen.insert(normalized).inserted
            else { return nil }
            return normalized
        }
    }

    private static func normalizeRelayURL(_ raw: String) -> String? {
        guard let url = URL(string: raw),
              url.scheme == "wss" || url.scheme == "ws",
              url.host != nil
        else { return nil }
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }
        components.scheme = components.scheme?.lowercased()
        components.host = components.host?.lowercased()
        components.fragment = nil
        return components.url?.absoluteString
    }
}
