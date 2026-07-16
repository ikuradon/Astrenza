import AstrenzaCore

@MainActor
protocol HomeStoreStateDataInteracting: AnyObject {
    var contentState: HomeTimelineContentSnapshot { get }

    func perform(
        _ intent: HomeTimelineDataIntent
    ) -> HomeTimelineContentSnapshot

    func runtimeBootstrapState(
        from state: NostrHomeTimelineState
    ) -> NostrHomeTimelineState

    func persistenceSnapshotInput(
        accountID: String
    ) -> HomeTimelineSnapshotInput

    #if DEBUG
    var dependencyWorkState: HomeTimelineDependencyWorkState { get }

    @discardableResult
    func enqueueSourceDependencies(
        _ dependencies: NostrEventDependencies,
        availableRelayURLs: [String],
        now: Int
    ) -> Bool

    @discardableResult
    func flushSourcePacketInstall(
        onFailure: @escaping HomeDependencyInstallFailureHandler
    ) -> Bool
    #endif
}

extension HomeTimelineDataInteractionWorkflow:
    HomeStoreStateDataInteracting {}

@MainActor
protocol HomeStoreTimelineStateInteracting: AnyObject {
    func replace(
        _ state: NostrHomeTimelineState,
        accountID: String?,
        context: HomeTimelineStateInteractionContext
    )

    @discardableResult
    func persistSnapshot(
        _ input: HomeTimelineSnapshotInput,
        context: HomeTimelineStateInteractionContext
    ) async -> Bool
}

extension HomeTimelineStateInteractionWorkflow:
    HomeStoreTimelineStateInteracting {}

@MainActor
protocol HomeStoreStateAccountSourcing: AnyObject {
    func currentAccountID() -> String?
}

extension HomeTimelinePublishedStateCoordinator:
    HomeStoreStateAccountSourcing {
    func currentAccountID() -> String? {
        accountContext.account?.pubkey
    }
}

@MainActor
protocol HomeStoreStateContextProviding: AnyObject {
    func stateContext() -> HomeTimelineStateInteractionContext
}

extension HomeStoreContextCoordinator: HomeStoreStateContextProviding {}

@MainActor
final class HomeStoreStateCoordinator {
    private let data: any HomeStoreStateDataInteracting
    private let state: any HomeStoreTimelineStateInteracting
    private let accountSource: any HomeStoreStateAccountSourcing
    private let contexts: any HomeStoreStateContextProviding

    init(
        data: any HomeStoreStateDataInteracting,
        state: any HomeStoreTimelineStateInteracting,
        accountSource: any HomeStoreStateAccountSourcing,
        contexts: any HomeStoreStateContextProviding
    ) {
        self.data = data
        self.state = state
        self.accountSource = accountSource
        self.contexts = contexts
    }

    static func live(
        components: HomeTimelineStoreComponents,
        contexts: HomeStoreContextCoordinator
    ) -> HomeStoreStateCoordinator {
        HomeStoreStateCoordinator(
            data: components.dataInteractionWorkflow,
            state: components.stateInteractionWorkflow,
            accountSource: components.publishedStateCoordinator,
            contexts: contexts
        )
    }

    var preferredEvents: [NostrEvent] {
        data.contentState.noteEvents
    }

    func installProvisionalRelays(
        _ relays: [String]
    ) -> HomeTimelineContentSnapshot {
        data.perform(.installProvisionalRelays(relays))
    }

    func replaceFollowedPubkeys(
        _ pubkeys: [String]
    ) -> HomeTimelineContentSnapshot {
        data.perform(.replaceFollowedPubkeys(pubkeys))
    }

    func replaceRuntimeBootstrapState(
        _ bootstrapState: NostrHomeTimelineState
    ) {
        replaceTimelineState(
            data.runtimeBootstrapState(from: bootstrapState)
        )
    }

    func replaceTimelineState(
        _ timelineState: NostrHomeTimelineState
    ) {
        state.replace(
            timelineState,
            accountID: accountSource.currentAccountID(),
            context: contexts.stateContext()
        )
    }

    @discardableResult
    func persistDatabase(accountID: String) async -> Bool {
        await state.persistSnapshot(
            data.persistenceSnapshotInput(accountID: accountID),
            context: contexts.stateContext()
        )
    }
}

#if DEBUG
extension HomeStoreStateCoordinator {
    @discardableResult
    func enqueueSourceDependencies(
        _ dependencies: NostrEventDependencies,
        availableRelayURLs: [String],
        now: Int
    ) -> Bool {
        data.enqueueSourceDependencies(
            dependencies,
            availableRelayURLs: availableRelayURLs,
            now: now
        )
    }

    @discardableResult
    func flushSourcePacketInstall(
        onFailure: @escaping HomeDependencyInstallFailureHandler
    ) -> Bool {
        data.flushSourcePacketInstall(onFailure: onFailure)
    }

    var pendingDependencyRequestCount: Int {
        data.dependencyWorkState.pendingSourceRequestCount
    }

    var hasPendingDependencyWork: Bool {
        data.dependencyWorkState.hasPendingWork
    }
}
#endif
