import Foundation
import AstrenzaCore
import SwiftUI

@MainActor
final class NostrHomeTimelineStore: ObservableObject {
    typealias Phase = NostrHomeTimelinePhase

    @Published private var publishedAccountContextState:
        HomeTimelinePublishedAccountContextState
    @Published private var publishedPresentationState =
        HomeTimelinePublishedPresentationState()
    @Published private var publishedActivityState =
        HomeTimelinePublishedActivityState()
    @Published private var publishedContentState =
        HomeTimelinePublishedContentState()
    @Published private var publishedRelayStatusState =
        HomeTimelinePublishedRelayStatusState()
    @Published private var publishedListProjectionState =
        HomeTimelinePublishedListProjectionState()
    @Published private var publishedPendingEventState =
        HomeTimelinePublishedPendingEventState()

    private let remoteLoadCoordinator: HomeTimelineRemoteLoadCoordinator
    private let loadInteractionWorkflow: HomeTimelineLoadInteractionWorkflow
    private let viewportInteractionWorkflow:
        HomeTimelineViewportInteractionWorkflow
    private let eventStore: NostrEventStore?
    private let dataInteractionWorkflow: HomeTimelineDataInteractionWorkflow
    private let runtimeInteractionWorkflow:
        HomeTimelineRuntimeInteractionWorkflow
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
    private let projectionInteractionWorkflow:
        HomeProjectionInteractionWorkflow
    private let backwardRequestRegistry: HomeTimelineBackwardRequestRegistry
    private let feedSyncInteractionWorkflow:
        HomeTimelineFeedSyncInteractionWorkflow
    private let lifecycleCoordinator: HomeTimelineLifecycleCoordinator
    private let accountStartInteractionWorkflow:
        HomeAccountStartInteractionWorkflow
    private let accountResetInteractionWorkflow:
        HomeAccountResetInteractionWorkflow
    private let relayStatusCoordinator: HomeTimelineRelayStatusCoordinator
    private let linkPreviewCoordinator: HomeTimelineLinkPreviewCoordinator
    private let stateInteractionWorkflow: HomeTimelineStateInteractionWorkflow
    private let publishInteractionWorkflow:
        HomeTimelinePublishInteractionWorkflow?
    private let localMutationInteractionWorkflow:
        HomeLocalMutationInteractionWorkflow?
    private let relayRuntime: NostrRelayRuntime?
    private let outboxCoordinator: HomeTimelineOutboxCoordinator
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

    private func timelineReadContext(
        applyingHomeFilters: Bool = true
    ) -> HomeTimelineReadContext {
        let dependencies = dataInteractionWorkflow.dependencyResolutionState
        return HomeTimelineReadContext(
            accountID: account?.pubkey,
            fallbackEntries: entries,
            metadataEvents: metadataEvents,
            nip05Resolutions: dependencies.nip05Resolutions,
            profileResolutionStates: dependencies.profileResolutionStates,
            followedPubkeys: Set(followedPubkeys),
            resolvedRelayCount: resolvedRelays.count,
            filterRules: applyingHomeFilters
                ? filterInteractionWorkflow.effectiveRuleSet(
                    accountID: account?.pubkey
                )
                : nil,
            syncPolicy: syncPolicy
        )
    }

    private func applyContentSnapshot(_ snapshot: HomeTimelineContentSnapshot) {
        guard let next = publishedContentState.applying(snapshot) else { return }
        publishedContentState = next
    }

    private func applyActivityTransition(
        _ transition: HomeTimelineActivityTransition
    ) {
        guard let next = publishedActivityState.applying(transition) else { return }
        publishedActivityState = next
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
        guard let next = publishedPresentationState.applying(transition) else { return }
        publishedPresentationState = next
    }

    private func updateRelayStatusCounts() {
        applyRelayStatusSnapshot(
            relayStatusCoordinator.snapshot(resolvedRelays: resolvedRelays)
        )
    }

    private func applyRelayStatusSnapshot(_ snapshot: HomeTimelineRelayStatusSnapshot) {
        applyPublishedRelayStatus(snapshot)
    }

    private func applyRelayStatusTransition(
        _ transition: HomeTimelineRelayStatusTransition?
    ) {
        guard let transition else { return }
        applyPublishedRelayStatus(
            transition.snapshot,
            publishingStatusChange: transition.publishesStatusChange
        )
        if let relayURL = transition.invalidatedRealtimeRelayURL {
            invalidateHomeTimelineRealtime(relayURL: relayURL)
        }
    }

    private func applyPublishedRelayStatus(
        _ snapshot: HomeTimelineRelayStatusSnapshot,
        publishingStatusChange: Bool = false
    ) {
        guard let next = publishedRelayStatusState.applying(
            snapshot,
            publishingStatusChange: publishingStatusChange
        ) else { return }
        publishedRelayStatusState = next
    }

    private func publishRelayStatusChange() {
        publishedRelayStatusState = publishedRelayStatusState.publishingStatusChange()
    }

    init(
        timelineLoader: NostrHomeTimelineLoader = NostrHomeTimelineLoader(),
        eventStore: NostrEventStore? = try? NostrEventStore.applicationSupport(appDirectory: "Astrenza"),
        relayRuntime: NostrRelayRuntime? = nil,
        linkPreviewResolver: NostrLinkPreviewResolver? = nil,
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
                outboxPublisher: outboxPublisher,
                localMutationPersistence: localMutationPersistence,
                syncPolicySettingsStore: syncPolicySettingsStore
            )
        )
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
        self.projectionInteractionWorkflow =
            components.projectionInteractionWorkflow
        self.backwardRequestRegistry = components.backwardRequestRegistry
        self.feedSyncInteractionWorkflow =
            components.feedSyncInteractionWorkflow
        self.lifecycleCoordinator = components.lifecycleCoordinator
        self.accountStartInteractionWorkflow =
            components.accountStartInteractionWorkflow
        self.accountResetInteractionWorkflow =
            components.accountResetInteractionWorkflow
        self.relayStatusCoordinator = components.relayStatusCoordinator
        self.linkPreviewCoordinator = components.linkPreviewCoordinator
        self.stateInteractionWorkflow = components.stateInteractionWorkflow
        self.publishInteractionWorkflow = components.publishInteractionWorkflow
        self.localMutationInteractionWorkflow =
            components.localMutationInteractionWorkflow
        self.relayRuntime = components.relayRuntime
        self.outboxCoordinator = components.outboxCoordinator
        self.publishedAccountContextState = HomeTimelinePublishedAccountContextState(
            syncPolicy: syncPolicy
        )
    }

    func start(account: NostrAccount) {
        accountStartInteractionWorkflow.start(
            account: account,
            context: accountStartInteractionContext()
        )
    }

    func setRestoreProjectionAnchor(_ anchorEventID: String?) {
        viewportInteractionWorkflow.setRestoreProjectionAnchor(
            anchorEventID,
            context: viewportInteractionContext()
        )
    }

    func restoredViewportState(accountID: String, timelineKey: String) -> TimelineViewportState? {
        projectionInteractionWorkflow.restoredViewportState(
            accountID: accountID,
            timelineKey: timelineKey
        )
    }

    func saveViewportState(_ state: TimelineViewportState) {
        viewportInteractionWorkflow.saveViewportState(
            state,
            context: viewportInteractionContext()
        )
    }

    func flushPendingViewportStateSave() {
        projectionInteractionWorkflow.flushPendingViewportWrite()
    }

    func refresh() {
        viewportInteractionWorkflow.refresh(
            viewportInteractionContext()
        )
    }

    func refreshLatest() async {
        await viewportInteractionWorkflow.refreshLatest(
            viewportInteractionContext()
        )
    }

    func setTimelineAtNewestWindow(_ isAtNewestWindow: Bool) {
        viewportInteractionWorkflow.setTimelineAtNewestWindow(
            isAtNewestWindow,
            context: viewportInteractionContext()
        )
    }

    func setTimelineScrollActive(_ isActive: Bool) {
        viewportInteractionWorkflow.setTimelineScrollActive(
            isActive,
            context: viewportInteractionContext()
        )
    }

    func dismissUnreadBadge() {
        viewportInteractionWorkflow.dismissUnreadBadge(
            viewportInteractionContext()
        )
    }

    func markMaterializedPostsRead(visiblePostIDs: [TimelinePost.ID]) {
        viewportInteractionWorkflow.markMaterializedPostsRead(
            visiblePostIDs: visiblePostIDs,
            context: viewportInteractionContext()
        )
    }

    func markNewestMaterializedWindowRead() {
        viewportInteractionWorkflow.markNewestMaterializedWindowRead(
            viewportInteractionContext()
        )
    }

    @discardableResult
    func applyPendingNewEvents() async -> Bool {
        viewportInteractionWorkflow.applyPendingNewEvents(
            viewportInteractionContext()
        )
    }

    func loadOlder() {
        viewportInteractionWorkflow.loadOlder(
            viewportInteractionContext()
        )
    }

    private func viewportInteractionContext(
    ) -> HomeTimelineViewportInteractionContext {
        HomeTimelineViewportInteractionContext(
            state: HomeTimelineViewportInteractionState(
                presentation: HomeTimelinePresentationAppState(
                    account: account,
                    restoreProjectionAnchorEventID:
                        restoreProjectionAnchorEventID
                ),
                pendingEvents: HomeTimelinePendingEventsState(
                    account: account,
                    hasPendingProjectionReload:
                        presentationWorkflow.interactionState
                            .hasPendingNewestProjectionReload
                ),
                pagination: HomeTimelinePaginationState(
                    account: account,
                    canBeginLoadingOlder:
                        activityInteractionWorkflow.state
                            .canBeginLoadingOlder,
                    hasMoreOlder: hasMoreOlder,
                    hasTimelineEvents: !noteEvents.isEmpty,
                    hasResolvedRelays: !resolvedRelays.isEmpty,
                    hasFollowedPubkeys: !followedPubkeys.isEmpty
                )
            ),
            effects: HomeTimelineViewportInteractionEffects(
                apply: { [weak self] application in
                    self?.applyViewportInteraction(application)
                },
                load: { [weak self] load in
                    guard let self else { return }
                    await performViewportInteraction(load)
                }
            )
        )
    }

    private func applyViewportInteraction(
        _ application: HomeTimelineViewportApplication
    ) {
        switch application {
        case .applyProjectionViewportTransition(let transition):
            applyProjectionViewportTransition(transition)
        case .reloadNewestProjectionWindow(let account):
            reloadNewestProjectionWindow(account: account)
        case .materializeEntries(let allowsRealtimeFollow):
            materializeEntries(allowsRealtimeFollow: allowsRealtimeFollow)
        case .applyRestoreProjectionAnchor(let account):
            applyRestoreProjectionAnchorIfPossible(account: account)
        case .scheduleViewportState(let state):
            projectionInteractionWorkflow.scheduleViewportState(state)
        case .applyPresentationTransition(let transition):
            applyPresentationTransition(transition)
        case .scheduleReadStateSave:
            scheduleHomeFeedReadStateSave()
        case .applyPendingEventCountPublication(let publication):
            applyPendingEventCountPublication(publication)
        case .clearPendingProjectionReload:
            presentationWorkflow.clearNewestProjectionReload()
        case .scheduleLinkPreviewResolution:
            scheduleLinkPreviewResolution()
        }
    }

    private func performViewportInteraction(
        _ load: HomeTimelineViewportInteractionLoad
    ) async {
        switch load {
        case .refreshLatest(let account, let lifecycle):
            await refreshLatest(account: account, lifecycle: lifecycle)
        case .loadOlder(let account, let lifecycle):
            await loadOlder(account: account, lifecycle: lifecycle)
        }
    }

    func backfillGap(_ gap: TimelineGap, direction: TimelineGapFillDirection) async -> Bool {
        await gapBackfillInteractionWorkflow.backfill(
            gap: gap,
            direction: direction,
            context: gapBackfillInteractionContext()
        )
    }

    func enqueuePublish(_ input: NostrPublishInput, signer: any NostrEventSigning) async throws {
        guard let account, let publishInteractionWorkflow else { return }
        try await publishInteractionWorkflow.enqueue(
            input: input,
            signer: signer,
            context: publishInteractionContext(account: account)
        )
    }

    private func activateOutbox(accountID: String) {
        outboxCoordinator.activate(accountID: accountID) { [weak self] in
            self?.publishRelayStatusChange()
        }
    }

    func muteAuthor(of post: TimelinePost) {
        localMutationInteractionWorkflow?.perform(
            .muteAuthor(authorPubkey: post.author.pubkey),
            context: localMutationInteractionContext()
        )
    }

    func bookmark(_ post: TimelinePost) {
        localMutationInteractionWorkflow?.perform(
            .bookmark(eventID: post.id),
            context: localMutationInteractionContext()
        )
    }

    func cancel() {
        accountResetInteractionWorkflow.reset(
            context: accountResetInteractionContext()
        )
    }

    private func load(
        account: NostrAccount,
        lifecycle: HomeTimelineLifecycleToken
    ) async {
        await loadInteractionWorkflow.loadInitial(
            account: account,
            lifecycle: lifecycle,
            context: loadInteractionContext()
        )
    }

    private func refreshLatest(
        account: NostrAccount,
        lifecycle: HomeTimelineLifecycleToken
    ) async {
        await loadInteractionWorkflow.refreshLatest(
            account: account,
            lifecycle: lifecycle,
            context: loadInteractionContext()
        )
    }

    private func loadOlder(
        account: NostrAccount,
        lifecycle: HomeTimelineLifecycleToken
    ) async {
        await loadInteractionWorkflow.loadOlder(
            account: account,
            lifecycle: lifecycle,
            context: loadInteractionContext()
        )
    }

    private func loadInteractionContext() -> HomeTimelineLoadInteractionContext {
        HomeTimelineLoadInteractionContext(
            state: HomeTimelineLoadInteractionState(
                hasRelayRuntime: relayRuntime != nil,
                hasTimelineEvents: !noteEvents.isEmpty
            ),
            effects: HomeTimelineLoadInteractionEffects(
                environment: HomeTimelineLoadEnvironment(
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
                apply: { [weak self] application in
                    self?.applyLoadApplication(application)
                },
                perform: { [weak self] application in
                    guard let self else { return }
                    await performLoadApplication(application)
                }
            )
        )
    }

    private func applyLoadApplication(
        _ application: HomeTimelineLoadApplication
    ) {
        switch application {
        case .applyActivityTransition(let transition):
            applyActivityTransition(transition)
        case .installProvisionalRuntimeBootstrap(let account):
            installProvisionalRuntimeBootstrapIfNeeded(account: account)
        case .restartAccount(let account):
            start(account: account)
        case .recordBackwardDiagnostic(let diagnostic):
            recordBackwardLoadDiagnostic(diagnostic)
        case .replaceTimelineState(let state):
            replaceTimelineState(state)
        case .replaceRuntimeBootstrapState(let state):
            replaceRuntimeBootstrapState(state)
        case .replaceFollowedPubkeys(let pubkeys):
            replaceFollowedPubkeys(pubkeys)
        case .materializeEntries:
            materializeEntries()
        case .recordLoadDiagnostic(let diagnostic):
            recordLoadDiagnostic(diagnostic)
        case .setPhase(let phase):
            applyActivityIntent(.setPhase(phase))
        }
    }

    private func performLoadApplication(
        _ application: HomeTimelineLoadAsyncApplication
    ) async {
        switch application {
        case .configureRuntime(let account):
            await configureRelayRuntime(account: account)
        case .persistDatabase(let account):
            await persistDatabase(account: account)
        }
    }

    private func recordBackwardLoadDiagnostic(
        _ diagnostic: HomeTimelineBackwardRequestDiagnostic
    ) {
        recordRuntimeSyncEvent(
            relayURL: diagnostic.relayURL,
            kind: .partialFailure,
            subscriptionID: diagnostic.subscriptionID,
            message: diagnostic.message
        )
    }

    private func recordLoadDiagnostic(_ diagnostic: HomeTimelineLoadDiagnostic) {
        recordRuntimeSyncEvent(
            relayURL: diagnostic.relayURL,
            kind: diagnostic.kind,
            subscriptionID: diagnostic.subscriptionID,
            message: diagnostic.message
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
    private func restoreCachedSnapshot(account: NostrAccount) -> Bool {
        stateInteractionWorkflow.restoreCachedState(
            accountID: account.pubkey,
            context: stateInteractionContext()
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
            context: stateInteractionContext()
        )
    }

    private func stateInteractionContext() -> HomeTimelineStateInteractionContext {
        HomeTimelineStateInteractionContext(
            effects: HomeTimelineStateInteractionEffects(
                environment: HomeTimelineStateInteractionEnvironment(
                    persistenceState: { [weak self] in
                        HomeTimelinePersistenceState(
                            accountID: self?.account?.pubkey,
                            followedPubkeys: self?.followedPubkeys ?? []
                        )
                    },
                    hasPendingEvents: { [weak self] in
                        self?.viewportInteractionWorkflow.hasBufferedEvents == true
                    },
                    runtimeApplicationState: { [weak self] in
                        self?.runtimeApplicationState()
                    }
                ),
                apply: { [weak self] application in
                    self?.applyStateInteractionApplication(application)
                }
            )
        )
    }

    private func applyStateInteractionApplication(
        _ application: HomeTimelineStateInteractionApplication
    ) {
        switch application {
        case .applyPresentationTransition(let transition):
            applyPresentationTransition(transition)
        case .applyContentSnapshot(let snapshot):
            applyContentSnapshot(snapshot)
        case .applyRelayStatusSnapshot(let snapshot):
            applyRelayStatusSnapshot(snapshot)
        case .applyListProjectionInvalidation(let invalidation):
            applyListProjectionInvalidation(invalidation)
        case .applyPendingEventCountPublication(let publication):
            applyPendingEventCountPublication(publication)
        case .reloadProjection(let account, let anchorEventID):
            reloadProjectionWindow(account: account, around: anchorEventID)
        case .requestNewestProjectionReload:
            presentationWorkflow.requestNewestProjectionReload()
        case .scheduleMaterialization(let delay, let allowsRealtimeFollow):
            scheduleMaterializeEntries(
                delayNanoseconds: delay,
                allowsRealtimeFollow: allowsRealtimeFollow
            )
        case .materializeEntries:
            materializeEntries()
        case .recordRuntimeDiagnostic(let diagnostic):
            recordRuntimeSyncEvent(
                relayURL: diagnostic.relayURL,
                kind: .partialFailure,
                subscriptionID: nil,
                message: diagnostic.message
            )
        }
    }

    private func ensureHomeFeedDefinition(account: NostrAccount) {
        projectionInteractionWorkflow.ensureDefinition(
            account: account,
            followedPubkeys: followedPubkeys,
            liveEvents: noteEvents
        )
    }

    private func isCurrentHomeFeedContext(_ context: HomeFeedRuntimeContext?) -> Bool {
        projectionInteractionWorkflow.isCurrent(
            context,
            accountID: account?.pubkey
        )
    }

    private func restoreHomeFeedReadState(account: NostrAccount) {
        let positions = entries.compactMap(\.post).map { post in
            HomeTimelineReadPosition(postID: post.id, createdAt: post.createdAt)
        }
        let boundaryID = projectionInteractionWorkflow
            .restoredReadBoundaryPostID(
                accountID: account.pubkey,
                positions: positions
            )
        guard let boundaryID else { return }
        applyPresentationTransition(
            presentationWorkflow.restoreReadBoundary(postID: boundaryID)
        )
    }

    private func scheduleHomeFeedReadStateSave() {
        guard let account else { return }
        projectionInteractionWorkflow.scheduleReadBoundarySave(
            accountID: account.pubkey,
            boundary: currentReadBoundaryCursor()
        )
    }

    private func homeFeedReadBoundaryWrite() -> HomeTimelineReadBoundaryWrite? {
        guard let account else { return nil }
        return projectionInteractionWorkflow.readBoundaryWrite(
            accountID: account.pubkey,
            boundary: currentReadBoundaryCursor()
        )
    }

    private func currentReadBoundaryCursor() -> NostrTimelineEntryCursor? {
        let boundaryID = presentationWorkflow.interactionState.readBoundaryPostID
        return boundaryID.flatMap(timelineEvent(id:)).map {
            NostrTimelineEntryCursor(sortTimestamp: $0.createdAt, eventID: $0.id)
        }
    }

    private func reloadNewestProjectionWindow(account: NostrAccount) {
        projectionInteractionWorkflow.reloadNewestProjection(account: account)
    }

    @discardableResult
    private func reloadProjectionWindow(
        account: NostrAccount,
        around anchorEventID: String?,
        mergingWithCurrentWindow: Bool = false
    ) -> Bool {
        projectionInteractionWorkflow.reloadProjection(
            account: account,
            around: anchorEventID,
            mergingWithCurrentWindow: mergingWithCurrentWindow
        )
    }

    private func applyRestoreProjectionAnchorIfPossible(account: NostrAccount) {
        guard let restoreProjectionAnchorEventID else { return }
        guard reloadProjectionWindow(account: account, around: restoreProjectionAnchorEventID) else { return }
        materializeEntries()
        scheduleLinkPreviewResolution()
        if !entries.isEmpty {
            applyActivityIntent(.setPhase(.loaded))
        }
    }

    private func startRuntimeSession() {
        runtimeInteractionWorkflow.startSession(
            context: runtimeInteractionContext()
        )
    }

    private func installProvisionalRuntimeBootstrapIfNeeded(account: NostrAccount) {
        guard relayRuntime != nil, resolvedRelays.isEmpty else { return }
        let provisionalRelays = provisionalDiscoveryRelays(for: account)
        guard !provisionalRelays.isEmpty else { return }
        applyContentSnapshot(
            dataInteractionWorkflow.perform(
                .installProvisionalRelays(provisionalRelays)
            )
        )
        updateRelayStatusCounts()
    }

    private func provisionalDiscoveryRelays(for account: NostrAccount) -> [String] {
        normalizedRelayURLs(account.discoveryRelays + remoteLoadCoordinator.bootstrapRelays)
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
        await runtimeInteractionWorkflow.configure(
            account: account,
            defaultRelayURLs: runtimeRelayURLs(account: account),
            forceInstall: forceInstall,
            context: runtimeInteractionContext()
        )
    }

    private func recordRuntimeSetupDiagnostic(
        _ diagnostic: HomeTimelineRuntimeSetupDiagnostic
    ) {
        recordRuntimeSyncEvent(
            relayURL: diagnostic.relayURL,
            kind: .partialFailure,
            subscriptionID: diagnostic.subscriptionID,
            message: diagnostic.message
        )
    }

    private func runtimeRelayURLs(account: NostrAccount) -> [String] {
        Array(
            normalizedRelayURLs(
                resolvedRelays + account.discoveryRelays + remoteLoadCoordinator.bootstrapRelays
            )
            .dedupedPreservingOrder()
            .prefix(10)
        )
    }

    private func runtimePacketContext(
        isActive: Bool? = nil
    ) -> HomeTimelineRuntimePacketContext {
        HomeTimelineRuntimePacketContext(
            isActive: isActive ?? (
                activityInteractionWorkflow.state.phase != .idle
            ),
            accountID: account?.pubkey,
            resolvedRelays: resolvedRelays,
            isCurrentFeedContext: { [weak self] context in
                self?.isCurrentHomeFeedContext(context) == true
            }
        )
    }

    private func runtimeInteractionContext(
    ) -> HomeTimelineRuntimeInteractionContext {
        HomeTimelineRuntimeInteractionContext(
            state: HomeTimelineRuntimeInteractionState(
                account: account,
                profileRelayURLs: account.map(runtimeRelayURLs(account:)) ?? [],
                policy: syncPolicy,
                hasRelayRuntime: relayRuntime != nil,
                isTerminating:
                    accountResetInteractionWorkflow.isRuntimeTerminating
            ),
            effects: HomeTimelineRuntimeInteractionEffects(
                environment: HomeTimelineRuntimeStoreEnvironment(
                    packetContext: { [weak self] isActive in
                        self?.runtimePacketContext(isActive: isActive)
                    },
                    isAccountCurrent: { [weak self] accountID in
                        self?.account?.pubkey == accountID
                    }
                ),
                runtimeApplication: runtimeApplicationEffects(),
                apply: { [weak self] application in
                    self?.applyRuntimeInteractionApplication(application)
                },
                perform: { [weak self] application in
                    await self?.performRuntimeInteractionApplication(application)
                }
            )
        )
    }

    private func runtimeEventInteractionContext(
    ) -> HomeTimelineRuntimeEventContext {
        HomeTimelineRuntimeEventContext(
            state: HomeTimelineRuntimeEventInteractionState(
                account: account,
                hasRelayRuntime: relayRuntime != nil,
                receivedWhileRealtime:
                    activityInteractionWorkflow.state.isRealtime
            ),
            effects: HomeTimelineRuntimeEventStoreEffects(
                environment: HomeTimelineRuntimeEventEnvironment(
                    presentationState: { [self] receivedWhileRealtime in
                        HomeTimelineRuntimeEventPresentationState(
                            receivedWhileRealtime: receivedWhileRealtime,
                            hasRestoreProjectionAnchor:
                                restoreProjectionAnchorEventID != nil,
                            isTimelineAtNewestWindow: isTimelineAtNewestWindow,
                            hasPendingEvents:
                                viewportInteractionWorkflow.hasBufferedEvents
                        )
                    },
                    isAccountCurrent: { [self] accountID in
                        account?.pubkey == accountID
                    }
                ),
                runtimeApplication: runtimeApplicationEffects(),
                apply: { [weak self] application in
                    self?.applyRuntimeInteractionApplication(application)
                }
            )
        )
    }

    private func applyRuntimeInteractionApplication(
        _ application: HomeTimelineRuntimeStoreAction
    ) {
        switch application {
        case .setRealtime(let isRealtime):
            applyFeedSyncAction(.setRealtime(isRealtime))
        case .applyRelayStatusTransition(let transition):
            applyRelayStatusTransition(transition)
        case .handleBackwardCompletion(let completion):
            handleBackwardCompletion(completion)
        case .invalidateListEntries:
            invalidateListEntries()
        case .scheduleMaterialization:
            scheduleMaterializeEntries()
        case .recordSetupDiagnostic(let diagnostic):
            recordRuntimeSetupDiagnostic(diagnostic)
        case .recordEventDiagnostic(let diagnostic):
            recordRuntimeSyncEvent(
                relayURL: diagnostic.relayURL,
                kind: .partialFailure,
                subscriptionID: diagnostic.subscriptionID,
                message: diagnostic.message
            )
        case .scheduleLinkPreviewResolution:
            scheduleLinkPreviewResolution()
        }
    }

    private func performRuntimeInteractionApplication(
        _ application: HomeTimelineRuntimeStoreAsyncAction
    ) async {
        switch application {
        case .handleEvent(let relayURL, let subscriptionID, let event):
            await handleRuntimeEvent(
                relayURL: relayURL,
                subscriptionID: subscriptionID,
                event: event
            )
        }
    }

}

private extension NostrHomeTimelineStore {

    private func handleRuntimeEvent(relayURL: String, subscriptionID: String, event: NostrEvent) async {
        await runtimeInteractionWorkflow.handleEvent(
            relayURL: relayURL,
            subscriptionID: subscriptionID,
            event: event,
            context: runtimeEventInteractionContext()
        )
    }

    private func runtimeEventApplicationContext(
        account: NostrAccount,
        lifecycle: HomeTimelineLifecycleToken
    ) -> HomeTimelineRuntimeEventApplicationContext {
        HomeTimelineRuntimeEventApplicationContext(
            account: account,
            lifecycle: lifecycle,
            hasRelayRuntime: relayRuntime != nil
        )
    }

    private func runtimeApplicationEffects() -> HomeTimelineRuntimeApplicationEffects {
        stateInteractionWorkflow.runtimeApplicationEffects(
            context: stateInteractionContext()
        )
    }

    private func runtimeApplicationState() -> HomeTimelineRuntimeApplicationState {
        let dependencies = dataInteractionWorkflow.dependencyResolutionState
        return HomeTimelineRuntimeApplicationState(
            account: account,
            resolvedRelays: resolvedRelays,
            followedPubkeys: followedPubkeys,
            nip05Resolutions: dependencies.nip05Resolutions,
            hasMoreOlder: hasMoreOlder,
            deferredMaterializationDelayNanoseconds:
                presentationWorkflow.interactionState
                    .defaultDelayNanoseconds * 2
        )
    }

    private func enqueueBackwardDependencies(for event: NostrEvent) async {
        guard let account,
              let lifecycle = lifecycleCoordinator.token(for: account.pubkey)
        else { return }
        _ = await runtimeInteractionWorkflow.enqueueDependencies(
            for: event,
            context: runtimeEventApplicationContext(
                account: account,
                lifecycle: lifecycle
            ),
            application: runtimeApplicationEffects()
        )
    }

    private func resolveNIP05IfNeeded(for metadataEvent: NostrEvent) {
        guard let account,
              let lifecycle = lifecycleCoordinator.token(for: account.pubkey)
        else { return }
        runtimeInteractionWorkflow.resolveNIP05IfNeeded(
            for: metadataEvent,
            context: runtimeEventApplicationContext(
                account: account,
                lifecycle: lifecycle
            ),
            application: runtimeApplicationEffects()
        )
    }

    private func handleBackwardCompletion(_ completion: NostrBackwardREQCompletion) {
        backwardInteractionWorkflow.handle(
            completion,
            context: backwardInteractionContext()
        )
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
        message: String?
    ) {
        guard let account else { return }
        applyRelayStatusTransition(
            relayStatusCoordinator.record(
                accountID: account.pubkey,
                resolvedRelays: resolvedRelays,
                relayURL: relayURL,
                kind: kind,
                subscriptionID: subscriptionID,
                eventCount: eventCount,
                newestCreatedAt: newestCreatedAt,
                oldestCreatedAt: oldestCreatedAt,
                message: message
            )
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

    private func materializeEntries(allowsRealtimeFollow: Bool = false) {
        let dependencies = dataInteractionWorkflow.dependencyResolutionState
        guard let transition = projectionInteractionWorkflow.materialize(
            HomeTimelineMaterializationRequest(
                account: account,
                nip05Resolutions: dependencies.nip05Resolutions,
                profileResolutionStates: dependencies.profileResolutionStates,
                policy: syncPolicy,
                allowsRealtimeFollow: allowsRealtimeFollow
            )
        ) else { return }
        applyPresentationTransition(transition)
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
            relaySyncEvents: relayStatusCoordinator.events
        )
    }

    private func replaceTimelineState(_ state: NostrHomeTimelineState) {
        stateInteractionWorkflow.replace(
            state,
            accountID: account?.pubkey,
            context: stateInteractionContext()
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
            application: runtimeApplicationEffects()
        )
    }
}

extension NostrHomeTimelineStore {
    func suspendTimelineFilters() {
        filterInteractionWorkflow.perform(
            .suspend,
            context: filterInteractionContext()
        )
    }

    func resumeTimelineFilters() {
        filterInteractionWorkflow.perform(
            .resume,
            context: filterInteractionContext()
        )
    }
}

private extension NostrHomeTimelineStore {
    func filterInteractionContext(
    ) -> HomeFilterInteractionContext {
        HomeFilterInteractionContext(
            effects: HomeFilterInteractionEffects(
                apply: { [weak self] action in
                    self?.applyFilterAction(action)
                }
            )
        )
    }

    func applyFilterAction(
        _ action: HomeTimelineFilterStoreAction
    ) {
        switch action {
        case .invalidateListEntries:
            invalidateListEntries()
        case .materializeEntries:
            materializeEntries()
        }
    }

    func feedSyncInteractionContext(
    ) -> HomeFeedSyncInteractionContext {
        HomeFeedSyncInteractionContext(
            effects: HomeFeedSyncInteractionEffects(
                apply: { [weak self] action in
                    self?.applyFeedSyncAction(action)
                }
            )
        )
    }

    func applyFeedSyncAction(
        _ action: HomeTimelineFeedSyncStoreAction
    ) {
        switch action {
        case .setRealtime(let isRealtime):
            applyActivityIntent(.setRealtime(isRealtime))
        }
    }

    func resetHomeTimelineRealtime(
        expecting runtimeKeys: Set<RuntimeSubscriptionKey> = []
    ) {
        feedSyncInteractionWorkflow.prepareForwardSubscriptions(
            runtimeKeys,
            context: feedSyncInteractionContext()
        )
    }

    func invalidateHomeTimelineRealtime(
        for key: RuntimeSubscriptionKey
    ) {
        feedSyncInteractionWorkflow.invalidateForwardSubscription(
            key,
            context: feedSyncInteractionContext()
        )
    }

    func invalidateHomeTimelineRealtime(relayURL: String) {
        feedSyncInteractionWorkflow.invalidateForwardSubscriptions(
            relayURL: relayURL,
            context: feedSyncInteractionContext()
        )
    }

    func localMutationInteractionContext(
    ) -> HomeLocalMutationInteractionContext {
        HomeLocalMutationInteractionContext(
            state: HomeLocalMutationInteractionState(
                accountID: account?.pubkey
            ),
            effects: HomeLocalMutationInteractionEffects(
                apply: { [weak self] action in
                    self?.applyLocalMutationAction(action)
                }
            )
        )
    }

    func applyLocalMutationAction(
        _ action: HomeTimelineLocalMutationStoreAction
    ) {
        switch action {
        case .invalidateListEntries:
            invalidateListEntries()
        case .materializeEntries:
            materializeEntries()
        case .setPhase(let phase):
            applyActivityIntent(.setPhase(phase))
        }
    }

    func gapBackfillInteractionContext(
    ) -> HomeGapBackfillInteractionContext {
        HomeGapBackfillInteractionContext(
            state: HomeTimelineGapBackfillInteractionState(
                account: account,
                hasRelayRuntime: relayRuntime != nil,
                resolvedRelayCount: resolvedRelays.count
            ),
            effects: HomeGapBackfillInteractionEffects(
                apply: { [weak self] action in
                    self?.applyGapBackfillAction(action)
                }
            )
        )
    }

    func applyGapBackfillAction(
        _ action: HomeTimelineGapBackfillStoreAction
    ) {
        switch action {
        case .recordDiagnostic(let diagnostic):
            recordRuntimeSyncEvent(
                relayURL: diagnostic.relayURL,
                kind: .partialFailure,
                subscriptionID: diagnostic.subscriptionID,
                message: diagnostic.message
            )
        case .reloadProjection(let account, let anchorEventID):
            reloadProjectionWindow(
                account: account,
                around: anchorEventID
            )
        case .materializeEntries:
            materializeEntries()
        }
    }

    func publishInteractionContext(
        account: NostrAccount
    ) -> HomeTimelinePublishInteractionContext {
        HomeTimelinePublishInteractionContext(
            state: HomeTimelinePublishInteractionState(
                account: account,
                accountWriteRelays:
                    NostrRelayList.parse(from: relayListEvent).writeRelays,
                fallbackRelays: resolvedRelays
            ),
            effects: HomeTimelinePublishInteractionEffects(
                environment: HomeTimelinePublishEnvironment(
                    currentAccountID: { [weak self] in self?.account?.pubkey }
                ),
                apply: { [weak self] action in
                    self?.applyPublishAction(action)
                },
                perform: { [weak self] action in
                    guard let self else { return }
                    await performPublishAsyncAction(action)
                }
            )
        )
    }

    func applyPublishAction(_ action: HomeTimelinePublishStoreAction) {
        switch action {
        case .applyContentSnapshot(let snapshot):
            applyContentSnapshot(snapshot)
        case .reloadNewestProjectionWindow(let account):
            reloadNewestProjectionWindow(account: account)
        case .materializeEntries:
            materializeEntries()
        case .setPhase(let phase):
            applyActivityIntent(.setPhase(phase))
        case .requestImmediateOutboxDrain:
            outboxCoordinator.requestImmediateDrain()
        }
    }

    func performPublishAsyncAction(
        _ action: HomeTimelinePublishAsyncAction
    ) async {
        switch action {
        case .persistDatabase(let account):
            await persistDatabase(account: account)
        }
    }

    func accountResetInteractionContext(
    ) -> HomeAccountResetInteractionContext {
        HomeAccountResetInteractionContext(
            state: HomeTimelineAccountResetInteractionState(
                readBoundaryWrite: homeFeedReadBoundaryWrite(),
                resolvedRelays: resolvedRelays
            ),
            effects: HomeAccountResetInteractionEffects(
                environment: HomeTimelineAccountResetEnvironment(
                    currentAccount: { [weak self] in self?.account }
                ),
                apply: { [weak self] action in
                    self?.applyAccountResetAction(action)
                },
                perform: { [weak self] action in
                    guard let self else { return }
                    await performAccountResetAsyncAction(action)
                }
            )
        )
    }

    func applyAccountResetAction(
        _ action: HomeTimelineAccountResetStoreAction
    ) {
        switch action {
        case .applyPresentationTransition(let transition):
            applyPresentationTransition(transition)
        case .clearPendingEvents:
            clearPendingNewEvents()
        case .applyActivityTransition(let transition):
            applyActivityTransition(transition)
        case .invalidateListEntries:
            invalidateListEntries()
        case .resetRealtimeState:
            resetHomeTimelineRealtime()
        case .applyContentSnapshot(let snapshot):
            applyContentSnapshot(snapshot)
        case .applyRelayStatusSnapshot(let snapshot):
            applyRelayStatusSnapshot(snapshot)
        case .applyProjectionViewportTransition(let transition):
            applyProjectionViewportTransition(transition)
        case .publishRelayStatusChange:
            publishRelayStatusChange()
        case .applyAccountContextTransition(let transition):
            applyAccountContextTransition(transition)
        }
    }

    func performAccountResetAsyncAction(
        _ action: HomeTimelineAccountResetAsyncAction
    ) async {
        switch action {
        case .resetRuntimeState:
            runtimeInteractionWorkflow.resetSetup()
            resetHomeTimelineRealtime()
        case .startRuntimeSession:
            startRuntimeSession()
        case .configureRuntime(let account, let forceInstall):
            await configureRelayRuntime(
                account: account,
                forceInstall: forceInstall
            )
        }
    }

    func accountStartInteractionContext(
    ) -> HomeAccountStartInteractionContext {
        HomeAccountStartInteractionContext(
            state: HomeTimelineAccountStartInteractionState(
                hasRelayRuntime: relayRuntime != nil
            ),
            effects: HomeAccountStartInteractionEffects(
                environment: HomeTimelineAccountStartEnvironment(
                    state: { [unowned self] in
                        HomeTimelineAccountStartStoreState(
                            accountID: account?.pubkey,
                            syncPolicy: syncPolicy,
                            restoreProjectionAnchorEventID:
                                restoreProjectionAnchorEventID,
                            hasEntries: !entries.isEmpty,
                            hasResolvedRelays: !resolvedRelays.isEmpty
                        )
                    },
                    restoreCachedSnapshot: { [weak self] account in
                        self?.restoreCachedSnapshot(account: account) ?? false
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
                    }
                ),
                apply: { [weak self] action in
                    self?.applyAccountStartAction(action)
                },
                load: { [weak self] request in
                    guard let self else { return }
                    await load(
                        account: request.account,
                        lifecycle: request.lifecycle
                    )
                }
            )
        )
    }

    func applyAccountStartAction(
        _ action: HomeTimelineAccountStartStoreAction
    ) {
        switch action {
        case .applyProjectionViewportTransition,
             .reloadNewestProjectionWindow,
             .materializeEntries,
             .applyRestoreProjectionAnchor:
            applyAccountStartProjectionAction(action)
        default:
            applyAccountStartAccountAction(action)
        }
    }

    func applyAccountStartAccountAction(
        _ action: HomeTimelineAccountStartStoreAction
    ) {
        switch action {
        case .cancelCurrentAccount:
            cancel()
        case .applyAccountContextTransition(let transition):
            applyAccountContextTransition(transition)
        case .startRuntimeSession:
            startRuntimeSession()
        case .ensureHomeFeedDefinition(let account):
            ensureHomeFeedDefinition(account: account)
        case .installProvisionalRuntimeBootstrap(let account):
            installProvisionalRuntimeBootstrapIfNeeded(account: account)
        case .restoreHomeFeedReadState(let account):
            restoreHomeFeedReadState(account: account)
        case .setPhase(let phase):
            applyActivityIntent(.setPhase(phase))
        case .activateOutbox(let accountID):
            activateOutbox(accountID: accountID)
        case .applyProjectionViewportTransition,
             .reloadNewestProjectionWindow,
             .materializeEntries,
             .applyRestoreProjectionAnchor:
            assertionFailure("Projection action reached the account router")
        }
    }

    func applyAccountStartProjectionAction(
        _ action: HomeTimelineAccountStartStoreAction
    ) {
        switch action {
        case .applyProjectionViewportTransition(let transition):
            applyProjectionViewportTransition(transition)
        case .reloadNewestProjectionWindow(let account):
            reloadNewestProjectionWindow(account: account)
        case .materializeEntries:
            materializeEntries()
        case .applyRestoreProjectionAnchor(let account):
            applyRestoreProjectionAnchorIfPossible(account: account)
        case .cancelCurrentAccount,
             .applyAccountContextTransition,
             .startRuntimeSession,
             .ensureHomeFeedDefinition,
             .installProvisionalRuntimeBootstrap,
             .restoreHomeFeedReadState,
             .setPhase,
             .activateOutbox:
            assertionFailure("Account action reached the projection router")
        }
    }

    func backwardInteractionContext(
    ) -> HomeTimelineBackwardInteractionContext {
        HomeTimelineBackwardInteractionContext(
            state: HomeTimelineBackwardInteractionState(account: account),
            effects: HomeTimelineBackwardInteractionEffects(
                apply: { [weak self] action in
                    self?.applyBackwardInteractionAction(action)
                },
                resolveDependencies: { [weak self] request in
                    guard let self else { return false }
                    return await resolveBackwardDependencies(request)
                }
            )
        )
    }

    func applyBackwardInteractionAction(
        _ action: HomeTimelineBackwardStoreAction
    ) {
        switch action {
        case .applyContentSnapshot(let snapshot):
            applyContentSnapshot(snapshot)
        case .recordDiagnostic(let diagnostic):
            recordRuntimeSyncEvent(
                relayURL: diagnostic.relayURL,
                kind: .partialFailure,
                subscriptionID: diagnostic.subscriptionID,
                message: diagnostic.message
            )
        case .reloadProjection(
            let account,
            let anchorEventID,
            let mergingWithCurrentWindow
        ):
            reloadProjectionWindow(
                account: account,
                around: anchorEventID,
                mergingWithCurrentWindow: mergingWithCurrentWindow
            )
        case .materializeEntries:
            materializeEntries()
        case .scheduleLinkPreviewResolution:
            scheduleLinkPreviewResolution()
        case .incrementRelayStatusRevision:
            publishRelayStatusChange()
        }
    }

    func resolveBackwardDependencies(
        _ request: HomeTimelineBackwardDependencyRequest
    ) async -> Bool {
        await runtimeInteractionWorkflow.enqueueDependencies(
            for: request.event,
            context: runtimeEventApplicationContext(
                account: request.account,
                lifecycle: request.lifecycle
            ),
            application: runtimeApplicationEffects()
        )
    }

    var syncPolicy: NostrSyncPolicy {
        publishedAccountContextState.syncPolicy
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
        guard let next = publishedAccountContextState.applying(transition) else {
            return
        }
        publishedAccountContextState = next
    }

    @discardableResult
    func clearPendingNewEvents() -> Bool {
        viewportInteractionWorkflow.clearPendingEvents(
            viewportInteractionContext()
        )
    }

    func applyPendingEventCountPublication(
        _ publication: HomeTimelinePendingEventCountPublication
    ) {
        guard let next = publishedPendingEventState.applying(publication) else {
            return
        }
        publishedPendingEventState = next
    }

    func invalidateListEntries() {
        applyListProjectionInvalidation(
            queryInteractionWorkflow.invalidateListEntries()
        )
    }

    func applyListProjectionInvalidation(
        _ invalidation: HomeTimelineListProjectionInvalidation
    ) {
        guard let next = publishedListProjectionState.applying(invalidation) else {
            return
        }
        publishedListProjectionState = next
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
        guard let account else { return [] }
        return queryInteractionWorkflow.listEntries(
            HomeTimelineListProjectionQuery(
                accountID: account.pubkey,
                limit: limit,
                homeContentRevision: resolvedContentRevision,
                context: timelineReadContext(applyingHomeFilters: false)
            )
        )
    }

    func post(eventID: String) -> TimelinePost? {
        queryInteractionWorkflow.post(
            eventID: eventID,
            context: timelineReadContext()
        )
    }

    func profile(pubkey: String, isCurrentUser: Bool = false) -> UserProfile {
        queryInteractionWorkflow.profile(
            pubkey: pubkey,
            isCurrentUser: isCurrentUser,
            context: timelineReadContext()
        )
    }

    func profilePosts(pubkey: String, limit: Int = 80) -> [TimelinePost] {
        queryInteractionWorkflow.profilePosts(
            pubkey: pubkey,
            limit: limit,
            context: timelineReadContext()
        )
    }

    func replyAncestors(
        for post: TimelinePost,
        limit: Int = 8
    ) -> [TimelinePost] {
        queryInteractionWorkflow.replyAncestors(
            for: post,
            limit: limit,
            context: timelineReadContext()
        )
    }

    func replies(for post: TimelinePost, limit: Int = 24) -> [TimelinePost] {
        queryInteractionWorkflow.replies(
            for: post,
            limit: limit,
            context: timelineReadContext()
        )
    }
}

extension NostrHomeTimelineStore {
    var account: NostrAccount? {
        publishedAccountContextState.account
    }

    var currentSyncPolicy: NostrSyncPolicy {
        publishedAccountContextState.syncPolicy
    }

    var unmaterializedNewCount: Int {
        publishedPendingEventState.count
    }

    var listContentRevision: Int {
        publishedListProjectionState.revision
    }

    var relayStatusRevision: Int {
        publishedRelayStatusState.revision
    }

    var relayRuntimeStates: [String: NostrRelayConnectionState] {
        publishedRelayStatusState.snapshot.runtimeStates
    }

    var relayStatusCounts: (connected: Int, planned: Int) {
        (
            connected: publishedRelayStatusState.snapshot.connectedRelayCount,
            planned: publishedRelayStatusState.snapshot.plannedRelayCount
        )
    }

    var activityStatus: NostrTimelineActivityStatus? {
        activityInteractionWorkflow.status(
            context: HomeTimelineActivityContext(
                connectedRelayCount: relayStatusCounts.connected,
                plannedRelayCount: relayStatusCounts.planned,
                hasOlderPageRequest: backwardRequestRegistry.hasOlderPageRequest,
                hasGapWork: backwardRequestRegistry.hasGapWork,
                hasBackwardRequests: backwardRequestRegistry.hasRequests,
                hasPendingDependencyWork:
                    dataInteractionWorkflow.dependencyWorkState.hasPendingWork
            )
        )
    }

    var isRelayProcessing: Bool {
        activityStatus != nil
    }

    var phase: Phase {
        publishedActivityState.phase
    }

    var isRefreshing: Bool {
        publishedActivityState.isRefreshing
    }

    var isLoadingOlder: Bool {
        publishedActivityState.isLoadingOlder
    }

    var isHomeTimelineRealtime: Bool {
        publishedActivityState.isRealtime
    }

    var resolvedRelays: [String] {
        publishedContentState.resolvedRelays
    }

    var followedPubkeys: [String] {
        publishedContentState.followedPubkeys
    }

    var hasMoreOlder: Bool {
        publishedContentState.hasMoreOlder
    }

    var entries: [TimelineFeedEntry] {
        publishedPresentationState.entries
    }

    var filterStatus: TimelineFilterStatus {
        publishedPresentationState.filterStatus
    }

    var materializedUnreadCount: Int {
        publishedPresentationState.materializedUnreadCount
    }

    var visibleUnreadBadgeCount: Int {
        publishedPresentationState.visibleUnreadBadgeCount
    }

    var resolvedContentRevision: Int {
        publishedPresentationState.resolvedContentRevision
    }

    var realtimeFollowSourceRevision: Int? {
        publishedPresentationState.realtimeFollowSourceRevision
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
        applyFeedSyncAction(.setRealtime(isRealtime))
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
            context: viewportInteractionContext()
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
    ) {
        if lifecycleCoordinator.token(for: account.pubkey) == nil {
            lifecycleCoordinator.begin(accountID: account.pubkey)
        }
        applyAccountContextTransition(.activate(
            account,
            syncPolicy: syncPolicy
        ))
        applyContentSnapshot(
            dataInteractionWorkflow.perform(
                .replaceFollowedPubkeys(sourceAuthors)
            )
        )
        projectionInteractionWorkflow.activateStoredProjection(
            definition: definition,
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
        feedSyncInteractionWorkflow.registerForwardContext(
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

    func testingHandleFeedSyncRequestStarted(_ attempt: NostrRelayRequestAttempt) async {
        await runtimeInteractionWorkflow.handlePacket(
            .requestStarted(attempt),
            isActive: true,
            context: runtimeInteractionContext()
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
        backwardRequestRegistry.requestCount +
            dataInteractionWorkflow.dependencyWorkState.pendingSourceRequestCount
    }

    var testingHasPendingDependencyWork: Bool {
        dataInteractionWorkflow.dependencyWorkState.hasPendingWork
    }

    var testingActiveFeedSyncRequestCount: Int {
        feedSyncInteractionWorkflow.activeRequestCount
    }

    var testingActiveFeedSyncContextCount: Int {
        feedSyncInteractionWorkflow.activeContextCount
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
