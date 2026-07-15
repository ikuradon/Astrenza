import AstrenzaCore

@MainActor
protocol HomeTimelineStateApplying: AnyObject {
    @discardableResult
    func restoreCachedState(
        accountID: String,
        handlers: HomeTimelineStateApplicationHandlers
    ) -> Bool

    func replace(
        _ state: NostrHomeTimelineState,
        accountID: String?,
        handlers: HomeTimelineStateApplicationHandlers
    )
}

extension HomeTimelineStateApplicationCoordinator: HomeTimelineStateApplying {}

@MainActor
protocol HomeTimelineStatePersisting: AnyObject {
    @discardableResult
    func persistSnapshot(
        _ input: HomeTimelineSnapshotInput,
        handlers: HomeTimelinePersistenceHandlers
    ) async -> Bool

    @discardableResult
    func persistMetadata(
        _ snapshot: HomeTimelineMetadataSnapshot,
        handlers: HomeTimelinePersistenceHandlers
    ) async -> Bool
}

extension HomeTimelinePersistenceCoordinator: HomeTimelineStatePersisting {}

struct HomeTimelineStateWorkflowEffects: Sendable {
    typealias PresentationTransition = @MainActor @Sendable (
        _ transition: HomeTimelinePresentationTransition
    ) -> Void
    typealias ContentSnapshot = @MainActor @Sendable (
        _ snapshot: HomeTimelineContentSnapshot
    ) -> Void
    typealias RelayStatusSnapshot = @MainActor @Sendable (
        _ snapshot: HomeTimelineRelayStatusSnapshot
    ) -> Void
    typealias RevisionChange = @MainActor @Sendable (_ revision: Int) -> Void
    typealias CountChange = @MainActor @Sendable (_ count: Int) -> Void
    typealias PersistenceState = @MainActor @Sendable () -> HomeTimelinePersistenceState
    typealias PendingEvents = @MainActor @Sendable () -> Bool
    typealias Action = @MainActor @Sendable () -> Void

    let applyPresentationTransition: PresentationTransition
    let applyContentSnapshot: ContentSnapshot
    let applyRelayStatusSnapshot: RelayStatusSnapshot
    let listRevisionChanged: RevisionChange
    let pendingCountChanged: CountChange
    let persistenceState: PersistenceState
    let hasPendingEvents: PendingEvents
    let materializeEntries: Action
}

@MainActor
final class HomeTimelineStateWorkflow {
    private let stateApplication: any HomeTimelineStateApplying
    private let persistence: any HomeTimelineStatePersisting

    init(
        stateApplication: any HomeTimelineStateApplying,
        persistence: any HomeTimelineStatePersisting
    ) {
        self.stateApplication = stateApplication
        self.persistence = persistence
    }

    @discardableResult
    func restoreCachedState(
        accountID: String,
        effects: HomeTimelineStateWorkflowEffects
    ) -> Bool {
        stateApplication.restoreCachedState(
            accountID: accountID,
            handlers: applicationHandlers(effects: effects)
        )
    }

    func replace(
        _ state: NostrHomeTimelineState,
        accountID: String?,
        effects: HomeTimelineStateWorkflowEffects
    ) {
        stateApplication.replace(
            state,
            accountID: accountID,
            handlers: applicationHandlers(effects: effects)
        )
    }

    @discardableResult
    func persistSnapshot(
        _ input: HomeTimelineSnapshotInput,
        effects: HomeTimelineStateWorkflowEffects
    ) async -> Bool {
        await persistence.persistSnapshot(
            input,
            handlers: persistenceHandlers(effects: effects)
        )
    }

    @discardableResult
    func persistMetadata(
        _ snapshot: HomeTimelineMetadataSnapshot,
        effects: HomeTimelineStateWorkflowEffects
    ) async -> Bool {
        await persistence.persistMetadata(
            snapshot,
            handlers: persistenceHandlers(effects: effects)
        )
    }

    private func applicationHandlers(
        effects: HomeTimelineStateWorkflowEffects
    ) -> HomeTimelineStateApplicationHandlers {
        HomeTimelineStateApplicationHandlers(
            applyPresentationTransition: effects.applyPresentationTransition,
            applyContentSnapshot: effects.applyContentSnapshot,
            applyRelayStatusSnapshot: effects.applyRelayStatusSnapshot,
            listRevisionChanged: effects.listRevisionChanged,
            pendingCountChanged: effects.pendingCountChanged
        )
    }

    private func persistenceHandlers(
        effects: HomeTimelineStateWorkflowEffects
    ) -> HomeTimelinePersistenceHandlers {
        HomeTimelinePersistenceHandlers(
            state: effects.persistenceState,
            hasPendingEvents: effects.hasPendingEvents,
            perform: { [weak self] command in
                self?.apply(command, effects: effects)
            }
        )
    }

    private func apply(
        _ command: HomeTimelinePersistenceCommand,
        effects: HomeTimelineStateWorkflowEffects
    ) {
        switch command {
        case .materializeEntries:
            effects.materializeEntries()
        }
    }
}
