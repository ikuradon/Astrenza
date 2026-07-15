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
    typealias ProjectionReloadHandler = @MainActor @Sendable (
        _ didReload: Bool
    ) -> Void

    private let contentCoordinator: HomeTimelineContentCoordinator
    private let filterCoordinator: HomeTimelineFilterCoordinator
    private let presentationCoordinator: HomeTimelinePresentationCoordinator
    private let projectionController: HomeFeedProjectionController
    private let worker: any HomeTimelineMaterializationWorking

    private var materializationTask: Task<Void, Never>?
    private var materializationGeneration: UInt64 = 0
    private var projectionTask: Task<Bool, Never>?
    private var projectionGeneration: UInt64 = 0

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

    func reloadNewestProjection(
        account: NostrAccount,
        onCompletion: ProjectionReloadHandler? = nil
    ) {
        let content = contentCoordinator.snapshot
        let projectionController = projectionController
        enqueueProjectionReload(onCompletion: onCompletion) {
            await projectionController.reloadNewest(
                accountID: account.pubkey,
                followedPubkeys: content.followedPubkeys,
                liveEvents: content.noteEvents
            )
        }
    }

    func reloadProjection(
        account: NostrAccount,
        around anchorEventID: String?,
        mergingWithCurrentWindow: Bool,
        onCompletion: ProjectionReloadHandler? = nil
    ) {
        let content = contentCoordinator.snapshot
        let projectionController = projectionController
        enqueueProjectionReload(onCompletion: onCompletion) {
            await projectionController.reload(
                accountID: account.pubkey,
                followedPubkeys: content.followedPubkeys,
                liveEvents: content.noteEvents,
                around: anchorEventID,
                mergingWithCurrentWindow: mergingWithCurrentWindow
            )
        }
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

        startMaterialization(
            request,
            pass: pass,
            onTransition: onTransition
        )
    }

    func cancel() {
        cancelTask()
        cancelProjectionTask()
        presentationCoordinator.cancelMaterialization()
    }

    func waitForPendingPresentation() async {
        if let projectionTask {
            _ = await projectionTask.value
        }
        if let materializationTask {
            await materializationTask.value
        }
    }

    private func startMaterialization(
        _ request: HomeTimelineMaterializationRequest,
        pass: HomeTimelineMaterializationPass,
        onTransition: @escaping TransitionHandler
    ) {
        cancelTask()
        let generation = materializationGeneration
        let worker = worker
        let pendingProjectionTask = projectionTask
        materializationTask = Task { [weak self] in
            if let pendingProjectionTask {
                _ = await pendingProjectionTask.value
            }
            guard !Task.isCancelled,
                  let self,
                  generation == materializationGeneration
            else { return }
            let input = materializationInput(for: request)
            guard let materialized = await worker.materialize(input),
                  !Task.isCancelled,
                  generation == materializationGeneration
            else { return }
            finishMaterialization(
                materialized,
                pass: pass,
                generation: generation,
                onTransition: onTransition
            )
        }
    }

    private func materializationInput(
        for request: HomeTimelineMaterializationRequest
    ) -> HomeTimelineMaterializationInput {
        let content = contentCoordinator.snapshot
        return HomeTimelineMaterializationInput(
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
        )
    }

    private func enqueueProjectionReload(
        onCompletion: ProjectionReloadHandler?,
        operation: @escaping @MainActor @Sendable (
        ) async -> NostrFeedWindow?
    ) {
        cancelTask()
        projectionTask?.cancel()
        projectionGeneration &+= 1
        let generation = projectionGeneration
        projectionTask = Task { [weak self] in
            guard !Task.isCancelled else { return false }
            let window = await operation()
            guard let self,
                  !Task.isCancelled,
                  generation == projectionGeneration
            else { return false }
            let didReload = window != nil
            if let window {
                contentCoordinator.replaceProjectionEvents(window.events)
            }
            projectionTask = nil
            onCompletion?(didReload)
            return didReload
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

    private func cancelProjectionTask() {
        projectionGeneration &+= 1
        projectionTask?.cancel()
        projectionTask = nil
    }
}
