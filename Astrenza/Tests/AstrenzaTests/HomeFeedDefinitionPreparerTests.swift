import AstrenzaCore
import Testing
@testable import Astrenza

@Suite("Home feed definition preparer")
struct HomeFeedDefinitionPreparerTests {
    @Test("Rebuild projects stored and live events for allowed authors")
    func rebuildsProjectionFromStoredAndLiveEvents() async throws {
        let eventStore = try NostrEventStore.inMemory()
        let accountID = identifier("a")
        let followed = identifier("b")
        let excluded = identifier("c")
        let storedNote = event(id: "1", pubkey: followed, kind: 1)
        let liveRepost = event(
            id: "2",
            pubkey: followed,
            kind: 6,
            tags: [["e", storedNote.id]]
        )
        let excludedNote = event(id: "3", pubkey: excluded, kind: 1)
        try eventStore.save(
            events: [storedNote, liveRepost, excludedNote],
            receivedAt: 100
        )
        let preparer = HomeFeedDefinitionPreparer(eventStore: eventStore)

        let outcome = await preparer.prepare(request(
            sequence: 1,
            accountID: accountID,
            followedPubkeys: [followed],
            liveEvents: [liveRepost, excludedNote]
        ))

        let preparation = try #require(outcome.preparation)
        #expect(preparation.plan.requiresProjectionReplacement)
        #expect(preparation.plan.sourceAuthors == [followed])
        guard case .replace(let optionalWindow) = preparation.windowUpdate
        else {
            Issue.record("Expected replacement window")
            return
        }
        let window = try #require(optionalWindow)
        #expect(Set(window.events.map(\.id)) == [storedNote.id, liveRepost.id])
        #expect(Set(window.memberships.map(\.reason)) == ["projection-rebuild"])
        #expect(window.memberships.first { $0.eventID == liveRepost.id }?
            .subjectEventID == storedNote.id)
        #expect(try eventStore.feedDefinition(
            feedID: preparation.plan.definition.feedID
        ) == preparation.plan.definition)
    }

    @Test("An unchanged definition repairs an empty projection")
    func repairsEmptyProjection() async throws {
        let eventStore = try NostrEventStore.inMemory()
        let accountID = identifier("d")
        let note = event(id: "4", pubkey: accountID, kind: 1)
        let plan = try #require(HomeFeedProjectionBuilder.definitionPlan(
            accountID: accountID,
            followedPubkeys: [],
            existingDefinition: nil,
            now: 100
        ))
        try eventStore.save(events: [note], receivedAt: 100)
        try eventStore.saveFeedDefinition(plan.definition)
        let preparer = HomeFeedDefinitionPreparer(eventStore: eventStore)

        let outcome = await preparer.prepare(request(
            sequence: 1,
            accountID: accountID,
            followedPubkeys: [],
            liveEvents: [note],
            now: 200
        ))

        let preparation = try #require(outcome.preparation)
        #expect(!preparation.plan.requiresProjectionReplacement)
        #expect(preparation.windowUpdate == .preserve)
        let memberships = try eventStore.feedMemberships(
            feedID: plan.definition.feedID,
            revision: plan.definition.revision,
            limit: 10
        )
        #expect(memberships.map(\.eventID) == [note.id])
        #expect(memberships.map(\.reason) == ["projection-repair"])
    }

    @Test("An older sequence cannot overwrite a newer feed specification")
    func olderSequenceCannotOverwriteNewerSpecification() async throws {
        let eventStore = try NostrEventStore.inMemory()
        let accountID = identifier("e")
        let newerAuthor = identifier("f")
        let olderAuthor = identifier("0")
        let preparer = HomeFeedDefinitionPreparer(eventStore: eventStore)

        let newer = await preparer.prepare(request(
            sequence: 2,
            accountID: accountID,
            followedPubkeys: [newerAuthor],
            liveEvents: []
        ))
        let older = await preparer.prepare(request(
            sequence: 1,
            accountID: accountID,
            followedPubkeys: [olderAuthor],
            liveEvents: []
        ))

        let newerPreparation = try #require(newer.preparation)
        #expect(older == .superseded)
        #expect(try eventStore.feedDefinition(
            feedID: newerPreparation.plan.definition.feedID
        ) == newerPreparation.plan.definition)
    }

    private func request(
        sequence: UInt64,
        accountID: String,
        followedPubkeys: [String],
        liveEvents: [NostrEvent],
        now: Int = 100
    ) -> HomeFeedDefinitionPreparationRequest {
        HomeFeedDefinitionPreparationRequest(
            sequence: sequence,
            accountID: accountID,
            followedPubkeys: followedPubkeys,
            liveEvents: liveEvents,
            now: now,
            windowLimit: 20
        )
    }

    private func event(
        id: Character,
        pubkey: String,
        kind: Int,
        tags: [[String]] = []
    ) -> NostrEvent {
        NostrEvent(
            id: identifier(id),
            pubkey: pubkey,
            createdAt: Int(id.asciiValue ?? 0),
            kind: kind,
            tags: tags,
            content: "event-\(id)",
            sig: String(repeating: "f", count: 128)
        )
    }

    private func identifier(_ character: Character) -> String {
        String(repeating: String(character), count: 64)
    }
}

@Suite("Home feed definition controller ordering")
@MainActor
struct HomeFeedDefinitionControllerTests {
    @Test("Prewarm and concurrent callers share the same definition preparation")
    func prewarmAndConcurrentCallersSharePreparation() async throws {
        let accountID = identifier("a")
        let plan = try definitionPlan(accountID: accountID, followedPubkeys: [])
        let preparer = SuspendedHomeFeedDefinitionPreparer()
        let controller = HomeFeedProjectionController(
            eventStore: nil,
            definitionPreparer: preparer
        )

        controller.prewarmDefinition(
            accountID: accountID,
            followedPubkeys: [],
            liveEvents: [],
            now: 100
        )
        #expect(
            controller.feedID(accountID: accountID) ==
                HomeFeedProjectionBuilder.feedID(accountID: accountID)
        )
        let first = Task {
            await controller.ensureDefinition(
                accountID: accountID,
                followedPubkeys: [],
                liveEvents: [],
                now: 100
            )
        }
        try #require(await waitForRequestCount(1, preparer: preparer))
        let second = Task {
            await controller.ensureDefinition(
                accountID: accountID,
                followedPubkeys: [],
                liveEvents: [],
                now: 100
            )
        }
        await Task.yield()

        #expect(preparer.requestCount == 1)
        #expect(preparer.resumeRequest(at: 0, with: .prepared(.init(
            plan: plan,
            windowUpdate: .replace(nil)
        ))))
        #expect(await first.value)
        #expect(await second.value)
        #expect(controller.definition == plan.definition)
        #expect(controller.generation == 1)
    }

    @Test("A newer definition request supersedes an older completion")
    func newerRequestSupersedesOlderCompletion() async throws {
        let accountID = identifier("b")
        let olderAuthor = identifier("c")
        let newerAuthor = identifier("d")
        let olderPlan = try definitionPlan(
            accountID: accountID,
            followedPubkeys: [olderAuthor]
        )
        let newerPlan = try definitionPlan(
            accountID: accountID,
            followedPubkeys: [newerAuthor]
        )
        let preparer = SuspendedHomeFeedDefinitionPreparer()
        let controller = HomeFeedProjectionController(
            eventStore: nil,
            definitionPreparer: preparer
        )

        let older = Task {
            await controller.ensureDefinition(
                accountID: accountID,
                followedPubkeys: [olderAuthor],
                liveEvents: [],
                now: 100
            )
        }
        try #require(await waitForRequestCount(1, preparer: preparer))
        let newer = Task {
            await controller.ensureDefinition(
                accountID: accountID,
                followedPubkeys: [newerAuthor],
                liveEvents: [],
                now: 100
            )
        }
        try #require(await waitForRequestCount(2, preparer: preparer))

        #expect(preparer.resumeRequest(at: 1, with: .prepared(.init(
            plan: newerPlan,
            windowUpdate: .replace(nil)
        ))))
        #expect(await newer.value)
        #expect(preparer.resumeRequest(at: 0, with: .prepared(.init(
            plan: olderPlan,
            windowUpdate: .replace(nil)
        ))))
        #expect(await older.value == false)
        #expect(controller.definition == newerPlan.definition)
        #expect(controller.sourceAuthors == [newerAuthor])
        #expect(controller.generation == 2)
    }

    private func waitForRequestCount(
        _ count: Int,
        preparer: SuspendedHomeFeedDefinitionPreparer
    ) async -> Bool {
        for _ in 0..<100 {
            if preparer.requestCount == count { return true }
            await Task.yield()
        }
        return false
    }

    private func definitionPlan(
        accountID: String,
        followedPubkeys: [String]
    ) throws -> HomeFeedDefinitionPlan {
        try #require(HomeFeedProjectionBuilder.definitionPlan(
            accountID: accountID,
            followedPubkeys: followedPubkeys,
            existingDefinition: nil,
            now: 100
        ))
    }

    private func identifier(_ character: Character) -> String {
        String(repeating: String(character), count: 64)
    }
}

private extension HomeFeedDefinitionPreparationOutcome {
    var preparation: HomeFeedDefinitionPreparation? {
        guard case .prepared(let preparation) = self else { return nil }
        return preparation
    }
}

@MainActor
private final class SuspendedHomeFeedDefinitionPreparer:
    HomeFeedDefinitionPreparing {
    private(set) var requests: [HomeFeedDefinitionPreparationRequest] = []
    private var continuations: [
        Int: CheckedContinuation<HomeFeedDefinitionPreparationOutcome, Never>
    ] = [:]

    var requestCount: Int { requests.count }

    func plan(
        _ request: HomeFeedDefinitionPlanRequest
    ) async -> HomeFeedDefinitionPlan? {
        nil
    }

    func prepare(
        _ request: HomeFeedDefinitionPreparationRequest
    ) async -> HomeFeedDefinitionPreparationOutcome {
        let index = requests.count
        requests.append(request)
        return await withCheckedContinuation { continuation in
            continuations[index] = continuation
        }
    }

    @discardableResult
    func resumeRequest(
        at index: Int,
        with outcome: HomeFeedDefinitionPreparationOutcome
    ) -> Bool {
        guard let continuation = continuations.removeValue(forKey: index)
        else { return false }
        continuation.resume(returning: outcome)
        return true
    }
}
