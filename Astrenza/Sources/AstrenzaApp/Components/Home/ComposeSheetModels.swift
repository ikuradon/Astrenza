import Foundation

enum ComposeSheetMode: Equatable, Sendable {
    case post
    case reply
    case quote

    var title: String {
        switch self {
        case .post: "Compose"
        case .reply: "Reply"
        case .quote: "Quote"
        }
    }

    var placeholder: String {
        switch self {
        case .post: "Say something..."
        case .reply: "Write a reply..."
        case .quote: "Add a comment..."
        }
    }

    var actionTitle: String {
        switch self {
        case .post: "Post"
        case .reply: "Reply"
        case .quote: "Quote"
        }
    }
}

struct ComposeEventReference: Codable, Equatable, Sendable {
    let eventID: String
    let relayHint: String?
    let pubkey: String?
}

struct ComposeReplyContext: Codable, Equatable, Sendable {
    let root: ComposeEventReference
    let parent: ComposeEventReference
    let recipientPubkeys: [String]
}

struct ComposeQuoteContext: Codable, Equatable, Sendable {
    let target: ComposeEventReference
}

enum ComposeContext: Codable, Equatable, Sendable {
    case post
    case reply(ComposeReplyContext)
    case quote(ComposeQuoteContext)

    var mode: ComposeSheetMode {
        switch self {
        case .post: .post
        case .reply: .reply
        case .quote: .quote
        }
    }

    var parentEventID: String? {
        switch self {
        case .post: nil
        case .reply(let context): context.parent.eventID
        case .quote(let context): context.target.eventID
        }
    }
}

enum ComposeSubmissionState: Equatable, Sendable {
    case editing
    case uploadingMedia(completed: Int, total: Int)
    case signing
    case savingToOutbox
    case queued(eventID: String?)
    case failed(message: String)

    var isBusy: Bool {
        switch self {
        case .uploadingMedia, .signing, .savingToOutbox:
            true
        case .editing, .queued, .failed:
            false
        }
    }
}

struct ComposeSubmitRequest: Equatable, Sendable {
    let context: ComposeContext
    let text: String
    let isSensitive: Bool
    let sensitiveReason: String
    let customEmojis: [ComposeCustomEmojiReference]
    let media: [ComposeMediaUploadRequest]

    var mode: ComposeSheetMode { context.mode }
}

struct ComposeCustomEmojiReference: Codable, Equatable, Sendable {
    let shortcode: String
    let url: String
    let emojiSetAddress: String?

    init(
        shortcode: String,
        url: String,
        emojiSetAddress: String? = nil
    ) {
        self.shortcode = shortcode
        self.url = url
        self.emojiSetAddress = emojiSetAddress
    }
}

struct ComposeMediaUploadRequest: Codable, Equatable, Sendable {
    let id: UUID
    let localURL: URL
    let mimeType: String
    let width: Int?
    let height: Int?
    let altText: String?
}

struct ComposeUploadedMedia: Equatable, Sendable {
    let url: URL
    let mimeType: String
    let width: Int?
    let height: Int?
    let sha256: String
    let altText: String?
}
