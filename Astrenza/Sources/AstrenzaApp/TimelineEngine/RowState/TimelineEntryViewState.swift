import DesignSystem
import Foundation

struct TimelineEntryViewState: Identifiable, Equatable, Codable, Sendable {
    let id: TimelineEntryID
    let itemKey: String
    let sourceEventID: EventID
    let subjectEventID: EventID?
    let sortKey: TimelineSortKey
    let reason: FeedItemReason

    var author: ResolveState<ResolvedProfile>
    var body: ResolvedBodyText
    var media: [ResolveState<ResolvedMedia>]
    var linkPreview: ResolveState<ResolvedLinkPreview>
    var repost: ResolveState<ResolvedRepost>?
    var quote: ResolveState<ResolvedQuote>?
    var replyContext: ResolveState<ResolvedReplyContext>?
    var stats: ResolveState<ResolvedStats>
    var visibility: TimelineVisibilityState
    var publishState: PublishState?
    var layoutContract: TimelineRowLayoutContract
    var diagnostics: TimelineEntryViewStateDiagnostics
}

enum ResolveState<Value: Codable & Equatable & Sendable>: Equatable, Codable, Sendable {
    case absent
    case pending
    case resolving
    case resolved(Value)
    case failed(ResolveFailure)
    case blocked(VisibilityReason)
    case unavailable(UnavailableReason)
}

struct ResolveFailure: Equatable, Codable, Sendable {
    var target: TimelineDelayedResolveTarget
    var fallbackMode: TimelineFallbackMode
    var keepsSourceNoteVisible: Bool
    var message: String
    var reservedAspectRatio: Double?
    var reservedHeight: Double?
}

enum VisibilityReason: String, Equatable, Codable, Sendable {
    case muted
    case blocked
    case deleted
    case unavailable
    case localFilter
}

struct UnavailableReason: Equatable, Codable, Sendable {
    enum Kind: String, Equatable, Codable, Sendable {
        case missing
        case deleted
        case blocked
        case muted
        case targetUnavailable
        case unavailable
    }

    var kind: Kind
    var itemKey: String?
    var fallbackMode: TimelineFallbackMode?

    static let deleted = UnavailableReason(kind: .deleted)
    static let targetUnavailable = UnavailableReason(kind: .targetUnavailable)

    init(
        kind: Kind,
        itemKey: String? = nil,
        fallbackMode: TimelineFallbackMode? = nil
    ) {
        self.kind = kind
        self.itemKey = itemKey
        self.fallbackMode = fallbackMode
    }
}

struct TimelineSortKey: Equatable, Codable, Sendable {
    var sortAt: Int64
    var tieBreakID: String
}

enum FeedItemReason: String, CaseIterable, Equatable, Codable, Sendable {
    case author
    case reply
    case repost
    case quote
    case mention
    case reaction
    case zap
    case unknown

    init(_ reason: TimelineProjectionFeedItemReason) {
        switch reason {
        case .author:
            self = .author
        case .reply:
            self = .reply
        case .repost:
            self = .repost
        case .quote:
            self = .quote
        case .mention:
            self = .mention
        case .reaction:
            self = .reaction
        case .unknown:
            self = .unknown
        }
    }
}

enum TimelineVisibilityPresentation: String, Equatable, Codable, Sendable {
    case visible
    case collapsed
    case deletedPlaceholder
    case mutedPlaceholder
    case blockedPlaceholder
    case unavailablePlaceholder
}

struct TimelineVisibilityState: Equatable, Codable, Sendable {
    var mode: TimelineVisibilityMode
    var presentation: TimelineVisibilityPresentation
    var reason: VisibilityReason?
    var unavailableReason: UnavailableReason?
    var includedInVisibleSnapshot: Bool
    var pendingNewVisible: Bool
    var keepsSourceNoteVisible: Bool
    var removesSourceNote: Bool
    var fallbackMode: TimelineFallbackMode
}

struct ResolvedProfile: Equatable, Codable, Sendable {
    enum Avatar: Equatable, Codable, Sendable {
        case defaultAvatar
        case remoteURL(String)
    }

    var pubkeyFallback: String
    var displayName: String
    var handle: String
    var avatar: Avatar
    var isFallback: Bool
}

struct ResolvedBodyText: Equatable, Codable, Sendable {
    var text: String
    var keepsSourceNoteVisible: Bool
    var mentionRendering: MentionRenderingMode
}

struct ResolvedMedia: Equatable, Codable, Sendable {
    var id: String
    var reservedAspectRatio: Double?
    var reservedHeight: Double?
    var isPlaceholder: Bool
}

struct ResolvedLinkPreview: Equatable, Codable, Sendable {
    var urlString: String
    var title: String
    var mode: LinkPreviewMode
    var fallbackMode: TimelineFallbackMode
}

struct ResolvedRepost: Equatable, Codable, Sendable {
    var itemKey: String
    var sourceEventID: EventID
    var subjectEventID: EventID?
    var isPlaceholder: Bool
}

struct ResolvedQuote: Equatable, Codable, Sendable {
    var itemKey: String
    var subjectEventID: EventID?
    var mode: QuoteCardMode
    var maxLines: Int
    var createsReplyRelation: Bool
}

struct ResolvedReplyContext: Equatable, Codable, Sendable {
    var parentEventID: EventID?
    var mode: ReplyHeaderMode
    var allowsInlineParentPreviewInHome: Bool
}

struct ResolvedStats: Equatable, Codable, Sendable {
    var replyCount: Int
    var repostCount: Int
    var reactionCount: Int
}

enum PublishState: String, Equatable, Codable, Sendable {
    case placeholder
}

struct TimelineEntryViewStateDiagnostics: Equatable, Codable, Sendable {
    var scenarioName: String
    var initialEntryID: TimelineEntryID
    var finalEntryID: TimelineEntryID
    var delayedResolveTargets: [TimelineDelayedResolveTarget]
    var mutationStyle: TimelineProjectionMutationExpectation.Style
    var delayedResolveMutationStyle: TimelineProjectionMutationExpectation.Style?
    var reconfigureEntryIDs: [TimelineEntryID]
    var insertedIDs: [TimelineEntryID]
    var deletedIDs: [TimelineEntryID]
    var allowsDeleteInsertForDelayedResolve: Bool
    var readMarkerChanged: Bool
    var pendingNewVisible: Bool
    var requiresNetworkWork: Bool
    var requiresDBWork: Bool
    var quoteCreatesReplyRelation: Bool
    var fallbackMode: TimelineFallbackMode
    var keepsSourceNoteVisible: Bool
}
