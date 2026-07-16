import AstrenzaCore
@testable import Astrenza

@MainActor
final class StoreRuntimeInteractionSpy: HomeStoreRuntimeInteracting {
    enum Call: Equatable {
        case start(accountID: String?)
        case provisional(accountID: String, stateAccountID: String?)
        case configure(accountID: String, forceInstall: Bool, contextID: String?)
        case event(relayURL: String, subscriptionID: String, eventID: String, accountID: String?)
        case dependencies(eventID: String, accountID: String?)
        case reset
        #if DEBUG
        case ensureLifecycle(accountID: String)
        case packet(isActive: Bool?, accountID: String?)
        #endif
    }

    let sessionStart = HomeTimelineRuntimeSessionStart(
        didStartProfileUpdates: true,
        didStartRuntimeEvents: false
    )
    let lifecycle = HomeTimelineLifecycleToken(
        accountID: String(repeating: "a", count: 64),
        generation: 9
    )
    var provisionalRelayURLs: [String]? = ["wss://bootstrap.example"]
    var dependencyResult = true
    private(set) var calls: [Call] = []

    func startSession(
        context: HomeTimelineRuntimeInteractionContext
    ) -> HomeTimelineRuntimeSessionStart {
        calls.append(.start(accountID: context.state.account?.pubkey))
        return sessionStart
    }

    func provisionalBootstrapRelayURLs(
        account: NostrAccount,
        state: HomeTimelineRuntimeInteractionState
    ) -> [String]? {
        calls.append(.provisional(
            accountID: account.pubkey,
            stateAccountID: state.account?.pubkey
        ))
        return provisionalRelayURLs
    }

    func configure(
        account: NostrAccount,
        forceInstall: Bool,
        context: HomeTimelineRuntimeInteractionContext
    ) async {
        calls.append(.configure(
            accountID: account.pubkey,
            forceInstall: forceInstall,
            contextID: context.state.account?.pubkey
        ))
    }

    func handleEvent(
        relayURL: String,
        subscriptionID: String,
        event: NostrEvent,
        context: HomeTimelineRuntimeEventContext
    ) async {
        calls.append(.event(
            relayURL: relayURL,
            subscriptionID: subscriptionID,
            eventID: event.id,
            accountID: context.state.account?.pubkey
        ))
    }

    func enqueueDependencies(
        for event: NostrEvent,
        state: HomeTimelineRuntimeDependencyState,
        application: HomeTimelineRuntimeApplicationEffects
    ) async -> Bool {
        calls.append(.dependencies(
            eventID: event.id,
            accountID: state.account?.pubkey
        ))
        application.sourceInstallFailed("coordinator dependency probe")
        return dependencyResult
    }

    func resetSetup() {
        calls.append(.reset)
    }

    #if DEBUG
    func ensureLifecycle(
        accountID: String
    ) -> HomeTimelineLifecycleToken {
        calls.append(.ensureLifecycle(accountID: accountID))
        return lifecycle
    }

    func handlePacket(
        _ packet: NostrRelayRuntimePacket,
        isActive: Bool?,
        context: HomeTimelineRuntimeInteractionContext
    ) async {
        calls.append(.packet(
            isActive: isActive,
            accountID: context.state.account?.pubkey
        ))
    }
    #endif
}

@MainActor
final class StoreBackwardInteractionSpy: HomeStoreBackwardInteracting {
    private(set) var calls: [(groupID: String, accountID: String?)] = []

    func handle(
        _ completion: NostrBackwardREQCompletion,
        context: HomeTimelineBackwardInteractionContext
    ) {
        calls.append((
            groupID: completion.groupID,
            accountID: context.state.account?.pubkey
        ))
    }
}

@MainActor
final class StoreLinkPreviewInteractionSpy:
    HomeStoreLinkPreviewInteracting {
    var result = true
    private(set) var accountIDs: [String?] = []

    func schedule(
        state: HomeTimelineLinkPreviewInteractionState,
        effects: HomeLinkPreviewInteractionEffects
    ) -> Bool {
        accountIDs.append(state.accountID)
        effects.didUpdate()
        return result
    }
}

@MainActor
final class StoreRuntimeContextProviderSpy:
    HomeStoreRuntimeContextProviding {
    enum Read: Equatable {
        case runtimeInteraction
        case runtimeState
        case runtimeEvent
        case dependencyState
        case runtimeApplication
        case backward
        case linkPreview
    }

    let fixture: RuntimeInteractionFixture
    private(set) var reads: [Read] = []
    private(set) var linkPreviewUpdateCount = 0

    init(fixture: RuntimeInteractionFixture) {
        self.fixture = fixture
    }

    func runtimeInteractionContext(
    ) -> HomeTimelineRuntimeInteractionContext {
        reads.append(.runtimeInteraction)
        return fixture.context
    }

    func runtimeEventContext() -> HomeTimelineRuntimeEventContext {
        reads.append(.runtimeEvent)
        return fixture.eventContext
    }

    func runtimeInteractionState() -> HomeTimelineRuntimeInteractionState {
        reads.append(.runtimeState)
        return fixture.context.state
    }

    func runtimeDependencyState() -> HomeTimelineRuntimeDependencyState {
        reads.append(.dependencyState)
        return fixture.dependencyState
    }

    var runtimeApplicationEffects: HomeTimelineRuntimeApplicationEffects {
        reads.append(.runtimeApplication)
        return fixture.probe.runtimeApplicationEffects
    }

    func backwardContext() -> HomeTimelineBackwardInteractionContext {
        reads.append(.backward)
        return HomeTimelineBackwardInteractionContext(
            state: HomeTimelineBackwardInteractionState(
                account: fixture.account,
                resolvedRelays: fixture.relayURLs
            ),
            effects: HomeTimelineBackwardInteractionEffects(
                apply: { _ in },
                resolveDependencies: { _ in false }
            )
        )
    }

    func linkPreviewInteraction(
    ) -> HomeTimelineLinkPreviewStoreInteraction {
        reads.append(.linkPreview)
        return HomeTimelineLinkPreviewStoreInteraction(
            state: HomeTimelineLinkPreviewInteractionState(
                accountID: fixture.account.pubkey,
                resolvedRelays: fixture.relayURLs,
                policy: fixture.policy
            ),
            effects: HomeLinkPreviewInteractionEffects(
                didUpdate: { [weak self] in
                    self?.linkPreviewUpdateCount += 1
                },
                apply: { _ in }
            )
        )
    }
}

@MainActor
struct StoreRuntimeCoordinatorFixture {
    let interactionFixture: RuntimeInteractionFixture
    let runtime: StoreRuntimeInteractionSpy
    let backward: StoreBackwardInteractionSpy
    let linkPreview: StoreLinkPreviewInteractionSpy
    let contexts: StoreRuntimeContextProviderSpy
    let coordinator: HomeStoreRuntimeCoordinator

    init() {
        let interactionFixture = RuntimeInteractionFixture()
        let contexts = StoreRuntimeContextProviderSpy(
            fixture: interactionFixture
        )
        let runtime = StoreRuntimeInteractionSpy()
        let backward = StoreBackwardInteractionSpy()
        let linkPreview = StoreLinkPreviewInteractionSpy()
        self.interactionFixture = interactionFixture
        self.runtime = runtime
        self.backward = backward
        self.linkPreview = linkPreview
        self.contexts = contexts
        self.coordinator = HomeStoreRuntimeCoordinator(
            runtime: runtime,
            backward: backward,
            linkPreview: linkPreview,
            contexts: contexts
        )
    }
}
