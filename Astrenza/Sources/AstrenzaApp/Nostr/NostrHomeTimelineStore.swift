import Foundation
import AstrenzaCore
import Combine
import SwiftUI

@MainActor
final class NostrHomeTimelineStore: ObservableObject {
    typealias Phase = NostrHomeTimelinePhase

    @Published private var publishedStateRevision = 0

    private let publishedStateCoordinator:
        HomeTimelinePublishedStateCoordinator
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
    private var publishedStateObservation: AnyCancellable?

    var relayStatusEventStore: NostrEventStore? {
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
        self.publishedStateCoordinator =
            components.publishedStateCoordinator
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
        observePublishedState()
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

    func refreshLatest() async {
        await viewportCoordinator.refreshLatest()
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

    func muteAuthor(of post: TimelinePost) {
        featureActionCoordinator.muteAuthor(
            authorPubkey: post.author.pubkey
        )
    }

    func bookmark(_ post: TimelinePost) {
        featureActionCoordinator.bookmark(eventID: post.id)
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

private extension NostrHomeTimelineStore {
    func observePublishedState() {
        publishedStateObservation =
            publishedStateCoordinator.objectWillChange.sink { [weak self] in
                self?.publishedStateRevision &+= 1
            }
    }
}

extension NostrHomeTimelineStore {
    var syncPolicy: NostrSyncPolicy {
        publishedStateCoordinator.accountContext.syncPolicy
    }

    var restoreProjectionAnchorEventID: String? {
        viewportCoordinator.restoreProjectionAnchorEventID
    }

    var isTimelineAtNewestWindow: Bool {
        viewportCoordinator.isTimelineAtNewestWindow
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
        publishedStateCoordinator.accountContext.account
    }

    var currentSyncPolicy: NostrSyncPolicy {
        publishedStateCoordinator.accountContext.syncPolicy
    }

    var unmaterializedNewCount: Int {
        publishedStateCoordinator.pendingEvents.count
    }

    var listContentRevision: Int {
        publishedStateCoordinator.listProjection.revision
    }

    var relayStatusRevision: Int {
        statusCoordinator.relayStatusRevision
    }

    var relayRuntimeStates: [String: NostrRelayConnectionState] {
        statusCoordinator.relayStatusSnapshot.runtimeStates
    }

    var relayStatusCounts: (connected: Int, planned: Int) {
        let snapshot = statusCoordinator.relayStatusSnapshot
        return (
            connected: snapshot.connectedRelayCount,
            planned: snapshot.plannedRelayCount
        )
    }

    var activityStatus: NostrTimelineActivityStatus? {
        statusCoordinator.activityStatus()
    }

    var isRelayProcessing: Bool {
        activityStatus != nil
    }

    var phase: Phase {
        statusCoordinator.activitySnapshot.phase
    }

    var isRefreshing: Bool {
        statusCoordinator.activitySnapshot.isRefreshing
    }

    var isLoadingOlder: Bool {
        statusCoordinator.activitySnapshot.isLoadingOlder
    }

    var isHomeTimelineRealtime: Bool {
        statusCoordinator.activitySnapshot.isRealtime
    }

    var resolvedRelays: [String] {
        publishedStateCoordinator.content.resolvedRelays
    }

    var followedPubkeys: [String] {
        publishedStateCoordinator.content.followedPubkeys
    }

    var hasMoreOlder: Bool {
        publishedStateCoordinator.content.hasMoreOlder
    }

    var entries: [TimelineFeedEntry] {
        publishedStateCoordinator.presentation.entries
    }

    var filterStatus: TimelineFilterStatus {
        publishedStateCoordinator.presentation.filterStatus
    }

    var materializedUnreadCount: Int {
        publishedStateCoordinator.presentation.materializedUnreadCount
    }

    var visibleUnreadBadgeCount: Int {
        publishedStateCoordinator.presentation.visibleUnreadBadgeCount
    }

    var resolvedContentRevision: Int {
        publishedStateCoordinator.presentation.resolvedContentRevision
    }

    var realtimeFollowSourceRevision: Int? {
        publishedStateCoordinator.presentation.realtimeFollowSourceRevision
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
