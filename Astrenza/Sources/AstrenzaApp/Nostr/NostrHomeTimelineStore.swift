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
    private let eventStore: NostrEventStore?
    private let contentCoordinator: HomeTimelineContentCoordinator
    private let runtimeEventProcessor: HomeTimelineRuntimeEventProcessor
    private let runtimeEventApplicationCoordinator: HomeTimelineRuntimeEventApplicationCoordinator
    private let backwardCompletionApplicationCoordinator: HomeTimelineBackwardCompletionApplicationCoordinator
    private let backfillPersistence: HomeTimelineBackfillPersistence
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
    private let runtimeEventPump: HomeTimelineRuntimeEventPump
    private let relayRuntimeConfigurator: HomeTimelineRelayRuntimeConfigurator
    private let relayRuntimeTerminator: HomeTimelineRelayRuntimeTerminator
    private let relayStatusCoordinator: HomeTimelineRelayStatusCoordinator
    private let linkPreviewCoordinator: HomeTimelineLinkPreviewCoordinator
    private let readStateCoordinator: HomeTimelineReadStateCoordinator
    private let syncPlanner: HomeTimelineSyncPlanner
    private let timelineRepository: HomeTimelineRepository
    private let timelineCoordinator: HomeTimelineCoordinator
    private let gapReconciliationCoordinator: HomeTimelineGapReconciliationCoordinator
    private let homeFeedProjection: HomeFeedProjectionController
    private let snapshotCoordinator: HomeTimelineSnapshotCoordinator
    private let publishCoordinator: HomeTimelinePublishCoordinator?
    private let localMutationCoordinator: HomeTimelineLocalMutationCoordinator?
    private let relayRuntime: NostrRelayRuntime?
    private let outboxCoordinator: HomeTimelineOutboxCoordinator
    private let syncPolicySettingsStore: NostrSyncPolicySettingsStore
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
        if let relayRuntime {
            sourcePacketInstaller = { packets in
                try await relayRuntime.installBackward(packets, mergeField: .ids)
            }
        } else {
            sourcePacketInstaller = nil
        }
        let backfillPersistence = HomeTimelineBackfillPersistence(eventStore: eventStore)
        self.backfillPersistence = backfillPersistence
        self.syncPlanner = syncPlanner
        let timelineRepository = HomeTimelineRepository(eventStore: eventStore)
        self.timelineRepository = timelineRepository
        self.timelineCoordinator = HomeTimelineCoordinator()
        self.gapReconciliationCoordinator = HomeTimelineGapReconciliationCoordinator(
            reconciler: HomeTimelineGapReconciler(
                eventStore: eventStore,
                relayClient: timelineLoader.relayClient
            ),
            persistence: backfillPersistence
        )
        let homeFeedProjection = HomeFeedProjectionController(eventStore: eventStore)
        self.homeFeedProjection = homeFeedProjection
        self.snapshotCoordinator = HomeTimelineSnapshotCoordinator(
            eventStore: eventStore,
            persistenceWorker: persistenceWorker,
            projectionController: homeFeedProjection
        )
        self.publishCoordinator = eventStore.map(HomeTimelinePublishCoordinator.init)
        self.localMutationCoordinator = (localMutationPersistence ?? eventStore).map {
            HomeTimelineLocalMutationCoordinator(persistence: $0)
        }
        let backwardRequestRegistry = HomeTimelineBackwardRequestRegistry()
        self.backwardRequestRegistry = backwardRequestRegistry
        let feedSyncCoordinator = HomeTimelineFeedSyncCoordinator(
            eventStore: eventStore,
            backwardRequestRegistry: backwardRequestRegistry
        )
        self.feedSyncCoordinator = feedSyncCoordinator
        self.runtimeEventProcessor = HomeTimelineRuntimeEventProcessor(
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
        self.activityCoordinator = HomeTimelineActivityCoordinator()
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
        self.runtimeEventApplicationCoordinator = HomeTimelineRuntimeEventApplicationCoordinator(
            contentCoordinator: contentCoordinator,
            dependencyCoordinator: dependencyCoordinator,
            listProjectionCache: listProjectionCache,
            pendingEventBuffer: pendingEventBuffer,
            backwardRequestRegistry: backwardRequestRegistry,
            lifecycleCoordinator: lifecycleCoordinator
        )
        let runtimeEventPump = HomeTimelineRuntimeEventPump()
        self.runtimeEventPump = runtimeEventPump
        self.relayRuntimeConfigurator = HomeTimelineRelayRuntimeConfigurator(
            relayRuntime: relayRuntime,
            runtimeEventPump: runtimeEventPump,
            dependencyCoordinator: dependencyCoordinator,
            syncPlanner: syncPlanner
        )
        self.relayRuntimeTerminator = HomeTimelineRelayRuntimeTerminator()
        let relayStatusCoordinator = HomeTimelineRelayStatusCoordinator(
            diagnostics: HomeTimelineRelayDiagnosticsLedger(
                eventStore: eventStore,
                persistenceWorker: persistenceWorker
            )
        )
        self.relayStatusCoordinator = relayStatusCoordinator
        self.remoteLoadCoordinator = HomeTimelineRemoteLoadCoordinator(
            loader: timelineLoader,
            relayEventPersistence: relayStatusCoordinator
        )
        self.linkPreviewCoordinator = HomeTimelineLinkPreviewCoordinator(
            eventStore: eventStore,
            resolver: linkPreviewResolver
        )
        self.readStateCoordinator = HomeTimelineReadStateCoordinator(
            eventStore: eventStore,
            persistenceWorker: persistenceWorker
        )
        self.outboxCoordinator = HomeTimelineOutboxCoordinator(
            drainer: HomeTimelineOutboxDrainer(
                eventStore: eventStore,
                publisher: outboxPublisher
            )
        )
        self.syncPolicySettingsStore = syncPolicySettingsStore
        self.syncPolicy = syncPolicy
    }

    func start(account: NostrAccount) {
        let isSameAccount = self.account?.pubkey == account.pubkey
        if isSameAccount {
            startRuntimeEventPump()
            activateOutbox(accountID: account.pubkey)
            return
        }
        if let currentAccount = self.account,
           currentAccount.pubkey != account.pubkey {
            cancel()
        }
        let lifecycle = lifecycleCoordinator.begin(accountID: account.pubkey)
        self.account = account
        syncPolicy = syncPolicySettingsStore.policy(accountID: account.pubkey, fallback: syncPolicy)
        startRuntimeEventPump()
        lifecycleCoordinator.setRuntimeBootstrapCompleted(
            restoreCachedSnapshot(account: account),
            for: lifecycle
        )
        ensureHomeFeedDefinition(account: account)
        if restoreProjectionAnchorEventID == nil,
           let viewportState = restoredViewportState(accountID: account.pubkey, timelineKey: "home") {
            restoreProjectionAnchorEventID = viewportState.anchorPostID
            isTimelineAtNewestWindow = false
        }
        if restoreProjectionAnchorEventID == nil {
            reloadNewestProjectionWindow(account: account)
            materializeEntries()
        } else {
            applyRestoreProjectionAnchorIfPossible(account: account)
        }
        installProvisionalRuntimeBootstrapIfNeeded(account: account)
        restoreHomeFeedReadState(account: account)
        if relayRuntime != nil,
           lifecycleCoordinator.hasCompletedRuntimeBootstrap,
           !resolvedRelays.isEmpty {
            applyActivityTransition(activityCoordinator.setPhase(.loaded))
        } else if relayRuntime != nil || entries.isEmpty {
            applyActivityTransition(activityCoordinator.setPhase(.resolvingRelays))
        }
        lifecycleCoordinator.startLoad(for: lifecycle) { [weak self] in
            await self?.load(account: account, lifecycle: lifecycle)
        }
        activateOutbox(accountID: account.pubkey)
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
        guard let account,
              relayRuntime != nil,
              !resolvedRelays.isEmpty
        else { return false }

        let installed = await requestGapNotesThroughRuntime(account: account, gap: gap, direction: direction)
        if installed, let definition = homeFeedProjection.definition {
            try? backfillPersistence.markGapRequested(
                newerEventID: gap.newerPostID,
                olderEventID: gap.olderPostID,
                definition: definition
            )
            _ = reloadProjectionWindow(account: account, around: gap.newerPostID)
            materializeEntries()
        }
        return installed
    }

    func enqueuePublish(_ input: NostrPublishInput, signer: any NostrEventSigning) async throws {
        guard let account, let publishCoordinator else { return }
        let writeRelays = NostrRelayList.parse(from: relayListEvent).writeRelays
        let publish = try await publishCoordinator.prepare(
            input,
            accountID: account.pubkey,
            accountWriteRelays: writeRelays,
            fallbackRelays: resolvedRelays,
            signer: signer
        )
        guard self.account?.pubkey == publish.accountID else { return }

        ensureHomeFeedDefinition(account: account)
        let event = try publishCoordinator.persist(
            publish,
            feedDefinition: homeFeedProjection.definition
        )
        applyContentSnapshot(
            contentCoordinator.insertOutboxEvent(
                event,
                accountID: account.pubkey
            )
        )
        reloadNewestProjectionWindow(account: account)
        materializeEntries()
        await persistDatabase(account: account)
        applyActivityTransition(activityCoordinator.setPhase(.loaded))
        outboxCoordinator.requestImmediateDrain()
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
        readStateCoordinator.endSession(flushing: homeFeedReadBoundaryWrite())
        relayStatusCoordinator.flushTraffic()
        let cancellationGeneration = lifecycleCoordinator.cancel()
        runtimeEventPump.cancel()
        linkPreviewCoordinator.reset()
        applyPresentationTransition(presentationCoordinator.reset())
        outboxCoordinator.cancel()
        dependencyCoordinator.reset()
        backwardRequestRegistry.reset()
        clearPendingNewEvents()
        applyActivityTransition(activityCoordinator.reset())
        invalidateListEntries()
        homeFeedProjection.reset()
        relayRuntimeConfigurator.reset()
        resetHomeTimelineRealtime()
        feedSyncCoordinator.reset(finishingActiveRequestsWith: .cancelled)
        applyContentSnapshot(contentCoordinator.reset())
        applyRelayStatusSnapshot(
            relayStatusCoordinator.reset(resolvedRelays: resolvedRelays)
        )
        restoreProjectionAnchorEventID = nil
        isTimelineAtNewestWindow = true
        filterCoordinator.reset()
        relayStatusRevision &+= 1
        account = nil
        scheduleRelayRuntimeTermination(cancellationGeneration: cancellationGeneration)
    }

    private func scheduleRelayRuntimeTermination(cancellationGeneration: UInt64) {
        guard let relayRuntime else { return }
        relayRuntimeTerminator.schedule(
            termination: { [weak self] in
                await self?.dependencyCoordinator.stopProfileUpdates()
                await relayRuntime.terminate()
            },
            onLatestCompletion: { [weak self] in
                guard let self,
                      lifecycleCoordinator.currentToken?.generation != cancellationGeneration,
                      let account
                else { return }

                runtimeEventPump.cancel()
                relayRuntimeConfigurator.reset()
                resetHomeTimelineRealtime()
                startRuntimeEventPump()
                await configureRelayRuntime(account: account, forceInstall: true)
            }
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
        switch outcome {
        case .loaded(let state):
            apply(state)
            materializeEntries()
            await persistDatabase(account: account)
            guard !Task.isCancelled,
                  lifecycleCoordinator.isCurrent(lifecycle)
            else { return }
            await configureRelayRuntime(account: account)
            guard lifecycleCoordinator.isCurrent(lifecycle) else { return }
            applyActivityTransition(activityCoordinator.setPhase(.loaded))
        case .cancelled:
            return
        case .failed(let message):
            applyActivityTransition(
                activityCoordinator.setPhase(.failed("Home timeline failed: \(message)"))
            )
        }
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
        switch outcome {
        case .loaded(let bootstrapState):
            apply(runtimeBootstrapState(from: bootstrapState))
            lifecycleCoordinator.setRuntimeBootstrapCompleted(true, for: lifecycle)
            materializeEntries()
            await persistDatabase(account: account)
            guard !Task.isCancelled,
                  lifecycleCoordinator.isCurrent(lifecycle)
            else { return }
            await configureRelayRuntime(account: account)
            guard lifecycleCoordinator.isCurrent(lifecycle) else { return }
            applyActivityTransition(activityCoordinator.setPhase(.loaded))
        case .cancelled:
            return
        case .failed(let message):
            recordRuntimeSyncEvent(
                relayURL: resolvedRelays.first ?? "runtime",
                kind: .partialFailure,
                subscriptionID: "astrenza-bootstrap",
                message: "bootstrap refresh failed: \(message)"
            )
            if hadCachedBootstrap {
                applyActivityTransition(activityCoordinator.setPhase(.loaded))
            } else if !resolvedRelays.isEmpty {
                applyContentSnapshot(
                    contentCoordinator.replaceFollowedPubkeys([account.pubkey])
                )
                lifecycleCoordinator.setRuntimeBootstrapCompleted(true, for: lifecycle)
                await configureRelayRuntime(account: account)
                applyActivityTransition(activityCoordinator.setPhase(.loaded))
            } else {
                applyActivityTransition(
                    activityCoordinator.setPhase(.failed("Home timeline failed: \(message)"))
                )
            }
        }
    }

    private func runtimeBootstrapState(from bootstrapState: NostrHomeTimelineState) -> NostrHomeTimelineState {
        contentCoordinator.runtimeBootstrapState(
            from: bootstrapState,
            nip05Resolutions: dependencyCoordinator.nip05Resolutions
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
        switch outcome {
        case .loaded(let state):
            apply(state)
            materializeEntries()
            await persistDatabase(account: account)
            guard !Task.isCancelled,
                  lifecycleCoordinator.isCurrent(lifecycle)
            else { return }
            await configureRelayRuntime(account: account)
            guard lifecycleCoordinator.isCurrent(lifecycle) else { return }
            applyActivityTransition(activityCoordinator.setPhase(.loaded))
        case .cancelled:
            return
        case .failed(let message):
            applyActivityTransition(
                activityCoordinator.setPhase(.failed("Refresh failed: \(message)"))
            )
        }
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
            await requestOlderNotesThroughRuntime(account: account)
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
        switch outcome {
        case .loaded(let state):
            apply(state)
            if !state.hasMoreOlder {
                return
            }

            materializeEntries()
            await persistDatabase(account: account)
            guard !Task.isCancelled,
                  lifecycleCoordinator.isCurrent(lifecycle)
            else { return }
            await configureRelayRuntime(account: account)
            guard lifecycleCoordinator.isCurrent(lifecycle) else { return }
            applyActivityTransition(activityCoordinator.setPhase(.loaded))
        case .cancelled:
            return
        case .failed(let message):
            applyActivityTransition(
                activityCoordinator.setPhase(.failed("Older notes failed: \(message)"))
            )
        }
    }

    private func requestOlderNotesThroughRuntime(account: NostrAccount) async {
        guard let relayRuntime,
              let oldestCreatedAt = noteEvents.map(\.createdAt).min()
        else { return }
        ensureHomeFeedDefinition(account: account)
        guard let feedContext = activeHomeFeedRuntimeContext() else { return }
        let olderAnchorPostID = noteEvents.last?.id

        guard let packet = syncPlanner.olderNotesPacket(
            account: account,
            followedPubkeys: followedPubkeys,
            oldestCreatedAt: oldestCreatedAt,
            relayURLs: resolvedRelays
        ) else { return }

        backwardRequestRegistry.registerOlderPage(
            groupID: packet.groupID,
            context: feedContext,
            anchorEventID: olderAnchorPostID
        )

        do {
            try await relayRuntime.installBackward([packet], mergeField: .authors)
        } catch {
            backwardRequestRegistry.remove(groupID: packet.groupID)
            recordRuntimeSyncEvent(
                relayURL: resolvedRelays.first ?? "runtime",
                kind: .partialFailure,
                subscriptionID: packet.subscriptionID,
                message: "older enqueue failed: \(error.localizedDescription)"
            )
        }
    }

    private func requestGapNotesThroughRuntime(
        account: NostrAccount,
        gap: TimelineGap,
        direction: TimelineGapFillDirection
    ) async -> Bool {
        guard let relayRuntime,
              let newerEvent = timelineEvent(id: gap.newerPostID),
              let olderEvent = timelineEvent(id: gap.olderPostID)
        else { return false }
        ensureHomeFeedDefinition(account: account)
        guard let feedContext = activeHomeFeedRuntimeContext() else { return false }

        guard let packet = syncPlanner.gapNotesPacket(
            account: account,
            followedPubkeys: followedPubkeys,
            newerEvent: newerEvent,
            olderEvent: olderEvent,
            missingEstimate: gap.missingEstimate,
            relayURLs: resolvedRelays
        ) else { return false }

        backwardRequestRegistry.registerGap(
            groupID: packet.groupID,
            context: feedContext,
            newerEventID: gap.newerPostID,
            olderEventID: gap.olderPostID,
            direction: direction
        )

        do {
            try await relayRuntime.installBackward([packet], mergeField: .authors)
            return true
        } catch {
            backwardRequestRegistry.remove(groupID: packet.groupID)
            recordRuntimeSyncEvent(
                relayURL: resolvedRelays.first ?? "runtime",
                kind: .partialFailure,
                subscriptionID: packet.subscriptionID,
                message: "gap enqueue failed: \(error.localizedDescription)"
            )
            return false
        }
    }

    private func timelineEvent(id: String) -> NostrEvent? {
        if let event = noteEvents.first(where: { $0.id == id }) {
            return event
        }
        return timelineRepository.event(id: id)
    }

    @discardableResult
    private func restoreCachedSnapshot(account: NostrAccount) -> Bool {
        if let databaseState = snapshotCoordinator.restoredState(accountID: account.pubkey) {
            apply(databaseState)
            return true
        }

        applyPresentationTransition(presentationCoordinator.reset())
        applyContentSnapshot(contentCoordinator.reset())
        dependencyCoordinator.replaceNIP05Resolutions([:])
        applyRelayStatusSnapshot(
            relayStatusCoordinator.reset(resolvedRelays: resolvedRelays)
        )
        clearPendingNewEvents()
        return false
    }

    private func persistDatabase(account: NostrAccount) async {
        guard let lifecycle = lifecycleCoordinator.token(for: account.pubkey) else { return }
        guard let receipt = await snapshotCoordinator.persistSnapshot(
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
            )
        ) else { return }
        guard !Task.isCancelled,
              lifecycleCoordinator.isCurrent(lifecycle),
              self.account?.pubkey == account.pubkey,
              snapshotCoordinator.activatePersistedSnapshot(
                receipt,
                accountID: account.pubkey,
                followedPubkeys: followedPubkeys
              )
        else { return }
        if pendingEventBuffer.isEmpty {
            materializeEntries()
        }
    }

    private func persistTimelineMetadata(account: NostrAccount) async {
        guard let lifecycle = lifecycleCoordinator.token(for: account.pubkey) else { return }
        let didPersist = await snapshotCoordinator.persistMetadata(
            HomeTimelineMetadataSnapshot(
                accountID: account.pubkey,
                relays: resolvedRelays,
                followedPubkeys: followedPubkeys,
                nip05Resolutions: dependencyCoordinator.nip05Resolutions,
                hasMoreOlder: hasMoreOlder
            )
        )
        guard didPersist,
              lifecycleCoordinator.isCurrent(lifecycle),
              self.account?.pubkey == account.pubkey
        else { return }
    }

    private func ensureHomeFeedDefinition(account: NostrAccount) {
        homeFeedProjection.ensureDefinition(
            accountID: account.pubkey,
            followedPubkeys: followedPubkeys,
            liveEvents: noteEvents
        )
    }

    private func activeHomeFeedRuntimeContext() -> HomeFeedRuntimeContext? {
        homeFeedProjection.runtimeContext()
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

    private func startRuntimeEventPump() {
        startProfileDirectoryEventPump()
        guard let relayRuntime,
              !relayRuntimeTerminator.isTerminating,
              let accountID = account?.pubkey,
              let lifecycle = lifecycleCoordinator.token(for: accountID)
        else { return }
        runtimeEventPump.start(
            stream: { await relayRuntime.events() },
            isSourceCurrent: { [weak self] in
                self?.lifecycleCoordinator.isCurrent(lifecycle) == true &&
                    self?.account?.pubkey == accountID
            },
            onPacket: { [weak self] packet in
                await self?.handleRuntimePacket(packet)
            }
        )
    }

    private func startProfileDirectoryEventPump() {
        guard !relayRuntimeTerminator.isTerminating,
              let account
        else { return }
        let relayURLs = runtimeRelayURLs(account: account)
        dependencyCoordinator.startProfileUpdates(relayURLs: relayURLs) { [weak self] update in
            self?.handleProfileDirectoryUpdate(update)
        }
    }

    private func handleProfileDirectoryUpdate(_ update: NostrProfileDirectoryUpdate) {
        guard account != nil else { return }
        for event in update.metadataEvents {
            let effectiveEvent = rememberLatestMetadataEvent(event, consultEventStore: false)
            resolveNIP05IfNeeded(for: effectiveEvent)
        }
        if !update.states.isEmpty || !update.metadataEvents.isEmpty {
            invalidateListEntries()
            scheduleMaterializeEntries()
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
        guard relayRuntime != nil,
              !relayRuntimeTerminator.isTerminating,
              self.account?.pubkey == account.pubkey,
              lifecycleCoordinator.hasCompletedRuntimeBootstrap,
              !resolvedRelays.isEmpty,
              let identity = currentRelayRuntimeConfigurationIdentity(),
              identity.accountID == account.pubkey
        else { return }

        let request = HomeTimelineRelayRuntimeConfigurationRequest(
            identity: identity,
            account: account,
            contactItems: NostrContactList.items(from: contactListEvent),
            defaultRelayURLs: runtimeRelayURLs(account: account),
            policy: syncPolicy,
            forceInstall: forceInstall
        )
        await relayRuntimeConfigurator.configure(
            request,
            handlers: HomeTimelineRelayRuntimeConfigurationHandlers(
                currentIdentity: { [weak self] in
                    self?.currentRelayRuntimeConfigurationIdentity()
                },
                prepareDependencies: { [weak self] in
                    guard let self else { return }
                    await ensureProfileDirectoryDependencies(for: noteEvents)
                },
                prepareFeed: { [weak self] in
                    guard let self else { return nil }
                    ensureHomeFeedDefinition(account: account)
                    guard let context = activeHomeFeedRuntimeContext() else { return nil }
                    return HomeTimelineRelayRuntimeFeedPreparation(
                        context: context,
                        newestCreatedAt: noteEvents.map(\.createdAt).max(),
                        newestCreatedAtByRelay: forwardCursorNewestCreatedAtByRelay(
                            accountID: account.pubkey
                        ),
                        initialCreatedAt: noteEvents.map(\.createdAt).min()
                    )
                },
                prepareInstall: { [weak self] packets, runtimeKeys, context in
                    guard let self else { return }
                    resetHomeTimelineRealtime(expecting: runtimeKeys)
                    for packet in packets {
                        feedSyncCoordinator.registerForwardContext(
                            context,
                            groupID: packet.groupID
                        )
                    }
                },
                isFeedContextCurrent: { [weak self] context in
                    self?.isCurrentHomeFeedContext(context) == true
                },
                didFail: { [weak self] message in
                    self?.recordRuntimeSyncEvent(
                        relayURL: identity.resolvedRelays.first ?? "runtime",
                        kind: .partialFailure,
                        subscriptionID: NostrHomeForwardREQBuilder.subscriptionID,
                        message: message
                    )
                }
            )
        )
    }

    private func currentRelayRuntimeConfigurationIdentity()
        -> HomeTimelineRelayRuntimeConfigurationIdentity? {
        guard let account,
              let lifecycle = lifecycleCoordinator.token(for: account.pubkey)
        else { return nil }
        return HomeTimelineRelayRuntimeConfigurationIdentity(
            accountID: account.pubkey,
            lifecycleGeneration: lifecycle.generation,
            resolvedRelays: resolvedRelays,
            followedPubkeys: followedPubkeys,
            contactListEventID: contactListEvent?.id
        )
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

    private func applyFeedSyncTransition(_ transition: HomeTimelineFeedSyncTransition) {
        publishHomeTimelineRealtimeState(transition.isRealtime)
        let diagnostic = transition.diagnostic
        recordRuntimeSyncEvent(
            relayURL: diagnostic.relayURL,
            kind: diagnostic.kind,
            subscriptionID: diagnostic.subscriptionID,
            eventCount: diagnostic.eventCount,
            newestCreatedAt: diagnostic.newestCreatedAt,
            oldestCreatedAt: diagnostic.oldestCreatedAt,
            message: diagnostic.message
        )
    }

    private func forwardCursorNewestCreatedAtByRelay(accountID: String) -> [String: Int]? {
        timelineRepository.newestCreatedAtByRelay(
            accountID: accountID,
            timelineKey: "home",
            relayURLs: resolvedRelays
        )
    }

    private func handleRuntimePacket(_ packet: NostrRelayRuntimePacket) async {
        guard !Self.isProfileDirectoryPacket(packet) else { return }
        await timelineCoordinator.handleRuntimePacket(
            packet,
            handlers: HomeTimelineRuntimePacketHandlers(
                shouldHandle: { self.activityCoordinator.snapshot.phase != .idle },
                stateChanged: { relayURL, state in
                    self.handleRuntimeStateChange(relayURL: relayURL, state: state)
                },
                requestStarted: { attempt in
                    self.handleFeedSyncRequestStarted(attempt)
                },
                requestInstalled: { requestID, _, _, installedAt in
                    self.feedSyncCoordinator.recordRequestInstalled(
                        requestID: requestID,
                        installedAt: installedAt
                    )
                },
                requestEnded: { end in
                    self.feedSyncCoordinator.endRequestAttempt(end)
                    self.publishHomeTimelineRealtimeState()
                },
                event: { relayURL, subscriptionID, event in
                    await self.handleRuntimeEvent(
                        relayURL: relayURL,
                        subscriptionID: subscriptionID,
                        event: event
                    )
                },
                eose: { relayURL, subscriptionID in
                    self.applyFeedSyncTransition(
                        self.feedSyncCoordinator.handleStreamCompletion(
                            relayURL: relayURL,
                            subscriptionID: subscriptionID,
                            completion: .eose
                        )
                    )
                },
                closed: { relayURL, subscriptionID, message in
                    self.applyFeedSyncTransition(
                        self.feedSyncCoordinator.handleStreamCompletion(
                            relayURL: relayURL,
                            subscriptionID: subscriptionID,
                            completion: .closed(message: message)
                        )
                    )
                },
                timeout: { relayURL, subscriptionID, message in
                    self.applyFeedSyncTransition(
                        self.feedSyncCoordinator.handleStreamCompletion(
                            relayURL: relayURL,
                            subscriptionID: subscriptionID,
                            completion: .timeout(message: message)
                        )
                    )
                },
                backwardCompleted: { completion in
                    self.handleBackwardCompletion(completion)
                },
                traffic: { delta in
                    self.relayStatusCoordinator.recordTraffic(delta)
                },
                notice: { relayURL, message in
                    self.applyRelayStatusTransition(
                        self.relayStatusCoordinator.handleNotice(
                            accountID: self.account?.pubkey,
                            resolvedRelays: self.resolvedRelays,
                            relayURL: relayURL,
                            message: message
                        )
                    )
                },
                auth: { relayURL, challenge in
                    self.applyRelayStatusTransition(
                        self.relayStatusCoordinator.handleAuthenticationChallenge(
                            accountID: self.account?.pubkey,
                            resolvedRelays: self.resolvedRelays,
                            relayURL: relayURL,
                            challenge: challenge
                        )
                    )
                }
            )
        )
    }

    private func handleRuntimeStateChange(relayURL: String, state: NostrRelayConnectionState) {
        applyRelayStatusTransition(
            relayStatusCoordinator.handleRuntimeStateChange(
                accountID: account?.pubkey,
                resolvedRelays: resolvedRelays,
                relayURL: relayURL,
                state: state
            )
        )
    }

    private static func isProfileDirectoryPacket(_ packet: NostrRelayRuntimePacket) -> Bool {
        switch packet {
        case .requestStarted(let attempt):
            NostrProfileDirectory.handles(groupID: attempt.packet.groupID)
        case .requestInstalled(_, _, let subscriptionID, _),
             .event(_, let subscriptionID, _),
             .eose(_, let subscriptionID),
             .closed(_, let subscriptionID, _),
             .timeout(_, let subscriptionID, _):
            NostrProfileDirectory.handles(subscriptionID: subscriptionID)
        case .requestEnded(let end):
            NostrProfileDirectory.handles(subscriptionID: end.subscriptionID)
        case .backwardCompleted(let completion):
            NostrProfileDirectory.handles(groupID: completion.groupID)
        case .stateChanged, .traffic, .notice, .auth:
            false
        }
    }

    private func handleRuntimeEvent(relayURL: String, subscriptionID: String, event: NostrEvent) async {
        guard let account,
              let lifecycle = lifecycleCoordinator.token(for: account.pubkey)
        else { return }
        let accountID = account.pubkey
        let receivedWhileRealtime = activityCoordinator.snapshot.isRealtime
        let outcome = await runtimeEventProcessor.process(
            relayURL: relayURL,
            subscriptionID: subscriptionID,
            event: event,
            forwardPresentationState: { [self] in
                HomeTimelineRuntimeEventPresentationState(
                    receivedWhileRealtime: receivedWhileRealtime,
                    hasRestoreProjectionAnchor: restoreProjectionAnchorEventID != nil,
                    isTimelineAtNewestWindow: isTimelineAtNewestWindow,
                    hasPendingEvents: !pendingEventBuffer.isEmpty
                )
            },
            ensureFeedDefinition: { [self] in
                ensureHomeFeedDefinition(account: account)
            },
            activeFeedContext: { [self] in
                activeHomeFeedRuntimeContext()
            }
        )
        switch outcome {
        case .ignored:
            return
        case .persistenceFailed(let message):
            recordRuntimeSyncEvent(
                relayURL: relayURL,
                kind: .partialFailure,
                subscriptionID: subscriptionID,
                message: message
            )
            return
        case .processed(let result):
            guard lifecycleCoordinator.isCurrent(lifecycle),
                  self.account?.pubkey == accountID
            else { return }
            guard await applyRuntimeEventApplicationPlan(
                result.applicationPlan,
                account: account,
                backwardRequestKey: result.backwardRequestKey,
                lifecycle: lifecycle
            ) else { return }
            scheduleLinkPreviewResolution()
            feedSyncCoordinator.record(
                event,
                relayURL: relayURL,
                subscriptionID: subscriptionID
            )
        }
    }

    private func applyRuntimeEventApplicationPlan(
        _ plan: HomeTimelineRuntimeEventApplicationPlan,
        account: NostrAccount,
        backwardRequestKey: String?,
        lifecycle: HomeTimelineLifecycleToken
    ) async -> Bool {
        await runtimeEventApplicationCoordinator.apply(
            plan,
            backwardRequestKey: backwardRequestKey,
            context: runtimeEventApplicationContext(
                account: account,
                lifecycle: lifecycle
            ),
            handlers: runtimeEventApplicationHandlers()
        )
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
        _ = await runtimeEventApplicationCoordinator.enqueueDependencies(
            for: event,
            context: runtimeEventApplicationContext(
                account: account,
                lifecycle: lifecycle
            ),
            handlers: runtimeEventApplicationHandlers()
        )
    }

    private func ensureProfileDirectoryDependencies(for events: [NostrEvent]) async {
        await dependencyCoordinator.ensureProfiles(for: events)
    }

    private func resolveNIP05IfNeeded(for metadataEvent: NostrEvent) {
        guard let account,
              let lifecycle = lifecycleCoordinator.token(for: account.pubkey)
        else { return }
        runtimeEventApplicationCoordinator.resolveNIP05IfNeeded(
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
            reconcileCompletedGap(gap, context: context)
        case .incrementRelayStatusRevision:
            relayStatusRevision &+= 1
        }
    }

    private func reconcileCompletedGap(
        _ gap: PendingGapBackfill,
        context: HomeFeedRuntimeContext
    ) {
        guard let accountID = account?.pubkey,
              accountID == context.accountID,
              let lifecycle = lifecycleCoordinator.token(for: accountID),
              isCurrentHomeFeedContext(context)
        else { return }
        let reconciliationID = backwardRequestRegistry.beginGapReconciliation(
            gap: gap,
            context: context
        )
        relayStatusRevision &+= 1

        Task { [weak self] in
            await self?.runCompletedGapReconciliation(
                gap,
                reconciliationID: reconciliationID,
                accountID: accountID,
                lifecycle: lifecycle,
                context: context
            )
        }
    }

    private func runCompletedGapReconciliation(
        _ gap: PendingGapBackfill,
        reconciliationID: String,
        accountID: String,
        lifecycle: HomeTimelineLifecycleToken,
        context: HomeFeedRuntimeContext
    ) async {
        defer {
            if lifecycleCoordinator.isCurrent(lifecycle),
               self.account?.pubkey == accountID {
                backwardRequestRegistry.endGapReconciliation(reconciliationID)
                relayStatusRevision &+= 1
            }
        }

        guard lifecycleCoordinator.isCurrent(lifecycle),
              let account,
              account.pubkey == accountID,
              isCurrentHomeFeedContext(context),
              let newerEvent = timelineEvent(id: gap.newerPostID),
              let olderEvent = timelineEvent(id: gap.olderPostID)
        else { return }

        let execution = await gapReconciliationCoordinator.reconcile(
            newerEvent: newerEvent,
            olderEvent: olderEvent,
            gap: gap,
            context: context,
            relays: resolvedRelays,
            inMemoryEvents: noteEvents
        )
        guard lifecycleCoordinator.isCurrent(lifecycle),
              self.account?.pubkey == accountID,
              isCurrentHomeFeedContext(context)
        else { return }
        for diagnostic in execution.diagnostics {
            recordRuntimeSyncEvent(
                relayURL: diagnostic.relayURL,
                kind: .partialFailure,
                subscriptionID: diagnostic.subscriptionID,
                message: diagnostic.message
            )
        }
        for event in execution.recoveredEvents {
            await enqueueBackwardDependencies(for: event)
            guard lifecycleCoordinator.isCurrent(lifecycle),
                  self.account?.pubkey == accountID,
                  isCurrentHomeFeedContext(context)
            else { return }
        }

        guard execution.reloadsProjection,
              lifecycleCoordinator.isCurrent(lifecycle),
              self.account?.pubkey == accountID,
              isCurrentHomeFeedContext(context)
        else { return }
        reloadProjectionWindow(account: account, around: gap.stableAnchorPostID)
        materializeEntries()
        scheduleLinkPreviewResolution()
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

    private func handleFeedSyncRequestStarted(_ attempt: NostrRelayRequestAttempt) {
        let result = feedSyncCoordinator.startRequest(
            attempt,
            isCurrentFeedContext: { [weak self] context in
                self?.isCurrentHomeFeedContext(context) == true
            }
        )
        guard result.wasHandled else { return }
        publishHomeTimelineRealtimeState(result.isRealtime)
        if let failureMessage = result.failureMessage {
            recordRuntimeSyncEvent(
                relayURL: attempt.relayURL,
                kind: .partialFailure,
                subscriptionID: attempt.packet.subscriptionID,
                message: "feed sync request save failed: \(failureMessage)"
            )
        }
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

    private func apply(_ state: NostrHomeTimelineState) {
        applyContentSnapshot(
            contentCoordinator.replace(
                with: state,
                accountID: account?.pubkey
            )
        )
        dependencyCoordinator.replaceNIP05Resolutions(state.nip05Resolutions)
        applyRelayStatusSnapshot(
            relayStatusCoordinator.replaceEvents(
                state.relaySyncEvents,
                resolvedRelays: resolvedRelays
            )
        )
        homeFeedProjection.clearWindow()
        invalidateListEntries()
    }

    @discardableResult
    private func rememberLatestMetadataEvent(
        _ event: NostrEvent,
        consultEventStore: Bool = true
    ) -> NostrEvent {
        runtimeEventApplicationCoordinator.rememberLatestMetadataEvent(
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
        handleFeedSyncRequestStarted(attempt)
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
