import Foundation

public struct NostrDraftEventReference: Codable, Equatable, Sendable {
    public let eventID: String
    public let relayHint: String?
    public let pubkey: String?

    public init(eventID: String, relayHint: String? = nil, pubkey: String? = nil) {
        self.eventID = eventID
        self.relayHint = relayHint
        self.pubkey = pubkey
    }
}

public enum NostrDraftContext: Codable, Equatable, Sendable {
    case post
    case reply(
        root: NostrDraftEventReference,
        parent: NostrDraftEventReference,
        recipientPubkeys: [String]
    )
    case quote(target: NostrDraftEventReference)
}

public enum NostrDraftMediaUploadState: String, Codable, Equatable, Sendable {
    case local
    case uploaded
}

public struct NostrDraftMediaReference: Codable, Equatable, Sendable {
    public let id: String
    public let kind: String
    public let localIdentifier: String?
    public let localPath: String?
    public let remoteURL: String?
    public let mimeType: String?
    public let width: Int?
    public let height: Int?
    public let sha256: String?
    public let altText: String?
    public let uploadState: NostrDraftMediaUploadState

    public init(
        id: String,
        kind: String,
        localIdentifier: String? = nil,
        localPath: String? = nil,
        remoteURL: String? = nil,
        mimeType: String? = nil,
        width: Int? = nil,
        height: Int? = nil,
        sha256: String? = nil,
        altText: String? = nil,
        uploadState: NostrDraftMediaUploadState = .local
    ) {
        self.id = id
        self.kind = kind
        self.localIdentifier = localIdentifier
        self.localPath = localPath
        self.remoteURL = remoteURL
        self.mimeType = mimeType
        self.width = width
        self.height = height
        self.sha256 = sha256
        self.altText = altText
        self.uploadState = uploadState
    }
}

public struct NostrDraftRecord: Codable, Equatable, Sendable {
    public let draftID: String
    public let accountID: String
    public let context: NostrDraftContext
    public let text: String
    public let contentWarning: String?
    public let tags: [[String]]
    public let media: [NostrDraftMediaReference]
    public let updatedAt: Int

    public init(
        draftID: String,
        accountID: String,
        context: NostrDraftContext = .post,
        text: String,
        contentWarning: String? = nil,
        tags: [[String]] = [],
        media: [NostrDraftMediaReference] = [],
        updatedAt: Int
    ) {
        self.draftID = draftID
        self.accountID = accountID
        self.context = context
        self.text = text
        self.contentWarning = contentWarning
        self.tags = tags
        self.media = media
        self.updatedAt = updatedAt
    }

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
        let context: NostrDraftContext
        if let parentEventID {
            let reference = NostrDraftEventReference(eventID: parentEventID)
            context = .reply(
                root: reference,
                parent: reference,
                recipientPubkeys: []
            )
        } else {
            context = .post
        }
        self.init(
            draftID: draftID,
            accountID: accountID,
            context: context,
            text: text,
            contentWarning: contentWarning,
            media: media,
            updatedAt: updatedAt
        )
    }

    public var kind: Int { 1 }

    public var parentEventID: String? {
        switch context {
        case .post: nil
        case .reply(_, let parent, _): parent.eventID
        case .quote(let target): target.eventID
        }
    }
}
