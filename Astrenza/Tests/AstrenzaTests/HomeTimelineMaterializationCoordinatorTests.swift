import AstrenzaCore
import Testing
@testable import Astrenza

@Suite("Home timeline materialization coordinator")
@MainActor
struct HomeTimelineMaterializationCoordinatorTests {
    @Test("Materialization publishes one transition and skips an unchanged render")
    func materializesAndSkipsUnchangedRender() async throws {
        let account = account()
        let note = event(idCharacter: "1", pubkey: account.pubkey, createdAt: 100)
        let system = makeSystem(eventStore: nil)
        installContent([note], account: account, in: system)

        let first = await materialize(
            request(account: account, allowsRealtimeFollow: true),
            in: system
        )
        let duplicate = await materialize(
            request(account: account, allowsRealtimeFollow: false),
            in: system
        )

        #expect(first.snapshot.entries.compactMap(\.post?.id) == [note.id])
        #expect(first.changes.contains(.entries))
        #expect(first.changes.contains(.resolvedContentRevision))
        #expect(first.snapshot.realtimeFollowSourceRevision == 1)
        #expect(duplicate.changes.isEmpty)
        #expect(duplicate.snapshot.resolvedContentRevision == 1)
        #expect(system.presentation.snapshot.entries.compactMap(\.post?.id) == [note.id])
    }

    @Test("Materialization applies the current Home filter projection")
    func materializesWithFilterProjection() async throws {
        let eventStore = try NostrEventStore.inMemory()
        let account = account()
        try eventStore.saveFilterRule(NostrFilterRuleRecord(
            ruleID: "warning",
            accountID: account.pubkey,
            kind: .keyword,
            value: "caution",
            presentation: .maskWithWarning,
            scopes: [.home],
            createdAt: 1,
            updatedAt: 1
        ))
        let note = event(
            idCharacter: "2",
            pubkey: account.pubkey,
            createdAt: 200,
            content: "caution content"
        )
        let system = makeSystem(eventStore: eventStore)
        installContent([note], account: account, in: system)

        let transition = await materialize(
            request(account: account),
            in: system
        )

        #expect(transition.snapshot.filterStatus.activeRuleCount == 1)
        #expect(transition.snapshot.filterStatus.warningMatchCount == 1)
        #expect(transition.snapshot.filterStatus.hiddenMatchCount == 0)
        #expect(transition.snapshot.entries.compactMap(\.post).first?.bodyPresentation.collapseReason == .filtered)
    }

    @Test("A requested newest projection reload completes before rendering")
    func reloadsNewestProjectionBeforeRendering() async throws {
        let eventStore = try NostrEventStore.inMemory()
        let account = account()
        let note = event(idCharacter: "3", pubkey: account.pubkey, createdAt: 300)
        let system = makeSystem(eventStore: eventStore)
        try installPersistedProjection([note], account: account, in: system)
        system.presentation.requestNewestProjectionReload()

        let transition = await materialize(
            request(account: account),
            in: system
        )

        #expect(system.projection.window?.events.map(\.id) == [note.id])
        #expect(system.content.noteEvents.map(\.id) == [note.id])
        #expect(transition.snapshot.entries.compactMap(\.post?.id) == [note.id])
        #expect(!system.presentation.hasPendingNewestProjectionReload)
    }

    @Test("Anchored projection reload replaces content with the bounded window")
    func anchoredReloadReplacesContentWindow() async throws {
        let eventStore = try NostrEventStore.inMemory()
        let account = account()
        let events = (1...5).map { index in
            event(
                idCharacter: Character(String(index)),
                pubkey: account.pubkey,
                createdAt: 600 - index * 100
            )
        }
        let projection = HomeFeedProjectionController(
            eventStore: eventStore,
            windowLimit: 2,
            anchorLeadingLimit: 1,
            anchorTrailingLimit: 1
        )
        let system = makeSystem(
            eventStore: eventStore,
            projection: projection
        )
        try installPersistedProjection(events, account: account, in: system)
        let anchor = events[2]

        let didReload = await withCheckedContinuation { continuation in
            system.coordinator.reloadProjection(
                account: account,
                around: anchor.id,
                mergingWithCurrentWindow: false
            ) {
                continuation.resume(returning: $0)
            }
        }

        #expect(didReload)
        let windowEventIDs = try #require(system.projection.window?.events.map(\.id))
        #expect(windowEventIDs.count == 3)
        #expect(windowEventIDs.contains(anchor.id))
        #expect(system.content.noteEvents.map(\.id) == windowEventIDs)
    }

    private func makeSystem(
        eventStore: NostrEventStore?,
        projection: HomeFeedProjectionController? = nil
    ) -> System {
        let content = HomeTimelineContentCoordinator(eventStore: eventStore)
        let filter = HomeTimelineFilterCoordinator(eventStore: eventStore)
        let presentation = HomeTimelinePresentationCoordinator()
        let projection = projection ?? HomeFeedProjectionController(eventStore: eventStore)
        let repository = HomeTimelineRepository(eventStore: eventStore)
        return System(
            coordinator: HomeTimelineMaterializationCoordinator(
                contentCoordinator: content,
                filterCoordinator: filter,
                presentationCoordinator: presentation,
                projectionController: projection,
                worker: HomeTimelineMaterializationWorker(
                    repository: repository,
                    filterProjector: HomeTimelineFilterProjector(
                        eventStore: eventStore
                    )
                )
            ),
            content: content,
            presentation: presentation,
            projection: projection,
            eventStore: eventStore
        )
    }

    private func materialize(
        _ request: HomeTimelineMaterializationRequest,
        in system: System
    ) async -> HomeTimelinePresentationTransition {
        await withCheckedContinuation { continuation in
            system.coordinator.materialize(request) { transition in
                continuation.resume(returning: transition)
            }
        }
    }

    private func installContent(
        _ events: [NostrEvent],
        account: NostrAccount,
        in system: System
    ) {
        _ = system.content.replace(
            with: state(events: events, account: account),
            accountID: account.pubkey
        )
    }

    private func installPersistedProjection(
        _ events: [NostrEvent],
        account: NostrAccount,
        in system: System
    ) throws {
        let eventStore = try #require(system.eventStore)
        let plan = try #require(HomeFeedProjectionBuilder.definitionPlan(
            accountID: account.pubkey,
            followedPubkeys: [account.pubkey],
            existingDefinition: nil,
            now: 10
        ))
        let state = state(events: events, account: account)
        try eventStore.saveHomeFeedState(
            state,
            accountID: account.pubkey,
            definition: plan.definition,
            memberships: HomeFeedProjectionBuilder.memberships(
                events: events,
                feedID: plan.definition.feedID,
                feedRevision: plan.definition.revision,
                reason: "test",
                insertedAt: 10
            ),
            savedAt: 10
        )
        _ = system.content.replace(with: state, accountID: account.pubkey)
    }

    private func state(
        events: [NostrEvent],
        account: NostrAccount
    ) -> NostrHomeTimelineState {
        NostrHomeTimelineState(
            relays: ["wss://relay.example"],
            followedPubkeys: [account.pubkey],
            noteEvents: events,
            metadataEvents: []
        )
    }

    private func request(
        account: NostrAccount,
        allowsRealtimeFollow: Bool = false
    ) -> HomeTimelineMaterializationRequest {
        HomeTimelineMaterializationRequest(
            account: account,
            nip05Resolutions: [:],
            profileResolutionStates: [:],
            policy: .default(networkType: .unknown, lowPowerMode: false),
            allowsRealtimeFollow: allowsRealtimeFollow
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
        idCharacter: Character,
        pubkey: String,
        createdAt: Int,
        content: String = "note"
    ) -> NostrEvent {
        NostrEvent(
            id: String(repeating: String(idCharacter), count: 64),
            pubkey: pubkey,
            createdAt: createdAt,
            kind: 1,
            tags: [],
            content: content,
            sig: String(repeating: "0", count: 128)
        )
    }

    private struct System {
        let coordinator: HomeTimelineMaterializationCoordinator
        let content: HomeTimelineContentCoordinator
        let presentation: HomeTimelinePresentationCoordinator
        let projection: HomeFeedProjectionController
        let eventStore: NostrEventStore?
    }
}
