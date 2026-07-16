import AstrenzaCore

@MainActor
protocol HomeStoreAccountStarting: AnyObject {
    func start(
        account: NostrAccount,
        context: HomeAccountStartInteractionContext
    )
}

extension HomeAccountStartInteractionWorkflow: HomeStoreAccountStarting {}

@MainActor
protocol HomeStoreAccountResetting: AnyObject {
    func reset(context: HomeAccountResetInteractionContext)
}

extension HomeAccountResetInteractionWorkflow: HomeStoreAccountResetting {}

@MainActor
protocol HomeStoreTimelineLoading: AnyObject {
    func refreshLatest(
        account: NostrAccount,
        lifecycle: HomeTimelineLifecycleToken,
        context: HomeTimelineLoadInteractionContext
    ) async

    func loadOlder(
        account: NostrAccount,
        lifecycle: HomeTimelineLifecycleToken,
        context: HomeTimelineLoadInteractionContext
    ) async
}

extension HomeTimelineLoadInteractionWorkflow: HomeStoreTimelineLoading {}

@MainActor
protocol HomeStoreMaterializationCancelling: AnyObject {
    func cancelMaterialization()
}

extension HomeStoreProjectionCoordinator:
    HomeStoreMaterializationCancelling {}

@MainActor
protocol HomeStoreLifecycleContextProviding: AnyObject {
    func accountStartContext() -> HomeAccountStartInteractionContext
    func accountResetContext() -> HomeAccountResetInteractionContext
    func loadContext() -> HomeTimelineLoadInteractionContext
}

extension HomeStoreContextCoordinator:
    HomeStoreLifecycleContextProviding {}

@MainActor
final class HomeStoreLifecycleCoordinator {
    private let accountStart: any HomeStoreAccountStarting
    private let accountReset: any HomeStoreAccountResetting
    private let load: any HomeStoreTimelineLoading
    private let materialization: any HomeStoreMaterializationCancelling
    private let contexts: any HomeStoreLifecycleContextProviding

    init(
        accountStart: any HomeStoreAccountStarting,
        accountReset: any HomeStoreAccountResetting,
        load: any HomeStoreTimelineLoading,
        materialization: any HomeStoreMaterializationCancelling,
        contexts: any HomeStoreLifecycleContextProviding
    ) {
        self.accountStart = accountStart
        self.accountReset = accountReset
        self.load = load
        self.materialization = materialization
        self.contexts = contexts
    }

    static func live(
        components: HomeTimelineStoreComponents,
        projection: HomeStoreProjectionCoordinator,
        contexts: HomeStoreContextCoordinator
    ) -> HomeStoreLifecycleCoordinator {
        HomeStoreLifecycleCoordinator(
            accountStart: components.accountStartInteractionWorkflow,
            accountReset: components.accountResetInteractionWorkflow,
            load: components.loadInteractionWorkflow,
            materialization: projection,
            contexts: contexts
        )
    }

    func start(account: NostrAccount) {
        accountStart.start(
            account: account,
            context: contexts.accountStartContext()
        )
    }

    func cancel() {
        materialization.cancelMaterialization()
        accountReset.reset(context: contexts.accountResetContext())
    }

    func restart(account: NostrAccount) {
        cancel()
        start(account: account)
    }

    func refreshLatest(
        account: NostrAccount,
        lifecycle: HomeTimelineLifecycleToken
    ) async {
        await load.refreshLatest(
            account: account,
            lifecycle: lifecycle,
            context: contexts.loadContext()
        )
    }

    func loadOlder(
        account: NostrAccount,
        lifecycle: HomeTimelineLifecycleToken
    ) async {
        await load.loadOlder(
            account: account,
            lifecycle: lifecycle,
            context: contexts.loadContext()
        )
    }
}
