import AstrenzaCore
import Testing
@testable import Astrenza

@Suite("Home timeline state workflow")
@MainActor
struct HomeTimelineStateWorkflowTests {
    @Test("Restore and replacement stay behind the state effect boundary")
    func stateApplicationRoutesEffects() {
        let fixture = StateWorkflowFixture()

        let didRestore = fixture.workflow.restoreCachedState(
            accountID: "account",
            effects: fixture.effects
        )
        fixture.workflow.replace(
            fixture.timelineState,
            accountID: "replacement-account",
            effects: fixture.effects
        )

        #expect(didRestore)
        #expect(fixture.stateApplication.restoredAccountID == "account")
        #expect(fixture.stateApplication.replacementAccountID == "replacement-account")
        #expect(fixture.stateApplication.replacementRelays == fixture.timelineState.relays)
        #expect(fixture.probe.events == [
            .presentationTransition,
            .contentSnapshot(["wss://effective.example"]),
            .relayStatusSnapshot(1),
            .listRevision(41),
            .pendingCount(3)
        ])
    }

    @Test("Snapshot persistence routes current state, pending work, and materialization")
    func snapshotPersistenceRoutesEffects() async {
        let fixture = StateWorkflowFixture()

        let didPersist = await fixture.workflow.persistSnapshot(
            fixture.snapshotInput,
            effects: fixture.effects
        )

        #expect(didPersist)
        #expect(fixture.persistence.snapshotAccountID == "account")
        #expect(fixture.persistence.observedStates == [fixture.persistenceState])
        #expect(fixture.persistence.observedPendingEvents == [true])
        #expect(fixture.probe.events == [
            .persistenceState,
            .pendingEvents,
            .materializeEntries
        ])
    }

    @Test("Metadata persistence preserves the coordinator result and current state")
    func metadataPersistencePreservesResult() async {
        let fixture = StateWorkflowFixture(metadataResult: false)

        let didPersist = await fixture.workflow.persistMetadata(
            fixture.metadataSnapshot,
            effects: fixture.effects
        )

        #expect(!didPersist)
        #expect(fixture.persistence.metadataAccountID == "account")
        #expect(fixture.persistence.observedStates == [fixture.persistenceState])
        #expect(fixture.probe.events == [.persistenceState])
    }
}

@MainActor
private final class StateApplicationSpy: HomeTimelineStateApplying {
    var restoredAccountID: String?
    var replacementAccountID: String?
    var replacementRelays: [String] = []
    var restoreResult = true

    func restoreCachedState(
        accountID: String,
        handlers: HomeTimelineStateApplicationHandlers
    ) -> Bool {
        restoredAccountID = accountID
        handlers.applyPresentationTransition(presentationTransition)
        handlers.applyContentSnapshot(contentSnapshot)
        handlers.applyRelayStatusSnapshot(relayStatusSnapshot)
        handlers.applyListProjectionInvalidation(
            HomeTimelineListProjectionInvalidation(revision: 41)
        )
        handlers.pendingCountChanged(3)
        return restoreResult
    }

    func replace(
        _ state: NostrHomeTimelineState,
        accountID: String?,
        handlers: HomeTimelineStateApplicationHandlers
    ) {
        _ = handlers
        replacementAccountID = accountID
        replacementRelays = state.relays
    }

    private var presentationTransition: HomeTimelinePresentationTransition {
        HomeTimelinePresentationTransition(
            snapshot: HomeTimelinePresentationSnapshot(
                entries: [],
                filterStatus: TimelineFilterStatus(),
                materializedUnreadCount: 0,
                visibleUnreadBadgeCount: 0,
                resolvedContentRevision: 0,
                realtimeFollowSourceRevision: nil
            ),
            changes: [],
            didChangeReadState: false
        )
    }

    private var contentSnapshot: HomeTimelineContentSnapshot {
        HomeTimelineContentSnapshot(
            resolvedRelays: ["wss://effective.example"],
            followedPubkeys: [],
            noteEvents: [],
            metadataEvents: [],
            relayListEvent: nil,
            contactListEvent: nil,
            hasMoreOlder: true
        )
    }

    private var relayStatusSnapshot: HomeTimelineRelayStatusSnapshot {
        HomeTimelineRelayStatusSnapshot(
            runtimeStates: [:],
            connectedRelayCount: 0,
            plannedRelayCount: 1
        )
    }
}

@MainActor
private final class StatePersistenceSpy: HomeTimelineStatePersisting {
    var snapshotAccountID: String?
    var metadataAccountID: String?
    var observedStates: [HomeTimelinePersistenceState] = []
    var observedPendingEvents: [Bool] = []
    let snapshotResult: Bool
    let metadataResult: Bool

    init(snapshotResult: Bool = true, metadataResult: Bool = true) {
        self.snapshotResult = snapshotResult
        self.metadataResult = metadataResult
    }

    func persistSnapshot(
        _ input: HomeTimelineSnapshotInput,
        handlers: HomeTimelinePersistenceHandlers
    ) async -> Bool {
        snapshotAccountID = input.accountID
        observedStates.append(handlers.state())
        observedPendingEvents.append(handlers.hasPendingEvents())
        handlers.perform(.materializeEntries)
        return snapshotResult
    }

    func persistMetadata(
        _ snapshot: HomeTimelineMetadataSnapshot,
        handlers: HomeTimelinePersistenceHandlers
    ) async -> Bool {
        metadataAccountID = snapshot.accountID
        observedStates.append(handlers.state())
        return metadataResult
    }
}

@MainActor
private final class StateWorkflowProbe {
    enum Event: Equatable {
        case presentationTransition
        case contentSnapshot([String])
        case relayStatusSnapshot(Int)
        case listRevision(Int)
        case pendingCount(Int)
        case persistenceState
        case pendingEvents
        case materializeEntries
    }

    var events: [Event] = []
}

@MainActor
private struct StateWorkflowFixture {
    let stateApplication = StateApplicationSpy()
    let persistence: StatePersistenceSpy
    let probe = StateWorkflowProbe()
    let workflow: HomeTimelineStateWorkflow

    init(
        snapshotResult: Bool = true,
        metadataResult: Bool = true
    ) {
        self.persistence = StatePersistenceSpy(
            snapshotResult: snapshotResult,
            metadataResult: metadataResult
        )
        self.workflow = HomeTimelineStateWorkflow(
            stateApplication: stateApplication,
            persistence: persistence
        )
    }

    var persistenceState: HomeTimelinePersistenceState {
        HomeTimelinePersistenceState(
            accountID: "account",
            followedPubkeys: ["followed"]
        )
    }

    var effects: HomeTimelineStateWorkflowEffects {
        HomeTimelineStateWorkflowEffects(
            applyPresentationTransition: { [probe] _ in
                probe.events.append(.presentationTransition)
            },
            applyContentSnapshot: { [probe] snapshot in
                probe.events.append(.contentSnapshot(snapshot.resolvedRelays))
            },
            applyRelayStatusSnapshot: { [probe] snapshot in
                probe.events.append(.relayStatusSnapshot(snapshot.plannedRelayCount))
            },
            applyListProjectionInvalidation: { [probe] invalidation in
                probe.events.append(.listRevision(invalidation.revision))
            },
            pendingCountChanged: { [probe] count in
                probe.events.append(.pendingCount(count))
            },
            persistenceState: { [probe, persistenceState] in
                probe.events.append(.persistenceState)
                return persistenceState
            },
            hasPendingEvents: { [probe] in
                probe.events.append(.pendingEvents)
                return true
            },
            materializeEntries: { [probe] in
                probe.events.append(.materializeEntries)
            }
        )
    }

    var timelineState: NostrHomeTimelineState {
        NostrHomeTimelineState(
            relays: ["wss://incoming.example"],
            followedPubkeys: [],
            noteEvents: [],
            metadataEvents: [],
            nip05Resolutions: [:],
            hasMoreOlder: true,
            relaySyncEvents: []
        )
    }

    var snapshotInput: HomeTimelineSnapshotInput {
        HomeTimelineSnapshotInput(
            accountID: "account",
            relays: [],
            followedPubkeys: [],
            noteEvents: [],
            metadataEvents: [],
            relayListEvent: nil,
            contactListEvent: nil,
            nip05Resolutions: [:],
            hasMoreOlder: true
        )
    }

    var metadataSnapshot: HomeTimelineMetadataSnapshot {
        HomeTimelineMetadataSnapshot(
            accountID: "account",
            relays: [],
            followedPubkeys: [],
            nip05Resolutions: [:],
            hasMoreOlder: true
        )
    }
}
