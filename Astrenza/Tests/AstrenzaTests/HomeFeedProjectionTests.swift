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
    func controllerActivatesStoredProjectionWindow() throws {
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

        controller.activateStoredProjection(
            definition: plan.definition,
            sourceAuthors: plan.sourceAuthors
        )

        #expect(controller.definition == plan.definition)
        #expect(controller.window?.events.map(\.id) == [storedEvent.id])
        #expect(controller.sourceAuthors == plan.sourceAuthors)
        #expect(controller.generation == 1)
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
