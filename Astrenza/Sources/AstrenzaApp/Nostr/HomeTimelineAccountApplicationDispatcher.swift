import AstrenzaCore

struct HomeTimelineAccountApplicationEffects: Sendable {
    typealias Action = @MainActor @Sendable () -> Void
    typealias Account = @MainActor @Sendable (_ account: NostrAccount) -> Void
    typealias AccountContextTransition = @MainActor @Sendable (
        _ transition: HomeTimelineAccountContextTransition
    ) -> Void
    typealias ProjectionViewportTransition = @MainActor @Sendable (
        _ transition: HomeTimelineProjectionViewportTransition
    ) -> Void
    typealias Phase = @MainActor @Sendable (
        _ phase: NostrHomeTimelinePhase
    ) -> Void
    typealias PresentationTransition = @MainActor @Sendable (
        _ transition: HomeTimelinePresentationTransition
    ) -> Void
    typealias ActivityTransition = @MainActor @Sendable (
        _ transition: HomeTimelineActivityTransition
    ) -> Void
    typealias ContentSnapshot = @MainActor @Sendable (
        _ snapshot: HomeTimelineContentSnapshot
    ) -> Void
    typealias RelayStatusSnapshot = @MainActor @Sendable (
        _ snapshot: HomeTimelineRelayStatusSnapshot
    ) -> Void
    typealias RuntimeConfiguration = @MainActor @Sendable (
        _ account: NostrAccount,
        _ forceInstall: Bool
    ) async -> Void

    let cancelCurrentAccount: Action
    let applyAccountContextTransition: AccountContextTransition
    let startRuntimeSession: Action
    let prepareHomeFeedDefinition: Account
    let applyProjectionViewportTransition: ProjectionViewportTransition
    let reloadNewestProjectionWindow: Account
    let materializeEntries: Action
    let applyRestoreProjectionAnchor: Account
    let installProvisionalRuntimeBootstrap: Account
    let setPhase: Phase
    let publishRelayStatusChange: Action
    let applyPresentationTransition: PresentationTransition
    let clearPendingEvents: Action
    let applyActivityTransition: ActivityTransition
    let invalidateListEntries: Action
    let resetRealtimeState: Action
    let applyContentSnapshot: ContentSnapshot
    let applyRelayStatusSnapshot: RelayStatusSnapshot
    let resetRuntimeSetup: Action
    let configureRuntime: RuntimeConfiguration
}

@MainActor
struct HomeTimelineAccountApplicationDispatcher {
    func apply(
        _ action: HomeTimelineAccountStartStoreAction,
        effects: HomeTimelineAccountApplicationEffects
    ) {
        switch action {
        case .account(let action):
            apply(action, effects: effects)
        case .projection(let action):
            apply(action, effects: effects)
        }
    }

    private func apply(
        _ action: HomeTimelineAccountStartAccountAction,
        effects: HomeTimelineAccountApplicationEffects
    ) {
        switch action {
        case .cancelCurrentAccount:
            effects.cancelCurrentAccount()
        case .applyAccountContextTransition(let transition):
            effects.applyAccountContextTransition(transition)
        case .startRuntimeSession:
            effects.startRuntimeSession()
        case .prepareHomeFeedDefinition(let account):
            effects.prepareHomeFeedDefinition(account)
        case .installProvisionalRuntimeBootstrap(let account):
            effects.installProvisionalRuntimeBootstrap(account)
        case .setPhase(let phase):
            effects.setPhase(phase)
        case .publishOutboxRelayResults:
            effects.publishRelayStatusChange()
        }
    }

    private func apply(
        _ action: HomeTimelineAccountStartProjectionAction,
        effects: HomeTimelineAccountApplicationEffects
    ) {
        switch action {
        case .applyProjectionViewportTransition(let transition):
            effects.applyProjectionViewportTransition(transition)
        case .reloadNewestProjectionWindow(let account):
            effects.reloadNewestProjectionWindow(account)
        case .materializeEntries:
            effects.materializeEntries()
        case .applyRestoreProjectionAnchor(let account):
            effects.applyRestoreProjectionAnchor(account)
        }
    }

    func apply(
        _ action: HomeTimelineAccountResetStoreAction,
        effects: HomeTimelineAccountApplicationEffects
    ) {
        switch action {
        case .applyPresentationTransition(let transition):
            effects.applyPresentationTransition(transition)
        case .clearPendingEvents:
            effects.clearPendingEvents()
        case .applyActivityTransition(let transition):
            effects.applyActivityTransition(transition)
        case .invalidateListEntries:
            effects.invalidateListEntries()
        case .resetRealtimeState:
            effects.resetRealtimeState()
        case .applyContentSnapshot(let snapshot):
            effects.applyContentSnapshot(snapshot)
        case .applyRelayStatusSnapshot(let snapshot):
            effects.applyRelayStatusSnapshot(snapshot)
        case .applyProjectionViewportTransition(let transition):
            effects.applyProjectionViewportTransition(transition)
        case .publishRelayStatusChange:
            effects.publishRelayStatusChange()
        case .applyAccountContextTransition(let transition):
            effects.applyAccountContextTransition(transition)
        }
    }

    func perform(
        _ action: HomeTimelineAccountResetAsyncAction,
        effects: HomeTimelineAccountApplicationEffects
    ) async {
        switch action {
        case .resetRuntimeState:
            effects.resetRuntimeSetup()
            effects.resetRealtimeState()
        case .startRuntimeSession:
            effects.startRuntimeSession()
        case .configureRuntime(let account, let forceInstall):
            await effects.configureRuntime(account, forceInstall)
        }
    }
}
