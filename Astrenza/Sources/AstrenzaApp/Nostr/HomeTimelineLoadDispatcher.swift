import AstrenzaCore

struct HomeTimelineLoadApplicationEffects: Sendable {
    typealias Action = @MainActor @Sendable () -> Void
    typealias Account = @MainActor @Sendable (
        _ account: NostrAccount
    ) -> Void
    typealias ActivityTransition = @MainActor @Sendable (
        _ transition: HomeTimelineActivityTransition
    ) -> Void
    typealias RelayStatusTransition = @MainActor @Sendable (
        _ transition: HomeTimelineRelayStatusTransition
    ) -> Void
    typealias TimelineState = @MainActor @Sendable (
        _ state: NostrHomeTimelineState
    ) -> Void
    typealias FollowedPubkeys = @MainActor @Sendable (
        _ pubkeys: [String]
    ) -> Void
    typealias Phase = @MainActor @Sendable (
        _ phase: NostrHomeTimelinePhase
    ) -> Void
    typealias AsyncAccount = @MainActor @Sendable (
        _ account: NostrAccount
    ) async -> Void

    let applyActivityTransition: ActivityTransition
    let applyRelayStatusTransition: RelayStatusTransition
    let installProvisionalRuntimeBootstrap: Account
    let restartAccount: Account
    let replaceTimelineState: TimelineState
    let replaceRuntimeBootstrapState: TimelineState
    let replaceFollowedPubkeys: FollowedPubkeys
    let materializeEntries: Action
    let setPhase: Phase
    let configureRuntime: AsyncAccount
    let persistDatabase: AsyncAccount
}

@MainActor
struct HomeTimelineLoadDispatcher {
    func apply(
        _ application: HomeTimelineLoadApplication,
        effects: HomeTimelineLoadApplicationEffects
    ) {
        switch application {
        case .applyActivityTransition(let transition):
            effects.applyActivityTransition(transition)
        case .applyRelayStatusTransition(let transition):
            effects.applyRelayStatusTransition(transition)
        case .installProvisionalRuntimeBootstrap(let account):
            effects.installProvisionalRuntimeBootstrap(account)
        case .restartAccount(let account):
            effects.restartAccount(account)
        case .replaceTimelineState(let state):
            effects.replaceTimelineState(state)
        case .replaceRuntimeBootstrapState(let state):
            effects.replaceRuntimeBootstrapState(state)
        case .replaceFollowedPubkeys(let pubkeys):
            effects.replaceFollowedPubkeys(pubkeys)
        case .materializeEntries:
            effects.materializeEntries()
        case .setPhase(let phase):
            effects.setPhase(phase)
        }
    }

    func perform(
        _ application: HomeTimelineLoadAsyncApplication,
        effects: HomeTimelineLoadApplicationEffects
    ) async {
        switch application {
        case .configureRuntime(let account):
            await effects.configureRuntime(account)
        case .persistDatabase(let account):
            await effects.persistDatabase(account)
        }
    }
}
