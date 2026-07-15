import AstrenzaCore
import Foundation
import Testing
@testable import Astrenza

@Suite("Home feed projection")
struct HomeFeedProjectionTests {
    @Test("Definition revisions change only when the feed specification changes")
    func definitionRevisionTracksSpecification() throws {
        let accountID = String(repeating: "a", count: 64)
        let first = try #require(HomeFeedProjectionBuilder.definitionPlan(
            accountID: accountID,
            followedPubkeys: ["followed-b", "followed-a"],
            existingDefinition: nil,
            now: 100
        ))

        #expect(first.definition.feedID == "feed:home:\(accountID)")
        #expect(first.definition.revision == 1)
        #expect(first.sourceAuthors == ["followed-b", "followed-a"])
        #expect(first.authors == ["followed-a", "followed-b"])
        #expect(first.requiresProjectionReplacement)

        let unchanged = try #require(HomeFeedProjectionBuilder.definitionPlan(
            accountID: accountID,
            followedPubkeys: ["followed-b", "followed-a"],
            existingDefinition: first.definition,
            now: 200
        ))
        #expect(unchanged.definition == first.definition)
        #expect(!unchanged.requiresProjectionReplacement)

        let changed = try #require(HomeFeedProjectionBuilder.definitionPlan(
            accountID: accountID,
            followedPubkeys: ["followed-c"],
            existingDefinition: first.definition,
            now: 300
        ))
        #expect(changed.definition.revision == 2)
        #expect(changed.definition.specificationHash != first.definition.specificationHash)
        #expect(changed.requiresProjectionReplacement)
    }

    @Test("Membership projection preserves repost subjects and sync provenance")
    func membershipProjectionPreservesProvenance() throws {
        let targetID = String(repeating: "b", count: 64)
        let repost = event(
            id: String(repeating: "c", count: 64),
            kind: 6,
            tags: [["e", "older"], ["e", targetID]]
        )
        let memberships = HomeFeedProjectionBuilder.memberships(
            events: [repost],
            feedID: "feed",
            feedRevision: 3,
            reason: "runtime",
            insertedAt: 10
        )
        let membership = try #require(memberships.first)
        #expect(membership.subjectEventID == targetID)
        #expect(membership.feedRevision == 3)

        let sources = HomeFeedProjectionBuilder.membershipSources(
            events: [repost],
            feedID: "feed",
            feedRevision: 3,
            reason: "runtime",
            insertedAt: 10,
            sourceRequestID: "request"
        )
        #expect(Set(sources.map(\.sourceType)) == ["author", "ingest", "sync-request"])
        #expect(sources.first(where: { $0.sourceType == "sync-request" })?.sourceID == "request")
    }

    @Test("Controller owns projection session state as one boundary")
    @MainActor
    func controllerOwnsProjectionSessionState() throws {
        let accountID = String(repeating: "a", count: 64)
        let plan = try #require(HomeFeedProjectionBuilder.definitionPlan(
            accountID: accountID,
            followedPubkeys: ["followed"],
            existingDefinition: nil,
            now: 100
        ))
        let controller = HomeFeedProjectionController(eventStore: nil)

        controller.activate(
            definition: plan.definition,
            window: nil,
            sourceAuthors: plan.sourceAuthors
        )

        #expect(controller.definition == plan.definition)
        #expect(controller.window == nil)
        #expect(controller.sourceAuthors == plan.sourceAuthors)
        #expect(controller.generation == 1)

        controller.clearWindow()

        #expect(controller.definition == plan.definition)
        #expect(controller.sourceAuthors == plan.sourceAuthors)
        #expect(controller.generation == 2)

        controller.reset()

        #expect(controller.definition == nil)
        #expect(controller.window == nil)
        #expect(controller.sourceAuthors == nil)
        #expect(controller.generation == 3)
    }

    @Test("Controller activates its stored projection window")
    @MainActor
    func controllerActivatesStoredProjectionWindow() async throws {
        let accountID = String(repeating: "a", count: 64)
        let plan = try #require(HomeFeedProjectionBuilder.definitionPlan(
            accountID: accountID,
            followedPubkeys: ["followed"],
            existingDefinition: nil,
            now: 100
        ))
        let storedEvent = event(
            id: String(repeating: "c", count: 64),
            kind: 1,
            tags: []
        )
        let eventStore = try NostrEventStore.inMemory()
        try eventStore.save(events: [storedEvent], receivedAt: 100)
        try eventStore.replaceFeedProjection(
            plan.definition,
            memberships: HomeFeedProjectionBuilder.memberships(
                events: [storedEvent],
                feedID: plan.definition.feedID,
                feedRevision: plan.definition.revision,
                reason: "test",
                insertedAt: 100
            )
        )
        let controller = HomeFeedProjectionController(eventStore: eventStore)

        await controller.activateStoredProjection(
            definition: plan.definition,
            sourceAuthors: plan.sourceAuthors
        )

        #expect(controller.definition == plan.definition)
        #expect(controller.window?.events.map(\.id) == [storedEvent.id])
        #expect(controller.sourceAuthors == plan.sourceAuthors)
        #expect(controller.generation == 1)
    }
}

extension HomeFeedProjectionTests {
    @Test("A newer window request supersedes an older completion")
    @MainActor
    func newerWindowRequestSupersedesOlderCompletion() async throws {
        let accountID = String(repeating: "a", count: 64)
        let plan = try #require(HomeFeedProjectionBuilder.definitionPlan(
            accountID: accountID,
            followedPubkeys: [accountID],
            existingDefinition: nil,
            now: 100
        ))
        let loader = SuspendedHomeFeedWindowLoader()
        let controller = HomeFeedProjectionController(
            eventStore: nil,
            windowLoader: loader
        )
        controller.activate(
            definition: plan.definition,
            window: nil,
            sourceAuthors: plan.sourceAuthors
        )
        let older = window(
            definition: plan.definition,
            event: event(id: String(repeating: "1", count: 64), kind: 1, tags: [])
        )
        let newer = window(
            definition: plan.definition,
            event: event(id: String(repeating: "2", count: 64), kind: 1, tags: [])
        )

        let olderTask = Task {
            await controller.reloadNewest(
                accountID: accountID,
                followedPubkeys: [accountID],
                liveEvents: []
            )
        }
        try #require(await waitForRequestCount(1, loader: loader))
        let newerTask = Task {
            await controller.reloadNewest(
                accountID: accountID,
                followedPubkeys: [accountID],
                liveEvents: []
            )
        }
        try #require(await waitForRequestCount(2, loader: loader))

        #expect(loader.resumeRequest(at: 1, with: newer))
        #expect(await newerTask.value?.events.map(\.id) == newer.events.map(\.id))
        #expect(loader.resumeRequest(at: 0, with: older))
        #expect(await olderTask.value == nil)
        #expect(controller.window?.events.map(\.id) == newer.events.map(\.id))
    }

    @Test("Reset invalidates a pending window request")
    @MainActor
    func resetInvalidatesPendingWindowRequest() async throws {
        let accountID = String(repeating: "a", count: 64)
        let plan = try #require(HomeFeedProjectionBuilder.definitionPlan(
            accountID: accountID,
            followedPubkeys: [accountID],
            existingDefinition: nil,
            now: 100
        ))
        let loader = SuspendedHomeFeedWindowLoader()
        let controller = HomeFeedProjectionController(
            eventStore: nil,
            windowLoader: loader
        )
        controller.activate(
            definition: plan.definition,
            window: nil,
            sourceAuthors: plan.sourceAuthors
        )
        let loaded = window(
            definition: plan.definition,
            event: event(id: String(repeating: "3", count: 64), kind: 1, tags: [])
        )
        let task = Task {
            await controller.reloadNewest(
                accountID: accountID,
                followedPubkeys: [accountID],
                liveEvents: []
            )
        }
        try #require(await waitForRequestCount(1, loader: loader))

        controller.reset()
        #expect(loader.resumeRequest(at: 0, with: loaded))

        #expect(await task.value == nil)
        #expect(controller.definition == nil)
        #expect(controller.window == nil)
    }

    @Test("A newer stored activation supersedes an older completion")
    @MainActor
    func newerStoredActivationSupersedesOlderCompletion() async throws {
        let first = try projectionPlan(accountID: String(repeating: "a", count: 64))
        let second = try projectionPlan(accountID: String(repeating: "b", count: 64))
        let loader = SuspendedHomeFeedWindowLoader()
        let controller = HomeFeedProjectionController(
            eventStore: nil,
            windowLoader: loader
        )
        let firstWindow = window(
            definition: first.definition,
            event: event(id: String(repeating: "4", count: 64), kind: 1, tags: [])
        )
        let secondWindow = window(
            definition: second.definition,
            event: event(id: String(repeating: "5", count: 64), kind: 1, tags: [])
        )

        let firstTask = Task {
            await controller.activateStoredProjection(
                definition: first.definition,
                sourceAuthors: first.sourceAuthors
            )
        }
        try #require(await waitForRequestCount(1, loader: loader))
        let secondTask = Task {
            await controller.activateStoredProjection(
                definition: second.definition,
                sourceAuthors: second.sourceAuthors
            )
        }
        try #require(await waitForRequestCount(2, loader: loader))

        #expect(loader.resumeRequest(at: 1, with: secondWindow))
        await secondTask.value
        #expect(loader.resumeRequest(at: 0, with: firstWindow))
        await firstTask.value

        #expect(controller.definition == second.definition)
        #expect(controller.window?.events.map(\.id) == secondWindow.events.map(\.id))
        #expect(controller.sourceAuthors == second.sourceAuthors)
        #expect(controller.generation == 2)
    }

    @MainActor
    private func waitForRequestCount(
        _ count: Int,
        loader: SuspendedHomeFeedWindowLoader
    ) async -> Bool {
        for _ in 0..<100 {
            if loader.requestCount == count { return true }
            await Task.yield()
        }
        return false
    }

    private func window(
        definition: NostrFeedDefinitionRecord,
        event: NostrEvent
    ) -> NostrFeedWindow {
        NostrFeedWindow(
            definition: definition,
            memberships: HomeFeedProjectionBuilder.memberships(
                events: [event],
                feedID: definition.feedID,
                feedRevision: definition.revision,
                reason: "test",
                insertedAt: 100
            ),
            events: [event],
            deletedItems: [],
            gaps: []
        )
    }

    private func projectionPlan(
        accountID: String
    ) throws -> HomeFeedDefinitionPlan {
        try #require(HomeFeedProjectionBuilder.definitionPlan(
            accountID: accountID,
            followedPubkeys: [accountID],
            existingDefinition: nil,
            now: 100
        ))
    }

    private func event(id: String, kind: Int, tags: [[String]]) -> NostrEvent {
        NostrEvent(
            id: id,
            pubkey: String(repeating: "d", count: 64),
            createdAt: 10,
            kind: kind,
            tags: tags,
            content: "event",
            sig: String(repeating: "e", count: 128)
        )
    }
}

@MainActor
private final class SuspendedHomeFeedWindowLoader: HomeFeedWindowLoading {
    private(set) var requests: [HomeFeedWindowLoadRequest] = []
    private var continuations: [
        Int: CheckedContinuation<NostrFeedWindow?, Never>
    ] = [:]

    var requestCount: Int { requests.count }

    func load(
        _ request: HomeFeedWindowLoadRequest
    ) async -> sending NostrFeedWindow? {
        let index = requests.count
        requests.append(request)
        return await withCheckedContinuation { continuation in
            continuations[index] = continuation
        }
    }

    @discardableResult
    func resumeRequest(
        at index: Int,
        with window: NostrFeedWindow?
    ) -> Bool {
        guard let continuation = continuations.removeValue(forKey: index)
        else { return false }
        continuation.resume(returning: window)
        return true
    }
}
