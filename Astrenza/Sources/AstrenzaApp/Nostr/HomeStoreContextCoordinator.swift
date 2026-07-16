import AstrenzaCore

@MainActor
struct HomeStoreComposition {
    let query: HomeStoreQueryCoordinator
    let projection: HomeStoreProjectionCoordinator
    let context: HomeStoreContextCoordinator
    let lifecycle: HomeStoreLifecycleCoordinator
    let featureActions: HomeStoreFeatureActionCoordinator
    let sync: HomeStoreSyncCoordinator
    let state: HomeStoreStateCoordinator
    let runtime: HomeStoreRuntimeCoordinator
    let viewport: HomeStoreViewportCoordinator
    let presentation: HomeStorePresentationCoordinator
    let status: HomeStoreStatusCoordinator

    static func make(
        components: HomeTimelineStoreComponents
    ) -> HomeStoreComposition {
        let query = HomeStoreQueryCoordinator(
            interaction: components.queryInteractionWorkflow
        )
        let projectionViewport = HomeProjectionViewportCoordinator()
        let context = HomeStoreContextCoordinator.live(
            components: components,
            query: query,
            projectionViewport: projectionViewport,
            hasRelayRuntime: components.relayRuntime != nil
        )
        let projection = HomeStoreProjectionCoordinator.live(
            components: components
        )
        return HomeStoreComposition(
            query: query,
            projection: projection,
            context: context,
            lifecycle: HomeStoreLifecycleCoordinator.live(
                components: components,
                projection: projection,
                contexts: context
            ),
            featureActions: HomeStoreFeatureActionCoordinator.live(
                components: components,
                contexts: context
            ),
            sync: HomeStoreSyncCoordinator.live(
                components: components,
                contexts: context
            ),
            state: HomeStoreStateCoordinator.live(
                components: components,
                contexts: context
            ),
            runtime: HomeStoreRuntimeCoordinator.live(
                components: components,
                contexts: context
            ),
            viewport: HomeStoreViewportCoordinator.live(
                components: components,
                projection: projectionViewport,
                contexts: context
            ),
            presentation: HomeStorePresentationCoordinator.live(
                components: components
            ),
            status: HomeStoreStatusCoordinator.live(
                components: components
            )
        )
    }
}

@MainActor
protocol HomeStoreContextApplicationTarget:
    HomeStoreApplicationEffectTarget,
    HomeLoadApplicationEffectTarget,
    HomeAccountApplicationEffectTarget,
    HomeViewportApplicationEffectTarget {}

struct HomeStoreContextApplications: Sendable {
    let store: HomeTimelineStoreApplicationEffects
    let load: HomeTimelineLoadApplicationEffects
    let account: HomeTimelineAccountApplicationEffects
    let viewport: HomeTimelineViewportApplicationEffects
}

@MainActor
extension HomeStoreContextApplications {
    static func make(
        target: any HomeStoreContextApplicationTarget
    ) -> Self {
        HomeStoreContextApplications(
            store: HomeStoreApplicationEffectsFactory.make(target: target),
            load: HomeLoadApplicationEffectsFactory.make(target: target),
            account: HomeAccountApplicationEffectsFactory.make(target: target),
            viewport: HomeViewportApplicationEffectsFactory.make(
                target: target
            )
        )
    }
}

@MainActor
final class HomeStoreContextCoordinator {
    private struct Factories {
        let load: HomeLoadContextFactory
        let runtime: HomeRuntimeContextFactory
        let state: HomeStateContextFactory
        let feature: HomeFeatureContextFactory
        let account: HomeAccountContextFactory
        let viewport: HomeViewportContextFactory
        let runtimeApplication: HomeTimelineRuntimeApplicationEffects
    }

    private let source: any HomeStoreContextSourcing
    private var factories: Factories?

    init(source: any HomeStoreContextSourcing) {
        self.source = source
    }

    static func live(
        components: HomeTimelineStoreComponents,
        query: HomeStoreQueryCoordinator,
        projectionViewport: HomeProjectionViewportCoordinator,
        hasRelayRuntime: Bool
    ) -> HomeStoreContextCoordinator {
        HomeStoreContextCoordinator(
            source: HomeStoreContextSource(
                components: components,
                query: query,
                projectionViewport: projectionViewport,
                hasRelayRuntime: hasRelayRuntime
            )
        )
    }

    func bind(
        applications: HomeStoreContextApplications,
        readBoundaryTarget: any HomeStoreReadBoundaryTarget
    ) {
        source.bindReadBoundary(target: readBoundaryTarget)
        factories = makeFactories(applications: applications)
    }

    private func makeFactories(
        applications: HomeStoreContextApplications
    ) -> Factories {
        let source = source
        let state = HomeStateContextFactory(
            environment: HomeStateContextEnvironment(
                projection: { source.stateProjection() },
                applications: applications.store
            )
        )
        let runtimeApplication = source.runtimeApplicationEffects(
            context: state.context()
        )
        let load = Self.makeLoadFactory(
            source: source,
            applications: applications.load
        )
        let runtime = Self.makeRuntimeFactory(
            source: source,
            runtimeApplication: runtimeApplication,
            applications: applications.store
        )
        let feature = Self.makeFeatureFactory(
            source: source,
            runtimeApplication: runtimeApplication,
            applications: applications.store
        )
        let account = Self.makeAccountFactory(
            source: source,
            state: state,
            load: load,
            applications: applications.account
        )
        let viewport = Self.makeViewportFactory(
            source: source,
            applications: applications.viewport
        )
        return Factories(
            load: load,
            runtime: runtime,
            state: state,
            feature: feature,
            account: account,
            viewport: viewport,
            runtimeApplication: runtimeApplication
        )
    }

    func loadContext() -> HomeTimelineLoadInteractionContext {
        requiredFactories.load.context()
    }

    func runtimeInteractionContext(
    ) -> HomeTimelineRuntimeInteractionContext {
        requiredFactories.runtime.interactionContext()
    }

    func runtimeEventContext() -> HomeTimelineRuntimeEventContext {
        requiredFactories.runtime.eventContext()
    }

    func runtimeInteractionState() -> HomeTimelineRuntimeInteractionState {
        requiredFactories.runtime.interactionState()
    }

    func runtimeDependencyState() -> HomeTimelineRuntimeDependencyState {
        requiredFactories.runtime.dependencyState()
    }

    var runtimeApplicationEffects: HomeTimelineRuntimeApplicationEffects {
        requiredFactories.runtimeApplication
    }

    func stateContext() -> HomeTimelineStateInteractionContext {
        requiredFactories.state.context()
    }

    func filterContext() -> HomeFilterInteractionContext {
        requiredFactories.feature.filterContext()
    }

    func syncContext() -> HomeTimelineSyncInteractionContext {
        requiredFactories.feature.syncContext()
    }

    func localMutationContext() -> HomeLocalMutationInteractionContext {
        requiredFactories.feature.localMutationContext()
    }

    func gapBackfillContext() -> HomeGapBackfillInteractionContext {
        requiredFactories.feature.gapBackfillContext()
    }

    func publishContext(
        account: NostrAccount
    ) -> HomeTimelinePublishInteractionContext {
        requiredFactories.feature.publishContext(account: account)
    }

    func backwardContext() -> HomeTimelineBackwardInteractionContext {
        requiredFactories.feature.backwardContext()
    }

    func linkPreviewInteraction(
    ) -> HomeTimelineLinkPreviewStoreInteraction {
        requiredFactories.feature.linkPreviewInteraction()
    }

    func accountStartContext() -> HomeAccountStartInteractionContext {
        requiredFactories.account.startContext()
    }

    func accountResetContext() -> HomeAccountResetInteractionContext {
        requiredFactories.account.resetContext()
    }

    func viewportContext() -> HomeTimelineViewportInteractionContext {
        requiredFactories.viewport.context()
    }

    func scheduleReadBoundarySave() {
        source.scheduleReadBoundarySave()
    }

    private var requiredFactories: Factories {
        guard let factories else {
            preconditionFailure("Home Store contexts must be bound before use")
        }
        return factories
    }

    private static func makeLoadFactory(
        source: any HomeStoreContextSourcing,
        applications: HomeTimelineLoadApplicationEffects
    ) -> HomeLoadContextFactory {
        HomeLoadContextFactory(
            environment: HomeLoadContextEnvironment(
                snapshot: { source.loadSnapshot() },
                providers: HomeTimelineLoadEnvironment(
                    hasResolvedRelays: { source.hasResolvedRelays() },
                    currentState: { source.loaderState() },
                    localBackfillEvents: { account, current in
                        source.localBackfillEvents(
                            account: account,
                            current: current
                        )
                    },
                    resolvedRelays: { source.resolvedRelays() }
                ),
                applications: applications
            )
        )
    }

    private static func makeAccountFactory(
        source: any HomeStoreContextSourcing,
        state: HomeStateContextFactory,
        load: HomeLoadContextFactory,
        applications: HomeTimelineAccountApplicationEffects
    ) -> HomeAccountContextFactory {
        HomeAccountContextFactory(
            environment: HomeAccountLifecycleEnvironment(
                snapshot: { source.accountSnapshot() },
                readBoundaryWrite: { source.readBoundaryWrite() },
                restoreCachedSnapshot: { account in
                    await source.restoreCachedSnapshot(
                        account: account,
                        context: state.context()
                    )
                },
                restoredViewport: { accountID in
                    source.restoredViewport(accountID: accountID)
                },
                waitForCachedPresentation: {
                    await source.waitForCachedPresentation()
                },
                restoreCachedReadState: { account in
                    await source.restoreCachedReadState(account: account)
                },
                load: { request in
                    await source.load(request, context: load.context())
                },
                applications: applications
            )
        )
    }

    private static func makeRuntimeFactory(
        source: any HomeStoreContextSourcing,
        runtimeApplication: HomeTimelineRuntimeApplicationEffects,
        applications: HomeTimelineStoreApplicationEffects
    ) -> HomeRuntimeContextFactory {
        HomeRuntimeContextFactory(
            environment: HomeRuntimeContextEnvironment(
                snapshot: { source.runtimeSnapshot() },
                isCurrentFeedContext: { context in
                    source.isCurrentFeedContext(context)
                },
                runtimeApplication: runtimeApplication,
                applications: applications
            )
        )
    }

    private static func makeFeatureFactory(
        source: any HomeStoreContextSourcing,
        runtimeApplication: HomeTimelineRuntimeApplicationEffects,
        applications: HomeTimelineStoreApplicationEffects
    ) -> HomeFeatureContextFactory {
        HomeFeatureContextFactory(
            environment: HomeFeatureInteractionEnvironment(
                snapshot: { source.featureSnapshot() },
                applications: applications,
                resolveBackwardDependencies: { request in
                    await source.resolveBackwardDependencies(
                        request,
                        application: runtimeApplication
                    )
                },
                didUpdateLinkPreview: {
                    applications.invalidateListEntries()
                    applications.scheduleMaterialization(nil, nil)
                }
            )
        )
    }

    private static func makeViewportFactory(
        source: any HomeStoreContextSourcing,
        applications: HomeTimelineViewportApplicationEffects
    ) -> HomeViewportContextFactory {
        HomeViewportContextFactory(
            environment: HomeViewportContextEnvironment(
                snapshot: { source.viewportSnapshot() },
                applications: applications
            )
        )
    }
}
