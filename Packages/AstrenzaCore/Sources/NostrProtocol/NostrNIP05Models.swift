import Foundation

public enum NostrNIP05Status: String, Codable, Equatable, Sendable {
    case absent
    case unchecked
    case verified
    case invalid
    case failed
}

public struct NostrNIP05Resolution: Codable, Equatable, Sendable {
    public let identifier: String
    public let pubkey: String?
    public let relays: [String]
    public let status: NostrNIP05Status
    public let resolvedAt: Date

    public init(
        identifier: String,
        pubkey: String?,
        relays: [String],
        status: NostrNIP05Status,
        resolvedAt: Date = Date()
    ) {
        self.identifier = identifier
        self.pubkey = pubkey
        self.relays = relays
        self.status = status
        self.resolvedAt = resolvedAt
    }
}
