#if DEBUG
import AstrenzaCore

@MainActor
struct HomeStoreTestingDependencies {
    let application: HomeStoreApplicationCoordinator
    let runtime: HomeStoreRuntimeCoordinator
    let projection: HomeStoreProjectionCoordinator
    let sync: HomeStoreSyncCoordinator
    let state: HomeStoreStateCoordinator
    let viewport: HomeStoreViewportCoordinator
    let presentation: HomeStorePresentationCoordinator
}

@MainActor
extension NostrHomeTimelineStore {
    func testingApplyActivityTransition(
        _ transition: HomeTimelineActivityTransition
    ) {
        testingDependencies.application.applyActivityTransition(transition)
    }

    func testingApplyContentSnapshot(_ snapshot: HomeTimelineContentSnapshot) {
        testingDependencies.application.applyContentSnapshot(snapshot)
    }

    func testingApplyRelayStatusSnapshot(
        _ snapshot: HomeTimelineRelayStatusSnapshot
    ) {
        testingDependencies.application.applyRelayStatusSnapshot(snapshot)
    }

    func testingApplyRelayStatusTransition(
        _ transition: HomeTimelineRelayStatusTransition?
    ) {
        testingDependencies.application.applyRelayStatusTransition(transition)
    }

    func testingApplyListProjectionInvalidation(
        _ invalidation: HomeTimelineListProjectionInvalidation
    ) {
        testingDependencies.application.applyListProjectionInvalidation(
            invalidation
        )
    }

    func testingApplyPendingEventCountPublication(
        _ publication: HomeTimelinePendingEventCountPublication
    ) {
        testingDependencies.application.applyPendingEventCountPublication(
            publication
        )
    }

    func testingApplyAccountContextTransition(
        _ transition: HomeTimelineAccountContextTransition
    ) {
        testingDependencies.application.applyAccountContextTransition(
            transition
        )
    }

    func testingSetHomeTimelineRealtime(_ isRealtime: Bool) {
        testingDependencies.sync.setRealtimeForTesting(isRealtime)
    }

    func testingSetMaterializedPostIDs(_ ids: [TimelinePost.ID]) {
        let testEntries: [TimelineFeedEntry] = ids.map { id in
            .post(TimelinePost(
                id: id,
                author: .unresolved(
                    pubkey: String(repeating: "a", count: 64)
                ),
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
        testingDependencies.presentation.replaceEntriesForTesting(
            testEntries,
            renderFingerprint: testEntries.map { $0.id.hashValue }
        )
    }

    func testingSetReadBoundary(postID: TimelinePost.ID) {
        testingDependencies.presentation.setReadBoundaryForTesting(
            postID: postID
        )
    }

    func testingSetUnmaterializedNewEventIDs(_ ids: Set<String>) {
        testingDependencies.viewport.replacePendingEventIDs(ids)
    }

    func testingMergedProjectionWindow(
        _ current: NostrFeedWindow,
        with loaded: NostrFeedWindow,
        centeredOn anchorEventID: String
    ) -> NostrFeedWindow {
        testingDependencies.projection.mergedWindow(
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
        let dependencies = testingDependencies
        dependencies.runtime.ensureLifecycle(accountID: account.pubkey)
        dependencies.application.applyAccountContextTransition(.activate(
            account,
            syncPolicy: currentSyncPolicy
        ))
        dependencies.application.applyContentSnapshot(
            dependencies.state.replaceFollowedPubkeys(sourceAuthors)
        )
        await dependencies.projection.activateStoredProjection(
            definition: definition,
            sourceAuthors: sourceAuthors
        )
    }

    func testingRegisterOlderFeedRequest(
        packet: NostrREQPacket,
        definition: NostrFeedDefinitionRecord,
        anchorEventID: String?
    ) {
        testingDependencies.sync.registerOlderFeedRequest(
            packet: packet,
            definition: definition,
            anchorEventID: anchorEventID
        )
    }

    func testingRegisterForwardFeedRequest(
        packet: NostrREQPacket,
        definition: NostrFeedDefinitionRecord
    ) {
        testingDependencies.sync.registerForwardFeedRequest(
            packet: packet,
            definition: definition
        )
    }

    func testingRegisterGapFeedRequest(
        packet: NostrREQPacket,
        definition: NostrFeedDefinitionRecord,
        newerEventID: String,
        olderEventID: String,
        direction: TimelineGapFillDirection
    ) {
        testingDependencies.sync.registerGapFeedRequest(
            packet: packet,
            definition: definition,
            newerEventID: newerEventID,
            olderEventID: olderEventID,
            direction: direction
        )
    }

    func testingHandleFeedSyncRequestStarted(
        _ attempt: NostrRelayRequestAttempt
    ) async {
        await testingDependencies.runtime.handlePacket(
            .requestStarted(attempt),
            isActive: true
        )
    }

    func testingHandleBackwardEvent(
        relayURL: String,
        subscriptionID: String,
        event: NostrEvent
    ) async {
        await testingDependencies.application.handleRuntimeEvent(
            relayURL: relayURL,
            subscriptionID: subscriptionID,
            event: event
        )
    }

    func testingHandleHomeForwardEvent(
        relayURL: String,
        subscriptionID: String,
        event: NostrEvent
    ) async {
        await testingDependencies.application.handleRuntimeEvent(
            relayURL: relayURL,
            subscriptionID: subscriptionID,
            event: event
        )
    }

    func testingHandleBackwardCompletion(
        _ completion: NostrBackwardREQCompletion
    ) {
        testingDependencies.application.handleBackwardCompletion(completion)
    }

    func testingEnqueueBackwardDependencies(for event: NostrEvent) async {
        await testingDependencies.runtime.enqueueDependencies(for: event)
    }

    @discardableResult
    func testingEnqueueBackwardDependencies(
        _ dependencies: NostrEventDependencies,
        availableRelayURLs: [String]
    ) -> Bool {
        testingDependencies.state.enqueueSourceDependencies(
            dependencies,
            availableRelayURLs: availableRelayURLs,
            now: 0
        )
    }

    func testingFlushBackwardDependencies() {
        testingDependencies.state.flushSourcePacketInstall(
            onFailure: { _ in }
        )
    }

    var testingPendingBackwardRequestCount: Int {
        testingDependencies.sync.backwardRequestCount +
            testingDependencies.state.pendingDependencyRequestCount
    }

    var testingHasPendingDependencyWork: Bool {
        testingDependencies.state.hasPendingDependencyWork
    }

    var testingActiveFeedSyncRequestCount: Int {
        testingDependencies.sync.activeRequestCount
    }

    var testingActiveFeedSyncContextCount: Int {
        testingDependencies.sync.activeContextCount
    }
}
#endif
