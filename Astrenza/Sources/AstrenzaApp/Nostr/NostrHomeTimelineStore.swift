import Foundation
import AstrenzaCore
import SwiftUI

@MainActor
final class NostrHomeTimelineStore: ObservableObject {
    typealias Phase = NostrHomeTimelinePhase

    @Published private(set) var account: NostrAccount?
    @Published private(set) var entries: [TimelineFeedEntry] = []
    @Published private(set) var phase: Phase = .idle
    @Published private(set) var resolvedRelays: [String] = []
    @Published private(set) var followedPubkeys: [String] = []
    @Published private(set) var isRefreshing = false
    @Published private(set) var isLoadingOlder = false
    @Published private(set) var hasMoreOlder = true
    @Published private(set) var filterStatus = TimelineFilterStatus()
    @Published private(set) var relayStatusRevision = 0
    @Published private(set) var relayRuntimeStates: [String: NostrRelayConnectionState] = [:]
    @Published private(set) var relayStatusCounts: (connected: Int, planned: Int) = (connected: 0, planned: 1)
    @Published private(set) var unmaterializedNewCount = 0
    @Published private(set) var materializedUnreadCount = 0
    @Published private(set) var visibleUnreadBadgeCount = 0
    @Published private(set) var resolvedContentRevision = 0
    @Published private(set) var listContentRevision = 0
    @Published private(set) var isHomeTimelineRealtime = false
    @Published private(set) var realtimeFollowSourceRevision: Int?

    private let remoteLoadCoordinator: HomeTimelineRemoteLoadCoordinator
    private let loadApplicationCoordinator: HomeTimelineLoadApplicationCoordinator
    private let eventStore: NostrEventStore?
    private let contentCoordinator: HomeTimelineContentCoordinator
    private let runtimeEventCoordinator: HomeTimelineRuntimeEventCoordinator
    private let backwardRequestCoordinator: HomeTimelineBackwardRequestCoordinator
    private let gapBackfillWorkflow: HomeTimelineGapBackfillWorkflow
    private let backwardCompletionApplicationCoordinator: HomeTimelineBackwardCompletionApplicationCoordinator
    private let dependencyCoordinator: HomeTimelineDependencyResolutionCoordinator
    private let filterCoordinator: HomeTimelineFilterCoordinator
    private let listProjectionCache: HomeTimelineListProjectionCache
    private let activityCoordinator: HomeTimelineActivityCoordinator
    private let presentationCoordinator: HomeTimelinePresentationCoordinator
    private let materializationCoordinator: HomeTimelineMaterializationCoordinator
    private let pendingEventBuffer: HomeTimelinePendingEventBuffer
    private let backwardRequestRegistry: HomeTimelineBackwardRequestRegistry
    private let feedSyncCoordinator: HomeTimelineFeedSyncCoordinator
    private let lifecycleCoordinator: HomeTimelineLifecycleCoordinator
    private let runtimeSessionCoordinator: HomeTimelineRuntimeSessionCoordinator
    private let runtimeSetupCoordinator: HomeTimelineRuntimeSetupCoordinator
    private let runtimeShutdownCoordinator: HomeTimelineRuntimeShutdownCoordinator
    private let accountStartCoordinator: HomeTimelineAccountStartCoordinator
    private let accountResetCoordinator: HomeTimelineAccountResetCoordinator
    private let relayStatusCoordinator: HomeTimelineRelayStatusCoordinator
    private let linkPreviewCoordinator: HomeTimelineLinkPreviewCoordinator
    private let readStateCoordinator: HomeTimelineReadStateCoordinator
    private let timelineRepository: HomeTimelineRepository
    private let runtimePacketCoordinator: HomeTimelineRuntimePacketCoordinator
    private let gapReconciliationApplicationCoordinator: HomeTimelineGapReconciliationApplicationCoordinator
    private let homeFeedProjection: HomeFeedProjectionController
    private let stateApplicationCoordinator: HomeTimelineStateApplicationCoordinator
    private let persistenceCoordinator: HomeTimelinePersistenceCoordinator
    private let publishWorkflow: HomeTimelinePublishWorkflow?
    private let localMutationCoordinator: HomeTimelineLocalMutationCoordinator?
    private let relayRuntime: NostrRelayRuntime?
    private let outboxCoordinator: HomeTimelineOutboxCoordinator
    private var syncPolicy: NostrSyncPolicy
    private var isTimelineAtNewestWindow = true
    private var restoreProjectionAnchorEventID: String?

    var relayStatusEventStore: NostrEventStore? {
        eventStore
    }

    var currentSyncPolicy: NostrSyncPolicy {
        syncPolicy
    }

    private var noteEvents: [NostrEvent] {
        contentCoordinator.noteEvents
    }

    private var metadataEvents: [NostrEvent] {
        contentCoordinator.metadataEvents
    }

    private var relayListEvent: NostrEvent? {
        contentCoordinator.relayListEvent
    }

    private var contactListEvent: NostrEvent? {
        contentCoordinator.contactListEvent
    }

    private func timelineReadContext(
        applyingHomeFilters: Bool = true
    ) -> HomeTimelineReadContext {
        HomeTimelineReadContext(
            accountID: account?.pubkey,
            fallbackEntries: entries,
            metadataEvents: metadataEvents,
            nip05Resolutions: dependencyCoordinator.nip05Resolutions,
            profileResolutionStates: dependencyCoordinator.profileResolutionStates,
            followedPubkeys: Set(followedPubkeys),
            resolvedRelayCount: resolvedRelays.count,
            filterRules: applyingHomeFilters
                ? filterCoordinator.effectiveRuleSet(accountID: account?.pubkey)
                : nil,
            syncPolicy: syncPolicy
        )
    }

    private func applyContentSnapshot(_ snapshot: HomeTimelineContentSnapshot) {
        if resolvedRelays != snapshot.resolvedRelays {
            resolvedRelays = snapshot.resolvedRelays
        }
        if followedPubkeys != snapshot.followedPubkeys {
            followedPubkeys = snapshot.followedPubkeys
        }
        if hasMoreOlder != snapshot.hasMoreOlder {
            hasMoreOlder = snapshot.hasMoreOlder
        }
    }

    private func applyActivityTransition(
        _ transition: HomeTimelineActivityTransition
    ) {
        let changes = transition.changes
        let snapshot = transition.snapshot
        if changes.contains(.phase) {
            phase = snapshot.phase
        }
        if changes.contains(.refreshing) {
            isRefreshing = snapshot.isRefreshing
        }
        if changes.contains(.loadingOlder) {
            isLoadingOlder = snapshot.isLoadingOlder
        }
        if changes.contains(.realtime) {
            isHomeTimelineRealtime = snapshot.isRealtime
        }
    }

    private func applyPresentationTransition(
        _ transition: HomeTimelinePresentationTransition
    ) {
        let changes = transition.changes
        let snapshot = transition.snapshot
        if changes.contains(.entries) {
            entries = snapshot.entries
        }
        if changes.contains(.unreadCounts) {
            if materializedUnreadCount != snapshot.materializedUnreadCount {
                materializedUnreadCount = snapshot.materializedUnreadCount
            }
            if visibleUnreadBadgeCount != snapshot.visibleUnreadBadgeCount {
                visibleUnreadBadgeCount = snapshot.visibleUnreadBadgeCount
            }
        }
        if changes.contains(.filterStatus) {
            filterStatus = snapshot.filterStatus
        }
        if changes.contains(.resolvedContentRevision) {
            resolvedContentRevision = snapshot.resolvedContentRevision
        }
        if changes.contains(.realtimeFollowSourceRevision) {
            realtimeFollowSourceRevision = snapshot.realtimeFollowSourceRevision
        }
    }

    private func updateRelayStatusCounts() {
        applyRelayStatusSnapshot(
            relayStatusCoordinator.snapshot(resolvedRelays: resolvedRelays)
        )
    }

    private func applyRelayStatusSnapshot(_ snapshot: HomeTimelineRelayStatusSnapshot) {
        if relayRuntimeStates != snapshot.runtimeStates {
            relayRuntimeStates = snapshot.runtimeStates
        }
        setRelayStatusCountsIfNeeded((
            connected: snapshot.connectedRelayCount,
            planned: snapshot.plannedRelayCount
        ))
    }

    private func applyRelayStatusTransition(
        _ transition: HomeTimelineRelayStatusTransition?
    ) {
        guard let transition else { return }
        applyRelayStatusSnapshot(transition.snapshot)
        if let relayURL = transition.invalidatedRealtimeRelayURL {
            invalidateHomeTimelineRealtime(relayURL: relayURL)
        }
        if transition.publishesStatusChange {
            relayStatusRevision &+= 1
        }
    }

    private func setRelayStatusCountsIfNeeded(_ counts: (connected: Int, planned: Int)) {
        guard relayStatusCounts.connected != counts.connected ||
            relayStatusCounts.planned != counts.planned
        else { return }
        relayStatusCounts = counts
    }

    var activityStatus: NostrTimelineActivityStatus? {
        activityCoordinator.activityStatus(
            context: HomeTimelineActivityContext(
                connectedRelayCount: relayStatusCounts.connected,
                plannedRelayCount: relayStatusCounts.planned,
                hasOlderPageRequest: backwardRequestRegistry.hasOlderPageRequest,
                hasGapWork: backwardRequestRegistry.hasGapWork,
                hasBackwardRequests: backwardRequestRegistry.hasRequests,
                hasPendingDependencyWork: dependencyCoordinator.hasPendingWork
            )
        )
    }

    var isRelayProcessing: Bool {
        activityStatus != nil
    }

    init(
        timelineLoader: NostrHomeTimelineLoader = NostrHomeTimelineLoader(),
        eventStore: NostrEventStore? = try? NostrEventStore.applicationSupport(appDirectory: "Astrenza"),
        relayRuntime: NostrRelayRuntime? = nil,
        linkPreviewResolver: NostrLinkPreviewResolver? = nil,
        outboxPublisher: NostrOutboxRelayPublisher = NostrOutboxRelayPublisher(),
        localMutationPersistence: (any HomeTimelineLocalMutationPersisting)? = nil,
        syncPolicy: NostrSyncPolicy = .default(networkType: .unknown, lowPowerMode: false),
        syncPolicySettingsStore: NostrSyncPolicySettingsStore = .shared
    ) {
        let persistenceWorker = eventStore.map(HomeTimelinePersistenceWorker.init)
        self.eventStore = eventStore
        let contentCoordinator = HomeTimelineContentCoordinator(eventStore: eventStore)
        self.contentCoordinator = contentCoordinator
        let eventIngestor = HomeTimelineEventIngestor(eventStore: eventStore)
        let syncPlanner = HomeTimelineSyncPlanner()
        let profileDirectory = relayRuntime.map {
            NostrProfileDirectory(eventStore: eventStore, relayRuntime: $0)
        }
        let sourcePacketInstaller: HomeTimelineDependencyResolutionCoordinator.SourcePacketInstaller?
        let backwardPacketInstaller: HomeTimelineBackwardRequestCoordinator.PacketInstaller?
        if let relayRuntime {
            sourcePacketInstaller = { packets in
                try await relayRuntime.installBackward(packets, mergeField: .ids)
            }
            backwardPacketInstaller = { packets, mergeField in
                try await relayRuntime.installBackward(packets, mergeField: mergeField)
            }
        } else {
            sourcePacketInstaller = nil
            backwardPacketInstaller = nil
        }
        let backfillPersistence = HomeTimelineBackfillPersistence(eventStore: eventStore)
        let timelineRepository = HomeTimelineRepository(eventStore: eventStore)
        self.timelineRepository = timelineRepository
        let gapReconciliationCoordinator = HomeTimelineGapReconciliationCoordinator(
            reconciler: HomeTimelineGapReconciler(
                eventStore: eventStore,
                relayClient: timelineLoader.relayClient
            ),
            persistence: backfillPersistence
        )
        let homeFeedProjection = HomeFeedProjectionController(eventStore: eventStore)
        self.homeFeedProjection = homeFeedProjection
        let snapshotCoordinator = HomeTimelineSnapshotCoordinator(
            eventStore: eventStore,
            persistenceWorker: persistenceWorker,
            projectionController: homeFeedProjection
        )
        self.publishWorkflow = eventStore.map { eventStore in
            HomeTimelinePublishWorkflow(
                publisher: HomeTimelinePublishCoordinator(eventStore: eventStore),
                contentManager: contentCoordinator,
                projectionManager: homeFeedProjection
            )
        }
        self.localMutationCoordinator = (localMutationPersistence ?? eventStore).map {
            HomeTimelineLocalMutationCoordinator(persistence: $0)
        }
        let backwardRequestRegistry = HomeTimelineBackwardRequestRegistry()
        self.backwardRequestRegistry = backwardRequestRegistry
        let backwardRequestCoordinator = HomeTimelineBackwardRequestCoordinator(
            contentCoordinator: contentCoordinator,
            timelineRepository: timelineRepository,
            projectionController: homeFeedProjection,
            backwardRequestRegistry: backwardRequestRegistry,
            syncPlanner: syncPlanner,
            packetInstaller: backwardPacketInstaller
        )
        self.backwardRequestCoordinator = backwardRequestCoordinator
        self.gapBackfillWorkflow = HomeTimelineGapBackfillWorkflow(
            requester: backwardRequestCoordinator,
            persistence: backfillPersistence
        )
        let feedSyncCoordinator = HomeTimelineFeedSyncCoordinator(
            eventStore: eventStore,
            backwardRequestRegistry: backwardRequestRegistry
        )
        self.feedSyncCoordinator = feedSyncCoordinator
        let runtimeEventProcessor = HomeTimelineRuntimeEventProcessor(
            eventIngestor: eventIngestor,
            backwardRequestRegistry: backwardRequestRegistry,
            feedSyncCoordinator: feedSyncCoordinator
        )
        self.relayRuntime = relayRuntime
        let dependencyCoordinator = HomeTimelineDependencyResolutionCoordinator(
            eventIngestor: eventIngestor,
            profileDirectory: profileDirectory,
            nip05Resolver: timelineLoader.nip05Resolver,
            syncPlanner: syncPlanner,
            sourcePacketInstaller: sourcePacketInstaller
        )
        self.dependencyCoordinator = dependencyCoordinator
        self.backwardCompletionApplicationCoordinator =
            HomeTimelineBackwardCompletionApplicationCoordinator(
                backwardRequestRegistry: backwardRequestRegistry,
                dependencyCoordinator: dependencyCoordinator,
                contentCoordinator: contentCoordinator,
                projectionController: homeFeedProjection,
                persistence: backfillPersistence
            )
        let filterCoordinator = HomeTimelineFilterCoordinator(eventStore: eventStore)
        self.filterCoordinator = filterCoordinator
        let listProjectionCache = HomeTimelineListProjectionCache()
        self.listProjectionCache = listProjectionCache
        let activityCoordinator = HomeTimelineActivityCoordinator()
        self.activityCoordinator = activityCoordinator
        let presentationCoordinator = HomeTimelinePresentationCoordinator()
        self.presentationCoordinator = presentationCoordinator
        self.materializationCoordinator = HomeTimelineMaterializationCoordinator(
            contentCoordinator: contentCoordinator,
            filterCoordinator: filterCoordinator,
            presentationCoordinator: presentationCoordinator,
            projectionController: homeFeedProjection,
            repository: timelineRepository
        )
        let pendingEventBuffer = HomeTimelinePendingEventBuffer()
        self.pendingEventBuffer = pendingEventBuffer
        let lifecycleCoordinator = HomeTimelineLifecycleCoordinator()
        self.lifecycleCoordinator = lifecycleCoordinator
        self.persistenceCoordinator = HomeTimelinePersistenceCoordinator(
            snapshotPersistence: snapshotCoordinator,
            lifecycleCoordinator: lifecycleCoordinator
        )
        self.accountStartCoordinator = HomeTimelineAccountStartCoordinator(
            lifecycleCoordinator: lifecycleCoordinator,
            resolveSyncPolicy: { accountID, fallback in
                syncPolicySettingsStore.policy(accountID: accountID, fallback: fallback)
            }
        )
        self.loadApplicationCoordinator = HomeTimelineLoadApplicationCoordinator(
            lifecycleCoordinator: lifecycleCoordinator
        )
        let gapReconciliationApplicationCoordinator =
            HomeTimelineGapReconciliationApplicationCoordinator(
                reconciliationCoordinator: gapReconciliationCoordinator,
                contentCoordinator: contentCoordinator,
                timelineRepository: timelineRepository,
                projectionController: homeFeedProjection,
                backwardRequestRegistry: backwardRequestRegistry,
                lifecycleCoordinator: lifecycleCoordinator
            )
        self.gapReconciliationApplicationCoordinator = gapReconciliationApplicationCoordinator
        let runtimeEventApplicationCoordinator = HomeTimelineRuntimeEventApplicationCoordinator(
            contentCoordinator: contentCoordinator,
            dependencyCoordinator: dependencyCoordinator,
            listProjectionCache: listProjectionCache,
            pendingEventBuffer: pendingEventBuffer,
            backwardRequestRegistry: backwardRequestRegistry,
            lifecycleCoordinator: lifecycleCoordinator
        )
        let runtimeEventCoordinator = HomeTimelineRuntimeEventCoordinator(
            processor: runtimeEventProcessor,
            applicationCoordinator: runtimeEventApplicationCoordinator,
            contentCoordinator: contentCoordinator,
            projectionController: homeFeedProjection,
            feedEventRecorder: feedSyncCoordinator,
            lifecycleCoordinator: lifecycleCoordinator
        )
        self.runtimeEventCoordinator = runtimeEventCoordinator
        let runtimeEventPump = HomeTimelineRuntimeEventPump()
        let runtimeStream: HomeTimelineRuntimeSessionCoordinator.RuntimeStream?
        if let relayRuntime {
            runtimeStream = { await relayRuntime.events() }
        } else {
            runtimeStream = nil
        }
        let runtimeSessionCoordinator = HomeTimelineRuntimeSessionCoordinator(
            runtimeEventPump: runtimeEventPump,
            runtimeStream: runtimeStream,
            profileUpdateObserver: dependencyCoordinator,
            profileUpdateApplication: runtimeEventCoordinator,
            lifecycleCoordinator: lifecycleCoordinator
        )
        self.runtimeSessionCoordinator = runtimeSessionCoordinator
        let terminateRuntime: HomeTimelineRuntimeShutdownCoordinator.RuntimeTermination?
        if let relayRuntime {
            terminateRuntime = { await relayRuntime.terminate() }
        } else {
            terminateRuntime = nil
        }
        self.runtimeShutdownCoordinator = HomeTimelineRuntimeShutdownCoordinator(
            scheduler: HomeTimelineRelayRuntimeTerminator(),
            runtimeSession: runtimeSessionCoordinator,
            lifecycleCoordinator: lifecycleCoordinator,
            terminateRuntime: terminateRuntime
        )
        let relayRuntimeConfigurator = HomeTimelineRelayRuntimeConfigurator(
            relayRuntime: relayRuntime,
            runtimeEventPump: runtimeEventPump,
            dependencyCoordinator: dependencyCoordinator,
            syncPlanner: syncPlanner
        )
        let runtimeSetupCoordinator = HomeTimelineRuntimeSetupCoordinator(
            configurator: relayRuntimeConfigurator,
            contentCoordinator: contentCoordinator,
            dependencyCoordinator: dependencyCoordinator,
            projectionController: homeFeedProjection,
            feedSyncCoordinator: feedSyncCoordinator,
            lifecycleCoordinator: lifecycleCoordinator,
            timelineRepository: timelineRepository
        )
        self.runtimeSetupCoordinator = runtimeSetupCoordinator
        let relayStatusCoordinator = HomeTimelineRelayStatusCoordinator(
            diagnostics: HomeTimelineRelayDiagnosticsLedger(
                eventStore: eventStore,
                persistenceWorker: persistenceWorker
            )
        )
        self.relayStatusCoordinator = relayStatusCoordinator
        self.stateApplicationCoordinator = HomeTimelineStateApplicationCoordinator(
            snapshotCoordinator: snapshotCoordinator,
            presentationCoordinator: presentationCoordinator,
            contentCoordinator: contentCoordinator,
            dependencyCoordinator: dependencyCoordinator,
            relayStatusCoordinator: relayStatusCoordinator,
            projectionController: homeFeedProjection,
            listProjectionCache: listProjectionCache,
            pendingEventBuffer: pendingEventBuffer
        )
        self.runtimePacketCoordinator = HomeTimelineRuntimePacketCoordinator(
            feedSyncCoordinator: feedSyncCoordinator,
            relayStatusCoordinator: relayStatusCoordinator
        )
        self.remoteLoadCoordinator = HomeTimelineRemoteLoadCoordinator(
            loader: timelineLoader,
            relayEventPersistence: relayStatusCoordinator
        )
        let linkPreviewCoordinator = HomeTimelineLinkPreviewCoordinator(
            eventStore: eventStore,
            resolver: linkPreviewResolver
        )
        self.linkPreviewCoordinator = linkPreviewCoordinator
        let readStateCoordinator = HomeTimelineReadStateCoordinator(
            eventStore: eventStore,
            persistenceWorker: persistenceWorker
        )
        self.readStateCoordinator = readStateCoordinator
        let outboxCoordinator = HomeTimelineOutboxCoordinator(
            drainer: HomeTimelineOutboxDrainer(
                eventStore: eventStore,
                publisher: outboxPublisher
            )
        )
        self.outboxCoordinator = outboxCoordinator
        self.accountResetCoordinator = HomeTimelineAccountResetCoordinator(
            dependencies: HomeTimelineAccountResetDependencies(
                endReadSession: { readBoundaryWrite in
                    readStateCoordinator.endSession(flushing: readBoundaryWrite)
                },
                flushRelayTraffic: relayStatusCoordinator.flushTraffic,
                cancelLifecycle: lifecycleCoordinator.cancel,
                cancelGapReconciliation: gapReconciliationApplicationCoordinator.cancel,
                cancelRuntimeEvents: runtimeSessionCoordinator.cancelRuntimeEvents,
                resetLinkPreviews: linkPreviewCoordinator.reset,
                resetPresentation: presentationCoordinator.reset,
                cancelOutbox: outboxCoordinator.cancel,
                resetDependencies: dependencyCoordinator.reset,
                resetBackwardRequests: backwardRequestRegistry.reset,
                resetActivity: activityCoordinator.reset,
                resetProjection: homeFeedProjection.reset,
                resetRuntimeSetup: runtimeSetupCoordinator.reset,
                resetFeedSync: {
                    feedSyncCoordinator.reset(finishingActiveRequestsWith: .cancelled)
                },
                resetContent: contentCoordinator.reset,
                resetRelayStatus: relayStatusCoordinator.reset,
                resetFilters: filterCoordinator.reset
            )
        )
        self.syncPolicy = syncPolicy
    }

    func start(account: NostrAccount) {
        accountStartCoordinator.start(
            HomeTimelineAccountStartRequest(
                account: account,
                hasRelayRuntime: relayRuntime != nil
            ),
            handlers: accountStartHandlers()
        )
    }

    func setRestoreProjectionAnchor(_ anchorEventID: String?) {
        restoreProjectionAnchorEventID = anchorEventID
        if anchorEventID != nil {
            isTimelineAtNewestWindow = false
        }
        guard let account else { return }
        if anchorEventID == nil {
            reloadNewestProjectionWindow(account: account)
            materializeEntries()
        } else {
            applyRestoreProjectionAnchorIfPossible(account: account)
        }
    }

    func restoredViewportState(accountID: String, timelineKey: String) -> TimelineViewportState? {
        readStateCoordinator.restoredViewportState(
            accountID: accountID,
            timelineKey: timelineKey
        )
    }

    func saveViewportState(_ state: TimelineViewportState) {
        guard state.timelineKey == "home",
              let account,
              account.pubkey == state.accountID,
              let definition = homeFeedProjection.definition
        else { return }
        readStateCoordinator.scheduleViewportState(
            state,
            feedID: definition.feedID,
            scopeID: account.pubkey
        )
    }

    func flushPendingViewportStateSave() {
        readStateCoordinator.flushPendingViewportWrite()
    }

    func refresh() {
        guard let account,
              let lifecycle = lifecycleCoordinator.token(for: account.pubkey)
        else { return }
        restoreProjectionAnchorEventID = nil
        isTimelineAtNewestWindow = true
        lifecycleCoordinator.startPagination(for: lifecycle) { [weak self] in
            await self?.refreshLatest(account: account, lifecycle: lifecycle)
        }
    }

    func refreshLatest() async {
        guard let account,
              let lifecycle = lifecycleCoordinator.token(for: account.pubkey)
        else { return }
        await refreshLatest(account: account, lifecycle: lifecycle)
    }

    func setTimelineAtNewestWindow(_ isAtNewestWindow: Bool) {
        guard !isAtNewestWindow || restoreProjectionAnchorEventID == nil else { return }
        isTimelineAtNewestWindow = isAtNewestWindow
    }

    func setTimelineScrollActive(_ isActive: Bool) {
        presentationCoordinator.setScrollActive(isActive) { [weak self] allowsRealtimeFollow in
            self?.materializeEntries(allowsRealtimeFollow: allowsRealtimeFollow)
        }
    }

    func dismissUnreadBadge() {
        applyPresentationTransition(
            presentationCoordinator.dismissUnreadBadge()
        )
    }

    func markMaterializedPostsRead(visiblePostIDs: [TimelinePost.ID]) {
        guard let transition = presentationCoordinator.markVisiblePostsRead(
            visiblePostIDs
        ) else { return }
        applyPresentationTransition(transition)
        scheduleHomeFeedReadStateSave()
    }

    func markNewestMaterializedWindowRead() {
        guard let transition = presentationCoordinator.markNewestWindowRead() else { return }
        applyPresentationTransition(transition)
        scheduleHomeFeedReadStateSave()
    }

    @discardableResult
    func applyPendingNewEvents() async -> Bool {
        guard let account else { return false }
        let hadPendingNewEvents = pendingEventBuffer.hasEvents ||
            presentationCoordinator.hasPendingNewestProjectionReload
        restoreProjectionAnchorEventID = nil
        isTimelineAtNewestWindow = true
        reloadNewestProjectionWindow(account: account)
        clearPendingNewEvents()
        presentationCoordinator.clearNewestProjectionReload()
        materializeEntries()
        scheduleLinkPreviewResolution()
        return hadPendingNewEvents
    }

    func loadOlder() {
        guard let account,
              let lifecycle = lifecycleCoordinator.token(for: account.pubkey),
              activityCoordinator.canBeginLoadingOlder,
              hasMoreOlder,
              !noteEvents.isEmpty,
              !resolvedRelays.isEmpty,
              !followedPubkeys.isEmpty
        else { return }

        lifecycleCoordinator.startPagination(for: lifecycle) { [weak self] in
            await self?.loadOlder(account: account, lifecycle: lifecycle)
        }
    }

    func backfillGap(_ gap: TimelineGap, direction: TimelineGapFillDirection) async -> Bool {
        await gapBackfillWorkflow.backfill(
            HomeTimelineGapBackfillRequest(
                account: account,
                hasRelayRuntime: relayRuntime != nil,
                resolvedRelayCount: resolvedRelays.count,
                gap: gap,
                direction: direction
            ),
            handlers: gapBackfillHandlers()
        )
    }

    private func gapBackfillHandlers() -> HomeTimelineGapBackfillHandlers {
        HomeTimelineGapBackfillHandlers { [weak self] command in
            self?.applyGapBackfillCommand(command)
        }
    }

    private func applyGapBackfillCommand(
        _ command: HomeTimelineGapBackfillCommand
    ) {
        switch command {
        case .recordDiagnostic(let diagnostic):
            recordRuntimeSyncEvent(
                relayURL: diagnostic.relayURL,
                kind: .partialFailure,
                subscriptionID: diagnostic.subscriptionID,
                message: diagnostic.message
            )
        case .reloadProjection(let account, let anchorEventID):
            _ = reloadProjectionWindow(account: account, around: anchorEventID)
        case .materializeEntries:
            materializeEntries()
        }
    }

    func enqueuePublish(_ input: NostrPublishInput, signer: any NostrEventSigning) async throws {
        guard let account, let publishWorkflow else { return }
        try await publishWorkflow.enqueue(
            HomeTimelinePublishRequest(
                input: input,
                account: account,
                accountWriteRelays: NostrRelayList.parse(from: relayListEvent).writeRelays,
                fallbackRelays: resolvedRelays
            ),
            signer: signer,
            handlers: publishHandlers()
        )
    }

    private func publishHandlers() -> HomeTimelinePublishHandlers {
        HomeTimelinePublishHandlers(
            currentAccountID: { [weak self] in self?.account?.pubkey },
            perform: { [weak self] command in
                self?.applyPublishCommand(command)
            },
            persistDatabase: { [weak self] account in
                await self?.persistDatabase(account: account)
            }
        )
    }

    private func applyPublishCommand(
        _ command: HomeTimelinePublishCommand
    ) {
        switch command {
        case .applyContentSnapshot(let snapshot):
            applyContentSnapshot(snapshot)
        case .reloadNewestProjectionWindow(let account):
            reloadNewestProjectionWindow(account: account)
        case .materializeEntries:
            materializeEntries()
        case .setPhase(let phase):
            applyActivityTransition(activityCoordinator.setPhase(phase))
        case .requestImmediateOutboxDrain:
            outboxCoordinator.requestImmediateDrain()
        }
    }

    private func activateOutbox(accountID: String) {
        outboxCoordinator.activate(accountID: accountID) { [weak self] in
            self?.relayStatusRevision &+= 1
        }
    }

    func muteAuthor(of post: TimelinePost) {
        guard let account, let localMutationCoordinator else { return }

        do {
            try localMutationCoordinator.muteAuthor(
                accountID: account.pubkey,
                authorPubkey: post.author.pubkey
            )
            invalidateListEntries()
            materializeEntries()
        } catch {
            applyActivityTransition(
                activityCoordinator.setPhase(.failed("Mute failed: \(error.localizedDescription)"))
            )
        }
    }

    func bookmark(_ post: TimelinePost) {
        guard let account, let localMutationCoordinator else { return }

        do {
            try localMutationCoordinator.bookmarkPost(
                accountID: account.pubkey,
                eventID: post.id
            )
        } catch {
            applyActivityTransition(
                activityCoordinator.setPhase(.failed("Bookmark failed: \(error.localizedDescription)"))
            )
        }
    }

    func isBookmarked(_ post: TimelinePost) -> Bool {
        timelineRepository.isBookmarked(
            eventID: post.id,
            accountID: account?.pubkey
        )
    }

    func listEntries(limit: Int = 500) -> [TimelineFeedEntry] {
        guard let account else { return [] }
        let cacheKey = HomeTimelineListProjectionCache.Key(
            accountID: account.pubkey,
            limit: limit,
            homeContentRevision: resolvedContentRevision
        )
        let readContext = timelineReadContext(applyingHomeFilters: false)
        return listProjectionCache.entries(for: cacheKey) {
            timelineRepository.listEntries(
                limit: limit,
                context: readContext
            )
        }
    }

    func suspendTimelineFilters() {
        guard filterCoordinator.suspend() else { return }
        invalidateListEntries()
        materializeEntries()
    }

    func resumeTimelineFilters() {
        guard filterCoordinator.resume() else { return }
        invalidateListEntries()
        materializeEntries()
    }

    func cancel() {
        accountResetCoordinator.reset(
            context: HomeTimelineAccountResetContext(
                readBoundaryWrite: homeFeedReadBoundaryWrite(),
                resolvedRelays: resolvedRelays
            ),
            handlers: accountResetHandlers()
        )
    }

    func post(eventID: String) -> TimelinePost? {
        timelineRepository.post(
            eventID: eventID,
            context: timelineReadContext()
        )
    }

    func profile(pubkey: String, isCurrentUser: Bool = false) -> UserProfile {
        timelineRepository.profile(
            pubkey: pubkey,
            isCurrentUser: isCurrentUser,
            context: timelineReadContext()
        )
    }

    func profilePosts(pubkey: String, limit: Int = 80) -> [TimelinePost] {
        timelineRepository.profilePosts(
            pubkey: pubkey,
            limit: limit,
            context: timelineReadContext()
        )
    }

    func replyAncestors(for post: TimelinePost, limit: Int = 8) -> [TimelinePost] {
        timelineRepository.replyAncestors(
            for: post,
            limit: limit,
            context: timelineReadContext()
        )
    }

    func replies(for post: TimelinePost, limit: Int = 24) -> [TimelinePost] {
        timelineRepository.replies(
            for: post,
            limit: limit,
            context: timelineReadContext()
        )
    }

    private func load(
        account: NostrAccount,
        lifecycle: HomeTimelineLifecycleToken
    ) async {
        guard lifecycleCoordinator.isCurrent(lifecycle) else { return }
        if relayRuntime != nil {
            await loadRuntimeBootstrap(account: account, lifecycle: lifecycle)
            return
        }

        let outcome = await remoteLoadCoordinator.load(
            .initial(account: account),
            isCurrent: { [weak self] in
                self?.lifecycleCoordinator.isCurrent(lifecycle) == true
            },
            didReceiveStage: { [weak self] stage in
                self?.handleLoadStage(stage, lifecycle: lifecycle)
            },
            didFetch: { [weak self] in
                guard let self else { return }
                applyActivityTransition(activityCoordinator.setPhase(.loadingHome))
            }
        )
        await applyRemoteLoadOutcome(
            outcome,
            operation: .initial,
            account: account,
            lifecycle: lifecycle
        )
    }

    private func loadRuntimeBootstrap(
        account: NostrAccount,
        lifecycle: HomeTimelineLifecycleToken
    ) async {
        guard lifecycleCoordinator.isCurrent(lifecycle) else { return }
        installProvisionalRuntimeBootstrapIfNeeded(account: account)
        let hadCachedBootstrap = lifecycleCoordinator.hasCompletedRuntimeBootstrap
        if hadCachedBootstrap, !resolvedRelays.isEmpty {
            await configureRelayRuntime(account: account)
            guard !Task.isCancelled,
                  lifecycleCoordinator.isCurrent(lifecycle)
            else { return }
        } else {
            applyActivityTransition(activityCoordinator.setPhase(.resolvingRelays))
        }

        let outcome = await remoteLoadCoordinator.load(
            .runtimeBootstrap(account: account),
            isCurrent: { [weak self] in
                self?.lifecycleCoordinator.isCurrent(lifecycle) == true
            },
            didReceiveStage: { [weak self] stage in
                self?.handleLoadStage(stage, lifecycle: lifecycle)
            },
            didFetch: { [weak self] in
                guard let self else { return }
                applyActivityTransition(activityCoordinator.setPhase(.loadingHome))
            }
        )
        await applyRemoteLoadOutcome(
            outcome,
            operation: .runtimeBootstrap(hadCachedBootstrap: hadCachedBootstrap),
            account: account,
            lifecycle: lifecycle
        )
    }

    private func handleLoadStage(
        _ stage: NostrHomeTimelineLoadStage,
        lifecycle: HomeTimelineLifecycleToken
    ) {
        guard !Task.isCancelled,
              lifecycleCoordinator.isCurrent(lifecycle)
        else { return }
        switch stage {
        case .resolvingRelayList:
            applyActivityTransition(activityCoordinator.setPhase(.resolvingRelays))
        case .resolvingContactList:
            applyActivityTransition(activityCoordinator.setPhase(.resolvingContacts))
        case .loadingTimeline:
            applyActivityTransition(activityCoordinator.setPhase(.loadingHome))
        }
    }

    private func refreshLatest(
        account: NostrAccount,
        lifecycle: HomeTimelineLifecycleToken
    ) async {
        guard lifecycleCoordinator.isCurrent(lifecycle) else { return }
        guard !noteEvents.isEmpty else {
            start(account: account)
            return
        }

        guard let activityTransition = activityCoordinator.beginRefresh() else { return }
        applyActivityTransition(activityTransition)
        defer {
            if lifecycleCoordinator.isCurrent(lifecycle) {
                applyActivityTransition(activityCoordinator.endRefresh())
            }
        }

        if relayRuntime != nil {
            await configureRelayRuntime(account: account)
            guard !Task.isCancelled,
                  lifecycleCoordinator.isCurrent(lifecycle)
            else { return }
            applyActivityTransition(activityCoordinator.setPhase(.loaded))
            return
        }

        let outcome = await remoteLoadCoordinator.load(
            .refresh(account: account, current: loaderState()),
            isCurrent: { [weak self] in
                self?.lifecycleCoordinator.isCurrent(lifecycle) == true
            }
        )
        await applyRemoteLoadOutcome(
            outcome,
            operation: .refresh,
            account: account,
            lifecycle: lifecycle
        )
    }

    private func loadOlder(
        account: NostrAccount,
        lifecycle: HomeTimelineLifecycleToken
    ) async {
        guard lifecycleCoordinator.isCurrent(lifecycle) else { return }
        guard let activityTransition = activityCoordinator.beginLoadingOlder() else { return }
        applyActivityTransition(activityTransition)
        defer {
            if lifecycleCoordinator.isCurrent(lifecycle) {
                applyActivityTransition(activityCoordinator.endLoadingOlder())
            }
        }

        if relayRuntime != nil {
            let outcome = await backwardRequestCoordinator.requestOlder(
                account: account
            )
            _ = applyBackwardRequestOutcome(outcome)
            guard !Task.isCancelled,
                  lifecycleCoordinator.isCurrent(lifecycle)
            else { return }
            applyActivityTransition(activityCoordinator.setPhase(.loaded))
            return
        }

        let current = loaderState()
        let localBackfillEvents = databaseBackfillEvents(account: account, current: current)
        let outcome = await remoteLoadCoordinator.load(
            .older(
                account: account,
                current: current,
                localBackfillEvents: localBackfillEvents
            ),
            isCurrent: { [weak self] in
                self?.lifecycleCoordinator.isCurrent(lifecycle) == true
            }
        )
        await applyRemoteLoadOutcome(
            outcome,
            operation: .older,
            account: account,
            lifecycle: lifecycle
        )
    }

    private func applyRemoteLoadOutcome(
        _ outcome: HomeTimelineRemoteLoadOutcome,
        operation: HomeTimelineLoadOperation,
        account: NostrAccount,
        lifecycle: HomeTimelineLifecycleToken
    ) async {
        await loadApplicationCoordinator.apply(
            outcome,
            context: HomeTimelineLoadApplicationContext(
                account: account,
                lifecycle: lifecycle,
                operation: operation,
                resolvedRelays: resolvedRelays
            ),
            handlers: remoteLoadApplicationHandlers()
        )
    }

    private func remoteLoadApplicationHandlers() -> HomeTimelineLoadApplicationHandlers {
        HomeTimelineLoadApplicationHandlers(
            perform: { [weak self] command in
                self?.performRemoteLoadApplicationCommand(command)
            },
            persistDatabase: { [weak self] account in
                await self?.persistDatabase(account: account)
            },
            configureRelayRuntime: { [weak self] account in
                await self?.configureRelayRuntime(account: account)
            }
        )
    }

    private func performRemoteLoadApplicationCommand(
        _ command: HomeTimelineLoadApplicationCommand
    ) {
        switch command {
        case .replaceState(let state, let replacement):
            switch replacement {
            case .complete:
                replaceTimelineState(state)
            case .runtimeBootstrap:
                replaceTimelineState(contentCoordinator.runtimeBootstrapState(
                    from: state,
                    nip05Resolutions: dependencyCoordinator.nip05Resolutions
                ))
            }
        case .replaceFollowedPubkeys(let pubkeys):
            applyContentSnapshot(contentCoordinator.replaceFollowedPubkeys(pubkeys))
        case .materializeEntries:
            materializeEntries()
        case .recordDiagnostic(let diagnostic):
            recordRuntimeSyncEvent(
                relayURL: diagnostic.relayURL,
                kind: diagnostic.kind,
                subscriptionID: diagnostic.subscriptionID,
                message: diagnostic.message
            )
        case .setPhase(let phase):
            applyActivityTransition(activityCoordinator.setPhase(phase))
        }
    }

    private func applyBackwardRequestOutcome(
        _ outcome: HomeTimelineBackwardRequestOutcome
    ) -> NostrFeedDefinitionRecord? {
        switch outcome {
        case .unavailable:
            return nil
        case .installed(let definition):
            return definition
        case .failed(let diagnostic):
            recordRuntimeSyncEvent(
                relayURL: diagnostic.relayURL,
                kind: .partialFailure,
                subscriptionID: diagnostic.subscriptionID,
                message: diagnostic.message
            )
            return nil
        }
    }

    private func timelineEvent(id: String) -> NostrEvent? {
        noteEvents.first { $0.id == id } ?? timelineRepository.event(id: id)
    }

    @discardableResult
    private func restoreCachedSnapshot(account: NostrAccount) -> Bool {
        stateApplicationCoordinator.restoreCachedState(
            accountID: account.pubkey,
            handlers: stateApplicationHandlers()
        )
    }

    private func persistDatabase(account: NostrAccount) async {
        await persistenceCoordinator.persistSnapshot(
            HomeTimelineSnapshotInput(
                accountID: account.pubkey,
                relays: resolvedRelays,
                followedPubkeys: followedPubkeys,
                noteEvents: noteEvents,
                metadataEvents: metadataEvents,
                relayListEvent: relayListEvent,
                contactListEvent: contactListEvent,
                nip05Resolutions: dependencyCoordinator.nip05Resolutions,
                hasMoreOlder: hasMoreOlder
            ),
            handlers: persistenceHandlers()
        )
    }

    private func persistTimelineMetadata(account: NostrAccount) async {
        await persistenceCoordinator.persistMetadata(
            HomeTimelineMetadataSnapshot(
                accountID: account.pubkey,
                relays: resolvedRelays,
                followedPubkeys: followedPubkeys,
                nip05Resolutions: dependencyCoordinator.nip05Resolutions,
                hasMoreOlder: hasMoreOlder
            ),
            handlers: persistenceHandlers()
        )
    }

    private func persistenceHandlers() -> HomeTimelinePersistenceHandlers {
        HomeTimelinePersistenceHandlers(
            state: { [unowned self] in persistenceState() },
            hasPendingEvents: { [unowned self] in
                !pendingEventBuffer.isEmpty
            },
            perform: { [weak self] command in
                self?.applyPersistenceCommand(command)
            }
        )
    }

    private func persistenceState() -> HomeTimelinePersistenceState {
        HomeTimelinePersistenceState(
            accountID: account?.pubkey,
            followedPubkeys: followedPubkeys
        )
    }

    private func applyPersistenceCommand(
        _ command: HomeTimelinePersistenceCommand
    ) {
        switch command {
        case .materializeEntries:
            materializeEntries()
        }
    }

    private func ensureHomeFeedDefinition(account: NostrAccount) {
        homeFeedProjection.ensureDefinition(
            accountID: account.pubkey,
            followedPubkeys: followedPubkeys,
            liveEvents: noteEvents
        )
    }

    private func isCurrentHomeFeedContext(_ context: HomeFeedRuntimeContext?) -> Bool {
        homeFeedProjection.isCurrent(context, accountID: account?.pubkey)
    }

    private func restoreHomeFeedReadState(account: NostrAccount) {
        guard let definition = homeFeedProjection.definition,
              definition.accountID == account.pubkey
        else { return }
        let positions = entries.compactMap(\.post).map { post in
            HomeTimelineReadPosition(postID: post.id, createdAt: post.createdAt)
        }
        let boundaryID = readStateCoordinator.restoredReadBoundaryPostID(
            feedID: definition.feedID,
            positions: positions
        )
        guard let boundaryID else { return }
        applyPresentationTransition(
            presentationCoordinator.restoreReadBoundary(postID: boundaryID)
        )
    }

    private func scheduleHomeFeedReadStateSave() {
        guard let write = homeFeedReadBoundaryWrite() else { return }
        readStateCoordinator.scheduleReadBoundarySave(write)
    }

    private func homeFeedReadBoundaryWrite() -> HomeTimelineReadBoundaryWrite? {
        guard let account,
              let definition = homeFeedProjection.definition,
              definition.accountID == account.pubkey
        else { return nil }

        let boundaryID = presentationCoordinator.readBoundaryPostID
        let boundaryEvent = boundaryID.flatMap(timelineEvent(id:))
        let readBoundary = boundaryEvent.map {
            NostrTimelineEntryCursor(sortTimestamp: $0.createdAt, eventID: $0.id)
        }
        return HomeTimelineReadBoundaryWrite(
            scopeID: account.pubkey,
            feedID: definition.feedID,
            boundary: readBoundary,
            updatedAt: Int(Date().timeIntervalSince1970)
        )
    }

    private func reloadNewestProjectionWindow(account: NostrAccount) {
        materializationCoordinator.reloadNewestProjection(account: account)
    }

    @discardableResult
    private func reloadProjectionWindow(
        account: NostrAccount,
        around anchorEventID: String?,
        mergingWithCurrentWindow: Bool = false
    ) -> Bool {
        materializationCoordinator.reloadProjection(
            account: account,
            around: anchorEventID,
            mergingWithCurrentWindow: mergingWithCurrentWindow
        )
    }

    private func applyRestoreProjectionAnchorIfPossible(account: NostrAccount) {
        guard let restoreProjectionAnchorEventID else { return }
        guard reloadProjectionWindow(account: account, around: restoreProjectionAnchorEventID) else { return }
        materializeEntries()
        scheduleLinkPreviewResolution()
        if !entries.isEmpty {
            applyActivityTransition(activityCoordinator.setPhase(.loaded))
        }
    }

    private func startRuntimeSession() {
        let profileRelayURLs = account.map(runtimeRelayURLs(account:)) ?? []
        runtimeSessionCoordinator.start(
            HomeTimelineRuntimeSessionRequest(
                account: account,
                profileRelayURLs: profileRelayURLs,
                hasRelayRuntime: relayRuntime != nil,
                isTerminating: runtimeShutdownCoordinator.isTerminating
            ),
            handlers: HomeTimelineRuntimeSessionHandlers(
                isAccountCurrent: { [weak self] accountID in
                    self?.account?.pubkey == accountID
                },
                handlePacket: { [weak self] packet in
                    await self?.handleRuntimePacket(packet)
                },
                eventApplication: runtimeEventApplicationHandlers(),
                perform: { [weak self] command in
                    self?.applyRuntimeSessionCommand(command)
                }
            )
        )
    }

    private func applyRuntimeSessionCommand(
        _ command: HomeTimelineRuntimeSessionCommand
    ) {
        switch command {
        case .profileDirectoryChanged:
            invalidateListEntries()
            scheduleMaterializeEntries()
        }
    }

    private func accountStartHandlers() -> HomeTimelineAccountStartHandlers {
        HomeTimelineAccountStartHandlers(
            state: { [unowned self] in accountStartState() },
            perform: { [weak self] command in
                self?.applyAccountStartCommand(command)
            },
            restoreCachedSnapshot: { [weak self] account in
                self?.restoreCachedSnapshot(account: account) ?? false
            },
            restoredViewport: { [weak self] accountID in
                self?.restoredViewportState(accountID: accountID, timelineKey: "home")
                    .map { HomeTimelineRestoredViewport(anchorEventID: $0.anchorPostID) }
            },
            load: { [weak self] account, lifecycle in
                await self?.load(account: account, lifecycle: lifecycle)
            }
        )
    }

    private func accountStartState() -> HomeTimelineAccountStartState {
        HomeTimelineAccountStartState(
            accountID: account?.pubkey,
            syncPolicy: syncPolicy,
            restoreProjectionAnchorEventID: restoreProjectionAnchorEventID,
            hasEntries: !entries.isEmpty,
            hasResolvedRelays: !resolvedRelays.isEmpty
        )
    }

    private func applyAccountStartCommand(
        _ command: HomeTimelineAccountStartCommand
    ) {
        switch command {
        case .cancelCurrentAccount:
            cancel()
        case .setAccount(let account, let syncPolicy):
            self.account = account
            self.syncPolicy = syncPolicy
        case .startRuntimeSession:
            startRuntimeSession()
        case .ensureHomeFeedDefinition(let account):
            ensureHomeFeedDefinition(account: account)
        case .applyRestoredViewport(let viewport):
            restoreProjectionAnchorEventID = viewport.anchorEventID
            isTimelineAtNewestWindow = false
        case .reloadNewestProjectionWindow(let account):
            reloadNewestProjectionWindow(account: account)
        case .materializeEntries:
            materializeEntries()
        case .applyRestoreProjectionAnchor(let account):
            applyRestoreProjectionAnchorIfPossible(account: account)
        case .installProvisionalRuntimeBootstrap(let account):
            installProvisionalRuntimeBootstrapIfNeeded(account: account)
        case .restoreHomeFeedReadState(let account):
            restoreHomeFeedReadState(account: account)
        case .setPhase(let phase):
            applyActivityTransition(activityCoordinator.setPhase(phase))
        case .activateOutbox(let accountID):
            activateOutbox(accountID: accountID)
        }
    }

    private func accountResetHandlers() -> HomeTimelineAccountResetHandlers {
        HomeTimelineAccountResetHandlers(
            applyPresentationTransition: { [weak self] transition in
                self?.applyPresentationTransition(transition)
            },
            clearPendingEvents: { [weak self] in
                self?.clearPendingNewEvents()
            },
            applyActivityTransition: { [weak self] transition in
                self?.applyActivityTransition(transition)
            },
            invalidateListEntries: { [weak self] in
                self?.invalidateListEntries()
            },
            resetRealtimeState: { [weak self] in
                self?.resetHomeTimelineRealtime()
            },
            applyContentSnapshot: { [weak self] snapshot in
                self?.applyContentSnapshot(snapshot)
            },
            applyRelayStatusSnapshot: { [weak self] snapshot in
                self?.applyRelayStatusSnapshot(snapshot)
            },
            resetProjectionRestoreState: { [weak self] in
                self?.resetProjectionRestoreState()
            },
            clearPublishedAccountState: { [weak self] in
                self?.clearPublishedAccountState()
            },
            scheduleRuntimeShutdown: { [weak self] cancellationGeneration in
                guard let self else { return }
                runtimeShutdownCoordinator.schedule(
                    cancellationGeneration: cancellationGeneration,
                    handlers: runtimeShutdownHandlers()
                )
            }
        )
    }

    private func resetProjectionRestoreState() {
        restoreProjectionAnchorEventID = nil
        isTimelineAtNewestWindow = true
    }

    private func clearPublishedAccountState() {
        relayStatusRevision &+= 1
        account = nil
    }

    private func runtimeShutdownHandlers() -> HomeTimelineRuntimeShutdownHandlers {
        HomeTimelineRuntimeShutdownHandlers(
            currentAccount: { [weak self] in self?.account },
            perform: { [weak self] command in
                await self?.applyRuntimeShutdownCommand(command)
            }
        )
    }

    private func applyRuntimeShutdownCommand(
        _ command: HomeTimelineRuntimeShutdownCommand
    ) async {
        switch command {
        case .resetRuntimeState:
            runtimeSetupCoordinator.reset()
            resetHomeTimelineRealtime()
        case .startRuntimeSession:
            startRuntimeSession()
        case .configureRuntime(let account, let forceInstall):
            await configureRelayRuntime(account: account, forceInstall: forceInstall)
        }
    }

    private func installProvisionalRuntimeBootstrapIfNeeded(account: NostrAccount) {
        guard relayRuntime != nil, resolvedRelays.isEmpty else { return }
        let provisionalRelays = provisionalDiscoveryRelays(for: account)
        guard !provisionalRelays.isEmpty else { return }
        applyContentSnapshot(
            contentCoordinator.installProvisionalRelays(provisionalRelays)
        )
        updateRelayStatusCounts()
    }

    private func provisionalDiscoveryRelays(for account: NostrAccount) -> [String] {
        normalizedRelayURLs(account.discoveryRelays + remoteLoadCoordinator.bootstrapRelays)
            .dedupedPreservingOrder()
    }

    private func normalizedRelayURLs(_ relays: [String]) -> [String] {
        relays.compactMap { raw in
            var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if value.hasPrefix("https://") {
                value = "wss://" + value.dropFirst("https://".count)
            } else if value.hasPrefix("http://") {
                value = "ws://" + value.dropFirst("http://".count)
            } else if !value.hasPrefix("wss://") && !value.hasPrefix("ws://") {
                value = "wss://\(value)"
            }
            guard let url = URL(string: value), url.scheme == "wss" || url.scheme == "ws", url.host != nil else {
                return nil
            }
            return value
        }
    }

    private func configureRelayRuntime(account: NostrAccount, forceInstall: Bool = false) async {
        await runtimeSetupCoordinator.configure(
            HomeTimelineRuntimeSetupRequest(
                account: account,
                defaultRelayURLs: runtimeRelayURLs(account: account),
                policy: syncPolicy,
                hasRelayRuntime: relayRuntime != nil,
                isTerminating: runtimeShutdownCoordinator.isTerminating,
                forceInstall: forceInstall
            ),
            handlers: HomeTimelineRuntimeSetupHandlers(
                perform: { [weak self] command in
                    self?.applyRuntimeSetupCommand(command)
                }
            )
        )
    }

    private func applyRuntimeSetupCommand(
        _ command: HomeTimelineRuntimeSetupCommand
    ) {
        switch command {
        case .setRealtime(let isRealtime):
            publishHomeTimelineRealtimeState(isRealtime)
        case .recordDiagnostic(let diagnostic):
            recordRuntimeSyncEvent(
                relayURL: diagnostic.relayURL,
                kind: .partialFailure,
                subscriptionID: diagnostic.subscriptionID,
                message: diagnostic.message
            )
        }
    }

    private func runtimeRelayURLs(account: NostrAccount) -> [String] {
        Array(
            normalizedRelayURLs(
                resolvedRelays + account.discoveryRelays + remoteLoadCoordinator.bootstrapRelays
            )
            .dedupedPreservingOrder()
            .prefix(10)
        )
    }

    private func resetHomeTimelineRealtime(
        expecting runtimeKeys: Set<RuntimeSubscriptionKey> = []
    ) {
        feedSyncCoordinator.prepareForwardSubscriptions(runtimeKeys)
        publishHomeTimelineRealtimeState()
    }

    private func invalidateHomeTimelineRealtime(for key: RuntimeSubscriptionKey) {
        guard HomeTimelineSyncPlanner.isHomeForwardSubscription(key.subscriptionID) else { return }
        feedSyncCoordinator.invalidateForwardSubscription(key)
        publishHomeTimelineRealtimeState()
    }

    private func invalidateHomeTimelineRealtime(relayURL: String) {
        feedSyncCoordinator.invalidateForwardSubscriptions(relayURL: relayURL)
        publishHomeTimelineRealtimeState()
    }

    private func publishHomeTimelineRealtimeState() {
        publishHomeTimelineRealtimeState(feedSyncCoordinator.isRealtime)
    }

    private func publishHomeTimelineRealtimeState(_ nextIsRealtime: Bool) {
        applyActivityTransition(
            activityCoordinator.setRealtime(nextIsRealtime)
        )
    }

    private func handleRuntimePacket(_ packet: NostrRelayRuntimePacket) async {
        let application = runtimePacketCoordinator.handle(
            packet,
            context: runtimePacketContext(
                isActive: activityCoordinator.snapshot.phase != .idle
            )
        )
        guard application.wasHandled else { return }
        applyRuntimePacketState(application)
        switch application.action {
        case .event(let relayURL, let subscriptionID, let event):
            await handleRuntimeEvent(
                relayURL: relayURL,
                subscriptionID: subscriptionID,
                event: event
            )
        case .backwardCompleted(let completion):
            handleBackwardCompletion(completion)
        case nil:
            break
        }
    }

    private func runtimePacketContext(isActive: Bool) -> HomeTimelineRuntimePacketContext {
        HomeTimelineRuntimePacketContext(
            isActive: isActive,
            accountID: account?.pubkey,
            resolvedRelays: resolvedRelays,
            isCurrentFeedContext: { [weak self] context in
                self?.isCurrentHomeFeedContext(context) == true
            }
        )
    }

    private func applyRuntimePacketState(
        _ application: HomeTimelineRuntimePacketApplication
    ) {
        if let realtimeState = application.realtimeState {
            publishHomeTimelineRealtimeState(realtimeState)
        }
        applyRelayStatusTransition(application.relayStatusTransition)
    }

    private func handleRuntimeEvent(relayURL: String, subscriptionID: String, event: NostrEvent) async {
        let receivedWhileRealtime = activityCoordinator.snapshot.isRealtime
        await runtimeEventCoordinator.handle(
            HomeTimelineRuntimeEventRequest(
                relayURL: relayURL,
                subscriptionID: subscriptionID,
                event: event,
                account: account,
                hasRelayRuntime: relayRuntime != nil,
                receivedWhileRealtime: receivedWhileRealtime
            ),
            handlers: HomeTimelineRuntimeEventHandlers(
                presentationState: { [self] receivedWhileRealtime in
                    HomeTimelineRuntimeEventPresentationState(
                        receivedWhileRealtime: receivedWhileRealtime,
                        hasRestoreProjectionAnchor: restoreProjectionAnchorEventID != nil,
                        isTimelineAtNewestWindow: isTimelineAtNewestWindow,
                        hasPendingEvents: !pendingEventBuffer.isEmpty
                    )
                },
                isAccountCurrent: { [self] accountID in
                    account?.pubkey == accountID
                },
                application: runtimeEventApplicationHandlers(),
                perform: { [weak self] command in
                    self?.applyRuntimeEventCommand(command)
                }
            )
        )
    }

    private func applyRuntimeEventCommand(
        _ command: HomeTimelineRuntimeEventCommand
    ) {
        switch command {
        case .recordDiagnostic(let diagnostic):
            recordRuntimeSyncEvent(
                relayURL: diagnostic.relayURL,
                kind: .partialFailure,
                subscriptionID: diagnostic.subscriptionID,
                message: diagnostic.message
            )
        case .scheduleLinkPreviewResolution:
            scheduleLinkPreviewResolution()
        }
    }

    private func runtimeEventApplicationContext(
        account: NostrAccount,
        lifecycle: HomeTimelineLifecycleToken
    ) -> HomeTimelineRuntimeEventApplicationContext {
        HomeTimelineRuntimeEventApplicationContext(
            account: account,
            lifecycle: lifecycle,
            hasRelayRuntime: relayRuntime != nil
        )
    }

    private func runtimeEventApplicationHandlers() -> HomeTimelineRuntimeEventApplicationHandlers {
        HomeTimelineRuntimeEventApplicationHandlers(
            listRevisionChanged: { [weak self] revision in
                self?.listContentRevision = revision
            },
            pendingCountChanged: { [weak self] count in
                self?.setUnmaterializedNewCount(count)
            },
            perform: { [weak self] command in
                self?.applyRuntimeEventApplicationCommand(command)
            },
            persistTimelineMetadata: { [weak self] account in
                await self?.persistTimelineMetadata(account: account)
            },
            sourceInstallFailed: { [weak self] message in
                guard let self else { return }
                recordRuntimeSyncEvent(
                    relayURL: resolvedRelays.first ?? "runtime",
                    kind: .partialFailure,
                    subscriptionID: nil,
                    message: "backward enqueue failed: \(message)"
                )
            }
        )
    }

    private func applyRuntimeEventApplicationCommand(
        _ command: HomeTimelineRuntimeEventApplicationCommand
    ) {
        switch command {
        case .reloadProjection(let anchorEventID, let materialization):
            guard let account else { return }
            _ = reloadProjectionWindow(account: account, around: anchorEventID)
            switch materialization {
            case .scheduled(let allowsRealtimeFollow):
                scheduleMaterializeEntries(allowsRealtimeFollow: allowsRealtimeFollow)
            case .immediate:
                materializeEntries()
            }
        case .requestNewestProjectionReloadAndSchedule(let allowsRealtimeFollow):
            presentationCoordinator.requestNewestProjectionReload()
            scheduleMaterializeEntries(allowsRealtimeFollow: allowsRealtimeFollow)
        case .scheduleMaterialization(let schedule):
            switch schedule {
            case .standard:
                scheduleMaterializeEntries()
            case .deferredDependencies:
                scheduleMaterializeEntries(
                    delayNanoseconds: presentationCoordinator.defaultDelayNanoseconds * 2
                )
            }
        }
    }

    private func enqueueBackwardDependencies(for event: NostrEvent) async {
        guard let account,
              let lifecycle = lifecycleCoordinator.token(for: account.pubkey)
        else { return }
        _ = await runtimeEventCoordinator.enqueueDependencies(
            for: event,
            context: runtimeEventApplicationContext(
                account: account,
                lifecycle: lifecycle
            ),
            handlers: runtimeEventApplicationHandlers()
        )
    }

    private func resolveNIP05IfNeeded(for metadataEvent: NostrEvent) {
        guard let account,
              let lifecycle = lifecycleCoordinator.token(for: account.pubkey)
        else { return }
        runtimeEventCoordinator.resolveNIP05IfNeeded(
            for: metadataEvent,
            context: runtimeEventApplicationContext(
                account: account,
                lifecycle: lifecycle
            ),
            handlers: runtimeEventApplicationHandlers()
        )
    }

    private func handleBackwardCompletion(_ completion: NostrBackwardREQCompletion) {
        let commands = backwardCompletionApplicationCoordinator.handle(
            completion,
            accountID: account?.pubkey
        )
        for command in commands {
            applyBackwardCompletionCommand(command)
        }
    }

    private func applyBackwardCompletionCommand(
        _ command: HomeTimelineBackwardCompletionCommand
    ) {
        switch command {
        case .applyContentSnapshot(let snapshot):
            applyContentSnapshot(snapshot)
        case .recordDiagnostic(let diagnostic):
            recordRuntimeSyncEvent(
                relayURL: diagnostic.relayURL,
                kind: .partialFailure,
                subscriptionID: nil,
                message: diagnostic.message
            )
        case .reloadProjection(let anchorEventID, let mergingWithCurrentWindow):
            guard let account else { return }
            reloadProjectionWindow(
                account: account,
                around: anchorEventID,
                mergingWithCurrentWindow: mergingWithCurrentWindow
            )
            materializeEntries()
            scheduleLinkPreviewResolution()
        case .reconcileGap(let gap, let context):
            guard let account else { return }
            gapReconciliationApplicationCoordinator.start(
                gap,
                feedContext: context,
                account: account,
                handlers: gapReconciliationApplicationHandlers()
            )
        case .incrementRelayStatusRevision:
            relayStatusRevision &+= 1
        }
    }

    private func gapReconciliationApplicationHandlers()
        -> HomeTimelineGapReconciliationApplicationHandlers {
        HomeTimelineGapReconciliationApplicationHandlers(
            perform: { [weak self] command in
                self?.applyGapReconciliationApplicationCommand(command)
            },
            resolveDependencies: { [weak self] event, context in
                guard let self else { return false }
                return await runtimeEventCoordinator.enqueueDependencies(
                    for: event,
                    context: runtimeEventApplicationContext(
                        account: context.account,
                        lifecycle: context.lifecycle
                    ),
                    handlers: runtimeEventApplicationHandlers()
                )
            }
        )
    }

    private func applyGapReconciliationApplicationCommand(
        _ command: HomeTimelineGapReconciliationApplicationCommand
    ) {
        switch command {
        case .incrementRelayStatusRevision:
            relayStatusRevision &+= 1
        case .recordDiagnostic(let diagnostic):
            recordRuntimeSyncEvent(
                relayURL: diagnostic.relayURL,
                kind: .partialFailure,
                subscriptionID: diagnostic.subscriptionID,
                message: diagnostic.message
            )
        case .reloadProjection(let anchorEventID):
            guard let account else { return }
            reloadProjectionWindow(account: account, around: anchorEventID)
            materializeEntries()
            scheduleLinkPreviewResolution()
        }
    }

    private func scheduleLinkPreviewResolution() {
        guard let accountID = account?.pubkey else { return }
        linkPreviewCoordinator.schedule(
            scopeID: accountID,
            policy: syncPolicy,
            didUpdate: { [weak self] in
                self?.invalidateListEntries()
                self?.scheduleMaterializeEntries()
            },
            didFail: { [weak self] message in
                self?.recordRuntimeSyncEvent(
                    relayURL: "link-preview",
                    kind: .partialFailure,
                    subscriptionID: nil,
                    message: "link preview save failed: \(message)"
                )
            }
        )
    }

    private func recordRuntimeSyncEvent(
        relayURL: String,
        kind: NostrRelaySyncEventKind,
        subscriptionID: String?,
        eventCount: Int = 0,
        newestCreatedAt: Int? = nil,
        oldestCreatedAt: Int? = nil,
        message: String?
    ) {
        guard let account else { return }
        applyRelayStatusTransition(
            relayStatusCoordinator.record(
                accountID: account.pubkey,
                resolvedRelays: resolvedRelays,
                relayURL: relayURL,
                kind: kind,
                subscriptionID: subscriptionID,
                eventCount: eventCount,
                newestCreatedAt: newestCreatedAt,
                oldestCreatedAt: oldestCreatedAt,
                message: message
            )
        )
    }

    private func databaseBackfillEvents(account: NostrAccount, current: NostrHomeTimelineState) -> [NostrEvent]? {
        timelineRepository.olderBackfillEvents(
            accountID: account.pubkey,
            followedPubkeys: current.followedPubkeys,
            currentEvents: current.noteEvents,
            limit: 1_000
        )
    }

    private func materializeEntries(allowsRealtimeFollow: Bool = false) {
        guard let transition = materializationCoordinator.materialize(
            HomeTimelineMaterializationRequest(
                account: account,
                nip05Resolutions: dependencyCoordinator.nip05Resolutions,
                profileResolutionStates: dependencyCoordinator.profileResolutionStates,
                policy: syncPolicy,
                allowsRealtimeFollow: allowsRealtimeFollow
            )
        ) else { return }
        applyPresentationTransition(transition)
    }

    private func scheduleMaterializeEntries(
        delayNanoseconds: UInt64? = nil,
        allowsRealtimeFollow: Bool? = nil
    ) {
        presentationCoordinator.schedule(
            delayNanoseconds: delayNanoseconds,
            allowsRealtimeFollow: allowsRealtimeFollow
        ) { [weak self] allowsRealtimeFollow in
            self?.materializeEntries(allowsRealtimeFollow: allowsRealtimeFollow)
        }
    }

    @discardableResult
    private func clearPendingNewEvents() -> Bool {
        pendingEventBuffer.removeAll { [weak self] count in
            self?.setUnmaterializedNewCount(count)
        }
    }

    private func setUnmaterializedNewCount(_ count: Int) {
        guard unmaterializedNewCount != count else { return }
        unmaterializedNewCount = count
    }

    private func loaderState() -> NostrHomeTimelineState {
        contentCoordinator.loaderState(
            nip05Resolutions: dependencyCoordinator.nip05Resolutions,
            relaySyncEvents: relayStatusCoordinator.events
        )
    }

    private func replaceTimelineState(_ state: NostrHomeTimelineState) {
        stateApplicationCoordinator.replace(
            state,
            accountID: account?.pubkey,
            handlers: stateApplicationHandlers()
        )
    }

    private func stateApplicationHandlers() -> HomeTimelineStateApplicationHandlers {
        HomeTimelineStateApplicationHandlers(
            applyPresentationTransition: { [weak self] transition in
                self?.applyPresentationTransition(transition)
            },
            applyContentSnapshot: { [weak self] snapshot in
                self?.applyContentSnapshot(snapshot)
            },
            applyRelayStatusSnapshot: { [weak self] snapshot in
                self?.applyRelayStatusSnapshot(snapshot)
            },
            listRevisionChanged: { [weak self] revision in
                self?.listContentRevision = revision
            },
            pendingCountChanged: { [weak self] count in
                self?.setUnmaterializedNewCount(count)
            }
        )
    }

    @discardableResult
    private func rememberLatestMetadataEvent(
        _ event: NostrEvent,
        consultEventStore: Bool = true
    ) -> NostrEvent {
        runtimeEventCoordinator.rememberLatestMetadataEvent(
            event,
            consultEventStore: consultEventStore,
            handlers: runtimeEventApplicationHandlers()
        )
    }

    private func invalidateListEntries() {
        listContentRevision = listProjectionCache.invalidate()
    }

}

#if DEBUG
extension NostrHomeTimelineStore {
    func testingSetMaterializedPostIDs(_ ids: [TimelinePost.ID]) {
        let testEntries: [TimelineFeedEntry] = ids.map { id in
            .post(TimelinePost(
                id: id,
                author: .unresolved(pubkey: String(repeating: "a", count: 64)),
                avatar: AvatarStyle(
                    primary: .astrenzaAccent,
                    secondary: .astrenzaAttachmentBackground,
                    symbolName: "person.fill",
                    pictureState: .metadataPending,
                    placeholderSeed: id
                ),
                body: id,
                createdAt: TimelineMockClock.referenceNow,
                replyCount: nil,
                boostCount: nil,
                favoriteCount: nil,
                isLocked: false,
                media: nil,
                context: nil
            ))
        }
        applyPresentationTransition(
            presentationCoordinator.replaceEntriesForTesting(
                testEntries,
                renderFingerprint: testEntries.map { $0.id.hashValue }
            )
        )
    }

    func testingSetReadBoundary(postID: TimelinePost.ID) {
        applyPresentationTransition(
            presentationCoordinator.setReadBoundaryForTesting(postID: postID)
        )
    }

    func testingSetUnmaterializedNewEventIDs(_ ids: Set<String>) {
        pendingEventBuffer.replaceEventIDs(ids) { [weak self] count in
            self?.setUnmaterializedNewCount(count)
        }
    }

    func testingMergedProjectionWindow(
        _ current: NostrFeedWindow,
        with loaded: NostrFeedWindow,
        centeredOn anchorEventID: String
    ) -> NostrFeedWindow {
        HomeFeedProjectionBuilder.mergedWindow(
            current,
            with: loaded,
            centeredOn: anchorEventID,
            retainedLimit: homeFeedProjection.retainedWindowLimit
        )
    }

    func testingActivateHomeFeed(
        account: NostrAccount,
        definition: NostrFeedDefinitionRecord,
        sourceAuthors: [String]
    ) {
        if lifecycleCoordinator.token(for: account.pubkey) == nil {
            lifecycleCoordinator.begin(accountID: account.pubkey)
        }
        self.account = account
        applyContentSnapshot(
            contentCoordinator.replaceFollowedPubkeys(sourceAuthors)
        )
        homeFeedProjection.activateStoredProjection(
            definition: definition,
            sourceAuthors: sourceAuthors
        )
    }

    func testingRegisterOlderFeedRequest(
        packet: NostrREQPacket,
        definition: NostrFeedDefinitionRecord,
        anchorEventID: String?
    ) {
        backwardRequestRegistry.registerOlderPage(
            groupID: packet.groupID,
            context: HomeFeedRuntimeContext(definition: definition),
            anchorEventID: anchorEventID
        )
    }

    func testingRegisterForwardFeedRequest(
        packet: NostrREQPacket,
        definition: NostrFeedDefinitionRecord
    ) {
        feedSyncCoordinator.registerForwardContext(
            HomeFeedRuntimeContext(definition: definition),
            groupID: packet.groupID
        )
    }

    func testingRegisterGapFeedRequest(
        packet: NostrREQPacket,
        definition: NostrFeedDefinitionRecord,
        newerEventID: String,
        olderEventID: String,
        direction: TimelineGapFillDirection
    ) {
        backwardRequestRegistry.registerGap(
            groupID: packet.groupID,
            context: HomeFeedRuntimeContext(definition: definition),
            newerEventID: newerEventID,
            olderEventID: olderEventID,
            direction: direction
        )
    }

    func testingHandleFeedSyncRequestStarted(_ attempt: NostrRelayRequestAttempt) {
        let application = runtimePacketCoordinator.handle(
            .requestStarted(attempt),
            context: runtimePacketContext(isActive: true)
        )
        applyRuntimePacketState(application)
    }

    func testingHandleBackwardEvent(
        relayURL: String,
        subscriptionID: String,
        event: NostrEvent
    ) async {
        await handleRuntimeEvent(relayURL: relayURL, subscriptionID: subscriptionID, event: event)
    }

    func testingHandleHomeForwardEvent(
        relayURL: String,
        subscriptionID: String,
        event: NostrEvent
    ) async {
        await handleRuntimeEvent(relayURL: relayURL, subscriptionID: subscriptionID, event: event)
    }

    func testingHandleBackwardCompletion(_ completion: NostrBackwardREQCompletion) {
        handleBackwardCompletion(completion)
    }

    func testingEnqueueBackwardDependencies(for event: NostrEvent) async {
        await enqueueBackwardDependencies(for: event)
    }

    @discardableResult
    func testingEnqueueBackwardDependencies(
        _ dependencies: NostrEventDependencies,
        availableRelayURLs: [String]
    ) -> Bool {
        dependencyCoordinator.enqueueSourceDependencies(
            dependencies,
            cacheSnapshot: NostrDependencyFetchCacheSnapshot(),
            availableRelayURLs: availableRelayURLs,
            now: 0
        )
    }

    func testingFlushBackwardDependencies() {
        dependencyCoordinator.flushSourcePacketInstall(onFailure: { _ in })
    }

    var testingPendingBackwardRequestCount: Int {
        backwardRequestRegistry.requestCount + dependencyCoordinator.pendingSourceRequestCount
    }

    var testingHasPendingDependencyWork: Bool {
        dependencyCoordinator.hasPendingWork
    }

    var testingActiveFeedSyncRequestCount: Int {
        feedSyncCoordinator.activeRequestCount
    }

    var testingActiveFeedSyncContextCount: Int {
        feedSyncCoordinator.activeContextCount
    }
}
#endif

extension NIP05Status {
    init(_ coreStatus: NostrNIP05Status) {
        switch coreStatus {
        case .absent:
            self = .absent
        case .unchecked:
            self = .unchecked
        case .verified:
            self = .valid
        case .invalid, .failed:
            self = .invalid
        }
    }
}

private extension Array where Element == String {
    func dedupedPreservingOrder() -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for value in self where seen.insert(value).inserted {
            result.append(value)
        }
        return result
    }
}
