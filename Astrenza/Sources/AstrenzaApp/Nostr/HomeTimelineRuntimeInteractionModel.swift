import AstrenzaCore
import Foundation

struct HomeTimelineRuntimeInteractionState: Equatable, Sendable {
    let account: NostrAccount?
    let resolvedRelays: [String]
    let bootstrapRelayURLs: [String]
    let profileEvents: [NostrEvent]
    let policy: NostrSyncPolicy
    let hasRelayRuntime: Bool
    let isTerminating: Bool

    init(
        account: NostrAccount?,
        resolvedRelays: [String],
        bootstrapRelayURLs: [String],
        profileEvents: [NostrEvent] = [],
        policy: NostrSyncPolicy,
        hasRelayRuntime: Bool,
        isTerminating: Bool
    ) {
        self.account = account
        self.resolvedRelays = resolvedRelays
        self.bootstrapRelayURLs = bootstrapRelayURLs
        self.profileEvents = profileEvents
        self.policy = policy
        self.hasRelayRuntime = hasRelayRuntime
        self.isTerminating = isTerminating
    }
}

struct HomeTimelineRuntimeRelayPlanner: Sendable {
    func sessionRequest(
        state: HomeTimelineRuntimeInteractionState
    ) -> HomeTimelineRuntimeSessionRequest {
        HomeTimelineRuntimeSessionRequest(
            account: state.account,
            profileRelayURLs: state.account.map {
                runtimeRelayURLs(
                    account: $0,
                    resolvedRelayURLs: state.resolvedRelays,
                    bootstrapRelayURLs: state.bootstrapRelayURLs
                )
            } ?? [],
            profileEvents: state.profileEvents,
            hasRelayRuntime: state.hasRelayRuntime,
            isTerminating: state.isTerminating
        )
    }

    func setupRequest(
        account: NostrAccount,
        forceInstall: Bool,
        state: HomeTimelineRuntimeInteractionState
    ) -> HomeTimelineRuntimeSetupRequest {
        HomeTimelineRuntimeSetupRequest(
            account: account,
            defaultRelayURLs: runtimeRelayURLs(
                account: account,
                resolvedRelayURLs: state.resolvedRelays,
                bootstrapRelayURLs: state.bootstrapRelayURLs
            ),
            policy: state.policy,
            hasRelayRuntime: state.hasRelayRuntime,
            isTerminating: state.isTerminating,
            forceInstall: forceInstall
        )
    }

    func runtimeRelayURLs(
        account: NostrAccount,
        resolvedRelayURLs: [String],
        bootstrapRelayURLs: [String]
    ) -> [String] {
        deduplicatedRelayURLs(
            normalizedRelayURLs(
                resolvedRelayURLs +
                    account.discoveryRelays +
                    bootstrapRelayURLs
            )
        )
    }

    func provisionalBootstrapRelayURLs(
        account: NostrAccount,
        resolvedRelayURLs: [String],
        bootstrapRelayURLs: [String],
        hasRelayRuntime: Bool
    ) -> [String]? {
        guard hasRelayRuntime, resolvedRelayURLs.isEmpty else { return nil }
        let relayURLs = deduplicatedRelayURLs(
            normalizedRelayURLs(
                account.discoveryRelays + bootstrapRelayURLs
            )
        )
        return relayURLs.isEmpty ? nil : relayURLs
    }

    private func normalizedRelayURLs(_ relayURLs: [String]) -> [String] {
        NostrRelayURL.normalizedStrings(relayURLs, mode: .userFacing)
    }

    private func deduplicatedRelayURLs(_ relayURLs: [String]) -> [String] {
        var seen = Set<String>()
        return relayURLs.filter { seen.insert($0).inserted }
    }
}

struct HomeTimelineRuntimeStoreSnapshot: Equatable, Sendable {
    let account: NostrAccount?
    let resolvedRelays: [String]
    let bootstrapRelayURLs: [String]
    let profileEvents: [NostrEvent]
    let policy: NostrSyncPolicy
    let hasRelayRuntime: Bool
    let isTerminating: Bool
    let isRuntimeActive: Bool
    let isRealtime: Bool
    let hasRestoreProjectionAnchor: Bool
    let isTimelineAtNewestWindow: Bool
    let hasPendingEvents: Bool

    init(
        account: NostrAccount?,
        resolvedRelays: [String],
        bootstrapRelayURLs: [String],
        profileEvents: [NostrEvent] = [],
        policy: NostrSyncPolicy,
        hasRelayRuntime: Bool,
        isTerminating: Bool,
        isRuntimeActive: Bool,
        isRealtime: Bool,
        hasRestoreProjectionAnchor: Bool,
        isTimelineAtNewestWindow: Bool,
        hasPendingEvents: Bool
    ) {
        self.account = account
        self.resolvedRelays = resolvedRelays
        self.bootstrapRelayURLs = bootstrapRelayURLs
        self.profileEvents = profileEvents
        self.policy = policy
        self.hasRelayRuntime = hasRelayRuntime
        self.isTerminating = isTerminating
        self.isRuntimeActive = isRuntimeActive
        self.isRealtime = isRealtime
        self.hasRestoreProjectionAnchor = hasRestoreProjectionAnchor
        self.isTimelineAtNewestWindow = isTimelineAtNewestWindow
        self.hasPendingEvents = hasPendingEvents
    }

    static var empty: Self {
        HomeTimelineRuntimeStoreSnapshot(
            account: nil,
            resolvedRelays: [],
            bootstrapRelayURLs: [],
            profileEvents: [],
            policy: .default(),
            hasRelayRuntime: false,
            isTerminating: false,
            isRuntimeActive: false,
            isRealtime: false,
            hasRestoreProjectionAnchor: false,
            isTimelineAtNewestWindow: false,
            hasPendingEvents: false
        )
    }
}

@MainActor
struct HomeTimelineRuntimeContextProjector {
    func interactionState(
        from snapshot: HomeTimelineRuntimeStoreSnapshot
    ) -> HomeTimelineRuntimeInteractionState {
        HomeTimelineRuntimeInteractionState(
            account: snapshot.account,
            resolvedRelays: snapshot.resolvedRelays,
            bootstrapRelayURLs: snapshot.bootstrapRelayURLs,
            profileEvents: snapshot.profileEvents,
            policy: snapshot.policy,
            hasRelayRuntime: snapshot.hasRelayRuntime,
            isTerminating: snapshot.isTerminating
        )
    }

    func packetContext(
        from snapshot: HomeTimelineRuntimeStoreSnapshot,
        isActive: Bool?,
        isCurrentFeedContext: @escaping @MainActor (
            HomeFeedRuntimeContext
        ) -> Bool
    ) -> HomeTimelineRuntimePacketContext {
        HomeTimelineRuntimePacketContext(
            isActive: isActive ?? snapshot.isRuntimeActive,
            accountID: snapshot.account?.pubkey,
            resolvedRelays: snapshot.resolvedRelays,
            isCurrentFeedContext: isCurrentFeedContext
        )
    }

    func eventState(
        from snapshot: HomeTimelineRuntimeStoreSnapshot
    ) -> HomeTimelineRuntimeEventInteractionState {
        HomeTimelineRuntimeEventInteractionState(
            account: snapshot.account,
            resolvedRelays: snapshot.resolvedRelays,
            hasRelayRuntime: snapshot.hasRelayRuntime,
            receivedWhileRealtime: snapshot.isRealtime
        )
    }

    func eventPresentationState(
        from snapshot: HomeTimelineRuntimeStoreSnapshot,
        receivedWhileRealtime: Bool
    ) -> HomeTimelineRuntimeEventPresentationState {
        HomeTimelineRuntimeEventPresentationState(
            receivedWhileRealtime: receivedWhileRealtime,
            hasRestoreProjectionAnchor:
                snapshot.hasRestoreProjectionAnchor,
            isTimelineAtNewestWindow:
                snapshot.isTimelineAtNewestWindow,
            hasPendingEvents: snapshot.hasPendingEvents
        )
    }

    func dependencyState(
        from snapshot: HomeTimelineRuntimeStoreSnapshot
    ) -> HomeTimelineRuntimeDependencyState {
        HomeTimelineRuntimeDependencyState(
            account: snapshot.account,
            hasRelayRuntime: snapshot.hasRelayRuntime
        )
    }

    func isAccountCurrent(
        _ accountID: String,
        in snapshot: HomeTimelineRuntimeStoreSnapshot
    ) -> Bool {
        snapshot.account?.pubkey == accountID
    }
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
    case publishProfileMetadataChange
    case invalidateListEntries
    case scheduleMaterialization
    case scheduleLinkPreviewResolution
}

struct HomeTimelineRuntimeEventEnvelope: Equatable, Sendable {
    let relayURL: String
    let subscriptionID: String
    let event: NostrEvent
}

enum HomeTimelineRuntimeStoreAsyncAction: Equatable, Sendable {
    case handleEvent(
        relayURL: String,
        subscriptionID: String,
        event: NostrEvent
    )
    case handleEvents([HomeTimelineRuntimeEventEnvelope])
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
    let waitForPendingPresentation:
        HomeTimelineRuntimePacketHandlers.PresentationSettlement
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
