import Foundation

public struct NostrDraftMediaReference: Codable, Equatable, Sendable {
    public let id: String
    public let kind: String
    public let localIdentifier: String?
    public let altText: String?

    public init(id: String, kind: String, localIdentifier: String? = nil, altText: String? = nil) {
        self.id = id
        self.kind = kind
        self.localIdentifier = localIdentifier
        self.altText = altText
    }
}

public struct NostrDraftRecord: Codable, Equatable, Sendable {
    public let draftID: String
    public let accountID: String
    public let kind: Int
    public let parentEventID: String?
    public let text: String
    public let contentWarning: String?
    public let media: [NostrDraftMediaReference]
    public let updatedAt: Int

    public init(
        draftID: String,
        accountID: String,
        kind: Int,
        parentEventID: String? = nil,
        text: String,
        contentWarning: String? = nil,
        media: [NostrDraftMediaReference] = [],
        updatedAt: Int
    ) {
        self.draftID = draftID
        self.accountID = accountID
        self.kind = kind
        self.parentEventID = parentEventID
        self.text = text
        self.contentWarning = contentWarning
        self.media = media
        self.updatedAt = updatedAt
    }
}
