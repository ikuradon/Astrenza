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
    private let gapBackfillInteractionWorkflow:
        HomeGapBackfillInteractionWorkflow
    private let backwardInteractionWorkflow:
        HomeTimelineBackwardInteractionWorkflow
    private let filterInteractionWorkflow:
        HomeTimelineFilterInteractionWorkflow
    private let queryStoreCoordinator: HomeStoreQueryCoordinator
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
    private lazy var readBoundaryStoreCoordinator =
        HomeStoreReadBoundaryCoordinator(
            interaction: readBoundaryInteractionWorkflow,
            target: self
        )
    private lazy var storeApplicationEffects =
        HomeStoreApplicationEffectsFactory.make(target: self)
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
    private lazy var restoreProjectionAnchorWorkflow =
        HomeRestoreProjectionAnchorWorkflow(target: self)
    private var publishedStateObservation: AnyCancellable?
    private let projectionViewportCoordinator =
        HomeProjectionViewportCoordinator()

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

    func applyContentSnapshot(_ snapshot: HomeTimelineContentSnapshot) {
        publishedStateCoordinator.applyContentSnapshot(snapshot)
    }

    func applyActivityTransition(
        _ transition: HomeTimelineActivityTransition
    ) {
        publishedStateCoordinator.applyActivityTransition(transition)
    }

    func applyActivityIntent(
        _ intent: HomeTimelineActivityIntent
    ) {
        applyActivityTransition(
            activityInteractionWorkflow.perform(intent)
        )
    }

    func applyPresentationTransition(
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

    func applyRelayStatusSnapshot(_ snapshot: HomeTimelineRelayStatusSnapshot) {
        publishedStateCoordinator.applyRelayStatusSnapshot(snapshot)
    }

    func applyRelayStatusTransition(
        _ transition: HomeTimelineRelayStatusTransition?
    ) {
        if let relayURL = publishedStateCoordinator.applyRelayStatusTransition(
            transition
        ) {
            invalidateHomeTimelineRealtime(relayURL: relayURL)
        }
    }

    func publishRelayStatusChange() {
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
        self.queryStoreCoordinator = HomeStoreQueryCoordinator(
            interaction: components.queryInteractionWorkflow
        )
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
        self.queryStoreCoordinator.bind(target: self)
        observePublishedState()
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

    func refreshLatest(
        account: NostrAccount,
        lifecycle: HomeTimelineLifecycleToken
    ) async {
        await loadInteractionWorkflow.refreshLatest(
            account: account,
            lifecycle: lifecycle,
            context: loadContextFactory.context()
        )
    }

    func loadOlder(
        account: NostrAccount,
        lifecycle: HomeTimelineLifecycleToken
    ) async {
        await loadInteractionWorkflow.loadOlder(
            account: account,
            lifecycle: lifecycle,
            context: loadContextFactory.context()
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

    @discardableResult
    private func restoreCachedSnapshot(account: NostrAccount) async -> Bool {
        await stateInteractionWorkflow.restoreCachedState(
            accountID: account.pubkey,
            context: stateContextFactory.context()
        )
    }

    func persistDatabase(account: NostrAccount) async {
        await stateInteractionWorkflow.persistSnapshot(
            dataInteractionWorkflow.persistenceSnapshotInput(
                accountID: account.pubkey
            ),
            context: stateContextFactory.context()
        )
    }

    private func isCurrentHomeFeedContext(_ context: HomeFeedRuntimeContext?) -> Bool {
        projectionInteractionWorkflow.isCurrent(
            context,
            accountID: account?.pubkey
        )
    }

    private func restoreHomeFeedReadState(account: NostrAccount) async {
        await readBoundaryStoreCoordinator.restore(account: account)
    }

    func scheduleHomeFeedReadStateSave() {
        readBoundaryStoreCoordinator.scheduleSave()
    }

    private func homeFeedReadBoundaryWrite() -> HomeTimelineReadBoundaryWrite? {
        readBoundaryStoreCoordinator.boundaryWrite()
    }

    func prepareHomeFeedDefinition(account: NostrAccount) {
        projectionInteractionWorkflow.prepareDefinition(
            account: account,
            followedPubkeys: followedPubkeys,
            liveEvents: noteEvents
        )
    }

    func reloadNewestProjectionWindow(account: NostrAccount) {
        projectionInteractionWorkflow.reloadNewestProjection(account: account)
    }

    func reloadProjectionWindow(
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

    func requestNewestProjectionReload() {
        presentationWorkflow.requestNewestProjectionReload()
    }

    func applyRestoreProjectionAnchorIfPossible(account: NostrAccount) {
        restoreProjectionAnchorWorkflow.restoreIfPossible(account: account)
    }

    func startRuntimeSession() {
        runtimeInteractionWorkflow.startSession(
            context: runtimeContextFactory.interactionContext()
        )
    }

    func installProvisionalRuntimeBootstrapIfNeeded(account: NostrAccount) {
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

    func configureRelayRuntime(account: NostrAccount, forceInstall: Bool = false) async {
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

}

extension NostrHomeTimelineStore {

    func handleRuntimeEvent(
        relayURL: String,
        subscriptionID: String,
        event: NostrEvent
    ) async {
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

    func handleBackwardCompletion(_ completion: NostrBackwardREQCompletion) {
        backwardInteractionWorkflow.handle(
            completion,
            context: featureInteractionContextFactory.backwardContext()
        )
    }

    func scheduleLinkPreviewResolution() {
        let interaction =
            featureInteractionContextFactory.linkPreviewInteraction()
        linkPreviewInteractionWorkflow.schedule(
            state: interaction.state,
            effects: interaction.effects
        )
    }

    private func databaseBackfillEvents(account: NostrAccount, current: NostrHomeTimelineState) -> [NostrEvent]? {
        queryStoreCoordinator.olderBackfillEvents(
            account: account,
            current: current
        )
    }

    func materializeEntries(
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

    func scheduleMaterializeEntries(
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

    func replaceTimelineState(_ state: NostrHomeTimelineState) {
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
    func observePublishedState() {
        publishedStateObservation =
            publishedStateCoordinator.objectWillChange.sink { [weak self] in
                self?.publishedStateRevision &+= 1
            }
    }

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
                applications: HomeLoadApplicationEffectsFactory.make(
                    target: self
                )
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
                applications: storeApplicationEffects
            )
        )
    }

    func makeStateContextFactory() -> HomeStateContextFactory {
        HomeStateContextFactory(
            environment: HomeStateContextEnvironment(
                projection: { [weak self] in
                    self?.stateContextProjection()
                },
                applications: storeApplicationEffects
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
                applications: storeApplicationEffects,
                resolveBackwardDependencies: { [weak self] request in
                    guard let self else { return false }
                    return await resolveBackwardDependencies(request)
                },
                didUpdateLinkPreview: { [weak self] in
                    self?.invalidateListEntries()
                    self?.scheduleMaterializeEntries()
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
                load: { [weak self] request in
                    guard let self else { return }
                    await load(
                        account: request.account,
                        lifecycle: request.lifecycle
                    )
                },
                applications: HomeAccountApplicationEffectsFactory.make(
                    target: self
                )
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
                applications: HomeViewportApplicationEffectsFactory.make(
                    target: self
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
}

extension NostrHomeTimelineStore {
    var syncPolicy: NostrSyncPolicy {
        publishedStateCoordinator.accountContext.syncPolicy
    }

    var currentReadBoundaryPostID: String? {
        presentationWorkflow.interactionState.readBoundaryPostID
    }

    var restoreProjectionAnchorEventID: String? {
        projectionViewportCoordinator.restoreAnchorEventID
    }

    var isTimelineAtNewestWindow: Bool {
        projectionViewportCoordinator.isAtNewestWindow
    }
}

extension NostrHomeTimelineStore {
    func resetHomeTimelineRealtime(
        expecting runtimeKeys: Set<RuntimeSubscriptionKey> = []
    ) {
        syncInteractionWorkflow.prepareForwardSubscriptions(
            runtimeKeys,
            context: featureInteractionContextFactory.syncContext()
        )
    }

    func applyProjectionViewportTransition(
        _ transition: HomeTimelineProjectionViewportTransition
    ) {
        projectionViewportCoordinator.apply(transition)
    }

    func applyRestoredReadBoundary(postID: String) {
        applyPresentationTransition(
            presentationWorkflow.restoreReadBoundary(postID: postID)
        )
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

    func resetRuntimeSetup() {
        runtimeInteractionWorkflow.resetSetup()
    }

    func clearPendingProjectionReload() {
        presentationWorkflow.clearNewestProjectionReload()
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

extension NostrHomeTimelineStore:
    HomeStoreApplicationEffectTarget {}

extension NostrHomeTimelineStore:
    HomeAccountApplicationEffectTarget {}

extension NostrHomeTimelineStore:
    HomeViewportApplicationEffectTarget,
    HomeLoadApplicationEffectTarget {}

extension NostrHomeTimelineStore:
    HomeRestoreProjectionAnchorTarget {}

extension NostrHomeTimelineStore:
    HomeStoreReadBoundaryTarget {}

extension NostrHomeTimelineStore: HomeStoreQueryTarget {
    var queryPreferredEvents: [NostrEvent] {
        noteEvents
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
        featureInteractionContextFactory.syncContext().effects.apply(
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
