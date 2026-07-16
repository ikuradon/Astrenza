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
    private let dataInteractionWorkflow: HomeTimelineDataInteractionWorkflow
    private let runtimeCoordinator: HomeStoreRuntimeCoordinator
    private let gapBackfillInteractionWorkflow:
        HomeGapBackfillInteractionWorkflow
    private let filterInteractionWorkflow:
        HomeTimelineFilterInteractionWorkflow
    private let queryStoreCoordinator: HomeStoreQueryCoordinator
    private let projectionCoordinator: HomeStoreProjectionCoordinator
    private let contextCoordinator: HomeStoreContextCoordinator
    private let lifecycleCoordinator: HomeStoreLifecycleCoordinator
    private let presentationCoordinator: HomeStorePresentationCoordinator
    private let statusCoordinator: HomeStoreStatusCoordinator
    private let syncInteractionWorkflow: HomeTimelineSyncInteractionWorkflow
    private let stateInteractionWorkflow: HomeTimelineStateInteractionWorkflow
    private let publishInteractionWorkflow:
        HomeTimelinePublishInteractionWorkflow?
    private let localMutationInteractionWorkflow:
        HomeLocalMutationInteractionWorkflow?
    private lazy var restoreProjectionAnchorWorkflow =
        HomeRestoreProjectionAnchorWorkflow(target: self)
    private var publishedStateObservation: AnyCancellable?

    var relayStatusEventStore: NostrEventStore? {
        eventStore
    }

    func applyContentSnapshot(_ snapshot: HomeTimelineContentSnapshot) {
        publishedStateCoordinator.applyContentSnapshot(snapshot)
    }

    func applyActivityTransition(
        _ transition: HomeTimelineActivityTransition
    ) {
        statusCoordinator.applyActivityTransition(transition)
    }

    func applyActivityIntent(
        _ intent: HomeTimelineActivityIntent
    ) {
        statusCoordinator.applyActivityIntent(intent)
    }

    func applyPresentationTransition(
        _ transition: HomeTimelinePresentationTransition
    ) {
        presentationCoordinator.applyPresentationTransition(transition)
    }

    func applyRelayStatusSnapshot(_ snapshot: HomeTimelineRelayStatusSnapshot) {
        statusCoordinator.applyRelayStatusSnapshot(snapshot)
    }

    func applyRelayStatusTransition(
        _ transition: HomeTimelineRelayStatusTransition?
    ) {
        if let relayURL = statusCoordinator.applyRelayStatusTransition(
            transition
        ) {
            invalidateHomeTimelineRealtime(relayURL: relayURL)
        }
    }

    func publishRelayStatusChange() {
        statusCoordinator.publishRelayStatusChange()
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
        self.dataInteractionWorkflow = components.dataInteractionWorkflow
        self.runtimeCoordinator = composition.runtime
        self.gapBackfillInteractionWorkflow =
            components.gapBackfillInteractionWorkflow
        self.filterInteractionWorkflow =
            components.filterInteractionWorkflow
        self.queryStoreCoordinator = composition.query
        self.projectionCoordinator = composition.projection
        self.contextCoordinator = composition.context
        self.lifecycleCoordinator = composition.lifecycle
        self.presentationCoordinator = composition.presentation
        self.statusCoordinator = composition.status
        self.syncInteractionWorkflow = components.syncInteractionWorkflow
        self.stateInteractionWorkflow = components.stateInteractionWorkflow
        self.publishInteractionWorkflow = components.publishInteractionWorkflow
        self.localMutationInteractionWorkflow =
            components.localMutationInteractionWorkflow
        bindContextComposition()
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
        await gapBackfillInteractionWorkflow.backfill(
            gap: gap,
            direction: direction,
            context: contextCoordinator.gapBackfillContext()
        )
    }

    func enqueuePublish(_ input: NostrPublishInput, signer: any NostrEventSigning) async throws {
        guard let account, let publishInteractionWorkflow else { return }
        try await publishInteractionWorkflow.enqueue(
            input: input,
            signer: signer,
            context: contextCoordinator.publishContext(
                account: account
            )
        )
    }

    func muteAuthor(of post: TimelinePost) {
        localMutationInteractionWorkflow?.perform(
            .muteAuthor(authorPubkey: post.author.pubkey),
            context: contextCoordinator.localMutationContext()
        )
    }

    func bookmark(_ post: TimelinePost) {
        localMutationInteractionWorkflow?.perform(
            .bookmark(eventID: post.id),
            context: contextCoordinator.localMutationContext()
        )
    }

    func cancel() {
        lifecycleCoordinator.cancel()
    }

    func refreshLatest(
        account: NostrAccount,
        lifecycle: HomeTimelineLifecycleToken
    ) async {
        await lifecycleCoordinator.refreshLatest(
            account: account,
            lifecycle: lifecycle
        )
    }

    func loadOlder(
        account: NostrAccount,
        lifecycle: HomeTimelineLifecycleToken
    ) async {
        await lifecycleCoordinator.loadOlder(
            account: account,
            lifecycle: lifecycle
        )
    }

    func replaceRuntimeBootstrapState(
        _ state: NostrHomeTimelineState
    ) {
        replaceTimelineState(
            dataInteractionWorkflow.runtimeBootstrapState(from: state)
        )
    }

    func replaceFollowedPubkeys(_ pubkeys: [String]) {
        applyContentSnapshot(
            dataInteractionWorkflow.perform(.replaceFollowedPubkeys(pubkeys))
        )
    }

    func timelineEvent(id: String) -> NostrEvent? {
        queryStoreCoordinator.timelineEvent(id: id)
    }

    func persistDatabase(account: NostrAccount) async {
        await stateInteractionWorkflow.persistSnapshot(
            dataInteractionWorkflow.persistenceSnapshotInput(
                accountID: account.pubkey
            ),
            context: contextCoordinator.stateContext()
        )
    }

    func scheduleHomeFeedReadStateSave() {
        contextCoordinator.scheduleReadBoundarySave()
    }

    func prepareHomeFeedDefinition(account: NostrAccount) {
        projectionCoordinator.prepareDefinition(account: account)
    }

    func reloadNewestProjectionWindow(account: NostrAccount) {
        projectionCoordinator.reloadNewestProjection(account: account)
    }

    func reloadProjectionWindow(
        account: NostrAccount,
        around anchorEventID: String?,
        mergingWithCurrentWindow: Bool = false,
        onCompletion: HomeTimelineMaterializationCoordinating
            .ProjectionReloadHandler? = nil
    ) {
        projectionCoordinator.reloadProjection(
            account: account,
            around: anchorEventID,
            mergingWithCurrentWindow: mergingWithCurrentWindow,
            onCompletion: onCompletion
        )
    }

    func requestNewestProjectionReload() {
        presentationCoordinator.requestNewestProjectionReload()
    }

    func applyRestoreProjectionAnchorIfPossible(account: NostrAccount) {
        restoreProjectionAnchorWorkflow.restoreIfPossible(account: account)
    }

    func startRuntimeSession() {
        runtimeCoordinator.startSession()
    }

    func installProvisionalRuntimeBootstrapIfNeeded(account: NostrAccount) {
        guard let provisionalRelays = runtimeCoordinator
            .provisionalBootstrapRelayURLs(account: account)
        else { return }
        applyContentSnapshot(
            dataInteractionWorkflow.perform(
                .installProvisionalRelays(provisionalRelays)
            )
        )
        statusCoordinator.refreshRelayStatusCounts()
    }

    func configureRelayRuntime(account: NostrAccount, forceInstall: Bool = false) async {
        await runtimeCoordinator.configure(
            account: account,
            forceInstall: forceInstall
        )
    }

}

extension NostrHomeTimelineStore {

    func handleRuntimeEvent(
        relayURL: String,
        subscriptionID: String,
        event: NostrEvent
    ) async {
        await runtimeCoordinator.handleEvent(
            relayURL: relayURL,
            subscriptionID: subscriptionID,
            event: event
        )
    }

    private func enqueueBackwardDependencies(for event: NostrEvent) async {
        await runtimeCoordinator.enqueueDependencies(for: event)
    }

    func handleBackwardCompletion(_ completion: NostrBackwardREQCompletion) {
        runtimeCoordinator.handleBackwardCompletion(completion)
    }

    func scheduleLinkPreviewResolution() {
        runtimeCoordinator.scheduleLinkPreviewResolution()
    }

    func materializeEntries(
        allowsRealtimeFollow: Bool = false,
        onTransition: HomeTimelineMaterializationCoordinating
            .TransitionHandler? = nil
    ) {
        presentationCoordinator.materializeEntries(
            allowsRealtimeFollow: allowsRealtimeFollow,
            onTransition: onTransition
        )
    }

    func scheduleMaterializeEntries(
        delayNanoseconds: UInt64? = nil,
        allowsRealtimeFollow: Bool? = nil
    ) {
        presentationCoordinator.scheduleMaterialization(
            delayNanoseconds: delayNanoseconds,
            allowsRealtimeFollow: allowsRealtimeFollow
        )
    }

    func replaceTimelineState(_ state: NostrHomeTimelineState) {
        stateInteractionWorkflow.replace(
            state,
            accountID: account?.pubkey,
            context: contextCoordinator.stateContext()
        )
    }

}

extension NostrHomeTimelineStore {
    func suspendTimelineFilters() {
        filterInteractionWorkflow.perform(
            .suspend,
            context: contextCoordinator.filterContext()
        )
    }

    func resumeTimelineFilters() {
        filterInteractionWorkflow.perform(
            .resume,
            context: contextCoordinator.filterContext()
        )
    }
}

private extension NostrHomeTimelineStore {
    func bindContextComposition() {
        queryStoreCoordinator.bind(target: self)
        contextCoordinator.bind(
            applications: HomeStoreContextApplications.make(target: self),
            readBoundaryTarget: self
        )
        observePublishedState()
    }

    func observePublishedState() {
        publishedStateObservation =
            publishedStateCoordinator.objectWillChange.sink { [weak self] in
                self?.publishedStateRevision &+= 1
            }
    }

    func invalidateHomeTimelineRealtime(
        for key: RuntimeSubscriptionKey
    ) {
        syncInteractionWorkflow.invalidateForwardSubscription(
            key,
            context: contextCoordinator.syncContext()
        )
    }

    func invalidateHomeTimelineRealtime(relayURL: String) {
        syncInteractionWorkflow.invalidateForwardSubscriptions(
            relayURL: relayURL,
            context: contextCoordinator.syncContext()
        )
    }
}

extension NostrHomeTimelineStore {
    var syncPolicy: NostrSyncPolicy {
        publishedStateCoordinator.accountContext.syncPolicy
    }

    var currentReadBoundaryPostID: String? {
        presentationCoordinator.currentReadBoundaryPostID
    }

    var restoreProjectionAnchorEventID: String? {
        viewportCoordinator.restoreProjectionAnchorEventID
    }

    var isTimelineAtNewestWindow: Bool {
        viewportCoordinator.isTimelineAtNewestWindow
    }
}

extension NostrHomeTimelineStore {
    func resetHomeTimelineRealtime(
        expecting runtimeKeys: Set<RuntimeSubscriptionKey> = []
    ) {
        syncInteractionWorkflow.prepareForwardSubscriptions(
            runtimeKeys,
            context: contextCoordinator.syncContext()
        )
    }

    func applyProjectionViewportTransition(
        _ transition: HomeTimelineProjectionViewportTransition
    ) {
        viewportCoordinator.applyProjectionViewportTransition(transition)
    }

    func applyRestoredReadBoundary(postID: String) {
        presentationCoordinator.restoreReadBoundary(postID: postID)
    }

    func applyAccountContextTransition(
        _ transition: HomeTimelineAccountContextTransition
    ) {
        publishedStateCoordinator.applyAccountContextTransition(transition)
    }

    @discardableResult
    func clearPendingNewEvents() -> Bool {
        viewportCoordinator.clearPendingNewEvents()
    }

    func resetRuntimeSetup() {
        runtimeCoordinator.resetSetup()
    }

    func clearPendingProjectionReload() {
        presentationCoordinator.clearNewestProjectionReload()
    }

    func applyPendingEventCountPublication(
        _ publication: HomeTimelinePendingEventCountPublication
    ) {
        publishedStateCoordinator.applyPendingEventCountPublication(
            publication
        )
    }

    func invalidateListEntries() {
        applyListProjectionInvalidation(
            queryStoreCoordinator.invalidateListEntries()
        )
    }

    func applyListProjectionInvalidation(
        _ invalidation: HomeTimelineListProjectionInvalidation
    ) {
        publishedStateCoordinator.applyListProjectionInvalidation(invalidation)
    }
}

extension NostrHomeTimelineStore: HomeStoreQueryTarget {
    var queryPreferredEvents: [NostrEvent] {
        dataInteractionWorkflow.contentState.noteEvents
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
    func testingApplyActivityTransition(_ transition: HomeTimelineActivityTransition) {
        applyActivityTransition(transition)
    }

    func testingApplyContentSnapshot(_ snapshot: HomeTimelineContentSnapshot) {
        applyContentSnapshot(snapshot)
    }

    func testingApplyRelayStatusSnapshot(_ snapshot: HomeTimelineRelayStatusSnapshot) {
        applyRelayStatusSnapshot(snapshot)
    }

    func testingApplyRelayStatusTransition(_ transition: HomeTimelineRelayStatusTransition?) {
        applyRelayStatusTransition(transition)
    }

    func testingApplyListProjectionInvalidation(
        _ invalidation: HomeTimelineListProjectionInvalidation
    ) {
        applyListProjectionInvalidation(invalidation)
    }

    func testingApplyPendingEventCountPublication(
        _ publication: HomeTimelinePendingEventCountPublication
    ) {
        applyPendingEventCountPublication(publication)
    }

    func testingApplyAccountContextTransition(
        _ transition: HomeTimelineAccountContextTransition
    ) {
        applyAccountContextTransition(transition)
    }

    func testingSetHomeTimelineRealtime(_ isRealtime: Bool) {
        contextCoordinator.syncContext().effects.apply(
            .setRealtime(isRealtime)
        )
    }

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
        presentationCoordinator.replaceEntriesForTesting(
            testEntries,
            renderFingerprint: testEntries.map { $0.id.hashValue }
        )
    }

    func testingSetReadBoundary(postID: TimelinePost.ID) {
        presentationCoordinator.setReadBoundaryForTesting(postID: postID)
    }

    func testingSetUnmaterializedNewEventIDs(_ ids: Set<String>) {
        viewportCoordinator.replacePendingEventIDs(ids)
    }

    func testingMergedProjectionWindow(
        _ current: NostrFeedWindow,
        with loaded: NostrFeedWindow,
        centeredOn anchorEventID: String
    ) -> NostrFeedWindow {
        projectionCoordinator.mergedWindow(
            current,
            with: loaded,
            centeredOn: anchorEventID
        )
    }

    func testingActivateHomeFeed(
        account: NostrAccount,
        definition: NostrFeedDefinitionRecord,
        sourceAuthors: [String]
    ) async {
        runtimeCoordinator.ensureLifecycle(accountID: account.pubkey)
        applyAccountContextTransition(.activate(
            account,
            syncPolicy: syncPolicy
        ))
        applyContentSnapshot(
            dataInteractionWorkflow.perform(
                .replaceFollowedPubkeys(sourceAuthors)
            )
        )
        await projectionCoordinator.activateStoredProjection(
            definition: definition,
            sourceAuthors: sourceAuthors
        )
    }

    func testingRegisterOlderFeedRequest(
        packet: NostrREQPacket,
        definition: NostrFeedDefinitionRecord,
        anchorEventID: String?
    ) {
        syncInteractionWorkflow.registerOlderPage(
            groupID: packet.groupID,
            context: HomeFeedRuntimeContext(definition: definition),
            anchorEventID: anchorEventID
        )
    }

    func testingRegisterForwardFeedRequest(
        packet: NostrREQPacket,
        definition: NostrFeedDefinitionRecord
    ) {
        syncInteractionWorkflow.registerForwardContext(
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
        syncInteractionWorkflow.registerGap(
            groupID: packet.groupID,
            context: HomeFeedRuntimeContext(definition: definition),
            newerEventID: newerEventID,
            olderEventID: olderEventID,
            direction: direction
        )
    }

    func testingHandleFeedSyncRequestStarted(_ attempt: NostrRelayRequestAttempt) async {
        await runtimeCoordinator.handlePacket(
            .requestStarted(attempt),
            isActive: true
        )
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
        dataInteractionWorkflow.enqueueSourceDependencies(
            dependencies,
            availableRelayURLs: availableRelayURLs,
            now: 0
        )
    }

    func testingFlushBackwardDependencies() {
        dataInteractionWorkflow.flushSourcePacketInstall(onFailure: { _ in })
    }

    var testingPendingBackwardRequestCount: Int {
        syncInteractionWorkflow.backwardRequestState.requestCount +
            dataInteractionWorkflow.dependencyWorkState.pendingSourceRequestCount
    }

    var testingHasPendingDependencyWork: Bool {
        dataInteractionWorkflow.dependencyWorkState.hasPendingWork
    }

    var testingActiveFeedSyncRequestCount: Int {
        syncInteractionWorkflow.activeRequestCount
    }

    var testingActiveFeedSyncContextCount: Int {
        syncInteractionWorkflow.activeContextCount
    }
}
#endif
