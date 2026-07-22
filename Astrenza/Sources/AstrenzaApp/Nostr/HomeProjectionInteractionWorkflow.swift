import AstrenzaCore
import Foundation

@MainActor
protocol HomeFeedIdentityResolving: AnyObject {
    func feedID(accountID: String) -> String?
}

@MainActor
protocol HomeFeedProjectionControlling: HomeFeedIdentityResolving {
    var definition: NostrFeedDefinitionRecord? { get }
    var retainedWindowLimit: Int { get }

    func prewarmDefinition(
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
    ) async
}

extension HomeFeedProjectionController: HomeFeedProjectionControlling {}

@MainActor
protocol HomeTimelineViewportStateRestoring: AnyObject {
    func viewportState(
        accountID: String,
        timelineKey: String
    ) -> TimelineViewportState?
}

extension TimelineRestoreStore: HomeTimelineViewportStateRestoring {}

@MainActor
protocol HomeTimelineMaterializationCoordinating: AnyObject {
    typealias TransitionHandler = @MainActor @Sendable (
        _ transition: HomeTimelinePresentationTransition
    ) -> Void
    typealias ProjectionReloadHandler = @MainActor @Sendable (
        _ didReload: Bool
    ) -> Void

    func reloadNewestProjection(
        account: NostrAccount,
        preserving anchorEventID: String?,
        onCompletion: ProjectionReloadHandler?
    )

    func reloadProjection(
        account: NostrAccount,
        around anchorEventID: String?,
        mergingWithCurrentWindow: Bool,
        onCompletion: ProjectionReloadHandler?
    )

    func materialize(
        _ request: HomeTimelineMaterializationRequest,
        onTransition: @escaping TransitionHandler
    )

    func waitForPendingPresentation() async -> Bool

    func cancel()
}

extension HomeTimelineMaterializationCoordinator:
    HomeTimelineMaterializationCoordinating {}

@MainActor
final class HomeProjectionInteractionWorkflow {
    typealias TimestampProvider = @MainActor @Sendable () -> Int

    private let projection: any HomeFeedProjectionControlling
    private let viewportStateRestorer: any HomeTimelineViewportStateRestoring
    private let materialization: any HomeTimelineMaterializationCoordinating
    private let timestamp: TimestampProvider

    init(
        projection: any HomeFeedProjectionControlling,
        viewportStateRestorer: any HomeTimelineViewportStateRestoring,
        materialization: any HomeTimelineMaterializationCoordinating,
        timestamp: @escaping TimestampProvider = {
            Int(Date().timeIntervalSince1970)
        }
    ) {
        self.projection = projection
        self.viewportStateRestorer = viewportStateRestorer
        self.materialization = materialization
        self.timestamp = timestamp
    }

    func isCurrent(
        _ context: HomeFeedRuntimeContext?,
        accountID: String?
    ) -> Bool {
        projection.isCurrent(context, accountID: accountID)
    }

    func prepareDefinition(
        account: NostrAccount,
        followedPubkeys: [String],
        liveEvents: [NostrEvent]
    ) {
        projection.prewarmDefinition(
            accountID: account.pubkey,
            followedPubkeys: followedPubkeys,
            liveEvents: liveEvents,
            now: timestamp()
        )
    }

    func restoredViewportState(
        accountID: String,
        timelineKey: String
    ) -> TimelineViewportState? {
        guard timelineKey == "home",
              let state = viewportStateRestorer.viewportState(
                  accountID: accountID,
                  timelineKey: timelineKey
              ),
              state.accountID == accountID,
              state.timelineKey == timelineKey
        else { return nil }
        return state
    }

    func reloadNewestProjection(
        account: NostrAccount,
        preserving anchorEventID: String? = nil,
        onCompletion: HomeTimelineMaterializationCoordinating
            .ProjectionReloadHandler? = nil
    ) {
        materialization.reloadNewestProjection(
            account: account,
            preserving: anchorEventID,
            onCompletion: onCompletion
        )
    }

    func reloadProjection(
        account: NostrAccount,
        around anchorEventID: String?,
        mergingWithCurrentWindow: Bool,
        onCompletion: HomeTimelineMaterializationCoordinating
            .ProjectionReloadHandler? = nil
    ) {
        materialization.reloadProjection(
            account: account,
            around: anchorEventID,
            mergingWithCurrentWindow: mergingWithCurrentWindow,
            onCompletion: onCompletion
        )
    }

    func materialize(
        _ request: HomeTimelineMaterializationRequest,
        onTransition: @escaping HomeTimelineMaterializationCoordinating
            .TransitionHandler
    ) {
        materialization.materialize(
            request,
            onTransition: onTransition
        )
    }

    func cancelMaterialization() {
        materialization.cancel()
    }

    func waitForPendingPresentation() async -> Bool {
        await materialization.waitForPendingPresentation()
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
    ) async {
        await projection.activateStoredProjection(
            definition: definition,
            sourceAuthors: sourceAuthors
        )
    }
    #endif
}
