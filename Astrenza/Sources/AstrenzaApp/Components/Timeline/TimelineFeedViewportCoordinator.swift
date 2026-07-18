import CoreGraphics
import Foundation

struct TimelineFeedViewportIdentity: Equatable {
    let accountID: String
    let timelineKey: String
}

struct TimelineFeedVisibleAnchor: Equatable {
    let postID: TimelinePost.ID
    let offset: CGFloat
}

struct TimelineFeedViewportRestoreRequest: Equatable {
    let sourceIdentity: String
    let state: TimelineViewportState
}

enum TimelineFeedViewportRestorePhase: Equatable {
    case ready
    case awaitingContent(TimelineFeedViewportRestoreRequest)
    case positioning(TimelineFeedViewportRestoreRequest)
}

struct TimelineFeedViewportRestoreCoordinator {
    private(set) var phase: TimelineFeedViewportRestorePhase = .ready

    var blocksPersistence: Bool {
        switch phase {
        case .ready:
            false
        case .awaitingContent, .positioning:
            true
        }
    }

    var request: TimelineFeedViewportRestoreRequest? {
        switch phase {
        case .ready:
            nil
        case .awaitingContent(let request), .positioning(let request):
            request
        }
    }

    mutating func synchronize(
        sourceIdentity: String,
        state: TimelineViewportState?,
        isRestoreProtected: Bool
    ) {
        guard isRestoreProtected, let state else {
            phase = .ready
            return
        }

        let request = TimelineFeedViewportRestoreRequest(
            sourceIdentity: sourceIdentity,
            state: state
        )
        guard self.request != request else { return }
        phase = .awaitingContent(request)
    }

    mutating func beginPositioning() -> TimelineFeedViewportRestoreRequest? {
        guard case .awaitingContent(let request) = phase else { return nil }
        phase = .positioning(request)
        return request
    }

    mutating func retryPositioning() {
        guard case .positioning(let request) = phase else { return }
        phase = .awaitingContent(request)
    }

    mutating func complete(
        request: TimelineFeedViewportRestoreRequest,
        actualContentOffset: CGFloat,
        targetContentOffset: CGFloat,
        tolerance: CGFloat = 1
    ) -> Bool {
        guard self.request == request,
              TimelineFeedViewportRestorePolicy.isVerified(
                actualContentOffset: actualContentOffset,
                targetContentOffset: targetContentOffset,
                tolerance: tolerance
              )
        else { return false }

        phase = .ready
        return true
    }

    mutating func completeUsingFallback(
        request: TimelineFeedViewportRestoreRequest
    ) -> Bool {
        guard self.request == request else { return false }
        phase = .ready
        return true
    }
}

enum TimelineFeedViewportRestorePolicy {
    static let missingAnchorRetryLimit = 4

    static func targetContentOffset(
        anchorMinY: CGFloat,
        anchorOffset: CGFloat,
        anchorLineY: CGFloat,
        minimumOffset: CGFloat,
        maximumOffset: CGFloat
    ) -> CGFloat {
        let proposed = anchorMinY - anchorLineY + anchorOffset
        return min(max(proposed, minimumOffset), max(maximumOffset, minimumOffset))
    }

    static func isVerified(
        actualContentOffset: CGFloat,
        targetContentOffset: CGFloat,
        tolerance: CGFloat = 1
    ) -> Bool {
        abs(actualContentOffset - targetContentOffset) <= tolerance
    }

    static func shouldFallbackForMissingAnchor(
        hasContent: Bool,
        attempt: Int
    ) -> Bool {
        hasContent && attempt >= missingAnchorRetryLimit
    }

    static func canSaveViewport(
        hasUserInteraction: Bool,
        isRestoreBlocked: Bool,
        isProgrammaticScroll: Bool
    ) -> Bool {
        hasUserInteraction && !isRestoreBlocked && !isProgrammaticScroll
    }

    static func canFollowRealtimeEntries(
        isRealtimeEnabled: Bool,
        isPullRefreshProtected: Bool,
        isRestoreProtected: Bool,
        didRestoreViewport: Bool,
        isRestoringViewport: Bool
    ) -> Bool {
        isRealtimeEnabled &&
            !isPullRefreshProtected &&
            !isRestoringViewport &&
            (!isRestoreProtected || didRestoreViewport)
    }
}

enum TimelinePostReadLinePosition: Equatable {
    case aboveOrAt
    case below
}

enum TimelineReadLineCrossingPolicy {
    static func advancesReadBoundary(
        previous: TimelinePostReadLinePosition?,
        current: TimelinePostReadLinePosition,
        isUserScrollActive: Bool
    ) -> Bool {
        isUserScrollActive &&
            previous == .aboveOrAt &&
            current == .below
    }
}
