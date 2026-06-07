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
    @Published private(set) var pendingNewCount = 0

    private let timelineLoader: NostrHomeTimelineLoader
    private let eventStore: NostrEventStore?
    private let relayRuntime: NostrRelayRuntime?
    private let linkPreviewResolver: NostrLinkPreviewResolver?
    private var loadTask: Task<Void, Never>?
    private var paginationTask: Task<Void, Never>?
    private var runtimeTask: Task<Void, Never>?
    private var linkPreviewTask: Task<Void, Never>?
    private var materializeTask: Task<Void, Never>?
    private var resolvingLinkPreviewURLs = Set<String>()
    private var pendingBackwardRequests: [String: PendingBackwardRequest] = [:]
    private var runtimeSyncWindows: [RuntimeSubscriptionKey: RuntimeSyncWindow] = [:]
    private var dependencyFetchQueue = NostrDependencyFetchQueue()
    private var backwardFlushTask: Task<Void, Never>?
    private var installedHomeForwardPacket: NostrREQPacket?
    private var noteEvents: [NostrEvent] = []
    private var metadataEvents: [NostrEvent] = []
    private var relayListEvent: NostrEvent?
    private var contactListEvent: NostrEvent?
    private var nip05Resolutions: [String: NostrNIP05Resolution] = [:]
    private var relaySyncEvents: [NostrRelaySyncEventRecord] = []
    private var areTimelineFiltersSuspended = false
    private var pendingNewEventIDs = Set<String>()
    private var isTimelineAtNewestWindow = true
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
            !pendingBackwardRequests.isEmpty
    }

    init(
        timelineLoader: NostrHomeTimelineLoader = NostrHomeTimelineLoader(),
        eventStore: NostrEventStore? = try? NostrEventStore.applicationSupport(appDirectory: "Astrenza"),
        relayRuntime: NostrRelayRuntime? = nil,
        linkPreviewResolver: NostrLinkPreviewResolver? = nil
    ) {
        self.timelineLoader = timelineLoader
        self.eventStore = eventStore
        self.relayRuntime = relayRuntime
        self.linkPreviewResolver = linkPreviewResolver
    }

    func start(account: NostrAccount) {
        self.account = account
        startRuntimeEventPump()
        restoreCachedSnapshot(account: account)
        if !resolvedRelays.isEmpty {
            Task {
                await configureRelayRuntime(account: account)
            }
        }
        if entries.isEmpty {
            phase = .resolvingRelays
        }
        loadTask?.cancel()
        loadTask = Task {
            await load(account: account)
        }
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

    func applyPendingNewEvents() async {
        guard let account else { return }
        reloadNewestProjectionWindow(account: account)
        pendingNewEventIDs.removeAll()
        pendingNewCount = 0
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
        backwardFlushTask?.cancel()
        loadTask = nil
        paginationTask = nil
        runtimeTask = nil
        linkPreviewTask = nil
        backwardFlushTask = nil
        dependencyFetchQueue.removeAll()
        pendingBackwardRequests.removeAll()
        pendingNewEventIDs.removeAll()
        pendingNewCount = 0
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
                  let parentID = Self.replyParentID(from: tags),
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
            Self.replyParentID(from: event.tags) == post.id
        })
    }

    private func load(account: NostrAccount) async {
        do {
            let state = if relayRuntime != nil {
                runtimeBootstrapState(
                    from: try await timelineLoader.bootstrapState(account: account)
                )
            } else {
                try await timelineLoader.initialState(account: account)
            }
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

        let authors = followedPubkeys.isEmpty ? [account.pubkey] : Array(followedPubkeys.prefix(128))
        guard let packet = NostrBackwardREQBuilder.olderNotes(
            authors: authors,
            until: oldestCreatedAt - 1,
            limit: 100,
            relayURLs: resolvedRelays
        ) else { return }

        pendingBackwardRequests[packet.groupID] = PendingBackwardRequest(
            profilePubkeys: [],
            sourceEventIDs: [],
            isOlderPage: true
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

        let authors = followedPubkeys.isEmpty ? [account.pubkey] : Array(followedPubkeys.prefix(128))
        guard let packet = NostrBackwardREQBuilder.notesWindow(
            authors: authors,
            since: olderEvent.createdAt + 1,
            until: newerEvent.createdAt - 1,
            limit: max(1, min(gap.missingEstimate, 250)),
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
        pendingNewEventIDs.removeAll()
        pendingNewCount = 0
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

    private func reloadProjectionWindow(account: NostrAccount, around anchorEventID: String?) {
        guard let eventStore else { return }
        let timelineEntries: [NostrTimelineEntryRecord]
        if let anchorEventID,
           let anchoredEntries = try? eventStore.timelineEntries(
            accountID: account.pubkey,
            timelineKey: "home",
            aroundEventID: anchorEventID,
            leadingLimit: projectionAnchorLeadingLimit,
            trailingLimit: projectionAnchorTrailingLimit
           ) {
            timelineEntries = anchoredEntries
        } else {
            timelineEntries = (try? eventStore.timelineEntries(
                accountID: account.pubkey,
                timelineKey: "home",
                limit: projectionWindowLimit
            )) ?? []
        }
        noteEvents = projectedTimelineEvents(entries: timelineEntries)
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

    private func configureRelayRuntime(account: NostrAccount, forceInstall: Bool = false) async {
        guard let relayRuntime, !resolvedRelays.isEmpty else { return }

        do {
            try await relayRuntime.setDefaultRelays(resolvedRelays)
            let authors = followedPubkeys.isEmpty ? [account.pubkey] : followedPubkeys
            let newestCreatedAt = noteEvents.map(\.createdAt).max()
            let packet = NostrHomeForwardREQBuilder.reconnectPacket(
                authors: authors,
                newestCreatedAt: newestCreatedAt,
                relayURLs: resolvedRelays
            )
            guard forceInstall || installedHomeForwardPacket != packet else { return }
            try await relayRuntime.installForward(packet)
            installedHomeForwardPacket = packet
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
        switch packet {
        case .stateChanged(let relayURL, let state):
            handleRuntimeStateChange(relayURL: relayURL, state: state)
        case .event(let relayURL, let subscriptionID, let event):
            handleRuntimeEvent(relayURL: relayURL, subscriptionID: subscriptionID, event: event)
        case .eose(let relayURL, let subscriptionID):
            let window = finishRuntimeSyncWindow(relayURL: relayURL, subscriptionID: subscriptionID)
            recordRuntimeSyncEvent(
                relayURL: relayURL,
                kind: .eose,
                subscriptionID: subscriptionID,
                newestCreatedAt: window.newestCreatedAt,
                oldestCreatedAt: window.oldestCreatedAt,
                message: "EOSE received"
            )
        case .closed(let relayURL, let subscriptionID, let message):
            recordRuntimeSyncEvent(
                relayURL: relayURL,
                kind: Self.syncEventKind(forClosedMessage: message),
                subscriptionID: subscriptionID,
                message: message
            )
        case .timeout(let relayURL, let subscriptionID, let message):
            recordRuntimeSyncEvent(
                relayURL: relayURL,
                kind: .timeout,
                subscriptionID: subscriptionID,
                message: message
            )
        case .backwardCompleted(let completion):
            handleBackwardCompletion(completion)
        case .notice(let relayURL, let message):
            recordRuntimeSyncEvent(
                relayURL: relayURL,
                kind: message.lowercased().contains("timeout") ? .timeout : .partialFailure,
                subscriptionID: NostrHomeForwardREQBuilder.subscriptionID,
                message: message
            )
        case .auth(let relayURL, let challenge):
            guard !hasRecentRuntimeSyncEvent(
                relayURL: relayURL,
                kind: .authRequired,
                message: challenge
            ) else { return }
            recordRuntimeSyncEvent(
                relayURL: relayURL,
                kind: .authRequired,
                subscriptionID: NostrHomeForwardREQBuilder.subscriptionID,
                message: challenge
            )
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

    private func handleRuntimeEvent(relayURL: String, subscriptionID: String, event: NostrEvent) {
        if subscriptionID == NostrHomeForwardREQBuilder.subscriptionID {
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

        let embeddedTarget = embeddedRepostTarget(from: event)
        let eventsToSave = [event] + (embeddedTarget.map { [$0] } ?? [])
        do {
            try eventStore?.save(events: eventsToSave)
            try eventStore?.recordEventSources(eventIDs: eventsToSave.map(\.id), relayURL: relayURL)
        } catch {
            recordRuntimeSyncEvent(
                relayURL: relayURL,
                kind: .partialFailure,
                subscriptionID: subscriptionID,
                message: "event save failed: \(error.localizedDescription)"
            )
            return
        }

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
            if isTimelineAtNewestWindow && pendingNewEventIDs.isEmpty {
                reloadNewestProjectionWindow(account: account)
                materializeEntries()
            } else if pendingNewEventIDs.insert(event.id).inserted {
                pendingNewCount = pendingNewEventIDs.count
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

        let embeddedTarget = embeddedRepostTarget(from: event)
        let eventsToSave = [event] + (embeddedTarget.map { [$0] } ?? [])
        do {
            try eventStore?.save(events: eventsToSave)
            try eventStore?.recordEventSources(eventIDs: eventsToSave.map(\.id), relayURL: relayURL)
        } catch {
            recordRuntimeSyncEvent(
                relayURL: relayURL,
                kind: .partialFailure,
                subscriptionID: subscriptionID,
                message: "backward event save failed: \(error.localizedDescription)"
            )
            return
        }

        switch event.kind {
        case 0:
            metadataEvents.removeAll { $0.pubkey == event.pubkey }
            metadataEvents.append(event)
            dependencyFetchQueue.finish(profilePubkeys: [event.pubkey], succeeded: true)
            resolveNIP05IfNeeded(for: event)
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

        guard dependencyFetchQueue.enqueue(
            dependencies: dependencies,
            cacheSnapshot: cacheSnapshot,
            availableRelayURLs: resolvedRelays
        ) else {
            return
        }
        scheduleBackwardDependencyFlush()
    }

    private func embeddedRepostTarget(from event: NostrEvent) -> NostrEvent? {
        guard event.kind == 6,
              let data = event.content.data(using: .utf8),
              let embedded = try? JSONDecoder().decode(NostrEvent.self, from: data),
              embedded.kind == 1,
              embedded.hasValidShape
        else {
            return nil
        }
        return embedded
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
            metadataEvents.removeAll { $0.pubkey == profile.pubkey }
            metadataEvents.append(profile)
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

        var profilePackets: [NostrREQPacket] = []
        var sourcePackets: [NostrREQPacket] = []
        var registeredGroupIDs: [String] = []
        var registeredProfilePubkeys: [String] = []
        var registeredSourceEventIDs: [String] = []

        for group in batch.profileGroups {
            guard let packet = NostrBackwardREQBuilder.profiles(authors: group.values, relayURLs: group.relayURLs) else {
                continue
            }
            pendingBackwardRequests[packet.groupID] = PendingBackwardRequest(profilePubkeys: group.values, sourceEventIDs: [])
            registeredGroupIDs.append(packet.groupID)
            registeredProfilePubkeys.append(contentsOf: group.values)
            profilePackets.append(packet)
        }
        for group in batch.sourceGroups {
            guard let packet = NostrBackwardREQBuilder.sourceEvents(ids: group.values, relayURLs: group.relayURLs) else {
                continue
            }
            pendingBackwardRequests[packet.groupID] = PendingBackwardRequest(profilePubkeys: [], sourceEventIDs: group.values)
            registeredGroupIDs.append(packet.groupID)
            registeredSourceEventIDs.append(contentsOf: group.values)
            sourcePackets.append(packet)
        }

        guard !profilePackets.isEmpty || !sourcePackets.isEmpty else { return }

        Task {
            do {
                if !profilePackets.isEmpty {
                    try await relayRuntime.installBackward(profilePackets, mergeField: .authors)
                }
                if !sourcePackets.isEmpty {
                    try await relayRuntime.installBackward(sourcePackets, mergeField: .ids)
                }
            } catch {
                await MainActor.run {
                    registeredGroupIDs.forEach { pendingBackwardRequests.removeValue(forKey: $0) }
                    dependencyFetchQueue.finish(
                        profilePubkeys: registeredProfilePubkeys,
                        sourceEventIDs: registeredSourceEventIDs,
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
        let priorBottomPostID = noteEvents.last?.id
        dependencyFetchQueue.finish(
            profilePubkeys: request.profilePubkeys,
            sourceEventIDs: request.sourceEventIDs,
            succeeded: completion.status == .completed || completion.status == .partial
        )
        if request.isOlderPage && completion.status == .completed && completion.eventCount == 0 {
            hasMoreOlder = false
        }
        let didReceiveTimelineEvents = completion.eventCount > 0 || request.receivedTimelineEventCount > 0
        if completion.status == .completed || completion.status == .partial || didReceiveTimelineEvents {
            if request.isOlderPage,
               didReceiveTimelineEvents,
               let account {
                reloadProjectionWindow(account: account, around: priorBottomPostID)
                materializeEntries()
                scheduleLinkPreviewResolution()
            }

            if let gap = request.gap,
               let account {
                markGapResolved(gap)
                reloadProjectionWindow(account: account, around: gap.stableAnchorPostID)
                materializeEntries()
                scheduleLinkPreviewResolution()
            }
        }
        relayStatusRevision &+= 1
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

        let authors = current.followedPubkeys.isEmpty ? [account.pubkey] : Array(current.followedPubkeys.prefix(128))
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
        let materialReferenceEvents = noteEvents + contextEvents
        let deletedEntries = account.flatMap { account in
            try? eventStore?.deletedTimelineEntries(accountID: account.pubkey, timelineKey: "home", limit: 250)
        } ?? []
        let timelineEntries = account.flatMap { account in
            try? eventStore?.timelineEntries(accountID: account.pubkey, timelineKey: "home", limit: 500)
        } ?? []
        let nextEntries = NostrTimelineMaterializer.entries(
            noteEvents: noteEvents,
            contextEvents: contextEvents,
            metadataEvents: metadataEvents,
            nip05Resolutions: nip05Resolutions,
            followedPubkeys: Set(followedPubkeys),
            mediaAssetsByEventID: mediaAssetsByEventID(for: materialReferenceEvents),
            linkPreviewsByNormalizedURL: linkPreviewsByNormalizedURL(for: materialReferenceEvents),
            filterRules: materializerFilterRuleSet,
            deletedEntries: deletedEntries,
            timelineEntries: timelineEntries,
            relayCount: max(1, resolvedRelays.count)
        )
        let nextFingerprint = entriesRenderFingerprint(for: nextEntries)
        if nextFingerprint != lastEntriesRenderFingerprint {
            entries = nextEntries
            lastEntriesRenderFingerprint = nextFingerprint
        }

        let nextFilterStatus = timelineFilterStatus(ruleSet: activeFilterRuleSet)
        if nextFilterStatus != filterStatus {
            filterStatus = nextFilterStatus
        }
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

    private func entriesRenderFingerprint(for entries: [TimelineFeedEntry]) -> [String] {
        entries.map(entryRenderFingerprint)
    }

    private func entryRenderFingerprint(_ entry: TimelineFeedEntry) -> String {
        switch entry {
        case .post(let post):
            return [
                "post",
                post.id,
                post.author.primaryText,
                post.author.secondaryText,
                "\(post.author.nip05Status)",
                "\(post.author.isMetadataResolved)",
                "\(post.author.isFollowed)",
                post.avatar.imageURL?.absoluteString ?? "",
                "\(post.avatar.pictureState)",
                post.body,
                post.timestamp,
                post.repostedBy?.author.primaryText ?? "",
                post.repostedBy?.timestamp ?? "",
                post.replyContext?.author.primaryText ?? "",
                post.replyContext?.bodyPreview ?? "",
                post.quotedPost?.body ?? "",
                post.contentWarning?.displayReason ?? "",
                mediaRenderFingerprint(post.media),
                post.linkSummary?.compactText ?? "",
                "\(post.actionState.didReply)",
                "\(post.actionState.didRepost)",
                "\(post.actionState.didFavorite)",
                "\(post.actionState.didZap)"
            ].joined(separator: "\u{1f}")
        case .gap(let gap):
            return [
                "gap",
                gap.id,
                gap.newerPostID,
                gap.olderPostID,
                "\(gap.missingEstimate)",
                "\(gap.relayCount)",
                "\(gap.state)",
                gap.backfilledPosts.map(\.id).joined(separator: ",")
            ].joined(separator: "\u{1f}")
        case .deleted(let entry):
            return "deleted\u{1f}\(entry.id)"
        }
    }

    private func mediaRenderFingerprint(_ media: TimelineMedia?) -> String {
        guard let media else { return "" }
        switch media {
        case .gallery(let tiles):
            return tiles.map { tile in
                [
                    tile.id,
                    tile.title,
                    tile.symbolName,
                    tile.url?.absoluteString ?? "",
                    tile.altText ?? ""
                ].joined(separator: "\u{1e}")
            }.joined(separator: "\u{1d}")
        case .linkPreview(let preview):
            return ["link", preview.title, preview.subtitle, preview.host, preview.url].joined(separator: "\u{1e}")
        case .unresolvedLink(let preview):
            return ["unresolved", preview.host, preview.url].joined(separator: "\u{1e}")
        }
    }

    private func materializedPosts(from events: [NostrEvent]) -> [TimelinePost] {
        let pubkeys = Set(events.map(\.pubkey))
        let metadata = (try? eventStore?.latestReplaceableEvents(pubkeys: pubkeys, kind: 0)) ?? metadataEvents.filter { pubkeys.contains($0.pubkey) }

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
        return NostrTimelineMaterializer.avatar(for: item)
    }

    private func banner(for pubkey: String) -> ProfileBannerStyle {
        let palette = NostrTimelineMaterializer.avatarPalette(for: pubkey)
        return ProfileBannerStyle(colors: [palette.secondary, palette.primary], symbolName: "sparkles")
    }

    private static func profileMetadata(from event: NostrEvent) -> NostrProfileMetadata? {
        guard let data = event.content.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(NostrProfileMetadata.self, from: data)
    }

    private static func replyParentID(from tags: [NostrStoredEventTag]) -> String? {
        let replyTag = tags.last { $0.name == "e" && $0.marker == "reply" }
        if let replyTag {
            return replyTag.value
        }

        let eTags = tags.filter { $0.name == "e" }
        let hasMarkedThreadTags = eTags.contains { $0.marker != nil }
        guard !hasMarkedThreadTags else { return nil }
        return eTags.last?.value
    }

    private static func replyParentID(from tags: [[String]]) -> String? {
        let replyTag = tags.last { tag in
            tag.count >= 4 && tag[0] == "e" && tag[3] == "reply"
        }
        if let replyTag, replyTag.count >= 2 {
            return replyTag[1]
        }

        let eTags = tags.filter { tag in
            tag.count >= 2 && tag[0] == "e"
        }
        let hasMarkedThreadTags = eTags.contains { $0.count >= 4 }
        guard !hasMarkedThreadTags else { return nil }
        return eTags.last?[1]
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
        resolvedRelays = state.relays
        followedPubkeys = state.followedPubkeys
        noteEvents = state.noteEvents
        metadataEvents = state.metadataEvents
        relayListEvent = state.relayListEvent
        contactListEvent = state.contactListEvent
        nip05Resolutions = state.nip05Resolutions
        relaySyncEvents = state.relaySyncEvents
        hasMoreOlder = state.hasMoreOlder
        updateRelayStatusCounts()
    }
}

enum NostrTimelineMaterializer {
    private struct SortableTimelineEntry {
        let id: String
        let sortTimestamp: Int
        let entry: TimelineFeedEntry
    }

    static func entries(
        noteEvents: [NostrEvent],
        contextEvents: [NostrEvent] = [],
        metadataEvents: [NostrEvent],
        nip05Resolutions: [String: NostrNIP05Resolution] = [:],
        followedPubkeys: Set<String>,
        mediaAssetsByEventID: [String: [NostrMediaAssetRecord]] = [:],
        linkPreviewsByNormalizedURL: [String: NostrLinkPreviewRecord] = [:],
        filterRules: NostrFilterRuleSet? = nil,
        deletedEntries: [NostrDeletedTimelineEntryRecord] = [],
        timelineEntries: [NostrTimelineEntryRecord] = [],
        relayCount: Int = 1,
        timeline: NostrFilterTimelineScope = .home
    ) -> [TimelineFeedEntry] {
        let deletedTargetIDs = Set(deletedEntries.map(\.targetEventID))
        let timelineEntryByEventID = Dictionary(uniqueKeysWithValues: timelineEntries.map { ($0.eventID, $0) })
        let postsByID = Dictionary(uniqueKeysWithValues: posts(
            noteEvents: noteEvents,
            contextEvents: contextEvents,
            metadataEvents: metadataEvents,
            nip05Resolutions: nip05Resolutions,
            followedPubkeys: followedPubkeys,
            mediaAssetsByEventID: mediaAssetsByEventID,
            linkPreviewsByNormalizedURL: linkPreviewsByNormalizedURL,
            filterRules: filterRules,
            timeline: timeline
        )
        .filter { !deletedTargetIDs.contains($0.id) }
        .map { ($0.id, $0) })

        let postEntries = noteEvents.compactMap { event -> SortableTimelineEntry? in
            guard let post = postsByID[event.id] else { return nil }
            return SortableTimelineEntry(
                id: post.id,
                sortTimestamp: event.createdAt,
                entry: .post(post)
            )
        }
        let deletedRows = deletedEntries.map { deletedEntry in
            SortableTimelineEntry(
                id: deletedEntry.targetEventID,
                sortTimestamp: deletedEntry.sortTimestamp,
                entry: .deleted(TimelineDeletedEntry(id: "deleted-\(deletedEntry.targetEventID)"))
            )
        }

        let sortedEntries = (postEntries + deletedRows)
            .sorted { lhs, rhs in
                if lhs.sortTimestamp == rhs.sortTimestamp {
                    return lhs.id < rhs.id
                }
                return lhs.sortTimestamp > rhs.sortTimestamp
            }

        guard !timelineEntryByEventID.isEmpty else {
            return sortedEntries.map(\.entry)
        }

        return insertingGapRows(
            into: sortedEntries,
            timelineEntryByEventID: timelineEntryByEventID,
            relayCount: relayCount
        )
        .map(\.entry)
    }

    private static func insertingGapRows(
        into sortedEntries: [SortableTimelineEntry],
        timelineEntryByEventID: [String: NostrTimelineEntryRecord],
        relayCount: Int
    ) -> [SortableTimelineEntry] {
        var output: [SortableTimelineEntry] = []

        for index in sortedEntries.indices {
            let entry = sortedEntries[index]
            let isPostEntry: Bool
            if case .post = entry.entry {
                isPostEntry = true
            } else {
                isPostEntry = false
            }

            if isPostEntry,
               let timelineEntry = timelineEntryByEventID[entry.id],
               timelineEntry.gapBefore,
               let previousPostID = nearestPostID(in: sortedEntries, before: index),
               timelineEntryByEventID[previousPostID]?.gapAfter != true {
                output.append(gapEntry(
                    newerPostID: previousPostID,
                    olderPostID: entry.id,
                    sortTimestamp: entry.sortTimestamp + 1,
                    relayCount: relayCount
                ))
            }

            output.append(entry)

            if isPostEntry,
               let timelineEntry = timelineEntryByEventID[entry.id],
               timelineEntry.gapAfter,
               let nextPostID = nearestPostID(in: sortedEntries, after: index) {
                output.append(gapEntry(
                    newerPostID: entry.id,
                    olderPostID: nextPostID,
                    sortTimestamp: entry.sortTimestamp - 1,
                    relayCount: relayCount
                ))
            }
        }

        return output
    }

    private static func nearestPostID(in entries: [SortableTimelineEntry], before index: Int) -> String? {
        guard index > entries.startIndex else { return nil }
        for candidateIndex in stride(from: index - 1, through: entries.startIndex, by: -1) {
            if case .post = entries[candidateIndex].entry {
                return entries[candidateIndex].id
            }
        }
        return nil
    }

    private static func nearestPostID(in entries: [SortableTimelineEntry], after index: Int) -> String? {
        let nextIndex = index + 1
        guard nextIndex < entries.endIndex else { return nil }
        for candidateIndex in nextIndex..<entries.endIndex {
            if case .post = entries[candidateIndex].entry {
                return entries[candidateIndex].id
            }
        }
        return nil
    }

    private static func gapEntry(
        newerPostID: String,
        olderPostID: String,
        sortTimestamp: Int,
        relayCount: Int
    ) -> SortableTimelineEntry {
        let gapID = "gap-\(newerPostID)-\(olderPostID)"
        return SortableTimelineEntry(
            id: gapID,
            sortTimestamp: sortTimestamp,
            entry: .gap(TimelineGap(
                id: gapID,
                newerPostID: newerPostID,
                olderPostID: olderPostID,
                missingEstimate: 1,
                relayCount: max(1, relayCount),
                state: .needsBackfill,
                backfilledPosts: []
            ))
        )
    }

    static func posts(
        noteEvents: [NostrEvent],
        contextEvents: [NostrEvent] = [],
        metadataEvents: [NostrEvent],
        nip05Resolutions: [String: NostrNIP05Resolution] = [:],
        followedPubkeys: Set<String>,
        mediaAssetsByEventID: [String: [NostrMediaAssetRecord]] = [:],
        linkPreviewsByNormalizedURL: [String: NostrLinkPreviewRecord] = [:],
        filterRules: NostrFilterRuleSet? = nil,
        timeline: NostrFilterTimelineScope = .home,
        now: Int = Int(Date().timeIntervalSince1970)
    ) -> [TimelinePost] {
        var eventsByID: [String: NostrEvent] = [:]
        for event in contextEvents + noteEvents {
            eventsByID[event.id] = event
        }
        let directPosts = NostrHomeTimelineMaterializer.items(
            noteEvents: noteEvents,
            metadataEvents: metadataEvents,
            followedPubkeys: followedPubkeys,
            nip05Resolutions: nip05Resolutions,
            filterRules: filterRules,
            timeline: timeline,
            now: now
        )
        .compactMap { item -> SortableTimelinePost? in
            guard let event = eventsByID[item.id] else { return nil }
            return SortableTimelinePost(
                id: event.id,
                sortTimestamp: event.createdAt,
                post: post(
                    for: item,
                    event: event,
                    eventsByID: eventsByID,
                    metadataEvents: metadataEvents,
                    nip05Resolutions: nip05Resolutions,
                    followedPubkeys: followedPubkeys,
                    mediaAssets: mediaAssetsByEventID[event.id] ?? [],
                    linkPreviewsByNormalizedURL: linkPreviewsByNormalizedURL
                )
            )
        }
        let reposts = repostPosts(
            from: noteEvents,
            metadataEvents: metadataEvents,
            nip05Resolutions: nip05Resolutions,
            followedPubkeys: followedPubkeys,
            eventsByID: eventsByID,
            mediaAssetsByEventID: mediaAssetsByEventID,
            linkPreviewsByNormalizedURL: linkPreviewsByNormalizedURL
        )

        return (directPosts + reposts)
            .sorted { lhs, rhs in
                if lhs.sortTimestamp == rhs.sortTimestamp {
                    return lhs.id < rhs.id
                }
                return lhs.sortTimestamp > rhs.sortTimestamp
            }
            .map(\.post)
    }

    static func post(for item: NostrHomeTimelineItem) -> TimelinePost {
        post(for: item, event: nil, eventsByID: [:])
    }

    private static func post(
        for item: NostrHomeTimelineItem,
        event: NostrEvent?,
        eventsByID: [String: NostrEvent],
        metadataEvents: [NostrEvent] = [],
        nip05Resolutions: [String: NostrNIP05Resolution] = [:],
        followedPubkeys: Set<String> = [],
        mediaAssets: [NostrMediaAssetRecord] = [],
        linkPreviewsByNormalizedURL: [String: NostrLinkPreviewRecord] = [:],
        idOverride: String? = nil,
        repostedBy: TimelineRepostAttribution? = nil
    ) -> TimelinePost {
        let author: TimelineAuthor
        if let displayName = item.displayName {
            author = .resolved(
                displayName: displayName,
                nip05: item.nip05,
                nip05Status: NIP05Status(item.nip05Status),
                pubkey: item.pubkey,
                isFollowed: item.isFollowed
            )
        } else {
            author = .unresolved(pubkey: item.pubkey)
        }
        let attachments = event.map(NostrContentAttachmentClassifier.attachments(from:)) ?? []
        let mediaAttachments = attachments.filter { $0.kind == .media }
        let linkURLs = attachments.filter { $0.kind == .linkPreview }.map(\.url)
        let contentWarning = event.flatMap(contentWarning(from:))

        return TimelinePost(
            id: idOverride ?? item.id,
            author: author,
            avatar: avatar(for: item),
            body: item.body,
            timestamp: relativeTimestamp(from: item.createdAt),
            replyCount: nil,
            boostCount: nil,
            favoriteCount: nil,
            isLocked: false,
            media: media(
                assets: mediaAssets,
                mediaAttachments: mediaAttachments,
                linkURLs: linkURLs,
                linkPreviewsByNormalizedURL: linkPreviewsByNormalizedURL,
                pubkey: item.pubkey
            ),
            context: nil,
            repostedBy: repostedBy,
            quotedPost: event.flatMap {
                quotedPost(
                    from: $0,
                    eventsByID: eventsByID,
                    metadataEvents: metadataEvents,
                    nip05Resolutions: nip05Resolutions,
                    followedPubkeys: followedPubkeys
                )
            },
            replyContext: event.flatMap { replyContext(from: $0, eventsByID: eventsByID, fallbackAuthor: author) },
            replyMention: event.flatMap { replyMention(from: $0, author: author) },
            contentWarning: contentWarning,
            bodyPresentation: bodyPresentation(
                body: item.body,
                linkURLs: linkURLs,
                isFollowed: item.isFollowed,
                filterMatch: item.filterMatch
            ),
            linkSummary: linkSummary(from: linkURLs),
            actionState: .none
        )
    }

    private struct SortableTimelinePost {
        let id: String
        let sortTimestamp: Int
        let post: TimelinePost
    }

    private static func repostPosts(
        from events: [NostrEvent],
        metadataEvents: [NostrEvent],
        nip05Resolutions: [String: NostrNIP05Resolution],
        followedPubkeys: Set<String>,
        eventsByID: [String: NostrEvent],
        mediaAssetsByEventID: [String: [NostrMediaAssetRecord]],
        linkPreviewsByNormalizedURL: [String: NostrLinkPreviewRecord]
    ) -> [SortableTimelinePost] {
        events
            .filter { $0.kind == 6 }
            .compactMap { repostEvent in
                guard let targetID = repostTargetID(from: repostEvent) else { return nil }

                let attribution = repostAttribution(
                    for: repostEvent,
                    metadataEvents: metadataEvents,
                    nip05Resolutions: nip05Resolutions,
                    followedPubkeys: followedPubkeys
                )
                guard let targetEvent = eventsByID[targetID],
                      targetEvent.kind == 1
                else {
                    return missingRepostTarget(
                        repostEvent: repostEvent,
                        targetID: targetID,
                        attribution: attribution
                    )
                }

                let targetItem = NostrHomeTimelineMaterializer.items(
                    noteEvents: [targetEvent],
                    metadataEvents: metadataEvents,
                    followedPubkeys: followedPubkeys,
                    nip05Resolutions: nip05Resolutions
                ).first
                guard let targetItem else { return nil }

                return SortableTimelinePost(
                    id: repostEvent.id,
                    sortTimestamp: repostEvent.createdAt,
                    post: post(
                        for: targetItem,
                        event: targetEvent,
                        eventsByID: eventsByID,
                        metadataEvents: metadataEvents,
                        nip05Resolutions: nip05Resolutions,
                        followedPubkeys: followedPubkeys,
                        mediaAssets: mediaAssetsByEventID[targetEvent.id] ?? [],
                        linkPreviewsByNormalizedURL: linkPreviewsByNormalizedURL,
                        idOverride: repostEvent.id,
                        repostedBy: attribution
                    )
                )
            }
    }

    private static func repostAttribution(
        for repostEvent: NostrEvent,
        metadataEvents: [NostrEvent],
        nip05Resolutions: [String: NostrNIP05Resolution],
        followedPubkeys: Set<String>
    ) -> TimelineRepostAttribution {
        let metadata = NostrHomeTimelineMaterializer.latestMetadataByPubkey(metadataEvents)[repostEvent.pubkey]
        let repostItem = NostrHomeTimelineItem(
            id: repostEvent.id,
            pubkey: repostEvent.pubkey,
            displayName: metadata?.bestName,
            nip05: metadata?.nip05,
            nip05Status: coreNIP05Status(metadata: metadata, resolution: nip05Resolutions[repostEvent.pubkey]),
            isFollowed: followedPubkeys.contains(repostEvent.pubkey),
            body: "",
            createdAt: repostEvent.createdAt,
            avatarPictureState: avatarPictureState(for: metadata),
            avatarImageURL: metadata?.pictureURL
        )
        let author: TimelineAuthor
        if let displayName = repostItem.displayName {
            author = .resolved(
                displayName: displayName,
                nip05: repostItem.nip05,
                nip05Status: NIP05Status(repostItem.nip05Status),
                pubkey: repostItem.pubkey,
                isFollowed: repostItem.isFollowed
            )
        } else {
            author = .unresolved(pubkey: repostEvent.pubkey)
        }
        return TimelineRepostAttribution(
            author: author,
            avatar: avatar(for: repostItem),
            timestamp: relativeTimestamp(from: repostEvent.createdAt)
        )
    }

    private static func missingRepostTarget(
        repostEvent: NostrEvent,
        targetID: String,
        attribution: TimelineRepostAttribution
    ) -> SortableTimelinePost {
        let targetPubkey = repostEvent.tags.first { tag in
            tag.count >= 2 && tag[0] == "p" && tag[1].count == 64
        }?[1] ?? TimelineAuthor.mockPubkey(for: targetID)
        let author = TimelineAuthor.unresolved(pubkey: targetPubkey)
        let avatar = AvatarStyle(
            primary: .secondary,
            secondary: .gray,
            symbolName: "arrow.triangle.2.circlepath",
            pictureState: .metadataPending,
            placeholderSeed: targetPubkey
        )
        let post = TimelinePost(
            id: repostEvent.id,
            author: author,
            avatar: avatar,
            body: "Reposted post unavailable",
            timestamp: relativeTimestamp(from: repostEvent.createdAt),
            replyCount: nil,
            boostCount: nil,
            favoriteCount: nil,
            isLocked: false,
            media: nil,
            context: nil,
            repostedBy: attribution,
            bodyPresentation: .collapsed(lineLimit: 1, reason: .longText),
            actionState: .none
        )
        return SortableTimelinePost(id: repostEvent.id, sortTimestamp: repostEvent.createdAt, post: post)
    }

    static func avatar(for item: NostrHomeTimelineItem) -> AvatarStyle {
        let palette = avatarPalette(for: item.pubkey)
        return AvatarStyle(
            primary: palette.primary,
            secondary: palette.secondary,
            symbolName: "person.fill",
            pictureState: AvatarPictureState(item.avatarPictureState),
            placeholderSeed: item.pubkey,
            imageURL: item.avatarImageURL
        )
    }

    private static func avatarPictureState(for metadata: NostrProfileMetadata?) -> NostrAvatarPictureState {
        guard let metadata else { return .metadataPending }
        return metadata.pictureURL == nil ? .missing : .resolved
    }

    private static func coreNIP05Status(
        metadata: NostrProfileMetadata?,
        resolution: NostrNIP05Resolution?
    ) -> NostrNIP05Status {
        guard let identifier = metadata?.nip05, !identifier.isEmpty else { return .absent }
        guard let resolution, resolution.identifier == identifier else { return .unchecked }
        return resolution.status
    }

    static func avatarPalette(for pubkey: String) -> (primary: Color, secondary: Color) {
        let colors: [Color] = [.purple, .cyan, .mint, .orange, .pink, .blue, .green, .indigo]
        let seed = pubkey.utf8.reduce(0) { Int($0) + Int($1) }
        return (colors[seed % colors.count], colors[(seed / 3 + 2) % colors.count])
    }

    private static func relativeTimestamp(from createdAt: Int) -> String {
        let delta = max(0, Int(Date().timeIntervalSince1970) - createdAt)
        if delta < 60 {
            return "\(delta)s"
        }
        if delta < 3_600 {
            return "\(delta / 60)m"
        }
        if delta < 86_400 {
            return "\(delta / 3_600)h"
        }
        return "\(delta / 86_400)d"
    }

    private static func media(
        assets: [NostrMediaAssetRecord],
        mediaAttachments: [NostrClassifiedAttachment],
        linkURLs: [URL],
        linkPreviewsByNormalizedURL: [String: NostrLinkPreviewRecord],
        pubkey: String
    ) -> TimelineMedia? {
        if !assets.isEmpty {
            let palette = avatarPalette(for: pubkey)
            let tiles = assets.prefix(5).compactMap { asset -> MediaTile? in
                guard let url = URL(string: asset.url) else { return nil }
                return MediaTile(
                    title: asset.alt ?? (url.lastPathComponent.isEmpty ? (url.host ?? "media") : url.lastPathComponent),
                    colors: [palette.primary, palette.secondary],
                    symbolName: asset.mimeType?.hasPrefix("video/") == true ? "play.rectangle" : "photo",
                    url: url,
                    altText: asset.alt
                )
            }
            if !tiles.isEmpty {
                return .gallery(Array(tiles))
            }
        }

        if !mediaAttachments.isEmpty {
            let palette = avatarPalette(for: pubkey)
            let tiles = mediaAttachments.prefix(5).map { attachment in
                let url = attachment.url
                return MediaTile(
                    title: attachment.alt ?? (url.lastPathComponent.isEmpty ? (url.host ?? "media") : url.lastPathComponent),
                    colors: [palette.primary, palette.secondary],
                    symbolName: attachment.mimeType?.hasPrefix("video/") == true ? "play.rectangle" : "photo",
                    url: url,
                    altText: attachment.alt
                )
            }
            return .gallery(Array(tiles))
        }

        guard let link = linkURLs.first else { return nil }
        let normalizedURL = NostrLinkParser.normalizedURLString(link)
        if let preview = linkPreviewsByNormalizedURL[normalizedURL],
           preview.status == "resolved",
           let title = preview.title {
            return .linkPreview(LinkPreview(
                title: title,
                subtitle: preview.summary ?? preview.siteName ?? normalizedURL,
                host: preview.siteName ?? link.host ?? link.absoluteString,
                url: preview.url
            ))
        }
        return .unresolvedLink(UnresolvedLinkPreview(host: link.host ?? link.absoluteString, url: link.absoluteString))
    }

    private static func contentWarning(from event: NostrEvent) -> TimelineContentWarning? {
        guard let tag = event.tags.first(where: { $0.first == "content-warning" }) else { return nil }
        return TimelineContentWarning(reason: tag.dropFirst().first)
    }

    private static func replyContext(
        from event: NostrEvent,
        eventsByID: [String: NostrEvent],
        fallbackAuthor: TimelineAuthor
    ) -> TimelineReplyContext? {
        guard let parentID = replyParentID(from: event.tags),
              let parent = eventsByID[parentID]
        else { return nil }

        let parentItem = NostrHomeTimelineItem(
            id: parent.id,
            pubkey: parent.pubkey,
            displayName: nil,
            nip05: nil,
            nip05Status: .absent,
            isFollowed: true,
            body: parent.content,
            createdAt: parent.createdAt,
            avatarPictureState: .metadataPending,
            avatarImageURL: nil
        )
        let parentAuthor = parent.pubkey == event.pubkey ? fallbackAuthor : TimelineAuthor.unresolved(pubkey: parent.pubkey)
        return TimelineReplyContext(
            author: parentAuthor,
            avatar: avatar(for: parentItem),
            timestamp: relativeTimestamp(from: parent.createdAt),
            bodyPreview: parent.content,
            isSelfReply: parent.pubkey == event.pubkey
        )
    }

    private static func replyMention(from event: NostrEvent, author: TimelineAuthor) -> TimelineReplyMention? {
        guard replyParentID(from: event.tags) != nil,
              let pubkey = event.tags.first(where: { $0.first == "p" && $0.count >= 2 })?[1],
              pubkey != event.pubkey
        else { return nil }

        let display = "@\(pubkey.prefix(10))"
        return TimelineReplyMention(text: String(display), isExternal: pubkey != author.pubkey)
    }

    private static func quotedPost(
        from event: NostrEvent,
        eventsByID: [String: NostrEvent],
        metadataEvents: [NostrEvent],
        nip05Resolutions: [String: NostrNIP05Resolution],
        followedPubkeys: Set<String>
    ) -> QuotedTimelinePost? {
        guard let quotedID = quotedPostID(from: event) else { return nil }
        if let quoted = eventsByID[quotedID] {
            let item = NostrHomeTimelineMaterializer.items(
                noteEvents: [quoted],
                metadataEvents: metadataEvents,
                followedPubkeys: followedPubkeys,
                nip05Resolutions: nip05Resolutions
            ).first ?? NostrHomeTimelineItem(
                id: quoted.id,
                pubkey: quoted.pubkey,
                displayName: nil,
                nip05: nil,
                nip05Status: .absent,
                isFollowed: followedPubkeys.contains(quoted.pubkey),
                body: quoted.content,
                createdAt: quoted.createdAt,
                avatarPictureState: .metadataPending,
                avatarImageURL: nil
            )
            let author: TimelineAuthor
            if let displayName = item.displayName {
                author = .resolved(
                    displayName: displayName,
                    nip05: item.nip05,
                    nip05Status: NIP05Status(item.nip05Status),
                    pubkey: item.pubkey,
                    isFollowed: item.isFollowed
                )
            } else {
                author = .unresolved(pubkey: item.pubkey)
            }
            return QuotedTimelinePost(
                author: author,
                avatar: avatar(for: item),
                body: quoted.content,
                timestamp: relativeTimestamp(from: quoted.createdAt),
                isAvailable: true
            )
        }

        return QuotedTimelinePost(
            author: TimelineAuthor.unresolved(pubkey: quotedID),
            avatar: AvatarStyle(primary: .secondary, secondary: .gray, symbolName: "quote.bubble.fill", pictureState: .metadataPending, placeholderSeed: quotedID),
            body: "Quoted note is not cached yet.",
            timestamp: "",
            isAvailable: false
        )
    }

    private static func quotedPostID(from event: NostrEvent) -> String? {
        if let quotedTagID = event.tags.last(where: { $0.first == "q" && $0.count >= 2 })?[1] {
            return quotedTagID
        }
        if let contentReference = nip19EventReference(in: event.content) {
            return contentReference
        }
        return quoteLikeEventID(from: event.tags)
    }

    private static func nip19EventReference(in content: String) -> String? {
        content
            .split(whereSeparator: \.isWhitespace)
            .lazy
            .compactMap { token -> String? in
                let trimmed = token.trimmingCharacters(in: CharacterSet(charactersIn: ".,;:!?)]}>\n"))
                guard trimmed.hasPrefix("note1") || trimmed.hasPrefix("nostr:note1") else { return nil }
                return try? NostrNIP19.eventIDHex(from: trimmed)
            }
            .first
    }

    private static func quoteLikeEventID(from tags: [[String]]) -> String? {
        tags.last { tag in
            tag.count >= 4 && tag[0] == "e" && tag[3] == "mention"
        }?[1]
    }

    private static func repostTargetID(from event: NostrEvent) -> String? {
        event.tags.last { tag in
            tag.count >= 2 && tag[0] == "e"
        }?[1]
    }

    private static func bodyPresentation(
        body: String,
        linkURLs: [URL],
        isFollowed: Bool,
        filterMatch: NostrFilterMatchReason? = nil
    ) -> TimelineBodyPresentation {
        if filterMatch != nil {
            return .collapsed(lineLimit: 2, reason: .filtered)
        }
        if !isFollowed && !linkURLs.isEmpty {
            return .collapsed(lineLimit: 3, reason: .lowTrustLinks)
        }
        if linkURLs.count >= 5 {
            return .collapsed(lineLimit: 4, reason: .linkHeavy)
        }
        if body.count > 1_000 {
            return .collapsed(lineLimit: 8, reason: .longText)
        }
        return .standard
    }

    private static func linkSummary(from linkURLs: [URL]) -> TimelineLinkSummary? {
        guard !linkURLs.isEmpty else { return nil }
        let hosts = Array(Set(linkURLs.compactMap(\.host))).sorted()
        return TimelineLinkSummary(totalCount: linkURLs.count, visibleHosts: hosts, unresolvedCount: linkURLs.count)
    }

    private static func replyParentID(from tags: [[String]]) -> String? {
        let replyTag = tags.last { tag in
            tag.count >= 4 && tag[0] == "e" && tag[3] == "reply"
        }
        if let replyTag, replyTag.count >= 2 {
            return replyTag[1]
        }

        let eTags = tags.filter { tag in
            tag.count >= 2 && tag[0] == "e"
        }
        let hasMarkedThreadTags = eTags.contains { $0.count >= 4 }
        guard !hasMarkedThreadTags else { return nil }
        return eTags.last?[1]
    }
}

private extension NIP05Status {
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
    let profilePubkeys: [String]
    let sourceEventIDs: [String]
    var isOlderPage = false
    var gap: PendingGapBackfill?
    var receivedTimelineEventCount = 0
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
