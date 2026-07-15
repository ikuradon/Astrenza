import AstrenzaCore

struct HomeTimelineMaterializationRequest: Sendable {
    let account: NostrAccount?
    let nip05Resolutions: [String: NostrNIP05Resolution]
    let profileResolutionStates: [String: NostrProfileResolutionState]
    let policy: NostrSyncPolicy
    let allowsRealtimeFollow: Bool
}

@MainActor
final class HomeTimelineMaterializationCoordinator {
    private let contentCoordinator: HomeTimelineContentCoordinator
    private let filterCoordinator: HomeTimelineFilterCoordinator
    private let presentationCoordinator: HomeTimelinePresentationCoordinator
    private let projectionController: HomeFeedProjectionController
    private let repository: HomeTimelineRepository

    init(
        contentCoordinator: HomeTimelineContentCoordinator,
        filterCoordinator: HomeTimelineFilterCoordinator,
        presentationCoordinator: HomeTimelinePresentationCoordinator,
        projectionController: HomeFeedProjectionController,
        repository: HomeTimelineRepository
    ) {
        self.contentCoordinator = contentCoordinator
        self.filterCoordinator = filterCoordinator
        self.presentationCoordinator = presentationCoordinator
        self.projectionController = projectionController
        self.repository = repository
    }

    @discardableResult
    func reloadNewestProjection(account: NostrAccount) -> Bool {
        let content = contentCoordinator.snapshot
        guard let window = projectionController.reloadNewest(
            accountID: account.pubkey,
            followedPubkeys: content.followedPubkeys,
            liveEvents: content.noteEvents
        ) else { return false }
        contentCoordinator.replaceProjectionEvents(window.events)
        return true
    }

    @discardableResult
    func reloadProjection(
        account: NostrAccount,
        around anchorEventID: String?,
        mergingWithCurrentWindow: Bool
    ) -> Bool {
        let content = contentCoordinator.snapshot
        guard let window = projectionController.reload(
            accountID: account.pubkey,
            followedPubkeys: content.followedPubkeys,
            liveEvents: content.noteEvents,
            around: anchorEventID,
            mergingWithCurrentWindow: mergingWithCurrentWindow
        ) else { return false }
        contentCoordinator.replaceProjectionEvents(window.events)
        return true
    }

    func materialize(
        _ request: HomeTimelineMaterializationRequest
    ) -> HomeTimelinePresentationTransition? {
        guard let pass = presentationCoordinator.beginMaterialization(
            allowsRealtimeFollow: request.allowsRealtimeFollow
        ) else { return nil }
        if pass.shouldReloadNewestProjection, let account = request.account {
            reloadNewestProjection(account: account)
            presentationCoordinator.clearNewestProjectionReload()
        }

        let content = contentCoordinator.snapshot
        let filterProjection = filterCoordinator.projection(
            accountID: request.account?.pubkey,
            events: content.noteEvents
        )
        let contextEvents = repository.contextEvents(for: content.noteEvents)
        let materialized = repository.materialize(
            HomeTimelineRenderInput(
                noteEvents: content.noteEvents,
                feedWindow: projectionController.window,
                contextEvents: contextEvents,
                metadataEvents: content.metadataEvents,
                nip05Resolutions: request.nip05Resolutions,
                profileResolutionStates: request.profileResolutionStates,
                followedPubkeys: content.followedPubkeys,
                resolvedRelayCount: content.resolvedRelays.count,
                filterRules: filterProjection.effectiveRuleSet,
                filterStatus: filterProjection.status,
                timeline: .home,
                policy: request.policy
            )
        )
        return presentationCoordinator.apply(materialized, pass: pass)
    }
}
