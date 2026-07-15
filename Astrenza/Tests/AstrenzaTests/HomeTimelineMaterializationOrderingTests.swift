import AstrenzaCore
import Testing
@testable import Astrenza

@Suite("Home timeline materialization ordering")
@MainActor
struct MaterializationOrderingTests {
    @Test("A superseded worker result cannot publish stale timeline entries")
    func supersededWorkerResultCannotPublish() async throws {
        let account = account()
        let first = event(character: "4", account: account, createdAt: 400)
        let second = event(character: "5", account: account, createdAt: 500)
        let worker = SuspendedMaterializationWorker()
        let system = makeSystem(worker: worker)
        let transitions = MaterializationTransitionProbe()
        install(first, account: account, in: system)

        system.coordinator.materialize(request(account: account)) {
            transitions.values.append($0)
        }
        try #require(await waitUntil {
            worker.requestedEventIDs == [first.id]
        })

        install(second, account: account, in: system)
        system.coordinator.materialize(request(account: account)) {
            transitions.values.append($0)
        }
        try #require(await waitUntil {
            worker.requestedEventIDs == [first.id, second.id]
        })

        #expect(worker.resume(eventID: second.id))
        try #require(await waitUntil { transitions.values.count == 1 })
        #expect(
            transitions.values.first?.snapshot.entries.map(\.id) == [second.id]
        )

        #expect(worker.resume(eventID: first.id))
        for _ in 0..<10 { await Task.yield() }
        #expect(transitions.values.count == 1)
        #expect(system.presentation.snapshot.entries.map(\.id) == [second.id])
    }

    private func makeSystem(
        worker: any HomeTimelineMaterializationWorking
    ) -> MaterializationOrderingSystem {
        let content = HomeTimelineContentCoordinator(eventStore: nil)
        let presentation = HomeTimelinePresentationCoordinator()
        return MaterializationOrderingSystem(
            coordinator: HomeTimelineMaterializationCoordinator(
                contentCoordinator: content,
                filterCoordinator: HomeTimelineFilterCoordinator(
                    eventStore: nil
                ),
                presentationCoordinator: presentation,
                projectionController: HomeFeedProjectionController(
                    eventStore: nil
                ),
                worker: worker
            ),
            content: content,
            presentation: presentation
        )
    }

    private func install(
        _ event: NostrEvent,
        account: NostrAccount,
        in system: MaterializationOrderingSystem
    ) {
        _ = system.content.replace(
            with: NostrHomeTimelineState(
                relays: ["wss://relay.example"],
                followedPubkeys: [account.pubkey],
                noteEvents: [event],
                metadataEvents: []
            ),
            accountID: account.pubkey
        )
    }

    private func waitUntil(
        _ predicate: @escaping @MainActor () -> Bool
    ) async -> Bool {
        for _ in 0..<100 {
            if predicate() { return true }
            await Task.yield()
        }
        return false
    }

    private func request(
        account: NostrAccount
    ) -> HomeTimelineMaterializationRequest {
        HomeTimelineMaterializationRequest(
            account: account,
            nip05Resolutions: [:],
            profileResolutionStates: [:],
            policy: .default(),
            allowsRealtimeFollow: false
        )
    }

    private func account() -> NostrAccount {
        NostrAccount(
            pubkey: String(repeating: "a", count: 64),
            displayIdentifier: "account",
            readOnly: true
        )
    }

    private func event(
        character: Character,
        account: NostrAccount,
        createdAt: Int
    ) -> NostrEvent {
        NostrEvent(
            id: String(repeating: String(character), count: 64),
            pubkey: account.pubkey,
            createdAt: createdAt,
            kind: 1,
            tags: [],
            content: "note-\(character)",
            sig: String(repeating: "0", count: 128)
        )
    }
}

@MainActor
private final class MaterializationTransitionProbe {
    var values: [HomeTimelinePresentationTransition] = []
}

@MainActor
private final class SuspendedMaterializationWorker:
    HomeTimelineMaterializationWorking {
    private(set) var requestedEventIDs: [String] = []
    private var inputs: [String: HomeTimelineMaterializationInput] = [:]
    private var continuations: [
        String: CheckedContinuation<HomeTimelineMaterializedSnapshot?, Never>
    ] = [:]

    func materialize(
        _ input: HomeTimelineMaterializationInput
    ) async -> sending HomeTimelineMaterializedSnapshot? {
        guard let eventID = input.noteEvents.first?.id else { return nil }
        requestedEventIDs.append(eventID)
        inputs[eventID] = input
        return await withCheckedContinuation { continuation in
            continuations[eventID] = continuation
        }
    }

    @discardableResult
    func resume(eventID: String) -> Bool {
        guard let input = inputs.removeValue(forKey: eventID),
              let continuation = continuations.removeValue(forKey: eventID)
        else { return false }
        continuation.resume(returning: snapshot(from: input))
        return true
    }

    private func snapshot(
        from input: HomeTimelineMaterializationInput
    ) -> HomeTimelineMaterializedSnapshot {
        HomeTimelineMaterializedSnapshot(
            entries: input.noteEvents.map(materializedEntry),
            filterStatus: TimelineFilterStatus(
                isSuspended: input.filtersSuspended
            ),
            renderFingerprint: input.noteEvents.map { $0.id.hashValue }
        )
    }

    private func materializedEntry(
        _ event: NostrEvent
    ) -> TimelineFeedEntry {
        .post(TimelinePost(
            id: event.id,
            author: .unresolved(pubkey: event.pubkey),
            avatar: AvatarStyle(
                primary: .clear,
                secondary: .clear,
                symbolName: "person"
            ),
            body: event.content,
            createdAt: event.createdAt,
            replyCount: nil,
            boostCount: nil,
            favoriteCount: nil,
            isLocked: false,
            media: nil,
            context: nil
        ))
    }
}

@MainActor
private struct MaterializationOrderingSystem {
    let coordinator: HomeTimelineMaterializationCoordinator
    let content: HomeTimelineContentCoordinator
    let presentation: HomeTimelinePresentationCoordinator
}
