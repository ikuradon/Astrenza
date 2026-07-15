import AstrenzaCore
import Foundation

struct HomeTimelineRuntimeInteractionState: Equatable, Sendable {
    let account: NostrAccount?
    let resolvedRelays: [String]
    let bootstrapRelayURLs: [String]
    let policy: NostrSyncPolicy
    let hasRelayRuntime: Bool
    let isTerminating: Bool
}

struct HomeTimelineRuntimeRelayPlanner: Sendable {
    private let runtimeRelayLimit: Int

    init(runtimeRelayLimit: Int = 10) {
        self.runtimeRelayLimit = max(0, runtimeRelayLimit)
    }

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
        Array(
            deduplicatedRelayURLs(
                normalizedRelayURLs(
                    resolvedRelayURLs +
                        account.discoveryRelays +
                        bootstrapRelayURLs
                )
            )
            .prefix(runtimeRelayLimit)
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
        relayURLs.compactMap { rawValue in
            var value = rawValue.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            if value.hasPrefix("https://") {
                value = "wss://" + value.dropFirst("https://".count)
            } else if value.hasPrefix("http://") {
                value = "ws://" + value.dropFirst("http://".count)
            } else if !value.hasPrefix("wss://") &&
                        !value.hasPrefix("ws://") {
                value = "wss://\(value)"
            }
            guard let url = URL(string: value),
                  url.scheme == "wss" || url.scheme == "ws",
                  url.host != nil
            else { return nil }
            return value
        }
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
    let policy: NostrSyncPolicy
    let hasRelayRuntime: Bool
    let isTerminating: Bool
    let isRuntimeActive: Bool
    let isRealtime: Bool
    let hasRestoreProjectionAnchor: Bool
    let isTimelineAtNewestWindow: Bool
    let hasPendingEvents: Bool
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
