import Foundation
import AstrenzaCore
import SwiftUI

struct TimelineFilterStatus: Equatable {
    var activeRuleCount = 0
    var warningMatchCount = 0
    var hiddenMatchCount = 0
    var isSuspended = false

    var matchedPostCount: Int {
        warningMatchCount + hiddenMatchCount
    }

    var isVisible: Bool {
        activeRuleCount > 0 || isSuspended
    }
}

struct NostrTimelineActivityStatus: Equatable {
    let title: String
    let detail: String
    let compactLabel: String
}

enum NostrHomeTimelineStoreError: Error, Equatable {
    case noPublishRelayDestinations
}

@MainActor
final class NostrHomeTimelineStore: ObservableObject {
    enum Phase: Equatable {
        case idle
        case resolvingRelays
        case resolvingContacts
        case loadingHome
        case loaded
        case failed(String)

        var copy: String {
            switch self {
            case .idle:
                "Preparing Home timeline"
            case .resolvingRelays:
                "Resolving kind:10002 relay list"
            case .resolvingContacts:
                "Resolving kind:3 contact list"
            case .loadingHome:
                "Connecting Home relays"
            case .loaded:
                "Home timeline loaded"
            case .failed(let message):
                message
            }
        }

    }

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

    private let timelineLoader: NostrHomeTimelineLoader
    private let eventStore: NostrEventStore?
    private let persistenceWorker: HomeTimelinePersistenceWorker?
    private let eventIngestor: HomeTimelineEventIngestor
    private let dependencyCoordinator: HomeTimelineDependencyResolutionCoordinator
    private let materializationScheduler: HomeTimelineMaterializationScheduler
    private let relayDiagnostics: HomeTimelineRelayDiagnosticsLedger
    private let linkPreviewCoordinator: HomeTimelineLinkPreviewCoordinator
    private let syncPlanner: HomeTimelineSyncPlanner
    private let timelineRepository: HomeTimelineRepository
    private let timelineCoordinator: HomeTimelineCoordinator
    private let gapReconciler: HomeTimelineGapReconciler
    private let homeFeedProjection: HomeFeedProjectionController
    private let relayRuntime: NostrRelayRuntime?
    private let profileDirectory: NostrProfileDirectory?
    private let outboxDrainer: HomeTimelineOutboxDrainer
    private let syncPolicySettingsStore: NostrSyncPolicySettingsStore
    private var syncPolicy: NostrSyncPolicy
    private var loadTask: Task<Void, Never>?
    private var paginationTask: Task<Void, Never>?
    private var runtimeTask: Task<Void, Never>?
    private var profileDirectoryUpdateTask: Task<Void, Never>?
    private var unmaterializedCountTask: Task<Void, Never>?
    private var outboxTask: Task<Void, Never>?
    private var outboxTaskGeneration: UInt64 = 0
    private var feedReadStateTask: Task<Void, Never>?
    private var viewportStateTask: Task<Void, Never>?
    private var pendingViewportState: PendingFeedViewportState?
    private var pendingBackwardRequests: [String: PendingBackwardRequest] = [:]
    private var pendingGapReconciliationIDs = Set<String>()
    private var feedSyncLifecycle: HomeTimelineFeedSyncLifecycle
    private var pendingRelayTrafficDeltas: [NostrRelayTrafficDelta] = []
    private var lastRelayTrafficFlushAt = 0
    private var dependencyFlushTask: Task<Void, Never>?
    private var installedHomeForwardPackets: [NostrREQPacket] = []
    private var noteEvents: [NostrEvent] = []
    private var metadataEvents: [NostrEvent] = []
    private var profileResolutionStates: [String: NostrProfileResolutionState] = [:]
    private var relayListEvent: NostrEvent?
    private var contactListEvent: NostrEvent?
    private var areTimelineFiltersSuspended = false
    private var unmaterializedNewEventIDs = Set<String>()
    private var unreadState = HomeTimelineUnreadState()
    private var isTimelineAtNewestWindow = true
    private var restoreProjectionAnchorEventID: String?
    private var hasCompletedRuntimeBootstrap = false
    private var listEntriesCache: ListEntriesCache?
    private var runtimeLifecycleGeneration: UInt64 = 0
    private var relayRuntimeConfigurationSequence: UInt64 = 0
    private var isRuntimeEventPumpReady = false
    private var runtimeEventPumpReadyWaiters: [CheckedContinuation<Bool, Never>] = []
    private var relayRuntimeTerminationSequence: UInt64 = 0
    private var relayRuntimeTerminationTask: Task<Void, Never>?

    var relayStatusEventStore: NostrEventStore? {
        eventStore
    }

    var currentSyncPolicy: NostrSyncPolicy {
        syncPolicy
    }

    private func updateRelayStatusCounts() {
        setRelayStatusCountsIfNeeded(
            relayDiagnostics.statusCounts(
                resolvedRelays: resolvedRelays,
                runtimeStates: relayRuntimeStates
            )
        )
    }

    private func setRelayStatusCountsIfNeeded(_ counts: (connected: Int, planned: Int)) {
        guard relayStatusCounts.connected != counts.connected ||
            relayStatusCounts.planned != counts.planned
        else { return }
        relayStatusCounts = counts
    }

    var activityStatus: NostrTimelineActivityStatus? {
        switch phase {
        case .resolvingRelays:
            return NostrTimelineActivityStatus(
                title: "Resolving relay list",
                detail: "Looking up kind:10002 on discovery relays",
                compactLabel: "kind:10002"
            )
        case .resolvingContacts:
            return NostrTimelineActivityStatus(
                title: "Resolving contacts",
                detail: "Looking up kind:3 before opening Home",
                compactLabel: "kind:3"
            )
        case .loadingHome:
            return NostrTimelineActivityStatus(
                title: "Connecting Home relays",
                detail: "\(relayStatusCounts.connected) of \(relayStatusCounts.planned) relays ready",
                compactLabel: "Home"
            )
        case .idle, .loaded, .failed:
            break
        }

        if isRefreshing {
            return NostrTimelineActivityStatus(
                title: "Updating Home timeline",
                detail: "Fetching newer events from Home relays",
                compactLabel: "Updating"
            )
        }
        if isLoadingOlder || pendingBackwardRequests.values.contains(where: \.isOlderPage) {
            return NostrTimelineActivityStatus(
                title: "Loading older posts",
                detail: "Fetching the previous Home timeline window",
                compactLabel: "Older"
            )
        }
        if !pendingGapReconciliationIDs.isEmpty ||
            pendingBackwardRequests.values.contains(where: { $0.gap != nil }) {
            return NostrTimelineActivityStatus(
                title: "Filling a timeline gap",
                detail: "Reconciling missing events between local windows",
                compactLabel: "Gap"
            )
        }
        if !pendingBackwardRequests.isEmpty || dependencyCoordinator.hasPendingWork {
            return NostrTimelineActivityStatus(
                title: "Resolving referenced posts",
                detail: "Fetching events referenced by visible posts",
                compactLabel: "Resolving"
            )
        }
        return nil
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
        syncPolicy: NostrSyncPolicy = .default(networkType: .unknown, lowPowerMode: false),
        syncPolicySettingsStore: NostrSyncPolicySettingsStore = .shared
    ) {
        let persistenceWorker = eventStore.map(HomeTimelinePersistenceWorker.init)
        self.timelineLoader = timelineLoader
        self.eventStore = eventStore
        self.persistenceWorker = persistenceWorker
        let eventIngestor = HomeTimelineEventIngestor(eventStore: eventStore)
        let syncPlanner = HomeTimelineSyncPlanner()
        let profileDirectory = relayRuntime.map {
            NostrProfileDirectory(eventStore: eventStore, relayRuntime: $0)
        }
        self.eventIngestor = eventIngestor
        self.syncPlanner = syncPlanner
        self.timelineRepository = HomeTimelineRepository(eventStore: eventStore)
        self.timelineCoordinator = HomeTimelineCoordinator()
        self.gapReconciler = HomeTimelineGapReconciler(
            eventStore: eventStore,
            relayClient: timelineLoader.relayClient
        )
        self.homeFeedProjection = HomeFeedProjectionController(eventStore: eventStore)
        self.feedSyncLifecycle = HomeTimelineFeedSyncLifecycle(eventStore: eventStore)
        self.relayRuntime = relayRuntime
        self.profileDirectory = profileDirectory
        self.dependencyCoordinator = HomeTimelineDependencyResolutionCoordinator(
            eventIngestor: eventIngestor,
            profileDirectory: profileDirectory,
            nip05Resolver: timelineLoader.nip05Resolver,
            syncPlanner: syncPlanner
        )
        self.materializationScheduler = HomeTimelineMaterializationScheduler()
        self.relayDiagnostics = HomeTimelineRelayDiagnosticsLedger(
            eventStore: eventStore,
            persistenceWorker: persistenceWorker
        )
        self.linkPreviewCoordinator = HomeTimelineLinkPreviewCoordinator(
            eventStore: eventStore,
            resolver: linkPreviewResolver
        )
        self.outboxDrainer = HomeTimelineOutboxDrainer(
            eventStore: eventStore,
            publisher: outboxPublisher
        )
        self.syncPolicySettingsStore = syncPolicySettingsStore
        self.syncPolicy = syncPolicy
    }

    func start(account: NostrAccount) {
        let isSameAccount = self.account?.pubkey == account.pubkey
        if isSameAccount {
            startRuntimeEventPump()
            scheduleOutboxDrain()
            return
        }
        if let currentAccount = self.account,
           currentAccount.pubkey != account.pubkey {
            cancel()
        }
        runtimeLifecycleGeneration &+= 1
        self.account = account
        syncPolicy = syncPolicySettingsStore.policy(accountID: account.pubkey, fallback: syncPolicy)
        startRuntimeEventPump()
        hasCompletedRuntimeBootstrap = restoreCachedSnapshot(account: account)
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
        if relayRuntime != nil, hasCompletedRuntimeBootstrap, !resolvedRelays.isEmpty {
            phase = .loaded
        } else if relayRuntime != nil || entries.isEmpty {
            phase = .resolvingRelays
        }
        loadTask?.cancel()
        loadTask = Task {
            await load(account: account)
        }
        scheduleOutboxDrain()
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
        guard timelineKey == "home",
              let state = try? eventStore?.feedReadState(
                feedID: HomeFeedProjectionBuilder.feedID(accountID: accountID)
              ),
              let anchorEventID = state.viewportAnchorEventID
        else { return nil }
        return TimelineViewportState(
            accountID: accountID,
            timelineKey: timelineKey,
            anchorPostID: anchorEventID,
            anchorOffset: state.viewportAnchorOffset,
            contentOffset: 0,
            updatedAt: Date(timeIntervalSince1970: TimeInterval(state.updatedAt))
        )
    }

    func saveViewportState(_ state: TimelineViewportState) {
        guard state.timelineKey == "home",
              let account,
              account.pubkey == state.accountID,
              persistenceWorker != nil,
              let definition = homeFeedProjection.definition
        else { return }

        pendingViewportState = PendingFeedViewportState(
            accountID: account.pubkey,
            feedID: definition.feedID,
            anchorEventID: state.anchorPostID,
            anchorOffset: Double(state.anchorOffset),
            updatedAt: Int(state.updatedAt.timeIntervalSince1970)
        )
        viewportStateTask?.cancel()
        viewportStateTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(600))
            } catch {
                return
            }
            guard let self, !Task.isCancelled else { return }
            await self.persistPendingViewportState()
        }
    }

    func flushPendingViewportStateSave() {
        viewportStateTask?.cancel()
        viewportStateTask = nil
        guard let pendingViewportState, let persistenceWorker else { return }
        self.pendingViewportState = nil
        Task {
            try? await persistenceWorker.saveViewportState(
                feedID: pendingViewportState.feedID,
                anchorEventID: pendingViewportState.anchorEventID,
                anchorOffset: pendingViewportState.anchorOffset,
                updatedAt: pendingViewportState.updatedAt
            )
        }
    }

    func refresh() {
        guard let account else { return }
        restoreProjectionAnchorEventID = nil
        isTimelineAtNewestWindow = true
        paginationTask?.cancel()
        paginationTask = Task {
            await refreshLatest(account: account)
        }
    }

    func refreshLatest() async {
        guard let account else { return }
        await refreshLatest(account: account)
    }

    func setTimelineAtNewestWindow(_ isAtNewestWindow: Bool) {
        guard !isAtNewestWindow || restoreProjectionAnchorEventID == nil else { return }
        isTimelineAtNewestWindow = isAtNewestWindow
    }

    func setTimelineScrollActive(_ isActive: Bool) {
        materializationScheduler.setScrollActive(isActive) { [weak self] allowsRealtimeFollow in
            self?.materializeEntries(allowsRealtimeFollow: allowsRealtimeFollow)
        }
    }

    func dismissUnreadBadge() {
        unreadState.dismissBadge()
        publishUnreadState()
    }

    func markMaterializedPostsRead(visiblePostIDs: [TimelinePost.ID]) {
        let previousState = unreadState
        unreadState.markVisiblePostsRead(visiblePostIDs)
        guard unreadState != previousState else { return }
        publishUnreadState()
        scheduleHomeFeedReadStateSave()
    }

    func markNewestMaterializedWindowRead() {
        guard unreadState.canMarkNewestWindowRead else { return }
        unreadState.markNewestWindowRead()
        publishUnreadState()
        scheduleHomeFeedReadStateSave()
    }

    @discardableResult
    func applyPendingNewEvents() async -> Bool {
        guard let account else { return false }
        let hadPendingNewEvents = !unmaterializedNewEventIDs.isEmpty ||
            materializationScheduler.hasPendingNewestProjectionReload
        restoreProjectionAnchorEventID = nil
        isTimelineAtNewestWindow = true
        reloadNewestProjectionWindow(account: account)
        unmaterializedNewEventIDs.removeAll()
        unmaterializedCountTask?.cancel()
        unmaterializedCountTask = nil
        unmaterializedNewCount = 0
        materializationScheduler.clearNewestProjectionReload()
        materializeEntries()
        scheduleLinkPreviewResolution()
        return hadPendingNewEvents
    }

    func loadOlder() {
        guard let account,
              !isLoadingOlder,
              hasMoreOlder,
              !noteEvents.isEmpty,
              !resolvedRelays.isEmpty,
              !followedPubkeys.isEmpty
        else { return }

        paginationTask?.cancel()
        paginationTask = Task {
            await loadOlder(account: account)
        }
    }

    func backfillGap(_ gap: TimelineGap, direction: TimelineGapFillDirection) async -> Bool {
        guard let account,
              relayRuntime != nil,
              !resolvedRelays.isEmpty
        else { return false }

        let installed = await requestGapNotesThroughRuntime(account: account, gap: gap, direction: direction)
        if installed, let definition = homeFeedProjection.definition {
            try? eventStore?.markFeedGap(
                feedID: definition.feedID,
                revision: definition.revision,
                newerEventID: gap.newerPostID,
                olderEventID: gap.olderPostID,
                state: .requested
            )
            _ = reloadProjectionWindow(account: account, around: gap.newerPostID)
            materializeEntries()
        }
        return installed
    }

    func enqueuePublish(_ input: NostrPublishInput, signer: any NostrEventSigning) async throws {
        guard let account, let eventStore else { return }
        let writeRelays = NostrRelayList.parse(from: relayListEvent).writeRelays
        let relayURLs = writeRelays.isEmpty ? resolvedRelays : writeRelays
        let createdAt = Int(Date().timeIntervalSince1970)
        let unsignedEvent = input.unsignedEvent(pubkey: account.pubkey, createdAt: createdAt)
        let signedEvent = try await signer.sign(unsignedEvent)
        let destinationRelays = NostrPublishDestinationResolver.relayDestinations(
            accountWriteRelays: relayURLs,
            taggedUserReadRelays: [],
            fallbackRelays: resolvedRelays
        )
        guard !destinationRelays.isEmpty else {
            throw NostrHomeTimelineStoreError.noPublishRelayDestinations
        }
        let record = try eventStore.enqueueOutboxEvent(
            signedEvent,
            accountID: account.pubkey,
            relayURLs: destinationRelays,
            createdAt: createdAt
        )

        ensureHomeFeedDefinition(account: account)
        let feedMembership = homeFeedProjection.definition.flatMap { definition in
            HomeFeedProjectionBuilder.memberships(
                events: [record.event],
                feedID: definition.feedID,
                feedRevision: definition.revision,
                reason: "outbox",
                insertedAt: createdAt
            ).first
        }
        let feedMembershipSources = homeFeedProjection.definition.map { definition in
            HomeFeedProjectionBuilder.membershipSources(
                events: [record.event],
                feedID: definition.feedID,
                feedRevision: definition.revision,
                reason: "outbox",
                insertedAt: createdAt
            )
        } ?? []
        try eventStore.ingest(
            events: [record.event],
            eventSources: [],
            feedMemberships: feedMembership.map { [$0] } ?? [],
            feedMembershipSources: feedMembershipSources,
            receivedAt: createdAt
        )
        noteEvents.removeAll { $0.id == record.event.id }
        noteEvents.insert(record.event, at: 0)
        if !followedPubkeys.contains(account.pubkey) {
            followedPubkeys.append(account.pubkey)
        }
        reloadNewestProjectionWindow(account: account)
        materializeEntries()
        await persistDatabase(account: account)
        phase = .loaded
        scheduleOutboxDrain()
    }

    private func scheduleOutboxDrain(delayNanoseconds: UInt64 = 0) {
        if outboxTask != nil {
            guard delayNanoseconds == 0 else { return }
            outboxTask?.cancel()
            outboxTask = nil
        }
        guard account != nil, eventStore != nil else { return }
        outboxTaskGeneration &+= 1
        let taskGeneration = outboxTaskGeneration
        outboxTask = Task { [weak self] in
            guard let self, let accountID = self.account?.pubkey else { return }
            if delayNanoseconds > 0 {
                do {
                    try await Task.sleep(nanoseconds: delayNanoseconds)
                } catch {
                    return
                }
            }
            let result = await self.outboxDrainer.drain(accountID: accountID)
            guard self.outboxTaskGeneration == taskGeneration else { return }
            self.outboxTask = nil
            if result.didRecordRelayResults {
                self.relayStatusRevision &+= 1
            }
            guard !Task.isCancelled,
                  self.account?.pubkey == accountID,
                  let nextRetryAt = result.nextRetryAt
            else { return }
            let now = Int(Date().timeIntervalSince1970)
            let delaySeconds = max(1, nextRetryAt - now)
            self.scheduleOutboxDrain(delayNanoseconds: UInt64(delaySeconds) * 1_000_000_000)
        }
    }

    func muteAuthor(of post: TimelinePost) {
        guard let account, let eventStore else { return }
        let now = Int(Date().timeIntervalSince1970)
        let rule = NostrFilterRuleRecord(
            ruleID: "local:mute-pubkey:\(account.pubkey):\(post.author.pubkey)",
            accountID: account.pubkey,
            kind: .mutedPubkey,
            value: post.author.pubkey,
            createdAt: now,
            updatedAt: now
        )

        do {
            try eventStore.saveFilterRule(rule)
            invalidateListEntries()
            materializeEntries()
        } catch {
            phase = .failed("Mute failed: \(error.localizedDescription)")
        }
    }

    func bookmark(_ post: TimelinePost) {
        guard let account, let eventStore else { return }
        let now = Int(Date().timeIntervalSince1970)
        let bookmark = NostrLocalBookmarkRecord(
            accountID: account.pubkey,
            eventID: post.id,
            createdAt: now
        )

        do {
            try eventStore.saveLocalBookmark(bookmark)
        } catch {
            phase = .failed("Bookmark failed: \(error.localizedDescription)")
        }
    }

    func isBookmarked(_ post: TimelinePost) -> Bool {
        guard let account, let eventStore else { return false }
        return ((try? eventStore.localBookmarks(accountID: account.pubkey)) ?? [])
            .contains { $0.eventID == post.id }
    }

    func listEntries(limit: Int = 500) -> [TimelineFeedEntry] {
        guard let account, let eventStore else { return [] }
        if let listEntriesCache,
           listEntriesCache.accountID == account.pubkey,
           listEntriesCache.limit == limit,
           listEntriesCache.homeContentRevision == resolvedContentRevision,
           listEntriesCache.listContentRevision == listContentRevision {
            return listEntriesCache.entries
        }
        let listEvents = cachedListTimelineEvents(accountID: account.pubkey, eventStore: eventStore, limit: limit)
        guard !listEvents.isEmpty else {
            listEntriesCache = ListEntriesCache(
                accountID: account.pubkey,
                limit: limit,
                homeContentRevision: resolvedContentRevision,
                listContentRevision: listContentRevision,
                entries: []
            )
            return []
        }
        let pubkeys = Set(listEvents.map(\.pubkey))
        let metadata = (try? eventStore.latestReplaceableEvents(pubkeys: pubkeys, kind: 0)) ?? metadataEvents.filter { pubkeys.contains($0.pubkey) }
        let materializedEntries = NostrTimelineMaterializer.entries(
            noteEvents: listEvents,
            metadataEvents: metadata,
            nip05Resolutions: dependencyCoordinator.nip05Resolutions,
            profileResolutionStates: profileResolutionStates,
            followedPubkeys: Set(followedPubkeys),
            mediaAssetsByEventID: mediaAssetsByEventID(for: listEvents),
            linkPreviewsByNormalizedURL: linkPreviewsByNormalizedURL(for: listEvents),
            filterRules: listFilterRuleSet(),
            timeline: .lists
        )
        listEntriesCache = ListEntriesCache(
            accountID: account.pubkey,
            limit: limit,
            homeContentRevision: resolvedContentRevision,
            listContentRevision: listContentRevision,
            entries: materializedEntries
        )
        return materializedEntries
    }

    func suspendTimelineFilters() {
        guard !areTimelineFiltersSuspended else { return }
        areTimelineFiltersSuspended = true
        invalidateListEntries()
        materializeEntries()
    }

    func resumeTimelineFilters() {
        guard areTimelineFiltersSuspended else { return }
        areTimelineFiltersSuspended = false
        invalidateListEntries()
        materializeEntries()
    }

    func cancel() {
        flushPendingViewportStateSave()
        persistHomeFeedReadState()
        flushRelayTrafficDeltas()
        runtimeLifecycleGeneration &+= 1
        let cancellationGeneration = runtimeLifecycleGeneration
        loadTask?.cancel()
        paginationTask?.cancel()
        runtimeTask?.cancel()
        profileDirectoryUpdateTask?.cancel()
        resolveRuntimeEventPumpReadiness(false)
        linkPreviewCoordinator.reset()
        materializationScheduler.reset()
        realtimeFollowSourceRevision = materializationScheduler.realtimeFollowSourceRevision
        unmaterializedCountTask?.cancel()
        outboxTask?.cancel()
        outboxTaskGeneration &+= 1
        feedReadStateTask?.cancel()
        viewportStateTask?.cancel()
        dependencyFlushTask?.cancel()
        loadTask = nil
        paginationTask = nil
        runtimeTask = nil
        profileDirectoryUpdateTask = nil
        unmaterializedCountTask = nil
        outboxTask = nil
        feedReadStateTask = nil
        viewportStateTask = nil
        dependencyFlushTask = nil
        dependencyCoordinator.reset()
        pendingBackwardRequests.removeAll()
        pendingGapReconciliationIDs.removeAll()
        unmaterializedNewEventIDs.removeAll()
        unmaterializedNewCount = 0
        isRefreshing = false
        isLoadingOlder = false
        listEntriesCache = nil
        listContentRevision &+= 1
        homeFeedProjection.reset()
        installedHomeForwardPackets = []
        resetHomeTimelineRealtime()
        finishActiveFeedSyncRequests(reason: .cancelled)
        feedSyncLifecycle.reset()
        pendingRelayTrafficDeltas.removeAll()
        relayRuntimeStates = [:]
        entries = []
        resolvedRelays = []
        followedPubkeys = []
        noteEvents = []
        metadataEvents = []
        profileResolutionStates = [:]
        relayListEvent = nil
        contactListEvent = nil
        relayDiagnostics.reset()
        hasMoreOlder = true
        filterStatus = TimelineFilterStatus()
        unreadState.reset()
        publishUnreadState()
        restoreProjectionAnchorEventID = nil
        isTimelineAtNewestWindow = true
        hasCompletedRuntimeBootstrap = false
        areTimelineFiltersSuspended = false
        updateRelayStatusCounts()
        relayStatusRevision &+= 1
        phase = .idle
        account = nil
        scheduleRelayRuntimeTermination(cancellationGeneration: cancellationGeneration)
    }

    private func scheduleRelayRuntimeTermination(cancellationGeneration: UInt64) {
        guard let relayRuntime else { return }
        relayRuntimeTerminationSequence &+= 1
        let terminationSequence = relayRuntimeTerminationSequence
        let previousTerminationTask = relayRuntimeTerminationTask
        relayRuntimeTerminationTask = Task { [weak self] in
            await previousTerminationTask?.value
            await self?.profileDirectory?.stop()
            await relayRuntime.terminate()
            guard let self,
                  self.relayRuntimeTerminationSequence == terminationSequence
            else { return }
            self.relayRuntimeTerminationTask = nil
            guard self.runtimeLifecycleGeneration != cancellationGeneration,
                  let account = self.account
            else { return }

            self.runtimeTask?.cancel()
            self.runtimeTask = nil
            self.resolveRuntimeEventPumpReadiness(false)
            self.installedHomeForwardPackets = []
            self.resetHomeTimelineRealtime()
            self.startRuntimeEventPump()
            await self.configureRelayRuntime(account: account, forceInstall: true)
        }
    }

    func post(eventID: String) -> TimelinePost? {
        guard let eventStore,
              let event = try? eventStore.event(id: eventID),
              event.kind == 1
        else {
            return entries.compactMap(\.post).first { $0.id == eventID }
        }

        return materializedPosts(from: [event]).first
    }

    func profile(pubkey: String, isCurrentUser: Bool = false) -> UserProfile {
        let metadata = try? eventStore?.latestReplaceableEvent(pubkey: pubkey, kind: 0)
        let posts = profilePosts(pubkey: pubkey, limit: 1_000)
        let author = materializedAuthor(pubkey: pubkey, metadataEvent: metadata)
        let avatar = posts.first?.avatar ?? avatar(for: pubkey)
        let relayCount = isCurrentUser ? resolvedRelays.count : max(1, resolvedRelays.count)

        return UserProfile(
            id: pubkey,
            author: author,
            avatar: avatar,
            banner: banner(for: pubkey),
            bio: metadata.flatMap(Self.profileMetadata).map { _ in "kind:0 profile metadata is cached." } ?? "kind:0 profile is not cached yet.",
            isCurrentUser: isCurrentUser,
            isFollowed: followedPubkeys.contains(pubkey) || isCurrentUser,
            followerCount: 0,
            followingCount: isCurrentUser ? followedPubkeys.count : 0,
            postCount: posts.count,
            relayCount: relayCount,
            latestFollowers: [],
            featuredHashtags: []
        )
    }

    func profilePosts(pubkey: String, limit: Int = 80) -> [TimelinePost] {
        guard let events = try? eventStore?.events(kind: 1, authors: [pubkey], limit: limit) else {
            return entries.compactMap(\.post).filter { $0.author.pubkey == pubkey }
        }

        return materializedPosts(from: events)
    }

    func replyAncestors(for post: TimelinePost, limit: Int = 8) -> [TimelinePost] {
        guard let eventStore else { return [] }

        var ancestors: [NostrEvent] = []
        var currentID = post.id
        var visited = Set([post.id])

        while ancestors.count < limit {
            guard let tags = try? eventStore.tags(eventID: currentID),
                  let parentID = NostrTimelineReplyProjection.replyParentID(from: tags),
                  !visited.contains(parentID),
                  let parentEvent = try? eventStore.event(id: parentID),
                  parentEvent.kind == 1
            else {
                break
            }

            ancestors.append(parentEvent)
            visited.insert(parentID)
            currentID = parentID
        }

        return materializedPosts(from: ancestors.reversed())
    }

    func replies(for post: TimelinePost, limit: Int = 24) -> [TimelinePost] {
        guard let events = try? eventStore?.eventsReferencing(eventID: post.id, kind: 1, limit: limit) else {
            return []
        }

        return materializedPosts(from: events.filter { event in
            NostrTimelineReplyProjection.replyParentID(from: event.tags) == post.id
        })
    }

    private func isCurrentLifecycle(accountID: String, generation: UInt64) -> Bool {
        runtimeLifecycleGeneration == generation && account?.pubkey == accountID
    }

    private func load(account: NostrAccount) async {
        let lifecycleGeneration = runtimeLifecycleGeneration
        guard isCurrentLifecycle(accountID: account.pubkey, generation: lifecycleGeneration) else { return }
        if relayRuntime != nil {
            await loadRuntimeBootstrap(account: account)
            return
        }

        do {
            let state = try await timelineLoader.initialState(
                account: account,
                onStage: { [weak self] stage in
                    await self?.handleLoadStage(
                        stage,
                        accountID: account.pubkey,
                        lifecycleGeneration: lifecycleGeneration
                    )
                }
            )
            guard !Task.isCancelled,
                  isCurrentLifecycle(accountID: account.pubkey, generation: lifecycleGeneration)
            else { return }
            phase = .loadingHome
            await relayDiagnostics.persistFetchedEvents(state.relaySyncEvents)
            guard !Task.isCancelled,
                  isCurrentLifecycle(accountID: account.pubkey, generation: lifecycleGeneration)
            else { return }
            apply(state)
            materializeEntries()
            await persistDatabase(account: account)
            guard !Task.isCancelled,
                  isCurrentLifecycle(accountID: account.pubkey, generation: lifecycleGeneration)
            else { return }
            await configureRelayRuntime(account: account)
            guard isCurrentLifecycle(accountID: account.pubkey, generation: lifecycleGeneration) else { return }
            phase = .loaded
        } catch {
            guard !Task.isCancelled,
                  isCurrentLifecycle(accountID: account.pubkey, generation: lifecycleGeneration)
            else { return }
            phase = .failed("Home timeline failed: \(error.localizedDescription)")
        }
    }

    private func loadRuntimeBootstrap(account: NostrAccount) async {
        let lifecycleGeneration = runtimeLifecycleGeneration
        guard isCurrentLifecycle(accountID: account.pubkey, generation: lifecycleGeneration) else { return }
        installProvisionalRuntimeBootstrapIfNeeded(account: account)
        let hadCachedBootstrap = hasCompletedRuntimeBootstrap
        if hadCachedBootstrap, !resolvedRelays.isEmpty {
            await configureRelayRuntime(account: account)
            guard !Task.isCancelled,
                  isCurrentLifecycle(accountID: account.pubkey, generation: lifecycleGeneration)
            else { return }
        } else {
            phase = .resolvingRelays
        }

        do {
            let bootstrapState = try await timelineLoader.bootstrapState(
                account: account,
                onStage: { [weak self] stage in
                    await self?.handleLoadStage(
                        stage,
                        accountID: account.pubkey,
                        lifecycleGeneration: lifecycleGeneration
                    )
                }
            )
            guard !Task.isCancelled,
                  isCurrentLifecycle(accountID: account.pubkey, generation: lifecycleGeneration)
            else { return }
            phase = .loadingHome
            await relayDiagnostics.persistFetchedEvents(bootstrapState.relaySyncEvents)
            guard !Task.isCancelled,
                  isCurrentLifecycle(accountID: account.pubkey, generation: lifecycleGeneration)
            else { return }
            apply(runtimeBootstrapState(from: bootstrapState))
            hasCompletedRuntimeBootstrap = true
            materializeEntries()
            await persistDatabase(account: account)
            guard !Task.isCancelled,
                  isCurrentLifecycle(accountID: account.pubkey, generation: lifecycleGeneration)
            else { return }
            await configureRelayRuntime(account: account)
            guard isCurrentLifecycle(accountID: account.pubkey, generation: lifecycleGeneration) else { return }
            phase = .loaded
        } catch {
            guard !Task.isCancelled,
                  isCurrentLifecycle(accountID: account.pubkey, generation: lifecycleGeneration)
            else { return }
            recordRuntimeSyncEvent(
                relayURL: resolvedRelays.first ?? "runtime",
                kind: .partialFailure,
                subscriptionID: "astrenza-bootstrap",
                message: "bootstrap refresh failed: \(error.localizedDescription)"
            )
            if hadCachedBootstrap {
                phase = .loaded
            } else if !resolvedRelays.isEmpty {
                followedPubkeys = [account.pubkey]
                hasCompletedRuntimeBootstrap = true
                await configureRelayRuntime(account: account)
                phase = .loaded
            } else {
                phase = .failed("Home timeline failed: \(error.localizedDescription)")
            }
        }
    }

    private func runtimeBootstrapState(from bootstrapState: NostrHomeTimelineState) -> NostrHomeTimelineState {
        NostrHomeTimelineState(
            relays: bootstrapState.relays,
            followedPubkeys: bootstrapState.followedPubkeys,
            noteEvents: noteEvents,
            metadataEvents: metadataEvents,
            relayListEvent: bootstrapState.relayListEvent,
            contactListEvent: bootstrapState.contactListEvent,
            nip05Resolutions: dependencyCoordinator.nip05Resolutions,
            hasMoreOlder: hasMoreOlder,
            relaySyncEvents: bootstrapState.relaySyncEvents.map { event in
                NostrRelaySyncEventRecord(
                    accountID: event.accountID,
                    timelineKey: event.timelineKey,
                    relayURL: event.relayURL,
                    kind: event.kind,
                    occurredAt: event.occurredAt,
                    subscriptionID: event.subscriptionID,
                    eventCount: event.eventCount,
                    newestCreatedAt: nil,
                    oldestCreatedAt: nil,
                    latencyMilliseconds: event.latencyMilliseconds,
                    message: event.message
                )
            }
        )
    }

    private func handleLoadStage(
        _ stage: NostrHomeTimelineLoadStage,
        accountID: String,
        lifecycleGeneration: UInt64
    ) {
        guard !Task.isCancelled,
              isCurrentLifecycle(accountID: accountID, generation: lifecycleGeneration)
        else { return }
        switch stage {
        case .resolvingRelayList:
            phase = .resolvingRelays
        case .resolvingContactList:
            phase = .resolvingContacts
        case .loadingTimeline:
            phase = .loadingHome
        }
    }

    private func refreshLatest(account: NostrAccount) async {
        guard !isRefreshing else { return }
        let lifecycleGeneration = runtimeLifecycleGeneration
        guard isCurrentLifecycle(accountID: account.pubkey, generation: lifecycleGeneration) else { return }
        guard !noteEvents.isEmpty else {
            start(account: account)
            return
        }

        isRefreshing = true
        defer {
            if isCurrentLifecycle(accountID: account.pubkey, generation: lifecycleGeneration) {
                isRefreshing = false
            }
        }

        if relayRuntime != nil {
            await configureRelayRuntime(account: account)
            guard !Task.isCancelled,
                  isCurrentLifecycle(accountID: account.pubkey, generation: lifecycleGeneration)
            else { return }
            phase = .loaded
            return
        }

        do {
            let state = try await timelineLoader.refreshedState(account: account, current: loaderState())
            guard !Task.isCancelled,
                  isCurrentLifecycle(accountID: account.pubkey, generation: lifecycleGeneration)
            else { return }
            await relayDiagnostics.persistFetchedEvents(state.relaySyncEvents)
            guard !Task.isCancelled,
                  isCurrentLifecycle(accountID: account.pubkey, generation: lifecycleGeneration)
            else { return }
            apply(state)
            materializeEntries()
            await persistDatabase(account: account)
            guard !Task.isCancelled,
                  isCurrentLifecycle(accountID: account.pubkey, generation: lifecycleGeneration)
            else { return }
            await configureRelayRuntime(account: account)
            guard isCurrentLifecycle(accountID: account.pubkey, generation: lifecycleGeneration) else { return }
            phase = .loaded
        } catch {
            guard !Task.isCancelled,
                  isCurrentLifecycle(accountID: account.pubkey, generation: lifecycleGeneration)
            else { return }
            phase = .failed("Refresh failed: \(error.localizedDescription)")
        }
    }

    private func loadOlder(account: NostrAccount) async {
        let lifecycleGeneration = runtimeLifecycleGeneration
        guard isCurrentLifecycle(accountID: account.pubkey, generation: lifecycleGeneration) else { return }
        isLoadingOlder = true
        defer {
            if isCurrentLifecycle(accountID: account.pubkey, generation: lifecycleGeneration) {
                isLoadingOlder = false
            }
        }

        if relayRuntime != nil {
            await requestOlderNotesThroughRuntime(account: account)
            guard !Task.isCancelled,
                  isCurrentLifecycle(accountID: account.pubkey, generation: lifecycleGeneration)
            else { return }
            phase = .loaded
            return
        }

        do {
            let current = loaderState()
            let localBackfillEvents = databaseBackfillEvents(account: account, current: current)
            let state = try await timelineLoader.olderState(
                account: account,
                current: current,
                localBackfillEvents: localBackfillEvents
            )
            guard !Task.isCancelled,
                  isCurrentLifecycle(accountID: account.pubkey, generation: lifecycleGeneration)
            else { return }
            await relayDiagnostics.persistFetchedEvents(state.relaySyncEvents)
            guard !Task.isCancelled,
                  isCurrentLifecycle(accountID: account.pubkey, generation: lifecycleGeneration)
            else { return }
            apply(state)
            if !state.hasMoreOlder {
                return
            }

            materializeEntries()
            await persistDatabase(account: account)
            guard !Task.isCancelled,
                  isCurrentLifecycle(accountID: account.pubkey, generation: lifecycleGeneration)
            else { return }
            await configureRelayRuntime(account: account)
            guard isCurrentLifecycle(accountID: account.pubkey, generation: lifecycleGeneration) else { return }
            phase = .loaded
        } catch {
            guard !Task.isCancelled,
                  isCurrentLifecycle(accountID: account.pubkey, generation: lifecycleGeneration)
            else { return }
            phase = .failed("Older notes failed: \(error.localizedDescription)")
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

        pendingBackwardRequests[packet.groupID] = PendingBackwardRequest(
            feedContext: feedContext,
            isOlderPage: true,
            olderAnchorPostID: olderAnchorPostID
        )

        do {
            try await relayRuntime.installBackward([packet], mergeField: .authors)
        } catch {
            pendingBackwardRequests.removeValue(forKey: packet.groupID)
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

        pendingBackwardRequests[packet.groupID] = PendingBackwardRequest(
            feedContext: feedContext,
            gap: PendingGapBackfill(
                newerPostID: gap.newerPostID,
                olderPostID: gap.olderPostID,
                direction: direction
            )
        )

        do {
            try await relayRuntime.installBackward([packet], mergeField: .authors)
            return true
        } catch {
            pendingBackwardRequests.removeValue(forKey: packet.groupID)
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
        return try? eventStore?.event(id: id)
    }

    @discardableResult
    private func restoreCachedSnapshot(account: NostrAccount) -> Bool {
        if let databaseState = try? eventStore?.homeFeedState(accountID: account.pubkey) {
            apply(databaseState)
            return true
        }

        if restoreLegacySnapshotForMigration(account: account) {
            return true
        }

        entries = []
        materializationScheduler.replaceRenderFingerprint([])
        resolvedRelays = []
        updateRelayStatusCounts()
        followedPubkeys = []
        noteEvents = []
        metadataEvents = []
        relayListEvent = nil
        contactListEvent = nil
        dependencyCoordinator.replaceNIP05Resolutions([:])
        relayDiagnostics.reset()
        hasMoreOlder = true
        filterStatus = TimelineFilterStatus()
        unmaterializedNewEventIDs.removeAll()
        unmaterializedNewCount = 0
        unreadState.reset()
        publishUnreadState()
        return false
    }

    /// V4以前の開発用DBをGeneric Feedへ移すための一度限りのcompatibility pathです。
    private func restoreLegacySnapshotForMigration(account: NostrAccount) -> Bool {
        guard let state = try? eventStore?.legacyHomeTimelineStateForMigration(
            accountID: account.pubkey
        ) else { return false }
        apply(state)
        return true
    }

    private func persistDatabase(account: NostrAccount) async {
        guard let persistenceWorker else { return }
        let now = Int(Date().timeIntervalSince1970)
        guard let plan = homeFeedDefinitionPlan(account: account, now: now) else { return }
        let definition = plan.definition
        let allowedAuthors = Set(plan.authors)
        let projectionEvents = HomeTimelinePersistenceProjection.boundedEvents(
            from: noteEvents,
            allowedAuthors: allowedAuthors
        )
        let metadataPubkeys = Set(projectionEvents.map(\.pubkey)).union([account.pubkey])
        let state = NostrHomeTimelineState(
            relays: resolvedRelays,
            followedPubkeys: followedPubkeys,
            noteEvents: projectionEvents,
            metadataEvents: metadataEvents.filter { metadataPubkeys.contains($0.pubkey) },
            relayListEvent: relayListEvent,
            contactListEvent: contactListEvent,
            nip05Resolutions: dependencyCoordinator.nip05Resolutions,
            hasMoreOlder: hasMoreOlder,
            relaySyncEvents: []
        )
        let memberships = HomeFeedProjectionBuilder.memberships(
            events: projectionEvents,
            feedID: definition.feedID,
            feedRevision: definition.revision,
            reason: "state",
            insertedAt: now
        )
        let membershipSources = HomeFeedProjectionBuilder.membershipSources(
            events: projectionEvents,
            feedID: definition.feedID,
            feedRevision: definition.revision,
            reason: "state",
            insertedAt: now
        )
        let lifecycleGeneration = runtimeLifecycleGeneration
        let savedProjectionWindowGeneration = homeFeedProjection.generation
        do {
            let window = try await persistenceWorker.saveFeedSnapshot(
                HomeTimelineFeedPersistenceSnapshot(
                    state: state,
                    accountID: account.pubkey,
                    definition: definition,
                    memberships: memberships,
                    membershipSources: membershipSources,
                    savedAt: now,
                    windowLimit: homeFeedProjection.windowLimit
                )
            )
            guard !Task.isCancelled,
                  runtimeLifecycleGeneration == lifecycleGeneration,
                  self.account?.pubkey == account.pubkey,
                  homeFeedProjection.generation == savedProjectionWindowGeneration,
                  (followedPubkeys.isEmpty ? [account.pubkey] : followedPubkeys) == plan.sourceAuthors,
                  let currentPlan = homeFeedDefinitionPlan(account: account, now: now),
                  currentPlan.definition.revision == definition.revision,
                  currentPlan.definition.specificationHash == definition.specificationHash
            else { return }
            homeFeedProjection.activate(
                definition: definition,
                window: window,
                sourceAuthors: plan.sourceAuthors
            )
            if unmaterializedNewEventIDs.isEmpty {
                materializeEntries()
            }
        } catch {
            // Live networking can still populate the timeline if the database write fails.
        }
    }

    private func persistTimelineMetadata(account: NostrAccount) async {
        guard let persistenceWorker else { return }
        let now = Int(Date().timeIntervalSince1970)
        let lifecycleGeneration = runtimeLifecycleGeneration
        let state = NostrHomeTimelineState(
            relays: resolvedRelays,
            followedPubkeys: followedPubkeys,
            noteEvents: [],
            metadataEvents: [],
            nip05Resolutions: dependencyCoordinator.nip05Resolutions,
            hasMoreOlder: hasMoreOlder,
            relaySyncEvents: []
        )
        do {
            try await persistenceWorker.saveTimelineMetadata(
                state,
                accountID: account.pubkey,
                savedAt: now
            )
            guard runtimeLifecycleGeneration == lifecycleGeneration,
                  self.account?.pubkey == account.pubkey
            else { return }
        } catch {
            // 次回のeventまたはstate保存で再試行します。
        }
    }

    private func ensureHomeFeedDefinition(account: NostrAccount) {
        homeFeedProjection.ensureDefinition(
            accountID: account.pubkey,
            followedPubkeys: followedPubkeys,
            liveEvents: noteEvents
        )
    }

    private func homeFeedDefinitionPlan(
        account: NostrAccount,
        now: Int
    ) -> HomeFeedDefinitionPlan? {
        homeFeedProjection.definitionPlan(
            accountID: account.pubkey,
            followedPubkeys: followedPubkeys,
            now: now
        )
    }

    private func activeHomeFeedRuntimeContext() -> HomeFeedRuntimeContext? {
        homeFeedProjection.runtimeContext()
    }

    private func isCurrentHomeFeedContext(_ context: HomeFeedRuntimeContext?) -> Bool {
        homeFeedProjection.isCurrent(context, accountID: account?.pubkey)
    }

    private func feedScopedForwardPackets(
        _ packets: [NostrREQPacket],
        context: HomeFeedRuntimeContext
    ) -> [NostrREQPacket] {
        let specificationToken = String(context.specificationHash.prefix(12))
        return packets.map { packet in
            NostrREQPacket(
                strategy: packet.strategy,
                subscriptionID: packet.subscriptionID,
                groupID: "\(packet.groupID)-feed-r\(context.revision)-\(specificationToken)",
                filters: packet.filters,
                relayURLs: packet.relayURLs
            )
        }
    }

    private func restoreHomeFeedReadState(account: NostrAccount) {
        guard let eventStore,
              let definition = homeFeedProjection.definition,
              definition.accountID == account.pubkey,
              let state = try? eventStore.feedReadState(feedID: definition.feedID)
        else { return }

        let postIDs = entries.compactMap(\.post?.id)
        let exactBoundaryID = state.readBoundary?.eventID
        let boundaryID: TimelinePost.ID?
        if let exactBoundaryID, postIDs.contains(exactBoundaryID) {
            boundaryID = exactBoundaryID
        } else if let cursor = state.readBoundary {
            boundaryID = entries.compactMap(\.post).first { post in
                let timestamp = post.createdAt
                return timestamp < cursor.sortTimestamp ||
                    (timestamp == cursor.sortTimestamp && post.id >= cursor.eventID)
            }?.id
        } else {
            boundaryID = nil
        }

        guard let boundaryID else { return }
        unreadState.setReadBoundary(postID: boundaryID)
        publishUnreadState()
    }

    private func scheduleHomeFeedReadStateSave() {
        guard account != nil, homeFeedProjection.definition != nil else { return }
        feedReadStateTask?.cancel()
        feedReadStateTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: 500_000_000)
            } catch {
                return
            }
            guard let self, !Task.isCancelled else { return }
            self.persistHomeFeedReadState()
            self.feedReadStateTask = nil
        }
    }

    private func persistPendingViewportState() async {
        viewportStateTask = nil
        guard let pendingViewportState,
              let persistenceWorker,
              account?.pubkey == pendingViewportState.accountID
        else { return }
        self.pendingViewportState = nil
        try? await persistenceWorker.saveViewportState(
            feedID: pendingViewportState.feedID,
            anchorEventID: pendingViewportState.anchorEventID,
            anchorOffset: pendingViewportState.anchorOffset,
            updatedAt: pendingViewportState.updatedAt
        )
    }

    private func persistHomeFeedReadState() {
        guard let account,
              let persistenceWorker,
              let definition = homeFeedProjection.definition,
              definition.accountID == account.pubkey
        else { return }

        let boundaryID = unreadState.readBoundaryPostID
        let boundaryEvent = boundaryID.flatMap(timelineEvent(id:))
        let readBoundary = boundaryEvent.map {
            NostrTimelineEntryCursor(sortTimestamp: $0.createdAt, eventID: $0.id)
        }
        let updatedAt = Int(Date().timeIntervalSince1970)
        Task {
            try? await persistenceWorker.saveReadBoundary(
                feedID: definition.feedID,
                boundary: readBoundary,
                updatedAt: updatedAt
            )
        }
    }

    private func reloadNewestProjectionWindow(account: NostrAccount) {
        guard let window = homeFeedProjection.reloadNewest(
            accountID: account.pubkey,
            followedPubkeys: followedPubkeys,
            liveEvents: noteEvents
        ) else { return }
        noteEvents = window.events
    }

    @discardableResult
    private func reloadProjectionWindow(
        account: NostrAccount,
        around anchorEventID: String?,
        mergingWithCurrentWindow: Bool = false
    ) -> Bool {
        guard let window = homeFeedProjection.reload(
            accountID: account.pubkey,
            followedPubkeys: followedPubkeys,
            liveEvents: noteEvents,
            around: anchorEventID,
            mergingWithCurrentWindow: mergingWithCurrentWindow
        ) else { return false }
        noteEvents = window.events
        return true
    }

    private func applyRestoreProjectionAnchorIfPossible(account: NostrAccount) {
        guard let restoreProjectionAnchorEventID else { return }
        guard reloadProjectionWindow(account: account, around: restoreProjectionAnchorEventID) else { return }
        materializeEntries()
        scheduleLinkPreviewResolution()
        if !entries.isEmpty {
            phase = .loaded
        }
    }

    private func contextEventsForCurrentProjection() -> [NostrEvent] {
        guard let eventStore else { return [] }
        let sourceIDs = Array(Set(noteEvents.flatMap { event in
            NostrEventDependencies.extract(from: event).sourceEventIDs
        })).sorted()
        guard !sourceIDs.isEmpty else { return [] }
        let visibleIDs = Set(noteEvents.map(\.id))
        return ((try? eventStore.events(ids: sourceIDs)) ?? []).filter { !visibleIDs.contains($0.id) }
    }

    private func startRuntimeEventPump() {
        startProfileDirectoryEventPump()
        guard let relayRuntime,
              relayRuntimeTerminationTask == nil,
              runtimeTask == nil,
              let accountID = account?.pubkey
        else { return }
        let lifecycleGeneration = runtimeLifecycleGeneration
        resolveRuntimeEventPumpReadiness(false)
        runtimeTask = Task { [weak self] in
            let stream = await relayRuntime.events()
            guard !Task.isCancelled,
                  self?.runtimeLifecycleGeneration == lifecycleGeneration,
                  self?.account?.pubkey == accountID
            else {
                self?.resolveRuntimeEventPumpReadiness(
                    false,
                    lifecycleGeneration: lifecycleGeneration
                )
                return
            }
            self?.resolveRuntimeEventPumpReadiness(
                true,
                lifecycleGeneration: lifecycleGeneration
            )
            for await packet in stream {
                guard !Task.isCancelled,
                      self?.runtimeLifecycleGeneration == lifecycleGeneration,
                      self?.account?.pubkey == accountID
                else { break }
                await self?.handleRuntimePacket(packet)
            }
        }
    }

    private func startProfileDirectoryEventPump() {
        guard let profileDirectory,
              profileDirectoryUpdateTask == nil,
              relayRuntimeTerminationTask == nil,
              let account
        else { return }
        let accountID = account.pubkey
        let lifecycleGeneration = runtimeLifecycleGeneration
        let relayURLs = runtimeRelayURLs(account: account)
        profileDirectoryUpdateTask = Task { [weak self] in
            let updates = await profileDirectory.updates()
            await profileDirectory.start(relayURLs: relayURLs)
            for await update in updates {
                guard !Task.isCancelled,
                      self?.runtimeLifecycleGeneration == lifecycleGeneration,
                      self?.account?.pubkey == accountID
                else { break }
                self?.handleProfileDirectoryUpdate(update)
            }
        }
    }

    private func handleProfileDirectoryUpdate(_ update: NostrProfileDirectoryUpdate) {
        guard account != nil else { return }
        profileResolutionStates.merge(update.states) { _, latest in latest }
        for event in update.metadataEvents {
            let effectiveEvent = rememberLatestMetadataEvent(event, consultEventStore: false)
            resolveNIP05IfNeeded(for: effectiveEvent)
        }
        if !update.states.isEmpty || !update.metadataEvents.isEmpty {
            invalidateListEntries()
            scheduleMaterializeEntries()
        }
    }

    private func waitForRuntimeEventPumpReady() async -> Bool {
        if isRuntimeEventPumpReady { return true }
        guard runtimeTask != nil, !Task.isCancelled else { return false }
        let isReady = await withCheckedContinuation { continuation in
            if isRuntimeEventPumpReady {
                continuation.resume(returning: true)
            } else if runtimeTask != nil {
                runtimeEventPumpReadyWaiters.append(continuation)
            } else {
                continuation.resume(returning: false)
            }
        }
        return isReady && !Task.isCancelled
    }

    private func resolveRuntimeEventPumpReadiness(
        _ isReady: Bool,
        lifecycleGeneration: UInt64? = nil
    ) {
        if let lifecycleGeneration,
           lifecycleGeneration != runtimeLifecycleGeneration {
            return
        }
        isRuntimeEventPumpReady = isReady
        let waiters = runtimeEventPumpReadyWaiters
        runtimeEventPumpReadyWaiters.removeAll(keepingCapacity: true)
        for waiter in waiters {
            waiter.resume(returning: isReady)
        }
    }

    private func installProvisionalRuntimeBootstrapIfNeeded(account: NostrAccount) {
        guard relayRuntime != nil, resolvedRelays.isEmpty else { return }
        let provisionalRelays = provisionalDiscoveryRelays(for: account)
        guard !provisionalRelays.isEmpty else { return }
        resolvedRelays = provisionalRelays
        updateRelayStatusCounts()
    }

    private func provisionalDiscoveryRelays(for account: NostrAccount) -> [String] {
        normalizedRelayURLs(account.discoveryRelays + timelineLoader.bootstrapRelays)
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
        guard let relayRuntime,
              relayRuntimeTerminationTask == nil,
              self.account?.pubkey == account.pubkey,
              hasCompletedRuntimeBootstrap,
              !resolvedRelays.isEmpty
        else { return }

        relayRuntimeConfigurationSequence &+= 1
        let configurationSequence = relayRuntimeConfigurationSequence
        let lifecycleGeneration = runtimeLifecycleGeneration
        let expectedResolvedRelays = resolvedRelays
        let expectedFollowedPubkeys = followedPubkeys
        let expectedContactListEventID = contactListEvent?.id
        let expectedContactItems = NostrContactList.items(from: contactListEvent)
        let expectedDefaultRelays = runtimeRelayURLs(account: account)

        func remainsCurrent() -> Bool {
            relayRuntimeConfigurationSequence == configurationSequence &&
                isCurrentLifecycle(accountID: account.pubkey, generation: lifecycleGeneration) &&
                resolvedRelays == expectedResolvedRelays &&
                followedPubkeys == expectedFollowedPubkeys &&
                contactListEvent?.id == expectedContactListEventID
        }

        do {
            guard await waitForRuntimeEventPumpReady() else { return }
            guard remainsCurrent() else { return }
            await relayRuntime.setTrafficContext(
                accountID: account.pubkey,
                policy: syncPolicy
            )
            guard remainsCurrent() else { return }
            await profileDirectory?.updateRelayURLs(expectedDefaultRelays)
            guard remainsCurrent() else { return }
            try await relayRuntime.setDefaultRelays(expectedDefaultRelays)
            guard remainsCurrent() else { return }
            await ensureProfileDirectoryDependencies(for: noteEvents)
            guard remainsCurrent() else { return }
            ensureHomeFeedDefinition(account: account)
            let newestCreatedAt = noteEvents.map(\.createdAt).max()
            let initialCreatedAt = noteEvents.map(\.createdAt).min()
            let newestCreatedAtByRelay = forwardCursorNewestCreatedAtByRelay(accountID: account.pubkey)
            let plan = syncPlanner.forwardPlan(
                account: account,
                followedPubkeys: expectedFollowedPubkeys,
                contactItems: expectedContactItems,
                newestCreatedAt: newestCreatedAt,
                newestCreatedAtByRelay: newestCreatedAtByRelay,
                initialCreatedAt: initialCreatedAt,
                relayURLs: expectedResolvedRelays,
                policy: syncPolicy
            )
            guard remainsCurrent() else { return }
            guard let feedContext = activeHomeFeedRuntimeContext() else { return }
            let scopedPackets = feedScopedForwardPackets(plan.packets, context: feedContext)
            guard forceInstall || installedHomeForwardPackets != scopedPackets else { return }
            resetHomeTimelineRealtime(
                expecting: homeForwardRuntimeKeys(
                    packets: scopedPackets,
                    defaultRelayURLs: expectedDefaultRelays
                )
            )
            for packet in scopedPackets {
                feedSyncLifecycle.registerForwardContext(feedContext, groupID: packet.groupID)
            }
            try await relayRuntime.installForward(
                scopedPackets,
                replacingGroupIDsWithPrefix: HomeTimelineSyncPlanner.homeForwardGroupPrefix
            )
            guard remainsCurrent(), isCurrentHomeFeedContext(feedContext) else { return }
            installedHomeForwardPackets = scopedPackets
        } catch {
            guard remainsCurrent() else { return }
            recordRuntimeSyncEvent(
                relayURL: resolvedRelays.first ?? "runtime",
                kind: .partialFailure,
                subscriptionID: NostrHomeForwardREQBuilder.subscriptionID,
                message: String(describing: error)
            )
        }
    }

    private func runtimeRelayURLs(account: NostrAccount) -> [String] {
        Array(
            normalizedRelayURLs(
                resolvedRelays + account.discoveryRelays + timelineLoader.bootstrapRelays
            )
            .dedupedPreservingOrder()
            .prefix(10)
        )
    }

    private func homeForwardRuntimeKeys(
        packets: [NostrREQPacket],
        defaultRelayURLs: [String]
    ) -> Set<RuntimeSubscriptionKey> {
        Set(packets.flatMap { packet in
            NostrREQScheduler.forwardChunks(packet)
        }.flatMap { packet in
            let relayURLs = packet.relayURLs.isEmpty
                ? defaultRelayURLs
                : defaultRelayURLs.filter { packet.relayURLs.contains($0) }
            return relayURLs.map { relayURL in
                RuntimeSubscriptionKey(
                    relayURL: relayURL,
                    subscriptionID: packet.subscriptionID
                )
            }
        })
    }

    private func resetHomeTimelineRealtime(
        expecting runtimeKeys: Set<RuntimeSubscriptionKey> = []
    ) {
        feedSyncLifecycle.prepareForwardSubscriptions(runtimeKeys)
        publishHomeTimelineRealtimeState()
    }

    private func invalidateHomeTimelineRealtime(for key: RuntimeSubscriptionKey) {
        guard Self.isHomeForwardSubscription(key.subscriptionID) else { return }
        feedSyncLifecycle.invalidateForwardSubscription(key)
        publishHomeTimelineRealtimeState()
    }

    private func invalidateHomeTimelineRealtime(relayURL: String) {
        feedSyncLifecycle.invalidateForwardSubscriptions(relayURL: relayURL)
        publishHomeTimelineRealtimeState()
    }

    private func publishHomeTimelineRealtimeState() {
        let nextIsRealtime = feedSyncLifecycle.isRealtime
        guard isHomeTimelineRealtime != nextIsRealtime else { return }
        isHomeTimelineRealtime = nextIsRealtime
    }

    private func forwardCursorNewestCreatedAtByRelay(accountID: String) -> [String: Int]? {
        guard let eventStore else { return nil }

        var newestCreatedAtByRelay: [String: Int] = [:]
        for relayURL in resolvedRelays {
            if let newestCreatedAt = try? eventStore.syncCursor(
                accountID: accountID,
                timelineKey: "home",
                relayURL: relayURL
            )?.newestCreatedAt {
                newestCreatedAtByRelay[relayURL] = newestCreatedAt
            }
        }
        return newestCreatedAtByRelay
    }

    private func handleRuntimePacket(_ packet: NostrRelayRuntimePacket) async {
        guard !Self.isProfileDirectoryPacket(packet) else { return }
        await timelineCoordinator.handleRuntimePacket(
            packet,
            handlers: HomeTimelineRuntimePacketHandlers(
                shouldHandle: { self.phase != .idle },
                stateChanged: { relayURL, state in
                    self.handleRuntimeStateChange(relayURL: relayURL, state: state)
                },
                requestStarted: { attempt in
                    self.handleFeedSyncRequestStarted(attempt)
                },
                requestInstalled: { requestID, _, _, installedAt in
                    try? self.eventStore?.markFeedSyncRequestInstalled(
                        requestID: requestID,
                        at: installedAt
                    )
                },
                requestEnded: { end in
                    self.handleFeedSyncRequestEnded(end)
                },
                event: { relayURL, subscriptionID, event in
                    await self.handleRuntimeEvent(
                        relayURL: relayURL,
                        subscriptionID: subscriptionID,
                        event: event
                    )
                },
                eose: { relayURL, subscriptionID in
                    let window = self.finishRuntimeSyncWindow(relayURL: relayURL, subscriptionID: subscriptionID)
                    let isHomeForward = Self.isHomeForwardSubscription(subscriptionID)
                    self.recordFeedSyncEOSE(
                        relayURL: relayURL,
                        subscriptionID: subscriptionID,
                        window: window
                    )
                    self.recordRuntimeSyncEvent(
                        relayURL: relayURL,
                        kind: .eose,
                        subscriptionID: subscriptionID,
                        eventCount: window.eventCount,
                        newestCreatedAt: isHomeForward ? window.newestCreatedAt : nil,
                        oldestCreatedAt: isHomeForward ? window.oldestCreatedAt : nil,
                        message: "EOSE received"
                    )
                },
                closed: { relayURL, subscriptionID, message in
                    let window = self.finishRuntimeSyncWindow(relayURL: relayURL, subscriptionID: subscriptionID)
                    self.endFeedSyncRequest(
                        relayURL: relayURL,
                        subscriptionID: subscriptionID,
                        reason: .closed,
                        message: message,
                        window: window
                    )
                    self.recordRuntimeSyncEvent(
                        relayURL: relayURL,
                        kind: Self.syncEventKind(forClosedMessage: message),
                        subscriptionID: subscriptionID,
                        eventCount: window.eventCount,
                        newestCreatedAt: window.newestCreatedAt,
                        oldestCreatedAt: window.oldestCreatedAt,
                        message: message
                    )
                },
                timeout: { relayURL, subscriptionID, message in
                    let window = self.finishRuntimeSyncWindow(relayURL: relayURL, subscriptionID: subscriptionID)
                    self.endFeedSyncRequest(
                        relayURL: relayURL,
                        subscriptionID: subscriptionID,
                        reason: .timeout,
                        message: message,
                        window: window
                    )
                    self.recordRuntimeSyncEvent(
                        relayURL: relayURL,
                        kind: .timeout,
                        subscriptionID: subscriptionID,
                        eventCount: window.eventCount,
                        newestCreatedAt: window.newestCreatedAt,
                        oldestCreatedAt: window.oldestCreatedAt,
                        message: message
                    )
                },
                backwardCompleted: { completion in
                    self.handleBackwardCompletion(completion)
                },
                traffic: { delta in
                    self.handleRelayTraffic(delta)
                },
                notice: { relayURL, message in
                    self.recordRuntimeSyncEvent(
                        relayURL: relayURL,
                        kind: message.lowercased().contains("timeout") ? .timeout : .partialFailure,
                        subscriptionID: NostrHomeForwardREQBuilder.subscriptionID,
                        message: message
                    )
                },
                auth: { relayURL, challenge in
                    guard !self.hasRecentRuntimeSyncEvent(
                        relayURL: relayURL,
                        kind: .authRequired,
                        message: challenge
                    ) else { return }
                    self.recordRuntimeSyncEvent(
                        relayURL: relayURL,
                        kind: .authRequired,
                        subscriptionID: NostrHomeForwardREQBuilder.subscriptionID,
                        message: challenge
                    )
                }
            )
        )
    }

    private func handleRelayTraffic(_ delta: NostrRelayTrafficDelta) {
        pendingRelayTrafficDeltas.append(delta)
        let now = delta.occurredAt
        guard pendingRelayTrafficDeltas.count >= 50 || now - lastRelayTrafficFlushAt >= 5 else {
            return
        }
        flushRelayTrafficDeltas(now: now)
    }

    private func flushRelayTrafficDeltas(now: Int = Int(Date().timeIntervalSince1970)) {
        guard !pendingRelayTrafficDeltas.isEmpty, let eventStore else { return }
        let deltas = pendingRelayTrafficDeltas
        pendingRelayTrafficDeltas = []
        lastRelayTrafficFlushAt = now
        do {
            try eventStore.recordRelayTraffic(deltas)
        } catch {
            pendingRelayTrafficDeltas.insert(contentsOf: deltas, at: 0)
        }
    }

    private func handleRuntimeStateChange(relayURL: String, state: NostrRelayConnectionState) {
        guard resolvedRelays.contains(relayURL) else { return }
        relayRuntimeStates[relayURL] = state
        updateRelayStatusCounts()
        switch state {
        case .connected:
            recordRuntimeSyncEvent(relayURL: relayURL, kind: .connected, subscriptionID: nil, message: "connected")
        case .waitingForRetry, .retrying:
            invalidateHomeTimelineRealtime(relayURL: relayURL)
            recordRuntimeSyncEvent(relayURL: relayURL, kind: .reconnect, subscriptionID: nil, message: state.rawValue)
        case .error:
            invalidateHomeTimelineRealtime(relayURL: relayURL)
            recordRuntimeSyncEvent(relayURL: relayURL, kind: .partialFailure, subscriptionID: nil, message: state.rawValue)
        case .rejected:
            invalidateHomeTimelineRealtime(relayURL: relayURL)
            recordRuntimeSyncEvent(relayURL: relayURL, kind: .rejected, subscriptionID: nil, message: state.rawValue)
        case .suspended:
            invalidateHomeTimelineRealtime(relayURL: relayURL)
            recordRuntimeSyncEvent(relayURL: relayURL, kind: .suspended, subscriptionID: nil, message: state.rawValue)
        case .initialized, .connecting, .dormant, .terminated:
            invalidateHomeTimelineRealtime(relayURL: relayURL)
        }
    }

    private static func syncEventKind(forClosedMessage message: String) -> NostrRelaySyncEventKind {
        let normalized = message.lowercased()
        if normalized.contains("auth-required") || normalized.contains("auth required") {
            return .authRequired
        }
        if normalized.contains("payment-required") || normalized.contains("payment required") {
            return .paymentRequired
        }
        return .closed
    }

    private static func isHomeForwardSubscription(_ subscriptionID: String) -> Bool {
        HomeTimelineSyncPlanner.isHomeForwardSubscription(subscriptionID)
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
        if Self.isHomeForwardSubscription(subscriptionID) {
            await handleHomeForwardEvent(relayURL: relayURL, subscriptionID: subscriptionID, event: event)
            return
        }

        await handleBackwardEvent(relayURL: relayURL, subscriptionID: subscriptionID, event: event)
    }

    private func pendingBackwardRequestKey(for subscriptionID: String) -> String? {
        if let exactOrPrefixed = pendingBackwardRequests.first(where: { entry in
            subscriptionID == entry.key || subscriptionID.hasPrefix(entry.key + "-")
        })?.key {
            return exactOrPrefixed
        }
        if subscriptionID.contains("astrenza-gap-notes") {
            return pendingBackwardRequests.first { $0.value.gap != nil }?.key
        }
        if subscriptionID.contains("astrenza-older-notes") {
            return pendingBackwardRequests.first { $0.value.isOlderPage }?.key
        }
        return nil
    }

    private func handleHomeForwardEvent(relayURL: String, subscriptionID: String, event: NostrEvent) async {
        guard event.kind == 1 || event.kind == 5 || event.kind == 6,
              let account
        else { return }
        let receivedWhileRealtime = isHomeTimelineRealtime
        let lifecycleGeneration = runtimeLifecycleGeneration
        let accountID = account.pubkey

        let runtimeKey = RuntimeSubscriptionKey(relayURL: relayURL, subscriptionID: subscriptionID)
        let requestID = feedSyncLifecycle.requestID(for: runtimeKey)
        let requestContext = feedSyncLifecycle.context(for: runtimeKey)

        let ingestResult: HomeTimelineEventIngestResult
        let projectsIntoCurrentFeed: Bool
        do {
            ensureHomeFeedDefinition(account: account)
            projectsIntoCurrentFeed = isCurrentHomeFeedContext(requestContext) &&
                requestContext?.includes(event) == true
            let insertedAt = Int(Date().timeIntervalSince1970)
            let feedMembership = projectsIntoCurrentFeed ? homeFeedProjection.definition.flatMap { definition in
                HomeFeedProjectionBuilder.memberships(
                    events: [event],
                    feedID: definition.feedID,
                    feedRevision: definition.revision,
                    reason: "forward",
                    insertedAt: insertedAt
                ).first
            } : nil
            let feedMembershipSources = projectsIntoCurrentFeed ? homeFeedProjection.definition.map { definition in
                HomeFeedProjectionBuilder.membershipSources(
                    events: [event],
                    feedID: definition.feedID,
                    feedRevision: definition.revision,
                    reason: "forward",
                    insertedAt: insertedAt,
                    sourceRequestID: requestID
                )
            } ?? [] : []
            ingestResult = try await eventIngestor.ingest(
                event: event,
                relayURL: relayURL,
                feedMembership: feedMembership,
                feedMembershipSources: feedMembershipSources
            )
        } catch {
            recordRuntimeSyncEvent(
                relayURL: relayURL,
                kind: .partialFailure,
                subscriptionID: subscriptionID,
                message: "event save failed: \(error.localizedDescription)"
            )
            return
        }
        guard runtimeLifecycleGeneration == lifecycleGeneration,
              self.account?.pubkey == accountID
        else { return }
        let embeddedTarget = ingestResult.embeddedEvent
        invalidateListEntries()

        if event.kind == 5, projectsIntoCurrentFeed {
            let deletedAnchor = removeEventsDeletedFromCurrentProjection(by: event)
            _ = reloadProjectionWindow(account: account, around: deletedAnchor)
            scheduleMaterializeEntries(allowsRealtimeFollow: receivedWhileRealtime)
        } else if projectsIntoCurrentFeed {
            await enqueueBackwardDependencies(for: event)
            if let embeddedTarget {
                await enqueueBackwardDependencies(for: embeddedTarget)
            }
            if restoreProjectionAnchorEventID == nil,
               isTimelineAtNewestWindow,
                unmaterializedNewEventIDs.isEmpty {
                materializationScheduler.requestNewestProjectionReload()
                scheduleMaterializeEntries(allowsRealtimeFollow: receivedWhileRealtime)
            } else if unmaterializedNewEventIDs.insert(event.id).inserted {
                scheduleUnmaterializedCountPublish()
            }
        }
        scheduleLinkPreviewResolution()
        trackRuntimeSyncWindow(relayURL: relayURL, subscriptionID: subscriptionID, event: event)
    }

    private func handleBackwardEvent(relayURL: String, subscriptionID: String, event: NostrEvent) async {
        guard let account else { return }
        let lifecycleGeneration = runtimeLifecycleGeneration
        let accountID = account.pubkey
        let requestKey = pendingBackwardRequestKey(for: subscriptionID)
        let request = requestKey.flatMap { pendingBackwardRequests[$0] }
        let isTimelineBackfill = request?.isOlderPage == true || request?.gap != nil
        let runtimeKey = RuntimeSubscriptionKey(relayURL: relayURL, subscriptionID: subscriptionID)
        let sourceRequestID = feedSyncLifecycle.requestID(for: runtimeKey)
        let activeRequestContext = feedSyncLifecycle.context(for: runtimeKey)
        let requestContext = request?.feedContext

        let ingestResult: HomeTimelineEventIngestResult
        let projectsIntoCurrentFeed: Bool
        do {
            if isTimelineBackfill {
                ensureHomeFeedDefinition(account: account)
            }
            // 配信可否はpendingBackwardRequestsで判定する。provenance用requestStartedは
            // 最初のEVENT到着時点でまだqueue内に残っている場合がある。
            projectsIntoCurrentFeed = isTimelineBackfill &&
                requestContext != nil &&
                (activeRequestContext == nil || requestContext == activeRequestContext) &&
                isCurrentHomeFeedContext(requestContext) &&
                requestContext?.includes(event) == true
            let insertedAt = Int(Date().timeIntervalSince1970)
            let timelineSource = request?.isOlderPage == true ? "older" : "gap"
            let feedMembership = projectsIntoCurrentFeed ? homeFeedProjection.definition.flatMap { definition in
                HomeFeedProjectionBuilder.memberships(
                    events: [event],
                    feedID: definition.feedID,
                    feedRevision: definition.revision,
                    reason: timelineSource,
                    insertedAt: insertedAt
                ).first
            } : nil
            let feedMembershipSources = projectsIntoCurrentFeed ? homeFeedProjection.definition.map { definition in
                HomeFeedProjectionBuilder.membershipSources(
                    events: [event],
                    feedID: definition.feedID,
                    feedRevision: definition.revision,
                    reason: timelineSource,
                    insertedAt: insertedAt,
                    sourceRequestID: sourceRequestID
                )
            } ?? [] : []
            ingestResult = try await eventIngestor.ingest(
                event: event,
                relayURL: relayURL,
                feedMembership: feedMembership,
                feedMembershipSources: feedMembershipSources
            )
        } catch {
            recordRuntimeSyncEvent(
                relayURL: relayURL,
                kind: .partialFailure,
                subscriptionID: subscriptionID,
                message: "backward event save failed: \(error.localizedDescription)"
            )
            return
        }
        guard runtimeLifecycleGeneration == lifecycleGeneration,
              self.account?.pubkey == accountID
        else { return }
        let embeddedTarget = ingestResult.embeddedEvent
        if event.kind == 1 || event.kind == 5 || event.kind == 6 {
            invalidateListEntries()
        }

        switch event.kind {
        case 0:
            let effectiveMetadataEvent = rememberLatestMetadataEvent(event)
            resolveNIP05IfNeeded(for: effectiveMetadataEvent)
            scheduleMaterializeEntries()
        case 1, 6:
            if projectsIntoCurrentFeed {
                if let requestKey {
                    pendingBackwardRequests[requestKey]?.receivedTimelineEventCount += 1
                    if pendingBackwardRequests[requestKey]?.receivedTimelineEventIDs.contains(event.id) != true {
                        pendingBackwardRequests[requestKey]?.receivedTimelineEventIDs.append(event.id)
                    }
                }
            }
            dependencyCoordinator.finishSourceEvent(eventID: event.id)
            if !isTimelineBackfill || projectsIntoCurrentFeed {
                await enqueueBackwardDependencies(for: event)
                if let embeddedTarget {
                    await enqueueBackwardDependencies(for: embeddedTarget)
                }
            }
            if !isTimelineBackfill {
                scheduleMaterializeEntries(
                    delayNanoseconds: materializationScheduler.defaultDelayNanoseconds * 2
                )
            }
        case 5:
            if !isTimelineBackfill || projectsIntoCurrentFeed {
                let deletedAnchor = removeEventsDeletedFromCurrentProjection(by: event)
                _ = reloadProjectionWindow(account: account, around: deletedAnchor)
                materializeEntries()
            }
        default:
            break
        }

        scheduleLinkPreviewResolution()
        trackRuntimeSyncWindow(relayURL: relayURL, subscriptionID: subscriptionID, event: event)
    }

    private func removeEventsDeletedFromCurrentProjection(by deletionEvent: NostrEvent) -> String? {
        let targetEventIDs = Set(deletionEvent.tags.compactMap { tag in
            tag.count >= 2 && tag[0] == "e" ? tag[1] : nil
        })
        guard !targetEventIDs.isEmpty else { return nil }
        noteEvents.removeAll { event in
            targetEventIDs.contains(event.id) && event.pubkey == deletionEvent.pubkey
        }
        return targetEventIDs.sorted().first
    }

    private func enqueueBackwardDependencies(for event: NostrEvent) async {
        guard relayRuntime != nil, !resolvedRelays.isEmpty, let accountID = account?.pubkey else { return }
        let lifecycleGeneration = runtimeLifecycleGeneration
        let result = await dependencyCoordinator.enqueueDependencies(
            for: event,
            liveMetadataEvents: metadataEvents,
            liveNoteEventIDs: Set(noteEvents.map(\.id)),
            availableRelayURLs: resolvedRelays
        )
        guard runtimeLifecycleGeneration == lifecycleGeneration,
              account?.pubkey == accountID
        else { return }
        result.cachedProfiles.forEach { profile in
            rememberLatestMetadataEvent(profile, consultEventStore: false)
        }
        if !result.cachedProfiles.isEmpty || result.didResolveCachedDependencies {
            scheduleMaterializeEntries()
        }
        if result.didEnqueueSourceDependencies {
            scheduleBackwardDependencyFlush()
        }
    }

    private func ensureProfileDirectoryDependencies(for events: [NostrEvent]) async {
        await dependencyCoordinator.ensureProfiles(for: events)
    }

    private func resolveNIP05IfNeeded(for metadataEvent: NostrEvent) {
        dependencyCoordinator.resolveNIP05IfNeeded(for: metadataEvent) { [weak self] in
            guard let self else { return }
            self.invalidateListEntries()
            self.scheduleMaterializeEntries()
            if let account = self.account {
                await self.persistTimelineMetadata(account: account)
            }
        }
    }

    private func scheduleBackwardDependencyFlush() {
        guard dependencyFlushTask == nil else { return }
        dependencyFlushTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 12_000_000)
            await MainActor.run {
                self?.flushBackwardDependencies()
            }
        }
    }

    private func flushBackwardDependencies() {
        guard let relayRuntime else { return }
        dependencyFlushTask = nil
        let plan = dependencyCoordinator.drainSourcePacketPlan()
        guard !plan.isEmpty else { return }
        guard let accountID = account?.pubkey else { return }
        let lifecycleGeneration = runtimeLifecycleGeneration

        Task {
            do {
                if !plan.sourcePackets.isEmpty {
                    try await relayRuntime.installBackward(plan.sourcePackets, mergeField: .ids)
                }
            } catch {
                await MainActor.run {
                    guard runtimeLifecycleGeneration == lifecycleGeneration,
                          account?.pubkey == accountID
                    else { return }
                    dependencyCoordinator.failSourceRequests(in: plan)
                    recordRuntimeSyncEvent(
                        relayURL: resolvedRelays.first ?? "runtime",
                        kind: .partialFailure,
                        subscriptionID: nil,
                        message: "backward enqueue failed: \(error.localizedDescription)"
                    )
                }
            }
        }
    }

    private func handleBackwardCompletion(_ completion: NostrBackwardREQCompletion) {
        guard let request = pendingBackwardRequests.removeValue(forKey: completion.groupID) else {
            if dependencyCoordinator.completeSourceRequest(completion) {
                relayStatusRevision &+= 1
            }
            return
        }
        let priorBottomPostID = request.olderAnchorPostID ?? noteEvents.last?.id
        let isTimelineBackfill = request.isOlderPage || request.gap != nil
        guard !isTimelineBackfill || isCurrentHomeFeedContext(request.feedContext) else {
            relayStatusRevision &+= 1
            return
        }
        if request.isOlderPage && completion.status == .completed && completion.eventCount == 0 {
            hasMoreOlder = false
        }
        let didReceiveTimelineEvents = completion.eventCount > 0 ||
            request.receivedTimelineEventCount > 0 ||
            !request.receivedTimelineEventIDs.isEmpty
        if request.isOlderPage,
           didReceiveTimelineEvents,
           let account {
            if completion.status != .completed {
                markOlderPageBoundaryGap(request)
            }
            reloadProjectionWindow(
                account: account,
                around: priorBottomPostID,
                mergingWithCurrentWindow: true
            )
            materializeEntries()
            scheduleLinkPreviewResolution()
        }

        if let gap = request.gap,
           let feedContext = request.feedContext,
           let account {
            if completion.status == .completed {
                reconcileCompletedGap(gap, context: feedContext)
            } else {
                if completion.status == .partial || didReceiveTimelineEvents {
                    markGapUnresolved(gap, context: feedContext)
                }
                // eventなしのtimeout/CLOSEDでも永続化済みgapを再投影する。
                // bootstrap保存と競合するとeventだけのwindowが残る場合があるため。
                reloadProjectionWindow(account: account, around: gap.stableAnchorPostID)
                materializeEntries()
                scheduleLinkPreviewResolution()
            }
        }
        relayStatusRevision &+= 1
    }

    private func markOlderPageBoundaryGap(_ request: PendingBackwardRequest) {
        guard account != nil,
              let definition = homeFeedProjection.definition,
              let anchorPostID = request.olderAnchorPostID,
              let newestReceivedEventID = newestReceivedTimelineEventID(in: request)
        else { return }
        do {
            try eventStore?.markFeedGap(
                feedID: definition.feedID,
                revision: definition.revision,
                newerEventID: anchorPostID,
                olderEventID: newestReceivedEventID,
                state: .unresolved,
                sourceRequestID: request.sourceRequestIDs.last
            )
        } catch {
            recordRuntimeSyncEvent(
                relayURL: resolvedRelays.first ?? "runtime",
                kind: .partialFailure,
                subscriptionID: nil,
                message: "older gap mark failed: \(error.localizedDescription)"
            )
        }
    }

    private func newestReceivedTimelineEventID(in request: PendingBackwardRequest) -> String? {
        guard let eventStore else { return nil }
        let uniqueEventIDs = Array(Set(request.receivedTimelineEventIDs))
        guard !uniqueEventIDs.isEmpty,
              let events = try? eventStore.events(ids: uniqueEventIDs)
        else { return nil }
        return events.max { lhs, rhs in
            if lhs.createdAt == rhs.createdAt {
                return lhs.id > rhs.id
            }
            return lhs.createdAt < rhs.createdAt
        }?.id
    }

    private func markGapResolved(_ gap: PendingGapBackfill, context: HomeFeedRuntimeContext) {
        guard account != nil, isCurrentHomeFeedContext(context) else { return }
        do {
            try eventStore?.resolveFeedGap(
                feedID: context.feedID,
                revision: context.revision,
                newerEventID: gap.newerPostID,
                olderEventID: gap.olderPostID
            )
        } catch {
            recordRuntimeSyncEvent(
                relayURL: resolvedRelays.first ?? "runtime",
                kind: .partialFailure,
                subscriptionID: nil,
                message: "gap resolve failed: \(error.localizedDescription)"
            )
        }
    }

    private func markGapUnresolved(_ gap: PendingGapBackfill, context: HomeFeedRuntimeContext) {
        guard isCurrentHomeFeedContext(context) else { return }
        try? eventStore?.markFeedGap(
            feedID: context.feedID,
            revision: context.revision,
            newerEventID: gap.newerPostID,
            olderEventID: gap.olderPostID,
            state: .unresolved
        )
    }

    private func reconcileCompletedGap(
        _ gap: PendingGapBackfill,
        context: HomeFeedRuntimeContext
    ) {
        guard let accountID = account?.pubkey,
              accountID == context.accountID,
              isCurrentHomeFeedContext(context)
        else { return }
        let lifecycleGeneration = runtimeLifecycleGeneration
        let reconciliationID = "\(context.feedID)#\(context.revision):\(gap.newerPostID)-\(gap.olderPostID)"
        pendingGapReconciliationIDs.insert(reconciliationID)
        relayStatusRevision &+= 1

        Task { [weak self] in
            await self?.runCompletedGapReconciliation(
                gap,
                reconciliationID: reconciliationID,
                accountID: accountID,
                lifecycleGeneration: lifecycleGeneration,
                context: context
            )
        }
    }

    private func runCompletedGapReconciliation(
        _ gap: PendingGapBackfill,
        reconciliationID: String,
        accountID: String,
        lifecycleGeneration: UInt64,
        context: HomeFeedRuntimeContext
    ) async {
        defer {
            if self.runtimeLifecycleGeneration == lifecycleGeneration,
               self.account?.pubkey == accountID {
                pendingGapReconciliationIDs.remove(reconciliationID)
                relayStatusRevision &+= 1
            }
        }

        guard runtimeLifecycleGeneration == lifecycleGeneration,
              let account,
              account.pubkey == accountID,
              isCurrentHomeFeedContext(context),
              let newerEvent = timelineEvent(id: gap.newerPostID),
              let olderEvent = timelineEvent(id: gap.olderPostID)
        else { return }

        let output = await gapReconciler.reconcile(
            newerEvent: newerEvent,
            olderEvent: olderEvent,
            context: context,
            relays: Array(resolvedRelays.prefix(4)),
            inMemoryEvents: noteEvents
        )
        guard runtimeLifecycleGeneration == lifecycleGeneration,
              self.account?.pubkey == accountID,
              isCurrentHomeFeedContext(context)
        else { return }
        for diagnostic in output.diagnostics {
            recordRuntimeSyncEvent(
                relayURL: diagnostic.relayURL,
                kind: .partialFailure,
                subscriptionID: "astrenza-neg-gap",
                message: diagnostic.message
            )
        }
        switch output.result {
        case .verifiedComplete:
            markGapResolved(gap, context: context)
        case .indeterminate:
            markGapUnresolved(gap, context: context)
            recordRuntimeSyncEvent(
                relayURL: resolvedRelays.first ?? "runtime",
                kind: .partialFailure,
                subscriptionID: "astrenza-neg-gap",
                message: "gap reconciliation was inconclusive"
            )
        case .recovered(let recoveredEvents):
            do {
                let insertedAt = Int(Date().timeIntervalSince1970)
                let scopedEvents = recoveredEvents.filter(context.includes)
                let feedMemberships = HomeFeedProjectionBuilder.memberships(
                    events: scopedEvents,
                    feedID: context.feedID,
                    feedRevision: context.revision,
                    reason: "gap-negentropy",
                    insertedAt: insertedAt
                )
                let feedMembershipSources = HomeFeedProjectionBuilder.membershipSources(
                    events: scopedEvents,
                    feedID: context.feedID,
                    feedRevision: context.revision,
                    reason: "gap-negentropy",
                    insertedAt: insertedAt
                )
                try eventStore?.ingest(
                    events: scopedEvents,
                    eventSources: [],
                    feedMemberships: feedMemberships,
                    feedMembershipSources: feedMembershipSources,
                    receivedAt: insertedAt
                )
                for event in scopedEvents {
                    await enqueueBackwardDependencies(for: event)
                }
                markGapUnresolved(gap, context: context)
            } catch {
                recordRuntimeSyncEvent(
                    relayURL: resolvedRelays.first ?? "runtime",
                    kind: .partialFailure,
                    subscriptionID: "astrenza-gap-events",
                    message: "gap negentropy save failed: \(error.localizedDescription)"
                )
                return
            }
        }

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
        message: String?,
        publishesStatusChange: Bool = true
    ) {
        guard let account else { return }
        relayDiagnostics.record(
            accountID: account.pubkey,
            relayURL: relayURL,
            kind: kind,
            occurredAt: Int(Date().timeIntervalSince1970),
            subscriptionID: subscriptionID,
            eventCount: eventCount,
            newestCreatedAt: newestCreatedAt,
            oldestCreatedAt: oldestCreatedAt,
            message: message
        )
        updateRelayStatusCounts()
        if publishesStatusChange {
            relayStatusRevision &+= 1
        }
    }

    private func handleFeedSyncRequestStarted(_ attempt: NostrRelayRequestAttempt) {
        guard let registration = feedSyncRegistration(for: attempt.packet)
        else { return }

        let key = RuntimeSubscriptionKey(
            relayURL: attempt.relayURL,
            subscriptionID: attempt.packet.subscriptionID
        )
        if attempt.packet.strategy == .forward {
            invalidateHomeTimelineRealtime(for: key)
        }
        guard let eventStore else { return }

        do {
            try feedSyncLifecycle.beginRequest(
                attempt,
                context: registration.context,
                direction: registration.direction,
                purpose: registration.purpose
            )
            if let pendingRequestKey = registration.pendingRequestKey {
                pendingBackwardRequests[pendingRequestKey]?.sourceRequestIDs.append(attempt.requestID)
            }
            if let gap = registration.gap,
               isCurrentHomeFeedContext(registration.context) {
                try? eventStore.markFeedGap(
                    feedID: registration.context.feedID,
                    revision: registration.context.revision,
                    newerEventID: gap.newerPostID,
                    olderEventID: gap.olderPostID,
                    state: .requested,
                    sourceRequestID: attempt.requestID,
                    at: attempt.startedAt
                )
            }
        } catch {
            recordRuntimeSyncEvent(
                relayURL: attempt.relayURL,
                kind: .partialFailure,
                subscriptionID: attempt.packet.subscriptionID,
                message: "feed sync request save failed: \(error.localizedDescription)"
            )
        }
    }

    private func feedSyncRegistration(for packet: NostrREQPacket) -> HomeFeedSyncRegistration? {
        if packet.strategy == .forward, Self.isHomeForwardSubscription(packet.subscriptionID) {
            guard let context = feedSyncLifecycle.forwardContext(groupID: packet.groupID) else { return nil }
            let hasSince = packet.filters.contains { $0["since"] != nil }
            return HomeFeedSyncRegistration(
                context: context,
                direction: .forward,
                purpose: hasSince ? .newer : .initial,
                pendingRequestKey: nil,
                gap: nil
            )
        }
        guard packet.strategy == .backward,
              let requestKey = pendingBackwardRequestKey(for: packet.subscriptionID),
              let request = pendingBackwardRequests[requestKey],
              let context = request.feedContext
        else { return nil }
        if request.gap != nil {
            return HomeFeedSyncRegistration(
                context: context,
                direction: .backward,
                purpose: .gap,
                pendingRequestKey: requestKey,
                gap: request.gap
            )
        }
        if request.isOlderPage {
            return HomeFeedSyncRegistration(
                context: context,
                direction: .backward,
                purpose: .older,
                pendingRequestKey: requestKey,
                gap: nil
            )
        }
        return nil
    }

    private func recordFeedSyncEOSE(
        relayURL: String,
        subscriptionID: String,
        window: RuntimeSyncWindow
    ) {
        let key = RuntimeSubscriptionKey(relayURL: relayURL, subscriptionID: subscriptionID)
        let isForward = Self.isHomeForwardSubscription(subscriptionID)
        // Forward REQはEOSE後もlive subscriptionとして継続するため、
        // lifecycleがrevision contextとrequest provenanceをCLOSED/置換まで保持します。
        feedSyncLifecycle.recordEOSE(
            key: key,
            isForward: isForward,
            window: window,
            at: Int(Date().timeIntervalSince1970)
        )
        publishHomeTimelineRealtimeState()
    }

    private func endFeedSyncRequest(
        relayURL: String,
        subscriptionID: String,
        reason: NostrFeedSyncEndReason,
        message: String? = nil,
        window: RuntimeSyncWindow
    ) {
        let key = RuntimeSubscriptionKey(relayURL: relayURL, subscriptionID: subscriptionID)
        feedSyncLifecycle.endRequest(
            key: key,
            reason: reason,
            message: message,
            window: window,
            at: Int(Date().timeIntervalSince1970)
        )
        publishHomeTimelineRealtimeState()
    }

    private func handleFeedSyncRequestEnded(_ end: NostrRelayRequestAttemptEnd) {
        feedSyncLifecycle.endRequestAttempt(end)
        publishHomeTimelineRealtimeState()
    }

    private func finishActiveFeedSyncRequests(reason: NostrFeedSyncEndReason) {
        feedSyncLifecycle.finishActiveRequests(
            reason: reason,
            at: Int(Date().timeIntervalSince1970)
        )
    }

    private func trackRuntimeSyncWindow(relayURL: String, subscriptionID: String, event: NostrEvent) {
        let key = RuntimeSubscriptionKey(relayURL: relayURL, subscriptionID: subscriptionID)
        feedSyncLifecycle.record(event, for: key)
    }

    private func finishRuntimeSyncWindow(relayURL: String, subscriptionID: String) -> RuntimeSyncWindow {
        let key = RuntimeSubscriptionKey(relayURL: relayURL, subscriptionID: subscriptionID)
        return feedSyncLifecycle.finishWindow(for: key)
    }

    private func hasRecentRuntimeSyncEvent(
        relayURL: String,
        kind: NostrRelaySyncEventKind,
        message: String?
    ) -> Bool {
        relayDiagnostics.hasRecentEvent(relayURL: relayURL, kind: kind, message: message)
    }

    private func databaseBackfillEvents(account: NostrAccount, current: NostrHomeTimelineState) -> [NostrEvent]? {
        guard let eventStore,
              let until = current.noteEvents.map(\.createdAt).min().map({ max(0, $0 - 1) })
        else {
            return nil
        }

        let authors = current.followedPubkeys.isEmpty ? [account.pubkey] : current.followedPubkeys
        guard let events = try? eventStore.events(kind: 1, authors: authors, until: until, limit: 1_000),
              !events.isEmpty
        else {
            return nil
        }
        return events
    }

    private func materializeEntries(allowsRealtimeFollow: Bool = false) {
        guard let pass = materializationScheduler.beginMaterialization(
            allowsRealtimeFollow: allowsRealtimeFollow
        ) else { return }
        if pass.shouldReloadNewestProjection, let account {
            reloadNewestProjectionWindow(account: account)
            materializationScheduler.clearNewestProjectionReload()
        }
        let filterRules = homeFilterRules()
        let activeFilterRuleSet = filterRules.isEmpty ? nil : NostrFilterRuleSet(rules: filterRules)
        let materializerFilterRuleSet = areTimelineFiltersSuspended ? nil : activeFilterRuleSet
        let contextEvents = contextEventsForCurrentProjection()
        let snapshot = timelineRepository.materialize(
            account: account,
            noteEvents: noteEvents,
            feedWindow: homeFeedProjection.window,
            contextEvents: contextEvents,
            metadataEvents: metadataEvents,
            nip05Resolutions: dependencyCoordinator.nip05Resolutions,
            profileResolutionStates: profileResolutionStates,
            followedPubkeys: followedPubkeys,
            resolvedRelays: resolvedRelays,
            filterRules: materializerFilterRuleSet,
            filterStatus: timelineFilterStatus(ruleSet: activeFilterRuleSet),
            policy: syncPolicy
        )
        var didChangePublishedContent = false
        if materializationScheduler.shouldPublish(
            renderFingerprint: snapshot.renderFingerprint
        ) {
            entries = snapshot.entries
            didChangePublishedContent = true
        }
        unreadState.replaceMaterializedPostIDs(entries.compactMap(\.post?.id))
        publishUnreadState()

        if snapshot.filterStatus != filterStatus {
            filterStatus = snapshot.filterStatus
            didChangePublishedContent = true
        }
        if didChangePublishedContent {
            resolvedContentRevision &+= 1
            materializationScheduler.didPublish(
                revision: resolvedContentRevision,
                allowsRealtimeFollow: pass.allowsRealtimeFollow
            )
            realtimeFollowSourceRevision = materializationScheduler.realtimeFollowSourceRevision
        }
    }

    private func publishUnreadState() {
        materializedUnreadCount = unreadState.materializedUnreadCount
        visibleUnreadBadgeCount = unreadState.visibleUnreadBadgeCount
    }

    private func scheduleMaterializeEntries(
        delayNanoseconds: UInt64? = nil,
        allowsRealtimeFollow: Bool? = nil
    ) {
        materializationScheduler.schedule(
            delayNanoseconds: delayNanoseconds,
            allowsRealtimeFollow: allowsRealtimeFollow
        ) { [weak self] allowsRealtimeFollow in
            self?.materializeEntries(allowsRealtimeFollow: allowsRealtimeFollow)
        }
    }

    private func scheduleUnmaterializedCountPublish() {
        guard unmaterializedCountTask == nil else { return }
        unmaterializedCountTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 100_000_000)
            guard let self, !Task.isCancelled else { return }
            self.unmaterializedCountTask = nil
            let count = self.unmaterializedNewEventIDs.count
            if self.unmaterializedNewCount != count {
                self.unmaterializedNewCount = count
            }
        }
    }

    private func materializedPosts(from events: [NostrEvent]) -> [TimelinePost] {
        let profilePubkeys = Set(events.flatMap { event in
            NostrEventDependencies.extract(from: event).profilePubkeys
        })
        let storedMetadata = (try? eventStore?.latestReplaceableEvents(pubkeys: profilePubkeys, kind: 0)) ?? []
        let liveMetadata = metadataEvents.filter { profilePubkeys.contains($0.pubkey) }
        let metadata = storedMetadata + liveMetadata

        return NostrTimelineMaterializer.posts(
            noteEvents: events,
            metadataEvents: metadata,
            nip05Resolutions: dependencyCoordinator.nip05Resolutions,
            profileResolutionStates: profileResolutionStates,
            followedPubkeys: Set(followedPubkeys),
            mediaAssetsByEventID: mediaAssetsByEventID(for: events),
            linkPreviewsByNormalizedURL: linkPreviewsByNormalizedURL(for: events),
            filterRules: homeFilterRuleSet(),
            policy: syncPolicy
        )
    }

    private func homeFilterRuleSet() -> NostrFilterRuleSet? {
        guard !areTimelineFiltersSuspended else { return nil }
        let rules = homeFilterRules()
        guard !rules.isEmpty else { return nil }
        return NostrFilterRuleSet(rules: rules)
    }

    private func listFilterRuleSet() -> NostrFilterRuleSet? {
        guard let account, let eventStore else { return nil }
        let rules = ((try? eventStore.filterRules(accountID: account.pubkey)) ?? [])
            .filter { $0.applies(to: .lists) }
        guard !rules.isEmpty else { return nil }
        return NostrFilterRuleSet(rules: rules)
    }

    private func homeFilterRules() -> [NostrFilterRuleRecord] {
        guard let account, let eventStore else {
            return []
        }

        var rules = ((try? eventStore.filterRules(accountID: account.pubkey)) ?? [])
            .filter { $0.applies(to: .home) }
        let publicMuteItems = cachedPublicMuteItems(accountID: account.pubkey, eventStore: eventStore)
        rules.append(
            contentsOf: NostrFilterRuleSet.publicMuteRules(
                accountID: account.pubkey,
                items: publicMuteItems,
                updatedAt: Int(Date().timeIntervalSince1970)
            )
        )

        return rules
    }

    private func timelineFilterStatus(ruleSet: NostrFilterRuleSet?) -> TimelineFilterStatus {
        guard let ruleSet else {
            return TimelineFilterStatus(isSuspended: areTimelineFiltersSuspended)
        }

        var status = TimelineFilterStatus(
            activeRuleCount: ruleSet.rules.count,
            isSuspended: areTimelineFiltersSuspended
        )
        guard !areTimelineFiltersSuspended else { return status }

        let now = Int(Date().timeIntervalSince1970)
        for event in noteEvents {
            guard let match = ruleSet.matchDetail(event: event, timeline: .home, now: now) else { continue }
            switch match.rule.presentation {
            case .maskWithWarning:
                status.warningMatchCount += 1
            case .hide:
                status.hiddenMatchCount += 1
            }
        }
        return status
    }

    private func cachedPublicMuteItems(accountID: String, eventStore: NostrEventStore) -> [NostrListItemRecord] {
        guard let summaries = try? eventStore.listSummaries(accountID: accountID) else { return [] }
        return summaries
            .filter { $0.kind == 10_000 }
            .flatMap { summary in
                (try? eventStore.listItems(listID: summary.listID)) ?? []
            }
    }

    private func cachedListTimelineEvents(
        accountID: String,
        eventStore: NostrEventStore,
        limit: Int
    ) -> [NostrEvent] {
        guard let summaries = try? eventStore.listSummaries(accountID: accountID) else { return [] }
        var eventsByID: [String: NostrEvent] = [:]
        var remaining = max(0, limit)
        guard remaining > 0 else { return [] }

        for summary in summaries where remaining > 0 {
            let items = (try? eventStore.listItems(listID: summary.listID)) ?? []
            switch summary.kind {
            case 30_000:
                let authors = items
                    .filter { $0.itemType == "pubkey" }
                    .map(\.value)
                let events = (try? eventStore.events(kind: 1, authors: authors, limit: remaining)) ?? []
                for event in events where eventsByID[event.id] == nil {
                    eventsByID[event.id] = event
                    remaining -= 1
                    if remaining <= 0 { break }
                }
            case 10_003, 30_003:
                for item in items where item.itemType == "event" && remaining > 0 {
                    guard let event = try? eventStore.event(id: item.value),
                          event.kind == 1,
                          eventsByID[event.id] == nil
                    else { continue }
                    eventsByID[event.id] = event
                    remaining -= 1
                }
            default:
                break
            }
        }

        return eventsByID.values.sorted { lhs, rhs in
            if lhs.createdAt == rhs.createdAt {
                return lhs.id < rhs.id
            }
            return lhs.createdAt > rhs.createdAt
        }
    }

    private func mediaAssetsByEventID(for events: [NostrEvent]) -> [String: [NostrMediaAssetRecord]] {
        guard let eventStore else { return [:] }
        return (try? eventStore.mediaAssets(eventIDs: events.map(\.id))) ?? [:]
    }

    private func linkPreviewsByNormalizedURL(for events: [NostrEvent]) -> [String: NostrLinkPreviewRecord] {
        guard let eventStore else { return [:] }
        let urls = events.flatMap { NostrLinkParser.webURLs(in: $0.content) }
        return (try? eventStore.linkPreviews(urls: urls)) ?? [:]
    }

    private func materializedAuthor(pubkey: String, metadataEvent: NostrEvent?) -> TimelineAuthor {
        let metadata = metadataEvent.flatMap(Self.profileMetadata)
        guard metadataEvent != nil else {
            return .unresolved(
                pubkey: pubkey,
                state: profileResolutionStates[pubkey] ?? .unknown
            )
        }

        return .metadataResolved(
            displayName: metadata?.bestName,
            nip05: metadata?.nip05,
            nip05Status: NIP05Status(
                dependencyCoordinator.nip05Resolutions[pubkey]?.status ?? .unchecked
            ),
            pubkey: pubkey,
            isFollowed: followedPubkeys.contains(pubkey)
        )
    }

    private func avatar(for pubkey: String) -> AvatarStyle {
        let item = NostrHomeTimelineItem(
            id: pubkey,
            pubkey: pubkey,
            displayName: nil,
            nip05: nil,
            nip05Status: .absent,
            isFollowed: followedPubkeys.contains(pubkey),
            body: "",
            createdAt: Int(Date().timeIntervalSince1970),
            avatarPictureState: .metadataPending,
            avatarImageURL: nil,
            profileResolutionState: profileResolutionStates[pubkey] ?? .unknown
        )
        return NostrTimelineAuthorProjection.avatar(for: item)
    }

    private func banner(for pubkey: String) -> ProfileBannerStyle {
        let palette = NostrTimelineAuthorProjection.avatarPalette(for: pubkey)
        return ProfileBannerStyle(colors: [palette.secondary, palette.primary], symbolName: "sparkles")
    }

    private static func profileMetadata(from event: NostrEvent) -> NostrProfileMetadata? {
        guard let data = event.content.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(NostrProfileMetadata.self, from: data)
    }

    private func loaderState() -> NostrHomeTimelineState {
        NostrHomeTimelineState(
            relays: resolvedRelays,
            followedPubkeys: followedPubkeys,
            noteEvents: noteEvents,
            metadataEvents: metadataEvents,
            relayListEvent: relayListEvent,
            contactListEvent: contactListEvent,
            nip05Resolutions: dependencyCoordinator.nip05Resolutions,
            hasMoreOlder: hasMoreOlder,
            relaySyncEvents: relayDiagnostics.events
        )
    }

    private func apply(_ state: NostrHomeTimelineState) {
        let storedRelayListEvent = account.flatMap { account in
            try? eventStore?.latestReplaceableEvent(pubkey: account.pubkey, kind: 10002)
        }
        let storedContactListEvent = account.flatMap { account in
            try? eventStore?.latestReplaceableEvent(pubkey: account.pubkey, kind: 3)
        }
        let effectiveRelayListEvent = freshestReplaceableEvent([
            relayListEvent,
            state.relayListEvent,
            storedRelayListEvent
        ])
        let effectiveContactListEvent = freshestReplaceableEvent([
            contactListEvent,
            state.contactListEvent,
            storedContactListEvent
        ])
        let effectiveRelays = effectiveReadRelays(
            from: effectiveRelayListEvent,
            stateRelays: state.relays
        )
        let effectiveFollowedPubkeys: [String]
        if effectiveContactListEvent?.id != nil,
           effectiveContactListEvent?.id != state.contactListEvent?.id {
            effectiveFollowedPubkeys = NostrContactList.pubkeys(from: effectiveContactListEvent)
        } else {
            effectiveFollowedPubkeys = state.followedPubkeys
        }

        resolvedRelays = effectiveRelays
        followedPubkeys = effectiveFollowedPubkeys
        noteEvents = state.noteEvents
        metadataEvents = state.metadataEvents
        relayListEvent = effectiveRelayListEvent
        contactListEvent = effectiveContactListEvent
        dependencyCoordinator.replaceNIP05Resolutions(state.nip05Resolutions)
        relayDiagnostics.replaceEvents(state.relaySyncEvents)
        hasMoreOlder = state.hasMoreOlder
        homeFeedProjection.clearWindow()
        invalidateListEntries()
        updateRelayStatusCounts()
    }

    private func effectiveReadRelays(
        from relayListEvent: NostrEvent?,
        stateRelays: [String]
    ) -> [String] {
        let readRelays = NostrRelayList.parse(from: relayListEvent).readRelays
        if !readRelays.isEmpty {
            return readRelays
        }
        if !stateRelays.isEmpty {
            return stateRelays
        }
        return resolvedRelays
    }

    @discardableResult
    private func rememberLatestMetadataEvent(
        _ event: NostrEvent,
        consultEventStore: Bool = true
    ) -> NostrEvent {
        let storedMetadataEvent = consultEventStore
            ? try? eventStore?.latestReplaceableEvent(pubkey: event.pubkey, kind: 0)
            : nil
        let currentMetadataEvent = metadataEvents.first { $0.pubkey == event.pubkey }
        let effectiveMetadataEvent = freshestReplaceableEvent([
            currentMetadataEvent,
            event,
            storedMetadataEvent
        ]) ?? event
        let didChange = currentMetadataEvent?.id != effectiveMetadataEvent.id
        metadataEvents.removeAll { $0.pubkey == event.pubkey }
        metadataEvents.append(effectiveMetadataEvent)
        if didChange {
            invalidateListEntries()
        }
        return effectiveMetadataEvent
    }

    private func invalidateListEntries() {
        listEntriesCache = nil
        listContentRevision &+= 1
    }

    private func freshestReplaceableEvent(_ events: [NostrEvent?]) -> NostrEvent? {
        events.compactMap(\.self).max { lhs, rhs in
            if lhs.createdAt == rhs.createdAt {
                return lhs.id > rhs.id
            }
            return lhs.createdAt < rhs.createdAt
        }
    }
}

#if DEBUG
extension NostrHomeTimelineStore {
    func testingSetMaterializedPostIDs(_ ids: [TimelinePost.ID]) {
        entries = ids.map { id in
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
        materializationScheduler.replaceRenderFingerprint(entries.map { $0.id.hashValue })
        unreadState.replaceMaterializedPostIDs(ids, marksInitialWindowRead: false)
        publishUnreadState()
    }

    func testingSetReadBoundary(postID: TimelinePost.ID) {
        unreadState.setReadBoundary(postID: postID)
        publishUnreadState()
    }

    func testingSetUnmaterializedNewEventIDs(_ ids: Set<String>) {
        unmaterializedNewEventIDs = ids
        unmaterializedNewCount = ids.count
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
        self.account = account
        followedPubkeys = sourceAuthors
        homeFeedProjection.activate(
            definition: definition,
            window: try? eventStore?.feedWindow(
                feedID: definition.feedID,
                revision: definition.revision,
                limit: homeFeedProjection.windowLimit
            ),
            sourceAuthors: sourceAuthors
        )
    }

    func testingRegisterOlderFeedRequest(
        packet: NostrREQPacket,
        definition: NostrFeedDefinitionRecord,
        anchorEventID: String?
    ) {
        pendingBackwardRequests[packet.groupID] = PendingBackwardRequest(
            feedContext: HomeFeedRuntimeContext(definition: definition),
            isOlderPage: true,
            olderAnchorPostID: anchorEventID
        )
    }

    func testingRegisterForwardFeedRequest(
        packet: NostrREQPacket,
        definition: NostrFeedDefinitionRecord
    ) {
        feedSyncLifecycle.registerForwardContext(
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
        pendingBackwardRequests[packet.groupID] = PendingBackwardRequest(
            feedContext: HomeFeedRuntimeContext(definition: definition),
            gap: PendingGapBackfill(
                newerPostID: newerEventID,
                olderPostID: olderEventID,
                direction: direction
            )
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
        await handleBackwardEvent(relayURL: relayURL, subscriptionID: subscriptionID, event: event)
    }

    func testingHandleHomeForwardEvent(
        relayURL: String,
        subscriptionID: String,
        event: NostrEvent
    ) async {
        await handleHomeForwardEvent(relayURL: relayURL, subscriptionID: subscriptionID, event: event)
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
        flushBackwardDependencies()
    }

    var testingPendingBackwardRequestCount: Int {
        pendingBackwardRequests.count + dependencyCoordinator.pendingSourceRequestCount
    }

    var testingHasPendingDependencyWork: Bool {
        dependencyCoordinator.hasPendingWork
    }

    var testingActiveFeedSyncRequestCount: Int {
        feedSyncLifecycle.activeRequestCount
    }

    var testingActiveFeedSyncContextCount: Int {
        feedSyncLifecycle.activeContextCount
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

private struct PendingBackwardRequest {
    var feedContext: HomeFeedRuntimeContext? = nil
    var isOlderPage = false
    var olderAnchorPostID: String?
    var gap: PendingGapBackfill?
    var receivedTimelineEventCount = 0
    var receivedTimelineEventIDs: [String] = []
    var sourceRequestIDs: [String] = []
}

private struct PendingFeedViewportState: Sendable {
    let accountID: String
    let feedID: String
    let anchorEventID: String?
    let anchorOffset: Double
    let updatedAt: Int
}

private struct HomeFeedSyncRegistration {
    let context: HomeFeedRuntimeContext
    let direction: NostrFeedSyncDirection
    let purpose: NostrFeedSyncPurpose
    let pendingRequestKey: String?
    let gap: PendingGapBackfill?
}

private struct PendingGapBackfill {
    let newerPostID: String
    let olderPostID: String
    let direction: TimelineGapFillDirection

    var stableAnchorPostID: String {
        switch direction {
        case .newer:
            olderPostID
        case .older:
            newerPostID
        }
    }
}

private struct ListEntriesCache {
    let accountID: String
    let limit: Int
    let homeContentRevision: Int
    let listContentRevision: Int
    let entries: [TimelineFeedEntry]
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
