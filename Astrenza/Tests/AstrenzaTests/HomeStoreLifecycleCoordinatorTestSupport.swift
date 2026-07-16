import AstrenzaCore
@testable import Astrenza

@MainActor
final class StoreLifecycleOrderProbe {
    enum Step: Equatable {
        case cancelMaterialization
        case resetAccount
    }

    private(set) var steps: [Step] = []

    func record(_ step: Step) {
        steps.append(step)
    }
}

@MainActor
final class StoreAccountStartSpy: HomeStoreAccountStarting {
    struct Call: Equatable {
        let accountID: String
        let hasRelayRuntime: Bool
    }

    private(set) var calls: [Call] = []

    func start(
        account: NostrAccount,
        context: HomeAccountStartInteractionContext
    ) {
        calls.append(Call(
            accountID: account.pubkey,
            hasRelayRuntime: context.state.hasRelayRuntime
        ))
    }
}

@MainActor
final class StoreAccountResetSpy: HomeStoreAccountResetting {
    struct Call: Equatable {
        let resolvedRelays: [String]
        let readBoundaryScopeID: String?
    }

    private let order: StoreLifecycleOrderProbe
    private(set) var calls: [Call] = []

    init(order: StoreLifecycleOrderProbe) {
        self.order = order
    }

    func reset(context: HomeAccountResetInteractionContext) {
        order.record(.resetAccount)
        calls.append(Call(
            resolvedRelays: context.state.resolvedRelays,
            readBoundaryScopeID: context.state.readBoundaryWrite?.scopeID
        ))
    }
}

@MainActor
final class StoreTimelineLoadSpy: HomeStoreTimelineLoading {
    enum Call: Equatable {
        case refreshLatest(
            accountID: String,
            lifecycle: HomeTimelineLifecycleToken,
            state: HomeTimelineLoadInteractionState
        )
        case loadOlder(
            accountID: String,
            lifecycle: HomeTimelineLifecycleToken,
            state: HomeTimelineLoadInteractionState
        )
    }

    private(set) var calls: [Call] = []

    func refreshLatest(
        account: NostrAccount,
        lifecycle: HomeTimelineLifecycleToken,
        context: HomeTimelineLoadInteractionContext
    ) async {
        calls.append(.refreshLatest(
            accountID: account.pubkey,
            lifecycle: lifecycle,
            state: context.state
        ))
    }

    func loadOlder(
        account: NostrAccount,
        lifecycle: HomeTimelineLifecycleToken,
        context: HomeTimelineLoadInteractionContext
    ) async {
        calls.append(.loadOlder(
            accountID: account.pubkey,
            lifecycle: lifecycle,
            state: context.state
        ))
    }
}

@MainActor
final class StoreMaterializationCancellationSpy:
    HomeStoreMaterializationCancelling {
    private let order: StoreLifecycleOrderProbe

    init(order: StoreLifecycleOrderProbe) {
        self.order = order
    }

    func cancelMaterialization() {
        order.record(.cancelMaterialization)
    }
}

@MainActor
final class StoreLifecycleContextProviderSpy:
    HomeStoreLifecycleContextProviding {
    enum Read: Equatable {
        case accountStart
        case accountReset
        case load
    }

    private let coordinator: HomeStoreContextCoordinator
    private(set) var reads: [Read] = []

    init(coordinator: HomeStoreContextCoordinator) {
        self.coordinator = coordinator
    }

    func accountStartContext() -> HomeAccountStartInteractionContext {
        reads.append(.accountStart)
        return coordinator.accountStartContext()
    }

    func accountResetContext() -> HomeAccountResetInteractionContext {
        reads.append(.accountReset)
        return coordinator.accountResetContext()
    }

    func loadContext() -> HomeTimelineLoadInteractionContext {
        reads.append(.load)
        return coordinator.loadContext()
    }
}

@MainActor
struct StoreLifecycleCoordinatorFixture {
    let contextFixture: StoreContextCoordinatorFixture
    let order: StoreLifecycleOrderProbe
    let accountStart: StoreAccountStartSpy
    let accountReset: StoreAccountResetSpy
    let load: StoreTimelineLoadSpy
    let materialization: StoreMaterializationCancellationSpy
    let contexts: StoreLifecycleContextProviderSpy
    let coordinator: HomeStoreLifecycleCoordinator

    init() {
        let contextFixture = StoreContextCoordinatorFixture()
        contextFixture.installSnapshots()
        contextFixture.source.readBoundaryWriteValue =
            HomeTimelineReadBoundaryWrite(
                scopeID: contextFixture.account.pubkey,
                feedID: "home",
                boundary: nil,
                updatedAt: 100
            )
        let order = StoreLifecycleOrderProbe()
        let accountStart = StoreAccountStartSpy()
        let accountReset = StoreAccountResetSpy(order: order)
        let load = StoreTimelineLoadSpy()
        let materialization = StoreMaterializationCancellationSpy(
            order: order
        )
        let contexts = StoreLifecycleContextProviderSpy(
            coordinator: contextFixture.coordinator
        )

        self.contextFixture = contextFixture
        self.order = order
        self.accountStart = accountStart
        self.accountReset = accountReset
        self.load = load
        self.materialization = materialization
        self.contexts = contexts
        coordinator = HomeStoreLifecycleCoordinator(
            accountStart: accountStart,
            accountReset: accountReset,
            load: load,
            materialization: materialization,
            contexts: contexts
        )
    }
}
