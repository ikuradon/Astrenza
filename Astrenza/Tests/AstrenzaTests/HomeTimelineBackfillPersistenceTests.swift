import AstrenzaCore
import Foundation
import Testing
@testable import Astrenza

@Suite("Home timeline backfill persistence")
struct HomeTimelineBackfillPersistenceTests {
    @Test("Older page boundary uses the newest received event and request provenance")
    func marksOlderPageBoundary() throws {
        let eventStore = try NostrEventStore.inMemory()
        let definition = try definition()
        try eventStore.saveFeedDefinition(definition)
        let older = event(idCharacter: "b", createdAt: 100)
        let newest = event(idCharacter: "c", createdAt: 200)
        let anchor = event(idCharacter: "d", createdAt: 300)
        try eventStore.save(events: [older, newest, anchor], receivedAt: 10)
        try eventStore.replaceFeedProjection(
            definition,
            memberships: HomeFeedProjectionBuilder.memberships(
                events: [older, newest, anchor],
                feedID: definition.feedID,
                feedRevision: definition.revision,
                reason: "test",
                insertedAt: 10
            )
        )
        try eventStore.beginFeedSyncRequest(
            NostrFeedSyncRequestRecord(
                requestID: "request-2",
                feedID: definition.feedID,
                feedRevision: definition.revision,
                feedSpecificationHash: definition.specificationHash,
                relayURL: "wss://relay.example",
                subscriptionID: "older-request",
                direction: .backward,
                purpose: .older,
                requestedAt: 20
            ),
            filters: [try NostrFeedSyncFilterRecord(
                requestID: "request-2",
                filterIndex: 0,
                filter: ["kinds": .ints([1, 6])]
            )]
        )
        let persistence = HomeTimelineBackfillPersistence(eventStore: eventStore, now: { 500 })
        let request = PendingBackwardRequest(
            feedContext: HomeFeedRuntimeContext(definition: definition),
            isOlderPage: true,
            olderAnchorPostID: anchor.id,
            receivedTimelineEventCount: 3,
            receivedTimelineEventIDs: [older.id, newest.id, older.id],
            sourceRequestIDs: ["request-1", "request-2"]
        )

        #expect(try persistence.markOlderPageBoundaryGap(
            request: request,
            definition: definition
        ))

        let gap = try #require(try eventStore.feedGaps(
            feedID: definition.feedID,
            revision: definition.revision
        ).first)
        #expect(gap.newerEventID == anchor.id)
        #expect(gap.olderEventID == newest.id)
        #expect(gap.sourceRequestID == "request-2")
        #expect(gap.state == .unresolved)
        #expect(gap.updatedAt == 500)
    }

    @Test("Installed gap requests persist the requested state and timestamp")
    func marksInstalledGapRequested() throws {
        let fixture = try fixture(initialState: .unresolved)

        try fixture.persistence.markGapRequested(
            newerEventID: fixture.gap.newerPostID,
            olderEventID: fixture.gap.olderPostID,
            definition: fixture.definition
        )

        let gap = try #require(try fixture.eventStore.feedGaps(
            feedID: fixture.definition.feedID,
            revision: fixture.definition.revision
        ).first)
        #expect(gap.state == .requested)
        #expect(gap.updatedAt == 500)
    }

    @Test("Verified reconciliation resolves the persisted gap")
    func resolvesVerifiedGap() throws {
        let fixture = try fixture(initialState: .requested)
        let outcome = fixture.persistence.apply(
            .verifiedComplete,
            gap: fixture.gap,
            context: fixture.context
        )

        #expect(outcome == .verifiedComplete(resolveFailure: nil))
        let gap = try #require(try fixture.eventStore.feedGaps(
            feedID: fixture.definition.feedID,
            revision: fixture.definition.revision,
            includeResolved: true
        ).first)
        #expect(gap.state == .resolved)
        #expect(gap.resolvedAt == 500)
    }

    @Test("Indeterminate reconciliation restores an unresolved gap")
    func restoresIndeterminateGap() throws {
        let fixture = try fixture(initialState: .requested)
        let outcome = fixture.persistence.apply(
            .indeterminate,
            gap: fixture.gap,
            context: fixture.context
        )

        #expect(outcome == .indeterminate)
        let gap = try #require(try fixture.eventStore.feedGaps(
            feedID: fixture.definition.feedID,
            revision: fixture.definition.revision
        ).first)
        #expect(gap.state == .unresolved)
        #expect(gap.updatedAt == 500)
    }

    @Test("Recovered events are scoped, atomically projected, and returned for dependencies")
    func persistsScopedRecoveredEvents() throws {
        let fixture = try fixture(initialState: .requested)
        let accepted = event(idCharacter: "d", pubkey: authorID, createdAt: 150)
        let rejected = event(idCharacter: "e", pubkey: foreignAuthorID, createdAt: 140)

        let outcome = fixture.persistence.apply(
            .recovered([accepted, rejected]),
            gap: fixture.gap,
            context: fixture.context
        )

        #expect(outcome == .recovered([accepted]))
        #expect(try fixture.eventStore.event(id: accepted.id) == accepted)
        #expect(try fixture.eventStore.event(id: rejected.id) == nil)
        let membership = try #require(try fixture.eventStore.feedMemberships(
            feedID: fixture.definition.feedID,
            revision: fixture.definition.revision,
            limit: 10
        ).first { $0.eventID == accepted.id })
        #expect(membership.eventID == accepted.id)
        #expect(membership.reason == "gap-negentropy")
        let sources = try fixture.eventStore.feedMembershipSources(
            feedID: fixture.definition.feedID,
            revision: fixture.definition.revision,
            eventID: accepted.id
        )
        #expect(Set(sources.map(\.sourceType)) == ["author", "ingest"])
        #expect(sources.allSatisfy { $0.insertedAt == 500 })
        let gap = try #require(try fixture.eventStore.feedGaps(
            feedID: fixture.definition.feedID,
            revision: fixture.definition.revision
        ).first)
        #expect(gap.state == .unresolved)
    }

    @Test("A projection failure rolls back recovered canonical events")
    func rollsBackFailedRecovery() throws {
        let eventStore = try NostrEventStore.inMemory()
        let definition = try definition()
        let context = HomeFeedRuntimeContext(definition: definition)
        let gap = PendingGapBackfill(
            newerPostID: "newer",
            olderPostID: "older",
            direction: .older
        )
        let recovered = event(idCharacter: "f", pubkey: authorID, createdAt: 150)
        let persistence = HomeTimelineBackfillPersistence(eventStore: eventStore, now: { 500 })

        let outcome = persistence.apply(.recovered([recovered]), gap: gap, context: context)

        guard case .recoveryFailed = outcome else {
            Issue.record("Missing feed definition should fail recovered projection")
            return
        }
        #expect(try eventStore.event(id: recovered.id) == nil)
    }

    private func fixture(initialState: NostrFeedGapState) throws -> Fixture {
        let eventStore = try NostrEventStore.inMemory()
        let definition = try definition()
        try eventStore.saveFeedDefinition(definition)
        let context = HomeFeedRuntimeContext(definition: definition)
        let newerBoundary = event(idCharacter: "7", createdAt: 200)
        let olderBoundary = event(idCharacter: "8", createdAt: 100)
        try eventStore.save(events: [newerBoundary, olderBoundary], receivedAt: 50)
        try eventStore.replaceFeedProjection(
            definition,
            memberships: HomeFeedProjectionBuilder.memberships(
                events: [newerBoundary, olderBoundary],
                feedID: definition.feedID,
                feedRevision: definition.revision,
                reason: "test",
                insertedAt: 50
            )
        )
        let gap = PendingGapBackfill(
            newerPostID: newerBoundary.id,
            olderPostID: olderBoundary.id,
            direction: .older
        )
        try eventStore.markFeedGap(
            feedID: definition.feedID,
            revision: definition.revision,
            newerEventID: gap.newerPostID,
            olderEventID: gap.olderPostID,
            state: initialState,
            at: 100
        )
        return Fixture(
            eventStore: eventStore,
            definition: definition,
            context: context,
            gap: gap,
            persistence: HomeTimelineBackfillPersistence(eventStore: eventStore, now: { 500 })
        )
    }

    private func definition() throws -> NostrFeedDefinitionRecord {
        let specification = try JSONEncoder().encode(
            HomeFeedSpecification(authors: [authorID], kinds: [1, 6])
        )
        return NostrFeedDefinitionRecord(
            feedID: "feed:home:\(accountID)",
            accountID: accountID,
            kind: "home",
            specificationJSON: specification,
            specificationHash: "specification",
            revision: 3,
            createdAt: 1,
            updatedAt: 1
        )
    }

    private func event(
        idCharacter: String,
        pubkey: String? = nil,
        createdAt: Int
    ) -> NostrEvent {
        NostrEvent(
            id: String(repeating: idCharacter, count: 64),
            pubkey: pubkey ?? authorID,
            createdAt: createdAt,
            kind: 1,
            tags: [],
            content: idCharacter,
            sig: String(repeating: "1", count: 128)
        )
    }

    private var accountID: String { String(repeating: "a", count: 64) }
    private var authorID: String { String(repeating: "b", count: 64) }
    private var foreignAuthorID: String { String(repeating: "9", count: 64) }

    private struct Fixture {
        let eventStore: NostrEventStore
        let definition: NostrFeedDefinitionRecord
        let context: HomeFeedRuntimeContext
        let gap: PendingGapBackfill
        let persistence: HomeTimelineBackfillPersistence
    }
}
