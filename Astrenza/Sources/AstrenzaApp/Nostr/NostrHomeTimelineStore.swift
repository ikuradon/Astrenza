import AstrenzaCore
import Foundation

@MainActor
final class NostrHomeTimelineStore {
    typealias Phase = NostrHomeTimelinePhase

    private let composition: HomeStoreComposition
    private let blossomServerResolver: NostrBlossomServerResolver?
    private let profilePageResolver: NostrProfilePageResolver?
    private let composeEmojiResolver: NostrComposeEmojiResolver?

    var presentationEventStore: NostrEventStore? {
        composition.presentation.presentationEventStore
    }

    init(
        composition: HomeStoreComposition,
        blossomServerResolver: NostrBlossomServerResolver? = nil,
        profilePageResolver: NostrProfilePageResolver? = nil,
        composeEmojiResolver: NostrComposeEmojiResolver? = nil
    ) {
        self.composition = composition
        self.blossomServerResolver = blossomServerResolver
        self.profilePageResolver = profilePageResolver
        self.composeEmojiResolver = composeEmojiResolver
    }
}

extension NostrHomeTimelineStore {
    func start(account: NostrAccount) {
        composition.lifecycle.start(account: account)
    }

    func setRestoreProjectionAnchor(_ anchorEventID: String?) {
        composition.viewport.setRestoreProjectionAnchor(anchorEventID)
    }

    func restoredViewportState(accountID: String, timelineKey: String) -> TimelineViewportState? {
        composition.projection.restoredViewportState(
            accountID: accountID,
            timelineKey: timelineKey
        )
    }

    func refresh() {
        composition.viewport.refresh()
    }

    func applySyncPolicy(_ policy: NostrSyncPolicy, accountID: String?) {
        composition.syncPolicy.apply(policy, accountID: accountID)
    }

    func setTimelineAtNewestWindow(_ isAtNewestWindow: Bool) {
        composition.viewport.setTimelineAtNewestWindow(isAtNewestWindow)
    }

    func setTimelineScrollActive(_ isActive: Bool) {
        composition.viewport.setTimelineScrollActive(isActive)
    }

    func dismissUnreadBadge() {
        composition.viewport.dismissUnreadBadge()
    }

    func markMaterializedPostsRead(visiblePostIDs: [TimelinePost.ID]) {
        composition.viewport.markMaterializedPostsRead(
            visiblePostIDs: visiblePostIDs
        )
    }

    func markNewestMaterializedWindowRead() {
        composition.viewport.markNewestMaterializedWindowRead()
    }

    @discardableResult
    func applyPendingNewEvents() async -> Bool {
        await composition.viewport.applyPendingNewEvents()
    }

    func loadOlder() {
        composition.viewport.loadOlder()
    }

    func backfillGap(_ gap: TimelineGap, direction: TimelineGapFillDirection) async -> Bool {
        await composition.featureActions.backfillGap(
            gap,
            direction: direction
        )
    }

    func enqueuePublish(
        _ input: NostrPublishInput,
        taggedUserReadRelays: [String] = [],
        signer: any NostrEventSigning,
        reportProgress: @escaping @MainActor @Sendable (
            HomeTimelinePublishStage
        ) -> Void = { _ in }
    ) async throws -> Bool {
        try await composition.featureActions.enqueuePublish(
            input,
            taggedUserReadRelays: taggedUserReadRelays,
            signer: signer,
            reportProgress: reportProgress
        )
    }

    func resolveBlossomServers(accountID: String) async -> [URL] {
        var seen = Set<String>()
        let relayURLs = (
            resolvedRelays
                + (account?.discoveryRelays ?? [])
                + NostrHomeTimelineLoader.defaultBootstrapRelays
        ).filter { seen.insert($0).inserted }
        return await blossomServerResolver?.resolve(
            accountID: accountID,
            relayURLs: relayURLs
        ) ?? []
    }

    func resolveProfilePage(pubkey: String) async {
        guard let profilePageResolver else { return }
        let eventStore = presentationEventStore
        let relayList = NostrRelayList.parse(from:
            try? eventStore?.latestReplaceableEvent(
                pubkey: pubkey,
                kind: 10_002
            )
        )
        let observedRelays = (try? eventStore?.observedRelayURLsByAuthor(
            authors: [pubkey],
            limitPerAuthor: 4
        )[pubkey]) ?? []
        let relayURLs = relayList.writeRelays
            + observedRelays
            + resolvedRelays
            + (account?.discoveryRelays ?? [])
            + NostrHomeTimelineLoader.defaultBootstrapRelays
        if await profilePageResolver.resolve(
            pubkey: pubkey,
            relayURLs: relayURLs
        ) {
            composition.application.publishProfileMetadataChange()
        }
    }

    func resolveComposeEmojiCatalog(accountID: String) async {
        guard let composeEmojiResolver else { return }
        let eventStore = presentationEventStore
        let relayList = NostrRelayList.parse(from:
            try? eventStore?.latestReplaceableEvent(
                pubkey: accountID,
                kind: 10_002
            )
        )
        let observedRelays = (try? eventStore?.observedRelayURLsByAuthor(
            authors: [accountID],
            limitPerAuthor: 4
        )[accountID]) ?? []
        let relayURLs = relayList.writeRelays
            + observedRelays
            + resolvedRelays
            + (account?.discoveryRelays ?? [])
            + NostrHomeTimelineLoader.defaultBootstrapRelays
        _ = await composeEmojiResolver.resolve(
            accountID: accountID,
            relayURLs: relayURLs
        )
    }

    func muteAuthor(authorPubkey: String) {
        composition.featureActions.muteAuthor(authorPubkey: authorPubkey)
    }

    func bookmark(eventID: String) {
        composition.featureActions.bookmark(eventID: eventID)
    }

    func cancel() {
        composition.lifecycle.cancel()
    }
}

extension NostrHomeTimelineStore {
    func suspendTimelineFilters() {
        composition.featureActions.suspendFilters()
    }

    func resumeTimelineFilters() {
        composition.featureActions.resumeFilters()
    }
}

extension NostrHomeTimelineStore {
    func isBookmarked(_ post: TimelinePost) -> Bool {
        composition.query.isBookmarked(post)
    }

    func listEntries(limit: Int = 500) -> [TimelineFeedEntry] {
        composition.query.listEntries(limit: limit)
    }

    func post(eventID: String) -> TimelinePost? {
        composition.query.post(eventID: eventID)
    }

    func profile(pubkey: String, isCurrentUser: Bool = false) -> UserProfile {
        composition.query.profile(
            pubkey: pubkey,
            isCurrentUser: isCurrentUser
        )
    }

    func profileProjection(
        pubkey: String,
        isCurrentUser: Bool = false,
        postsLimit: Int = 80
    ) -> HomeTimelineProfileProjection {
        composition.query.profileProjection(
            pubkey: pubkey,
            isCurrentUser: isCurrentUser,
            postsLimit: postsLimit
        )
    }

    func profilePosts(pubkey: String, limit: Int = 80) -> [TimelinePost] {
        composition.query.profilePosts(
            pubkey: pubkey,
            limit: limit
        )
    }

    func replyAncestors(
        for post: TimelinePost,
        limit: Int = 8
    ) -> [TimelinePost] {
        composition.query.replyAncestors(
            for: post,
            limit: limit
        )
    }

    func replies(for post: TimelinePost, limit: Int = 24) -> [TimelinePost] {
        composition.query.replies(
            for: post,
            limit: limit
        )
    }
}

extension NostrHomeTimelineStore {
    var account: NostrAccount? {
        composition.state.account
    }

    var currentSyncPolicy: NostrSyncPolicy {
        composition.state.currentSyncPolicy
    }

    var unmaterializedNewCount: Int {
        composition.viewport.pendingEventCount
    }

    var listContentRevision: Int {
        composition.query.listContentRevision
    }

    var relayStatusRevision: Int {
        composition.status.relayStatusRevision
    }

    var relayRuntimeStates: [String: NostrRelayConnectionState] {
        composition.status.relayRuntimeStates
    }

    var relayStatusCounts: (connected: Int, planned: Int) {
        composition.status.relayStatusCounts
    }

    var activityStatus: NostrTimelineActivityStatus? {
        composition.status.activityStatus
    }

    var isRelayProcessing: Bool {
        composition.status.isRelayProcessing
    }

    var phase: Phase {
        composition.status.phase
    }

    var isRefreshing: Bool {
        composition.status.isRefreshing
    }

    var isLoadingOlder: Bool {
        composition.status.isLoadingOlder
    }

    var isHomeTimelineRealtime: Bool {
        composition.status.isRealtime
    }

    var initialHomeTimelineSyncState: HomeTimelineInitialSyncState {
        composition.status.initialSyncState
    }

    var resolvedRelays: [String] {
        composition.state.resolvedRelays
    }

    var followedPubkeys: [String] {
        composition.state.followedPubkeys
    }

    var hasMoreOlder: Bool {
        composition.state.hasMoreOlder
    }

    var entries: [TimelineFeedEntry] {
        composition.presentation.entries
    }

    var filterStatus: TimelineFilterStatus {
        composition.presentation.filterStatus
    }

    var materializedUnreadCount: Int {
        composition.presentation.materializedUnreadCount
    }

    var visibleUnreadBadgeCount: Int {
        composition.presentation.visibleUnreadBadgeCount
    }

    var unreadCountAnchorPostID: TimelinePost.ID? {
        composition.presentation.currentReadBoundaryPostID
    }

    var resolvedContentRevision: Int {
        composition.presentation.resolvedContentRevision
    }

    var profileMetadataRevision: Int {
        composition.presentation.profileMetadataRevision
    }

    var realtimeFollowSourceRevision: Int? {
        composition.presentation.realtimeFollowSourceRevision
    }
}

#if DEBUG
extension NostrHomeTimelineStore {
    var testingDependencies: HomeStoreTestingDependencies {
        HomeStoreTestingDependencies(
            application: composition.application,
            runtime: composition.runtime,
            projection: composition.projection,
            sync: composition.sync,
            state: composition.state,
            viewport: composition.viewport,
            presentation: composition.presentation
        )
    }
}
#endif
