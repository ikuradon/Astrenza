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
    private let runtimeEventApplicationPlanner: HomeTimelineRuntimeEventApplicationPlanner
    private let dependencyCoordinator: HomeTimelineDependencyResolutionCoordinator
    private let listProjectionCache: HomeTimelineListProjectionCache
    private let materializationScheduler: HomeTimelineMaterializationScheduler
    private let pendingEventBuffer: HomeTimelinePendingEventBuffer
    private let backwardRequestRegistry: HomeTimelineBackwardRequestRegistry
    private let feedSyncCoordinator: HomeTimelineFeedSyncCoordinator
    private let lifecycleCoordinator: HomeTimelineLifecycleCoordinator
    private let runtimeEventPump: HomeTimelineRuntimeEventPump
    private let relayRuntimeConfigurator: HomeTimelineRelayRuntimeConfigurator
    private let relayRuntimeTerminator: HomeTimelineRelayRuntimeTerminator
    private let relayDiagnostics: HomeTimelineRelayDiagnosticsLedger
    private let linkPreviewCoordinator: HomeTimelineLinkPreviewCoordinator
    private let readStateCoordinator: HomeTimelineReadStateCoordinator
    private let syncPlanner: HomeTimelineSyncPlanner
    private let timelineRepository: HomeTimelineRepository
    private let timelineCoordinator: HomeTimelineCoordinator
    private let gapReconciler: HomeTimelineGapReconciler
    private let homeFeedProjection: HomeFeedProjectionController
    private let relayRuntime: NostrRelayRuntime?
    private let outboxCoordinator: HomeTimelineOutboxCoordinator
    private let syncPolicySettingsStore: NostrSyncPolicySettingsStore
    private var syncPolicy: NostrSyncPolicy
    private var noteEvents: [NostrEvent] = []
    private var metadataEvents: [NostrEvent] = []
    private var relayListEvent: NostrEvent?
    private var contactListEvent: NostrEvent?
    private var areTimelineFiltersSuspended = false
    private var unreadState = HomeTimelineUnreadState()
    private var isTimelineAtNewestWindow = true
    private var restoreProjectionAnchorEventID: String?

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
        if isLoadingOlder || backwardRequestRegistry.hasOlderPageRequest {
            return NostrTimelineActivityStatus(
                title: "Loading older posts",
                detail: "Fetching the previous Home timeline window",
                compactLabel: "Older"
            )
        }
        if backwardRequestRegistry.hasGapWork {
            return NostrTimelineActivityStatus(
                title: "Filling a timeline gap",
                detail: "Reconciling missing events between local windows",
                compactLabel: "Gap"
            )
        }
        if backwardRequestRegistry.hasRequests || dependencyCoordinator.hasPendingWork {
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
        let sourcePacketInstaller: HomeTimelineDependencyResolutionCoordinator.SourcePacketInstaller?
        if let relayRuntime {
            sourcePacketInstaller = { packets in
                try await relayRuntime.installBackward(packets, mergeField: .ids)
            }
        } else {
            sourcePacketInstaller = nil
        }
        self.eventIngestor = eventIngestor
        self.runtimeEventApplicationPlanner = HomeTimelineRuntimeEventApplicationPlanner()
        self.syncPlanner = syncPlanner
        self.timelineRepository = HomeTimelineRepository(eventStore: eventStore)
        self.timelineCoordinator = HomeTimelineCoordinator()
        self.gapReconciler = HomeTimelineGapReconciler(
            eventStore: eventStore,
            relayClient: timelineLoader.relayClient
        )
        self.homeFeedProjection = HomeFeedProjectionController(eventStore: eventStore)
        let backwardRequestRegistry = HomeTimelineBackwardRequestRegistry()
        self.backwardRequestRegistry = backwardRequestRegistry
        self.feedSyncCoordinator = HomeTimelineFeedSyncCoordinator(
            eventStore: eventStore,
            backwardRequestRegistry: backwardRequestRegistry
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
        self.listProjectionCache = HomeTimelineListProjectionCache()
        self.materializationScheduler = HomeTimelineMaterializationScheduler()
        self.pendingEventBuffer = HomeTimelinePendingEventBuffer()
        self.lifecycleCoordinator = HomeTimelineLifecycleCoordinator()
        let runtimeEventPump = HomeTimelineRuntimeEventPump()
        self.runtimeEventPump = runtimeEventPump
        self.relayRuntimeConfigurator = HomeTimelineRelayRuntimeConfigurator(
            relayRuntime: relayRuntime,
            runtimeEventPump: runtimeEventPump,
            dependencyCoordinator: dependencyCoordinator,
            syncPlanner: syncPlanner
        )
        self.relayRuntimeTerminator = HomeTimelineRelayRuntimeTerminator()
        self.relayDiagnostics = HomeTimelineRelayDiagnosticsLedger(
            eventStore: eventStore,
            persistenceWorker: persistenceWorker
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
            phase = .loaded
        } else if relayRuntime != nil || entries.isEmpty {
            phase = .resolvingRelays
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
        let hadPendingNewEvents = pendingEventBuffer.hasEvents ||
            materializationScheduler.hasPendingNewestProjectionReload
        restoreProjectionAnchorEventID = nil
        isTimelineAtNewestWindow = true
        reloadNewestProjectionWindow(account: account)
        clearPendingNewEvents()
        materializationScheduler.clearNewestProjectionReload()
        materializeEntries()
        scheduleLinkPreviewResolution()
        return hadPendingNewEvents
    }

    func loadOlder() {
        guard let account,
              let lifecycle = lifecycleCoordinator.token(for: account.pubkey),
              !isLoadingOlder,
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
        outboxCoordinator.requestImmediateDrain()
    }

    private func activateOutbox(accountID: String) {
        outboxCoordinator.activate(accountID: accountID) { [weak self] in
            self?.relayStatusRevision &+= 1
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
        let cacheKey = HomeTimelineListProjectionCache.Key(
            accountID: account.pubkey,
            limit: limit,
            homeContentRevision: resolvedContentRevision
        )
        return listProjectionCache.entries(for: cacheKey) {
            let listEvents = cachedListTimelineEvents(
                accountID: account.pubkey,
                eventStore: eventStore,
                limit: limit
            )
            guard !listEvents.isEmpty else { return [] }
            let pubkeys = Set(listEvents.map(\.pubkey))
            let metadata = (try? eventStore.latestReplaceableEvents(
                pubkeys: pubkeys,
                kind: 0
            )) ?? metadataEvents.filter { pubkeys.contains($0.pubkey) }
            return NostrTimelineMaterializer.entries(
                noteEvents: listEvents,
                metadataEvents: metadata,
                nip05Resolutions: dependencyCoordinator.nip05Resolutions,
                profileResolutionStates: dependencyCoordinator.profileResolutionStates,
                followedPubkeys: Set(followedPubkeys),
                mediaAssetsByEventID: mediaAssetsByEventID(for: listEvents),
                linkPreviewsByNormalizedURL: linkPreviewsByNormalizedURL(for: listEvents),
                filterRules: listFilterRuleSet(),
                timeline: .lists
            )
        }
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
        readStateCoordinator.endSession(flushing: homeFeedReadBoundaryWrite())
        relayDiagnostics.flushTraffic()
        let cancellationGeneration = lifecycleCoordinator.cancel()
        runtimeEventPump.cancel()
        linkPreviewCoordinator.reset()
        materializationScheduler.reset()
        realtimeFollowSourceRevision = materializationScheduler.realtimeFollowSourceRevision
        outboxCoordinator.cancel()
        dependencyCoordinator.reset()
        backwardRequestRegistry.reset()
        clearPendingNewEvents()
        isRefreshing = false
        isLoadingOlder = false
        invalidateListEntries()
        homeFeedProjection.reset()
        relayRuntimeConfigurator.reset()
        resetHomeTimelineRealtime()
        feedSyncCoordinator.reset(finishingActiveRequestsWith: .cancelled)
        relayRuntimeStates = [:]
        entries = []
        resolvedRelays = []
        followedPubkeys = []
        noteEvents = []
        metadataEvents = []
        relayListEvent = nil
        contactListEvent = nil
        relayDiagnostics.reset()
        hasMoreOlder = true
        filterStatus = TimelineFilterStatus()
        unreadState.reset()
        publishUnreadState()
        restoreProjectionAnchorEventID = nil
        isTimelineAtNewestWindow = true
        areTimelineFiltersSuspended = false
        updateRelayStatusCounts()
        relayStatusRevision &+= 1
        phase = .idle
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

    private func load(
        account: NostrAccount,
        lifecycle: HomeTimelineLifecycleToken
    ) async {
        guard lifecycleCoordinator.isCurrent(lifecycle) else { return }
        if relayRuntime != nil {
            await loadRuntimeBootstrap(account: account, lifecycle: lifecycle)
            return
        }

        do {
            let state = try await timelineLoader.initialState(
                account: account,
                onStage: { [weak self] stage in
                    await self?.handleLoadStage(
                        stage,
                        lifecycle: lifecycle
                    )
                }
            )
            guard !Task.isCancelled,
                  lifecycleCoordinator.isCurrent(lifecycle)
            else { return }
            phase = .loadingHome
            await relayDiagnostics.persistFetchedEvents(state.relaySyncEvents)
            guard !Task.isCancelled,
                  lifecycleCoordinator.isCurrent(lifecycle)
            else { return }
            apply(state)
            materializeEntries()
            await persistDatabase(account: account)
            guard !Task.isCancelled,
                  lifecycleCoordinator.isCurrent(lifecycle)
            else { return }
            await configureRelayRuntime(account: account)
            guard lifecycleCoordinator.isCurrent(lifecycle) else { return }
            phase = .loaded
        } catch {
            guard !Task.isCancelled,
                  lifecycleCoordinator.isCurrent(lifecycle)
            else { return }
            phase = .failed("Home timeline failed: \(error.localizedDescription)")
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
            phase = .resolvingRelays
        }

        do {
            let bootstrapState = try await timelineLoader.bootstrapState(
                account: account,
                onStage: { [weak self] stage in
                    await self?.handleLoadStage(
                        stage,
                        lifecycle: lifecycle
                    )
                }
            )
            guard !Task.isCancelled,
                  lifecycleCoordinator.isCurrent(lifecycle)
            else { return }
            phase = .loadingHome
            await relayDiagnostics.persistFetchedEvents(bootstrapState.relaySyncEvents)
            guard !Task.isCancelled,
                  lifecycleCoordinator.isCurrent(lifecycle)
            else { return }
            apply(runtimeBootstrapState(from: bootstrapState))
            lifecycleCoordinator.setRuntimeBootstrapCompleted(true, for: lifecycle)
            materializeEntries()
            await persistDatabase(account: account)
            guard !Task.isCancelled,
                  lifecycleCoordinator.isCurrent(lifecycle)
            else { return }
            await configureRelayRuntime(account: account)
            guard lifecycleCoordinator.isCurrent(lifecycle) else { return }
            phase = .loaded
        } catch {
            guard !Task.isCancelled,
                  lifecycleCoordinator.isCurrent(lifecycle)
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
                lifecycleCoordinator.setRuntimeBootstrapCompleted(true, for: lifecycle)
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
        lifecycle: HomeTimelineLifecycleToken
    ) {
        guard !Task.isCancelled,
              lifecycleCoordinator.isCurrent(lifecycle)
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

    private func refreshLatest(
        account: NostrAccount,
        lifecycle: HomeTimelineLifecycleToken
    ) async {
        guard !isRefreshing else { return }
        guard lifecycleCoordinator.isCurrent(lifecycle) else { return }
        guard !noteEvents.isEmpty else {
            start(account: account)
            return
        }

        isRefreshing = true
        defer {
            if lifecycleCoordinator.isCurrent(lifecycle) {
                isRefreshing = false
            }
        }

        if relayRuntime != nil {
            await configureRelayRuntime(account: account)
            guard !Task.isCancelled,
                  lifecycleCoordinator.isCurrent(lifecycle)
            else { return }
            phase = .loaded
            return
        }

        do {
            let state = try await timelineLoader.refreshedState(account: account, current: loaderState())
            guard !Task.isCancelled,
                  lifecycleCoordinator.isCurrent(lifecycle)
            else { return }
            await relayDiagnostics.persistFetchedEvents(state.relaySyncEvents)
            guard !Task.isCancelled,
                  lifecycleCoordinator.isCurrent(lifecycle)
            else { return }
            apply(state)
            materializeEntries()
            await persistDatabase(account: account)
            guard !Task.isCancelled,
                  lifecycleCoordinator.isCurrent(lifecycle)
            else { return }
            await configureRelayRuntime(account: account)
            guard lifecycleCoordinator.isCurrent(lifecycle) else { return }
            phase = .loaded
        } catch {
            guard !Task.isCancelled,
                  lifecycleCoordinator.isCurrent(lifecycle)
            else { return }
            phase = .failed("Refresh failed: \(error.localizedDescription)")
        }
    }

    private func loadOlder(
        account: NostrAccount,
        lifecycle: HomeTimelineLifecycleToken
    ) async {
        guard lifecycleCoordinator.isCurrent(lifecycle) else { return }
        isLoadingOlder = true
        defer {
            if lifecycleCoordinator.isCurrent(lifecycle) {
                isLoadingOlder = false
            }
        }

        if relayRuntime != nil {
            await requestOlderNotesThroughRuntime(account: account)
            guard !Task.isCancelled,
                  lifecycleCoordinator.isCurrent(lifecycle)
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
                  lifecycleCoordinator.isCurrent(lifecycle)
            else { return }
            await relayDiagnostics.persistFetchedEvents(state.relaySyncEvents)
            guard !Task.isCancelled,
                  lifecycleCoordinator.isCurrent(lifecycle)
            else { return }
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
            phase = .loaded
        } catch {
            guard !Task.isCancelled,
                  lifecycleCoordinator.isCurrent(lifecycle)
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
        clearPendingNewEvents()
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
        guard let persistenceWorker,
              let lifecycle = lifecycleCoordinator.token(for: account.pubkey)
        else { return }
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
                  lifecycleCoordinator.isCurrent(lifecycle),
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
            if pendingEventBuffer.isEmpty {
                materializeEntries()
            }
        } catch {
            // Live networking can still populate the timeline if the database write fails.
        }
    }

    private func persistTimelineMetadata(account: NostrAccount) async {
        guard let persistenceWorker,
              let lifecycle = lifecycleCoordinator.token(for: account.pubkey)
        else { return }
        let now = Int(Date().timeIntervalSince1970)
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
            guard lifecycleCoordinator.isCurrent(lifecycle),
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
        unreadState.setReadBoundary(postID: boundaryID)
        publishUnreadState()
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

        let boundaryID = unreadState.readBoundaryPostID
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
                resolvedRelays + account.discoveryRelays + timelineLoader.bootstrapRelays
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
        guard Self.isHomeForwardSubscription(key.subscriptionID) else { return }
        feedSyncCoordinator.invalidateForwardSubscription(key)
        publishHomeTimelineRealtimeState()
    }

    private func invalidateHomeTimelineRealtime(relayURL: String) {
        feedSyncCoordinator.invalidateForwardSubscriptions(relayURL: relayURL)
        publishHomeTimelineRealtimeState()
    }

    private func publishHomeTimelineRealtimeState() {
        let nextIsRealtime = feedSyncCoordinator.isRealtime
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
                    let window = self.feedSyncCoordinator.finishWindow(
                        relayURL: relayURL,
                        subscriptionID: subscriptionID
                    )
                    let isHomeForward = Self.isHomeForwardSubscription(subscriptionID)
                    self.feedSyncCoordinator.recordEOSE(
                        relayURL: relayURL,
                        subscriptionID: subscriptionID,
                        window: window
                    )
                    self.publishHomeTimelineRealtimeState()
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
                    let window = self.feedSyncCoordinator.finishWindow(
                        relayURL: relayURL,
                        subscriptionID: subscriptionID
                    )
                    self.feedSyncCoordinator.endRequest(
                        relayURL: relayURL,
                        subscriptionID: subscriptionID,
                        reason: .closed,
                        message: message,
                        window: window
                    )
                    self.publishHomeTimelineRealtimeState()
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
                    let window = self.feedSyncCoordinator.finishWindow(
                        relayURL: relayURL,
                        subscriptionID: subscriptionID
                    )
                    self.feedSyncCoordinator.endRequest(
                        relayURL: relayURL,
                        subscriptionID: subscriptionID,
                        reason: .timeout,
                        message: message,
                        window: window
                    )
                    self.publishHomeTimelineRealtimeState()
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
                    self.relayDiagnostics.recordTraffic(delta)
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

    private func handleHomeForwardEvent(relayURL: String, subscriptionID: String, event: NostrEvent) async {
        guard event.kind == 1 || event.kind == 5 || event.kind == 6,
              let account,
              let lifecycle = lifecycleCoordinator.token(for: account.pubkey)
        else { return }
        let receivedWhileRealtime = isHomeTimelineRealtime
        let accountID = account.pubkey

        let requestID = feedSyncCoordinator.requestID(
            relayURL: relayURL,
            subscriptionID: subscriptionID
        )
        let requestContext = feedSyncCoordinator.context(
            relayURL: relayURL,
            subscriptionID: subscriptionID
        )

        let projectedIngestResult: HomeTimelineProjectedEventIngestResult
        do {
            ensureHomeFeedDefinition(account: account)
            projectedIngestResult = try await eventIngestor.ingestForward(
                HomeTimelineForwardEventIngestRequest(
                    event: event,
                    relayURL: relayURL,
                    activeFeedContext: activeHomeFeedRuntimeContext(),
                    requestContext: requestContext,
                    sourceRequestID: requestID
                )
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
        guard lifecycleCoordinator.isCurrent(lifecycle),
              self.account?.pubkey == accountID
        else { return }
        let applicationPlan = runtimeEventApplicationPlanner.planForward(.init(
            event: event,
            embeddedEvent: projectedIngestResult.eventResult.embeddedEvent,
            projectsIntoCurrentFeed: projectedIngestResult.projectsIntoCurrentFeed,
            receivedWhileRealtime: receivedWhileRealtime,
            hasRestoreProjectionAnchor: restoreProjectionAnchorEventID != nil,
            isTimelineAtNewestWindow: isTimelineAtNewestWindow,
            hasPendingEvents: !pendingEventBuffer.isEmpty
        ))
        guard await applyRuntimeEventApplicationPlan(
            applicationPlan,
            account: account,
            backwardRequestKey: nil,
            lifecycle: lifecycle
        ) else { return }
        scheduleLinkPreviewResolution()
        feedSyncCoordinator.record(event, relayURL: relayURL, subscriptionID: subscriptionID)
    }

    private func handleBackwardEvent(relayURL: String, subscriptionID: String, event: NostrEvent) async {
        guard let account,
              let lifecycle = lifecycleCoordinator.token(for: account.pubkey)
        else { return }
        let accountID = account.pubkey
        let requestKey = backwardRequestRegistry.key(for: subscriptionID)
        let request = requestKey.flatMap { backwardRequestRegistry.request(for: $0) }
        let projectionReason: HomeTimelineFeedProjectionReason? = if request?.isOlderPage == true {
            .older
        } else if request?.gap != nil {
            .gap
        } else {
            nil
        }
        let isTimelineBackfill = projectionReason != nil
        let sourceRequestID = feedSyncCoordinator.requestID(
            relayURL: relayURL,
            subscriptionID: subscriptionID
        )
        let activeRequestContext = feedSyncCoordinator.context(
            relayURL: relayURL,
            subscriptionID: subscriptionID
        )
        let requestContext = request?.feedContext

        let projectedIngestResult: HomeTimelineProjectedEventIngestResult
        do {
            if isTimelineBackfill {
                ensureHomeFeedDefinition(account: account)
            }
            // 配信可否はbackward request registryで判定する。provenance用requestStartedは
            // 最初のEVENT到着時点でまだqueue内に残っている場合がある。
            projectedIngestResult = try await eventIngestor.ingestBackward(
                HomeTimelineBackwardEventIngestRequest(
                    event: event,
                    relayURL: relayURL,
                    activeFeedContext: activeHomeFeedRuntimeContext(),
                    requestContext: requestContext,
                    activeRequestContext: activeRequestContext,
                    projectionReason: projectionReason,
                    sourceRequestID: sourceRequestID
                )
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
        guard lifecycleCoordinator.isCurrent(lifecycle),
              self.account?.pubkey == accountID
        else { return }
        let applicationPlan = runtimeEventApplicationPlanner.planBackward(.init(
            event: event,
            embeddedEvent: projectedIngestResult.eventResult.embeddedEvent,
            projectsIntoCurrentFeed: projectedIngestResult.projectsIntoCurrentFeed,
            isTimelineBackfill: isTimelineBackfill
        ))
        guard await applyRuntimeEventApplicationPlan(
            applicationPlan,
            account: account,
            backwardRequestKey: requestKey,
            lifecycle: lifecycle
        ) else { return }
        scheduleLinkPreviewResolution()
        feedSyncCoordinator.record(event, relayURL: relayURL, subscriptionID: subscriptionID)
    }

    private func applyRuntimeEventApplicationPlan(
        _ plan: HomeTimelineRuntimeEventApplicationPlan,
        account: NostrAccount,
        backwardRequestKey: String?,
        lifecycle: HomeTimelineLifecycleToken
    ) async -> Bool {
        guard isCurrentRuntimeEventApplication(lifecycle) else { return false }
        if plan.invalidatesListEntries {
            invalidateListEntries()
        }
        if let metadataEvent = plan.metadataEvent {
            let effectiveMetadataEvent = rememberLatestMetadataEvent(metadataEvent)
            resolveNIP05IfNeeded(for: effectiveMetadataEvent)
        }
        if let eventID = plan.backwardTimelineEventID,
           let backwardRequestKey {
            backwardRequestRegistry.recordTimelineEvent(eventID, for: backwardRequestKey)
        }
        if let eventID = plan.sourceEventIDToFinish {
            dependencyCoordinator.finishSourceEvent(eventID: eventID)
        }
        if let dependencyEvent = plan.dependencyEvent {
            await enqueueBackwardDependencies(for: dependencyEvent)
            guard isCurrentRuntimeEventApplication(lifecycle) else { return false }
        }
        if let embeddedDependencyEvent = plan.embeddedDependencyEvent {
            await enqueueBackwardDependencies(for: embeddedDependencyEvent)
            guard isCurrentRuntimeEventApplication(lifecycle) else { return false }
        }
        if let deletion = plan.deletion {
            let deletedAnchor = removeEventsDeletedFromCurrentProjection(by: deletion.event)
            _ = reloadProjectionWindow(account: account, around: deletedAnchor)
            switch deletion.materialization {
            case .scheduled(let allowsRealtimeFollow):
                scheduleMaterializeEntries(allowsRealtimeFollow: allowsRealtimeFollow)
            case .immediate:
                materializeEntries()
            }
        }
        if let projectionUpdate = plan.projectionUpdate {
            switch projectionUpdate {
            case .reloadNewestAndSchedule(let allowsRealtimeFollow):
                materializationScheduler.requestNewestProjectionReload()
                scheduleMaterializeEntries(allowsRealtimeFollow: allowsRealtimeFollow)
            case .bufferPendingEvent(let eventID):
                bufferPendingNewEvent(eventID)
            }
        }
        if let schedule = plan.materializationSchedule {
            switch schedule {
            case .standard:
                scheduleMaterializeEntries()
            case .deferredDependencies:
                scheduleMaterializeEntries(
                    delayNanoseconds: materializationScheduler.defaultDelayNanoseconds * 2
                )
            }
        }
        return isCurrentRuntimeEventApplication(lifecycle)
    }

    private func isCurrentRuntimeEventApplication(
        _ lifecycle: HomeTimelineLifecycleToken
    ) -> Bool {
        lifecycleCoordinator.isCurrent(lifecycle) && account?.pubkey == lifecycle.accountID
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
        guard relayRuntime != nil,
              !resolvedRelays.isEmpty,
              let accountID = account?.pubkey,
              let lifecycle = lifecycleCoordinator.token(for: accountID)
        else { return }
        let result = await dependencyCoordinator.enqueueDependencies(
            for: event,
            liveMetadataEvents: metadataEvents,
            liveNoteEventIDs: Set(noteEvents.map(\.id)),
            availableRelayURLs: resolvedRelays
        )
        guard lifecycleCoordinator.isCurrent(lifecycle),
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
        dependencyCoordinator.scheduleSourcePacketInstall { [weak self] message in
            guard let self else { return }
            recordRuntimeSyncEvent(
                relayURL: resolvedRelays.first ?? "runtime",
                kind: .partialFailure,
                subscriptionID: nil,
                message: "backward enqueue failed: \(message)"
            )
        }
    }

    private func handleBackwardCompletion(_ completion: NostrBackwardREQCompletion) {
        guard let request = backwardRequestRegistry.remove(groupID: completion.groupID) else {
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

        let output = await gapReconciler.reconcile(
            newerEvent: newerEvent,
            olderEvent: olderEvent,
            context: context,
            relays: Array(resolvedRelays.prefix(4)),
            inMemoryEvents: noteEvents
        )
        guard lifecycleCoordinator.isCurrent(lifecycle),
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
        guard let registration = feedSyncCoordinator.registration(for: attempt.packet)
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
            try feedSyncCoordinator.beginRequest(attempt, registration: registration)
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
            profileResolutionStates: dependencyCoordinator.profileResolutionStates,
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

    private func bufferPendingNewEvent(_ eventID: String) {
        pendingEventBuffer.insert(eventID: eventID) { [weak self] count in
            self?.setUnmaterializedNewCount(count)
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
            profileResolutionStates: dependencyCoordinator.profileResolutionStates,
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
                state: dependencyCoordinator.profileResolutionStates[pubkey] ?? .unknown
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
            profileResolutionState: dependencyCoordinator.profileResolutionStates[pubkey] ?? .unknown
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
        listContentRevision = listProjectionCache.invalidate()
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
