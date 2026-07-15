import AstrenzaCore

@MainActor
protocol HomeTimelinePersistenceLifecycle: AnyObject {
    func token(for accountID: String) -> HomeTimelineLifecycleToken?
    func isCurrent(_ token: HomeTimelineLifecycleToken) -> Bool
}

extension HomeTimelineLifecycleCoordinator: HomeTimelinePersistenceLifecycle {}

@MainActor
protocol HomeTimelineSnapshotPersisting: AnyObject {
    func saveSnapshot(
        _ input: HomeTimelineSnapshotInput
    ) async -> HomeTimelineSnapshotSaveReceipt?

    func activateSnapshot(
        _ receipt: HomeTimelineSnapshotSaveReceipt,
        accountID: String,
        followedPubkeys: [String]
    ) -> Bool

    func saveMetadata(_ snapshot: HomeTimelineMetadataSnapshot) async -> Bool
}

extension HomeTimelineSnapshotCoordinator: HomeTimelineSnapshotPersisting {
    func saveSnapshot(
        _ input: HomeTimelineSnapshotInput
    ) async -> HomeTimelineSnapshotSaveReceipt? {
        await persistSnapshot(input)
    }

    func activateSnapshot(
        _ receipt: HomeTimelineSnapshotSaveReceipt,
        accountID: String,
        followedPubkeys: [String]
    ) -> Bool {
        activatePersistedSnapshot(
            receipt,
            accountID: accountID,
            followedPubkeys: followedPubkeys
        )
    }

    func saveMetadata(_ snapshot: HomeTimelineMetadataSnapshot) async -> Bool {
        await persistMetadata(snapshot)
    }
}

struct HomeTimelinePersistenceState: Equatable, Sendable {
    let accountID: String?
    let followedPubkeys: [String]
}

enum HomeTimelinePersistenceCommand: Equatable, Sendable {
    case materializeEntries
}

struct HomeTimelinePersistenceHandlers: Sendable {
    typealias StateProvider = @MainActor @Sendable () -> HomeTimelinePersistenceState
    typealias CommandHandler = @MainActor @Sendable (
        _ command: HomeTimelinePersistenceCommand
    ) -> Void
    typealias PendingEventsProvider = @MainActor @Sendable () -> Bool

    let state: StateProvider
    let hasPendingEvents: PendingEventsProvider
    let perform: CommandHandler
}

@MainActor
final class HomeTimelinePersistenceCoordinator {
    private let snapshotPersistence: any HomeTimelineSnapshotPersisting
    private let lifecycleCoordinator: any HomeTimelinePersistenceLifecycle

    init(
        snapshotPersistence: any HomeTimelineSnapshotPersisting,
        lifecycleCoordinator: any HomeTimelinePersistenceLifecycle
    ) {
        self.snapshotPersistence = snapshotPersistence
        self.lifecycleCoordinator = lifecycleCoordinator
    }

    @discardableResult
    func persistSnapshot(
        _ input: HomeTimelineSnapshotInput,
        handlers: HomeTimelinePersistenceHandlers
    ) async -> Bool {
        guard let lifecycle = lifecycleCoordinator.token(for: input.accountID) else {
            return false
        }
        guard let receipt = await snapshotPersistence.saveSnapshot(input) else {
            return false
        }
        guard !Task.isCancelled,
              lifecycleCoordinator.isCurrent(lifecycle)
        else { return false }

        let state = handlers.state()
        guard state.accountID == input.accountID,
              snapshotPersistence.activateSnapshot(
                receipt,
                accountID: input.accountID,
                followedPubkeys: state.followedPubkeys
              )
        else { return false }

        if !handlers.hasPendingEvents() {
            handlers.perform(.materializeEntries)
        }
        return true
    }

    @discardableResult
    func persistMetadata(
        _ snapshot: HomeTimelineMetadataSnapshot,
        handlers: HomeTimelinePersistenceHandlers
    ) async -> Bool {
        guard let lifecycle = lifecycleCoordinator.token(for: snapshot.accountID) else {
            return false
        }
        guard await snapshotPersistence.saveMetadata(snapshot),
              lifecycleCoordinator.isCurrent(lifecycle)
        else { return false }
        return handlers.state().accountID == snapshot.accountID
    }
}
