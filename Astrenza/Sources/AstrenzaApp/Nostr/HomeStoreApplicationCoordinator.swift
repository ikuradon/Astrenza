import AstrenzaCore

@MainActor
protocol HomeStoreContextApplicationTarget:
    HomeStoreApplicationEffectTarget,
    HomeLoadApplicationEffectTarget,
    HomeAccountApplicationEffectTarget,
    HomeViewportApplicationEffectTarget {}

@MainActor
struct HomeStoreApplicationCollaborators {
    let publishedState: HomeTimelinePublishedStateCoordinator
    let context: HomeStoreContextCoordinator
    let query: HomeStoreQueryCoordinator
    let projection: HomeStoreProjectionCoordinator
    let lifecycle: HomeStoreLifecycleCoordinator
    let sync: HomeStoreSyncCoordinator
    let state: HomeStoreStateCoordinator
    let runtime: HomeStoreRuntimeCoordinator
    let viewport: HomeStoreViewportCoordinator
    let presentation: HomeStorePresentationCoordinator
    let status: HomeStoreStatusCoordinator
    let restore: HomeStoreRestoreCoordinator
}

@MainActor
final class HomeStoreApplicationCoordinator:
    HomeStoreContextApplicationTarget {
    private let collaborators: HomeStoreApplicationCollaborators

    init(collaborators: HomeStoreApplicationCollaborators) {
        self.collaborators = collaborators
    }

    var contextApplications: HomeStoreContextApplications {
        HomeStoreContextApplications.make(target: self)
    }
}

extension HomeStoreApplicationCoordinator {
    func applyContentSnapshot(_ snapshot: HomeTimelineContentSnapshot) {
        collaborators.publishedState.applyContentSnapshot(snapshot)
    }

    func applyAccountContextTransition(
        _ transition: HomeTimelineAccountContextTransition
    ) {
        collaborators.publishedState.applyAccountContextTransition(transition)
    }

    func applyPendingEventCountPublication(
        _ publication: HomeTimelinePendingEventCountPublication
    ) {
        collaborators.publishedState.applyPendingEventCountPublication(
            publication
        )
    }

    func applyListProjectionInvalidation(
        _ invalidation: HomeTimelineListProjectionInvalidation
    ) {
        collaborators.publishedState.applyListProjectionInvalidation(
            invalidation
        )
    }

    func invalidateListEntries() {
        applyListProjectionInvalidation(
            collaborators.query.invalidateListEntries()
        )
    }
}

extension HomeStoreApplicationCoordinator {
    func applyActivityTransition(
        _ transition: HomeTimelineActivityTransition
    ) {
        collaborators.status.applyActivityTransition(transition)
    }

    func applyActivityIntent(_ intent: HomeTimelineActivityIntent) {
        collaborators.status.applyActivityIntent(intent)
    }

    func applyRelayStatusSnapshot(
        _ snapshot: HomeTimelineRelayStatusSnapshot
    ) {
        collaborators.status.applyRelayStatusSnapshot(snapshot)
    }

    func applyRelayStatusTransition(
        _ transition: HomeTimelineRelayStatusTransition?
    ) {
        guard let relayURL = collaborators.status.applyRelayStatusTransition(
            transition
        ) else { return }
        collaborators.sync.invalidateForwardSubscriptions(relayURL: relayURL)
    }

    func publishRelayStatusChange() {
        collaborators.status.publishRelayStatusChange()
    }

    func publishProfileMetadataChange() {
        collaborators.publishedState.publishProfileMetadataChange()
    }

    func resetHomeTimelineRealtime(
        expecting runtimeKeys: Set<RuntimeSubscriptionKey>
    ) {
        collaborators.sync.prepareForwardSubscriptions(runtimeKeys)
    }
}

extension HomeStoreApplicationCoordinator {
    func start(account: NostrAccount) {
        collaborators.lifecycle.start(account: account)
    }

    func cancel() {
        collaborators.lifecycle.cancel()
    }

    func refreshLatest(
        account: NostrAccount,
        lifecycle: HomeTimelineLifecycleToken
    ) async {
        await collaborators.lifecycle.refreshLatest(
            account: account,
            lifecycle: lifecycle
        )
    }

    func loadOlder(
        account: NostrAccount,
        lifecycle: HomeTimelineLifecycleToken
    ) async {
        await collaborators.lifecycle.loadOlder(
            account: account,
            lifecycle: lifecycle
        )
    }
}

extension HomeStoreApplicationCoordinator {
    func prepareHomeFeedDefinition(account: NostrAccount) {
        collaborators.projection.prepareDefinition(account: account)
    }

    func reloadNewestProjectionWindow(account: NostrAccount) {
        collaborators.projection.reloadNewestProjection(
            account: account,
            preserving:
                collaborators.viewport.restoreProjectionAnchorEventID
        )
    }

    func reloadProjectionWindow(
        account: NostrAccount,
        around anchorEventID: String?,
        mergingWithCurrentWindow: Bool,
        onCompletion: HomeTimelineMaterializationCoordinating
            .ProjectionReloadHandler?
    ) {
        collaborators.projection.reloadProjection(
            account: account,
            around: anchorEventID,
            mergingWithCurrentWindow: mergingWithCurrentWindow,
            onCompletion: onCompletion
        )
    }

    func applyProjectionViewportTransition(
        _ transition: HomeTimelineProjectionViewportTransition
    ) {
        collaborators.viewport.applyProjectionViewportTransition(transition)
    }

    @discardableResult
    func clearPendingNewEvents() -> Bool {
        collaborators.viewport.clearPendingNewEvents()
    }

    func applyRestoreProjectionAnchorIfPossible(account: NostrAccount) {
        collaborators.restore.restoreIfPossible(account: account)
    }
}

extension HomeStoreApplicationCoordinator {
    func applyPresentationTransition(
        _ transition: HomeTimelinePresentationTransition
    ) {
        collaborators.presentation.applyPresentationTransition(transition)
    }

    func requestNewestProjectionReload() {
        collaborators.presentation.requestNewestProjectionReload()
    }

    func materializeEntries(
        allowsRealtimeFollow: Bool,
        onTransition: HomeTimelineMaterializationCoordinating
            .TransitionHandler?
    ) {
        collaborators.presentation.materializeEntries(
            allowsRealtimeFollow: allowsRealtimeFollow,
            onTransition: onTransition
        )
    }

    func waitForPendingPresentation() async -> Bool {
        await collaborators.presentation.waitForPendingPresentation()
    }

    func scheduleMaterializeEntries(
        delayNanoseconds: UInt64?,
        allowsRealtimeFollow: Bool?
    ) {
        collaborators.presentation.scheduleMaterialization(
            delayNanoseconds: delayNanoseconds,
            allowsRealtimeFollow: allowsRealtimeFollow
        )
    }

    func clearPendingProjectionReload() {
        collaborators.presentation.clearNewestProjectionReload()
    }
}

extension HomeStoreApplicationCoordinator {
    func startRuntimeSession() {
        collaborators.runtime.startSession()
    }

    func installProvisionalRuntimeBootstrapIfNeeded(account: NostrAccount) {
        guard let provisionalRelays = collaborators.runtime
            .provisionalBootstrapRelayURLs(account: account)
        else { return }
        applyContentSnapshot(
            collaborators.state.installProvisionalRelays(provisionalRelays)
        )
        collaborators.status.refreshRelayStatusCounts()
    }

    func configureRelayRuntime(
        account: NostrAccount,
        forceInstall: Bool
    ) async {
        await collaborators.runtime.configure(
            account: account,
            forceInstall: forceInstall
        )
    }

    func handleRuntimeEvents(
        _ events: [HomeTimelineRuntimeEventEnvelope]
    ) async {
        await collaborators.runtime.handleEvents(events)
    }

    func handleRuntimeEvent(
        relayURL: String,
        subscriptionID: String,
        event: NostrEvent
    ) async {
        await handleRuntimeEvents([HomeTimelineRuntimeEventEnvelope(
            relayURL: relayURL,
            subscriptionID: subscriptionID,
            event: event
        )])
    }

    func handleBackwardCompletion(_ completion: NostrBackwardREQCompletion) {
        collaborators.runtime.handleBackwardCompletion(completion)
    }

    func scheduleLinkPreviewResolution() {
        collaborators.runtime.scheduleLinkPreviewResolution()
    }

    func resetRuntimeSetup() {
        collaborators.runtime.resetSetup()
    }
}

extension HomeStoreApplicationCoordinator {
    func replaceTimelineState(_ state: NostrHomeTimelineState) {
        collaborators.state.replaceTimelineState(state)
    }

    func replaceRuntimeBootstrapState(_ state: NostrHomeTimelineState) {
        collaborators.state.replaceRuntimeBootstrapState(state)
    }

    func replaceFollowedPubkeys(_ pubkeys: [String]) {
        applyContentSnapshot(
            collaborators.state.replaceFollowedPubkeys(pubkeys)
        )
    }

    func persistDatabase(account: NostrAccount) async {
        await collaborators.state.persistDatabase(accountID: account.pubkey)
    }

    func scheduleHomeFeedReadStateSave() {
        collaborators.context.scheduleReadBoundarySave()
    }
}
