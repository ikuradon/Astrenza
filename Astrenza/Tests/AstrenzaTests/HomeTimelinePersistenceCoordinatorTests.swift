import AstrenzaCore
import Foundation
import Testing
@testable import Astrenza

@Suite("Home timeline persistence coordinator")
@MainActor
struct HomeTimelinePersistenceCoordinatorTests {
    @Test("Snapshot persistence does not start without an account lifecycle")
    func snapshotRequiresLifecycle() async {
        let probe = PersistenceProbe()
        probe.lifecycleToken = nil
        let coordinator = makeCoordinator(probe)

        let didActivate = await coordinator.persistSnapshot(
            snapshotInput(),
            handlers: probe.handlers()
        )

        #expect(!didActivate)
        #expect(probe.events == [.token("account")])
    }

    @Test("A failed snapshot save stops before lifecycle validation")
    func failedSnapshotStopsBeforeValidation() async {
        let probe = PersistenceProbe()
        let coordinator = makeCoordinator(probe)

        let didActivate = await coordinator.persistSnapshot(
            snapshotInput(),
            handlers: probe.handlers()
        )

        #expect(!didActivate)
        #expect(probe.events == [
            .token("account"),
            .saveSnapshot("account")
        ])
    }

    @Test("Cancellation after snapshot I/O stops before lifecycle validation")
    func cancelledSnapshotStopsBeforeValidation() async {
        let probe = PersistenceProbe()
        probe.snapshotReceipt = receipt()
        probe.cancelSnapshotTask = true
        let coordinator = makeCoordinator(probe)

        let didActivate = await Task { @MainActor in
            await coordinator.persistSnapshot(
                snapshotInput(),
                handlers: probe.handlers()
            )
        }.value

        #expect(!didActivate)
        #expect(probe.events == [
            .token("account"),
            .saveSnapshot("account")
        ])
    }

    @Test("A stale lifecycle does not read current Store state")
    func staleSnapshotDoesNotReadState() async {
        let probe = PersistenceProbe()
        probe.snapshotReceipt = receipt()
        probe.isLifecycleCurrent = false
        let coordinator = makeCoordinator(probe)

        let didActivate = await coordinator.persistSnapshot(
            snapshotInput(),
            handlers: probe.handlers()
        )

        #expect(!didActivate)
        #expect(probe.events == [
            .token("account"),
            .saveSnapshot("account"),
            .isCurrent(probe.requiredLifecycleToken)
        ])
    }

    @Test("An account switch after snapshot I/O prevents activation")
    func switchedAccountPreventsActivation() async {
        let probe = PersistenceProbe()
        probe.snapshotReceipt = receipt()
        probe.currentState = HomeTimelinePersistenceState(
            accountID: "other",
            followedPubkeys: ["latest-follow"]
        )
        let coordinator = makeCoordinator(probe)

        let didActivate = await coordinator.persistSnapshot(
            snapshotInput(),
            handlers: probe.handlers()
        )

        #expect(!didActivate)
        #expect(probe.events == [
            .token("account"),
            .saveSnapshot("account"),
            .isCurrent(probe.requiredLifecycleToken),
            .state(probe.currentState)
        ])
    }

    @Test("A rejected snapshot activation does not materialize entries")
    func rejectedActivationDoesNotMaterialize() async {
        let probe = PersistenceProbe()
        probe.snapshotReceipt = receipt()
        probe.activatesSnapshot = false
        let coordinator = makeCoordinator(probe)

        let didActivate = await coordinator.persistSnapshot(
            snapshotInput(),
            handlers: probe.handlers()
        )

        #expect(!didActivate)
        #expect(probe.events == expectedSnapshotEvents(probe))
    }

    @Test(
        "Successful activation uses latest follows and materializes only without pending events",
        arguments: [false, true]
    )
    func successfulActivationRespectsPendingEvents(hasPendingEvents: Bool) async {
        let probe = PersistenceProbe()
        probe.snapshotReceipt = receipt()
        probe.currentState = HomeTimelinePersistenceState(
            accountID: "account",
            followedPubkeys: ["latest-follow"]
        )
        probe.hasPendingEvents = hasPendingEvents
        let coordinator = makeCoordinator(probe)

        let didActivate = await coordinator.persistSnapshot(
            snapshotInput(),
            handlers: probe.handlers()
        )
        var expected = expectedSnapshotEvents(probe)
        expected.append(.pendingEvents(hasPendingEvents))
        if !hasPendingEvents {
            expected.append(.command(.materializeEntries))
        }

        #expect(didActivate)
        #expect(probe.events == expected)
    }

    @Test("Metadata persistence does not start without an account lifecycle")
    func metadataRequiresLifecycle() async {
        let probe = PersistenceProbe()
        probe.lifecycleToken = nil
        let coordinator = makeCoordinator(probe)

        let didPersist = await coordinator.persistMetadata(
            metadataSnapshot(),
            handlers: probe.handlers()
        )

        #expect(!didPersist)
        #expect(probe.events == [.token("account")])
    }

    @Test("A failed metadata save stops before lifecycle validation")
    func failedMetadataStopsBeforeValidation() async {
        let probe = PersistenceProbe()
        probe.savesMetadata = false
        let coordinator = makeCoordinator(probe)

        let didPersist = await coordinator.persistMetadata(
            metadataSnapshot(),
            handlers: probe.handlers()
        )

        #expect(!didPersist)
        #expect(probe.events == [
            .token("account"),
            .saveMetadata("account")
        ])
    }

    @Test("A stale metadata save does not read current Store state")
    func staleMetadataDoesNotReadState() async {
        let probe = PersistenceProbe()
        probe.isLifecycleCurrent = false
        let coordinator = makeCoordinator(probe)

        let didPersist = await coordinator.persistMetadata(
            metadataSnapshot(),
            handlers: probe.handlers()
        )

        #expect(!didPersist)
        #expect(probe.events == [
            .token("account"),
            .saveMetadata("account"),
            .isCurrent(probe.requiredLifecycleToken)
        ])
    }

    @Test(
        "A successful metadata save remains valid only for the current account",
        arguments: ["account", "other"]
    )
    func metadataRequiresCurrentAccount(currentAccountID: String) async {
        let probe = PersistenceProbe()
        probe.currentState = HomeTimelinePersistenceState(
            accountID: currentAccountID,
            followedPubkeys: []
        )
        let coordinator = makeCoordinator(probe)

        let didPersist = await coordinator.persistMetadata(
            metadataSnapshot(),
            handlers: probe.handlers()
        )

        #expect(didPersist == (currentAccountID == "account"))
        #expect(probe.events == [
            .token("account"),
            .saveMetadata("account"),
            .isCurrent(probe.requiredLifecycleToken),
            .state(probe.currentState)
        ])
    }

    private func makeCoordinator(
        _ probe: PersistenceProbe
    ) -> HomeTimelinePersistenceCoordinator {
        HomeTimelinePersistenceCoordinator(
            snapshotPersistence: probe,
            lifecycleCoordinator: probe
        )
    }

    private func expectedSnapshotEvents(
        _ probe: PersistenceProbe
    ) -> [PersistenceProbe.Event] {
        [
            .token("account"),
            .saveSnapshot("account"),
            .isCurrent(probe.requiredLifecycleToken),
            .state(probe.currentState),
            .activateSnapshot(
                accountID: "account",
                followedPubkeys: probe.currentState.followedPubkeys
            )
        ]
    }

    private func snapshotInput() -> HomeTimelineSnapshotInput {
        HomeTimelineSnapshotInput(
            accountID: "account",
            relays: ["wss://relay.example"],
            followedPubkeys: ["captured-follow"],
            noteEvents: [],
            metadataEvents: [],
            relayListEvent: nil,
            contactListEvent: nil,
            nip05Resolutions: [:],
            hasMoreOlder: true
        )
    }

    private func metadataSnapshot() -> HomeTimelineMetadataSnapshot {
        HomeTimelineMetadataSnapshot(
            accountID: "account",
            relays: ["wss://relay.example"],
            followedPubkeys: ["captured-follow"],
            nip05Resolutions: [:],
            hasMoreOlder: true
        )
    }

    private func receipt() -> HomeTimelineSnapshotSaveReceipt {
        HomeTimelineSnapshotSaveReceipt(
            definition: NostrFeedDefinitionRecord(
                feedID: "feed:home:account",
                accountID: "account",
                kind: "home",
                specificationJSON: Data(),
                specificationHash: "specification",
                revision: 1,
                createdAt: 100,
                updatedAt: 100
            ),
            sourceAuthors: ["captured-follow"],
            projectionGeneration: 1,
            window: nil,
            savedAt: 100
        )
    }
}

@MainActor
private final class PersistenceProbe:
    HomeTimelinePersistenceLifecycle,
    HomeTimelineSnapshotPersisting {
    enum Event: Equatable {
        case token(String)
        case saveSnapshot(String)
        case saveMetadata(String)
        case isCurrent(HomeTimelineLifecycleToken)
        case state(HomeTimelinePersistenceState)
        case activateSnapshot(accountID: String, followedPubkeys: [String])
        case pendingEvents(Bool)
        case command(HomeTimelinePersistenceCommand)
    }

    var lifecycleToken: HomeTimelineLifecycleToken? = HomeTimelineLifecycleToken(
        accountID: "account",
        generation: 1
    )
    var isLifecycleCurrent = true
    var snapshotReceipt: HomeTimelineSnapshotSaveReceipt?
    var activatesSnapshot = true
    var savesMetadata = true
    var cancelSnapshotTask = false
    var currentState = HomeTimelinePersistenceState(
        accountID: "account",
        followedPubkeys: ["latest-follow"]
    )
    var hasPendingEvents = false
    private(set) var events: [Event] = []

    var requiredLifecycleToken: HomeTimelineLifecycleToken {
        lifecycleToken ?? HomeTimelineLifecycleToken(
            accountID: "missing",
            generation: 0
        )
    }

    func token(for accountID: String) -> HomeTimelineLifecycleToken? {
        events.append(.token(accountID))
        return lifecycleToken
    }

    func isCurrent(_ token: HomeTimelineLifecycleToken) -> Bool {
        events.append(.isCurrent(token))
        return isLifecycleCurrent
    }

    func saveSnapshot(
        _ input: HomeTimelineSnapshotInput
    ) async -> HomeTimelineSnapshotSaveReceipt? {
        events.append(.saveSnapshot(input.accountID))
        if cancelSnapshotTask {
            withUnsafeCurrentTask { task in
                task?.cancel()
            }
        }
        return snapshotReceipt
    }

    func activateSnapshot(
        _ receipt: HomeTimelineSnapshotSaveReceipt,
        accountID: String,
        followedPubkeys: [String]
    ) async -> Bool {
        _ = receipt
        events.append(.activateSnapshot(
            accountID: accountID,
            followedPubkeys: followedPubkeys
        ))
        return activatesSnapshot
    }

    func saveMetadata(_ snapshot: HomeTimelineMetadataSnapshot) async -> Bool {
        events.append(.saveMetadata(snapshot.accountID))
        return savesMetadata
    }

    func handlers() -> HomeTimelinePersistenceHandlers {
        HomeTimelinePersistenceHandlers(
            state: { [self] in
                events.append(.state(currentState))
                return currentState
            },
            hasPendingEvents: { [self] in
                events.append(.pendingEvents(hasPendingEvents))
                return hasPendingEvents
            },
            perform: { [self] command in
                events.append(.command(command))
            }
        )
    }
}
