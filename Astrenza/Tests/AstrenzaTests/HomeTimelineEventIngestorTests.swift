import AstrenzaCore
import Foundation
import Testing
@testable import Astrenza

@Suite("Home timeline event ingestor")
struct HomeTimelineEventIngestorTests {
    @Test("Forward ingest atomically stores current feed membership and provenance")
    func forwardIngestProjectsCurrentFeed() async throws {
        let eventStore = try NostrEventStore.inMemory()
        let definition = try feedDefinition(revision: 3)
        try eventStore.saveFeedDefinition(definition)
        let context = HomeFeedRuntimeContext(definition: definition)
        let note = event(idCharacter: "c")
        let ingestor = HomeTimelineEventIngestor(eventStore: eventStore, now: { 500 })

        let result = try await ingestor.ingestForward(
            HomeTimelineForwardEventIngestRequest(
                event: note,
                relayURL: "wss://relay.example",
                activeFeedContext: context,
                requestContext: context,
                sourceRequestID: "forward-request"
            )
        )

        #expect(result.projectsIntoCurrentFeed)
        #expect(result.eventResult.primaryEventID == note.id)
        let membership = try #require(try eventStore.feedMemberships(
            feedID: definition.feedID,
            revision: definition.revision,
            limit: 1
        ).first)
        #expect(membership.eventID == note.id)
        #expect(membership.reason == HomeTimelineFeedProjectionReason.forward.rawValue)
        #expect(membership.insertedAt == 500)
        let sources = try eventStore.feedMembershipSources(
            feedID: definition.feedID,
            revision: definition.revision,
            eventID: note.id
        )
        #expect(Set(sources.map(\.sourceType)) == ["author", "ingest", "sync-request"])
        #expect(sources.first { $0.sourceType == "sync-request" }?.sourceID == "forward-request")
        #expect(sources.allSatisfy { $0.insertedAt == 500 })
    }

    @Test("Forward ingest saves an event without projecting a stale feed context")
    func forwardIngestRejectsStaleFeedContext() async throws {
        let eventStore = try NostrEventStore.inMemory()
        let definition = try feedDefinition(revision: 3)
        try eventStore.saveFeedDefinition(definition)
        let activeContext = HomeFeedRuntimeContext(definition: definition)
        let staleContext = HomeFeedRuntimeContext(definition: try feedDefinition(revision: 2))
        let note = event(idCharacter: "d")
        let ingestor = HomeTimelineEventIngestor(eventStore: eventStore, now: { 600 })

        let result = try await ingestor.ingestForward(
            HomeTimelineForwardEventIngestRequest(
                event: note,
                relayURL: "wss://relay.example",
                activeFeedContext: activeContext,
                requestContext: staleContext,
                sourceRequestID: "stale-request"
            )
        )

        #expect(!result.projectsIntoCurrentFeed)
        #expect(try eventStore.event(id: note.id) == note)
        #expect(try eventStore.feedMemberships(
            feedID: definition.feedID,
            revision: definition.revision,
            limit: 1
        ).isEmpty)
        #expect(try eventStore.feedMembershipSources(
            feedID: definition.feedID,
            revision: definition.revision,
            eventID: note.id
        ).isEmpty)
    }

    @Test("Backward ingest accepts registry context before request provenance arrives")
    func backwardIngestAcceptsQueuedRequestProvenance() async throws {
        let eventStore = try NostrEventStore.inMemory()
        let definition = try feedDefinition(revision: 3)
        try eventStore.saveFeedDefinition(definition)
        let context = HomeFeedRuntimeContext(definition: definition)
        let note = event(idCharacter: "e")
        let ingestor = HomeTimelineEventIngestor(eventStore: eventStore, now: { 700 })

        let result = try await ingestor.ingestBackward(
            HomeTimelineBackwardEventIngestRequest(
                event: note,
                relayURL: "wss://relay.example",
                activeFeedContext: context,
                requestContext: context,
                activeRequestContext: nil,
                projectionReason: .older,
                sourceRequestID: nil
            )
        )

        #expect(result.projectsIntoCurrentFeed)
        let membership = try #require(try eventStore.feedMemberships(
            feedID: definition.feedID,
            revision: definition.revision,
            limit: 1
        ).first)
        #expect(membership.eventID == note.id)
        #expect(membership.reason == HomeTimelineFeedProjectionReason.older.rawValue)
    }

    @Test("Backward ingest saves an event without projecting a conflicting active request")
    func backwardIngestRejectsConflictingActiveRequest() async throws {
        let eventStore = try NostrEventStore.inMemory()
        let definition = try feedDefinition(revision: 3)
        try eventStore.saveFeedDefinition(definition)
        let context = HomeFeedRuntimeContext(definition: definition)
        let conflictingContext = HomeFeedRuntimeContext(definition: try feedDefinition(revision: 2))
        let note = event(idCharacter: "f")
        let ingestor = HomeTimelineEventIngestor(eventStore: eventStore, now: { 800 })

        let result = try await ingestor.ingestBackward(
            HomeTimelineBackwardEventIngestRequest(
                event: note,
                relayURL: "wss://relay.example",
                activeFeedContext: context,
                requestContext: context,
                activeRequestContext: conflictingContext,
                projectionReason: .gap,
                sourceRequestID: "gap-request"
            )
        )

        #expect(!result.projectsIntoCurrentFeed)
        #expect(try eventStore.event(id: note.id) == note)
        #expect(try eventStore.feedMemberships(
            feedID: definition.feedID,
            revision: definition.revision,
            limit: 1
        ).isEmpty)
    }

    private func feedDefinition(revision: Int) throws -> NostrFeedDefinitionRecord {
        let specification = try JSONEncoder().encode(
            HomeFeedSpecification(authors: [authorID], kinds: [1, 6])
        )
        return NostrFeedDefinitionRecord(
            feedID: "feed:home:\(accountID)",
            accountID: accountID,
            kind: "home",
            specificationJSON: specification,
            specificationHash: "specification",
            revision: revision,
            createdAt: 1,
            updatedAt: 1
        )
    }

    private func event(idCharacter: String) -> NostrEvent {
        NostrEvent(
            id: String(repeating: idCharacter, count: 64),
            pubkey: authorID,
            createdAt: 100,
            kind: 1,
            tags: [],
            content: idCharacter,
            sig: String(repeating: "1", count: 128)
        )
    }

    private var accountID: String { String(repeating: "a", count: 64) }
    private var authorID: String { String(repeating: "b", count: 64) }
}
