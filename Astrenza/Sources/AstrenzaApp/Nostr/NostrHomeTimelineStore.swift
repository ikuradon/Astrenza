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
    private let remoteLoadCoordinator: HomeTimelineRemoteLoadCoordinator
    private let loadInteractionWorkflow: HomeTimelineLoadInteractionWorkflow
    private let viewportInteractionWorkflow:
        HomeTimelineViewportInteractionWorkflow
    private let eventStore: NostrEventStore?
    private let dataInteractionWorkflow: HomeTimelineDataInteractionWorkflow
    private let runtimeInteractionWorkflow:
        HomeTimelineRuntimeInteractionWorkflow
    private let stateContextProjector =
        HomeTimelineStateContextProjector()
    private let storeApplicationDispatcher =
        HomeTimelineStoreApplicationDispatcher()
    private let accountApplicationDispatcher =
        HomeTimelineAccountApplicationDispatcher()
    private let viewportApplicationDispatcher =
        HomeTimelineViewportDispatcher()
    private let gapBackfillInteractionWorkflow:
        HomeGapBackfillInteractionWorkflow
    private let backwardInteractionWorkflow:
        HomeTimelineBackwardInteractionWorkflow
    private let filterInteractionWorkflow:
        HomeTimelineFilterInteractionWorkflow
    private let queryInteractionWorkflow:
        HomeTimelineQueryInteractionWorkflow
    private let activityInteractionWorkflow:
        HomeTimelineActivityInteractionWorkflow
    private let presentationWorkflow: HomeTimelinePresentationWorkflow
    private let linkPreviewInteractionWorkflow:
        HomeLinkPreviewInteractionWorkflow
    private let projectionInteractionWorkflow:
        HomeProjectionInteractionWorkflow
    private let readBoundaryInteractionWorkflow:
        HomeReadBoundaryInteractionWorkflow
    private let syncInteractionWorkflow: HomeTimelineSyncInteractionWorkflow
    private let accountStartInteractionWorkflow:
        HomeAccountStartInteractionWorkflow
    private let accountResetInteractionWorkflow:
        HomeAccountResetInteractionWorkflow
    private let stateInteractionWorkflow: HomeTimelineStateInteractionWorkflow
    private let publishInteractionWorkflow:
        HomeTimelinePublishInteractionWorkflow?
    private let localMutationInteractionWorkflow:
        HomeLocalMutationInteractionWorkflow?
    private let relayRuntime: NostrRelayRuntime?
    private lazy var storeApplicationEffects =
        makeStoreApplicationEffects()
    private lazy var accountApplicationEffects =
        makeAccountApplicationEffects()
    private lazy var viewportApplicationEffects =
        makeViewportApplicationEffects()
    private lazy var featureInteractionContextFactory =
        makeFeatureInteractionContextFactory()
    private lazy var accountContextFactory =
        makeAccountContextFactory()
    private lazy var viewportContextFactory =
        makeViewportContextFactory()
    private lazy var loadContextFactory =
        makeLoadContextFactory()
    private lazy var stateContextFactory =
        makeStateContextFactory()
    private lazy var runtimeApplicationEffects =
        stateInteractionWorkflow.runtimeApplicationEffects(
            context: stateContextFactory.context()
        )
    private lazy var runtimeContextFactory =
        makeRuntimeContextFactory()
    private var publishedStateObservation: AnyCancellable?
    private var projectionViewportState = HomeTimelineProjectionViewportState()

    var relayStatusEventStore: NostrEventStore? {
        eventStore
    }

    private var contentState: HomeTimelineContentSnapshot {
        dataInteractionWorkflow.contentState
    }

    private var noteEvents: [NostrEvent] {
        contentState.noteEvents
    }

    private var metadataEvents: [NostrEvent] {
        contentState.metadataEvents
    }

    private var relayListEvent: NostrEvent? {
        contentState.relayListEvent
    }

    private var contactListEvent: NostrEvent? {
        contentState.contactListEvent
    }

    private var timelineQuerySnapshot: HomeTimelineQueryStoreSnapshot {
        HomeTimelineQueryStoreSnapshot(
            accountID: account?.pubkey,
            fallbackEntries: entries,
            resolvedRelayCount: resolvedRelays.count,
            syncPolicy: syncPolicy,
            homeContentRevision: resolvedContentRevision,
            listContentRevision: listContentRevision
        )
    }

    private func applyContentSnapshot(_ snapshot: HomeTimelineContentSnapshot) {
        publishedStateCoordinator.applyContentSnapshot(snapshot)
    }

    private func applyActivityTransition(
        _ transition: HomeTimelineActivityTransition
    ) {
        publishedStateCoordinator.applyActivityTransition(transition)
    }

    private func applyActivityIntent(
        _ intent: HomeTimelineActivityIntent
    ) {
        applyActivityTransition(
            activityInteractionWorkflow.perform(intent)
        )
    }

    private func applyPresentationTransition(
        _ transition: HomeTimelinePresentationTransition
    ) {
        publishedStateCoordinator.applyPresentationTransition(transition)
    }

    private func updateRelayStatusCounts() {
        applyRelayStatusSnapshot(
            syncInteractionWorkflow.relayStatusSnapshot(
                resolvedRelays: resolvedRelays
            )
        )
    }

    private func applyRelayStatusSnapshot(_ snapshot: HomeTimelineRelayStatusSnapshot) {
        publishedStateCoordinator.applyRelayStatusSnapshot(snapshot)
    }

    private func applyRelayStatusTransition(
        _ transition: HomeTimelineRelayStatusTransition?
    ) {
        if let relayURL = publishedStateCoordinator.applyRelayStatusTransition(
            transition
        ) {
            invalidateHomeTimelineRealtime(relayURL: relayURL)
        }
    }

    private func publishRelayStatusChange() {
        publishedStateCoordinator.publishRelayStatusChange()
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
        self.publishedStateCoordinator =
            components.publishedStateCoordinator
        self.remoteLoadCoordinator = components.remoteLoadCoordinator
        self.loadInteractionWorkflow = components.loadInteractionWorkflow
        self.viewportInteractionWorkflow = components.viewportInteractionWorkflow
        self.eventStore = components.eventStore
        self.dataInteractionWorkflow = components.dataInteractionWorkflow
        self.runtimeInteractionWorkflow = components.runtimeInteractionWorkflow
        self.gapBackfillInteractionWorkflow =
            components.gapBackfillInteractionWorkflow
        self.backwardInteractionWorkflow = components.backwardInteractionWorkflow
        self.filterInteractionWorkflow =
            components.filterInteractionWorkflow
        self.queryInteractionWorkflow = components.queryInteractionWorkflow
        self.activityInteractionWorkflow =
            components.activityInteractionWorkflow
        self.presentationWorkflow = components.presentationWorkflow
        self.linkPreviewInteractionWorkflow =
            components.linkPreviewInteractionWorkflow
        self.projectionInteractionWorkflow =
            components.projectionInteractionWorkflow
        self.readBoundaryInteractionWorkflow =
            components.readBoundaryInteractionWorkflow
        self.syncInteractionWorkflow = components.syncInteractionWorkflow
        self.accountStartInteractionWorkflow =
            components.accountStartInteractionWorkflow
        self.accountResetInteractionWorkflow =
            components.accountResetInteractionWorkflow
        self.stateInteractionWorkflow = components.stateInteractionWorkflow
        self.publishInteractionWorkflow = components.publishInteractionWorkflow
        self.localMutationInteractionWorkflow =
            components.localMutationInteractionWorkflow
        self.relayRuntime = components.relayRuntime
        self.publishedStateObservation =
            publishedStateCoordinator.objectWillChange.sink { [weak self] in
                self?.publishedStateRevision &+= 1
            }
    }

    func start(account: NostrAccount) {
        accountStartInteractionWorkflow.start(
            account: account,
            context: accountContextFactory.startContext()
        )
    }

    func setRestoreProjectionAnchor(_ anchorEventID: String?) {
        viewportInteractionWorkflow.setRestoreProjectionAnchor(
            anchorEventID,
            context: viewportContextFactory.context()
        )
    }

    func restoredViewportState(accountID: String, timelineKey: String) -> TimelineViewportState? {
        projectionInteractionWorkflow.restoredViewportState(
            accountID: accountID,
            timelineKey: timelineKey
        )
    }

    func refresh() {
        viewportInteractionWorkflow.refresh(
            viewportContextFactory.context()
        )
    }

    func refreshLatest() async {
        await viewportInteractionWorkflow.refreshLatest(
            viewportContextFactory.context()
        )
    }

    func setTimelineAtNewestWindow(_ isAtNewestWindow: Bool) {
        viewportInteractionWorkflow.setTimelineAtNewestWindow(
            isAtNewestWindow,
            context: viewportContextFactory.context()
        )
    }

    func setTimelineScrollActive(_ isActive: Bool) {
        viewportInteractionWorkflow.setTimelineScrollActive(
            isActive,
            context: viewportContextFactory.context()
        )
    }

    func dismissUnreadBadge() {
        viewportInteractionWorkflow.dismissUnreadBadge(
            viewportContextFactory.context()
        )
    }

    func markMaterializedPostsRead(visiblePostIDs: [TimelinePost.ID]) {
        viewportInteractionWorkflow.markMaterializedPostsRead(
            visiblePostIDs: visiblePostIDs,
            context: viewportContextFactory.context()
        )
    }

    func markNewestMaterializedWindowRead() {
        viewportInteractionWorkflow.markNewestMaterializedWindowRead(
            viewportContextFactory.context()
        )
    }

    @discardableResult
    func applyPendingNewEvents() async -> Bool {
        viewportInteractionWorkflow.applyPendingNewEvents(
            viewportContextFactory.context()
        )
    }

    func loadOlder() {
        viewportInteractionWorkflow.loadOlder(
            viewportContextFactory.context()
        )
    }

    private func dispatchViewportApplication(
        _ application: HomeTimelineViewportApplication
    ) {
        viewportApplicationDispatcher.apply(
            application,
            effects: viewportApplicationEffects
        )
    }

    private func performViewportApplication(
        _ load: HomeTimelineViewportInteractionLoad
    ) async {
        await viewportApplicationDispatcher.perform(
            load,
            effects: viewportApplicationEffects
        )
    }

    private func makeViewportApplicationEffects(
    ) -> HomeTimelineViewportApplicationEffects {
        HomeTimelineViewportApplicationEffects(
            applyProjectionViewportTransition: { [weak self] transition in
                self?.applyProjectionViewportTransition(transition)
            },
            reloadNewestProjectionWindow: { [weak self] account in
                self?.reloadNewestProjectionWindow(account: account)
            },
            materializeEntries: { [weak self] allowsRealtimeFollow in
                self?.materializeEntries(
                    allowsRealtimeFollow: allowsRealtimeFollow
                )
            },
            applyRestoreProjectionAnchor: { [weak self] account in
                self?.applyRestoreProjectionAnchorIfPossible(account: account)
            },
            applyPresentationTransition: { [weak self] transition in
                self?.applyPresentationTransition(transition)
            },
            scheduleReadStateSave: { [weak self] in
                self?.scheduleHomeFeedReadStateSave()
            },
            applyPendingEventCountPublication: { [weak self] publication in
                self?.applyPendingEventCountPublication(publication)
            },
            clearPendingProjectionReload: { [weak self] in
                self?.presentationWorkflow.clearNewestProjectionReload()
            },
            scheduleLinkPreviewResolution: { [weak self] in
                self?.scheduleLinkPreviewResolution()
            },
            refreshLatest: { [weak self] account, lifecycle in
                await self?.refreshLatest(
                    account: account,
                    lifecycle: lifecycle
                )
            },
            loadOlder: { [weak self] account, lifecycle in
                await self?.loadOlder(
                    account: account,
                    lifecycle: lifecycle
                )
            }
        )
    }

    func backfillGap(_ gap: TimelineGap, direction: TimelineGapFillDirection) async -> Bool {
        await gapBackfillInteractionWorkflow.backfill(
            gap: gap,
            direction: direction,
            context: featureInteractionContextFactory.gapBackfillContext()
        )
    }

    func enqueuePublish(_ input: NostrPublishInput, signer: any NostrEventSigning) async throws {
        guard let account, let publishInteractionWorkflow else { return }
        try await publishInteractionWorkflow.enqueue(
            input: input,
            signer: signer,
            context: featureInteractionContextFactory.publishContext(
                account: account
            )
        )
    }

    func muteAuthor(of post: TimelinePost) {
        localMutationInteractionWorkflow?.perform(
            .muteAuthor(authorPubkey: post.author.pubkey),
            context: featureInteractionContextFactory.localMutationContext()
        )
    }

    func bookmark(_ post: TimelinePost) {
        localMutationInteractionWorkflow?.perform(
            .bookmark(eventID: post.id),
            context: featureInteractionContextFactory.localMutationContext()
        )
    }

    func cancel() {
        projectionInteractionWorkflow.cancelMaterialization()
        accountResetInteractionWorkflow.reset(
            context: accountContextFactory.resetContext()
        )
    }

    private func load(
        account: NostrAccount,
        lifecycle: HomeTimelineLifecycleToken
    ) async {
        await loadInteractionWorkflow.loadInitial(
            account: account,
            lifecycle: lifecycle,
            context: loadContextFactory.context()
        )
    }

    private func refreshLatest(
        account: NostrAccount,
        lifecycle: HomeTimelineLifecycleToken
    ) async {
        await loadInteractionWorkflow.refreshLatest(
            account: account,
            lifecycle: lifecycle,
            context: loadContextFactory.context()
        )
    }

    private func loadOlder(
        account: NostrAccount,
        lifecycle: HomeTimelineLifecycleToken
    ) async {
        await loadInteractionWorkflow.loadOlder(
            account: account,
            lifecycle: lifecycle,
            context: loadContextFactory.context()
        )
    }

    private func makeLoadApplicationEffects(
    ) -> HomeTimelineLoadApplicationEffects {
        HomeTimelineLoadApplicationEffects(
            applyActivityTransition: { [weak self] transition in
                self?.applyActivityTransition(transition)
            },
            applyRelayStatusTransition: { [weak self] transition in
                self?.applyRelayStatusTransition(transition)
            },
            installProvisionalRuntimeBootstrap: { [weak self] account in
                self?.installProvisionalRuntimeBootstrapIfNeeded(
                    account: account
                )
            },
            restartAccount: { [weak self] account in
                self?.start(account: account)
            },
            replaceTimelineState: { [weak self] state in
                self?.replaceTimelineState(state)
            },
            replaceRuntimeBootstrapState: { [weak self] state in
                self?.replaceRuntimeBootstrapState(state)
            },
            replaceFollowedPubkeys: { [weak self] pubkeys in
                self?.replaceFollowedPubkeys(pubkeys)
            },
            materializeEntries: { [weak self] in
                self?.materializeEntries()
            },
            setPhase: { [weak self] phase in
                self?.applyActivityIntent(.setPhase(phase))
            },
            configureRuntime: { [weak self] account in
                await self?.configureRelayRuntime(account: account)
            },
            persistDatabase: { [weak self] account in
                await self?.persistDatabase(account: account)
            }
        )
    }

    private func replaceRuntimeBootstrapState(
        _ state: NostrHomeTimelineState
    ) {
        replaceTimelineState(
            dataInteractionWorkflow.runtimeBootstrapState(from: state)
        )
    }

    private func replaceFollowedPubkeys(_ pubkeys: [String]) {
        applyContentSnapshot(
            dataInteractionWorkflow.perform(.replaceFollowedPubkeys(pubkeys))
        )
    }

    private func timelineEvent(id: String) -> NostrEvent? {
        queryInteractionWorkflow.event(
            id: id,
            preferring: noteEvents
        )
    }

    @discardableResult
    private func restoreCachedSnapshot(account: NostrAccount) async -> Bool {
        await stateInteractionWorkflow.restoreCachedState(
            accountID: account.pubkey,
            context: stateContextFactory.context()
        )
    }

    private func persistDatabase(account: NostrAccount) async {
        let dependencies = dataInteractionWorkflow.dependencyResolutionState
        await stateInteractionWorkflow.persistSnapshot(
            HomeTimelineSnapshotInput(
                accountID: account.pubkey,
                relays: resolvedRelays,
                followedPubkeys: followedPubkeys,
                noteEvents: noteEvents,
                metadataEvents: metadataEvents,
                relayListEvent: relayListEvent,
                contactListEvent: contactListEvent,
                nip05Resolutions: dependencies.nip05Resolutions,
                hasMoreOlder: hasMoreOlder
            ),
            context: stateContextFactory.context()
        )
    }

    private func dispatchStoreApplication(
        _ application: HomeTimelineStateInteractionApplication
    ) {
        storeApplicationDispatcher.apply(
            application,
            effects: storeApplicationEffects
        )
    }

    private func isCurrentHomeFeedContext(_ context: HomeFeedRuntimeContext?) -> Bool {
        projectionInteractionWorkflow.isCurrent(
            context,
            accountID: account?.pubkey
        )
    }

    private func restoreHomeFeedReadState(account: NostrAccount) async {
        let positions = entries.compactMap(\.post).map { post in
            HomeTimelineReadPosition(postID: post.id, createdAt: post.createdAt)
        }
        let boundaryID = await readBoundaryInteractionWorkflow
            .restoredReadBoundaryPostID(
                accountID: account.pubkey,
                positions: positions
            )
        guard !Task.isCancelled,
              self.account?.pubkey == account.pubkey,
              let boundaryID
        else { return }
        applyPresentationTransition(
            presentationWorkflow.restoreReadBoundary(postID: boundaryID)
        )
    }

    private func scheduleHomeFeedReadStateSave() {
        guard let account else { return }
        readBoundaryInteractionWorkflow.scheduleReadBoundarySave(
            accountID: account.pubkey,
            boundaryEvent: currentReadBoundaryEvent()
        )
    }

    private func homeFeedReadBoundaryWrite() -> HomeTimelineReadBoundaryWrite? {
        guard let account else { return nil }
        return readBoundaryInteractionWorkflow.readBoundaryWrite(
            accountID: account.pubkey,
            boundaryEvent: currentReadBoundaryEvent()
        )
    }

    private func currentReadBoundaryEvent() -> NostrEvent? {
        let boundaryID = presentationWorkflow.interactionState.readBoundaryPostID
        return boundaryID.flatMap(timelineEvent(id:))
    }

    private func prepareHomeFeedDefinition(account: NostrAccount) {
        projectionInteractionWorkflow.prepareDefinition(
            account: account,
            followedPubkeys: followedPubkeys,
            liveEvents: noteEvents
        )
    }

    private func reloadNewestProjectionWindow(account: NostrAccount) {
        projectionInteractionWorkflow.reloadNewestProjection(account: account)
    }

    private func reloadProjectionWindow(
        account: NostrAccount,
        around anchorEventID: String?,
        mergingWithCurrentWindow: Bool = false,
        onCompletion: HomeTimelineMaterializationCoordinating
            .ProjectionReloadHandler? = nil
    ) {
        projectionInteractionWorkflow.reloadProjection(
            account: account,
            around: anchorEventID,
            mergingWithCurrentWindow: mergingWithCurrentWindow,
            onCompletion: onCompletion
        )
    }

    private func applyRestoreProjectionAnchorIfPossible(account: NostrAccount) {
        guard let restoreProjectionAnchorEventID else { return }
        reloadProjectionWindow(
            account: account,
            around: restoreProjectionAnchorEventID
        ) { [weak self] didReload in
            guard didReload,
                  let self,
                  self.account?.pubkey == account.pubkey,
                  self.restoreProjectionAnchorEventID ==
                    restoreProjectionAnchorEventID
            else { return }
            materializeEntries { [weak self] transition in
                guard let self else { return }
                scheduleLinkPreviewResolution()
                if !transition.snapshot.entries.isEmpty {
                    applyActivityIntent(.setPhase(.loaded))
                }
            }
        }
    }

    private func startRuntimeSession() {
        runtimeInteractionWorkflow.startSession(
            context: runtimeContextFactory.interactionContext()
        )
    }

    private func installProvisionalRuntimeBootstrapIfNeeded(account: NostrAccount) {
        guard let provisionalRelays = runtimeInteractionWorkflow
            .provisionalBootstrapRelayURLs(
                account: account,
                state: runtimeContextFactory.interactionState()
            )
        else { return }
        applyContentSnapshot(
            dataInteractionWorkflow.perform(
                .installProvisionalRelays(provisionalRelays)
            )
        )
        updateRelayStatusCounts()
    }

    private func configureRelayRuntime(account: NostrAccount, forceInstall: Bool = false) async {
        await runtimeInteractionWorkflow.configure(
            account: account,
            forceInstall: forceInstall,
            context: runtimeContextFactory.interactionContext()
        )
    }

    private func runtimeStoreSnapshot(
    ) -> HomeTimelineRuntimeStoreSnapshot {
        HomeTimelineRuntimeStoreSnapshot(
            account: account,
            resolvedRelays: resolvedRelays,
            bootstrapRelayURLs: remoteLoadCoordinator.bootstrapRelays,
            policy: syncPolicy,
            hasRelayRuntime: relayRuntime != nil,
            isTerminating:
                accountResetInteractionWorkflow.isRuntimeTerminating,
            isRuntimeActive:
                activityInteractionWorkflow.state.phase != .idle,
            isRealtime: activityInteractionWorkflow.state.isRealtime,
            hasRestoreProjectionAnchor:
                restoreProjectionAnchorEventID != nil,
            isTimelineAtNewestWindow: isTimelineAtNewestWindow,
            hasPendingEvents:
                viewportInteractionWorkflow.hasBufferedEvents
        )
    }

    private func dispatchStoreApplication(
        _ application: HomeTimelineRuntimeStoreAction
    ) {
        storeApplicationDispatcher.apply(
            application,
            effects: storeApplicationEffects
        )
    }

    private func dispatchStoreApplication(
        _ action: HomeTimelineLinkPreviewStoreAction
    ) {
        storeApplicationDispatcher.apply(
            action,
            effects: storeApplicationEffects
        )
    }

    private func dispatchStoreApplication(
        _ action: HomeTimelineFilterStoreAction
    ) {
        storeApplicationDispatcher.apply(
            action,
            effects: storeApplicationEffects
        )
    }

    private func dispatchStoreApplication(
        _ action: HomeTimelineSyncStoreAction
    ) {
        storeApplicationDispatcher.apply(
            action,
            effects: storeApplicationEffects
        )
    }

    private func dispatchStoreApplication(
        _ action: HomeTimelineLocalMutationStoreAction
    ) {
        storeApplicationDispatcher.apply(
            action,
            effects: storeApplicationEffects
        )
    }

    private func dispatchStoreApplication(
        _ action: HomeTimelineGapBackfillStoreAction
    ) {
        storeApplicationDispatcher.apply(
            action,
            effects: storeApplicationEffects
        )
    }

    private func dispatchStoreApplication(
        _ action: HomeTimelinePublishStoreAction
    ) {
        storeApplicationDispatcher.apply(
            action,
            effects: storeApplicationEffects
        )
    }

    private func dispatchStoreApplication(
        _ action: HomeTimelineBackwardStoreAction
    ) {
        storeApplicationDispatcher.apply(
            action,
            effects: storeApplicationEffects
        )
    }

    private func performStoreApplication(
        _ action: HomeTimelinePublishAsyncAction
    ) async {
        await storeApplicationDispatcher.perform(
            action,
            effects: storeApplicationEffects
        )
    }

    private func performStoreApplication(
        _ application: HomeTimelineRuntimeStoreAsyncAction
    ) async {
        await storeApplicationDispatcher.perform(
            application,
            effects: storeApplicationEffects
        )
    }

    private func makeStoreApplicationEffects(
    ) -> HomeTimelineStoreApplicationEffects {
        HomeTimelineStoreApplicationEffects(
            applyPresentationTransition: { [weak self] transition in
                self?.applyPresentationTransition(transition)
            },
            applyContentSnapshot: { [weak self] snapshot in
                self?.applyContentSnapshot(snapshot)
            },
            applyRelayStatusSnapshot: { [weak self] snapshot in
                self?.applyRelayStatusSnapshot(snapshot)
            },
            applyListProjectionInvalidation: { [weak self] invalidation in
                self?.applyListProjectionInvalidation(invalidation)
            },
            applyPendingEventCountPublication: { [weak self] publication in
                self?.applyPendingEventCountPublication(publication)
            },
            reloadProjection: {
                [weak self] account, anchorEventID, merging in
                self?.reloadProjectionWindow(
                    account: account,
                    around: anchorEventID,
                    mergingWithCurrentWindow: merging
                )
            },
            reloadNewestProjectionWindow: { [weak self] account in
                self?.reloadNewestProjectionWindow(account: account)
            },
            requestNewestProjectionReload: { [weak self] in
                self?.presentationWorkflow.requestNewestProjectionReload()
            },
            scheduleMaterialization: { [weak self] delay, realtimeFollow in
                self?.scheduleMaterializeEntries(
                    delayNanoseconds: delay,
                    allowsRealtimeFollow: realtimeFollow
                )
            },
            materializeEntries: { [weak self] in
                self?.materializeEntries()
            },
            applyRelayStatusTransition: { [weak self] transition in
                self?.applyRelayStatusTransition(transition)
            },
            setRealtime: { [weak self] isRealtime in
                self?.applyActivityIntent(.setRealtime(isRealtime))
            },
            setPhase: { [weak self] phase in
                self?.applyActivityIntent(.setPhase(phase))
            },
            handleBackwardCompletion: { [weak self] completion in
                self?.handleBackwardCompletion(completion)
            },
            invalidateListEntries: { [weak self] in
                self?.invalidateListEntries()
            },
            scheduleLinkPreviewResolution: { [weak self] in
                self?.scheduleLinkPreviewResolution()
            },
            publishRelayStatusChange: { [weak self] in
                self?.publishRelayStatusChange()
            },
            handleRuntimeEvent: { [weak self] relayURL, subscriptionID, event in
                await self?.handleRuntimeEvent(
                    relayURL: relayURL,
                    subscriptionID: subscriptionID,
                    event: event
                )
            },
            persistDatabase: { [weak self] account in
                await self?.persistDatabase(account: account)
            }
        )
    }

}

private extension NostrHomeTimelineStore {

    private func handleRuntimeEvent(relayURL: String, subscriptionID: String, event: NostrEvent) async {
        await runtimeInteractionWorkflow.handleEvent(
            relayURL: relayURL,
            subscriptionID: subscriptionID,
            event: event,
            context: runtimeContextFactory.eventContext()
        )
    }

    private func runtimeDependencyState() -> HomeTimelineRuntimeDependencyState {
        runtimeContextFactory.dependencyState()
    }

    private func stateContextProjection() -> HomeTimelineStateContextProjection {
        stateContextProjector.projection(from: stateStoreSnapshot())
    }

    private func stateStoreSnapshot() -> HomeTimelineStateStoreSnapshot {
        let dependencies = dataInteractionWorkflow.dependencyResolutionState
        return HomeTimelineStateStoreSnapshot(
            account: account,
            resolvedRelays: resolvedRelays,
            followedPubkeys: followedPubkeys,
            nip05Resolutions: dependencies.nip05Resolutions,
            hasMoreOlder: hasMoreOlder,
            hasPendingEvents: viewportInteractionWorkflow.hasBufferedEvents,
            defaultMaterializationDelayNanoseconds:
                presentationWorkflow.interactionState.defaultDelayNanoseconds
        )
    }

    private func enqueueBackwardDependencies(for event: NostrEvent) async {
        _ = await runtimeInteractionWorkflow.enqueueDependencies(
            for: event,
            state: runtimeDependencyState(),
            application: runtimeApplicationEffects
        )
    }

    private func resolveNIP05IfNeeded(for metadataEvent: NostrEvent) {
        runtimeInteractionWorkflow.resolveNIP05IfNeeded(
            for: metadataEvent,
            state: runtimeDependencyState(),
            application: runtimeApplicationEffects
        )
    }

    private func handleBackwardCompletion(_ completion: NostrBackwardREQCompletion) {
        backwardInteractionWorkflow.handle(
            completion,
            context: featureInteractionContextFactory.backwardContext()
        )
    }

    private func scheduleLinkPreviewResolution() {
        let interaction =
            featureInteractionContextFactory.linkPreviewInteraction()
        linkPreviewInteractionWorkflow.schedule(
            state: interaction.state,
            effects: interaction.effects
        )
    }

    private func databaseBackfillEvents(account: NostrAccount, current: NostrHomeTimelineState) -> [NostrEvent]? {
        queryInteractionWorkflow.olderBackfillEvents(
            HomeTimelineOlderBackfillQuery(
                accountID: account.pubkey,
                followedPubkeys: current.followedPubkeys,
                currentEvents: current.noteEvents,
                limit: 1_000
            )
        )
    }

    private func materializeEntries(
        allowsRealtimeFollow: Bool = false,
        onTransition: HomeTimelineMaterializationCoordinating
            .TransitionHandler? = nil
    ) {
        let dependencies = dataInteractionWorkflow.dependencyResolutionState
        projectionInteractionWorkflow.materialize(
            HomeTimelineMaterializationRequest(
                account: account,
                nip05Resolutions: dependencies.nip05Resolutions,
                profileResolutionStates: dependencies.profileResolutionStates,
                policy: syncPolicy,
                allowsRealtimeFollow: allowsRealtimeFollow
            )
        ) { [weak self] transition in
            guard let self else { return }
            applyPresentationTransition(transition)
            onTransition?(transition)
        }
    }

    private func scheduleMaterializeEntries(
        delayNanoseconds: UInt64? = nil,
        allowsRealtimeFollow: Bool? = nil
    ) {
        presentationWorkflow.scheduleMaterialization(
            delayNanoseconds: delayNanoseconds,
            allowsRealtimeFollow: allowsRealtimeFollow
        ) { [weak self] allowsRealtimeFollow in
            self?.materializeEntries(allowsRealtimeFollow: allowsRealtimeFollow)
        }
    }

    private func loaderState() -> NostrHomeTimelineState {
        dataInteractionWorkflow.loaderState(
            relaySyncEvents: syncInteractionWorkflow.relaySyncEvents
        )
    }

    private func replaceTimelineState(_ state: NostrHomeTimelineState) {
        stateInteractionWorkflow.replace(
            state,
            accountID: account?.pubkey,
            context: stateContextFactory.context()
        )
    }

    @discardableResult
    private func rememberLatestMetadataEvent(
        _ event: NostrEvent,
        consultEventStore: Bool = true
    ) -> NostrEvent {
        runtimeInteractionWorkflow.rememberLatestMetadataEvent(
            event,
            consultEventStore: consultEventStore,
            application: runtimeApplicationEffects
        )
    }
}

extension NostrHomeTimelineStore {
    func suspendTimelineFilters() {
        filterInteractionWorkflow.perform(
            .suspend,
            context: featureInteractionContextFactory.filterContext()
        )
    }

    func resumeTimelineFilters() {
        filterInteractionWorkflow.perform(
            .resume,
            context: featureInteractionContextFactory.filterContext()
        )
    }
}

private extension NostrHomeTimelineStore {
    func makeLoadContextFactory() -> HomeLoadContextFactory {
        HomeLoadContextFactory(
            environment: HomeLoadContextEnvironment(
                snapshot: { [weak self] in
                    guard let self else { return nil }
                    return HomeLoadContextSnapshot(
                        hasRelayRuntime: relayRuntime != nil,
                        hasTimelineEvents: !noteEvents.isEmpty
                    )
                },
                providers: HomeTimelineLoadEnvironment(
                    hasResolvedRelays: { [weak self] in
                        self?.resolvedRelays.isEmpty == false
                    },
                    currentState: { [weak self] in
                        self?.loaderState()
                    },
                    localBackfillEvents: { [weak self] account, current in
                        self?.databaseBackfillEvents(
                            account: account,
                            current: current
                        )
                    },
                    resolvedRelays: { [weak self] in
                        self?.resolvedRelays ?? []
                    }
                ),
                applications: makeLoadApplicationEffects()
            )
        )
    }

    func makeRuntimeContextFactory() -> HomeRuntimeContextFactory {
        HomeRuntimeContextFactory(
            environment: HomeRuntimeContextEnvironment(
                snapshot: { [weak self] in
                    self?.runtimeStoreSnapshot()
                },
                isCurrentFeedContext: { [weak self] context in
                    self?.isCurrentHomeFeedContext(context) == true
                },
                runtimeApplication: runtimeApplicationEffects,
                apply: { [weak self] application in
                    self?.dispatchStoreApplication(application)
                },
                perform: { [weak self] application in
                    await self?.performStoreApplication(application)
                }
            )
        )
    }

    func makeStateContextFactory() -> HomeStateContextFactory {
        HomeStateContextFactory(
            environment: HomeStateContextEnvironment(
                projection: { [weak self] in
                    self?.stateContextProjection()
                },
                apply: { [weak self] application in
                    self?.dispatchStoreApplication(application)
                }
            )
        )
    }

    func makeFeatureInteractionContextFactory(
    ) -> HomeFeatureContextFactory {
        HomeFeatureContextFactory(
            environment: HomeFeatureInteractionEnvironment(
                snapshot: { [weak self] in
                    self?.featureInteractionSnapshot()
                },
                applyFilter: { [weak self] action in
                    self?.dispatchStoreApplication(action)
                },
                applySync: { [weak self] action in
                    self?.dispatchStoreApplication(action)
                },
                applyLocalMutation: { [weak self] action in
                    self?.dispatchStoreApplication(action)
                },
                applyGapBackfill: { [weak self] action in
                    self?.dispatchStoreApplication(action)
                },
                applyPublish: { [weak self] action in
                    self?.dispatchStoreApplication(action)
                },
                performPublish: { [weak self] action in
                    guard let self else { return }
                    await performStoreApplication(action)
                },
                applyBackward: { [weak self] action in
                    self?.dispatchStoreApplication(action)
                },
                resolveBackwardDependencies: { [weak self] request in
                    guard let self else { return false }
                    return await resolveBackwardDependencies(request)
                },
                didUpdateLinkPreview: { [weak self] in
                    self?.invalidateListEntries()
                    self?.scheduleMaterializeEntries()
                },
                applyLinkPreview: { [weak self] action in
                    self?.dispatchStoreApplication(action)
                }
            )
        )
    }

    func featureInteractionSnapshot(
    ) -> HomeTimelineFeatureInteractionSnapshot {
        HomeTimelineFeatureInteractionSnapshot(
            account: account,
            resolvedRelays: resolvedRelays,
            relayListEvent: relayListEvent,
            syncPolicy: syncPolicy,
            hasRelayRuntime: relayRuntime != nil
        )
    }

    func resetHomeTimelineRealtime(
        expecting runtimeKeys: Set<RuntimeSubscriptionKey> = []
    ) {
        syncInteractionWorkflow.prepareForwardSubscriptions(
            runtimeKeys,
            context: featureInteractionContextFactory.syncContext()
        )
    }

    func invalidateHomeTimelineRealtime(
        for key: RuntimeSubscriptionKey
    ) {
        syncInteractionWorkflow.invalidateForwardSubscription(
            key,
            context: featureInteractionContextFactory.syncContext()
        )
    }

    func invalidateHomeTimelineRealtime(relayURL: String) {
        syncInteractionWorkflow.invalidateForwardSubscriptions(
            relayURL: relayURL,
            context: featureInteractionContextFactory.syncContext()
        )
    }

    func makeAccountContextFactory() -> HomeAccountContextFactory {
        HomeAccountContextFactory(
            environment: HomeAccountLifecycleEnvironment(
                snapshot: { [weak self] in
                    self?.accountLifecycleSnapshot()
                },
                readBoundaryWrite: { [weak self] in
                    self?.homeFeedReadBoundaryWrite()
                },
                restoreCachedSnapshot: { [weak self] account in
                    await self?.restoreCachedSnapshot(account: account) ?? false
                },
                restoredViewport: { [weak self] accountID in
                    self?.restoredViewportState(
                        accountID: accountID,
                        timelineKey: "home"
                    ).map {
                        HomeTimelineRestoredViewport(
                            anchorEventID: $0.anchorPostID
                        )
                    }
                },
                waitForCachedPresentation: { [weak self] in
                    await self?.projectionInteractionWorkflow
                        .waitForPendingPresentation()
                },
                restoreCachedReadState: { [weak self] account in
                    await self?.restoreHomeFeedReadState(account: account)
                },
                applyStart: { [weak self] action in
                    self?.dispatchAccountApplication(action)
                },
                load: { [weak self] request in
                    guard let self else { return }
                    await load(
                        account: request.account,
                        lifecycle: request.lifecycle
                    )
                },
                applyReset: { [weak self] action in
                    self?.dispatchAccountApplication(action)
                },
                performReset: { [weak self] action in
                    guard let self else { return }
                    await performAccountApplication(action)
                }
            )
        )
    }

    func accountLifecycleSnapshot() -> HomeAccountLifecycleSnapshot {
        HomeAccountLifecycleSnapshot(
            account: account,
            syncPolicy: syncPolicy,
            restoreProjectionAnchorEventID: restoreProjectionAnchorEventID,
            hasEntries: !entries.isEmpty,
            resolvedRelays: resolvedRelays,
            hasRelayRuntime: relayRuntime != nil
        )
    }

    func makeViewportContextFactory() -> HomeViewportContextFactory {
        HomeViewportContextFactory(
            environment: HomeViewportContextEnvironment(
                snapshot: { [weak self] in
                    self?.viewportStoreSnapshot()
                },
                effects: HomeTimelineViewportInteractionEffects(
                    apply: { [weak self] application in
                        self?.dispatchViewportApplication(application)
                    },
                    load: { [weak self] load in
                        guard let self else { return }
                        await performViewportApplication(load)
                    }
                )
            )
        )
    }

    func viewportStoreSnapshot() -> HomeViewportStoreSnapshot {
        HomeViewportStoreSnapshot(
            account: account,
            restoreProjectionAnchorEventID: restoreProjectionAnchorEventID,
            hasPendingProjectionReload:
                presentationWorkflow.interactionState
                    .hasPendingNewestProjectionReload,
            canBeginLoadingOlder:
                activityInteractionWorkflow.state.canBeginLoadingOlder,
            hasMoreOlder: hasMoreOlder,
            hasTimelineEvents: !noteEvents.isEmpty,
            hasResolvedRelays: !resolvedRelays.isEmpty,
            hasFollowedPubkeys: !followedPubkeys.isEmpty
        )
    }

    func dispatchAccountApplication(
        _ action: HomeTimelineAccountResetStoreAction
    ) {
        accountApplicationDispatcher.apply(
            action,
            effects: accountApplicationEffects
        )
    }

    func performAccountApplication(
        _ action: HomeTimelineAccountResetAsyncAction
    ) async {
        await accountApplicationDispatcher.perform(
            action,
            effects: accountApplicationEffects
        )
    }

    func dispatchAccountApplication(
        _ action: HomeTimelineAccountStartStoreAction
    ) {
        accountApplicationDispatcher.apply(
            action,
            effects: accountApplicationEffects
        )
    }

    func makeAccountApplicationEffects(
    ) -> HomeTimelineAccountApplicationEffects {
        HomeTimelineAccountApplicationEffects(
            cancelCurrentAccount: { [weak self] in
                self?.cancel()
            },
            applyAccountContextTransition: { [weak self] transition in
                self?.applyAccountContextTransition(transition)
            },
            startRuntimeSession: { [weak self] in
                self?.startRuntimeSession()
            },
            prepareHomeFeedDefinition: { [weak self] account in
                self?.prepareHomeFeedDefinition(account: account)
            },
            applyProjectionViewportTransition: { [weak self] transition in
                self?.applyProjectionViewportTransition(transition)
            },
            reloadNewestProjectionWindow: { [weak self] account in
                self?.reloadNewestProjectionWindow(account: account)
            },
            materializeEntries: { [weak self] in
                self?.materializeEntries()
            },
            applyRestoreProjectionAnchor: { [weak self] account in
                self?.applyRestoreProjectionAnchorIfPossible(account: account)
            },
            installProvisionalRuntimeBootstrap: { [weak self] account in
                self?.installProvisionalRuntimeBootstrapIfNeeded(
                    account: account
                )
            },
            setPhase: { [weak self] phase in
                self?.applyActivityIntent(.setPhase(phase))
            },
            publishRelayStatusChange: { [weak self] in
                self?.publishRelayStatusChange()
            },
            applyPresentationTransition: { [weak self] transition in
                self?.applyPresentationTransition(transition)
            },
            clearPendingEvents: { [weak self] in
                self?.clearPendingNewEvents()
            },
            applyActivityTransition: { [weak self] transition in
                self?.applyActivityTransition(transition)
            },
            invalidateListEntries: { [weak self] in
                self?.invalidateListEntries()
            },
            resetRealtimeState: { [weak self] in
                self?.resetHomeTimelineRealtime()
            },
            applyContentSnapshot: { [weak self] snapshot in
                self?.applyContentSnapshot(snapshot)
            },
            applyRelayStatusSnapshot: { [weak self] snapshot in
                self?.applyRelayStatusSnapshot(snapshot)
            },
            resetRuntimeSetup: { [weak self] in
                self?.runtimeInteractionWorkflow.resetSetup()
            },
            configureRuntime: { [weak self] account, forceInstall in
                await self?.configureRelayRuntime(
                    account: account,
                    forceInstall: forceInstall
                )
            }
        )
    }

    func resolveBackwardDependencies(
        _ request: HomeTimelineBackwardDependencyRequest
    ) async -> Bool {
        await runtimeInteractionWorkflow.enqueueDependencies(
            for: request.event,
            context: HomeTimelineRuntimeEventApplicationContext(
                account: request.account,
                lifecycle: request.lifecycle,
                hasRelayRuntime: relayRuntime != nil
            ),
            application: runtimeApplicationEffects
        )
    }

    var syncPolicy: NostrSyncPolicy {
        publishedStateCoordinator.accountContext.syncPolicy
    }

    var restoreProjectionAnchorEventID: String? {
        projectionViewportState.restoreAnchorEventID
    }

    var isTimelineAtNewestWindow: Bool {
        projectionViewportState.isAtNewestWindow
    }

    func applyProjectionViewportTransition(
        _ transition: HomeTimelineProjectionViewportTransition
    ) {
        guard let next = projectionViewportState.applying(transition) else {
            return
        }
        projectionViewportState = next
    }

    func applyAccountContextTransition(
        _ transition: HomeTimelineAccountContextTransition
    ) {
        publishedStateCoordinator.applyAccountContextTransition(transition)
    }

    @discardableResult
    func clearPendingNewEvents() -> Bool {
        viewportInteractionWorkflow.clearPendingEvents(
            viewportContextFactory.context()
        )
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
            queryInteractionWorkflow.invalidateListEntries()
        )
    }

    func applyListProjectionInvalidation(
        _ invalidation: HomeTimelineListProjectionInvalidation
    ) {
        publishedStateCoordinator.applyListProjectionInvalidation(invalidation)
    }
}

extension NostrHomeTimelineStore {
    func isBookmarked(_ post: TimelinePost) -> Bool {
        queryInteractionWorkflow.isBookmarked(
            eventID: post.id,
            accountID: account?.pubkey
        )
    }

    func listEntries(limit: Int = 500) -> [TimelineFeedEntry] {
        queryInteractionWorkflow.listEntries(
            limit: limit,
            snapshot: timelineQuerySnapshot
        )
    }

    func post(eventID: String) -> TimelinePost? {
        queryInteractionWorkflow.post(
            eventID: eventID,
            snapshot: timelineQuerySnapshot
        )
    }

    func profile(pubkey: String, isCurrentUser: Bool = false) -> UserProfile {
        queryInteractionWorkflow.profile(
            pubkey: pubkey,
            isCurrentUser: isCurrentUser,
            snapshot: timelineQuerySnapshot
        )
    }

    func profileProjection(
        pubkey: String,
        isCurrentUser: Bool = false,
        postsLimit: Int = 80
    ) -> HomeTimelineProfileProjection {
        queryInteractionWorkflow.profileProjection(
            pubkey: pubkey,
            isCurrentUser: isCurrentUser,
            postsLimit: postsLimit,
            snapshot: timelineQuerySnapshot
        )
    }

    func profilePosts(pubkey: String, limit: Int = 80) -> [TimelinePost] {
        queryInteractionWorkflow.profilePosts(
            pubkey: pubkey,
            limit: limit,
            snapshot: timelineQuerySnapshot
        )
    }

    func replyAncestors(
        for post: TimelinePost,
        limit: Int = 8
    ) -> [TimelinePost] {
        queryInteractionWorkflow.replyAncestors(
            for: post,
            limit: limit,
            snapshot: timelineQuerySnapshot
        )
    }

    func replies(for post: TimelinePost, limit: Int = 24) -> [TimelinePost] {
        queryInteractionWorkflow.replies(
            for: post,
            limit: limit,
            snapshot: timelineQuerySnapshot
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
        publishedStateCoordinator.relayStatus.revision
    }

    var relayRuntimeStates: [String: NostrRelayConnectionState] {
        publishedStateCoordinator.relayStatus.snapshot.runtimeStates
    }

    var relayStatusCounts: (connected: Int, planned: Int) {
        (
            connected: publishedStateCoordinator.relayStatus.snapshot
                .connectedRelayCount,
            planned: publishedStateCoordinator.relayStatus.snapshot
                .plannedRelayCount
        )
    }

    var activityStatus: NostrTimelineActivityStatus? {
        let backwardRequestState =
            syncInteractionWorkflow.backwardRequestState
        return activityInteractionWorkflow.status(
            context: HomeTimelineActivityContext(
                connectedRelayCount: relayStatusCounts.connected,
                plannedRelayCount: relayStatusCounts.planned,
                hasOlderPageRequest:
                    backwardRequestState.hasOlderPageRequest,
                hasGapWork: backwardRequestState.hasGapWork,
                hasBackwardRequests: backwardRequestState.hasRequests,
                hasPendingDependencyWork:
                    dataInteractionWorkflow.dependencyWorkState.hasPendingWork
            )
        )
    }

    var isRelayProcessing: Bool {
        activityStatus != nil
    }

    var phase: Phase {
        publishedStateCoordinator.activity.phase
    }

    var isRefreshing: Bool {
        publishedStateCoordinator.activity.isRefreshing
    }

    var isLoadingOlder: Bool {
        publishedStateCoordinator.activity.isLoadingOlder
    }

    var isHomeTimelineRealtime: Bool {
        publishedStateCoordinator.activity.isRealtime
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
        dispatchStoreApplication(
            HomeTimelineSyncStoreAction.setRealtime(isRealtime)
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
        applyPresentationTransition(
            presentationWorkflow.replaceEntriesForTesting(
                testEntries,
                renderFingerprint: testEntries.map { $0.id.hashValue }
            )
        )
    }

    func testingSetReadBoundary(postID: TimelinePost.ID) {
        applyPresentationTransition(
            presentationWorkflow.setReadBoundaryForTesting(postID: postID)
        )
    }

    func testingSetUnmaterializedNewEventIDs(_ ids: Set<String>) {
        viewportInteractionWorkflow.replacePendingEventIDs(
            ids,
            context: viewportContextFactory.context()
        )
    }

    func testingMergedProjectionWindow(
        _ current: NostrFeedWindow,
        with loaded: NostrFeedWindow,
        centeredOn anchorEventID: String
    ) -> NostrFeedWindow {
        projectionInteractionWorkflow.mergedWindow(
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
        runtimeInteractionWorkflow.ensureLifecycle(accountID: account.pubkey)
        applyAccountContextTransition(.activate(
            account,
            syncPolicy: syncPolicy
        ))
        applyContentSnapshot(
            dataInteractionWorkflow.perform(
                .replaceFollowedPubkeys(sourceAuthors)
            )
        )
        await projectionInteractionWorkflow.activateStoredProjection(
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
        await runtimeInteractionWorkflow.handlePacket(
            .requestStarted(attempt),
            isActive: true,
            context: runtimeContextFactory.interactionContext()
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
