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
    private let loadWorkflow: HomeTimelineLoadWorkflow
    private let viewportInteractionWorkflow:
        HomeTimelineViewportInteractionWorkflow
    private let eventStore: NostrEventStore?
    private let contentCoordinator: HomeTimelineContentCoordinator
    private let runtimeEventWorkflow: HomeTimelineRuntimeEventWorkflow
    private let runtimeWorkflow: HomeTimelineRuntimeWorkflow
    private let gapBackfillWorkflow: HomeTimelineGapBackfillWorkflow
    private let backwardCompletionWorkflow: HomeTimelineBackwardCompletionWorkflow
    private let dependencyCoordinator: HomeTimelineDependencyResolutionCoordinator
    private let filterCoordinator: HomeTimelineFilterCoordinator
    private let listProjectionCache: HomeTimelineListProjectionCache
    private let activityCoordinator: HomeTimelineActivityCoordinator
    private let presentationCoordinator: HomeTimelinePresentationCoordinator
    private let materializationCoordinator: HomeTimelineMaterializationCoordinator
    private let pendingEventBuffer: HomeTimelinePendingEventBuffer
    private let backwardRequestRegistry: HomeTimelineBackwardRequestRegistry
    private let feedSyncCoordinator: HomeTimelineFeedSyncCoordinator
    private let lifecycleCoordinator: HomeTimelineLifecycleCoordinator
    private let accountStartWorkflow: HomeTimelineAccountStartWorkflow
    private let accountResetWorkflow: HomeTimelineAccountResetWorkflow
    private let relayStatusCoordinator: HomeTimelineRelayStatusCoordinator
    private let linkPreviewCoordinator: HomeTimelineLinkPreviewCoordinator
    private let readStateCoordinator: HomeTimelineReadStateCoordinator
    private let timelineRepository: HomeTimelineRepository
    private let homeFeedProjection: HomeFeedProjectionController
    private let stateWorkflow: HomeTimelineStateWorkflow
    private let publishWorkflow: HomeTimelinePublishWorkflow?
    private let localMutationCoordinator: HomeTimelineLocalMutationCoordinator?
    private let relayRuntime: NostrRelayRuntime?
    private let outboxCoordinator: HomeTimelineOutboxCoordinator
    private var projectionViewportState = HomeTimelineProjectionViewportState()

    var relayStatusEventStore: NostrEventStore? {
        eventStore
    }

    private var noteEvents: [NostrEvent] {
        contentCoordinator.noteEvents
    }

    private var metadataEvents: [NostrEvent] {
        contentCoordinator.metadataEvents
    }

    private var relayListEvent: NostrEvent? {
        contentCoordinator.relayListEvent
    }

    private var contactListEvent: NostrEvent? {
        contentCoordinator.contactListEvent
    }

    private func timelineReadContext(
        applyingHomeFilters: Bool = true
    ) -> HomeTimelineReadContext {
        HomeTimelineReadContext(
            accountID: account?.pubkey,
            fallbackEntries: entries,
            metadataEvents: metadataEvents,
            nip05Resolutions: dependencyCoordinator.nip05Resolutions,
            profileResolutionStates: dependencyCoordinator.profileResolutionStates,
            followedPubkeys: Set(followedPubkeys),
            resolvedRelayCount: resolvedRelays.count,
            filterRules: applyingHomeFilters
                ? filterCoordinator.effectiveRuleSet(accountID: account?.pubkey)
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
        self.loadWorkflow = components.loadWorkflow
        self.viewportInteractionWorkflow = components.viewportInteractionWorkflow
        self.eventStore = components.eventStore
        self.contentCoordinator = components.contentCoordinator
        self.runtimeEventWorkflow = components.runtimeEventWorkflow
        self.runtimeWorkflow = components.runtimeWorkflow
        self.gapBackfillWorkflow = components.gapBackfillWorkflow
        self.backwardCompletionWorkflow = components.backwardCompletionWorkflow
        self.dependencyCoordinator = components.dependencyCoordinator
        self.filterCoordinator = components.filterCoordinator
        self.listProjectionCache = components.listProjectionCache
        self.activityCoordinator = components.activityCoordinator
        self.presentationCoordinator = components.presentationCoordinator
        self.materializationCoordinator = components.materializationCoordinator
        self.pendingEventBuffer = components.pendingEventBuffer
        self.backwardRequestRegistry = components.backwardRequestRegistry
        self.feedSyncCoordinator = components.feedSyncCoordinator
        self.lifecycleCoordinator = components.lifecycleCoordinator
        self.accountStartWorkflow = components.accountStartWorkflow
        self.accountResetWorkflow = components.accountResetWorkflow
        self.relayStatusCoordinator = components.relayStatusCoordinator
        self.linkPreviewCoordinator = components.linkPreviewCoordinator
        self.readStateCoordinator = components.readStateCoordinator
        self.timelineRepository = components.timelineRepository
        self.homeFeedProjection = components.homeFeedProjection
        self.stateWorkflow = components.stateWorkflow
        self.publishWorkflow = components.publishWorkflow
        self.localMutationCoordinator = components.localMutationCoordinator
        self.relayRuntime = components.relayRuntime
        self.outboxCoordinator = components.outboxCoordinator
        self.publishedAccountContextState = HomeTimelinePublishedAccountContextState(
            syncPolicy: syncPolicy
        )
    }

    func start(account: NostrAccount) {
        accountStartWorkflow.start(
            HomeTimelineAccountStartInput(
                account: account,
                hasRelayRuntime: relayRuntime != nil
            ),
            effects: accountStartEffects()
        )
    }

    func setRestoreProjectionAnchor(_ anchorEventID: String?) {
        viewportInteractionWorkflow.setRestoreProjectionAnchor(
            anchorEventID,
            context: viewportInteractionContext()
        )
    }

    func restoredViewportState(accountID: String, timelineKey: String) -> TimelineViewportState? {
        readStateCoordinator.restoredViewportState(
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
        readStateCoordinator.flushPendingViewportWrite()
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
                        restoreProjectionAnchorEventID,
                    homeFeedID: homeFeedProjection.definition?.feedID
                ),
                pendingEvents: HomeTimelinePendingEventsState(
                    account: account,
                    hasBufferedEvents: pendingEventBuffer.hasEvents,
                    hasPendingProjectionReload:
                        presentationCoordinator.hasPendingNewestProjectionReload
                ),
                pagination: HomeTimelinePaginationState(
                    account: account,
                    canBeginLoadingOlder:
                        activityCoordinator.canBeginLoadingOlder,
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
        case .scheduleViewportState(let state, let feedID, let scopeID):
            readStateCoordinator.scheduleViewportState(
                state,
                feedID: feedID,
                scopeID: scopeID
            )
        case .applyPresentationTransition(let transition):
            applyPresentationTransition(transition)
        case .scheduleReadStateSave:
            scheduleHomeFeedReadStateSave()
        case .clearBufferedEvents:
            clearPendingNewEvents()
        case .clearPendingProjectionReload:
            presentationCoordinator.clearNewestProjectionReload()
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
        await gapBackfillWorkflow.backfill(
            HomeTimelineGapBackfillRequest(
                account: account,
                hasRelayRuntime: relayRuntime != nil,
                resolvedRelayCount: resolvedRelays.count,
                gap: gap,
                direction: direction
            ),
            effects: gapBackfillEffects()
        )
    }

    private func gapBackfillEffects() -> HomeTimelineGapBackfillEffects {
        HomeTimelineGapBackfillEffects(
            recordDiagnostic: { [weak self] diagnostic in
                self?.recordRuntimeSyncEvent(
                    relayURL: diagnostic.relayURL,
                    kind: .partialFailure,
                    subscriptionID: diagnostic.subscriptionID,
                    message: diagnostic.message
                )
            },
            reloadProjection: { [weak self] account, anchorEventID in
                self?.reloadProjectionWindow(account: account, around: anchorEventID)
            },
            materializeEntries: { [weak self] in
                self?.materializeEntries()
            }
        )
    }

    func enqueuePublish(_ input: NostrPublishInput, signer: any NostrEventSigning) async throws {
        guard let account, let publishWorkflow else { return }
        try await publishWorkflow.enqueue(
            HomeTimelinePublishRequest(
                input: input,
                account: account,
                accountWriteRelays: NostrRelayList.parse(from: relayListEvent).writeRelays,
                fallbackRelays: resolvedRelays
            ),
            signer: signer,
            effects: publishEffects()
        )
    }

    private func publishEffects() -> HomeTimelinePublishEffects {
        HomeTimelinePublishEffects(
            currentAccountID: { [weak self] in self?.account?.pubkey },
            applyContentSnapshot: { [weak self] snapshot in
                self?.applyContentSnapshot(snapshot)
            },
            reloadNewestProjectionWindow: { [weak self] account in
                self?.reloadNewestProjectionWindow(account: account)
            },
            materializeEntries: { [weak self] in
                self?.materializeEntries()
            },
            persistDatabase: { [weak self] account in
                await self?.persistDatabase(account: account)
            },
            setPhase: { [weak self] phase in
                guard let self else { return }
                applyActivityTransition(activityCoordinator.setPhase(phase))
            },
            requestImmediateOutboxDrain: { [weak self] in
                self?.outboxCoordinator.requestImmediateDrain()
            }
        )
    }

    private func activateOutbox(accountID: String) {
        outboxCoordinator.activate(accountID: accountID) { [weak self] in
            self?.publishRelayStatusChange()
        }
    }

    func muteAuthor(of post: TimelinePost) {
        guard let account, let localMutationCoordinator else { return }

        do {
            try localMutationCoordinator.muteAuthor(
                accountID: account.pubkey,
                authorPubkey: post.author.pubkey
            )
            invalidateListEntries()
            materializeEntries()
        } catch {
            applyActivityTransition(
                activityCoordinator.setPhase(.failed("Mute failed: \(error.localizedDescription)"))
            )
        }
    }

    func bookmark(_ post: TimelinePost) {
        guard let account, let localMutationCoordinator else { return }

        do {
            try localMutationCoordinator.bookmarkPost(
                accountID: account.pubkey,
                eventID: post.id
            )
        } catch {
            applyActivityTransition(
                activityCoordinator.setPhase(.failed("Bookmark failed: \(error.localizedDescription)"))
            )
        }
    }

    func isBookmarked(_ post: TimelinePost) -> Bool {
        timelineRepository.isBookmarked(
            eventID: post.id,
            accountID: account?.pubkey
        )
    }

    func listEntries(limit: Int = 500) -> [TimelineFeedEntry] {
        guard let account else { return [] }
        let cacheKey = HomeTimelineListProjectionCache.Key(
            accountID: account.pubkey,
            limit: limit,
            homeContentRevision: resolvedContentRevision
        )
        let readContext = timelineReadContext(applyingHomeFilters: false)
        return listProjectionCache.entries(for: cacheKey) {
            timelineRepository.listEntries(
                limit: limit,
                context: readContext
            )
        }
    }

    func suspendTimelineFilters() {
        guard filterCoordinator.suspend() else { return }
        invalidateListEntries()
        materializeEntries()
    }

    func resumeTimelineFilters() {
        guard filterCoordinator.resume() else { return }
        invalidateListEntries()
        materializeEntries()
    }

    func cancel() {
        accountResetWorkflow.reset(
            HomeTimelineAccountResetInput(
                readBoundaryWrite: homeFeedReadBoundaryWrite(),
                resolvedRelays: resolvedRelays
            ),
            effects: accountResetEffects()
        )
    }

    func post(eventID: String) -> TimelinePost? {
        timelineRepository.post(
            eventID: eventID,
            context: timelineReadContext()
        )
    }

    func profile(pubkey: String, isCurrentUser: Bool = false) -> UserProfile {
        timelineRepository.profile(
            pubkey: pubkey,
            isCurrentUser: isCurrentUser,
            context: timelineReadContext()
        )
    }

    func profilePosts(pubkey: String, limit: Int = 80) -> [TimelinePost] {
        timelineRepository.profilePosts(
            pubkey: pubkey,
            limit: limit,
            context: timelineReadContext()
        )
    }

    func replyAncestors(for post: TimelinePost, limit: Int = 8) -> [TimelinePost] {
        timelineRepository.replyAncestors(
            for: post,
            limit: limit,
            context: timelineReadContext()
        )
    }

    func replies(for post: TimelinePost, limit: Int = 24) -> [TimelinePost] {
        timelineRepository.replies(
            for: post,
            limit: limit,
            context: timelineReadContext()
        )
    }

    private func load(
        account: NostrAccount,
        lifecycle: HomeTimelineLifecycleToken
    ) async {
        await loadWorkflow.loadInitial(
            HomeTimelineInitialLoadRequest(
                account: account,
                lifecycle: lifecycle,
                hasRelayRuntime: relayRuntime != nil
            ),
            effects: loadEffects()
        )
    }

    private func refreshLatest(
        account: NostrAccount,
        lifecycle: HomeTimelineLifecycleToken
    ) async {
        await loadWorkflow.refreshLatest(
            HomeTimelineRefreshRequest(
                account: account,
                lifecycle: lifecycle,
                hasTimelineEvents: !noteEvents.isEmpty,
                hasRelayRuntime: relayRuntime != nil
            ),
            effects: loadEffects()
        )
    }

    private func loadOlder(
        account: NostrAccount,
        lifecycle: HomeTimelineLifecycleToken
    ) async {
        await loadWorkflow.loadOlder(
            HomeTimelineOlderPageRequest(
                account: account,
                lifecycle: lifecycle,
                hasRelayRuntime: relayRuntime != nil
            ),
            effects: loadEffects()
        )
    }

    private func loadEffects() -> HomeTimelineLoadEffects {
        HomeTimelineLoadEffects(
            state: loadStateProviders(),
            application: loadAppEffects()
        )
    }

    private func loadStateProviders() -> HomeTimelineLoadStateProviders {
        HomeTimelineLoadStateProviders(
            hasResolvedRelays: { [weak self] in
                self?.resolvedRelays.isEmpty == false
            },
            currentState: { [weak self] in
                self?.loaderState()
            },
            localBackfillEvents: { [weak self] account, current in
                self?.databaseBackfillEvents(account: account, current: current)
            },
            resolvedRelays: { [weak self] in
                self?.resolvedRelays ?? []
            }
        )
    }

    private func loadAppEffects() -> HomeTimelineLoadAppEffects {
        HomeTimelineLoadAppEffects(
            applyActivityTransition: { [weak self] transition in
                self?.applyActivityTransition(transition)
            },
            installProvisionalRuntimeBootstrap: { [weak self] account in
                self?.installProvisionalRuntimeBootstrapIfNeeded(account: account)
            },
            configureRuntime: { [weak self] account in
                await self?.configureRelayRuntime(account: account)
            },
            restartAccount: { [weak self] account in
                self?.start(account: account)
            },
            recordBackwardDiagnostic: { [weak self] diagnostic in
                self?.recordBackwardLoadDiagnostic(diagnostic)
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
            persistDatabase: { [weak self] account in
                await self?.persistDatabase(account: account)
            },
            recordLoadDiagnostic: { [weak self] diagnostic in
                self?.recordLoadDiagnostic(diagnostic)
            },
            setPhase: { [weak self] phase in
                guard let self else { return }
                applyActivityTransition(activityCoordinator.setPhase(phase))
            }
        )
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
        replaceTimelineState(contentCoordinator.runtimeBootstrapState(
            from: state,
            nip05Resolutions: dependencyCoordinator.nip05Resolutions
        ))
    }

    private func replaceFollowedPubkeys(_ pubkeys: [String]) {
        applyContentSnapshot(contentCoordinator.replaceFollowedPubkeys(pubkeys))
    }

    private func timelineEvent(id: String) -> NostrEvent? {
        noteEvents.first { $0.id == id } ?? timelineRepository.event(id: id)
    }

    @discardableResult
    private func restoreCachedSnapshot(account: NostrAccount) -> Bool {
        stateWorkflow.restoreCachedState(
            accountID: account.pubkey,
            effects: stateWorkflowEffects()
        )
    }

    private func persistDatabase(account: NostrAccount) async {
        await stateWorkflow.persistSnapshot(
            HomeTimelineSnapshotInput(
                accountID: account.pubkey,
                relays: resolvedRelays,
                followedPubkeys: followedPubkeys,
                noteEvents: noteEvents,
                metadataEvents: metadataEvents,
                relayListEvent: relayListEvent,
                contactListEvent: contactListEvent,
                nip05Resolutions: dependencyCoordinator.nip05Resolutions,
                hasMoreOlder: hasMoreOlder
            ),
            effects: stateWorkflowEffects()
        )
    }

    private func stateWorkflowEffects() -> HomeTimelineStateWorkflowEffects {
        HomeTimelineStateWorkflowEffects(
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
            persistenceState: { [weak self] in
                HomeTimelinePersistenceState(
                    accountID: self?.account?.pubkey,
                    followedPubkeys: self?.followedPubkeys ?? []
                )
            },
            hasPendingEvents: { [weak self] in
                self?.pendingEventBuffer.isEmpty == false
            },
            materializeEntries: { [weak self] in
                self?.materializeEntries()
            }
        )
    }

    private func ensureHomeFeedDefinition(account: NostrAccount) {
        homeFeedProjection.ensureDefinition(
            accountID: account.pubkey,
            followedPubkeys: followedPubkeys,
            liveEvents: noteEvents
        )
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
        applyPresentationTransition(
            presentationCoordinator.restoreReadBoundary(postID: boundaryID)
        )
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

        let boundaryID = presentationCoordinator.readBoundaryPostID
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
        materializationCoordinator.reloadNewestProjection(account: account)
    }

    @discardableResult
    private func reloadProjectionWindow(
        account: NostrAccount,
        around anchorEventID: String?,
        mergingWithCurrentWindow: Bool = false
    ) -> Bool {
        materializationCoordinator.reloadProjection(
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
            applyActivityTransition(activityCoordinator.setPhase(.loaded))
        }
    }

    private func startRuntimeSession() {
        let profileRelayURLs = account.map(runtimeRelayURLs(account:)) ?? []
        runtimeWorkflow.startSession(
            HomeTimelineRuntimeSessionRequest(
                account: account,
                profileRelayURLs: profileRelayURLs,
                hasRelayRuntime: relayRuntime != nil,
                isTerminating: accountResetWorkflow.isRuntimeTerminating
            ),
            effects: runtimeSessionEffects()
        )
    }

    private func runtimeSessionEffects() -> HomeTimelineRuntimeSessionEffects {
        HomeTimelineRuntimeSessionEffects(
            isAccountCurrent: { [weak self] accountID in
                self?.account?.pubkey == accountID
            },
            application: runtimeApplicationEffects(),
            packet: runtimePacketEffects(),
            invalidateListEntries: { [weak self] in
                self?.invalidateListEntries()
            },
            scheduleMaterialization: { [weak self] in
                self?.scheduleMaterializeEntries()
            }
        )
    }

    private func runtimePacketEffects(
        isActive: Bool? = nil
    ) -> HomeTimelineRuntimePacketEffects {
        HomeTimelineRuntimePacketEffects(
            context: { [weak self] in
                self?.runtimePacketContext(isActive: isActive)
            },
            setRealtime: { [weak self] isRealtime in
                self?.publishHomeTimelineRealtimeState(isRealtime)
            },
            applyRelayStatusTransition: { [weak self] transition in
                self?.applyRelayStatusTransition(transition)
            },
            handleEvent: { [weak self] relayURL, subscriptionID, event in
                await self?.handleRuntimeEvent(
                    relayURL: relayURL,
                    subscriptionID: subscriptionID,
                    event: event
                )
            },
            handleBackwardCompletion: { [weak self] completion in
                self?.handleBackwardCompletion(completion)
            }
        )
    }

    private func accountStartEffects() -> HomeTimelineAccountStartEffects {
        HomeTimelineAccountStartEffects(
            state: { [unowned self] in
                HomeTimelineAccountStartState(
                    accountID: account?.pubkey,
                    syncPolicy: syncPolicy,
                    restoreProjectionAnchorEventID: restoreProjectionAnchorEventID,
                    hasEntries: !entries.isEmpty,
                    hasResolvedRelays: !resolvedRelays.isEmpty
                )
            },
            application: accountStartApplicationEffects(),
            restoreCachedSnapshot: { [weak self] account in
                self?.restoreCachedSnapshot(account: account) ?? false
            },
            restoredViewport: { [weak self] accountID in
                self?.restoredViewportState(accountID: accountID, timelineKey: "home")
                    .map { HomeTimelineRestoredViewport(anchorEventID: $0.anchorPostID) }
            },
            load: { [weak self] account, lifecycle in
                await self?.load(account: account, lifecycle: lifecycle)
            }
        )
    }

    private func accountStartApplicationEffects(
    ) -> HomeTimelineAccountStartAppEffects {
        HomeTimelineAccountStartAppEffects(
            cancelCurrentAccount: { [weak self] in self?.cancel() },
            applyAccountContextTransition: { [weak self] transition in
                self?.applyAccountContextTransition(transition)
            },
            startRuntimeSession: { [weak self] in self?.startRuntimeSession() },
            ensureHomeFeedDefinition: { [weak self] account in
                self?.ensureHomeFeedDefinition(account: account)
            },
            applyProjectionViewportTransition: { [weak self] transition in
                self?.applyProjectionViewportTransition(transition)
            },
            reloadNewestProjectionWindow: { [weak self] account in
                self?.reloadNewestProjectionWindow(account: account)
            },
            materializeEntries: { [weak self] in self?.materializeEntries() },
            applyRestoreProjectionAnchor: { [weak self] account in
                self?.applyRestoreProjectionAnchorIfPossible(account: account)
            },
            installProvisionalRuntimeBootstrap: { [weak self] account in
                self?.installProvisionalRuntimeBootstrapIfNeeded(account: account)
            },
            restoreHomeFeedReadState: { [weak self] account in
                self?.restoreHomeFeedReadState(account: account)
            },
            setPhase: { [weak self] phase in
                guard let self else { return }
                applyActivityTransition(activityCoordinator.setPhase(phase))
            },
            activateOutbox: { [weak self] accountID in
                self?.activateOutbox(accountID: accountID)
            }
        )
    }

    private func accountResetEffects() -> HomeTimelineAccountResetEffects {
        HomeTimelineAccountResetEffects(
            application: accountResetApplicationEffects(),
            runtimeShutdown: runtimeShutdownEffects()
        )
    }

    private func accountResetApplicationEffects() -> HomeTimelineAccountResetAppEffects {
        HomeTimelineAccountResetAppEffects(
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
            applyProjectionViewportTransition: { [weak self] transition in
                self?.applyProjectionViewportTransition(transition)
            },
            publishRelayStatusChange: { [weak self] in
                self?.publishRelayStatusChange()
            },
            applyAccountContextTransition: { [weak self] transition in
                self?.applyAccountContextTransition(transition)
            }
        )
    }

    private func runtimeShutdownEffects() -> HomeTimelineRuntimeShutdownEffects {
        HomeTimelineRuntimeShutdownEffects(
            currentAccount: { [weak self] in self?.account },
            resetRuntimeState: { [weak self] in
                guard let self else { return }
                runtimeWorkflow.resetSetup()
                resetHomeTimelineRealtime()
            },
            startRuntimeSession: { [weak self] in
                self?.startRuntimeSession()
            },
            configureRuntime: { [weak self] account, forceInstall in
                await self?.configureRelayRuntime(
                    account: account,
                    forceInstall: forceInstall
                )
            }
        )
    }

    private func installProvisionalRuntimeBootstrapIfNeeded(account: NostrAccount) {
        guard relayRuntime != nil, resolvedRelays.isEmpty else { return }
        let provisionalRelays = provisionalDiscoveryRelays(for: account)
        guard !provisionalRelays.isEmpty else { return }
        applyContentSnapshot(
            contentCoordinator.installProvisionalRelays(provisionalRelays)
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
        await runtimeWorkflow.configure(
            HomeTimelineRuntimeSetupRequest(
                account: account,
                defaultRelayURLs: runtimeRelayURLs(account: account),
                policy: syncPolicy,
                hasRelayRuntime: relayRuntime != nil,
                isTerminating: accountResetWorkflow.isRuntimeTerminating,
                forceInstall: forceInstall
            ),
            effects: runtimeSetupEffects()
        )
    }

    private func runtimeSetupEffects() -> HomeTimelineRuntimeSetupEffects {
        HomeTimelineRuntimeSetupEffects(
            setRealtime: { [weak self] isRealtime in
                self?.publishHomeTimelineRealtimeState(isRealtime)
            },
            recordDiagnostic: { [weak self] diagnostic in
                self?.recordRuntimeSetupDiagnostic(diagnostic)
            }
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

    private func resetHomeTimelineRealtime(
        expecting runtimeKeys: Set<RuntimeSubscriptionKey> = []
    ) {
        feedSyncCoordinator.prepareForwardSubscriptions(runtimeKeys)
        publishHomeTimelineRealtimeState()
    }

    private func invalidateHomeTimelineRealtime(for key: RuntimeSubscriptionKey) {
        guard HomeTimelineSyncPlanner.isHomeForwardSubscription(key.subscriptionID) else { return }
        feedSyncCoordinator.invalidateForwardSubscription(key)
        publishHomeTimelineRealtimeState()
    }

    private func invalidateHomeTimelineRealtime(relayURL: String) {
        feedSyncCoordinator.invalidateForwardSubscriptions(relayURL: relayURL)
        publishHomeTimelineRealtimeState()
    }

    private func publishHomeTimelineRealtimeState() {
        publishHomeTimelineRealtimeState(feedSyncCoordinator.isRealtime)
    }

    private func publishHomeTimelineRealtimeState(_ nextIsRealtime: Bool) {
        applyActivityTransition(
            activityCoordinator.setRealtime(nextIsRealtime)
        )
    }

    private func runtimePacketContext(
        isActive: Bool? = nil
    ) -> HomeTimelineRuntimePacketContext {
        HomeTimelineRuntimePacketContext(
            isActive: isActive ?? (
                activityCoordinator.snapshot.phase != .idle
            ),
            accountID: account?.pubkey,
            resolvedRelays: resolvedRelays,
            isCurrentFeedContext: { [weak self] context in
                self?.isCurrentHomeFeedContext(context) == true
            }
        )
    }

    private func handleRuntimeEvent(relayURL: String, subscriptionID: String, event: NostrEvent) async {
        let receivedWhileRealtime = activityCoordinator.snapshot.isRealtime
        await runtimeEventWorkflow.handle(
            HomeTimelineRuntimeEventInput(
                relayURL: relayURL,
                subscriptionID: subscriptionID,
                event: event,
                account: account,
                hasRelayRuntime: relayRuntime != nil,
                receivedWhileRealtime: receivedWhileRealtime
            ),
            effects: runtimeEventEffects()
        )
    }

    private func runtimeEventEffects() -> HomeTimelineRuntimeEventEffects {
        HomeTimelineRuntimeEventEffects(
            presentationState: { [self] receivedWhileRealtime in
                HomeTimelineRuntimeEventPresentationState(
                    receivedWhileRealtime: receivedWhileRealtime,
                    hasRestoreProjectionAnchor: restoreProjectionAnchorEventID != nil,
                    isTimelineAtNewestWindow: isTimelineAtNewestWindow,
                    hasPendingEvents: !pendingEventBuffer.isEmpty
                )
            },
            isAccountCurrent: { [self] accountID in
                account?.pubkey == accountID
            },
            application: runtimeApplicationEffects(),
            recordDiagnostic: { [weak self] diagnostic in
                self?.recordRuntimeSyncEvent(
                    relayURL: diagnostic.relayURL,
                    kind: .partialFailure,
                    subscriptionID: diagnostic.subscriptionID,
                    message: diagnostic.message
                )
            },
            scheduleLinkPreviewResolution: { [weak self] in
                self?.scheduleLinkPreviewResolution()
            }
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
        stateWorkflow.runtimeApplicationEffects(
            state: { [weak self] in
                self?.runtimeApplicationState()
            },
            actions: runtimeApplicationActions(),
            effects: stateWorkflowEffects()
        )
    }

    private func runtimeApplicationState() -> HomeTimelineRuntimeApplicationState {
        HomeTimelineRuntimeApplicationState(
            account: account,
            resolvedRelays: resolvedRelays,
            followedPubkeys: followedPubkeys,
            nip05Resolutions: dependencyCoordinator.nip05Resolutions,
            hasMoreOlder: hasMoreOlder,
            deferredMaterializationDelayNanoseconds:
                presentationCoordinator.defaultDelayNanoseconds * 2
        )
    }

    private func runtimeApplicationActions() -> HomeTimelineRuntimeApplicationActions {
        HomeTimelineRuntimeApplicationActions(
            reloadProjection: { [weak self] account, anchorEventID in
                self?.reloadProjectionWindow(
                    account: account,
                    around: anchorEventID
                )
            },
            requestNewestProjectionReload: { [weak self] in
                self?.presentationCoordinator.requestNewestProjectionReload()
            },
            scheduleMaterialization: { [weak self] delay, allowsRealtimeFollow in
                self?.scheduleMaterializeEntries(
                    delayNanoseconds: delay,
                    allowsRealtimeFollow: allowsRealtimeFollow
                )
            },
            materializeEntries: { [weak self] in
                self?.materializeEntries()
            },
            recordDiagnostic: { [weak self] diagnostic in
                self?.recordRuntimeSyncEvent(
                    relayURL: diagnostic.relayURL,
                    kind: .partialFailure,
                    subscriptionID: nil,
                    message: diagnostic.message
                )
            }
        )
    }

    private func enqueueBackwardDependencies(for event: NostrEvent) async {
        guard let account,
              let lifecycle = lifecycleCoordinator.token(for: account.pubkey)
        else { return }
        _ = await runtimeEventWorkflow.enqueueDependencies(
            for: event,
            context: runtimeEventApplicationContext(
                account: account,
                lifecycle: lifecycle
            ),
            effects: runtimeApplicationEffects()
        )
    }

    private func resolveNIP05IfNeeded(for metadataEvent: NostrEvent) {
        guard let account,
              let lifecycle = lifecycleCoordinator.token(for: account.pubkey)
        else { return }
        runtimeEventWorkflow.resolveNIP05IfNeeded(
            for: metadataEvent,
            context: runtimeEventApplicationContext(
                account: account,
                lifecycle: lifecycle
            ),
            effects: runtimeApplicationEffects()
        )
    }

    private func handleBackwardCompletion(_ completion: NostrBackwardREQCompletion) {
        backwardCompletionWorkflow.handle(
            HomeTimelineBackwardCompletionInput(
                completion: completion,
                account: account
            ),
            effects: backwardCompletionAppEffects()
        )
    }

    private func backwardCompletionAppEffects() -> HomeTimelineBackwardCompletionAppEffects {
        HomeTimelineBackwardCompletionAppEffects(
            applyContentSnapshot: { [weak self] snapshot in
                self?.applyContentSnapshot(snapshot)
            },
            recordDiagnostic: { [weak self] diagnostic in
                self?.recordRuntimeSyncEvent(
                    relayURL: diagnostic.relayURL,
                    kind: .partialFailure,
                    subscriptionID: diagnostic.subscriptionID,
                    message: diagnostic.message
                )
            },
            reloadProjection: { [weak self] account, anchorEventID, mergingWithCurrentWindow in
                self?.reloadProjectionWindow(
                    account: account,
                    around: anchorEventID,
                    mergingWithCurrentWindow: mergingWithCurrentWindow
                )
            },
            materializeEntries: { [weak self] in
                self?.materializeEntries()
            },
            scheduleLinkPreviewResolution: { [weak self] in
                self?.scheduleLinkPreviewResolution()
            },
            incrementRelayStatusRevision: { [weak self] in
                self?.publishRelayStatusChange()
            },
            resolveDependencies: { [weak self] event, account, lifecycle in
                guard let self else { return false }
                return await runtimeEventWorkflow.enqueueDependencies(
                    for: event,
                    context: runtimeEventApplicationContext(
                        account: account,
                        lifecycle: lifecycle
                    ),
                    effects: runtimeApplicationEffects()
                )
            }
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
        timelineRepository.olderBackfillEvents(
            accountID: account.pubkey,
            followedPubkeys: current.followedPubkeys,
            currentEvents: current.noteEvents,
            limit: 1_000
        )
    }

    private func materializeEntries(allowsRealtimeFollow: Bool = false) {
        guard let transition = materializationCoordinator.materialize(
            HomeTimelineMaterializationRequest(
                account: account,
                nip05Resolutions: dependencyCoordinator.nip05Resolutions,
                profileResolutionStates: dependencyCoordinator.profileResolutionStates,
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
        presentationCoordinator.schedule(
            delayNanoseconds: delayNanoseconds,
            allowsRealtimeFollow: allowsRealtimeFollow
        ) { [weak self] allowsRealtimeFollow in
            self?.materializeEntries(allowsRealtimeFollow: allowsRealtimeFollow)
        }
    }

    private func loaderState() -> NostrHomeTimelineState {
        contentCoordinator.loaderState(
            nip05Resolutions: dependencyCoordinator.nip05Resolutions,
            relaySyncEvents: relayStatusCoordinator.events
        )
    }

    private func replaceTimelineState(_ state: NostrHomeTimelineState) {
        stateWorkflow.replace(
            state,
            accountID: account?.pubkey,
            effects: stateWorkflowEffects()
        )
    }

    @discardableResult
    private func rememberLatestMetadataEvent(
        _ event: NostrEvent,
        consultEventStore: Bool = true
    ) -> NostrEvent {
        runtimeEventWorkflow.rememberLatestMetadataEvent(
            event,
            consultEventStore: consultEventStore,
            effects: runtimeApplicationEffects()
        )
    }
}

private extension NostrHomeTimelineStore {
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
        pendingEventBuffer.removeAll { [weak self] publication in
            self?.applyPendingEventCountPublication(publication)
        }
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
        applyListProjectionInvalidation(listProjectionCache.invalidate())
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
        activityCoordinator.activityStatus(
            context: HomeTimelineActivityContext(
                connectedRelayCount: relayStatusCounts.connected,
                plannedRelayCount: relayStatusCounts.planned,
                hasOlderPageRequest: backwardRequestRegistry.hasOlderPageRequest,
                hasGapWork: backwardRequestRegistry.hasGapWork,
                hasBackwardRequests: backwardRequestRegistry.hasRequests,
                hasPendingDependencyWork: dependencyCoordinator.hasPendingWork
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
        publishHomeTimelineRealtimeState(isRealtime)
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
            presentationCoordinator.replaceEntriesForTesting(
                testEntries,
                renderFingerprint: testEntries.map { $0.id.hashValue }
            )
        )
    }

    func testingSetReadBoundary(postID: TimelinePost.ID) {
        applyPresentationTransition(
            presentationCoordinator.setReadBoundaryForTesting(postID: postID)
        )
    }

    func testingSetUnmaterializedNewEventIDs(_ ids: Set<String>) {
        pendingEventBuffer.replaceEventIDs(ids) { [weak self] publication in
            self?.applyPendingEventCountPublication(publication)
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
        applyAccountContextTransition(.activate(
            account,
            syncPolicy: syncPolicy
        ))
        applyContentSnapshot(
            contentCoordinator.replaceFollowedPubkeys(sourceAuthors)
        )
        homeFeedProjection.activateStoredProjection(
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

    func testingHandleFeedSyncRequestStarted(_ attempt: NostrRelayRequestAttempt) async {
        await runtimeWorkflow.handlePacket(
            .requestStarted(attempt),
            effects: runtimePacketEffects(isActive: true)
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
