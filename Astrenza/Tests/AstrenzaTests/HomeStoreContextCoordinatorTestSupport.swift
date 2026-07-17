import AstrenzaCore
import Foundation
@testable import Astrenza

@MainActor
final class StoreContextSourceSpy: HomeStoreContextSourcing {
    enum SnapshotRead: Equatable {
        case load
        case runtime
        case state
        case feature
        case account
        case viewport
    }

    enum DependencyCall: Equatable {
        case hasResolvedRelays
        case loaderState
        case localBackfill(String)
        case resolvedRelays
        case currentFeed(String)
        case backward(String)
        case readBoundaryWrite
        case restoreCachedSnapshot(String)
        case restoredViewport(String)
        case waitForCachedPresentation
        case waitForPendingPresentation
        case restoreCachedReadState(String)
        case load(String)
        case scheduleReadBoundarySave
    }

    var loadSnapshotValue: HomeLoadContextSnapshot?
    var runtimeSnapshotValue: HomeTimelineRuntimeStoreSnapshot?
    var stateProjectionValue: HomeTimelineStateContextProjection?
    var featureSnapshotValue: HomeTimelineFeatureInteractionSnapshot?
    var accountSnapshotValue: HomeAccountLifecycleSnapshot?
    var viewportSnapshotValue: HomeViewportStoreSnapshot?
    var hasResolvedRelaysValue = false
    var loaderStateValue: NostrHomeTimelineState?
    var localBackfillEventsValue: [NostrEvent]?
    var resolvedRelaysValue: [String] = []
    var currentFeedResult = false
    var backwardResolutionResult = false
    var readBoundaryWriteValue: HomeTimelineReadBoundaryWrite?
    var restoreCachedSnapshotResult: HomeTimelineCachedStateRestoreOutcome = .missing
    var restoredViewportValue: HomeTimelineRestoredViewport?
    private(set) var snapshotReads: [SnapshotRead] = []
    private(set) var dependencyCalls: [DependencyCall] = []
    private(set) var runtimeApplicationContextCount = 0

    func loadSnapshot() -> HomeLoadContextSnapshot? {
        snapshotReads.append(.load)
        return loadSnapshotValue
    }

    func hasResolvedRelays() -> Bool {
        dependencyCalls.append(.hasResolvedRelays)
        return hasResolvedRelaysValue
    }

    func loaderState() -> NostrHomeTimelineState? {
        dependencyCalls.append(.loaderState)
        return loaderStateValue
    }

    func localBackfillEvents(
        account: NostrAccount,
        current _: NostrHomeTimelineState
    ) -> [NostrEvent]? {
        dependencyCalls.append(.localBackfill(account.pubkey))
        return localBackfillEventsValue
    }

    func resolvedRelays() -> [String] {
        dependencyCalls.append(.resolvedRelays)
        return resolvedRelaysValue
    }

    func runtimeSnapshot() -> HomeTimelineRuntimeStoreSnapshot? {
        snapshotReads.append(.runtime)
        return runtimeSnapshotValue
    }

    func isCurrentFeedContext(_ context: HomeFeedRuntimeContext) -> Bool {
        dependencyCalls.append(.currentFeed(context.feedID))
        return currentFeedResult
    }

    func waitForPendingPresentation() async {
        dependencyCalls.append(.waitForPendingPresentation)
    }

    func runtimeApplicationEffects(
        context _: HomeTimelineStateInteractionContext
    ) -> HomeTimelineRuntimeApplicationEffects {
        runtimeApplicationContextCount += 1
        return HomeTimelineRuntimeApplicationEffects(
            applyListProjectionInvalidation: { _ in },
            applyPendingEventCountPublication: { _ in },
            reloadProjection: { _, _ in },
            reloadNewestProjection: { _ in },
            scheduleMaterialization: { _ in },
            persistTimelineMetadata: { _ in },
            sourceInstallFailed: { _ in }
        )
    }

    func stateProjection() -> HomeTimelineStateContextProjection? {
        snapshotReads.append(.state)
        return stateProjectionValue
    }

    func featureSnapshot() -> HomeTimelineFeatureInteractionSnapshot? {
        snapshotReads.append(.feature)
        return featureSnapshotValue
    }

    func resolveBackwardDependencies(
        _ request: HomeTimelineBackwardDependencyRequest,
        application _: HomeTimelineRuntimeApplicationEffects
    ) async -> Bool {
        dependencyCalls.append(.backward(request.event.id))
        return backwardResolutionResult
    }

    func accountSnapshot() -> HomeAccountLifecycleSnapshot? {
        snapshotReads.append(.account)
        return accountSnapshotValue
    }

    func readBoundaryWrite() -> HomeTimelineReadBoundaryWrite? {
        dependencyCalls.append(.readBoundaryWrite)
        return readBoundaryWriteValue
    }

    func restoreCachedSnapshot(
        account: NostrAccount,
        context _: HomeTimelineStateInteractionContext
    ) async -> HomeTimelineCachedStateRestoreOutcome {
        dependencyCalls.append(.restoreCachedSnapshot(account.pubkey))
        return restoreCachedSnapshotResult
    }

    func restoredViewport(accountID: String) -> HomeTimelineRestoredViewport? {
        dependencyCalls.append(.restoredViewport(accountID))
        return restoredViewportValue
    }

    func waitForCachedPresentation() async {
        dependencyCalls.append(.waitForCachedPresentation)
    }

    func restoreCachedReadState(account: NostrAccount) async {
        dependencyCalls.append(.restoreCachedReadState(account.pubkey))
    }

    func load(
        _ request: HomeTimelineAccountStartLoadRequest,
        context _: HomeTimelineLoadInteractionContext
    ) async {
        dependencyCalls.append(.load(request.account.pubkey))
    }

    func viewportSnapshot() -> HomeViewportStoreSnapshot? {
        snapshotReads.append(.viewport)
        return viewportSnapshotValue
    }

    func scheduleReadBoundarySave() {
        dependencyCalls.append(.scheduleReadBoundarySave)
    }
}

@MainActor
struct StoreContextCoordinatorFixture {
    let account = NostrAccount(
        pubkey: String(repeating: "a", count: 64),
        displayIdentifier: "context-composition",
        readOnly: true
    )
    let source: StoreContextSourceSpy
    let target: HomeStoreApplicationCoordinator
    let coordinator: HomeStoreContextCoordinator

    init() {
        let source = StoreContextSourceSpy()
        let target = makeStoreContextApplicationTarget()
        let coordinator = HomeStoreContextCoordinator(source: source)
        coordinator.bind(
            applications: HomeStoreContextApplications.make(target: target)
        )
        self.source = source
        self.target = target
        self.coordinator = coordinator
    }

    var event: NostrEvent {
        NostrEvent(
            id: String(repeating: "1", count: 64),
            pubkey: account.pubkey,
            createdAt: 100,
            kind: 1,
            tags: [],
            content: "context composition",
            sig: String(repeating: "2", count: 128)
        )
    }

    var timelineState: NostrHomeTimelineState {
        NostrHomeTimelineState(
            relays: ["wss://relay.example"],
            followedPubkeys: [account.pubkey],
            noteEvents: [event],
            metadataEvents: []
        )
    }

    var lifecycle: HomeTimelineLifecycleToken {
        HomeTimelineLifecycleToken(
            accountID: account.pubkey,
            generation: 3
        )
    }

    var feedContext: HomeFeedRuntimeContext {
        HomeFeedRuntimeContext(definition: NostrFeedDefinitionRecord(
            feedID: "home:\(account.pubkey)",
            accountID: account.pubkey,
            kind: "home",
            specificationJSON: Data(#"{"authors":[],"kinds":[1,6]}"#.utf8),
            specificationHash: "context-composition",
            revision: 1,
            createdAt: 1,
            updatedAt: 1
        ))
    }

    var stateProjection: HomeTimelineStateContextProjection {
        HomeTimelineStateContextProjection(
            persistenceState: HomeTimelinePersistenceState(
                accountID: account.pubkey,
                followedPubkeys: [account.pubkey]
            ),
            runtimeApplicationState: HomeTimelineRuntimeApplicationState(
                account: account,
                resolvedRelays: ["wss://relay.example"],
                followedPubkeys: [account.pubkey],
                nip05Resolutions: [:],
                hasMoreOlder: true,
                deferredMaterializationDelayNanoseconds: 32
            ),
            hasPendingEvents: true
        )
    }

    func installSnapshots() {
        source.loadSnapshotValue = HomeLoadContextSnapshot(
            hasRelayRuntime: true,
            hasTimelineEvents: true
        )
        source.runtimeSnapshotValue = HomeTimelineRuntimeStoreSnapshot(
            account: account,
            resolvedRelays: ["wss://relay.example"],
            bootstrapRelayURLs: ["wss://bootstrap.example"],
            policy: .default(networkType: .wifi),
            hasRelayRuntime: true,
            isTerminating: false,
            isRuntimeActive: true,
            isRealtime: true,
            hasRestoreProjectionAnchor: false,
            isTimelineAtNewestWindow: true,
            hasPendingEvents: false
        )
        source.stateProjectionValue = stateProjection
        source.featureSnapshotValue = HomeTimelineFeatureInteractionSnapshot(
            account: account,
            resolvedRelays: ["wss://relay.example"],
            relayListEvent: nil,
            syncPolicy: .default(networkType: .wifi),
            hasRelayRuntime: true
        )
        source.accountSnapshotValue = HomeAccountLifecycleSnapshot(
            account: account,
            syncPolicy: .default(networkType: .wifi),
            restoreProjectionAnchorEventID: "anchor",
            hasEntries: true,
            resolvedRelays: ["wss://relay.example"],
            hasRelayRuntime: true
        )
        source.viewportSnapshotValue = HomeViewportStoreSnapshot(
            account: account,
            restoreProjectionAnchorEventID: "anchor",
            hasPendingProjectionReload: true,
            canBeginLoadingOlder: true,
            hasMoreOlder: true,
            hasTimelineEvents: true,
            hasResolvedRelays: true,
            hasFollowedPubkeys: true
        )
    }

    func clearSnapshots() {
        source.loadSnapshotValue = nil
        source.runtimeSnapshotValue = nil
        source.stateProjectionValue = nil
        source.featureSnapshotValue = nil
        source.accountSnapshotValue = nil
        source.viewportSnapshotValue = nil
    }
}

@MainActor
private func makeStoreContextApplicationTarget() -> HomeStoreApplicationCoordinator {
    let components = HomeTimelineStoreAssembly.assemble(
        HomeTimelineStoreAssemblyInput(
            timelineLoader: NostrHomeTimelineLoader(),
            eventStore: nil,
            startupFailureMessage: nil,
            relayRuntime: nil,
            linkPreviewResolver: nil,
            viewportStateRestorer: TimelineRestoreStore(),
            outboxPublisher: NostrOutboxRelayPublisher(),
            localMutationPersistence: nil,
            initialSyncPolicy: .default(networkType: .unknown),
            syncPolicySettingsStore: .shared
        )
    )
    return HomeStoreComposition.make(components: components).application
}
