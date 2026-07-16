import AstrenzaCore

@MainActor
protocol HomeStoreRuntimeInteracting: AnyObject {
    @discardableResult
    func startSession(
        context: HomeTimelineRuntimeInteractionContext
    ) -> HomeTimelineRuntimeSessionStart

    func provisionalBootstrapRelayURLs(
        account: NostrAccount,
        state: HomeTimelineRuntimeInteractionState
    ) -> [String]?

    func configure(
        account: NostrAccount,
        forceInstall: Bool,
        context: HomeTimelineRuntimeInteractionContext
    ) async

    func handleEvent(
        relayURL: String,
        subscriptionID: String,
        event: NostrEvent,
        context: HomeTimelineRuntimeEventContext
    ) async

    func enqueueDependencies(
        for event: NostrEvent,
        state: HomeTimelineRuntimeDependencyState,
        application: HomeTimelineRuntimeApplicationEffects
    ) async -> Bool

    func resetSetup()

    #if DEBUG
    @discardableResult
    func ensureLifecycle(
        accountID: String
    ) -> HomeTimelineLifecycleToken

    func handlePacket(
        _ packet: NostrRelayRuntimePacket,
        isActive: Bool?,
        context: HomeTimelineRuntimeInteractionContext
    ) async
    #endif
}

extension HomeTimelineRuntimeInteractionWorkflow:
    HomeStoreRuntimeInteracting {}

@MainActor
protocol HomeStoreBackwardInteracting: AnyObject {
    func handle(
        _ completion: NostrBackwardREQCompletion,
        context: HomeTimelineBackwardInteractionContext
    )
}

extension HomeTimelineBackwardInteractionWorkflow:
    HomeStoreBackwardInteracting {}

@MainActor
protocol HomeStoreLinkPreviewInteracting: AnyObject {
    @discardableResult
    func schedule(
        state: HomeTimelineLinkPreviewInteractionState,
        effects: HomeLinkPreviewInteractionEffects
    ) -> Bool
}

extension HomeLinkPreviewInteractionWorkflow:
    HomeStoreLinkPreviewInteracting {}

@MainActor
protocol HomeStoreRuntimeContextProviding: AnyObject {
    func runtimeInteractionContext(
    ) -> HomeTimelineRuntimeInteractionContext
    func runtimeEventContext() -> HomeTimelineRuntimeEventContext
    func runtimeInteractionState() -> HomeTimelineRuntimeInteractionState
    func runtimeDependencyState() -> HomeTimelineRuntimeDependencyState
    var runtimeApplicationEffects: HomeTimelineRuntimeApplicationEffects {
        get
    }
    func backwardContext() -> HomeTimelineBackwardInteractionContext
    func linkPreviewInteraction(
    ) -> HomeTimelineLinkPreviewStoreInteraction
}

extension HomeStoreContextCoordinator: HomeStoreRuntimeContextProviding {}

@MainActor
final class HomeStoreRuntimeCoordinator {
    private let runtime: any HomeStoreRuntimeInteracting
    private let backward: any HomeStoreBackwardInteracting
    private let linkPreview: any HomeStoreLinkPreviewInteracting
    private let contexts: any HomeStoreRuntimeContextProviding

    init(
        runtime: any HomeStoreRuntimeInteracting,
        backward: any HomeStoreBackwardInteracting,
        linkPreview: any HomeStoreLinkPreviewInteracting,
        contexts: any HomeStoreRuntimeContextProviding
    ) {
        self.runtime = runtime
        self.backward = backward
        self.linkPreview = linkPreview
        self.contexts = contexts
    }

    static func live(
        components: HomeTimelineStoreComponents,
        contexts: HomeStoreContextCoordinator
    ) -> HomeStoreRuntimeCoordinator {
        HomeStoreRuntimeCoordinator(
            runtime: components.runtimeInteractionWorkflow,
            backward: components.backwardInteractionWorkflow,
            linkPreview: components.linkPreviewInteractionWorkflow,
            contexts: contexts
        )
    }

    @discardableResult
    func startSession() -> HomeTimelineRuntimeSessionStart {
        runtime.startSession(
            context: contexts.runtimeInteractionContext()
        )
    }

    func provisionalBootstrapRelayURLs(
        account: NostrAccount
    ) -> [String]? {
        runtime.provisionalBootstrapRelayURLs(
            account: account,
            state: contexts.runtimeInteractionState()
        )
    }

    func configure(
        account: NostrAccount,
        forceInstall: Bool
    ) async {
        await runtime.configure(
            account: account,
            forceInstall: forceInstall,
            context: contexts.runtimeInteractionContext()
        )
    }

    func handleEvent(
        relayURL: String,
        subscriptionID: String,
        event: NostrEvent
    ) async {
        await runtime.handleEvent(
            relayURL: relayURL,
            subscriptionID: subscriptionID,
            event: event,
            context: contexts.runtimeEventContext()
        )
    }

    @discardableResult
    func enqueueDependencies(for event: NostrEvent) async -> Bool {
        await runtime.enqueueDependencies(
            for: event,
            state: contexts.runtimeDependencyState(),
            application: contexts.runtimeApplicationEffects
        )
    }

    func handleBackwardCompletion(
        _ completion: NostrBackwardREQCompletion
    ) {
        backward.handle(
            completion,
            context: contexts.backwardContext()
        )
    }

    @discardableResult
    func scheduleLinkPreviewResolution() -> Bool {
        let interaction = contexts.linkPreviewInteraction()
        return linkPreview.schedule(
            state: interaction.state,
            effects: interaction.effects
        )
    }

    func resetSetup() {
        runtime.resetSetup()
    }

    #if DEBUG
    @discardableResult
    func ensureLifecycle(
        accountID: String
    ) -> HomeTimelineLifecycleToken {
        runtime.ensureLifecycle(accountID: accountID)
    }

    func handlePacket(
        _ packet: NostrRelayRuntimePacket,
        isActive: Bool?
    ) async {
        await runtime.handlePacket(
            packet,
            isActive: isActive,
            context: contexts.runtimeInteractionContext()
        )
    }
    #endif
}
