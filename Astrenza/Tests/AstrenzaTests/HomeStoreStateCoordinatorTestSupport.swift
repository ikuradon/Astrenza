import AstrenzaCore
@testable import Astrenza

@MainActor
final class StoreStateOrderProbe {
    enum Step: Equatable {
        case runtimeBootstrapState
        case readAccount
        case replaceState
    }

    private(set) var steps: [Step] = []

    func record(_ step: Step) {
        steps.append(step)
    }
}

@MainActor
final class StoreStateDataSpy: HomeStoreStateDataInteracting {
    enum Call: Equatable {
        case perform(HomeTimelineDataIntent)
        case runtimeBootstrapState([String])
        case persistenceSnapshotInput(accountID: String)
        #if DEBUG
        case enqueueDependencies(
            NostrEventDependencies,
            relayURLs: [String],
            now: Int
        )
        case flushSourcePacketInstall
        #endif
    }

    private let provisionalSnapshot: HomeTimelineContentSnapshot
    private let followedSnapshot: HomeTimelineContentSnapshot
    private let bootstrapResult: NostrHomeTimelineState
    private let persistenceInput: HomeTimelineSnapshotInput
    private let order: StoreStateOrderProbe
    let dependencyWorkState: HomeTimelineDependencyWorkState
    private(set) var calls: [Call] = []

    init(
        provisionalSnapshot: HomeTimelineContentSnapshot,
        followedSnapshot: HomeTimelineContentSnapshot,
        bootstrapResult: NostrHomeTimelineState,
        persistenceInput: HomeTimelineSnapshotInput,
        dependencyWorkState: HomeTimelineDependencyWorkState,
        order: StoreStateOrderProbe
    ) {
        self.provisionalSnapshot = provisionalSnapshot
        self.followedSnapshot = followedSnapshot
        self.bootstrapResult = bootstrapResult
        self.persistenceInput = persistenceInput
        self.dependencyWorkState = dependencyWorkState
        self.order = order
    }

    func perform(
        _ intent: HomeTimelineDataIntent
    ) -> HomeTimelineContentSnapshot {
        calls.append(.perform(intent))
        switch intent {
        case .installProvisionalRelays:
            return provisionalSnapshot
        case .replaceFollowedPubkeys:
            return followedSnapshot
        }
    }

    func runtimeBootstrapState(
        from state: NostrHomeTimelineState
    ) -> NostrHomeTimelineState {
        order.record(.runtimeBootstrapState)
        calls.append(.runtimeBootstrapState(state.relays))
        return bootstrapResult
    }

    func persistenceSnapshotInput(
        accountID: String
    ) -> HomeTimelineSnapshotInput {
        calls.append(.persistenceSnapshotInput(accountID: accountID))
        return persistenceInput
    }

    #if DEBUG
    func enqueueSourceDependencies(
        _ dependencies: NostrEventDependencies,
        availableRelayURLs: [String],
        now: Int
    ) -> Bool {
        calls.append(.enqueueDependencies(
            dependencies,
            relayURLs: availableRelayURLs,
            now: now
        ))
        return true
    }

    func flushSourcePacketInstall(
        onFailure: @escaping HomeDependencyInstallFailureHandler
    ) -> Bool {
        calls.append(.flushSourcePacketInstall)
        onFailure("dependency install failed")
        return false
    }
    #endif
}

@MainActor
final class StoreTimelineStateInteractionSpy:
    HomeStoreTimelineStateInteracting {
    enum Call: Equatable {
        case replace(relays: [String], accountID: String?)
        case persist(accountID: String)
    }

    private let order: StoreStateOrderProbe
    private(set) var calls: [Call] = []

    init(order: StoreStateOrderProbe) {
        self.order = order
    }

    func replace(
        _ state: NostrHomeTimelineState,
        accountID: String?,
        context: HomeTimelineStateInteractionContext
    ) {
        order.record(.replaceState)
        calls.append(.replace(relays: state.relays, accountID: accountID))
        context.effects.apply(.requestNewestProjectionReload)
    }

    func persistSnapshot(
        _ input: HomeTimelineSnapshotInput,
        context: HomeTimelineStateInteractionContext
    ) async -> Bool {
        calls.append(.persist(accountID: input.accountID))
        context.effects.apply(.materializeEntries)
        return false
    }
}

@MainActor
final class StoreStateSourceSpy: HomeStoreStateSourcing {
    private let order: StoreStateOrderProbe
    var accountID: String?
    var syncPolicy = NostrSyncPolicy.default(
        networkType: .wifi,
        lowPowerMode: true
    )
    var resolvedRelays = ["wss://state.example"]
    var followedPubkeys = ["followed-author"]
    var hasMoreOlder = false
    private(set) var readCount = 0

    init(
        accountID: String?,
        order: StoreStateOrderProbe
    ) {
        self.accountID = accountID
        self.order = order
    }

    var account: NostrAccount? {
        accountID.map {
            NostrAccount(
                pubkey: $0,
                displayIdentifier: "state-account",
                readOnly: true
            )
        }
    }

    func currentAccountID() -> String? {
        order.record(.readAccount)
        readCount += 1
        return accountID
    }
}

@MainActor
final class StoreStateContextProviderSpy: HomeStoreStateContextProviding {
    enum Application: Equatable {
        case requestNewestProjectionReload(contextID: Int)
        case materializeEntries(contextID: Int)
    }

    private(set) var contextIDs: [Int] = []
    private(set) var applications: [Application] = []

    func stateContext() -> HomeTimelineStateInteractionContext {
        let contextID = contextIDs.count + 1
        contextIDs.append(contextID)
        return HomeTimelineStateInteractionContext(
            effects: HomeTimelineStateInteractionEffects(
                environment: HomeTimelineStateInteractionEnvironment(
                    projection: { nil }
                ),
                apply: { [weak self] application in
                    switch application {
                    case .requestNewestProjectionReload:
                        self?.applications.append(
                            .requestNewestProjectionReload(
                                contextID: contextID
                            )
                        )
                    case .materializeEntries:
                        self?.applications.append(
                            .materializeEntries(contextID: contextID)
                        )
                    default:
                        break
                    }
                }
            )
        )
    }
}

@MainActor
final class StoreStateFailureProbe {
    private(set) var messages: [String] = []

    func record(_ message: String) {
        messages.append(message)
    }
}

@MainActor
struct StoreStateCoordinatorFixture {
    let order: StoreStateOrderProbe
    let data: StoreStateDataSpy
    let state: StoreTimelineStateInteractionSpy
    let source: StoreStateSourceSpy
    let contexts: StoreStateContextProviderSpy
    let coordinator: HomeStoreStateCoordinator

    init() {
        let order = StoreStateOrderProbe()
        let state = StoreTimelineStateInteractionSpy(order: order)
        let source = StoreStateSourceSpy(
            accountID: "initial-account",
            order: order
        )
        let contexts = StoreStateContextProviderSpy()
        let data = StoreStateDataSpy(
            provisionalSnapshot: Self.provisionalSnapshot,
            followedSnapshot: Self.followedSnapshot,
            bootstrapResult: Self.bootstrapResult,
            persistenceInput: Self.persistenceInput,
            dependencyWorkState: HomeTimelineDependencyWorkState(
                hasPendingWork: true,
                pendingSourceRequestCount: 5
            ),
            order: order
        )
        self.order = order
        self.data = data
        self.state = state
        self.source = source
        self.contexts = contexts
        coordinator = HomeStoreStateCoordinator(
            data: data,
            state: state,
            source: source,
            contexts: contexts
        )
    }

    let bootstrapInput = NostrHomeTimelineState(
        relays: ["wss://bootstrap-input.example"],
        followedPubkeys: [],
        noteEvents: [],
        metadataEvents: []
    )

    let replacementState = NostrHomeTimelineState(
        relays: ["wss://replacement.example"],
        followedPubkeys: [],
        noteEvents: [],
        metadataEvents: []
    )

    static let provisionalSnapshot = HomeTimelineContentSnapshot(
        resolvedRelays: ["wss://provisional.example"],
        followedPubkeys: [],
        noteEvents: [],
        metadataEvents: [],
        relayListEvent: nil,
        contactListEvent: nil,
        hasMoreOlder: true
    )

    static let followedSnapshot = HomeTimelineContentSnapshot(
        resolvedRelays: [],
        followedPubkeys: ["followed"],
        noteEvents: [],
        metadataEvents: [],
        relayListEvent: nil,
        contactListEvent: nil,
        hasMoreOlder: true
    )

    static let bootstrapResult = NostrHomeTimelineState(
        relays: ["wss://bootstrap-result.example"],
        followedPubkeys: [],
        noteEvents: [],
        metadataEvents: []
    )

    static let persistenceInput = HomeTimelineSnapshotInput(
        accountID: "persisted-account",
        relays: [],
        followedPubkeys: [],
        noteEvents: [],
        metadataEvents: [],
        relayListEvent: nil,
        contactListEvent: nil,
        nip05Resolutions: [:],
        hasMoreOlder: true
    )
}
