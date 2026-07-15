import AstrenzaCore

@MainActor
protocol HomeTimelineRuntimeRouting: AnyObject {
    @discardableResult
    func startSession(
        _ request: HomeTimelineRuntimeSessionRequest,
        effects: HomeTimelineRuntimeSessionEffects
    ) -> HomeTimelineRuntimeSessionStart

    func configure(
        _ request: HomeTimelineRuntimeSetupRequest,
        effects: HomeTimelineRuntimeSetupEffects
    ) async

    func resetSetup()

    func handlePacket(
        _ packet: NostrRelayRuntimePacket,
        effects: HomeTimelineRuntimePacketEffects
    ) async
}

extension HomeTimelineRuntimeWorkflow: HomeTimelineRuntimeRouting {}

@MainActor
protocol HomeTimelineRuntimeEventRouting: AnyObject {
    func handle(
        _ input: HomeTimelineRuntimeEventInput,
        effects: HomeTimelineRuntimeEventEffects
    ) async

    func rememberLatestMetadataEvent(
        _ event: NostrEvent,
        consultEventStore: Bool,
        effects: HomeTimelineRuntimeApplicationEffects
    ) -> NostrEvent

    func resolveNIP05IfNeeded(
        for metadataEvent: NostrEvent,
        context: HomeTimelineRuntimeEventApplicationContext,
        effects: HomeTimelineRuntimeApplicationEffects
    )

    func enqueueDependencies(
        for event: NostrEvent,
        context: HomeTimelineRuntimeEventApplicationContext,
        effects: HomeTimelineRuntimeApplicationEffects
    ) async -> Bool
}

extension HomeTimelineRuntimeEventWorkflow: HomeTimelineRuntimeEventRouting {}

@MainActor
protocol HomeTimelineRuntimeLifecycleTracking: AnyObject {
    func token(for accountID: String) -> HomeTimelineLifecycleToken?

    #if DEBUG
    func begin(accountID: String) -> HomeTimelineLifecycleToken
    #endif
}

extension HomeTimelineLifecycleCoordinator:
    HomeTimelineRuntimeLifecycleTracking {}

struct HomeTimelineRuntimeInteractionState: Equatable, Sendable {
    let account: NostrAccount?
    let profileRelayURLs: [String]
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
    case recordSetupDiagnostic(HomeTimelineRuntimeSetupDiagnostic)
    case recordEventDiagnostic(HomeTimelineRuntimeEventDiagnostic)
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

@MainActor
final class HomeTimelineRuntimeInteractionWorkflow {
    private let runtime: any HomeTimelineRuntimeRouting
    private let events: any HomeTimelineRuntimeEventRouting
    private let lifecycle: any HomeTimelineRuntimeLifecycleTracking

    init(
        runtime: any HomeTimelineRuntimeRouting,
        events: any HomeTimelineRuntimeEventRouting,
        lifecycle: any HomeTimelineRuntimeLifecycleTracking
    ) {
        self.runtime = runtime
        self.events = events
        self.lifecycle = lifecycle
    }

    @discardableResult
    func startSession(
        context: HomeTimelineRuntimeInteractionContext
    ) -> HomeTimelineRuntimeSessionStart {
        runtime.startSession(
            HomeTimelineRuntimeSessionRequest(
                account: context.state.account,
                profileRelayURLs: context.state.profileRelayURLs,
                hasRelayRuntime: context.state.hasRelayRuntime,
                isTerminating: context.state.isTerminating
            ),
            effects: sessionEffects(for: context.effects)
        )
    }

    func configure(
        account: NostrAccount,
        defaultRelayURLs: [String],
        forceInstall: Bool,
        context: HomeTimelineRuntimeInteractionContext
    ) async {
        await runtime.configure(
            HomeTimelineRuntimeSetupRequest(
                account: account,
                defaultRelayURLs: defaultRelayURLs,
                policy: context.state.policy,
                hasRelayRuntime: context.state.hasRelayRuntime,
                isTerminating: context.state.isTerminating,
                forceInstall: forceInstall
            ),
            effects: setupEffects(for: context.effects)
        )
    }

    func resetSetup() {
        runtime.resetSetup()
    }

    func handlePacket(
        _ packet: NostrRelayRuntimePacket,
        isActive: Bool? = nil,
        context: HomeTimelineRuntimeInteractionContext
    ) async {
        await runtime.handlePacket(
            packet,
            effects: packetEffects(
                isActive: isActive,
                effects: context.effects
            )
        )
    }

    func handleEvent(
        relayURL: String,
        subscriptionID: String,
        event: NostrEvent,
        context: HomeTimelineRuntimeEventContext
    ) async {
        await events.handle(
            HomeTimelineRuntimeEventInput(
                relayURL: relayURL,
                subscriptionID: subscriptionID,
                event: event,
                account: context.state.account,
                hasRelayRuntime: context.state.hasRelayRuntime,
                receivedWhileRealtime: context.state.receivedWhileRealtime
            ),
            effects: eventEffects(for: context.effects)
        )
    }

    @discardableResult
    func rememberLatestMetadataEvent(
        _ event: NostrEvent,
        consultEventStore: Bool,
        application: HomeTimelineRuntimeApplicationEffects
    ) -> NostrEvent {
        events.rememberLatestMetadataEvent(
            event,
            consultEventStore: consultEventStore,
            effects: application
        )
    }

    func resolveNIP05IfNeeded(
        for metadataEvent: NostrEvent,
        state: HomeTimelineRuntimeDependencyState,
        application: HomeTimelineRuntimeApplicationEffects
    ) {
        guard let context = dependencyContext(for: state) else { return }
        events.resolveNIP05IfNeeded(
            for: metadataEvent,
            context: context,
            effects: application
        )
    }

    func enqueueDependencies(
        for event: NostrEvent,
        state: HomeTimelineRuntimeDependencyState,
        application: HomeTimelineRuntimeApplicationEffects
    ) async -> Bool {
        guard let context = dependencyContext(for: state) else { return false }
        return await enqueueDependencies(
            for: event,
            context: context,
            application: application
        )
    }

    func enqueueDependencies(
        for event: NostrEvent,
        context: HomeTimelineRuntimeEventApplicationContext,
        application: HomeTimelineRuntimeApplicationEffects
    ) async -> Bool {
        await events.enqueueDependencies(
            for: event,
            context: context,
            effects: application
        )
    }

    private func dependencyContext(
        for state: HomeTimelineRuntimeDependencyState
    ) -> HomeTimelineRuntimeEventApplicationContext? {
        guard let account = state.account,
              let lifecycle = lifecycle.token(for: account.pubkey)
        else { return nil }
        return HomeTimelineRuntimeEventApplicationContext(
            account: account,
            lifecycle: lifecycle,
            hasRelayRuntime: state.hasRelayRuntime
        )
    }

    private func sessionEffects(
        for effects: HomeTimelineRuntimeInteractionEffects
    ) -> HomeTimelineRuntimeSessionEffects {
        HomeTimelineRuntimeSessionEffects(
            isAccountCurrent: effects.environment.isAccountCurrent,
            application: effects.runtimeApplication,
            packet: packetEffects(isActive: nil, effects: effects),
            invalidateListEntries: {
                effects.apply(.invalidateListEntries)
            },
            scheduleMaterialization: {
                effects.apply(.scheduleMaterialization)
            }
        )
    }

    private func packetEffects(
        isActive: Bool?,
        effects: HomeTimelineRuntimeInteractionEffects
    ) -> HomeTimelineRuntimePacketEffects {
        HomeTimelineRuntimePacketEffects(
            context: {
                effects.environment.packetContext(isActive)
            },
            setRealtime: { isRealtime in
                effects.apply(.setRealtime(isRealtime))
            },
            applyRelayStatusTransition: { transition in
                effects.apply(.applyRelayStatusTransition(transition))
            },
            handleEvent: { relayURL, subscriptionID, event in
                await effects.perform(.handleEvent(
                    relayURL: relayURL,
                    subscriptionID: subscriptionID,
                    event: event
                ))
            },
            handleBackwardCompletion: { completion in
                effects.apply(.handleBackwardCompletion(completion))
            }
        )
    }

    private func setupEffects(
        for effects: HomeTimelineRuntimeInteractionEffects
    ) -> HomeTimelineRuntimeSetupEffects {
        HomeTimelineRuntimeSetupEffects(
            setRealtime: { isRealtime in
                effects.apply(.setRealtime(isRealtime))
            },
            recordDiagnostic: { diagnostic in
                effects.apply(.recordSetupDiagnostic(diagnostic))
            }
        )
    }

    private func eventEffects(
        for effects: HomeTimelineRuntimeEventStoreEffects
    ) -> HomeTimelineRuntimeEventEffects {
        HomeTimelineRuntimeEventEffects(
            presentationState: effects.environment.presentationState,
            isAccountCurrent: effects.environment.isAccountCurrent,
            application: effects.runtimeApplication,
            recordDiagnostic: { diagnostic in
                effects.apply(.recordEventDiagnostic(diagnostic))
            },
            scheduleLinkPreviewResolution: {
                effects.apply(.scheduleLinkPreviewResolution)
            }
        )
    }
}

#if DEBUG
extension HomeTimelineRuntimeInteractionWorkflow {
    @discardableResult
    func ensureLifecycle(accountID: String) -> HomeTimelineLifecycleToken {
        if let token = lifecycle.token(for: accountID) {
            return token
        }
        return lifecycle.begin(accountID: accountID)
    }
}
#endif
