import AstrenzaCore

struct HomeTimelineRuntimeInteractionState: Equatable, Sendable {
    let account: NostrAccount?
    let profileRelayURLs: [String]
    let resolvedRelays: [String]
    let policy: NostrSyncPolicy
    let hasRelayRuntime: Bool
    let isTerminating: Bool
}

struct HomeTimelineRuntimeStoreEnvironment: Sendable {
    typealias PacketContextProvider = @MainActor @Sendable (
        _ isActive: Bool?
    ) -> HomeTimelineRuntimePacketContext?
    typealias AccountValidity = @MainActor @Sendable (
        _ accountID: String
    ) -> Bool

    let packetContext: PacketContextProvider
    let isAccountCurrent: AccountValidity
}

enum HomeTimelineRuntimeStoreAction: Equatable, Sendable {
    case setRealtime(Bool)
    case applyRelayStatusTransition(HomeTimelineRelayStatusTransition?)
    case handleBackwardCompletion(NostrBackwardREQCompletion)
    case invalidateListEntries
    case scheduleMaterialization
    case scheduleLinkPreviewResolution
}

enum HomeTimelineRuntimeStoreAsyncAction: Equatable, Sendable {
    case handleEvent(
        relayURL: String,
        subscriptionID: String,
        event: NostrEvent
    )
}

struct HomeTimelineRuntimeInteractionEffects: Sendable {
    typealias ApplicationEffect = @MainActor @Sendable (
        _ application: HomeTimelineRuntimeStoreAction
    ) -> Void
    typealias AsyncApplicationEffect = @MainActor @Sendable (
        _ application: HomeTimelineRuntimeStoreAsyncAction
    ) async -> Void

    let environment: HomeTimelineRuntimeStoreEnvironment
    let runtimeApplication: HomeTimelineRuntimeApplicationEffects
    let apply: ApplicationEffect
    let perform: AsyncApplicationEffect
}

struct HomeTimelineRuntimeInteractionContext: Sendable {
    let state: HomeTimelineRuntimeInteractionState
    let effects: HomeTimelineRuntimeInteractionEffects
}

struct HomeTimelineRuntimeEventInteractionState: Equatable, Sendable {
    let account: NostrAccount?
    let resolvedRelays: [String]
    let hasRelayRuntime: Bool
    let receivedWhileRealtime: Bool
}

struct HomeTimelineRuntimeEventEnvironment: Sendable {
    let presentationState:
        HomeTimelineRuntimeEventEffects.PresentationStateProvider
    let isAccountCurrent: HomeTimelineRuntimeEventEffects.AccountValidity
}

struct HomeTimelineRuntimeEventStoreEffects: Sendable {
    let environment: HomeTimelineRuntimeEventEnvironment
    let runtimeApplication: HomeTimelineRuntimeApplicationEffects
    let apply: HomeTimelineRuntimeInteractionEffects.ApplicationEffect
}

struct HomeTimelineRuntimeEventContext: Sendable {
    let state: HomeTimelineRuntimeEventInteractionState
    let effects: HomeTimelineRuntimeEventStoreEffects
}

struct HomeTimelineRuntimeDependencyState: Equatable, Sendable {
    let account: NostrAccount?
    let hasRelayRuntime: Bool
}
