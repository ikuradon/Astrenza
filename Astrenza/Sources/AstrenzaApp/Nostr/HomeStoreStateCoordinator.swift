import AstrenzaCore

@MainActor
protocol HomeStoreStateDataInteracting: AnyObject {
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
protocol HomeStoreStateSourcing: AnyObject {
    var account: NostrAccount? { get }
    var syncPolicy: NostrSyncPolicy { get }
    var resolvedRelays: [String] { get }
    var followedPubkeys: [String] { get }
    var hasMoreOlder: Bool { get }

    func currentAccountID() -> String?
}

extension HomeTimelinePublishedStateCoordinator:
    HomeStoreStateSourcing {
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
    private let source: any HomeStoreStateSourcing
    private let contexts: any HomeStoreStateContextProviding

    init(
        data: any HomeStoreStateDataInteracting,
        state: any HomeStoreTimelineStateInteracting,
        source: any HomeStoreStateSourcing,
        contexts: any HomeStoreStateContextProviding
    ) {
        self.data = data
        self.state = state
        self.source = source
        self.contexts = contexts
    }

    static func live(
        components: HomeTimelineStoreComponents,
        contexts: HomeStoreContextCoordinator
    ) -> HomeStoreStateCoordinator {
        HomeStoreStateCoordinator(
            data: components.dataInteractionWorkflow,
            state: components.stateInteractionWorkflow,
            source: components.publishedStateCoordinator,
            contexts: contexts
        )
    }

    var account: NostrAccount? {
        source.account
    }

    var currentSyncPolicy: NostrSyncPolicy {
        source.syncPolicy
    }

    var resolvedRelays: [String] {
        source.resolvedRelays
    }

    var followedPubkeys: [String] {
        source.followedPubkeys
    }

    var hasMoreOlder: Bool {
        source.hasMoreOlder
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
            accountID: source.currentAccountID(),
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
