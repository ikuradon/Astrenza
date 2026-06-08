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
                "Ready"
            case .resolvingRelays:
                "Resolving NIP-65 relays"
            case .resolvingContacts:
                "Resolving kind:3 contacts"
            case .loadingHome:
                "Loading Home timeline"
            case .loaded:
                "Home timeline loaded"
            case .failed(let message):
                message
            }
        }

        var isProcessing: Bool {
            switch self {
            case .resolvingRelays, .resolvingContacts, .loadingHome:
                true
            case .idle, .loaded, .failed:
                false
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

    private let timelineLoader: NostrHomeTimelineLoader
    private let eventStore: NostrEventStore?
    private let eventIngestor: HomeTimelineEventIngestor
    private let syncPlanner: HomeTimelineSyncPlanner
    private let timelineRepository: HomeTimelineRepository
    private let timelineCoordinator: HomeTimelineCoordinator
    private let relayRuntime: NostrRelayRuntime?
    private let linkPreviewResolver: NostrLinkPreviewResolver?
    private var loadTask: Task<Void, Never>?
    private var paginationTask: Task<Void, Never>?
    private var runtimeTask: Task<Void, Never>?
    private var linkPreviewTask: Task<Void, Never>?
    private var materializeTask: Task<Void, Never>?
    private var resolvingLinkPreviewURLs = Set<String>()
    private var pendingBackwardRequests: [String: PendingBackwardRequest] = [:]
    private var pendingGapReconciliationIDs = Set<String>()
    private var runtimeSyncWindows: [RuntimeSubscriptionKey: RuntimeSyncWindow] = [:]
    private var pendingRelayTrafficDeltas: [NostrRelayTrafficDelta] = []
    private var lastRelayTrafficFlushAt = 0
    private var dependencyFetchQueue = NostrDependencyFetchQueue()
    private var backwardFlushTask: Task<Void, Never>?
    private var installedHomeForwardPackets: [NostrREQPacket] = []
    private var noteEvents: [NostrEvent] = []
    private var metadataEvents: [NostrEvent] = []
    private var relayListEvent: NostrEvent?
    private var contactListEvent: NostrEvent?
    private var nip05Resolutions: [String: NostrNIP05Resolution] = [:]
    private var relaySyncEvents: [NostrRelaySyncEventRecord] = []
    private var areTimelineFiltersSuspended = false
    private var unmaterializedNewEventIDs = Set<String>()
    private var unreadState = HomeTimelineUnreadState()
    private var isTimelineAtNewestWindow = true
    private var restoreProjectionAnchorEventID: String?
    private var lastEntriesRenderFingerprint: [String] = []
    private let materializeCoalescingDelayNanoseconds: UInt64 = 250_000_000
    private let projectionWindowLimit = 240
    private let projectionAnchorLeadingLimit = 80
    private let projectionAnchorTrailingLimit = 160

    var relayStatusEventStore: NostrEventStore? {
        eventStore
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

    private func restoreRelaySyncEventsForStatusCache(account: NostrAccount) {
        guard let storedEvents = try? eventStore?.relaySyncEvents(
            accountID: account.pubkey,
            timelineKey: "home",
            limit: 300
        ) else {
            updateRelayStatusCounts()
            return
        }

        for event in storedEvents where !relaySyncEvents.contains(event) {
            relaySyncEvents.append(event)
        }
        updateRelayStatusCounts()
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

    var isRelayProcessing: Bool {
        phase.isProcessing ||
            dependencyFetchQueue.hasPendingWork ||
            !pendingBackwardRequests.isEmpty ||
            !pendingGapReconciliationIDs.isEmpty
    }

    init(
        timelineLoader: NostrHomeTimelineLoader = NostrHomeTimelineLoader(),
        eventStore: NostrEventStore? = try? NostrEventStore.applicationSupport(appDirectory: "Astrenza"),
        relayRuntime: NostrRelayRuntime? = nil,
        linkPreviewResolver: NostrLinkPreviewResolver? = nil
    ) {
        self.timelineLoader = timelineLoader
        self.eventStore = eventStore
        self.eventIngestor = HomeTimelineEventIngestor(eventStore: eventStore)
        self.syncPlanner = HomeTimelineSyncPlanner()
        self.timelineRepository = HomeTimelineRepository(eventStore: eventStore)
        self.timelineCoordinator = HomeTimelineCoordinator()
        self.relayRuntime = relayRuntime
        self.linkPreviewResolver = linkPreviewResolver
    }

    func start(account: NostrAccount) {
        self.account = account
        startRuntimeEventPump()
        restoreCachedSnapshot(account: account)
        applyRestoreProjectionAnchorIfPossible(account: account)
        installProvisionalRuntimeBootstrapIfNeeded(account: account)
        if relayRuntime != nil, !resolvedRelays.isEmpty {
            phase = .loaded
        } else if entries.isEmpty {
            phase = .resolvingRelays
        }
        loadTask?.cancel()
        loadTask = Task {
            await load(account: account)
        }
    }

    func setRestoreProjectionAnchor(_ anchorEventID: String?) {
        restoreProjectionAnchorEventID = anchorEventID
        guard let account else { return }
        applyRestoreProjectionAnchorIfPossible(account: account)
    }

    func refresh() {
        guard let account else { return }
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
        isTimelineAtNewestWindow = isAtNewestWindow
    }

    func dismissUnreadBadge() {
        unreadState.dismissBadge()
        publishUnreadState()
    }

    func markMaterializedPostsRead(visiblePostIDs: [TimelinePost.ID]) {
        unreadState.markVisiblePostsRead(visiblePostIDs)
        publishUnreadState()
    }

    func markNewestMaterializedWindowRead() {
        unreadState.markNewestWindowRead()
        publishUnreadState()
    }

    func applyPendingNewEvents() async {
        guard let account else { return }
        reloadNewestProjectionWindow(account: account)
        unmaterializedNewEventIDs.removeAll()
        unmaterializedNewCount = 0
        materializeEntries()
        scheduleLinkPreviewResolution()
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

        return await requestGapNotesThroughRuntime(account: account, gap: gap, direction: direction)
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
        let record = try eventStore.enqueueOutboxEvent(
            signedEvent,
            accountID: account.pubkey,
            relayURLs: destinationRelays,
            createdAt: createdAt
        )

        try eventStore.save(events: [record.event])
        saveHomeTimelineIndex(events: [record.event], account: account, source: "outbox")
        noteEvents.removeAll { $0.id == record.event.id }
        noteEvents.insert(record.event, at: 0)
        if !followedPubkeys.contains(account.pubkey) {
            followedPubkeys.append(account.pubkey)
        }
        materializeEntries()
        persistDatabase(account: account)
        phase = .loaded
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
        let listEvents = cachedListTimelineEvents(accountID: account.pubkey, eventStore: eventStore, limit: limit)
        guard !listEvents.isEmpty else { return [] }
        let pubkeys = Set(listEvents.map(\.pubkey))
        let metadata = (try? eventStore.latestReplaceableEvents(pubkeys: pubkeys, kind: 0)) ?? metadataEvents.filter { pubkeys.contains($0.pubkey) }
        return NostrTimelineMaterializer.entries(
            noteEvents: listEvents,
            metadataEvents: metadata,
            nip05Resolutions: nip05Resolutions,
            followedPubkeys: Set(followedPubkeys),
            mediaAssetsByEventID: mediaAssetsByEventID(for: listEvents),
            linkPreviewsByNormalizedURL: linkPreviewsByNormalizedURL(for: listEvents),
            filterRules: listFilterRuleSet(),
            timeline: .lists
        )
    }

    func suspendTimelineFilters() {
        guard !areTimelineFiltersSuspended else { return }
        areTimelineFiltersSuspended = true
        materializeEntries()
    }

    func resumeTimelineFilters() {
        guard areTimelineFiltersSuspended else { return }
        areTimelineFiltersSuspended = false
        materializeEntries()
    }

    func cancel() {
        loadTask?.cancel()
        paginationTask?.cancel()
        runtimeTask?.cancel()
        linkPreviewTask?.cancel()
        materializeTask?.cancel()
        backwardFlushTask?.cancel()
        loadTask = nil
        paginationTask = nil
        runtimeTask = nil
        linkPreviewTask = nil
        materializeTask = nil
        backwardFlushTask = nil
        dependencyFetchQueue.removeAll()
        pendingBackwardRequests.removeAll()
        pendingGapReconciliationIDs.removeAll()
        unmaterializedNewEventIDs.removeAll()
        unmaterializedNewCount = 0
        runtimeSyncWindows.removeAll()
        relayRuntimeStates = [:]
        updateRelayStatusCounts()
        relayStatusRevision &+= 1
        phase = .idle
        Task { [relayRuntime] in
            await relayRuntime?.terminate()
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

    private func load(account: NostrAccount) async {
        if relayRuntime != nil {
            await loadRuntimeBootstrap(account: account)
            return
        }

        do {
            let state = try await timelineLoader.initialState(account: account)
            guard Task.isCancelled == false else { return }
            apply(state)
            materializeEntries()
            persistDatabase(account: account)
            await configureRelayRuntime(account: account)
            phase = .loaded
        } catch {
            guard Task.isCancelled == false else { return }
            phase = .failed("Home timeline failed: \(error.localizedDescription)")
        }
    }

    private func loadRuntimeBootstrap(account: NostrAccount) async {
        installProvisionalRuntimeBootstrapIfNeeded(account: account)
        if !resolvedRelays.isEmpty {
            phase = .loaded
            await configureRelayRuntime(account: account)
        }

        do {
            let bootstrapState = try await timelineLoader.bootstrapState(account: account)
            guard Task.isCancelled == false else { return }
            apply(runtimeBootstrapState(from: bootstrapState))
            materializeEntries()
            persistDatabase(account: account)
            await configureRelayRuntime(account: account)
            phase = .loaded
        } catch {
            guard Task.isCancelled == false else { return }
            recordRuntimeSyncEvent(
                relayURL: resolvedRelays.first ?? "runtime",
                kind: .partialFailure,
                subscriptionID: "astrenza-bootstrap",
                message: "bootstrap refresh failed: \(error.localizedDescription)"
            )
            phase = resolvedRelays.isEmpty ? .failed("Home timeline failed: \(error.localizedDescription)") : .loaded
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
            relaySyncEvents: bootstrapState.relaySyncEvents
        )
    }

    private func refreshLatest(account: NostrAccount) async {
        guard !isRefreshing else { return }
        guard !noteEvents.isEmpty else {
            start(account: account)
            return
        }

        isRefreshing = true
        defer { isRefreshing = false }

        if relayRuntime != nil {
            await configureRelayRuntime(account: account, forceInstall: true)
            phase = .loaded
            return
        }

        do {
            let state = try await timelineLoader.refreshedState(account: account, current: loaderState())
            guard Task.isCancelled == false else { return }
            apply(state)
            materializeEntries()
            persistDatabase(account: account)
            await configureRelayRuntime(account: account)
            phase = .loaded
        } catch {
            guard Task.isCancelled == false else { return }
            phase = .failed("Refresh failed: \(error.localizedDescription)")
        }
    }

    private func loadOlder(account: NostrAccount) async {
        isLoadingOlder = true
        defer { isLoadingOlder = false }

        if relayRuntime != nil {
            await requestOlderNotesThroughRuntime(account: account)
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
            guard Task.isCancelled == false else { return }
            apply(state)
            if !state.hasMoreOlder {
                return
            }

            materializeEntries()
            persistDatabase(account: account)
            await configureRelayRuntime(account: account)
            phase = .loaded
        } catch {
            guard Task.isCancelled == false else { return }
            phase = .failed("Older notes failed: \(error.localizedDescription)")
        }
    }

    private func requestOlderNotesThroughRuntime(account: NostrAccount) async {
        guard let relayRuntime,
              let oldestCreatedAt = noteEvents.map(\.createdAt).min()
        else { return }
        let olderAnchorPostID = noteEvents.last?.id

        guard let packet = syncPlanner.olderNotesPacket(
            account: account,
            followedPubkeys: followedPubkeys,
            oldestCreatedAt: oldestCreatedAt,
            relayURLs: resolvedRelays
        ) else { return }

        pendingBackwardRequests[packet.groupID] = PendingBackwardRequest(
            profilePubkeys: [],
            sourceEventIDs: [],
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

        guard let packet = syncPlanner.gapNotesPacket(
            account: account,
            followedPubkeys: followedPubkeys,
            newerEvent: newerEvent,
            olderEvent: olderEvent,
            missingEstimate: gap.missingEstimate,
            relayURLs: resolvedRelays
        ) else { return false }

        pendingBackwardRequests[packet.groupID] = PendingBackwardRequest(
            profilePubkeys: [],
            sourceEventIDs: [],
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

    private func restoreCachedSnapshot(account: NostrAccount) {
        if let databaseState = try? eventStore?.homeTimelineState(accountID: account.pubkey) {
            apply(databaseState)
            restoreRelaySyncEventsForStatusCache(account: account)
            materializeEntries()
            if !entries.isEmpty {
                phase = .loaded
            }
            return
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
    }

    private func persistDatabase(account: NostrAccount) {
        guard let eventStore else { return }
        do {
            try eventStore.saveHomeTimelineState(loaderState(), accountID: account.pubkey)
        } catch {
            // Live networking can still populate the timeline if the database write fails.
        }
    }

    private func saveHomeTimelineIndex(events: [NostrEvent], account: NostrAccount, source: String) {
        guard let eventStore, !events.isEmpty else { return }
        let now = Int(Date().timeIntervalSince1970)
        do {
            try eventStore.saveTimelineEntries(events.map { event in
                NostrTimelineEntryRecord(
                    accountID: account.pubkey,
                    timelineKey: "home",
                    eventID: event.id,
                    sortTimestamp: event.createdAt,
                    source: source,
                    insertedAt: now
                )
            })
        } catch {
            recordRuntimeSyncEvent(
                relayURL: resolvedRelays.first ?? "database",
                kind: .partialFailure,
                subscriptionID: nil,
                message: "timeline index save failed: \(error.localizedDescription)"
            )
        }
    }

    private func reloadNewestProjectionWindow(account: NostrAccount) {
        guard let eventStore,
              let timelineEntries = try? eventStore.timelineEntries(
                accountID: account.pubkey,
                timelineKey: "home",
                limit: projectionWindowLimit
              )
        else { return }
        noteEvents = projectedTimelineEvents(entries: timelineEntries)
    }

    @discardableResult
    private func reloadProjectionWindow(account: NostrAccount, around anchorEventID: String?) -> Bool {
        guard let eventStore else { return false }
        let timelineEntries: [NostrTimelineEntryRecord]
        if let anchorEventID,
           let anchoredEntries = try? eventStore.timelineEntries(
            accountID: account.pubkey,
            timelineKey: "home",
            aroundEventID: anchorEventID,
            leadingLimit: projectionAnchorLeadingLimit,
            trailingLimit: projectionAnchorTrailingLimit
           ) {
            guard anchoredEntries.contains(where: { $0.eventID == anchorEventID }) else { return false }
            timelineEntries = anchoredEntries
        } else {
            timelineEntries = (try? eventStore.timelineEntries(
                accountID: account.pubkey,
                timelineKey: "home",
                limit: projectionWindowLimit
            )) ?? []
        }
        noteEvents = projectedTimelineEvents(entries: timelineEntries)
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

    private func projectedTimelineEvents(entries timelineEntries: [NostrTimelineEntryRecord]) -> [NostrEvent] {
        guard let eventStore else { return [] }
        let eventIDs = timelineEntries.map(\.eventID)
        let events = (try? eventStore.events(ids: eventIDs)) ?? []
        let eventsByID = Dictionary(uniqueKeysWithValues: events.map { ($0.id, $0) })
        return eventIDs.compactMap { eventsByID[$0] }
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
        guard let relayRuntime, runtimeTask == nil else { return }
        runtimeTask = Task { [weak self] in
            for await packet in await relayRuntime.events() {
                self?.handleRuntimePacket(packet)
            }
        }
    }

    private func installProvisionalRuntimeBootstrapIfNeeded(account: NostrAccount) {
        guard relayRuntime != nil, resolvedRelays.isEmpty else { return }
        let provisionalRelays = provisionalDiscoveryRelays(for: account)
        guard !provisionalRelays.isEmpty else { return }
        resolvedRelays = provisionalRelays
        followedPubkeys = [account.pubkey]
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
        guard let relayRuntime, !resolvedRelays.isEmpty else { return }

        do {
            await relayRuntime.setTrafficContext(
                accountID: account.pubkey,
                policy: .default(networkType: .unknown, lowPowerMode: false)
            )
            try await relayRuntime.setDefaultRelays(resolvedRelays)
            let newestCreatedAt = noteEvents.map(\.createdAt).max()
            let policy = NostrSyncPolicy.default(networkType: .unknown, lowPowerMode: false)
            let plan = syncPlanner.forwardPlan(
                account: account,
                followedPubkeys: followedPubkeys,
                contactItems: NostrContactList.items(from: contactListEvent),
                newestCreatedAt: newestCreatedAt,
                relayURLs: resolvedRelays,
                policy: policy
            )
            guard forceInstall || installedHomeForwardPackets != plan.packets else { return }
            try await relayRuntime.installForward(
                plan.packets,
                replacingGroupIDsWithPrefix: HomeTimelineSyncPlanner.homeForwardGroupPrefix
            )
            installedHomeForwardPackets = plan.packets
        } catch {
            recordRuntimeSyncEvent(
                relayURL: resolvedRelays.first ?? "runtime",
                kind: .partialFailure,
                subscriptionID: NostrHomeForwardREQBuilder.subscriptionID,
                message: String(describing: error)
            )
        }
    }

    private func handleRuntimePacket(_ packet: NostrRelayRuntimePacket) {
        timelineCoordinator.handleRuntimePacket(
            packet,
            handlers: HomeTimelineRuntimePacketHandlers(
                shouldHandle: { self.phase != .idle },
                stateChanged: { relayURL, state in
                    self.handleRuntimeStateChange(relayURL: relayURL, state: state)
                },
                event: { relayURL, subscriptionID, event in
                    self.handleRuntimeEvent(relayURL: relayURL, subscriptionID: subscriptionID, event: event)
                },
                eose: { relayURL, subscriptionID in
                    let window = self.finishRuntimeSyncWindow(relayURL: relayURL, subscriptionID: subscriptionID)
                    self.recordRuntimeSyncEvent(
                        relayURL: relayURL,
                        kind: .eose,
                        subscriptionID: subscriptionID,
                        newestCreatedAt: window.newestCreatedAt,
                        oldestCreatedAt: window.oldestCreatedAt,
                        message: "EOSE received"
                    )
                },
                closed: { relayURL, subscriptionID, message in
                    self.recordRuntimeSyncEvent(
                        relayURL: relayURL,
                        kind: Self.syncEventKind(forClosedMessage: message),
                        subscriptionID: subscriptionID,
                        message: message
                    )
                },
                timeout: { relayURL, subscriptionID, message in
                    self.recordRuntimeSyncEvent(
                        relayURL: relayURL,
                        kind: .timeout,
                        subscriptionID: subscriptionID,
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
        relayRuntimeStates[relayURL] = state
        updateRelayStatusCounts()
        switch state {
        case .connected:
            recordRuntimeSyncEvent(relayURL: relayURL, kind: .connected, subscriptionID: nil, message: "connected")
        case .waitingForRetry, .retrying:
            recordRuntimeSyncEvent(relayURL: relayURL, kind: .reconnect, subscriptionID: nil, message: state.rawValue)
        case .error:
            recordRuntimeSyncEvent(relayURL: relayURL, kind: .partialFailure, subscriptionID: nil, message: state.rawValue)
        case .rejected:
            recordRuntimeSyncEvent(relayURL: relayURL, kind: .rejected, subscriptionID: nil, message: state.rawValue)
        case .suspended:
            recordRuntimeSyncEvent(relayURL: relayURL, kind: .suspended, subscriptionID: nil, message: state.rawValue)
        case .initialized, .connecting, .dormant, .terminated:
            break
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

    private func handleRuntimeEvent(relayURL: String, subscriptionID: String, event: NostrEvent) {
        if Self.isHomeForwardSubscription(subscriptionID) {
            handleHomeForwardEvent(relayURL: relayURL, subscriptionID: subscriptionID, event: event)
            return
        }

        handleBackwardEvent(relayURL: relayURL, subscriptionID: subscriptionID, event: event)
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
        if subscriptionID.contains("astrenza-kind0") {
            return pendingBackwardRequests.first { !$0.value.profilePubkeys.isEmpty }?.key
        }
        return nil
    }

    private func handleHomeForwardEvent(relayURL: String, subscriptionID: String, event: NostrEvent) {
        guard event.kind == 1 || event.kind == 5 || event.kind == 6,
              let account
        else { return }
        guard followedPubkeys.isEmpty || followedPubkeys.contains(event.pubkey) else { return }

        let ingestResult: HomeTimelineEventIngestResult
        do {
            ingestResult = try eventIngestor.ingest(event: event, relayURL: relayURL)
        } catch {
            recordRuntimeSyncEvent(
                relayURL: relayURL,
                kind: .partialFailure,
                subscriptionID: subscriptionID,
                message: "event save failed: \(error.localizedDescription)"
            )
            return
        }
        let embeddedTarget = ingestResult.embeddedEvent

        if event.kind == 5 {
            let deletedIDs = event.tags.compactMap { tag in
                tag.count >= 2 && tag[0] == "e" ? tag[1] : nil
            }
            noteEvents.removeAll { deletedIDs.contains($0.id) }
            materializeEntries()
        } else {
            saveHomeTimelineIndex(events: [event], account: account, source: "forward")
            enqueueBackwardDependencies(for: event)
            embeddedTarget.map(enqueueBackwardDependencies)
            if isTimelineAtNewestWindow && unmaterializedNewEventIDs.isEmpty {
                reloadNewestProjectionWindow(account: account)
                materializeEntries()
            } else if unmaterializedNewEventIDs.insert(event.id).inserted {
                unmaterializedNewCount = unmaterializedNewEventIDs.count
            }
        }
        scheduleLinkPreviewResolution()
        trackRuntimeSyncWindow(relayURL: relayURL, subscriptionID: subscriptionID, event: event)
        recordRuntimeSyncEvent(
            relayURL: relayURL,
            kind: .connected,
            subscriptionID: subscriptionID,
            eventCount: 1,
            newestCreatedAt: event.createdAt,
            oldestCreatedAt: event.createdAt,
            message: "EVENT received",
            publishesStatusChange: false
        )
    }

    private func handleBackwardEvent(relayURL: String, subscriptionID: String, event: NostrEvent) {
        guard let account else { return }
        let requestKey = pendingBackwardRequestKey(for: subscriptionID)
        let request = requestKey.flatMap { pendingBackwardRequests[$0] }

        let ingestResult: HomeTimelineEventIngestResult
        do {
            ingestResult = try eventIngestor.ingest(event: event, relayURL: relayURL)
        } catch {
            recordRuntimeSyncEvent(
                relayURL: relayURL,
                kind: .partialFailure,
                subscriptionID: subscriptionID,
                message: "backward event save failed: \(error.localizedDescription)"
            )
            return
        }
        let embeddedTarget = ingestResult.embeddedEvent

        switch event.kind {
        case 0:
            let effectiveMetadataEvent = rememberLatestMetadataEvent(event)
            dependencyFetchQueue.finish(profilePubkeys: [event.pubkey], succeeded: true)
            resolveNIP05IfNeeded(for: effectiveMetadataEvent)
            scheduleMaterializeEntries()
        case 1, 6:
            if request?.isOlderPage == true || request?.gap != nil {
                saveHomeTimelineIndex(
                    events: [event],
                    account: account,
                    source: request?.isOlderPage == true ? "older" : "gap"
                )
                if let requestKey {
                    pendingBackwardRequests[requestKey]?.receivedTimelineEventCount += 1
                    if pendingBackwardRequests[requestKey]?.receivedTimelineEventIDs.contains(event.id) != true {
                        pendingBackwardRequests[requestKey]?.receivedTimelineEventIDs.append(event.id)
                    }
                }
            }
            dependencyFetchQueue.finish(sourceEventIDs: [event.id], succeeded: true)
            enqueueBackwardDependencies(for: event)
            embeddedTarget.map(enqueueBackwardDependencies)
            if request?.isOlderPage == true || request?.gap != nil {
                scheduleMaterializeEntries()
            } else {
                scheduleMaterializeEntries(delayNanoseconds: materializeCoalescingDelayNanoseconds * 2)
            }
        case 5:
            let deletedIDs = event.tags.compactMap { tag in
                tag.count >= 2 && tag[0] == "e" ? tag[1] : nil
            }
            noteEvents.removeAll { deletedIDs.contains($0.id) }
            materializeEntries()
        default:
            break
        }

        scheduleLinkPreviewResolution()
        trackRuntimeSyncWindow(relayURL: relayURL, subscriptionID: subscriptionID, event: event)
        recordRuntimeSyncEvent(
            relayURL: relayURL,
            kind: .connected,
            subscriptionID: subscriptionID,
            eventCount: 1,
            newestCreatedAt: event.createdAt,
            oldestCreatedAt: event.createdAt,
            message: "backward EVENT received",
            publishesStatusChange: false
        )
    }

    private func enqueueBackwardDependencies(for event: NostrEvent) {
        guard relayRuntime != nil, !resolvedRelays.isEmpty else { return }
        let dependencies = NostrEventDependencies.extract(from: event)
        let cacheSnapshot = ingestCachedDependencies(dependencies)
        if cacheSnapshot.hasResolvedDependencies(for: dependencies) {
            scheduleMaterializeEntries()
        }

        guard dependencyFetchQueue.enqueue(
            dependencies: dependencies,
            cacheSnapshot: cacheSnapshot,
            availableRelayURLs: resolvedRelays
        ) else {
            return
        }
        scheduleBackwardDependencyFlush()
    }

    private func ingestCachedDependencies(_ dependencies: NostrEventDependencies) -> NostrDependencyFetchCacheSnapshot {
        guard let eventStore else {
            let profileReceivedAtByPubkey = Dictionary(uniqueKeysWithValues: metadataEvents.map { event in
                (event.pubkey, Int(Date().timeIntervalSince1970))
            })
            let knownEventIDs = Set(noteEvents.map(\.id))
            return NostrDependencyFetchCacheSnapshot(
                profileReceivedAtByPubkey: profileReceivedAtByPubkey,
                sourceEventIDs: knownEventIDs
            )
        }

        let cachedProfiles = (try? eventStore.latestReplaceableEvents(
            pubkeys: Set(dependencies.profilePubkeys),
            kind: 0
        )) ?? []
        for profile in cachedProfiles {
            rememberLatestMetadataEvent(profile)
        }

        let profileReceivedAtByPubkey = ((try? eventStore.latestReplaceableEventReceivedAtByPubkey(
            pubkeys: Set(dependencies.profilePubkeys),
            kind: 0
        )) ?? [:]).merging(
            Dictionary(uniqueKeysWithValues: metadataEvents.map { event in
                (event.pubkey, Int(Date().timeIntervalSince1970))
            }),
            uniquingKeysWith: { stored, _ in stored }
        )
        let cachedSourceEventIDs = Set(((try? eventStore.events(ids: dependencies.sourceEventIDs)) ?? []).map(\.id))
        let knownEventIDs = Set(noteEvents.map(\.id)).union(cachedSourceEventIDs)
        return NostrDependencyFetchCacheSnapshot(
            profileReceivedAtByPubkey: profileReceivedAtByPubkey,
            sourceEventIDs: knownEventIDs
        )
    }

    private func resolveNIP05IfNeeded(for metadataEvent: NostrEvent) {
        guard let metadata = Self.profileMetadata(from: metadataEvent) else { return }
        let identifier = metadata.nip05?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !identifier.isEmpty else {
            nip05Resolutions.removeValue(forKey: metadataEvent.pubkey)
            if let account {
                persistDatabase(account: account)
            }
            return
        }
        guard nip05Resolutions[metadataEvent.pubkey]?.identifier != identifier else {
            if let account {
                persistDatabase(account: account)
            }
            return
        }

        let resolver = timelineLoader.nip05Resolver
        Task { [weak self] in
            let resolution = await resolver.resolve(identifier: identifier, expectedPubkey: metadataEvent.pubkey)
            await MainActor.run {
                guard let self else { return }
                let latestMetadata = NostrHomeTimelineMaterializer
                    .latestMetadataByPubkey(self.metadataEvents)[metadataEvent.pubkey]
                guard latestMetadata?.nip05?.trimmingCharacters(in: .whitespacesAndNewlines) == resolution.identifier else {
                    return
                }
                self.nip05Resolutions[metadataEvent.pubkey] = resolution
                self.scheduleMaterializeEntries()
                if let account = self.account {
                    self.persistDatabase(account: account)
                }
            }
        }
    }

    private func scheduleBackwardDependencyFlush() {
        guard backwardFlushTask == nil else { return }
        backwardFlushTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 25_000_000)
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
        for (packet, group) in zip(plan.profilePackets, batch.profileGroups) {
            pendingBackwardRequests[packet.groupID] = PendingBackwardRequest(profilePubkeys: group.values, sourceEventIDs: [])
        }
        for (packet, group) in zip(plan.sourcePackets, batch.sourceGroups) {
            pendingBackwardRequests[packet.groupID] = PendingBackwardRequest(profilePubkeys: [], sourceEventIDs: group.values)
        }

        guard !plan.isEmpty else { return }

        Task {
            do {
                if !plan.profilePackets.isEmpty {
                    try await relayRuntime.installBackward(plan.profilePackets, mergeField: .authors)
                }
                if !plan.sourcePackets.isEmpty {
                    try await relayRuntime.installBackward(plan.sourcePackets, mergeField: .ids)
                }
            } catch {
                await MainActor.run {
                    plan.registeredGroupIDs.forEach { pendingBackwardRequests.removeValue(forKey: $0) }
                    dependencyFetchQueue.finish(
                        profilePubkeys: plan.registeredProfilePubkeys,
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
        dependencyFetchQueue.finish(
            profilePubkeys: request.profilePubkeys,
            sourceEventIDs: request.sourceEventIDs,
            succeeded: completion.status == .completed || completion.status == .partial
        )
        if request.isOlderPage && completion.status == .completed && completion.eventCount == 0 {
            hasMoreOlder = false
        }
        let didReceiveTimelineEvents = completion.eventCount > 0 ||
            request.receivedTimelineEventCount > 0 ||
            !request.receivedTimelineEventIDs.isEmpty
        if completion.status == .completed || completion.status == .partial || didReceiveTimelineEvents {
            if request.isOlderPage,
               didReceiveTimelineEvents,
               let account {
                if completion.status != .completed {
                    markOlderPageBoundaryGap(request)
                }
                reloadProjectionWindow(account: account, around: priorBottomPostID)
                materializeEntries()
                scheduleLinkPreviewResolution()
            }

            if let gap = request.gap,
               let account {
                if completion.status == .completed {
                    reconcileCompletedGap(gap)
                } else {
                    reloadProjectionWindow(account: account, around: gap.stableAnchorPostID)
                    materializeEntries()
                    scheduleLinkPreviewResolution()
                }
            }
        }
        relayStatusRevision &+= 1
    }

    private func markOlderPageBoundaryGap(_ request: PendingBackwardRequest) {
        guard let account,
              let anchorPostID = request.olderAnchorPostID,
              let newestReceivedEventID = newestReceivedTimelineEventID(in: request)
        else { return }
        do {
            try eventStore?.markTimelineGap(
                accountID: account.pubkey,
                timelineKey: "home",
                newerEventID: anchorPostID,
                olderEventID: newestReceivedEventID
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

    private func markGapResolved(_ gap: PendingGapBackfill) {
        guard let account else { return }
        do {
            try eventStore?.markTimelineGapResolved(
                accountID: account.pubkey,
                timelineKey: "home",
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

    private func reconcileCompletedGap(_ gap: PendingGapBackfill) {
        let reconciliationID = "\(gap.newerPostID)-\(gap.olderPostID)"
        pendingGapReconciliationIDs.insert(reconciliationID)
        relayStatusRevision &+= 1

        Task { [weak self] in
            await self?.runCompletedGapReconciliation(gap, reconciliationID: reconciliationID)
        }
    }

    private func runCompletedGapReconciliation(
        _ gap: PendingGapBackfill,
        reconciliationID: String
    ) async {
        defer {
            pendingGapReconciliationIDs.remove(reconciliationID)
            relayStatusRevision &+= 1
        }

        guard let account,
              let newerEvent = timelineEvent(id: gap.newerPostID),
              let olderEvent = timelineEvent(id: gap.olderPostID)
        else { return }

        let recoveredEvents = await fetchMissingGapEvents(
            account: account,
            newerEvent: newerEvent,
            olderEvent: olderEvent
        )
        if recoveredEvents.isEmpty {
            markGapResolved(gap)
        } else {
            do {
                try eventStore?.save(events: recoveredEvents)
                saveHomeTimelineIndex(events: recoveredEvents, account: account, source: "gap-negentropy")
                recoveredEvents.forEach(enqueueBackwardDependencies)
            } catch {
                recordRuntimeSyncEvent(
                    relayURL: resolvedRelays.first ?? "runtime",
                    kind: .partialFailure,
                    subscriptionID: "astrenza-gap-events",
                    message: "gap negentropy save failed: \(error.localizedDescription)"
                )
            }
        }

        reloadProjectionWindow(account: account, around: gap.stableAnchorPostID)
        materializeEntries()
        scheduleLinkPreviewResolution()
    }

    private func fetchMissingGapEvents(
        account: NostrAccount,
        newerEvent: NostrEvent,
        olderEvent: NostrEvent
    ) async -> [NostrEvent] {
        let authors = followedPubkeys.isEmpty ? [account.pubkey] : followedPubkeys
        guard !authors.isEmpty, olderEvent.createdAt < newerEvent.createdAt else { return [] }

        let localEvents = localGapWindowEvents(
            authors: authors,
            newerEvent: newerEvent,
            olderEvent: olderEvent
        )
        let filter = NostrRelayFilter(
            kinds: [1, 6],
            authors: authors,
            since: olderEvent.createdAt + 1,
            until: newerEvent.createdAt - 1,
            limit: max(1, min(newerEvent.createdAt - olderEvent.createdAt, 250))
        )

        let relayClient = timelineLoader.relayClient
        let missingIDs = await withTaskGroup(of: [String].self) { group in
            for relay in resolvedRelays.prefix(4) {
                group.addTask {
                    (try? await relayClient.fetchMissingEventIDs(
                        relayURL: relay,
                        filter: filter,
                        localEvents: localEvents,
                        subscriptionID: "astrenza-neg-gap"
                    )) ?? []
                }
            }

            var ids = Set<String>()
            for await relayIDs in group {
                ids.formUnion(relayIDs)
            }
            return Array(ids).sorted()
        }
        guard !missingIDs.isEmpty else { return [] }

        let request = NostrRelayRequest(
            subscriptionID: "astrenza-gap-events",
            filters: [["ids": .strings(Array(missingIDs.prefix(250)))]]
        )
        let events = await withTaskGroup(of: [NostrEvent].self) { group in
            for relay in resolvedRelays.prefix(4) {
                group.addTask {
                    (try? await relayClient.fetch(relayURL: relay, request: request)) ?? []
                }
            }

            var fetched: [NostrEvent] = []
            for await relayEvents in group {
                fetched.append(contentsOf: relayEvents)
            }
            return fetched
        }

        let missingIDSet = Set(missingIDs)
        return Array(
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
        let previews = ((try? eventStore.unresolvedLinkPreviews(limit: 6)) ?? [])
            .filter { resolvingLinkPreviewURLs.insert($0.normalizedURL).inserted }
        guard !previews.isEmpty else { return }

        linkPreviewTask = Task { [weak self] in
            for preview in previews {
                let resolved = await linkPreviewResolver.resolve(preview)
                do {
                    try eventStore.saveLinkPreview(resolved)
                } catch {
                    await MainActor.run {
                        self?.recordRuntimeSyncEvent(
                            relayURL: "link-preview",
                            kind: .partialFailure,
                            subscriptionID: nil,
                            message: "link preview save failed: \(error.localizedDescription)"
                        )
                    }
                }
            }

            await MainActor.run {
                guard let self else { return }
                previews.forEach { self.resolvingLinkPreviewURLs.remove($0.normalizedURL) }
                self.linkPreviewTask = nil
                self.scheduleMaterializeEntries()
                if let account = self.account {
                    self.persistDatabase(account: account)
                }
                self.scheduleLinkPreviewResolution()
            }
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
        try? eventStore?.saveRelaySyncEvents([event])
        updateRelayStatusCounts()
        if publishesStatusChange {
            relayStatusRevision &+= 1
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

    private func materializeEntries() {
        materializeTask?.cancel()
        materializeTask = nil
        let filterRules = homeFilterRules()
        let activeFilterRuleSet = filterRules.isEmpty ? nil : NostrFilterRuleSet(rules: filterRules)
        let materializerFilterRuleSet = areTimelineFiltersSuspended ? nil : activeFilterRuleSet
        let contextEvents = contextEventsForCurrentProjection()
        let snapshot = timelineRepository.materialize(
            account: account,
            noteEvents: noteEvents,
            contextEvents: contextEvents,
            metadataEvents: metadataEvents,
            nip05Resolutions: nip05Resolutions,
            followedPubkeys: followedPubkeys,
            resolvedRelays: resolvedRelays,
            filterRules: materializerFilterRuleSet,
            filterStatus: timelineFilterStatus(ruleSet: activeFilterRuleSet)
        )
        if snapshot.renderFingerprint != lastEntriesRenderFingerprint {
            entries = snapshot.entries
            lastEntriesRenderFingerprint = snapshot.renderFingerprint
        }
        unreadState.replaceMaterializedPostIDs(entries.compactMap(\.post?.id))
        publishUnreadState()

        if snapshot.filterStatus != filterStatus {
            filterStatus = snapshot.filterStatus
        }
        resolvedContentRevision &+= 1
    }

    private func publishUnreadState() {
        materializedUnreadCount = unreadState.materializedUnreadCount
        visibleUnreadBadgeCount = unreadState.visibleUnreadBadgeCount
    }

    private func scheduleMaterializeEntries(delayNanoseconds: UInt64? = nil) {
        guard materializeTask == nil else { return }
        let delay = delayNanoseconds ?? materializeCoalescingDelayNanoseconds
        materializeTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: delay)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self, !Task.isCancelled else { return }
                self.materializeTask = nil
                self.materializeEntries()
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
            followedPubkeys: Set(followedPubkeys),
            mediaAssetsByEventID: mediaAssetsByEventID(for: events),
            linkPreviewsByNormalizedURL: linkPreviewsByNormalizedURL(for: events),
            filterRules: homeFilterRuleSet()
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
        return Dictionary(
            uniqueKeysWithValues: events.map { event in
                (event.id, (try? eventStore.mediaAssets(eventID: event.id)) ?? [])
            }
        )
    }

    private func linkPreviewsByNormalizedURL(for events: [NostrEvent]) -> [String: NostrLinkPreviewRecord] {
        guard let eventStore else { return [:] }
        let urls = events.flatMap { NostrLinkParser.webURLs(in: $0.content) }
        return (try? eventStore.linkPreviews(urls: urls)) ?? [:]
    }

    private func materializedAuthor(pubkey: String, metadataEvent: NostrEvent?) -> TimelineAuthor {
        let metadata = metadataEvent.flatMap(Self.profileMetadata)
        guard let displayName = metadata?.bestName else {
            return .unresolved(pubkey: pubkey)
        }

        return .resolved(
            displayName: displayName,
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
            avatarImageURL: nil
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
            let currentFollowedPubkeys = NostrContactList.pubkeys(from: effectiveContactListEvent)
            effectiveFollowedPubkeys = currentFollowedPubkeys.isEmpty ? followedPubkeys : currentFollowedPubkeys
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
    private func rememberLatestMetadataEvent(_ event: NostrEvent) -> NostrEvent {
        let storedMetadataEvent = try? eventStore?.latestReplaceableEvent(pubkey: event.pubkey, kind: 0)
        let currentMetadataEvent = metadataEvents.first { $0.pubkey == event.pubkey }
        let effectiveMetadataEvent = freshestReplaceableEvent([
            currentMetadataEvent,
            event,
            storedMetadataEvent
        ]) ?? event
        metadataEvents.removeAll { $0.pubkey == event.pubkey }
        metadataEvents.append(effectiveMetadataEvent)
        return effectiveMetadataEvent
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
                timestamp: "now",
                replyCount: nil,
                boostCount: nil,
                favoriteCount: nil,
                isLocked: false,
                media: nil,
                context: nil
            ))
        }
        lastEntriesRenderFingerprint = entries.map(\.id)
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
    let profilePubkeys: [String]
    let sourceEventIDs: [String]
    var isOlderPage = false
    var olderAnchorPostID: String?
    var gap: PendingGapBackfill?
    var receivedTimelineEventCount = 0
    var receivedTimelineEventIDs: [String] = []
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

private struct RuntimeSubscriptionKey: Hashable {
    let relayURL: String
    let subscriptionID: String
}

private struct RuntimeSyncWindow {
    private(set) var newestCreatedAt: Int?
    private(set) var oldestCreatedAt: Int?

    mutating func include(_ event: NostrEvent) {
        newestCreatedAt = [newestCreatedAt, event.createdAt].compactMap { $0 }.max()
        oldestCreatedAt = [oldestCreatedAt, event.createdAt].compactMap { $0 }.min()
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
