import AstrenzaCore
import Foundation

@MainActor
protocol HomeFeedProjectionControlling: AnyObject {
    var definition: NostrFeedDefinitionRecord? { get }
    var retainedWindowLimit: Int { get }

    func ensureDefinition(
        accountID: String,
        followedPubkeys: [String],
        liveEvents: [NostrEvent],
        now: Int
    )

    func isCurrent(
        _ context: HomeFeedRuntimeContext?,
        accountID: String?
    ) -> Bool

    func activateStoredProjection(
        definition: NostrFeedDefinitionRecord,
        sourceAuthors: [String]
    )
}

extension HomeFeedProjectionController: HomeFeedProjectionControlling {}

@MainActor
protocol HomeTimelineReadStateCoordinating: AnyObject {
    func restoredViewportState(
        accountID: String,
        timelineKey: String
    ) -> TimelineViewportState?

    func restoredReadBoundaryPostID(
        feedID: String,
        positions: [HomeTimelineReadPosition]
    ) -> String?

    @discardableResult
    func scheduleViewportState(
        _ state: TimelineViewportState,
        feedID: String,
        scopeID: String
    ) -> Bool

    @discardableResult
    func scheduleReadBoundarySave(
        _ write: HomeTimelineReadBoundaryWrite
    ) -> Bool

    func flushPendingViewportWrite()
}

extension HomeTimelineReadStateCoordinator: HomeTimelineReadStateCoordinating {}

@MainActor
protocol HomeTimelineMaterializationCoordinating: AnyObject {
    @discardableResult
    func reloadNewestProjection(account: NostrAccount) -> Bool

    @discardableResult
    func reloadProjection(
        account: NostrAccount,
        around anchorEventID: String?,
        mergingWithCurrentWindow: Bool
    ) -> Bool

    func materialize(
        _ request: HomeTimelineMaterializationRequest
    ) -> HomeTimelinePresentationTransition?
}

extension HomeTimelineMaterializationCoordinator:
    HomeTimelineMaterializationCoordinating {}

@MainActor
final class HomeProjectionInteractionWorkflow {
    typealias TimestampProvider = @MainActor @Sendable () -> Int

    private let projection: any HomeFeedProjectionControlling
    private let readState: any HomeTimelineReadStateCoordinating
    private let materialization: any HomeTimelineMaterializationCoordinating
    private let timestamp: TimestampProvider

    init(
        projection: any HomeFeedProjectionControlling,
        readState: any HomeTimelineReadStateCoordinating,
        materialization: any HomeTimelineMaterializationCoordinating,
        timestamp: @escaping TimestampProvider = {
            Int(Date().timeIntervalSince1970)
        }
    ) {
        self.projection = projection
        self.readState = readState
        self.materialization = materialization
        self.timestamp = timestamp
    }

    func ensureDefinition(
        account: NostrAccount,
        followedPubkeys: [String],
        liveEvents: [NostrEvent]
    ) {
        projection.ensureDefinition(
            accountID: account.pubkey,
            followedPubkeys: followedPubkeys,
            liveEvents: liveEvents,
            now: timestamp()
        )
    }

    func isCurrent(
        _ context: HomeFeedRuntimeContext?,
        accountID: String?
    ) -> Bool {
        projection.isCurrent(context, accountID: accountID)
    }

    func restoredViewportState(
        accountID: String,
        timelineKey: String
    ) -> TimelineViewportState? {
        readState.restoredViewportState(
            accountID: accountID,
            timelineKey: timelineKey
        )
    }

    @discardableResult
    func scheduleViewportState(_ state: TimelineViewportState) -> Bool {
        guard let feedID = activeFeedID(accountID: state.accountID) else {
            return false
        }
        return readState.scheduleViewportState(
            state,
            feedID: feedID,
            scopeID: state.accountID
        )
    }

    func flushPendingViewportWrite() {
        readState.flushPendingViewportWrite()
    }

    func restoredReadBoundaryPostID(
        accountID: String,
        positions: [HomeTimelineReadPosition]
    ) -> String? {
        guard let feedID = activeFeedID(accountID: accountID) else {
            return nil
        }
        return readState.restoredReadBoundaryPostID(
            feedID: feedID,
            positions: positions
        )
    }

    func readBoundaryWrite(
        accountID: String,
        boundary: NostrTimelineEntryCursor?
    ) -> HomeTimelineReadBoundaryWrite? {
        guard let feedID = activeFeedID(accountID: accountID) else {
            return nil
        }
        return HomeTimelineReadBoundaryWrite(
            scopeID: accountID,
            feedID: feedID,
            boundary: boundary,
            updatedAt: timestamp()
        )
    }

    @discardableResult
    func scheduleReadBoundarySave(
        accountID: String,
        boundary: NostrTimelineEntryCursor?
    ) -> Bool {
        guard let write = readBoundaryWrite(
            accountID: accountID,
            boundary: boundary
        ) else { return false }
        return readState.scheduleReadBoundarySave(write)
    }

    @discardableResult
    func reloadNewestProjection(account: NostrAccount) -> Bool {
        materialization.reloadNewestProjection(account: account)
    }

    @discardableResult
    func reloadProjection(
        account: NostrAccount,
        around anchorEventID: String?,
        mergingWithCurrentWindow: Bool
    ) -> Bool {
        materialization.reloadProjection(
            account: account,
            around: anchorEventID,
            mergingWithCurrentWindow: mergingWithCurrentWindow
        )
    }

    func materialize(
        _ request: HomeTimelineMaterializationRequest
    ) -> HomeTimelinePresentationTransition? {
        materialization.materialize(request)
    }

    #if DEBUG
    func mergedWindow(
        _ current: NostrFeedWindow,
        with loaded: NostrFeedWindow,
        centeredOn anchorEventID: String
    ) -> NostrFeedWindow {
        HomeFeedProjectionBuilder.mergedWindow(
            current,
            with: loaded,
            centeredOn: anchorEventID,
            retainedLimit: projection.retainedWindowLimit
        )
    }

    func activateStoredProjection(
        definition: NostrFeedDefinitionRecord,
        sourceAuthors: [String]
    ) {
        projection.activateStoredProjection(
            definition: definition,
            sourceAuthors: sourceAuthors
        )
    }
    #endif

    private func activeFeedID(accountID: String) -> String? {
        guard let definition = projection.definition,
              definition.accountID == accountID
        else { return nil }
        return definition.feedID
    }
}
