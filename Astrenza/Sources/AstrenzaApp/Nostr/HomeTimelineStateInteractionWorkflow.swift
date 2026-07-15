import AstrenzaCore

@MainActor
protocol HomeTimelineStateRouting: AnyObject {
    @discardableResult
    func restoreCachedState(
        accountID: String,
        effects: HomeTimelineStateWorkflowEffects
    ) async -> Bool

    func replace(
        _ state: NostrHomeTimelineState,
        accountID: String?,
        effects: HomeTimelineStateWorkflowEffects
    )

    @discardableResult
    func persistSnapshot(
        _ input: HomeTimelineSnapshotInput,
        effects: HomeTimelineStateWorkflowEffects
    ) async -> Bool

    func runtimeApplicationEffects(
        state: @escaping HomeTimelineRuntimeApplicationState.Provider,
        actions: HomeTimelineRuntimeApplicationActions,
        effects: HomeTimelineStateWorkflowEffects
    ) -> HomeTimelineRuntimeApplicationEffects
}

extension HomeTimelineStateWorkflow: HomeTimelineStateRouting {}

struct HomeTimelineStateInteractionEnvironment: Sendable {
    typealias PersistenceStateProvider = @MainActor @Sendable () -> HomeTimelinePersistenceState
    typealias PendingEventsProvider = @MainActor @Sendable () -> Bool

    let persistenceState: PersistenceStateProvider
    let hasPendingEvents: PendingEventsProvider
    let runtimeApplicationState: HomeTimelineRuntimeApplicationState.Provider
}

enum HomeTimelineStateInteractionApplication {
    case applyPresentationTransition(HomeTimelinePresentationTransition)
    case applyContentSnapshot(HomeTimelineContentSnapshot)
    case applyRelayStatusSnapshot(HomeTimelineRelayStatusSnapshot)
    case applyListProjectionInvalidation(HomeTimelineListProjectionInvalidation)
    case applyPendingEventCountPublication(
        HomeTimelinePendingEventCountPublication
    )
    case reloadProjection(account: NostrAccount, anchorEventID: String?)
    case requestNewestProjectionReload
    case scheduleMaterialization(
        delayNanoseconds: UInt64?,
        allowsRealtimeFollow: Bool?
    )
    case materializeEntries
    case applyRelayStatusTransition(HomeTimelineRelayStatusTransition)
}

struct HomeTimelineStateInteractionEffects: Sendable {
    typealias ApplicationEffect = @MainActor @Sendable (
        _ application: HomeTimelineStateInteractionApplication
    ) -> Void

    let environment: HomeTimelineStateInteractionEnvironment
    let apply: ApplicationEffect
}

struct HomeTimelineStateInteractionContext: Sendable {
    let effects: HomeTimelineStateInteractionEffects
}

@MainActor
final class HomeTimelineStateInteractionWorkflow {
    private let stateWorkflow: any HomeTimelineStateRouting
    private let relayStatus: any HomeTimelineRelayStatusRecording

    init(
        stateWorkflow: any HomeTimelineStateRouting,
        relayStatus: any HomeTimelineRelayStatusRecording
    ) {
        self.stateWorkflow = stateWorkflow
        self.relayStatus = relayStatus
    }

    @discardableResult
    func restoreCachedState(
        accountID: String,
        context: HomeTimelineStateInteractionContext
    ) async -> Bool {
        await stateWorkflow.restoreCachedState(
            accountID: accountID,
            effects: stateEffects(for: context.effects)
        )
    }

    func replace(
        _ state: NostrHomeTimelineState,
        accountID: String?,
        context: HomeTimelineStateInteractionContext
    ) {
        stateWorkflow.replace(
            state,
            accountID: accountID,
            effects: stateEffects(for: context.effects)
        )
    }

    @discardableResult
    func persistSnapshot(
        _ input: HomeTimelineSnapshotInput,
        context: HomeTimelineStateInteractionContext
    ) async -> Bool {
        await stateWorkflow.persistSnapshot(
            input,
            effects: stateEffects(for: context.effects)
        )
    }

    func runtimeApplicationEffects(
        context: HomeTimelineStateInteractionContext
    ) -> HomeTimelineRuntimeApplicationEffects {
        stateWorkflow.runtimeApplicationEffects(
            state: context.effects.environment.runtimeApplicationState,
            actions: runtimeActions(for: context.effects),
            effects: stateEffects(for: context.effects)
        )
    }

    private func stateEffects(
        for effects: HomeTimelineStateInteractionEffects
    ) -> HomeTimelineStateWorkflowEffects {
        HomeTimelineStateWorkflowEffects(
            applyPresentationTransition: { transition in
                effects.apply(.applyPresentationTransition(transition))
            },
            applyContentSnapshot: { snapshot in
                effects.apply(.applyContentSnapshot(snapshot))
            },
            applyRelayStatusSnapshot: { snapshot in
                effects.apply(.applyRelayStatusSnapshot(snapshot))
            },
            applyListProjectionInvalidation: { invalidation in
                effects.apply(.applyListProjectionInvalidation(invalidation))
            },
            applyPendingEventCountPublication: { publication in
                effects.apply(.applyPendingEventCountPublication(publication))
            },
            persistenceState: effects.environment.persistenceState,
            hasPendingEvents: effects.environment.hasPendingEvents,
            materializeEntries: {
                effects.apply(.materializeEntries)
            }
        )
    }

    private func runtimeActions(
        for effects: HomeTimelineStateInteractionEffects
    ) -> HomeTimelineRuntimeApplicationActions {
        HomeTimelineRuntimeApplicationActions(
            reloadProjection: { account, anchorEventID in
                effects.apply(.reloadProjection(
                    account: account,
                    anchorEventID: anchorEventID
                ))
            },
            requestNewestProjectionReload: {
                effects.apply(.requestNewestProjectionReload)
            },
            scheduleMaterialization: { delay, allowsRealtimeFollow in
                effects.apply(.scheduleMaterialization(
                    delayNanoseconds: delay,
                    allowsRealtimeFollow: allowsRealtimeFollow
                ))
            },
            materializeEntries: {
                effects.apply(.materializeEntries)
            },
            recordDiagnostic: { diagnostic in
                self.recordRuntimeDiagnostic(
                    diagnostic,
                    effects: effects
                )
            }
        )
    }

    private func recordRuntimeDiagnostic(
        _ diagnostic: HomeTimelineRuntimeApplicationDiagnostic,
        effects: HomeTimelineStateInteractionEffects
    ) {
        guard let state = effects.environment.runtimeApplicationState(),
              let transition = relayStatus.recordDiagnostic(
                  diagnostic,
                  accountID: state.account?.pubkey,
                  resolvedRelays: state.resolvedRelays
              )
        else { return }
        effects.apply(.applyRelayStatusTransition(transition))
    }
}
