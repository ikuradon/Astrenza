import AstrenzaCore
import Foundation
import Testing
@testable import Astrenza

@Suite("Home timeline remote load coordinator")
@MainActor
struct HomeTimelineRemoteLoadCoordinatorTests {
    @Test("Initial load forwards stages and persists relay diagnostics before success")
    func initialLoadForwardsStagesAndPersistsDiagnostics() async {
        let fixture = fixture()
        let recorder = RemoteStateLoaderRecorder()
        let loader = RemoteStateLoaderStub(
            response: .loaded(fixture.state),
            stages: [.resolvingRelayList, .resolvingContactList, .loadingTimeline],
            recorder: recorder
        )
        let persistence = FetchedRelayEventPersistenceStub()
        let coordinator = HomeTimelineRemoteLoadCoordinator(
            loader: loader,
            relayEventPersistence: persistence
        )
        let observation = RemoteLoadObservation()

        let outcome = await coordinator.load(
            .initial(account: fixture.account),
            isCurrent: { true },
            didReceiveStage: { stage in
                observation.stages.append(stage)
            },
            didFetch: {
                observation.didFetch = true
            }
        )

        #expect(outcome == .loaded(fixture.state))
        #expect(observation.stages == [
            .resolvingRelayList,
            .resolvingContactList,
            .loadingTimeline
        ])
        #expect(observation.didFetch)
        #expect(persistence.batches == [fixture.state.relaySyncEvents])
        #expect(await recorder.calls == [.initial])
        #expect(coordinator.bootstrapRelays == ["wss://bootstrap.example"])
    }

    @Test("Every request routes through the matching loader operation")
    func routesEveryRequest() async {
        let fixture = fixture()
        let recorder = RemoteStateLoaderRecorder()
        let loader = RemoteStateLoaderStub(
            response: .loaded(fixture.state),
            stages: [],
            recorder: recorder
        )
        let persistence = FetchedRelayEventPersistenceStub()
        let coordinator = HomeTimelineRemoteLoadCoordinator(
            loader: loader,
            relayEventPersistence: persistence
        )
        let localBackfillEvent = event(idCharacter: "2", createdAt: 50)

        _ = await coordinator.load(
            .initial(account: fixture.account),
            isCurrent: { true }
        )
        _ = await coordinator.load(
            .runtimeBootstrap(account: fixture.account),
            isCurrent: { true }
        )
        _ = await coordinator.load(
            .refresh(account: fixture.account, current: fixture.state),
            isCurrent: { true }
        )
        _ = await coordinator.load(
            .older(
                account: fixture.account,
                current: fixture.state,
                localBackfillEvents: [localBackfillEvent]
            ),
            isCurrent: { true }
        )

        #expect(await recorder.calls == [
            .initial,
            .runtimeBootstrap,
            .refresh(currentEventIDs: fixture.state.noteEvents.map(\.id)),
            .older(
                currentEventIDs: fixture.state.noteEvents.map(\.id),
                localBackfillEventIDs: [localBackfillEvent.id]
            )
        ])
        #expect(persistence.batches.count == 4)
    }

    @Test("Loader failure is returned without persisting diagnostics")
    func loaderFailureSkipsPersistence() async {
        let fixture = fixture()
        let recorder = RemoteStateLoaderRecorder()
        let persistence = FetchedRelayEventPersistenceStub()
        let coordinator = HomeTimelineRemoteLoadCoordinator(
            loader: RemoteStateLoaderStub(
                response: .failed,
                stages: [],
                recorder: recorder
            ),
            relayEventPersistence: persistence
        )
        let observation = RemoteLoadObservation()

        let outcome = await coordinator.load(
            .refresh(account: fixture.account, current: fixture.state),
            isCurrent: { true },
            didFetch: {
                observation.didFetch = true
            }
        )

        #expect(outcome == .failed("remote load unavailable"))
        #expect(!observation.didFetch)
        #expect(persistence.batches.isEmpty)
        #expect(await recorder.calls == [
            .refresh(currentEventIDs: fixture.state.noteEvents.map(\.id))
        ])
    }

    @Test("Lifecycle invalidation suppresses later stages and fetched state")
    func lifecycleInvalidationCancelsDelivery() async {
        let fixture = fixture()
        let recorder = RemoteStateLoaderRecorder()
        let persistence = FetchedRelayEventPersistenceStub()
        let coordinator = HomeTimelineRemoteLoadCoordinator(
            loader: RemoteStateLoaderStub(
                response: .loaded(fixture.state),
                stages: [.resolvingRelayList, .resolvingContactList, .loadingTimeline],
                recorder: recorder
            ),
            relayEventPersistence: persistence
        )
        let liveness = RemoteLoadLiveness()
        let observation = RemoteLoadObservation()

        let outcome = await coordinator.load(
            .runtimeBootstrap(account: fixture.account),
            isCurrent: { liveness.isCurrent },
            didReceiveStage: { stage in
                observation.stages.append(stage)
                liveness.isCurrent = false
            },
            didFetch: {
                observation.didFetch = true
            }
        )

        #expect(outcome == .cancelled)
        #expect(observation.stages == [.resolvingRelayList])
        #expect(!observation.didFetch)
        #expect(persistence.batches.isEmpty)
    }

    @Test("Lifecycle invalidation during diagnostic persistence cancels state delivery")
    func invalidationDuringPersistenceCancelsDelivery() async {
        let fixture = fixture()
        let liveness = RemoteLoadLiveness()
        let persistence = FetchedRelayEventPersistenceStub(
            didPersist: {
                liveness.isCurrent = false
            }
        )
        let coordinator = HomeTimelineRemoteLoadCoordinator(
            loader: RemoteStateLoaderStub(
                response: .loaded(fixture.state),
                stages: [],
                recorder: RemoteStateLoaderRecorder()
            ),
            relayEventPersistence: persistence
        )
        let observation = RemoteLoadObservation()

        let outcome = await coordinator.load(
            .refresh(account: fixture.account, current: fixture.state),
            isCurrent: { liveness.isCurrent },
            didFetch: {
                observation.didFetch = true
            }
        )

        #expect(outcome == .cancelled)
        #expect(observation.didFetch)
        #expect(persistence.batches == [fixture.state.relaySyncEvents])
    }

    @Test("A cancelled task does not start a loader request")
    func cancelledTaskSkipsLoad() async {
        let fixture = fixture()
        let recorder = RemoteStateLoaderRecorder()
        let persistence = FetchedRelayEventPersistenceStub()
        let coordinator = HomeTimelineRemoteLoadCoordinator(
            loader: RemoteStateLoaderStub(
                response: .loaded(fixture.state),
                stages: [],
                recorder: recorder
            ),
            relayEventPersistence: persistence
        )

        let outcome = await Task { @MainActor in
            withUnsafeCurrentTask { task in
                task?.cancel()
            }
            return await coordinator.load(
                .initial(account: fixture.account),
                isCurrent: { true }
            )
        }.value

        #expect(outcome == .cancelled)
        #expect(await recorder.calls.isEmpty)
        #expect(persistence.batches.isEmpty)
    }

    private func fixture() -> Fixture {
        let account = NostrAccount(
            pubkey: String(repeating: "a", count: 64),
            displayIdentifier: "account",
            readOnly: true
        )
        let note = event(idCharacter: "1", createdAt: 100)
        let relaySyncEvent = NostrRelaySyncEventRecord(
            accountID: account.pubkey,
            timelineKey: "home",
            relayURL: "wss://relay.example",
            kind: .eose,
            occurredAt: 200,
            subscriptionID: "astrenza-home",
            eventCount: 1,
            message: "complete"
        )
        return Fixture(
            account: account,
            state: NostrHomeTimelineState(
                relays: ["wss://relay.example"],
                followedPubkeys: [account.pubkey],
                noteEvents: [note],
                metadataEvents: [],
                relaySyncEvents: [relaySyncEvent]
            )
        )
    }

    private func event(idCharacter: Character, createdAt: Int) -> NostrEvent {
        NostrEvent(
            id: String(repeating: String(idCharacter), count: 64),
            pubkey: String(repeating: "a", count: 64),
            createdAt: createdAt,
            kind: 1,
            tags: [],
            content: String(idCharacter),
            sig: String(repeating: "0", count: 128)
        )
    }

    private struct Fixture {
        let account: NostrAccount
        let state: NostrHomeTimelineState
    }
}

private enum RemoteStateLoaderCall: Equatable, Sendable {
    case initial
    case runtimeBootstrap
    case refresh(currentEventIDs: [String])
    case older(currentEventIDs: [String], localBackfillEventIDs: [String]?)
}

private actor RemoteStateLoaderRecorder {
    private(set) var calls: [RemoteStateLoaderCall] = []

    func record(_ call: RemoteStateLoaderCall) {
        calls.append(call)
    }
}

private enum RemoteStateLoaderResponse: Sendable {
    case loaded(NostrHomeTimelineState)
    case failed
}

private struct RemoteStateLoaderStub: HomeTimelineStateLoading {
    let response: RemoteStateLoaderResponse
    let stages: [NostrHomeTimelineLoadStage]
    let recorder: RemoteStateLoaderRecorder
    let bootstrapRelays = ["wss://bootstrap.example"]

    func bootstrapState(
        account: NostrAccount,
        onStage: (@Sendable (NostrHomeTimelineLoadStage) async -> Void)?
    ) async throws -> NostrHomeTimelineState {
        try await load(.runtimeBootstrap, onStage: onStage)
    }

    func initialState(
        account: NostrAccount,
        onStage: (@Sendable (NostrHomeTimelineLoadStage) async -> Void)?
    ) async throws -> NostrHomeTimelineState {
        try await load(.initial, onStage: onStage)
    }

    func refreshedState(
        account: NostrAccount,
        current: NostrHomeTimelineState
    ) async throws -> NostrHomeTimelineState {
        try await load(
            .refresh(currentEventIDs: current.noteEvents.map(\.id)),
            onStage: nil
        )
    }

    func olderState(
        account: NostrAccount,
        current: NostrHomeTimelineState,
        localBackfillEvents: [NostrEvent]?
    ) async throws -> NostrHomeTimelineState {
        try await load(
            .older(
                currentEventIDs: current.noteEvents.map(\.id),
                localBackfillEventIDs: localBackfillEvents?.map(\.id)
            ),
            onStage: nil
        )
    }

    private func load(
        _ call: RemoteStateLoaderCall,
        onStage: (@Sendable (NostrHomeTimelineLoadStage) async -> Void)?
    ) async throws -> NostrHomeTimelineState {
        await recorder.record(call)
        for stage in stages {
            await onStage?(stage)
        }
        switch response {
        case .loaded(let state):
            return state
        case .failed:
            throw RemoteStateLoaderError.unavailable
        }
    }
}

private enum RemoteStateLoaderError: LocalizedError {
    case unavailable

    var errorDescription: String? {
        "remote load unavailable"
    }
}

@MainActor
private final class FetchedRelayEventPersistenceStub: HomeTimelineFetchedRelayEventPersisting {
    typealias DidPersist = @MainActor @Sendable () -> Void

    private(set) var batches: [[NostrRelaySyncEventRecord]] = []
    private let didPersist: DidPersist?

    init(didPersist: DidPersist? = nil) {
        self.didPersist = didPersist
    }

    func persistFetchedEvents(_ events: [NostrRelaySyncEventRecord]) async {
        batches.append(events)
        didPersist?()
    }
}

@MainActor
private final class RemoteLoadObservation {
    var stages: [NostrHomeTimelineLoadStage] = []
    var didFetch = false
}

@MainActor
private final class RemoteLoadLiveness {
    var isCurrent = true
}
