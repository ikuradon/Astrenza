import AstrenzaCore
import Foundation

struct HomeTimelineMaterializationRequest: Sendable {
    let account: NostrAccount?
    let nip05Resolutions: [String: NostrNIP05Resolution]
    let profileResolutionStates: [String: NostrProfileResolutionState]
    let policy: NostrSyncPolicy
    let allowsRealtimeFollow: Bool
}

@MainActor
final class HomeTimelineMaterializationCoordinator {
    typealias TransitionHandler = @MainActor @Sendable (
        _ transition: HomeTimelinePresentationTransition
    ) -> Void

    private let contentCoordinator: HomeTimelineContentCoordinator
    private let filterCoordinator: HomeTimelineFilterCoordinator
    private let presentationCoordinator: HomeTimelinePresentationCoordinator
    private let projectionController: HomeFeedProjectionController
    private let worker: any HomeTimelineMaterializationWorking

    private var materializationTask: Task<Void, Never>?
    private var materializationGeneration: UInt64 = 0

    init(
        contentCoordinator: HomeTimelineContentCoordinator,
        filterCoordinator: HomeTimelineFilterCoordinator,
        presentationCoordinator: HomeTimelinePresentationCoordinator,
        projectionController: HomeFeedProjectionController,
        worker: any HomeTimelineMaterializationWorking
    ) {
        self.contentCoordinator = contentCoordinator
        self.filterCoordinator = filterCoordinator
        self.presentationCoordinator = presentationCoordinator
        self.projectionController = projectionController
        self.worker = worker
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
        _ request: HomeTimelineMaterializationRequest,
        onTransition: @escaping TransitionHandler
    ) {
        guard let pass = presentationCoordinator.beginMaterialization(
            allowsRealtimeFollow: request.allowsRealtimeFollow
        ) else {
            cancelTask()
            return
        }
        if pass.shouldReloadNewestProjection, let account = request.account {
            reloadNewestProjection(account: account)
            presentationCoordinator.clearNewestProjectionReload()
        }

        let content = contentCoordinator.snapshot
        startMaterialization(
            HomeTimelineMaterializationInput(
                accountID: request.account?.pubkey,
                noteEvents: content.noteEvents,
                feedWindow: projectionController.window,
                metadataEvents: content.metadataEvents,
                nip05Resolutions: request.nip05Resolutions,
                profileResolutionStates: request.profileResolutionStates,
                followedPubkeys: content.followedPubkeys,
                resolvedRelayCount: content.resolvedRelays.count,
                filtersSuspended: filterCoordinator.filtersSuspended,
                filterTimestamp: Int(Date().timeIntervalSince1970),
                policy: request.policy
            ),
            pass: pass,
            onTransition: onTransition
        )
    }

    func cancel() {
        cancelTask()
        presentationCoordinator.cancelMaterialization()
    }

    private func startMaterialization(
        _ input: HomeTimelineMaterializationInput,
        pass: HomeTimelineMaterializationPass,
        onTransition: @escaping TransitionHandler
    ) {
        cancelTask()
        let generation = materializationGeneration
        let worker = worker
        materializationTask = Task { [weak self] in
            guard let materialized = await worker.materialize(input),
                  !Task.isCancelled,
                  let self
            else { return }
            finishMaterialization(
                materialized,
                pass: pass,
                generation: generation,
                onTransition: onTransition
            )
        }
    }

    private func finishMaterialization(
        _ materialized: HomeTimelineMaterializedSnapshot,
        pass: HomeTimelineMaterializationPass,
        generation: UInt64,
        onTransition: TransitionHandler
    ) {
        guard generation == materializationGeneration else { return }
        materializationTask = nil
        guard let transition = presentationCoordinator.apply(
            materialized,
            pass: pass
        ) else { return }
        onTransition(transition)
    }

    private func cancelTask() {
        materializationGeneration &+= 1
        materializationTask?.cancel()
        materializationTask = nil
    }
}
