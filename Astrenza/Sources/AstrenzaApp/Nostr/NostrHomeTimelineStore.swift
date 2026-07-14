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
    private let syncPlanner: HomeTimelineSyncPlanner
    private let timelineRepository: HomeTimelineRepository
    private let timelineCoordinator: HomeTimelineCoordinator
    private let relayRuntime: NostrRelayRuntime?
    private let profileDirectory: NostrProfileDirectory?
    private let linkPreviewResolver: NostrLinkPreviewResolver?
    private let outboxPublisher: NostrOutboxRelayPublisher
    private let syncPolicySettingsStore: NostrSyncPolicySettingsStore
    private var syncPolicy: NostrSyncPolicy
    private var loadTask: Task<Void, Never>?
    private var paginationTask: Task<Void, Never>?
    private var runtimeTask: Task<Void, Never>?
    private var profileDirectoryUpdateTask: Task<Void, Never>?
    private var linkPreviewTask: Task<Void, Never>?
    private var materializeTask: Task<Void, Never>?
    private var unmaterializedCountTask: Task<Void, Never>?
    private var outboxTask: Task<Void, Never>?
    private var outboxTaskGeneration: UInt64 = 0
    private var feedReadStateTask: Task<Void, Never>?
    private var viewportStateTask: Task<Void, Never>?
    private var pendingViewportState: PendingFeedViewportState?
    private var resolvingLinkPreviewURLs = Set<String>()
    private var pendingBackwardRequests: [String: PendingBackwardRequest] = [:]
    private var pendingGapReconciliationIDs = Set<String>()
    private var runtimeSyncWindows: [RuntimeSubscriptionKey: RuntimeSyncWindow] = [:]
    private var activeFeedSyncRequestIDs: [RuntimeSubscriptionKey: String] = [:]
    private var activeFeedSyncContexts: [RuntimeSubscriptionKey: HomeFeedRuntimeContext] = [:]
    private var expectedHomeForwardRuntimeKeys = Set<RuntimeSubscriptionKey>()
    private var homeForwardEOSEKeys = Set<RuntimeSubscriptionKey>()
    private var forwardFeedContextsByGroupID: [String: HomeFeedRuntimeContext] = [:]
    private var pendingRelayTrafficDeltas: [NostrRelayTrafficDelta] = []
    private var lastRelayTrafficFlushAt = 0
    private var dependencyFetchQueue = NostrDependencyFetchQueue()
    private var backwardFlushTask: Task<Void, Never>?
    private var installedHomeForwardPackets: [NostrREQPacket] = []
    private var noteEvents: [NostrEvent] = []
    private var metadataEvents: [NostrEvent] = []
    private var profileResolutionStates: [String: NostrProfileResolutionState] = [:]
    private var relayListEvent: NostrEvent?
    private var contactListEvent: NostrEvent?
    private var nip05Resolutions: [String: NostrNIP05Resolution] = [:]
    private var resolvingNIP05IdentifiersByPubkey: [String: String] = [:]
    private var relaySyncEvents: [NostrRelaySyncEventRecord] = []
    private var areTimelineFiltersSuspended = false
    private var unmaterializedNewEventIDs = Set<String>()
    private var unreadState = HomeTimelineUnreadState()
    private var isTimelineAtNewestWindow = true
    private var restoreProjectionAnchorEventID: String?
    private var hasCompletedRuntimeBootstrap = false
    private var isTimelineScrollActive = false
    private var needsMaterializationAfterScroll = false
    private var pendingMaterializationAllowsRealtimeFollow: Bool?
    private var lastEntriesRenderFingerprint: [Int] = []
    private var needsNewestProjectionReload = false
    private var listEntriesCache: ListEntriesCache?
    private var activeHomeFeedDefinition: NostrFeedDefinitionRecord?
    private var activeHomeFeedWindow: NostrFeedWindow?
    private var projectionWindowGeneration: UInt64 = 0
    private var activeHomeFeedSourceAuthors: [String]?
    private var runtimeLifecycleGeneration: UInt64 = 0
    private var relayRuntimeConfigurationSequence: UInt64 = 0
    private var isRuntimeEventPumpReady = false
    private var runtimeEventPumpReadyWaiters: [CheckedContinuation<Bool, Never>] = []
    private var relayRuntimeTerminationSequence: UInt64 = 0
    private var relayRuntimeTerminationTask: Task<Void, Never>?
    private let materializeCoalescingDelayNanoseconds: UInt64 = 16_000_000
    private let projectionWindowLimit = 240
    private let projectionRetainedWindowLimit = HomeTimelinePersistenceProjection.retainedEventLimit
    private let projectionAnchorLeadingLimit = 80
    private let projectionAnchorTrailingLimit = 160

    var relayStatusEventStore: NostrEventStore? {
        eventStore
    }

    var currentSyncPolicy: NostrSyncPolicy {
        syncPolicy
    }

    private static func isRuntimeReachable(_ state: NostrRelayConnectionState) -> Bool {
        state == .connected
    }

    private func updateRelayStatusCounts() {
        let planned = resolvedRelays.count
        guard planned > 0 else {
            setRelayStatusCountsIfNeeded((connected: 0, planned: 1))
            return
        }

        let recentlyReachableRelayURLs = Set(
            relaySyncEvents
                .filter { event in
                    event.timelineKey == "home" &&
                        Self.isRecentlyReachableSyncEvent(event)
                }
                .map(\.relayURL)
        )

        let connected = resolvedRelays.filter { relayURL in
            if let runtimeState = relayRuntimeStates[relayURL] {
                return Self.isRuntimeReachable(runtimeState)
            }
            return recentlyReachableRelayURLs.contains(relayURL)
        }.count
        setRelayStatusCountsIfNeeded((connected: connected, planned: planned))
    }

    private func setRelayStatusCountsIfNeeded(_ counts: (connected: Int, planned: Int)) {
        guard relayStatusCounts.connected != counts.connected ||
            relayStatusCounts.planned != counts.planned
        else { return }
        relayStatusCounts = counts
    }

    private static func isRecentlyReachableSyncEvent(
        _ event: NostrRelaySyncEventRecord,
        now: Int = Int(Date().timeIntervalSince1970),
        freshnessWindowSeconds: Int = 180
    ) -> Bool {
        guard now - event.occurredAt <= freshnessWindowSeconds else { return false }
        switch event.kind {
        case .connected, .eose, .authRequired, .paymentRequired:
            return true
        case .closed, .reconnect, .timeout, .partialFailure, .rejected, .suspended, .negentropy:
            return false
        }
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
        if !pendingBackwardRequests.isEmpty {
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
        self.timelineLoader = timelineLoader
        self.eventStore = eventStore
        self.persistenceWorker = eventStore.map(HomeTimelinePersistenceWorker.init)
        self.eventIngestor = HomeTimelineEventIngestor(eventStore: eventStore)
        self.syncPlanner = HomeTimelineSyncPlanner()
        self.timelineRepository = HomeTimelineRepository(eventStore: eventStore)
        self.timelineCoordinator = HomeTimelineCoordinator()
        self.relayRuntime = relayRuntime
        self.profileDirectory = relayRuntime.map {
            NostrProfileDirectory(eventStore: eventStore, relayRuntime: $0)
        }
        self.linkPreviewResolver = linkPreviewResolver
        self.outboxPublisher = outboxPublisher
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
              let state = try? eventStore?.feedReadState(feedID: Self.homeFeedID(accountID: accountID)),
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
              let definition = activeHomeFeedDefinition
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
        guard isTimelineScrollActive != isActive else { return }
        isTimelineScrollActive = isActive
        if isActive {
            if materializeTask != nil {
                needsMaterializationAfterScroll = true
                materializeTask?.cancel()
                materializeTask = nil
            }
        } else if needsMaterializationAfterScroll {
            scheduleMaterializeEntries()
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
        let hadPendingNewEvents = !unmaterializedNewEventIDs.isEmpty || needsNewestProjectionReload
        restoreProjectionAnchorEventID = nil
        isTimelineAtNewestWindow = true
        reloadNewestProjectionWindow(account: account)
        unmaterializedNewEventIDs.removeAll()
        unmaterializedCountTask?.cancel()
        unmaterializedCountTask = nil
        unmaterializedNewCount = 0
        needsNewestProjectionReload = false
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
        if installed, let definition = activeHomeFeedDefinition {
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
        let feedMembership = activeHomeFeedDefinition.flatMap { definition in
            homeFeedMemberships(
                events: [record.event],
                feedID: definition.feedID,
                feedRevision: definition.revision,
                reason: "outbox",
                insertedAt: createdAt
            ).first
        }
        let feedMembershipSources = activeHomeFeedDefinition.map { definition in
            homeFeedMembershipSources(
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
            let nextRetryAt = await self.drainOutbox(accountID: accountID)
            guard self.outboxTaskGeneration == taskGeneration else { return }
            self.outboxTask = nil
            guard !Task.isCancelled,
                  self.account?.pubkey == accountID,
                  let nextRetryAt
            else { return }
            let now = Int(Date().timeIntervalSince1970)
            let delaySeconds = max(1, nextRetryAt - now)
            self.scheduleOutboxDrain(delayNanoseconds: UInt64(delaySeconds) * 1_000_000_000)
        }
    }

    private func drainOutbox(accountID: String) async -> Int? {
        guard let eventStore else { return nil }
        let now = Int(Date().timeIntervalSince1970)
        let candidates = ((try? eventStore.outboxEvents(accountID: accountID, limit: 500)) ?? [])
            .filter { record in
                let isRetryReady = record.nextRetryAt.map { $0 <= now } ?? true
                let isTerminal = record.status == NostrOutboxStatus.published ||
                    record.status == NostrOutboxStatus.rejected
                return !isTerminal && isRetryReady
            }

        for record in candidates {
            guard !Task.isCancelled, account?.pubkey == accountID else { return nil }
            let relayRecords = (try? eventStore.outboxRelays(localID: record.localID)) ?? []
            let relayURLs = relayRecords
                .filter {
                    $0.status != NostrOutboxStatus.published &&
                        $0.status != NostrOutboxStatus.rejected
                }
                .map(\.relayURL)
            guard !relayURLs.isEmpty else { continue }

            let results = await outboxPublisher.publish(event: record.event, relayURLs: relayURLs)
            guard !Task.isCancelled, account?.pubkey == accountID else { return nil }
            for result in results {
                let accepted = result.accepted || Self.isDuplicateRelayAcknowledgment(result.message)
                try? eventStore.recordOutboxRelayResult(
                    localID: record.localID,
                    relayURL: result.relayURL,
                    accepted: accepted,
                    message: result.message,
                    retryable: accepted || !Self.isTerminalRelayRejection(result.message)
                )
            }
            relayStatusRevision &+= 1
        }

        return ((try? eventStore.outboxEvents(accountID: accountID, limit: 500)) ?? [])
            .filter {
                $0.status != NostrOutboxStatus.published &&
                    $0.status != NostrOutboxStatus.rejected
            }
            .compactMap(\.nextRetryAt)
            .min()
    }

    private static func isDuplicateRelayAcknowledgment(_ message: String?) -> Bool {
        message?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .hasPrefix("duplicate:") == true
    }

    private static func isTerminalRelayRejection(_ message: String?) -> Bool {
        guard let prefix = message?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .split(separator: ":", maxSplits: 1)
            .first
            .map(String.init)
        else { return false }
        return [
            "auth-required",
            "blocked",
            "invalid",
            "payment-required",
            "pow",
            "restricted"
        ].contains(prefix)
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
            nip05Resolutions: nip05Resolutions,
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
        linkPreviewTask?.cancel()
        materializeTask?.cancel()
        unmaterializedCountTask?.cancel()
        outboxTask?.cancel()
        outboxTaskGeneration &+= 1
        feedReadStateTask?.cancel()
        viewportStateTask?.cancel()
        backwardFlushTask?.cancel()
        loadTask = nil
        paginationTask = nil
        runtimeTask = nil
        profileDirectoryUpdateTask = nil
        linkPreviewTask = nil
        materializeTask = nil
        pendingMaterializationAllowsRealtimeFollow = nil
        realtimeFollowSourceRevision = nil
        unmaterializedCountTask = nil
        outboxTask = nil
        feedReadStateTask = nil
        viewportStateTask = nil
        backwardFlushTask = nil
        dependencyFetchQueue.removeAll()
        pendingBackwardRequests.removeAll()
        pendingGapReconciliationIDs.removeAll()
        unmaterializedNewEventIDs.removeAll()
        unmaterializedNewCount = 0
        isRefreshing = false
        isLoadingOlder = false
        needsNewestProjectionReload = false
        listEntriesCache = nil
        listContentRevision &+= 1
        activeHomeFeedDefinition = nil
        activeHomeFeedWindow = nil
        projectionWindowGeneration &+= 1
        activeHomeFeedSourceAuthors = nil
        installedHomeForwardPackets = []
        resetHomeTimelineRealtime()
        finishActiveFeedSyncRequests(reason: .cancelled)
        runtimeSyncWindows.removeAll()
        activeFeedSyncRequestIDs.removeAll()
        activeFeedSyncContexts.removeAll()
        forwardFeedContextsByGroupID.removeAll()
        pendingRelayTrafficDeltas.removeAll()
        resolvingLinkPreviewURLs.removeAll()
        relayRuntimeStates = [:]
        entries = []
        lastEntriesRenderFingerprint = []
        resolvedRelays = []
        followedPubkeys = []
        noteEvents = []
        metadataEvents = []
        profileResolutionStates = [:]
        relayListEvent = nil
        contactListEvent = nil
        nip05Resolutions = [:]
        resolvingNIP05IdentifiersByPubkey = [:]
        relaySyncEvents = []
        hasMoreOlder = true
        filterStatus = TimelineFilterStatus()
        unreadState.reset()
        publishUnreadState()
        restoreProjectionAnchorEventID = nil
        isTimelineAtNewestWindow = true
        hasCompletedRuntimeBootstrap = false
        isTimelineScrollActive = false
        needsMaterializationAfterScroll = false
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
            await persistFetchedRelaySyncEvents(state.relaySyncEvents)
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
            await persistFetchedRelaySyncEvents(bootstrapState.relaySyncEvents)
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
            nip05Resolutions: nip05Resolutions,
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
            await persistFetchedRelaySyncEvents(state.relaySyncEvents)
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
            await persistFetchedRelaySyncEvents(state.relaySyncEvents)
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
            sourceEventIDs: [],
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
            sourceEventIDs: [],
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
        lastEntriesRenderFingerprint = []
        resolvedRelays = []
        updateRelayStatusCounts()
        followedPubkeys = []
        noteEvents = []
        metadataEvents = []
        relayListEvent = nil
        contactListEvent = nil
        nip05Resolutions = [:]
        relaySyncEvents = []
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
            nip05Resolutions: nip05Resolutions,
            hasMoreOlder: hasMoreOlder,
            relaySyncEvents: []
        )
        let memberships = homeFeedMemberships(
            events: projectionEvents,
            feedID: definition.feedID,
            feedRevision: definition.revision,
            reason: "state",
            insertedAt: now
        )
        let membershipSources = homeFeedMembershipSources(
            events: projectionEvents,
            feedID: definition.feedID,
            feedRevision: definition.revision,
            reason: "state",
            insertedAt: now
        )
        let lifecycleGeneration = runtimeLifecycleGeneration
        let savedProjectionWindowGeneration = projectionWindowGeneration
        do {
            let window = try await persistenceWorker.saveFeedSnapshot(
                HomeTimelineFeedPersistenceSnapshot(
                    state: state,
                    accountID: account.pubkey,
                    definition: definition,
                    memberships: memberships,
                    membershipSources: membershipSources,
                    savedAt: now,
                    windowLimit: projectionWindowLimit
                )
            )
            guard !Task.isCancelled,
                  runtimeLifecycleGeneration == lifecycleGeneration,
                  self.account?.pubkey == account.pubkey,
                  projectionWindowGeneration == savedProjectionWindowGeneration,
                  (followedPubkeys.isEmpty ? [account.pubkey] : followedPubkeys) == plan.sourceAuthors,
                  let currentPlan = homeFeedDefinitionPlan(account: account, now: now),
                  currentPlan.definition.revision == definition.revision,
                  currentPlan.definition.specificationHash == definition.specificationHash
            else { return }
            activeHomeFeedDefinition = definition
            activeHomeFeedWindow = window
            projectionWindowGeneration &+= 1
            activeHomeFeedSourceAuthors = plan.sourceAuthors
            if unmaterializedNewEventIDs.isEmpty {
                materializeEntries()
            }
        } catch {
            // Live networking can still populate the timeline if the database write fails.
        }
    }

    private func persistFetchedRelaySyncEvents(_ events: [NostrRelaySyncEventRecord]) async {
        guard !events.isEmpty, let persistenceWorker else { return }
        let normalizedEvents = events.map { event in
            let updatesTimelineCursor = Self.isTimelineCursorSubscription(event.subscriptionID)
            return NostrRelaySyncEventRecord(
                accountID: event.accountID,
                timelineKey: event.timelineKey,
                relayURL: event.relayURL,
                kind: event.kind,
                occurredAt: event.occurredAt,
                subscriptionID: event.subscriptionID,
                eventCount: event.eventCount,
                newestCreatedAt: updatesTimelineCursor ? event.newestCreatedAt : nil,
                oldestCreatedAt: updatesTimelineCursor ? event.oldestCreatedAt : nil,
                latencyMilliseconds: event.latencyMilliseconds,
                message: event.message
            )
        }
        try? await persistenceWorker.saveRelaySyncEvents(normalizedEvents)
    }

    private static func isTimelineCursorSubscription(_ subscriptionID: String?) -> Bool {
        guard let subscriptionID else { return false }
        return subscriptionID.hasPrefix("astrenza-home") ||
            subscriptionID.hasPrefix("astrenza-neg-gap") ||
            subscriptionID.hasPrefix("astrenza-gap-events")
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
            nip05Resolutions: nip05Resolutions,
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
        guard let eventStore else { return }
        let sourceAuthors = followedPubkeys.isEmpty ? [account.pubkey] : followedPubkeys
        if activeHomeFeedDefinition?.accountID == account.pubkey,
           activeHomeFeedSourceAuthors == sourceAuthors {
            return
        }
        let now = Int(Date().timeIntervalSince1970)
        guard let plan = homeFeedDefinitionPlan(account: account, now: now) else { return }
        if !plan.requiresProjectionReplacement {
            activeHomeFeedDefinition = plan.definition
            activeHomeFeedSourceAuthors = sourceAuthors
            repairHomeFeedProjectionIfNeeded(
                definition: plan.definition,
                allowedAuthors: Set(plan.authors)
            )
            return
        }

        let definition = plan.definition
        do {
            let projectionEvents = cachedHomeProjectionEvents(allowedAuthors: Set(plan.authors))
            let memberships = homeFeedMemberships(
                events: projectionEvents,
                feedID: definition.feedID,
                feedRevision: definition.revision,
                reason: "projection-rebuild",
                insertedAt: now
            )
            try eventStore.replaceFeedProjection(
                definition,
                memberships: memberships,
                sources: homeFeedMembershipSources(
                    events: projectionEvents,
                    feedID: definition.feedID,
                    feedRevision: definition.revision,
                    reason: "projection-rebuild",
                    insertedAt: now
                )
            )
            activeHomeFeedDefinition = definition
            activeHomeFeedWindow = try? eventStore.feedWindow(
                feedID: definition.feedID,
                revision: definition.revision,
                limit: projectionWindowLimit
            )
            projectionWindowGeneration &+= 1
            activeHomeFeedSourceAuthors = plan.sourceAuthors
        } catch {
            activeHomeFeedDefinition = nil
            activeHomeFeedWindow = nil
            projectionWindowGeneration &+= 1
            activeHomeFeedSourceAuthors = nil
        }
    }

    private func homeFeedDefinitionPlan(
        account: NostrAccount,
        now: Int
    ) -> HomeFeedDefinitionPlan? {
        guard let eventStore else { return nil }
        let sourceAuthors = followedPubkeys.isEmpty ? [account.pubkey] : followedPubkeys
        let authors = sourceAuthors.sorted()
        let specification = HomeFeedSpecification(authors: authors, kinds: [1, 6])
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let specificationJSON = try? encoder.encode(specification) else { return nil }
        let specificationHash = Self.stableFeedSpecificationHash(specificationJSON)
        let feedID = Self.homeFeedID(accountID: account.pubkey)
        let existingDefinition = try? eventStore.feedDefinition(feedID: feedID)
        if let existingDefinition,
           existingDefinition.specificationHash == specificationHash {
            return HomeFeedDefinitionPlan(
                definition: existingDefinition,
                sourceAuthors: sourceAuthors,
                authors: authors,
                requiresProjectionReplacement: false
            )
        }

        return HomeFeedDefinitionPlan(
            definition: NostrFeedDefinitionRecord(
                feedID: feedID,
                accountID: account.pubkey,
                kind: "home",
                specificationJSON: specificationJSON,
                specificationHash: specificationHash,
                sortPolicy: "created_at_desc_event_id_asc",
                revision: (existingDefinition?.revision ?? 0) + 1,
                createdAt: existingDefinition?.createdAt ?? now,
                updatedAt: now
            ),
            sourceAuthors: sourceAuthors,
            authors: authors,
            requiresProjectionReplacement: true
        )
    }

    private func repairHomeFeedProjectionIfNeeded(
        definition: NostrFeedDefinitionRecord,
        allowedAuthors: Set<String>
    ) {
        guard let eventStore else { return }
        let existingMemberships = (try? eventStore.feedMemberships(
            feedID: definition.feedID,
            revision: definition.revision,
            limit: 1
        )) ?? []
        guard existingMemberships.isEmpty else { return }
        let currentEvents = cachedHomeProjectionEvents(allowedAuthors: allowedAuthors)
        guard !currentEvents.isEmpty else { return }
        let now = Int(Date().timeIntervalSince1970)
        let memberships = homeFeedMemberships(
            events: currentEvents,
            feedID: definition.feedID,
            feedRevision: definition.revision,
            reason: "projection-repair",
            insertedAt: now
        )
        try? eventStore.replaceFeedProjection(
            definition,
            memberships: memberships,
            sources: homeFeedMembershipSources(
                events: currentEvents,
                feedID: definition.feedID,
                feedRevision: definition.revision,
                reason: "projection-repair",
                insertedAt: now
            )
        )
    }

    private func cachedHomeProjectionEvents(allowedAuthors: Set<String>) -> [NostrEvent] {
        guard let eventStore, !allowedAuthors.isEmpty else {
            return noteEvents.filter { event in
                (event.kind == 1 || event.kind == 6) && allowedAuthors.contains(event.pubkey)
            }
        }
        let authors = Array(allowedAuthors)
        let storedNotes = (try? eventStore.events(kind: 1, authors: authors, limit: 10_000)) ?? []
        let storedReposts = (try? eventStore.events(kind: 6, authors: authors, limit: 10_000)) ?? []
        var eventsByID: [String: NostrEvent] = [:]
        for event in noteEvents + storedNotes + storedReposts
        where (event.kind == 1 || event.kind == 6) && allowedAuthors.contains(event.pubkey) {
            eventsByID[event.id] = event
        }
        return Array(eventsByID.values)
    }

    private static func homeFeedID(accountID: String) -> String {
        "feed:home:\(accountID)"
    }

    private static func stableFeedSpecificationHash(_ data: Data) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in data {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(hash, radix: 16)
    }

    private func activeHomeFeedRuntimeContext() -> HomeFeedRuntimeContext? {
        guard let definition = activeHomeFeedDefinition else { return nil }
        return HomeFeedRuntimeContext(definition: definition)
    }

    private func isCurrentHomeFeedContext(_ context: HomeFeedRuntimeContext?) -> Bool {
        guard let context else { return false }
        return context.matches(activeHomeFeedDefinition) && account?.pubkey == context.accountID
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
              let definition = activeHomeFeedDefinition,
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
        guard account != nil, activeHomeFeedDefinition != nil else { return }
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
              let definition = activeHomeFeedDefinition,
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

    private func homeFeedMemberships(
        events: [NostrEvent],
        feedID: String,
        feedRevision: Int? = nil,
        reason: String,
        insertedAt: Int
    ) -> [NostrFeedMembershipRecord] {
        events.compactMap { event in
            guard event.kind == 1 || event.kind == 6 else { return nil }
            let subjectEventID = event.kind == 6
                ? event.tags.last(where: { $0.count >= 2 && $0[0] == "e" })?[1]
                : nil
            return NostrFeedMembershipRecord(
                feedID: feedID,
                eventID: event.id,
                subjectEventID: subjectEventID,
                sortTimestamp: event.createdAt,
                reason: reason,
                insertedAt: insertedAt,
                feedRevision: feedRevision
            )
        }
    }

    private func homeFeedMembershipSources(
        events: [NostrEvent],
        feedID: String,
        feedRevision: Int? = nil,
        reason: String,
        insertedAt: Int,
        sourceRequestID: String? = nil
    ) -> [NostrFeedMembershipSourceRecord] {
        events
            .filter { $0.kind == 1 || $0.kind == 6 }
            .flatMap { event in
                var sources = [
                    NostrFeedMembershipSourceRecord(
                        feedID: feedID,
                        eventID: event.id,
                        sourceType: "author",
                        sourceID: event.pubkey,
                        insertedAt: insertedAt,
                        feedRevision: feedRevision
                    ),
                    NostrFeedMembershipSourceRecord(
                        feedID: feedID,
                        eventID: event.id,
                        sourceType: "ingest",
                        sourceID: reason,
                        insertedAt: insertedAt,
                        feedRevision: feedRevision
                    )
                ]
                if let sourceRequestID {
                    sources.append(NostrFeedMembershipSourceRecord(
                        feedID: feedID,
                        eventID: event.id,
                        sourceType: "sync-request",
                        sourceID: sourceRequestID,
                        insertedAt: insertedAt,
                        feedRevision: feedRevision
                    ))
                }
                return sources
            }
    }

    private func reloadNewestProjectionWindow(account: NostrAccount) {
        ensureHomeFeedDefinition(account: account)
        guard let eventStore,
              let definition = activeHomeFeedDefinition,
              let window = try? eventStore.feedWindow(
                feedID: definition.feedID,
                revision: definition.revision,
                limit: projectionWindowLimit
              )
        else { return }
        activeHomeFeedWindow = window
        projectionWindowGeneration &+= 1
        noteEvents = window.events
    }

    @discardableResult
    private func reloadProjectionWindow(
        account: NostrAccount,
        around anchorEventID: String?,
        mergingWithCurrentWindow: Bool = false
    ) -> Bool {
        ensureHomeFeedDefinition(account: account)
        guard let eventStore, let definition = activeHomeFeedDefinition else { return false }
        let window: NostrFeedWindow?
        if let anchorEventID {
            window = try? eventStore.feedWindow(
                feedID: definition.feedID,
                revision: definition.revision,
                aroundEventID: anchorEventID,
                leadingLimit: projectionAnchorLeadingLimit,
                trailingLimit: projectionAnchorTrailingLimit
            )
        } else {
            window = try? eventStore.feedWindow(
                feedID: definition.feedID,
                revision: definition.revision,
                limit: projectionWindowLimit
            )
        }
        guard let window else { return false }
        if let anchorEventID,
           !window.memberships.contains(where: { $0.eventID == anchorEventID }) {
            return false
        }
        let nextWindow: NostrFeedWindow
        if mergingWithCurrentWindow,
           let activeHomeFeedWindow,
           let anchorEventID {
            nextWindow = mergedProjectionWindow(
                activeHomeFeedWindow,
                with: window,
                centeredOn: anchorEventID
            )
        } else {
            nextWindow = window
        }
        activeHomeFeedWindow = nextWindow
        projectionWindowGeneration &+= 1
        noteEvents = nextWindow.events
        return true
    }

    private func mergedProjectionWindow(
        _ current: NostrFeedWindow,
        with loaded: NostrFeedWindow,
        centeredOn anchorEventID: String
    ) -> NostrFeedWindow {
        guard current.definition.feedID == loaded.definition.feedID,
              current.definition.revision == loaded.definition.revision
        else { return loaded }

        var membershipsByEventID = Dictionary(
            uniqueKeysWithValues: current.memberships.map { ($0.eventID, $0) }
        )
        loaded.memberships.forEach { membershipsByEventID[$0.eventID] = $0 }
        let orderedMemberships = membershipsByEventID.values.sorted { lhs, rhs in
            if lhs.sortTimestamp != rhs.sortTimestamp {
                return lhs.sortTimestamp > rhs.sortTimestamp
            }
            return lhs.eventID < rhs.eventID
        }
        let retainedMemberships = retainedProjectionMemberships(
            orderedMemberships,
            centeredOn: anchorEventID
        )
        let retainedEventIDs = Set(retainedMemberships.map(\.eventID))

        var eventsByID = Dictionary(uniqueKeysWithValues: current.events.map { ($0.id, $0) })
        loaded.events.forEach { eventsByID[$0.id] = $0 }

        var deletedItemsByTarget = Dictionary(
            uniqueKeysWithValues: current.deletedItems.map { ($0.targetEventID, $0) }
        )
        loaded.deletedItems.forEach { item in
            if let existing = deletedItemsByTarget[item.targetEventID],
               existing.deletedAt > item.deletedAt {
                return
            }
            deletedItemsByTarget[item.targetEventID] = item
        }

        var gapsByBoundary: [String: NostrFeedGapRecord] = [:]
        (current.gaps + loaded.gaps).forEach { gap in
            let key = "\(gap.newerEventID)\u{0}\(gap.olderEventID)"
            if let existing = gapsByBoundary[key], existing.updatedAt > gap.updatedAt {
                return
            }
            gapsByBoundary[key] = gap
        }

        return NostrFeedWindow(
            definition: loaded.definition,
            memberships: retainedMemberships,
            events: retainedMemberships.compactMap { eventsByID[$0.eventID] },
            deletedItems: deletedItemsByTarget.values
                .filter { retainedEventIDs.contains($0.targetEventID) }
                .sorted { lhs, rhs in
                    if lhs.sortTimestamp != rhs.sortTimestamp {
                        return lhs.sortTimestamp > rhs.sortTimestamp
                    }
                    return lhs.targetEventID < rhs.targetEventID
                },
            gaps: gapsByBoundary.values
                .filter {
                    retainedEventIDs.contains($0.newerEventID) &&
                        retainedEventIDs.contains($0.olderEventID)
                }
                .sorted { lhs, rhs in
                    if lhs.updatedAt != rhs.updatedAt {
                        return lhs.updatedAt > rhs.updatedAt
                    }
                    if lhs.newerEventID != rhs.newerEventID {
                        return lhs.newerEventID < rhs.newerEventID
                    }
                    return lhs.olderEventID < rhs.olderEventID
                }
        )
    }

    private func retainedProjectionMemberships(
        _ memberships: [NostrFeedMembershipRecord],
        centeredOn anchorEventID: String
    ) -> [NostrFeedMembershipRecord] {
        guard memberships.count > projectionRetainedWindowLimit,
              let anchorIndex = memberships.firstIndex(where: { $0.eventID == anchorEventID })
        else { return memberships }

        let preferredStart = max(0, anchorIndex - projectionRetainedWindowLimit / 2)
        let start = min(preferredStart, memberships.count - projectionRetainedWindowLimit)
        return Array(memberships[start..<(start + projectionRetainedWindowLimit)])
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
                forwardFeedContextsByGroupID[packet.groupID] = feedContext
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
        expectedHomeForwardRuntimeKeys = runtimeKeys
        homeForwardEOSEKeys.removeAll()
        publishHomeTimelineRealtimeState()
    }

    private func invalidateHomeTimelineRealtime(for key: RuntimeSubscriptionKey) {
        guard Self.isHomeForwardSubscription(key.subscriptionID) else { return }
        homeForwardEOSEKeys.remove(key)
        publishHomeTimelineRealtimeState()
    }

    private func invalidateHomeTimelineRealtime(relayURL: String) {
        homeForwardEOSEKeys = homeForwardEOSEKeys.filter { $0.relayURL != relayURL }
        publishHomeTimelineRealtimeState()
    }

    private func markHomeTimelineRealtimeEOSE(for key: RuntimeSubscriptionKey) {
        guard expectedHomeForwardRuntimeKeys.contains(key) else { return }
        homeForwardEOSEKeys.insert(key)
        publishHomeTimelineRealtimeState()
    }

    private func publishHomeTimelineRealtimeState() {
        let nextIsRealtime = !expectedHomeForwardRuntimeKeys.isEmpty &&
            expectedHomeForwardRuntimeKeys.isSubset(of: homeForwardEOSEKeys)
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

    private func pendingBackwardRequest(for subscriptionID: String) -> PendingBackwardRequest? {
        pendingBackwardRequestKey(for: subscriptionID).flatMap { pendingBackwardRequests[$0] }
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
        if subscriptionID.contains("astrenza-source-events") {
            return pendingBackwardRequests.first { !$0.value.sourceEventIDs.isEmpty }?.key
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
        let requestID = activeFeedSyncRequestIDs[runtimeKey]
        let requestContext = activeFeedSyncContexts[runtimeKey]

        let ingestResult: HomeTimelineEventIngestResult
        let projectsIntoCurrentFeed: Bool
        do {
            ensureHomeFeedDefinition(account: account)
            projectsIntoCurrentFeed = isCurrentHomeFeedContext(requestContext) &&
                requestContext?.includes(event) == true
            let insertedAt = Int(Date().timeIntervalSince1970)
            let feedMembership = projectsIntoCurrentFeed ? activeHomeFeedDefinition.flatMap { definition in
                homeFeedMemberships(
                    events: [event],
                    feedID: definition.feedID,
                    feedRevision: definition.revision,
                    reason: "forward",
                    insertedAt: insertedAt
                ).first
            } : nil
            let feedMembershipSources = projectsIntoCurrentFeed ? activeHomeFeedDefinition.map { definition in
                homeFeedMembershipSources(
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
                needsNewestProjectionReload = true
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
        let sourceRequestID = activeFeedSyncRequestIDs[runtimeKey]
        let activeRequestContext = activeFeedSyncContexts[runtimeKey]
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
            let feedMembership = projectsIntoCurrentFeed ? activeHomeFeedDefinition.flatMap { definition in
                homeFeedMemberships(
                    events: [event],
                    feedID: definition.feedID,
                    feedRevision: definition.revision,
                    reason: timelineSource,
                    insertedAt: insertedAt
                ).first
            } : nil
            let feedMembershipSources = projectsIntoCurrentFeed ? activeHomeFeedDefinition.map { definition in
                homeFeedMembershipSources(
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
            dependencyFetchQueue.finish(sourceEventIDs: [event.id], succeeded: true)
            if !isTimelineBackfill || projectsIntoCurrentFeed {
                await enqueueBackwardDependencies(for: event)
                if let embeddedTarget {
                    await enqueueBackwardDependencies(for: embeddedTarget)
                }
            }
            if !isTimelineBackfill {
                scheduleMaterializeEntries(delayNanoseconds: materializeCoalescingDelayNanoseconds * 2)
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
        let dependencies = NostrEventDependencies.extract(from: event)
        let cacheResult = await eventIngestor.dependencyCacheResult(
            dependencies: dependencies,
            liveMetadataEvents: metadataEvents,
            liveNoteEventIDs: Set(noteEvents.map(\.id)),
            now: Int(Date().timeIntervalSince1970)
        )
        guard runtimeLifecycleGeneration == lifecycleGeneration,
              account?.pubkey == accountID
        else { return }
        cacheResult.cachedProfiles.forEach { profile in
            rememberLatestMetadataEvent(profile, consultEventStore: false)
        }
        let cacheSnapshot = cacheResult.snapshot
        if !cacheResult.cachedProfiles.isEmpty ||
            cacheSnapshot.hasResolvedDependencies(for: dependencies) {
            scheduleMaterializeEntries()
        }

        await profileDirectory?.ensureProfiles(
            pubkeys: [event.pubkey],
            relayHintsByPubkey: dependencies.profileRelayURLsByPubkey.filter { $0.key == event.pubkey },
            priority: .foreground
        )
        let backgroundProfilePubkeys = dependencies.profilePubkeys.filter { $0 != event.pubkey }
        if !backgroundProfilePubkeys.isEmpty {
            await profileDirectory?.ensureProfiles(
                pubkeys: backgroundProfilePubkeys,
                relayHintsByPubkey: dependencies.profileRelayURLsByPubkey.filter {
                    backgroundProfilePubkeys.contains($0.key)
                },
                priority: .background
            )
        }

        let sourceDependencies = NostrEventDependencies(
            sourceEventIDs: dependencies.sourceEventIDs,
            sourceRelayURLsByEventID: dependencies.sourceRelayURLsByEventID
        )
        let enqueuedSources = dependencyFetchQueue.enqueue(
            dependencies: sourceDependencies,
            cacheSnapshot: cacheSnapshot,
            availableRelayURLs: resolvedRelays
        )
        if enqueuedSources {
            scheduleBackwardDependencyFlush()
        }
    }

    private func ensureProfileDirectoryDependencies(for events: [NostrEvent]) async {
        guard let profileDirectory, !events.isEmpty else { return }
        var authorPubkeys = Set<String>()
        var referencedPubkeys = Set<String>()
        var relayHintsByPubkey: [String: [String]] = [:]
        for event in events {
            authorPubkeys.insert(event.pubkey)
            let dependencies = NostrEventDependencies.extract(from: event)
            referencedPubkeys.formUnion(dependencies.profilePubkeys)
            for (pubkey, relayHints) in dependencies.profileRelayURLsByPubkey {
                relayHintsByPubkey[pubkey, default: []].append(contentsOf: relayHints)
            }
        }
        referencedPubkeys.subtract(authorPubkeys)
        await profileDirectory.ensureProfiles(
            pubkeys: authorPubkeys.sorted(),
            relayHintsByPubkey: relayHintsByPubkey,
            priority: .foreground
        )
        if !referencedPubkeys.isEmpty {
            await profileDirectory.ensureProfiles(
                pubkeys: referencedPubkeys.sorted(),
                relayHintsByPubkey: relayHintsByPubkey,
                priority: .background
            )
        }
    }

    private func resolveNIP05IfNeeded(for metadataEvent: NostrEvent) {
        guard let metadata = Self.profileMetadata(from: metadataEvent) else { return }
        let identifier = metadata.nip05?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !identifier.isEmpty else {
            resolvingNIP05IdentifiersByPubkey.removeValue(forKey: metadataEvent.pubkey)
            guard nip05Resolutions.removeValue(forKey: metadataEvent.pubkey) != nil,
                  let account
            else { return }
            Task { [weak self] in
                await self?.persistTimelineMetadata(account: account)
            }
            return
        }
        guard nip05Resolutions[metadataEvent.pubkey]?.identifier != identifier else { return }
        guard resolvingNIP05IdentifiersByPubkey[metadataEvent.pubkey] != identifier else { return }

        let resolver = timelineLoader.nip05Resolver
        guard let accountID = account?.pubkey else { return }
        let lifecycleGeneration = runtimeLifecycleGeneration
        resolvingNIP05IdentifiersByPubkey[metadataEvent.pubkey] = identifier
        Task(priority: .utility) { [weak self] in
            let resolution = await resolver.resolve(identifier: identifier, expectedPubkey: metadataEvent.pubkey)
            guard let self,
                  self.runtimeLifecycleGeneration == lifecycleGeneration,
                  self.account?.pubkey == accountID
            else { return }
            if self.resolvingNIP05IdentifiersByPubkey[metadataEvent.pubkey] == identifier {
                self.resolvingNIP05IdentifiersByPubkey.removeValue(forKey: metadataEvent.pubkey)
            }
            let latestMetadata = NostrHomeTimelineMaterializer
                .latestMetadataByPubkey(self.metadataEvents)[metadataEvent.pubkey]
            guard latestMetadata?.nip05?.trimmingCharacters(in: .whitespacesAndNewlines) == resolution.identifier else {
                return
            }
            self.nip05Resolutions[metadataEvent.pubkey] = resolution
            self.invalidateListEntries()
            self.scheduleMaterializeEntries()
            if let account = self.account {
                await self.persistTimelineMetadata(account: account)
            }
        }
    }

    private func scheduleBackwardDependencyFlush() {
        guard backwardFlushTask == nil else { return }
        backwardFlushTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 12_000_000)
            await MainActor.run {
                self?.flushBackwardDependencies()
            }
        }
    }

    private func flushBackwardDependencies() {
        guard let relayRuntime else { return }
        backwardFlushTask = nil
        let batch = dependencyFetchQueue.drain()

        let plan = syncPlanner.dependencyPackets(batch: batch)
        for (packet, group) in zip(plan.sourcePackets, batch.sourceGroups) {
            pendingBackwardRequests[packet.groupID] = PendingBackwardRequest(
                sourceEventIDs: group.values
            )
        }

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
                    plan.registeredGroupIDs.forEach { pendingBackwardRequests.removeValue(forKey: $0) }
                    finishDependencyFetch(
                        sourceEventIDs: plan.registeredSourceEventIDs,
                        succeeded: false
                    )
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
        guard let request = pendingBackwardRequests.removeValue(forKey: completion.groupID) else { return }
        let priorBottomPostID = request.olderAnchorPostID ?? noteEvents.last?.id
        let isTimelineBackfill = request.isOlderPage || request.gap != nil
        finishDependencyFetch(
            sourceEventIDs: request.sourceEventIDs,
            succeeded: completion.status == .completed || completion.status == .partial
        )
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

    private func finishDependencyFetch(
        sourceEventIDs: [String],
        succeeded: Bool
    ) {
        dependencyFetchQueue.finish(
            sourceEventIDs: sourceEventIDs,
            succeeded: succeeded
        )
    }

    private func markOlderPageBoundaryGap(_ request: PendingBackwardRequest) {
        guard account != nil,
              let definition = activeHomeFeedDefinition,
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

        let reconciliation = await fetchMissingGapEvents(
            account: account,
            newerEvent: newerEvent,
            olderEvent: olderEvent,
            context: context
        )
        guard runtimeLifecycleGeneration == lifecycleGeneration,
              self.account?.pubkey == accountID,
              isCurrentHomeFeedContext(context)
        else { return }
        switch reconciliation {
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
                let feedMemberships = homeFeedMemberships(
                    events: scopedEvents,
                    feedID: context.feedID,
                    feedRevision: context.revision,
                    reason: "gap-negentropy",
                    insertedAt: insertedAt
                )
                let feedMembershipSources = homeFeedMembershipSources(
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

    private func fetchMissingGapEvents(
        account: NostrAccount,
        newerEvent: NostrEvent,
        olderEvent: NostrEvent,
        context: HomeFeedRuntimeContext
    ) async -> GapReconciliationResult {
        let authors = context.allowedAuthors.isEmpty
            ? [account.pubkey]
            : context.allowedAuthors.sorted()
        guard isCurrentHomeFeedContext(context),
              !authors.isEmpty,
              olderEvent.createdAt < newerEvent.createdAt
        else { return .indeterminate }

        let localEvents = localGapWindowEvents(
            authors: authors,
            newerEvent: newerEvent,
            olderEvent: olderEvent
        )
        let filter = NostrRelayFilter(
            kinds: [1, 6],
            authors: authors,
            since: olderEvent.createdAt + 1,
            until: newerEvent.createdAt - 1
        )

        let relayClient = timelineLoader.relayClient
        let relays = Array(resolvedRelays.prefix(4))
        guard !relays.isEmpty else { return .indeterminate }
        let verificationRequestIDs = beginGapVerificationRequests(
            relays: relays,
            filter: filter,
            requestedAt: Int(Date().timeIntervalSince1970),
            context: context
        )
        let probe = await withTaskGroup(of: GapRelayProbeResult.self) { group in
            for relay in relays {
                let requestID = verificationRequestIDs[relay]
                group.addTask {
                    do {
                        return .success(
                            relayURL: relay,
                            requestID: requestID,
                            missingEventIDs: try await relayClient.fetchMissingEventIDs(
                                relayURL: relay,
                                filter: filter,
                                localEvents: localEvents,
                                subscriptionID: "astrenza-neg-gap"
                            )
                        )
                    } catch {
                        return .failure(
                            relayURL: relay,
                            requestID: requestID,
                            outcome: Self.verificationFailureOutcome(error)
                        )
                    }
                }
            }

            var ids = Set<String>()
            var successCount = 0
            var results: [GapRelayProbeResult] = []
            for await result in group {
                results.append(result)
                guard case .success(_, _, let relayIDs) = result else { continue }
                successCount += 1
                ids.formUnion(relayIDs)
            }
            return (ids: Array(ids).sorted(), successCount: successCount, results: results)
        }
        persistGapVerificationResults(probe.results)
        guard isCurrentHomeFeedContext(context) else { return .indeterminate }
        guard probe.successCount > 0 else { return .indeterminate }
        guard !probe.ids.isEmpty else {
            return probe.successCount == relays.count ? .verifiedComplete : .indeterminate
        }
        let missingIDs = probe.ids

        let request = NostrRelayRequest(
            subscriptionID: "astrenza-gap-events",
            filters: [["ids": .strings(Array(missingIDs.prefix(250)))]]
        )
        let events = await withTaskGroup(of: GapRelayFetchResult.self) { group in
            for relay in relays {
                group.addTask {
                    do {
                        return .success(try await relayClient.fetch(relayURL: relay, request: request))
                    } catch {
                        return .failure
                    }
                }
            }

            var fetched: [NostrEvent] = []
            for await result in group {
                guard case .success(let relayEvents) = result else { continue }
                fetched.append(contentsOf: relayEvents)
            }
            return fetched
        }
        guard isCurrentHomeFeedContext(context) else { return .indeterminate }

        let missingIDSet = Set(missingIDs)
        let recoveredEvents = Array(
            Dictionary(uniqueKeysWithValues: events.compactMap { event -> (String, NostrEvent)? in
                guard missingIDSet.contains(event.id),
                      [1, 6].contains(event.kind),
                      authors.contains(event.pubkey),
                      event.createdAt > olderEvent.createdAt,
                      event.createdAt < newerEvent.createdAt
                else { return nil }
                return (event.id, event)
            }).values
        ).sorted { lhs, rhs in
            if lhs.createdAt == rhs.createdAt {
                return lhs.id < rhs.id
            }
            return lhs.createdAt > rhs.createdAt
        }
        return recoveredEvents.isEmpty ? .indeterminate : .recovered(recoveredEvents)
    }

    private func beginGapVerificationRequests(
        relays: [String],
        filter: NostrRelayFilter,
        requestedAt: Int,
        context: HomeFeedRuntimeContext
    ) -> [String: String] {
        guard let eventStore, isCurrentHomeFeedContext(context) else { return [:] }
        var filterObject: [String: AnySendableJSON] = [:]
        if let kinds = filter.kinds { filterObject["kinds"] = .ints(kinds) }
        if let authors = filter.authors { filterObject["authors"] = .strings(authors) }
        if let since = filter.since { filterObject["since"] = .int(since) }
        if let until = filter.until { filterObject["until"] = .int(until) }

        var requestIDs: [String: String] = [:]
        for relayURL in relays {
            let requestID = UUID().uuidString
            do {
                let syncFilter = try NostrFeedSyncFilterRecord(
                    requestID: requestID,
                    filterIndex: 0,
                    filter: filterObject
                )
                try eventStore.beginFeedSyncRequest(
                    NostrFeedSyncRequestRecord(
                        requestID: requestID,
                        feedID: context.feedID,
                        feedRevision: context.revision,
                        feedSpecificationHash: context.specificationHash,
                        relayURL: relayURL,
                        subscriptionID: "astrenza-neg-gap",
                        syncProtocol: .nip77,
                        direction: .verification,
                        purpose: .gap,
                        requestedAt: requestedAt
                    ),
                    filters: [syncFilter]
                )
                try eventStore.markFeedSyncRequestInstalled(requestID: requestID, at: requestedAt)
                requestIDs[relayURL] = requestID
            } catch {
                recordRuntimeSyncEvent(
                    relayURL: relayURL,
                    kind: .partialFailure,
                    subscriptionID: "astrenza-neg-gap",
                    message: "gap verification save failed: \(error.localizedDescription)"
                )
            }
        }
        return requestIDs
    }

    private func persistGapVerificationResults(_ results: [GapRelayProbeResult]) {
        let completedAt = Int(Date().timeIntervalSince1970)
        for result in results {
            switch result {
            case .success(_, let requestID, let missingEventIDs):
                guard let requestID else { continue }
                let outcome: NostrFeedVerificationOutcome = missingEventIDs.isEmpty
                    ? .noRemoteMissing
                    : .differencesFound
                try? eventStore?.completeFeedSyncVerification(
                    requestID: requestID,
                    outcome: outcome,
                    differenceCount: missingEventIDs.count,
                    at: completedAt
                )
            case .failure(_, let requestID, let outcome):
                guard let requestID else { continue }
                try? eventStore?.completeFeedSyncVerification(
                    requestID: requestID,
                    outcome: outcome,
                    differenceCount: nil,
                    at: completedAt
                )
            }
        }
    }

    nonisolated private static func verificationFailureOutcome(
        _ error: any Error
    ) -> NostrFeedVerificationOutcome {
        guard let relayError = error as? NostrRelayClientError,
              case .negentropyRelayError(let reason) = relayError
        else {
            return .failed
        }
        let normalizedReason = reason.lowercased()
        return normalizedReason.contains("unsupported") ||
            normalizedReason.contains("not supported") ||
            normalizedReason.contains("unknown command")
            ? .unsupported
            : .failed
    }

    private func localGapWindowEvents(
        authors: [String],
        newerEvent: NostrEvent,
        olderEvent: NostrEvent
    ) -> [NostrEvent] {
        let inMemoryEvents = noteEvents.filter { event in
            [1, 6].contains(event.kind) &&
                authors.contains(event.pubkey) &&
                event.createdAt > olderEvent.createdAt &&
                event.createdAt < newerEvent.createdAt
        }
        guard let eventStore else { return inMemoryEvents }

        let storedKind1 = ((try? eventStore.events(
            kind: 1,
            authors: authors,
            until: newerEvent.createdAt - 1,
            limit: 500
        )) ?? []).filter { $0.createdAt > olderEvent.createdAt }
        let storedKind6 = ((try? eventStore.events(
            kind: 6,
            authors: authors,
            until: newerEvent.createdAt - 1,
            limit: 500
        )) ?? []).filter { $0.createdAt > olderEvent.createdAt }
        return Array(
            Dictionary(uniqueKeysWithValues: (inMemoryEvents + storedKind1 + storedKind6).map { ($0.id, $0) }).values
        )
    }

    private func scheduleLinkPreviewResolution() {
        guard let eventStore, let linkPreviewResolver, linkPreviewTask == nil else { return }
        guard NostrContentAttachmentClassifier.linkPreviewFetchMode(for: syncPolicy) != .tapRequired else { return }
        let previews = ((try? eventStore.unresolvedLinkPreviews(limit: 6)) ?? [])
            .filter { resolvingLinkPreviewURLs.insert($0.normalizedURL).inserted }
        guard !previews.isEmpty else { return }
        guard let accountID = account?.pubkey else { return }
        let lifecycleGeneration = runtimeLifecycleGeneration

        linkPreviewTask = Task { [weak self] in
            for preview in previews {
                let resolved = await linkPreviewResolver.resolve(preview)
                guard !Task.isCancelled,
                      let self,
                      self.runtimeLifecycleGeneration == lifecycleGeneration,
                      self.account?.pubkey == accountID
                else { return }
                do {
                    try eventStore.saveLinkPreview(resolved)
                } catch {
                    self.recordRuntimeSyncEvent(
                        relayURL: "link-preview",
                        kind: .partialFailure,
                        subscriptionID: nil,
                        message: "link preview save failed: \(error.localizedDescription)"
                    )
                }
            }

            guard let self,
                  self.runtimeLifecycleGeneration == lifecycleGeneration,
                  self.account?.pubkey == accountID
            else { return }
            previews.forEach { self.resolvingLinkPreviewURLs.remove($0.normalizedURL) }
            self.linkPreviewTask = nil
            self.invalidateListEntries()
            self.scheduleMaterializeEntries()
            self.scheduleLinkPreviewResolution()
        }
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
        let event = NostrRelaySyncEventRecord(
            accountID: account.pubkey,
            timelineKey: "home",
            relayURL: relayURL,
            kind: kind,
            occurredAt: Int(Date().timeIntervalSince1970),
            subscriptionID: subscriptionID,
            eventCount: eventCount,
            newestCreatedAt: newestCreatedAt,
            oldestCreatedAt: oldestCreatedAt,
            latencyMilliseconds: nil,
            message: message
        )
        relaySyncEvents.append(event)
        trimRelaySyncEventCache()
        try? eventStore?.saveRelaySyncEvents([event])
        updateRelayStatusCounts()
        if publishesStatusChange {
            relayStatusRevision &+= 1
        }
    }

    private func trimRelaySyncEventCache(limit: Int = 500) {
        guard relaySyncEvents.count > limit else { return }
        relaySyncEvents.removeFirst(relaySyncEvents.count - limit)
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
        if let supersededRequestID = activeFeedSyncRequestIDs[key] {
            let supersededWindow = runtimeSyncWindows.removeValue(forKey: key) ?? RuntimeSyncWindow()
            activeFeedSyncContexts[key] = nil
            try? eventStore.endFeedSyncRequest(
                requestID: supersededRequestID,
                reason: .superseded,
                at: attempt.startedAt,
                eventCount: supersededWindow.eventCount,
                observedOldestPosition: supersededWindow.oldestCursor,
                observedNewestPosition: supersededWindow.newestCursor
            )
        }

        do {
            let filters = try attempt.packet.filters.enumerated().map { index, filter in
                try NostrFeedSyncFilterRecord(
                    requestID: attempt.requestID,
                    filterIndex: index,
                    filter: filter
                )
            }
            try eventStore.beginFeedSyncRequest(
                NostrFeedSyncRequestRecord(
                    requestID: attempt.requestID,
                    feedID: registration.context.feedID,
                    feedRevision: registration.context.revision,
                    feedSpecificationHash: registration.context.specificationHash,
                    relayURL: attempt.relayURL,
                    subscriptionID: attempt.packet.subscriptionID,
                    direction: registration.direction,
                    purpose: registration.purpose,
                    requestedAt: attempt.startedAt
                ),
                filters: filters
            )
            activeFeedSyncRequestIDs[key] = attempt.requestID
            activeFeedSyncContexts[key] = registration.context
            runtimeSyncWindows[key] = RuntimeSyncWindow()
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
            guard let context = forwardFeedContextsByGroupID[packet.groupID] else { return nil }
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
        let requestID: String?
        if Self.isHomeForwardSubscription(subscriptionID) {
            // Forward REQはEOSE後もlive subscriptionとして継続するため、
            // revision contextとrequest provenanceをCLOSED/置換まで保持します。
            requestID = activeFeedSyncRequestIDs[key]
            markHomeTimelineRealtimeEOSE(for: key)
        } else {
            requestID = activeFeedSyncRequestIDs.removeValue(forKey: key)
            activeFeedSyncContexts[key] = nil
        }
        guard let requestID else { return }
        try? eventStore?.recordFeedSyncEOSE(
            requestID: requestID,
            at: Int(Date().timeIntervalSince1970),
            eventCount: window.eventCount,
            observedOldestPosition: window.oldestCursor,
            observedNewestPosition: window.newestCursor
        )
    }

    private func endFeedSyncRequest(
        relayURL: String,
        subscriptionID: String,
        reason: NostrFeedSyncEndReason,
        message: String? = nil,
        window: RuntimeSyncWindow
    ) {
        let key = RuntimeSubscriptionKey(relayURL: relayURL, subscriptionID: subscriptionID)
        invalidateHomeTimelineRealtime(for: key)
        guard let requestID = activeFeedSyncRequestIDs.removeValue(forKey: key) else { return }
        activeFeedSyncContexts[key] = nil
        try? eventStore?.endFeedSyncRequest(
            requestID: requestID,
            reason: reason,
            message: message,
            at: Int(Date().timeIntervalSince1970),
            eventCount: window.eventCount,
            observedOldestPosition: window.oldestCursor,
            observedNewestPosition: window.newestCursor
        )
    }

    private func handleFeedSyncRequestEnded(_ end: NostrRelayRequestAttemptEnd) {
        let key = RuntimeSubscriptionKey(relayURL: end.relayURL, subscriptionID: end.subscriptionID)
        invalidateHomeTimelineRealtime(for: key)
        let isCurrentRequest = activeFeedSyncRequestIDs[key] == end.requestID
        let window = isCurrentRequest
            ? runtimeSyncWindows.removeValue(forKey: key) ?? RuntimeSyncWindow()
            : RuntimeSyncWindow()
        if isCurrentRequest {
            activeFeedSyncRequestIDs[key] = nil
            activeFeedSyncContexts[key] = nil
        }
        let reason: NostrFeedSyncEndReason
        switch end.reason {
        case .installFailed:
            reason = .installFailed
        case .cancelled:
            reason = .cancelled
        case .superseded:
            reason = .superseded
        }
        try? eventStore?.endFeedSyncRequest(
            requestID: end.requestID,
            reason: reason,
            message: end.message,
            at: end.endedAt,
            eventCount: window.eventCount,
            observedOldestPosition: window.oldestCursor,
            observedNewestPosition: window.newestCursor
        )
    }

    private func finishActiveFeedSyncRequests(reason: NostrFeedSyncEndReason) {
        let endedAt = Int(Date().timeIntervalSince1970)
        for (key, requestID) in activeFeedSyncRequestIDs {
            let window = runtimeSyncWindows[key] ?? RuntimeSyncWindow()
            try? eventStore?.endFeedSyncRequest(
                requestID: requestID,
                reason: reason,
                at: endedAt,
                eventCount: window.eventCount,
                observedOldestPosition: window.oldestCursor,
                observedNewestPosition: window.newestCursor
            )
        }
    }

    private func trackRuntimeSyncWindow(relayURL: String, subscriptionID: String, event: NostrEvent) {
        let key = RuntimeSubscriptionKey(relayURL: relayURL, subscriptionID: subscriptionID)
        runtimeSyncWindows[key, default: RuntimeSyncWindow()].include(event)
    }

    private func finishRuntimeSyncWindow(relayURL: String, subscriptionID: String) -> RuntimeSyncWindow {
        let key = RuntimeSubscriptionKey(relayURL: relayURL, subscriptionID: subscriptionID)
        return runtimeSyncWindows.removeValue(forKey: key) ?? RuntimeSyncWindow()
    }

    private func hasRecentRuntimeSyncEvent(
        relayURL: String,
        kind: NostrRelaySyncEventKind,
        message: String?
    ) -> Bool {
        relaySyncEvents.reversed().prefix(8).contains { event in
            event.relayURL == relayURL && event.kind == kind && event.message == message
        }
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
        materializeTask?.cancel()
        materializeTask = nil
        guard !isTimelineScrollActive else {
            needsMaterializationAfterScroll = true
            mergePendingMaterializationRealtimeFollow(allowsRealtimeFollow)
            return
        }
        pendingMaterializationAllowsRealtimeFollow = nil
        needsMaterializationAfterScroll = false
        if needsNewestProjectionReload, let account {
            reloadNewestProjectionWindow(account: account)
            needsNewestProjectionReload = false
        }
        let filterRules = homeFilterRules()
        let activeFilterRuleSet = filterRules.isEmpty ? nil : NostrFilterRuleSet(rules: filterRules)
        let materializerFilterRuleSet = areTimelineFiltersSuspended ? nil : activeFilterRuleSet
        let contextEvents = contextEventsForCurrentProjection()
        let snapshot = timelineRepository.materialize(
            account: account,
            noteEvents: noteEvents,
            feedWindow: activeHomeFeedWindow,
            contextEvents: contextEvents,
            metadataEvents: metadataEvents,
            nip05Resolutions: nip05Resolutions,
            profileResolutionStates: profileResolutionStates,
            followedPubkeys: followedPubkeys,
            resolvedRelays: resolvedRelays,
            filterRules: materializerFilterRuleSet,
            filterStatus: timelineFilterStatus(ruleSet: activeFilterRuleSet),
            policy: syncPolicy
        )
        var didChangePublishedContent = false
        if snapshot.renderFingerprint != lastEntriesRenderFingerprint {
            entries = snapshot.entries
            lastEntriesRenderFingerprint = snapshot.renderFingerprint
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
            realtimeFollowSourceRevision = allowsRealtimeFollow
                ? resolvedContentRevision
                : nil
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
        if let allowsRealtimeFollow {
            mergePendingMaterializationRealtimeFollow(allowsRealtimeFollow)
        }
        needsMaterializationAfterScroll = true
        guard !isTimelineScrollActive else { return }
        guard materializeTask == nil else { return }
        let delay = delayNanoseconds ?? materializeCoalescingDelayNanoseconds
        materializeTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: delay)
            guard let self, !Task.isCancelled else { return }
            self.materializeTask = nil
            let allowsRealtimeFollow = self.pendingMaterializationAllowsRealtimeFollow == true
            self.materializeEntries(allowsRealtimeFollow: allowsRealtimeFollow)
        }
    }

    private func mergePendingMaterializationRealtimeFollow(_ allowsRealtimeFollow: Bool) {
        pendingMaterializationAllowsRealtimeFollow =
            (pendingMaterializationAllowsRealtimeFollow ?? true) && allowsRealtimeFollow
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
            nip05Resolutions: nip05Resolutions,
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
            nip05Status: NIP05Status(nip05Resolutions[pubkey]?.status ?? .unchecked),
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
            nip05Resolutions: nip05Resolutions,
            hasMoreOlder: hasMoreOlder,
            relaySyncEvents: relaySyncEvents
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
        nip05Resolutions = state.nip05Resolutions
        relaySyncEvents = state.relaySyncEvents
        hasMoreOlder = state.hasMoreOlder
        activeHomeFeedWindow = nil
        projectionWindowGeneration &+= 1
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
        lastEntriesRenderFingerprint = entries.map { $0.id.hashValue }
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
        mergedProjectionWindow(current, with: loaded, centeredOn: anchorEventID)
    }

    func testingActivateHomeFeed(
        account: NostrAccount,
        definition: NostrFeedDefinitionRecord,
        sourceAuthors: [String]
    ) {
        self.account = account
        followedPubkeys = sourceAuthors
        activeHomeFeedDefinition = definition
        activeHomeFeedSourceAuthors = sourceAuthors
        activeHomeFeedWindow = try? eventStore?.feedWindow(
            feedID: definition.feedID,
            revision: definition.revision,
            limit: projectionWindowLimit
        )
        projectionWindowGeneration &+= 1
    }

    func testingRegisterOlderFeedRequest(
        packet: NostrREQPacket,
        definition: NostrFeedDefinitionRecord,
        anchorEventID: String?
    ) {
        pendingBackwardRequests[packet.groupID] = PendingBackwardRequest(
            sourceEventIDs: [],
            feedContext: HomeFeedRuntimeContext(definition: definition),
            isOlderPage: true,
            olderAnchorPostID: anchorEventID
        )
    }

    func testingRegisterForwardFeedRequest(
        packet: NostrREQPacket,
        definition: NostrFeedDefinitionRecord
    ) {
        forwardFeedContextsByGroupID[packet.groupID] = HomeFeedRuntimeContext(definition: definition)
    }

    func testingRegisterGapFeedRequest(
        packet: NostrREQPacket,
        definition: NostrFeedDefinitionRecord,
        newerEventID: String,
        olderEventID: String,
        direction: TimelineGapFillDirection
    ) {
        pendingBackwardRequests[packet.groupID] = PendingBackwardRequest(
            sourceEventIDs: [],
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
        dependencyFetchQueue.enqueue(
            dependencies: dependencies,
            cacheSnapshot: NostrDependencyFetchCacheSnapshot(),
            availableRelayURLs: availableRelayURLs,
            now: 0
        )
    }

    func testingFlushBackwardDependencies() {
        flushBackwardDependencies()
    }

    var testingPendingBackwardRequestCount: Int {
        pendingBackwardRequests.count
    }

    var testingHasPendingDependencyWork: Bool {
        dependencyFetchQueue.hasPendingWork
    }

    var testingActiveFeedSyncRequestCount: Int {
        activeFeedSyncRequestIDs.count
    }

    var testingActiveFeedSyncContextCount: Int {
        activeFeedSyncContexts.count
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

private extension NostrDependencyFetchCacheSnapshot {
    func hasResolvedDependencies(for dependencies: NostrEventDependencies) -> Bool {
        dependencies.profilePubkeys.contains { profileReceivedAtByPubkey[$0] != nil } ||
            dependencies.sourceEventIDs.contains { sourceEventIDs.contains($0) }
    }
}

private struct PendingBackwardRequest {
    let sourceEventIDs: [String]
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

private struct HomeFeedRuntimeContext: Equatable, Sendable {
    let feedID: String
    let accountID: String
    let revision: Int
    let specificationHash: String
    let allowedAuthors: Set<String>

    init(definition: NostrFeedDefinitionRecord) {
        feedID = definition.feedID
        accountID = definition.accountID
        revision = definition.revision
        specificationHash = definition.specificationHash
        let specification = try? JSONDecoder().decode(
            HomeFeedSpecification.self,
            from: definition.specificationJSON
        )
        allowedAuthors = Set(specification?.authors ?? [])
    }

    func matches(_ definition: NostrFeedDefinitionRecord?) -> Bool {
        guard let definition else { return false }
        return feedID == definition.feedID &&
            accountID == definition.accountID &&
            revision == definition.revision &&
            specificationHash == definition.specificationHash
    }

    func includes(_ event: NostrEvent) -> Bool {
        allowedAuthors.isEmpty || allowedAuthors.contains(event.pubkey)
    }
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

private enum GapReconciliationResult: Sendable {
    case verifiedComplete
    case recovered([NostrEvent])
    case indeterminate
}

private enum GapRelayProbeResult: Sendable {
    case success(relayURL: String, requestID: String?, missingEventIDs: [String])
    case failure(relayURL: String, requestID: String?, outcome: NostrFeedVerificationOutcome)
}

private enum GapRelayFetchResult: Sendable {
    case success([NostrEvent])
    case failure
}

private struct RuntimeSubscriptionKey: Hashable {
    let relayURL: String
    let subscriptionID: String
}

private struct ListEntriesCache {
    let accountID: String
    let limit: Int
    let homeContentRevision: Int
    let listContentRevision: Int
    let entries: [TimelineFeedEntry]
}

private struct HomeFeedSpecification: Codable, Sendable {
    let authors: [String]
    let kinds: [Int]
}

private struct HomeFeedDefinitionPlan {
    let definition: NostrFeedDefinitionRecord
    let sourceAuthors: [String]
    let authors: [String]
    let requiresProjectionReplacement: Bool
}

private struct RuntimeSyncWindow {
    private(set) var newestCreatedAt: Int?
    private(set) var oldestCreatedAt: Int?
    private(set) var eventCount = 0
    private(set) var newestCursor: NostrTimelineEntryCursor?
    private(set) var oldestCursor: NostrTimelineEntryCursor?

    mutating func include(_ event: NostrEvent) {
        newestCreatedAt = [newestCreatedAt, event.createdAt].compactMap { $0 }.max()
        oldestCreatedAt = [oldestCreatedAt, event.createdAt].compactMap { $0 }.min()
        eventCount += 1
        let cursor = NostrTimelineEntryCursor(sortTimestamp: event.createdAt, eventID: event.id)
        if let current = newestCursor {
            if cursor.sortTimestamp > current.sortTimestamp ||
                (cursor.sortTimestamp == current.sortTimestamp && cursor.eventID < current.eventID) {
                newestCursor = cursor
            }
        } else {
            newestCursor = cursor
        }
        if let current = oldestCursor {
            if cursor.sortTimestamp < current.sortTimestamp ||
                (cursor.sortTimestamp == current.sortTimestamp && cursor.eventID > current.eventID) {
                oldestCursor = cursor
            }
        } else {
            oldestCursor = cursor
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
