import AstrenzaCore

@MainActor
protocol HomeTimelineStateApplying: AnyObject {
    @discardableResult
    func restoreCachedState(
        accountID: String,
        handlers: HomeTimelineStateApplicationHandlers
    ) -> Bool

    func replace(
        _ state: NostrHomeTimelineState,
        accountID: String?,
        handlers: HomeTimelineStateApplicationHandlers
    )
}

extension HomeTimelineStateApplicationCoordinator: HomeTimelineStateApplying {}

@MainActor
protocol HomeTimelineStatePersisting: AnyObject {
    @discardableResult
    func persistSnapshot(
        _ input: HomeTimelineSnapshotInput,
        handlers: HomeTimelinePersistenceHandlers
    ) async -> Bool

    @discardableResult
    func persistMetadata(
        _ snapshot: HomeTimelineMetadataSnapshot,
        handlers: HomeTimelinePersistenceHandlers
    ) async -> Bool
}

extension HomeTimelinePersistenceCoordinator: HomeTimelineStatePersisting {}

struct HomeTimelineStateWorkflowEffects: Sendable {
    typealias PresentationTransition = @MainActor @Sendable (
        _ transition: HomeTimelinePresentationTransition
    ) -> Void
    typealias ContentSnapshot = @MainActor @Sendable (
        _ snapshot: HomeTimelineContentSnapshot
    ) -> Void
    typealias RelayStatusSnapshot = @MainActor @Sendable (
        _ snapshot: HomeTimelineRelayStatusSnapshot
    ) -> Void
    typealias ListProjectionInvalidation = @MainActor @Sendable (
        _ invalidation: HomeTimelineListProjectionInvalidation
    ) -> Void
    typealias CountChange = @MainActor @Sendable (_ count: Int) -> Void
    typealias PersistenceState = @MainActor @Sendable () -> HomeTimelinePersistenceState
    typealias PendingEvents = @MainActor @Sendable () -> Bool
    typealias Action = @MainActor @Sendable () -> Void

    let applyPresentationTransition: PresentationTransition
    let applyContentSnapshot: ContentSnapshot
    let applyRelayStatusSnapshot: RelayStatusSnapshot
    let applyListProjectionInvalidation: ListProjectionInvalidation
    let pendingCountChanged: CountChange
    let persistenceState: PersistenceState
    let hasPendingEvents: PendingEvents
    let materializeEntries: Action
}

struct HomeTimelineRuntimeApplicationState: Sendable {
    typealias Provider = @MainActor @Sendable () -> HomeTimelineRuntimeApplicationState?

    let account: NostrAccount?
    let resolvedRelays: [String]
    let followedPubkeys: [String]
    let nip05Resolutions: [String: NostrNIP05Resolution]
    let hasMoreOlder: Bool
    let deferredMaterializationDelayNanoseconds: UInt64
}

struct HomeTimelineRuntimeApplicationDiagnostic: Equatable, Sendable {
    let relayURL: String
    let message: String
}

struct HomeTimelineRuntimeApplicationActions: Sendable {
    typealias ProjectionReload = @MainActor @Sendable (
        _ account: NostrAccount,
        _ anchorEventID: String?
    ) -> Void
    typealias Action = @MainActor @Sendable () -> Void
    typealias MaterializationSchedule = @MainActor @Sendable (
        _ delayNanoseconds: UInt64?,
        _ allowsRealtimeFollow: Bool?
    ) -> Void
    typealias Diagnostic = @MainActor @Sendable (
        _ diagnostic: HomeTimelineRuntimeApplicationDiagnostic
    ) -> Void

    let reloadProjection: ProjectionReload
    let requestNewestProjectionReload: Action
    let scheduleMaterialization: MaterializationSchedule
    let materializeEntries: Action
    let recordDiagnostic: Diagnostic
}

@MainActor
final class HomeTimelineStateWorkflow {
    private let stateApplication: any HomeTimelineStateApplying
    private let persistence: any HomeTimelineStatePersisting

    init(
        stateApplication: any HomeTimelineStateApplying,
        persistence: any HomeTimelineStatePersisting
    ) {
        self.stateApplication = stateApplication
        self.persistence = persistence
    }

    @discardableResult
    func restoreCachedState(
        accountID: String,
        effects: HomeTimelineStateWorkflowEffects
    ) -> Bool {
        stateApplication.restoreCachedState(
            accountID: accountID,
            handlers: applicationHandlers(effects: effects)
        )
    }

    func replace(
        _ state: NostrHomeTimelineState,
        accountID: String?,
        effects: HomeTimelineStateWorkflowEffects
    ) {
        stateApplication.replace(
            state,
            accountID: accountID,
            handlers: applicationHandlers(effects: effects)
        )
    }

    @discardableResult
    func persistSnapshot(
        _ input: HomeTimelineSnapshotInput,
        effects: HomeTimelineStateWorkflowEffects
    ) async -> Bool {
        await persistence.persistSnapshot(
            input,
            handlers: persistenceHandlers(effects: effects)
        )
    }

    @discardableResult
    func persistMetadata(
        _ snapshot: HomeTimelineMetadataSnapshot,
        effects: HomeTimelineStateWorkflowEffects
    ) async -> Bool {
        await persistence.persistMetadata(
            snapshot,
            handlers: persistenceHandlers(effects: effects)
        )
    }

    func runtimeApplicationEffects(
        state: @escaping HomeTimelineRuntimeApplicationState.Provider,
        actions: HomeTimelineRuntimeApplicationActions,
        effects: HomeTimelineStateWorkflowEffects
    ) -> HomeTimelineRuntimeApplicationEffects {
        HomeTimelineRuntimeApplicationEffects(
            applyListProjectionInvalidation: effects.applyListProjectionInvalidation,
            pendingCountChanged: effects.pendingCountChanged,
            reloadProjection: { [weak self] anchorEventID, materialization in
                self?.reloadProjection(
                    anchorEventID: anchorEventID,
                    materialization: materialization,
                    state: state,
                    actions: actions
                )
            },
            reloadNewestProjection: { allowsRealtimeFollow in
                actions.requestNewestProjectionReload()
                actions.scheduleMaterialization(nil, allowsRealtimeFollow)
            },
            scheduleMaterialization: { [weak self] schedule in
                self?.scheduleMaterialization(
                    schedule,
                    state: state,
                    actions: actions
                )
            },
            persistTimelineMetadata: { [weak self] account in
                await self?.persistTimelineMetadata(
                    account: account,
                    state: state,
                    effects: effects
                )
            },
            sourceInstallFailed: { [weak self] message in
                self?.recordSourceInstallFailure(
                    message,
                    state: state,
                    actions: actions
                )
            }
        )
    }

    private func applicationHandlers(
        effects: HomeTimelineStateWorkflowEffects
    ) -> HomeTimelineStateApplicationHandlers {
        HomeTimelineStateApplicationHandlers(
            applyPresentationTransition: effects.applyPresentationTransition,
            applyContentSnapshot: effects.applyContentSnapshot,
            applyRelayStatusSnapshot: effects.applyRelayStatusSnapshot,
            applyListProjectionInvalidation: effects.applyListProjectionInvalidation,
            pendingCountChanged: effects.pendingCountChanged
        )
    }

    private func persistenceHandlers(
        effects: HomeTimelineStateWorkflowEffects
    ) -> HomeTimelinePersistenceHandlers {
        HomeTimelinePersistenceHandlers(
            state: effects.persistenceState,
            hasPendingEvents: effects.hasPendingEvents,
            perform: { [weak self] command in
                self?.apply(command, effects: effects)
            }
        )
    }

    private func apply(
        _ command: HomeTimelinePersistenceCommand,
        effects: HomeTimelineStateWorkflowEffects
    ) {
        switch command {
        case .materializeEntries:
            effects.materializeEntries()
        }
    }

    private func reloadProjection(
        anchorEventID: String?,
        materialization: HomeTimelineRuntimeEventApplicationPlan.DeletionMaterialization,
        state: HomeTimelineRuntimeApplicationState.Provider,
        actions: HomeTimelineRuntimeApplicationActions
    ) {
        guard let account = state()?.account else { return }
        actions.reloadProjection(account, anchorEventID)
        switch materialization {
        case .scheduled(let allowsRealtimeFollow):
            actions.scheduleMaterialization(nil, allowsRealtimeFollow)
        case .immediate:
            actions.materializeEntries()
        }
    }

    private func scheduleMaterialization(
        _ schedule: HomeTimelineRuntimeEventApplicationPlan.MaterializationSchedule,
        state: HomeTimelineRuntimeApplicationState.Provider,
        actions: HomeTimelineRuntimeApplicationActions
    ) {
        switch schedule {
        case .standard:
            actions.scheduleMaterialization(nil, nil)
        case .deferredDependencies:
            guard let state = state() else { return }
            actions.scheduleMaterialization(
                state.deferredMaterializationDelayNanoseconds,
                nil
            )
        }
    }

    private func persistTimelineMetadata(
        account: NostrAccount,
        state: HomeTimelineRuntimeApplicationState.Provider,
        effects: HomeTimelineStateWorkflowEffects
    ) async {
        guard let state = state() else { return }
        await persistMetadata(
            HomeTimelineMetadataSnapshot(
                accountID: account.pubkey,
                relays: state.resolvedRelays,
                followedPubkeys: state.followedPubkeys,
                nip05Resolutions: state.nip05Resolutions,
                hasMoreOlder: state.hasMoreOlder
            ),
            effects: effects
        )
    }

    private func recordSourceInstallFailure(
        _ message: String,
        state: HomeTimelineRuntimeApplicationState.Provider,
        actions: HomeTimelineRuntimeApplicationActions
    ) {
        guard let state = state() else { return }
        actions.recordDiagnostic(HomeTimelineRuntimeApplicationDiagnostic(
            relayURL: state.resolvedRelays.first ?? "runtime",
            message: "backward enqueue failed: \(message)"
        ))
    }
}
