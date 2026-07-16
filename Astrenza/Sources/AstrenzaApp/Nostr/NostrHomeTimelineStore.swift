import Foundation
import AstrenzaCore

@MainActor
final class NostrHomeTimelineStore {
    typealias Phase = NostrHomeTimelinePhase

    private let viewportCoordinator: HomeStoreViewportCoordinator
    private let eventStore: NostrEventStore?
    private let runtimeCoordinator: HomeStoreRuntimeCoordinator
    private let queryStoreCoordinator: HomeStoreQueryCoordinator
    private let projectionCoordinator: HomeStoreProjectionCoordinator
    private let applicationCoordinator: HomeStoreApplicationCoordinator
    private let lifecycleCoordinator: HomeStoreLifecycleCoordinator
    private let featureActionCoordinator: HomeStoreFeatureActionCoordinator
    private let syncCoordinator: HomeStoreSyncCoordinator
    private let stateCoordinator: HomeStoreStateCoordinator
    private let presentationCoordinator: HomeStorePresentationCoordinator
    private let statusCoordinator: HomeStoreStatusCoordinator

    var presentationEventStore: NostrEventStore? {
        eventStore
    }

    init(
        timelineLoader: NostrHomeTimelineLoader = NostrHomeTimelineLoader(),
        eventStore: NostrEventStore? = try? NostrEventStore.applicationSupport(appDirectory: "Astrenza"),
        relayRuntime: NostrRelayRuntime? = nil,
        linkPreviewResolver: NostrLinkPreviewResolver? = nil,
        viewportStateRestorer: any HomeTimelineViewportStateRestoring =
            TimelineRestoreStore(),
        outboxPublisher: NostrOutboxRelayPublisher = NostrOutboxRelayPublisher(),
        localMutationPersistence: (any HomeTimelineLocalMutationPersisting)? = nil,
        syncPolicy: NostrSyncPolicy = .default(networkType: .unknown, lowPowerMode: false),
        syncPolicySettingsStore: NostrSyncPolicySettingsStore = .shared
    ) {
        let components = HomeTimelineStoreAssembly.assemble(
            HomeTimelineStoreAssemblyInput(
                timelineLoader: timelineLoader,
                eventStore: eventStore,
                relayRuntime: relayRuntime,
                linkPreviewResolver: linkPreviewResolver,
                viewportStateRestorer: viewportStateRestorer,
                outboxPublisher: outboxPublisher,
                localMutationPersistence: localMutationPersistence,
                initialSyncPolicy: syncPolicy,
                syncPolicySettingsStore: syncPolicySettingsStore
            )
        )
        let composition = HomeStoreComposition.make(
            components: components
        )
        self.viewportCoordinator = composition.viewport
        self.eventStore = components.eventStore
        self.runtimeCoordinator = composition.runtime
        self.queryStoreCoordinator = composition.query
        self.projectionCoordinator = composition.projection
        self.applicationCoordinator = composition.application
        self.lifecycleCoordinator = composition.lifecycle
        self.featureActionCoordinator = composition.featureActions
        self.syncCoordinator = composition.sync
        self.stateCoordinator = composition.state
        self.presentationCoordinator = composition.presentation
        self.statusCoordinator = composition.status
    }
}

extension NostrHomeTimelineStore {
    func start(account: NostrAccount) {
        lifecycleCoordinator.start(account: account)
    }

    func setRestoreProjectionAnchor(_ anchorEventID: String?) {
        viewportCoordinator.setRestoreProjectionAnchor(anchorEventID)
    }

    func restoredViewportState(accountID: String, timelineKey: String) -> TimelineViewportState? {
        projectionCoordinator.restoredViewportState(
            accountID: accountID,
            timelineKey: timelineKey
        )
    }

    func refresh() {
        viewportCoordinator.refresh()
    }

    func setTimelineAtNewestWindow(_ isAtNewestWindow: Bool) {
        viewportCoordinator.setTimelineAtNewestWindow(isAtNewestWindow)
    }

    func setTimelineScrollActive(_ isActive: Bool) {
        viewportCoordinator.setTimelineScrollActive(isActive)
    }

    func dismissUnreadBadge() {
        viewportCoordinator.dismissUnreadBadge()
    }

    func markMaterializedPostsRead(visiblePostIDs: [TimelinePost.ID]) {
        viewportCoordinator.markMaterializedPostsRead(
            visiblePostIDs: visiblePostIDs
        )
    }

    func markNewestMaterializedWindowRead() {
        viewportCoordinator.markNewestMaterializedWindowRead()
    }

    @discardableResult
    func applyPendingNewEvents() async -> Bool {
        viewportCoordinator.applyPendingNewEvents()
    }

    func loadOlder() {
        viewportCoordinator.loadOlder()
    }

    func backfillGap(_ gap: TimelineGap, direction: TimelineGapFillDirection) async -> Bool {
        await featureActionCoordinator.backfillGap(
            gap,
            direction: direction
        )
    }

    func enqueuePublish(_ input: NostrPublishInput, signer: any NostrEventSigning) async throws {
        try await featureActionCoordinator.enqueuePublish(
            input,
            signer: signer
        )
    }

    func muteAuthor(authorPubkey: String) {
        featureActionCoordinator.muteAuthor(authorPubkey: authorPubkey)
    }

    func bookmark(eventID: String) {
        featureActionCoordinator.bookmark(eventID: eventID)
    }

    func cancel() {
        lifecycleCoordinator.cancel()
    }
}

extension NostrHomeTimelineStore {
    func suspendTimelineFilters() {
        featureActionCoordinator.suspendFilters()
    }

    func resumeTimelineFilters() {
        featureActionCoordinator.resumeFilters()
    }
}

extension NostrHomeTimelineStore {
    func isBookmarked(_ post: TimelinePost) -> Bool {
        queryStoreCoordinator.isBookmarked(post)
    }

    func listEntries(limit: Int = 500) -> [TimelineFeedEntry] {
        queryStoreCoordinator.listEntries(limit: limit)
    }

    func post(eventID: String) -> TimelinePost? {
        queryStoreCoordinator.post(eventID: eventID)
    }

    func profile(pubkey: String, isCurrentUser: Bool = false) -> UserProfile {
        queryStoreCoordinator.profile(
            pubkey: pubkey,
            isCurrentUser: isCurrentUser
        )
    }

    func profileProjection(
        pubkey: String,
        isCurrentUser: Bool = false,
        postsLimit: Int = 80
    ) -> HomeTimelineProfileProjection {
        queryStoreCoordinator.profileProjection(
            pubkey: pubkey,
            isCurrentUser: isCurrentUser,
            postsLimit: postsLimit
        )
    }

    func profilePosts(pubkey: String, limit: Int = 80) -> [TimelinePost] {
        queryStoreCoordinator.profilePosts(
            pubkey: pubkey,
            limit: limit
        )
    }

    func replyAncestors(
        for post: TimelinePost,
        limit: Int = 8
    ) -> [TimelinePost] {
        queryStoreCoordinator.replyAncestors(
            for: post,
            limit: limit
        )
    }

    func replies(for post: TimelinePost, limit: Int = 24) -> [TimelinePost] {
        queryStoreCoordinator.replies(
            for: post,
            limit: limit
        )
    }
}

extension NostrHomeTimelineStore {
    var account: NostrAccount? {
        stateCoordinator.account
    }

    var currentSyncPolicy: NostrSyncPolicy {
        stateCoordinator.currentSyncPolicy
    }

    var unmaterializedNewCount: Int {
        viewportCoordinator.pendingEventCount
    }

    var listContentRevision: Int {
        queryStoreCoordinator.listContentRevision
    }

    var relayStatusRevision: Int {
        statusCoordinator.relayStatusRevision
    }

    var relayRuntimeStates: [String: NostrRelayConnectionState] {
        statusCoordinator.relayRuntimeStates
    }

    var relayStatusCounts: (connected: Int, planned: Int) {
        statusCoordinator.relayStatusCounts
    }

    var activityStatus: NostrTimelineActivityStatus? {
        statusCoordinator.activityStatus
    }

    var isRelayProcessing: Bool {
        statusCoordinator.isRelayProcessing
    }

    var phase: Phase {
        statusCoordinator.phase
    }

    var isRefreshing: Bool {
        statusCoordinator.isRefreshing
    }

    var isLoadingOlder: Bool {
        statusCoordinator.isLoadingOlder
    }

    var isHomeTimelineRealtime: Bool {
        statusCoordinator.isRealtime
    }

    var resolvedRelays: [String] {
        stateCoordinator.resolvedRelays
    }

    var followedPubkeys: [String] {
        stateCoordinator.followedPubkeys
    }

    var hasMoreOlder: Bool {
        stateCoordinator.hasMoreOlder
    }

    var entries: [TimelineFeedEntry] {
        presentationCoordinator.entries
    }

    var filterStatus: TimelineFilterStatus {
        presentationCoordinator.filterStatus
    }

    var materializedUnreadCount: Int {
        presentationCoordinator.materializedUnreadCount
    }

    var visibleUnreadBadgeCount: Int {
        presentationCoordinator.visibleUnreadBadgeCount
    }

    var resolvedContentRevision: Int {
        presentationCoordinator.resolvedContentRevision
    }

    var profileMetadataRevision: Int {
        presentationCoordinator.profileMetadataRevision
    }

    var realtimeFollowSourceRevision: Int? {
        presentationCoordinator.realtimeFollowSourceRevision
    }
}

#if DEBUG
extension NostrHomeTimelineStore {
    var testingDependencies: HomeStoreTestingDependencies {
        HomeStoreTestingDependencies(
            application: applicationCoordinator,
            runtime: runtimeCoordinator,
            projection: projectionCoordinator,
            sync: syncCoordinator,
            state: stateCoordinator,
            viewport: viewportCoordinator,
            presentation: presentationCoordinator
        )
    }
}
#endif
