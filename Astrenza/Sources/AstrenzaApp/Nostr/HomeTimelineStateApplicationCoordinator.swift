import AstrenzaCore

struct HomeTimelineStateApplicationHandlers: Sendable {
    typealias PresentationTransitionHandler = @MainActor @Sendable (
        _ transition: HomeTimelinePresentationTransition
    ) -> Void
    typealias ContentSnapshotHandler = @MainActor @Sendable (
        _ snapshot: HomeTimelineContentSnapshot
    ) -> Void
    typealias RelayStatusSnapshotHandler = @MainActor @Sendable (
        _ snapshot: HomeTimelineRelayStatusSnapshot
    ) -> Void
    typealias ListProjectionInvalidationHandler = @MainActor @Sendable (
        _ invalidation: HomeTimelineListProjectionInvalidation
    ) -> Void
    typealias PendingEventCountPublicationHandler = @MainActor @Sendable (
        _ publication: HomeTimelinePendingEventCountPublication
    ) -> Void

    let applyPresentationTransition: PresentationTransitionHandler
    let applyContentSnapshot: ContentSnapshotHandler
    let applyRelayStatusSnapshot: RelayStatusSnapshotHandler
    let applyListProjectionInvalidation: ListProjectionInvalidationHandler
    let applyPendingEventCountPublication: PendingEventCountPublicationHandler
}

struct HomeTimelineStateApplicationDependencies: Sendable {
    typealias StateRestorer = @MainActor @Sendable (
        _ accountID: String
    ) async -> NostrHomeTimelineState?
    typealias PresentationReset = @MainActor @Sendable () -> HomeTimelinePresentationTransition
    typealias ContentReplacement = @MainActor @Sendable (
        _ state: NostrHomeTimelineState,
        _ accountID: String?
    ) -> HomeTimelineContentSnapshot
    typealias ContentReset = @MainActor @Sendable () -> HomeTimelineContentSnapshot
    typealias ResolutionReplacement = @MainActor @Sendable (
        _ resolutions: [String: NostrNIP05Resolution]
    ) -> Void
    typealias RelayEventReplacement = @MainActor @Sendable (
        _ events: [NostrRelaySyncEventRecord],
        _ resolvedRelays: [String]
    ) -> HomeTimelineRelayStatusSnapshot
    typealias RelayStatusReset = @MainActor @Sendable (
        _ resolvedRelays: [String]
    ) -> HomeTimelineRelayStatusSnapshot
    typealias Action = @MainActor @Sendable () -> Void
    typealias ListInvalidation = @MainActor @Sendable () -> HomeTimelineListProjectionInvalidation
    typealias PendingEventCountPublicationHandler =
        HomeTimelineStateApplicationHandlers.PendingEventCountPublicationHandler
    typealias PendingEventClear = @MainActor @Sendable (
        _ onCountPublication: @escaping PendingEventCountPublicationHandler
    ) -> Void

    let restoredState: StateRestorer
    let resetPresentation: PresentationReset
    let replaceContent: ContentReplacement
    let resetContent: ContentReset
    let replaceNIP05Resolutions: ResolutionReplacement
    let replaceRelayEvents: RelayEventReplacement
    let resetRelayStatus: RelayStatusReset
    let clearProjectionWindow: Action
    let invalidateListProjection: ListInvalidation
    let clearPendingEvents: PendingEventClear
}

@MainActor
final class HomeTimelineStateApplicationCoordinator {
    private let dependencies: HomeTimelineStateApplicationDependencies

    convenience init(
        snapshotCoordinator: HomeTimelineSnapshotCoordinator,
        presentationCoordinator: HomeTimelinePresentationCoordinator,
        contentCoordinator: HomeTimelineContentCoordinator,
        dependencyCoordinator: HomeTimelineDependencyResolutionCoordinator,
        relayStatusCoordinator: HomeTimelineRelayStatusCoordinator,
        projectionController: HomeFeedProjectionController,
        listProjectionCache: HomeTimelineListProjectionCache,
        pendingEventBuffer: HomeTimelinePendingEventBuffer
    ) {
        self.init(dependencies: HomeTimelineStateApplicationDependencies(
            restoredState: { accountID in
                await snapshotCoordinator.restoredState(accountID: accountID)
            },
            resetPresentation: presentationCoordinator.reset,
            replaceContent: { state, accountID in
                contentCoordinator.replace(with: state, accountID: accountID)
            },
            resetContent: contentCoordinator.reset,
            replaceNIP05Resolutions: dependencyCoordinator.replaceNIP05Resolutions,
            replaceRelayEvents: { events, resolvedRelays in
                relayStatusCoordinator.replaceEvents(
                    events,
                    resolvedRelays: resolvedRelays
                )
            },
            resetRelayStatus: { resolvedRelays in
                relayStatusCoordinator.reset(resolvedRelays: resolvedRelays)
            },
            clearProjectionWindow: projectionController.clearWindow,
            invalidateListProjection: listProjectionCache.invalidate,
            clearPendingEvents: { onCountPublication in
                _ = pendingEventBuffer.removeAll(
                    onCountPublication: onCountPublication
                )
            }
        ))
    }

    init(dependencies: HomeTimelineStateApplicationDependencies) {
        self.dependencies = dependencies
    }

    @discardableResult
    func restoreCachedState(
        accountID: String,
        handlers: HomeTimelineStateApplicationHandlers
    ) async -> Bool {
        let state = await dependencies.restoredState(accountID)
        guard !Task.isCancelled else { return false }
        guard let state else {
            resetMissingCachedState(handlers: handlers)
            return false
        }

        replace(state, accountID: accountID, handlers: handlers)
        return true
    }

    func replace(
        _ state: NostrHomeTimelineState,
        accountID: String?,
        handlers: HomeTimelineStateApplicationHandlers
    ) {
        let content = dependencies.replaceContent(state, accountID)
        handlers.applyContentSnapshot(content)
        dependencies.replaceNIP05Resolutions(state.nip05Resolutions)
        handlers.applyRelayStatusSnapshot(
            dependencies.replaceRelayEvents(
                state.relaySyncEvents,
                content.resolvedRelays
            )
        )
        dependencies.clearProjectionWindow()
        handlers.applyListProjectionInvalidation(
            dependencies.invalidateListProjection()
        )
    }

    private func resetMissingCachedState(
        handlers: HomeTimelineStateApplicationHandlers
    ) {
        handlers.applyPresentationTransition(dependencies.resetPresentation())
        let content = dependencies.resetContent()
        handlers.applyContentSnapshot(content)
        dependencies.replaceNIP05Resolutions([:])
        handlers.applyRelayStatusSnapshot(
            dependencies.resetRelayStatus(content.resolvedRelays)
        )
        dependencies.clearPendingEvents(
            handlers.applyPendingEventCountPublication
        )
    }
}
