import DesignSystem
import Foundation

enum TimelineProjectionFeedItemReason: String, CaseIterable, Codable, Sendable {
    case author
    case reply
    case repost
    case quote
    case mention
    case reaction
    case unknown
}

enum TimelineProjectionResolveState: String, CaseIterable, Codable, Sendable {
    case absent
    case pending
    case resolving
    case resolved
    case failed
    case blocked
    case unavailable

    var requiresFallback: Bool {
        switch self {
        case .absent, .pending, .resolving, .resolved:
            false
        case .failed, .blocked, .unavailable:
            true
        }
    }
}

enum TimelineDelayedResolveTarget: String, CaseIterable, Codable, Hashable, Sendable {
    case profile
    case bodyMention
    case media
    case linkPreviewOGP
    case repostTarget
    case quoteTarget
    case replyParentRoot
    case stats
    case publishStatePlaceholder
}

struct TimelineIdentityExpectation: Equatable, Codable, Sendable {
    var itemKey: String
    var sourceEventID: EventID
    var subjectEventID: EventID?
    var sortAt: Int64
    var tieBreakID: String
    var feedItemReason: TimelineProjectionFeedItemReason

    var entryID: TimelineEntryID {
        TimelineEntryID(
            rawValue: itemKey,
            sourceEventID: sourceEventID,
            sortAt: sortAt,
            tieBreakID: tieBreakID
        )
    }
}

struct TimelineResolveExpectation: Equatable, Codable, Sendable {
    var target: TimelineDelayedResolveTarget
    var initialState: TimelineProjectionResolveState
    var expectedState: TimelineProjectionResolveState

    var isDelayedResolveTransition: Bool {
        initialState != expectedState
    }

    var requiresFallback: Bool {
        expectedState.requiresFallback
    }
}

enum TimelineVisibilityMode: String, CaseIterable, Codable, Sendable {
    case visible
    case collapsed
    case deletedPlaceholder
    case mutedPlaceholder
    case blockedPlaceholder
    case unavailablePlaceholder
}

struct TimelineVisibilityExpectation: Equatable, Codable, Sendable {
    var mode: TimelineVisibilityMode
    var includedInVisibleSnapshot: Bool

    var isVisibleInHome: Bool {
        includedInVisibleSnapshot
    }

    var removesSourceNote: Bool {
        false
    }
}

enum TimelineFallbackMode: String, CaseIterable, Codable, Sendable {
    case none
    case urlOnly
    case fixedMediaPlaceholder
    case npubHeaderOnly
    case targetUnavailablePlaceholder
    case deletedPlaceholder
    case mutedCollapsed
    case blockedPlaceholder
    case failedInlineFallback
}

struct TimelineFallbackExpectation: Equatable, Codable, Sendable {
    var mode: TimelineFallbackMode
    var keepsSourceNoteVisible: Bool
}

struct TimelineLayoutExpectation: Equatable, Codable, Sendable {
    var contract: TimelineRowLayoutContract
    var noUnlimitedHeightGrowthAfterResolve: Bool
    var isDetailOnly: Bool

    var rowKind: TimelineRowKind {
        contract.rowKind
    }

    var canChangeHeightAfterFirstDisplay: Bool {
        contract.canChangeHeightAfterFirstDisplay
    }

    var reservedMediaAspectRatio: Double? {
        contract.reservedMediaAspectRatio
    }

    var reservedMediaHeight: Double? {
        contract.reservedMediaHeight
    }

    var linkPreviewMode: LinkPreviewMode {
        contract.linkPreviewMode
    }

    var quoteMode: QuoteCardMode {
        contract.quoteMode
    }

    var replyHeaderMode: ReplyHeaderMode {
        contract.replyHeaderMode
    }

    var bodyMentionRendering: MentionRenderingMode {
        contract.bodyMentionRendering
    }

    var maxBodyLinesInCollapsedMode: Int? {
        contract.maxBodyLinesInCollapsedMode
    }

    var maxQuoteLines: Int {
        contract.maxQuoteLines
    }

    var allowsInlineParentPreviewInHome: Bool {
        contract.allowsInlineParentPreviewInHome
    }
}

struct TimelineMutationExpectation: Equatable, Codable, Sendable {
    var initialEntryID: TimelineEntryID
    var finalEntryID: TimelineEntryID
    var expectedMutationStyle: TimelineMutationStyle
    var insertedIDs: [TimelineEntryID]
    var deletedIDs: [TimelineEntryID]
    var readMarkerChanged: Bool
    var pendingNewInsertedIntoVisibleSnapshot: Bool
    var quoteCreatesReplyRelation: Bool
}

struct TimelineProjectionInput: Equatable, Codable, Sendable {
    var identity: TimelineIdentityExpectation
    var resolveExpectations: [TimelineResolveExpectation]
    var isPendingNew: Bool
    var userActionAllowsPendingNewInsertion: Bool
}

struct TimelineProjectionExpectedOutput: Equatable, Codable, Sendable {
    var identity: TimelineIdentityExpectation
    var resolveExpectations: [TimelineResolveExpectation]
    var layout: TimelineLayoutExpectation
    var visibility: TimelineVisibilityExpectation
    var fallback: TimelineFallbackExpectation
    var mutation: TimelineMutationExpectation
}

struct TimelineProjectionScenario: Equatable, Codable, Sendable {
    var name: String
    var input: TimelineProjectionInput
    var expectedOutput: TimelineProjectionExpectedOutput

    var hasDelayedResolveTransition: Bool {
        expectedOutput.resolveExpectations.contains { $0.isDelayedResolveTransition }
    }
}
