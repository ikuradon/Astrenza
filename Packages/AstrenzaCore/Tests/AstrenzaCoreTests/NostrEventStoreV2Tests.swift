import CryptoKit
import Foundation
import GRDB
import Testing
@testable import AstrenzaCore

@Suite("Nostr event store schema v2")
struct NostrEventStoreV2Tests {
    @Test("Store is Sendable and installs persistence hot-path indexes")
    func persistenceHotPathIndexes() throws {
        let database = try DatabaseQueue()
        let store = try NostrEventStore(database: database)
        requireSendable(store)

        let indexDefinitions = try database.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                SELECT name, sql
                FROM sqlite_master
                WHERE type = 'index' AND name IN (?, ?, ?)
                """,
                arguments: [
                    "events_kind_pubkey_created_event",
                    "relay_sync_events_timeline_relay_occurred_id",
                    "event_tags_name_value_nocase"
                ]
            )
            return Dictionary(uniqueKeysWithValues: rows.map { row in
                let name: String = row["name"]
                let sql: String = row["sql"]
                return (name, sql.split(whereSeparator: { $0.isWhitespace }).joined(separator: " "))
            })
        }

        #expect(
            indexDefinitions["events_kind_pubkey_created_event"]?.contains(
                "ON events(kind, pubkey, created_at DESC, event_id ASC)"
            ) == true
        )
        #expect(
            indexDefinitions["relay_sync_events_timeline_relay_occurred_id"]?.contains(
                "ON relay_sync_events( account_id, timeline_key, relay_url, occurred_at DESC, id DESC )"
            ) == true
        )
        #expect(
            indexDefinitions["event_tags_name_value_nocase"]?.contains(
                "ON event_tags(tag_name, tag_value COLLATE NOCASE)"
            ) == true
        )
    }

    @Test("V6 replays deletions and V9 reduces feed read state to its boundary")
    func deletionReplayAndFeedReadStateBoundaryMigration() throws {
        let database = try DatabaseQueue()
        try preparePreV6Schema(database)
        try markPreV6MigrationsApplied(database)
        let author = String(repeating: "a", count: 64)
        let eventTarget = event(kind: 1, pubkey: author, createdAt: 100, content: "existing")
        let pendingTarget = event(kind: 1, pubkey: author, createdAt: 150, content: "pending")
        let addressTarget = event(
            kind: 30_000,
            pubkey: author,
            createdAt: 110,
            content: "addressable",
            tags: [["d", "friends"]]
        )
        let deletion = event(
            kind: 5,
            pubkey: author,
            createdAt: 200,
            tags: [
                ["e", eventTarget.id],
                ["e", pendingTarget.id],
                ["a", "30000:\(author):friends"]
            ]
        )
        try database.write { db in
            try insertFixtureEvent(eventTarget, db: db)
            try insertFixtureEvent(addressTarget, db: db)
            try insertFixtureEvent(deletion, db: db)
            try db.execute(
                sql: """
                INSERT INTO feed_read_state (
                    feed_id, viewport_anchor_event_id, viewport_anchor_offset,
                    read_sort_ts, read_event_id, updated_at
                ) VALUES (?, ?, ?, ?, ?, ?)
                """,
                arguments: ["fixture-feed", "viewport", 4.5, 90, "read", 77]
            )
        }

        let store = try NostrEventStore(database: database)

        #expect(try store.events(kind: 1, limit: 10, now: 300).isEmpty)
        #expect(try store.events(kind: 30_000, limit: 10, now: 300).isEmpty)
        #expect(try deletedAt(eventID: eventTarget.id, database: database) == deletion.createdAt)
        #expect(try deletedAt(eventID: addressTarget.id, database: database) == deletion.createdAt)
        #expect(
            try tombstoneDeletionEventID(
                targetEventID: eventTarget.id,
                author: author,
                database: database
            ) == deletion.id
        )
        #expect(
            try tombstoneDeletionEventID(
                targetEventID: pendingTarget.id,
                author: author,
                database: database
            ) == deletion.id
        )
        #expect(
            try addressTombstoneDeletionEventID(
                kind: addressTarget.kind,
                pubkey: author,
                dTag: "friends",
                database: database
            ) == deletion.id
        )

        try store.save(events: [pendingTarget], receivedAt: 250)

        #expect(try store.events(kind: 1, limit: 10, now: 300).isEmpty)
        #expect(try deletedAt(eventID: pendingTarget.id, database: database) == deletion.createdAt)
        let readState = try #require(try store.feedReadState(feedID: "fixture-feed"))
        #expect(readState.readBoundary == NostrTimelineEntryCursor(
            sortTimestamp: 90,
            eventID: "read"
        ))
        #expect(readState.updatedAt == 77)
        #expect(try feedReadStateColumnNames(database) == [
            "feed_id",
            "read_sort_ts",
            "read_event_id",
            "updated_at"
        ])
    }

    @Test("Re-saving an event only advances received_at and preserves canonical derived rows")
    func existingEventResavePreservesDerivedRows() throws {
        let database = try DatabaseQueue()
        let store = try NostrEventStore(database: database)
        let original = event(
            kind: 1,
            createdAt: 100,
            content: "read https://example.test/original",
            tags: [
                ["imeta", "url https://cdn.example.test/original.jpg", "m image/jpeg"],
                ["e", "original-reference"]
            ]
        )
        let conflictingDuplicate = NostrEvent(
            id: original.id,
            pubkey: String(repeating: "b", count: 64),
            createdAt: 999,
            kind: 0,
            tags: [
                ["imeta", "url https://cdn.example.test/replacement.png", "m image/png"],
                ["e", "replacement-reference"]
            ],
            content: "https://example.test/replacement",
            sig: String(repeating: "2", count: 128)
        )

        try store.save(events: [original], receivedAt: 200)
        let originalTags = try store.tags(eventID: original.id)
        let originalAssets = try store.mediaAssets(eventID: original.id)

        try store.save(events: [conflictingDuplicate, conflictingDuplicate], receivedAt: 100)

        #expect(try store.event(id: original.id) == original)
        #expect(try store.tags(eventID: original.id) == originalTags)
        #expect(try store.mediaAssets(eventID: original.id) == originalAssets)
        #expect(
            try store.latestReplaceableEvent(pubkey: conflictingDuplicate.pubkey, kind: 0) == nil
        )
        let previewURLs = [
            try #require(URL(string: "https://example.test/original")),
            try #require(URL(string: "https://example.test/replacement"))
        ]
        #expect(try store.linkPreviews(urls: previewURLs).keys.sorted() == ["https://example.test/original"])
        #expect(try receivedAt(eventID: original.id, database: database) == 200)

        try store.save(events: [original], receivedAt: 300)

        #expect(try receivedAt(eventID: original.id, database: database) == 300)
        #expect(try store.tags(eventID: original.id) == originalTags)
        #expect(try store.mediaAssets(eventID: original.id) == originalAssets)
    }

    @Test("Event counts preserve kind, author, and visibility constraints")
    func eventCountsMatchVisibleAuthorQueries() throws {
        let store = try NostrEventStore.inMemory()
        let firstAuthor = String(repeating: "a", count: 64)
        let secondAuthor = String(repeating: "b", count: 64)
        try store.save(events: eventCountFixtureEvents(
            firstAuthor: firstAuthor,
            secondAuthor: secondAuthor
        ))

        #expect(try store.eventCount(
            kind: 1,
            authors: [firstAuthor],
            now: 140
        ) == 3)
        #expect(try store.eventCount(
            kind: 1,
            authors: [firstAuthor],
            now: 200
        ) == 2)
        #expect(try store.eventCount(
            kind: 1,
            authors: [firstAuthor, secondAuthor],
            now: 200
        ) == 3)
        #expect(try store.eventCount(
            kind: 0,
            authors: [firstAuthor],
            now: 200
        ) == 1)
        #expect(try store.eventCount(kind: 1, authors: [], now: 200) == 0)
    }

    private func eventCountFixtureEvents(
        firstAuthor: String,
        secondAuthor: String
    ) -> [NostrEvent] {
        [
            event(
                kind: 1,
                pubkey: firstAuthor,
                createdAt: 100,
                content: "first"
            ),
            event(
                kind: 1,
                pubkey: firstAuthor,
                createdAt: 110,
                content: "second"
            ),
            event(
                kind: 1,
                pubkey: firstAuthor,
                createdAt: 120,
                content: "expired",
                tags: [["expiration", "150"]]
            ),
            event(
                kind: 1,
                pubkey: secondAuthor,
                createdAt: 130,
                content: "other"
            ),
            event(
                kind: 0,
                pubkey: firstAuthor,
                createdAt: 140,
                content: "metadata"
            )
        ]
    }

    @Test("Deletion request received before its target hides the later event")
    func pendingEventDeletionTombstone() throws {
        let store = try NostrEventStore.inMemory()
        let author = String(repeating: "a", count: 64)
        let attacker = String(repeating: "b", count: 64)
        let target = event(kind: 1, pubkey: author, createdAt: 100, content: "target")
        let validDeletion = event(
            kind: 5,
            pubkey: author,
            createdAt: 120,
            tags: [["e", target.id]]
        )
        let invalidDeletion = event(
            kind: 5,
            pubkey: attacker,
            createdAt: 130,
            tags: [["e", target.id]]
        )

        try store.save(events: [validDeletion, invalidDeletion])
        try store.save(events: [target])
        try store.saveTimelineEntries([
            NostrTimelineEntryRecord(
                accountID: "account",
                timelineKey: "home",
                eventID: target.id,
                sortTimestamp: target.createdAt,
                insertedAt: 140
            )
        ])

        #expect(try store.event(id: target.id) == target)
        #expect(try store.events(kind: 1, limit: 10, now: 200).isEmpty)
        #expect(
            try store.deletedTimelineEntries(
                accountID: "account",
                timelineKey: "home",
                limit: 10,
                now: 200
            ).first?.deletionEventID == validDeletion.id
        )
    }

    @Test("Deletion request from another author does not hide a later event")
    func pendingEventDeletionRejectsOtherAuthor() throws {
        let store = try NostrEventStore.inMemory()
        let author = String(repeating: "a", count: 64)
        let attacker = String(repeating: "b", count: 64)
        let target = event(kind: 1, pubkey: author, createdAt: 100, content: "target")
        let deletion = event(
            kind: 5,
            pubkey: attacker,
            createdAt: 120,
            tags: [["e", target.id]]
        )

        try store.save(events: [deletion])
        try store.save(events: [target])

        #expect(try store.events(kind: 1, limit: 10, now: 200).map(\.id) == [target.id])
    }

    @Test("Address deletion hides every version up to its timestamp regardless of arrival order")
    func addressDeletionTombstone() throws {
        let store = try NostrEventStore.inMemory()
        let author = String(repeating: "a", count: 64)
        let existing = event(
            kind: 30_000,
            pubkey: author,
            createdAt: 100,
            content: "existing",
            tags: [["d", "friends"]]
        )
        let otherAddress = event(
            kind: 30_000,
            pubkey: author,
            createdAt: 110,
            content: "other",
            tags: [["d", "work"]]
        )
        let deletion = event(
            kind: 5,
            pubkey: author,
            createdAt: 200,
            tags: [["a", "30000:\(author):friends"]]
        )
        let lateOldVersion = event(
            kind: 30_000,
            pubkey: author,
            createdAt: 150,
            content: "late old",
            tags: [["d", "friends"]]
        )
        let futureVersion = event(
            kind: 30_000,
            pubkey: author,
            createdAt: 250,
            content: "future",
            tags: [["d", "friends"]]
        )

        try store.save(events: [existing, otherAddress])
        try store.save(events: [deletion])
        try store.save(events: [lateOldVersion, futureVersion])

        let visibleIDs = Set(try store.events(kind: 30_000, limit: 10, now: 300).map(\.id))
        #expect(visibleIDs == Set([otherAddress.id, futureVersion.id]))
        #expect(try store.event(id: existing.id) == existing)
        #expect(try store.event(id: lateOldVersion.id) == lateOldVersion)
    }

    @Test("Composite timeline cursor does not skip events sharing a timestamp")
    func compositeTimelineCursor() throws {
        let store = try NostrEventStore.inMemory()
        let events = [
            event(kind: 1, createdAt: 101, content: "newest"),
            event(kind: 1, createdAt: 100, content: "same-1"),
            event(kind: 1, createdAt: 100, content: "same-2"),
            event(kind: 1, createdAt: 100, content: "same-3"),
            event(kind: 1, createdAt: 100, content: "same-4"),
            event(kind: 1, createdAt: 100, content: "same-5"),
            event(kind: 1, createdAt: 99, content: "oldest")
        ]
        try store.save(events: events)
        try store.saveTimelineEntries(events.map { event in
            NostrTimelineEntryRecord(
                accountID: "account",
                timelineKey: "home",
                eventID: event.id,
                sortTimestamp: event.createdAt,
                insertedAt: 200
            )
        })

        let expected = try store.timelineEntries(accountID: "account", timelineKey: "home", limit: 100)
        var actual: [NostrTimelineEntryRecord] = []
        var page = try store.timelineEntries(accountID: "account", timelineKey: "home", limit: 2)
        while !page.isEmpty {
            actual.append(contentsOf: page)
            let last = try #require(page.last)
            page = try store.timelineEntries(
                accountID: "account",
                timelineKey: "home",
                olderThan: NostrTimelineEntryCursor(
                    sortTimestamp: last.sortTimestamp,
                    eventID: last.eventID
                ),
                limit: 2
            )
        }

        #expect(actual == expected)
        #expect(Set(actual.map(\.eventID)).count == events.count)

        let anchor = expected[3]
        let newer = try store.timelineEntries(
            accountID: "account",
            timelineKey: "home",
            newerThan: NostrTimelineEntryCursor(
                sortTimestamp: anchor.sortTimestamp,
                eventID: anchor.eventID
            ),
            limit: 100
        )
        #expect(newer == Array(expected.prefix(3)))
    }

    @Test("Generic feed records persist, paginate, and cascade with their definition")
    func genericFeedProjectionRecords() throws {
        let store = try NostrEventStore.inMemory()
        let definition = NostrFeedDefinitionRecord(
            feedID: "account:home:v2",
            accountID: "account",
            kind: "home",
            specificationJSON: Data(#"{"follow_set_revision":3}"#.utf8),
            specificationHash: "spec-hash",
            revision: 3,
            createdAt: 100,
            updatedAt: 100
        )
        let events = [
            event(kind: 1, createdAt: 200, content: "one"),
            event(kind: 1, createdAt: 200, content: "two"),
            event(kind: 1, createdAt: 100, content: "three")
        ]
        try store.save(events: events)
        try store.saveFeedDefinition(definition)
        try store.saveFeedMemberships(events.map { event in
            NostrFeedMembershipRecord(
                feedID: definition.feedID,
                eventID: event.id,
                sortTimestamp: event.createdAt,
                reason: "follow",
                insertedAt: 210
            )
        })
        let allMemberships = try store.feedMemberships(feedID: definition.feedID, limit: 10)
        let first = try #require(allMemberships.first)
        let remainder = try store.feedMemberships(
            feedID: definition.feedID,
            olderThan: NostrTimelineEntryCursor(
                sortTimestamp: first.sortTimestamp,
                eventID: first.eventID
            ),
            limit: 10
        )
        let syncRequest = NostrFeedSyncRequestRecord(
            requestID: "request-1",
            feedID: definition.feedID,
            feedRevision: definition.revision,
            feedSpecificationHash: definition.specificationHash,
            relayURL: "wss://relay.example",
            subscriptionID: "home-forward",
            direction: .forward,
            purpose: .initial,
            requestedAt: 215
        )
        let syncFilter = try NostrFeedSyncFilterRecord(
            requestID: syncRequest.requestID,
            filterIndex: 0,
            filter: [
                "kinds": .ints([1, 6]),
                "since": .int(100),
                "until": .int(200),
                "limit": .int(10)
            ]
        )
        let readState = NostrFeedReadStateRecord(
            feedID: definition.feedID,
            readBoundary: NostrTimelineEntryCursor(
                sortTimestamp: first.sortTimestamp,
                eventID: first.eventID
            ),
            updatedAt: 230
        )
        try store.beginFeedSyncRequest(syncRequest, filters: [syncFilter])
        try store.markFeedSyncRequestInstalled(requestID: syncRequest.requestID, at: 216)
        try store.recordFeedSyncEOSE(
            requestID: syncRequest.requestID,
            at: 220,
            eventCount: events.count,
            observedOldestPosition: NostrTimelineEntryCursor(sortTimestamp: 100, eventID: events[2].id),
            observedNewestPosition: NostrTimelineEntryCursor(sortTimestamp: 200, eventID: first.eventID)
        )
        try store.saveFeedReadState(readState)

        #expect(try store.feedDefinition(feedID: definition.feedID) == definition)
        #expect(try store.feedDefinitions(accountID: "account") == [definition])
        #expect([first] + remainder == allMemberships)
        #expect(try store.feedSyncRequests(feedID: definition.feedID) == [
            NostrFeedSyncRequestRecord(
                requestID: syncRequest.requestID,
                feedID: syncRequest.feedID,
                feedRevision: syncRequest.feedRevision,
                feedSpecificationHash: syncRequest.feedSpecificationHash,
                relayURL: syncRequest.relayURL,
                subscriptionID: syncRequest.subscriptionID,
                direction: syncRequest.direction,
                purpose: syncRequest.purpose,
                requestedAt: syncRequest.requestedAt,
                installedAt: 216,
                eoseAt: 220,
                eventCount: events.count,
                observedOldestPosition: NostrTimelineEntryCursor(sortTimestamp: 100, eventID: events[2].id),
                observedNewestPosition: NostrTimelineEntryCursor(sortTimestamp: 200, eventID: first.eventID)
            )
        ])
        #expect(try store.feedCoverageSegments(feedID: definition.feedID, revision: 3).count == 1)
        #expect(try store.feedReadState(feedID: definition.feedID) == readState)

        let revisedDefinition = NostrFeedDefinitionRecord(
            feedID: definition.feedID,
            accountID: definition.accountID,
            kind: definition.kind,
            specificationJSON: Data(#"{"follow_set_revision":4}"#.utf8),
            specificationHash: "revised-spec-hash",
            revision: 4,
            createdAt: definition.createdAt,
            updatedAt: 240
        )
        try store.saveFeedDefinition(revisedDefinition)

        #expect(try store.feedDefinition(feedID: definition.feedID) == revisedDefinition)
        #expect(try store.feedMemberships(feedID: definition.feedID, limit: 10).isEmpty)
        #expect(try store.feedCoverageSegments(feedID: definition.feedID, revision: 4).isEmpty)
        #expect(try store.feedCoverageSegments(feedID: definition.feedID, revision: 3).count == 1)
        #expect(try store.feedReadState(feedID: definition.feedID) == readState)

        try store.saveFeedMemberships(allMemberships)

        try store.deleteFeedDefinition(feedID: definition.feedID)
        #expect(try store.feedMemberships(feedID: definition.feedID, limit: 10).isEmpty)
        #expect(try store.feedSyncRequests(feedID: definition.feedID).isEmpty)
        #expect(try store.feedCoverageSegments(feedID: definition.feedID).isEmpty)
        #expect(try store.feedReadState(feedID: definition.feedID) == nil)
    }

    @Test("An empty EOSE creates a complete segment without inventing event cursors")
    func emptyEOSECreatesCoverageSegment() throws {
        let store = try NostrEventStore.inMemory()
        let definition = coverageDefinition()
        try store.saveFeedDefinition(definition)
        let request = coverageRequest(
            id: "empty-eose",
            definition: definition,
            relayURL: "wss://one.example",
            requestedAt: 100
        )
        let filter = try coverageFilter(
            requestID: request.requestID,
            since: 10,
            until: 20,
            limit: 50
        )

        try store.beginFeedSyncRequest(request, filters: [filter])
        try store.markFeedSyncRequestInstalled(requestID: request.requestID, at: 101)
        try store.recordFeedSyncEOSE(
            requestID: request.requestID,
            at: 110,
            eventCount: 0,
            observedOldestPosition: nil,
            observedNewestPosition: nil
        )

        let storedRequest = try #require(try store.feedSyncRequests(feedID: definition.feedID).first)
        let storedFilter = try #require(try store.feedSyncFilters(requestID: request.requestID).first)
        let segment = try #require(try store.feedCoverageSegments(feedID: definition.feedID).first)
        let checkpoint = try #require(try store.feedSyncCheckpoints(feedID: definition.feedID).first)
        #expect(storedRequest.installedAt == 101)
        #expect(storedRequest.eoseAt == 110)
        #expect(storedRequest.endedAt == nil)
        #expect(storedRequest.eventCount == 0)
        #expect(storedFilter.hitLimit == false)
        #expect(segment.lowerTimestamp == 10)
        #expect(segment.upperTimestamp == 20)
        #expect(segment.snapshotAt == 110)
        #expect(segment.confidence == .relayEOSE)
        #expect(checkpoint.newestPosition == nil)
        #expect(checkpoint.oldestPosition == nil)
        #expect(checkpoint.lastEOSEAt == 110)
    }

    @Test("EOSE at the request limit records progress but not complete coverage")
    func limitReachedDoesNotCreateCoverageSegment() throws {
        let store = try NostrEventStore.inMemory()
        let definition = coverageDefinition()
        try store.saveFeedDefinition(definition)
        let request = coverageRequest(
            id: "limit-reached",
            definition: definition,
            relayURL: "wss://one.example",
            direction: .backward,
            purpose: .older,
            requestedAt: 100
        )
        let filter = try coverageFilter(
            requestID: request.requestID,
            until: 200,
            limit: 2
        )
        let oldest = NostrTimelineEntryCursor(sortTimestamp: 100, eventID: "oldest")
        let newest = NostrTimelineEntryCursor(sortTimestamp: 150, eventID: "newest")

        try store.beginFeedSyncRequest(request, filters: [filter])
        try store.markFeedSyncRequestInstalled(requestID: request.requestID, at: 101)
        try store.recordFeedSyncEOSE(
            requestID: request.requestID,
            at: 110,
            eventCount: 2,
            observedOldestPosition: oldest,
            observedNewestPosition: newest
        )

        let storedRequest = try #require(try store.feedSyncRequests(feedID: definition.feedID).first)
        let storedFilter = try #require(try store.feedSyncFilters(requestID: request.requestID).first)
        let checkpoint = try #require(try store.feedSyncCheckpoints(feedID: definition.feedID).first)
        #expect(storedRequest.endReason == .eose)
        #expect(storedRequest.endedAt == 110)
        #expect(storedFilter.hitLimit)
        #expect(try store.feedCoverageSegments(feedID: definition.feedID).isEmpty)
        #expect(checkpoint.oldestPosition == oldest)
        #expect(checkpoint.newestPosition == newest)
    }

    @Test("Timeout and CLOSED attempts retain terminal history without creating coverage")
    func failedTerminalsRetainHistoryWithoutCoverage() throws {
        let store = try NostrEventStore.inMemory()
        let definition = coverageDefinition()
        try store.saveFeedDefinition(definition)
        let timeoutRequest = coverageRequest(
            id: "timed-out",
            definition: definition,
            relayURL: "wss://one.example",
            requestedAt: 100
        )
        let closedRequest = coverageRequest(
            id: "closed",
            definition: definition,
            relayURL: "wss://one.example",
            requestedAt: 120
        )
        let timeoutFilter = try coverageFilter(requestID: timeoutRequest.requestID, since: 10, limit: 50)
        let closedFilter = try coverageFilter(requestID: closedRequest.requestID, since: 20, limit: 50)

        try store.beginFeedSyncRequest(timeoutRequest, filters: [timeoutFilter])
        try store.markFeedSyncRequestInstalled(requestID: timeoutRequest.requestID, at: 101)
        try store.endFeedSyncRequest(
            requestID: timeoutRequest.requestID,
            reason: .timeout,
            message: "idle timeout",
            at: 110,
            eventCount: 0,
            observedOldestPosition: nil,
            observedNewestPosition: nil
        )
        // terminal済みattemptへの遅延EOSEで、不完全なrequestをcoverageへ昇格させない。
        try store.recordFeedSyncEOSE(
            requestID: timeoutRequest.requestID,
            at: 111,
            eventCount: 0,
            observedOldestPosition: nil,
            observedNewestPosition: nil
        )

        try store.beginFeedSyncRequest(closedRequest, filters: [closedFilter])
        try store.markFeedSyncRequestInstalled(requestID: closedRequest.requestID, at: 121)
        try store.endFeedSyncRequest(
            requestID: closedRequest.requestID,
            reason: .closed,
            message: "rate-limited",
            at: 130,
            eventCount: 1,
            observedOldestPosition: NostrTimelineEntryCursor(sortTimestamp: 25, eventID: "observed"),
            observedNewestPosition: NostrTimelineEntryCursor(sortTimestamp: 25, eventID: "observed")
        )

        let requests = try store.feedSyncRequests(feedID: definition.feedID)
        #expect(requests.count == 2)
        #expect(requests[0].requestID == timeoutRequest.requestID)
        #expect(requests[0].endReason == .timeout)
        #expect(requests[0].endMessage == "idle timeout")
        #expect(requests[0].eoseAt == nil)
        #expect(requests[1].requestID == closedRequest.requestID)
        #expect(requests[1].endReason == .closed)
        #expect(requests[1].endMessage == "rate-limited")
        #expect(requests[1].eventCount == 1)
        #expect(try store.feedCoverageSegments(feedID: definition.feedID).isEmpty)
        #expect(try store.feedSyncCheckpoints(feedID: definition.feedID).isEmpty)
    }

    @Test("NIP-77 creates verified coverage only when the relay reports no missing events")
    func nip77VerificationSeparatesZeroAndDifferences() throws {
        let store = try NostrEventStore.inMemory()
        let definition = coverageDefinition()
        try store.saveFeedDefinition(definition)
        let verifiedRequest = coverageRequest(
            id: "nip77-zero",
            definition: definition,
            relayURL: "wss://one.example",
            syncProtocol: .nip77,
            direction: .verification,
            purpose: .repair,
            requestedAt: 100
        )
        let differencesRequest = coverageRequest(
            id: "nip77-differences",
            definition: definition,
            relayURL: "wss://one.example",
            syncProtocol: .nip77,
            direction: .verification,
            purpose: .repair,
            requestedAt: 120
        )
        let verifiedFilter = try coverageFilter(
            requestID: verifiedRequest.requestID,
            since: 10,
            until: 20
        )
        let differencesFilter = try coverageFilter(
            requestID: differencesRequest.requestID,
            since: 10,
            until: 20
        )

        try store.beginFeedSyncRequest(verifiedRequest, filters: [verifiedFilter])
        try store.completeFeedSyncVerification(
            requestID: verifiedRequest.requestID,
            outcome: .noRemoteMissing,
            differenceCount: 0,
            at: 110
        )
        try store.beginFeedSyncRequest(differencesRequest, filters: [differencesFilter])
        try store.completeFeedSyncVerification(
            requestID: differencesRequest.requestID,
            outcome: .differencesFound,
            differenceCount: 3,
            at: 130
        )

        let requests = try store.feedSyncRequests(feedID: definition.feedID)
        let segments = try store.feedCoverageSegments(feedID: definition.feedID)
        let checkpoints = try store.feedSyncCheckpoints(feedID: definition.feedID)
        #expect(segments.count == 1)
        #expect(checkpoints.count == 1)
        let segment = try #require(segments.first)
        let checkpoint = try #require(checkpoints.first)
        #expect(requests.first { $0.requestID == verifiedRequest.requestID }?.verificationOutcome == .noRemoteMissing)
        #expect(requests.first { $0.requestID == verifiedRequest.requestID }?.differenceCount == 0)
        #expect(requests.first { $0.requestID == differencesRequest.requestID }?.verificationOutcome == .differencesFound)
        #expect(requests.first { $0.requestID == differencesRequest.requestID }?.differenceCount == 3)
        #expect(segment.sourceRequestID == verifiedRequest.requestID)
        #expect(segment.confidence == .nip77Verified)
        #expect(segment.lowerTimestamp == 10)
        #expect(segment.upperTimestamp == 20)
        #expect(checkpoint.lastVerifiedAt == 110)
    }

    @Test("Late NIP-77 verification cannot revive a terminal request")
    func lateNIP77VerificationDoesNotCreateCoverage() throws {
        let store = try NostrEventStore.inMemory()
        let definition = coverageDefinition()
        try store.saveFeedDefinition(definition)
        let request = coverageRequest(
            id: "nip77-late-terminal",
            definition: definition,
            relayURL: "wss://one.example",
            syncProtocol: .nip77,
            direction: .verification,
            purpose: .repair,
            requestedAt: 100
        )
        try store.beginFeedSyncRequest(
            request,
            filters: [try coverageFilter(requestID: request.requestID, since: 10, until: 20)]
        )
        try store.endFeedSyncRequest(
            requestID: request.requestID,
            reason: .timeout,
            message: "verification timeout",
            at: 110,
            eventCount: 0,
            observedOldestPosition: nil,
            observedNewestPosition: nil
        )

        try store.completeFeedSyncVerification(
            requestID: request.requestID,
            outcome: .noRemoteMissing,
            differenceCount: 0,
            at: 120
        )

        let stored = try #require(try store.feedSyncRequests(feedID: definition.feedID).first)
        #expect(stored.endReason == .timeout)
        #expect(stored.endMessage == "verification timeout")
        #expect(stored.verificationOutcome == nil)
        #expect(stored.differenceCount == nil)
        #expect(try store.feedCoverageSegments(feedID: definition.feedID).isEmpty)
        #expect(try store.feedSyncCheckpoints(feedID: definition.feedID).isEmpty)
    }

    @Test("Coverage and checkpoints remain isolated by feed revision and relay")
    func coverageSeparatesRevisionAndRelay() throws {
        let store = try NostrEventStore.inMemory()
        let revisionOne = coverageDefinition(revision: 1, specificationHash: "spec-1")
        try store.saveFeedDefinition(revisionOne)
        try completeEmptyEOSE(
            store: store,
            request: coverageRequest(
                id: "r1-one",
                definition: revisionOne,
                relayURL: "wss://one.example",
                requestedAt: 100
            ),
            at: 110
        )
        try completeEmptyEOSE(
            store: store,
            request: coverageRequest(
                id: "r1-two",
                definition: revisionOne,
                relayURL: "wss://two.example",
                requestedAt: 120
            ),
            at: 130
        )

        let revisionTwo = coverageDefinition(revision: 2, specificationHash: "spec-2")
        try store.saveFeedDefinition(revisionTwo)
        try completeEmptyEOSE(
            store: store,
            request: coverageRequest(
                id: "r2-one",
                definition: revisionTwo,
                relayURL: "wss://one.example",
                requestedAt: 140
            ),
            at: 150
        )

        let revisionOneSegments = try store.feedCoverageSegments(feedID: revisionOne.feedID, revision: 1)
        let revisionTwoSegments = try store.feedCoverageSegments(feedID: revisionOne.feedID, revision: 2)
        let revisionOneCheckpoints = try store.feedSyncCheckpoints(feedID: revisionOne.feedID, revision: 1)
        let revisionTwoCheckpoints = try store.feedSyncCheckpoints(feedID: revisionOne.feedID, revision: 2)
        #expect(Set(revisionOneSegments.map(\.relayURL)) == Set(["wss://one.example", "wss://two.example"]))
        #expect(revisionOneSegments.allSatisfy { $0.feedRevision == 1 && $0.feedSpecificationHash == "spec-1" })
        #expect(revisionTwoSegments.count == 1)
        #expect(revisionTwoSegments.first?.relayURL == "wss://one.example")
        #expect(revisionTwoSegments.first?.feedSpecificationHash == "spec-2")
        #expect(Set(revisionOneCheckpoints.map(\.relayURL)) == Set(["wss://one.example", "wss://two.example"]))
        #expect(revisionTwoCheckpoints.count == 1)
        #expect(revisionTwoCheckpoints.first?.relayURL == "wss://one.example")
        #expect(try store.feedSyncRequests(feedID: revisionOne.feedID, revision: 1).count == 2)
        #expect(try store.feedSyncRequests(feedID: revisionOne.feedID, revision: 2).count == 1)
    }

    private func coverageDefinition(
        revision: Int = 1,
        specificationHash: String = "coverage-spec"
    ) -> NostrFeedDefinitionRecord {
        NostrFeedDefinitionRecord(
            feedID: "feed:coverage",
            accountID: "account",
            kind: "home",
            specificationJSON: Data("{\"revision\":\(revision)}".utf8),
            specificationHash: specificationHash,
            revision: revision,
            createdAt: 1,
            updatedAt: revision
        )
    }

    private func coverageRequest(
        id: String,
        definition: NostrFeedDefinitionRecord,
        relayURL: String,
        syncProtocol: NostrFeedSyncProtocol = .req,
        direction: NostrFeedSyncDirection = .forward,
        purpose: NostrFeedSyncPurpose = .newer,
        requestedAt: Int
    ) -> NostrFeedSyncRequestRecord {
        NostrFeedSyncRequestRecord(
            requestID: id,
            feedID: definition.feedID,
            feedRevision: definition.revision,
            feedSpecificationHash: definition.specificationHash,
            relayURL: relayURL,
            subscriptionID: "subscription-\(id)",
            syncProtocol: syncProtocol,
            direction: direction,
            purpose: purpose,
            requestedAt: requestedAt
        )
    }

    private func coverageFilter(
        requestID: String,
        since: Int? = nil,
        until: Int? = nil,
        limit: Int? = nil
    ) throws -> NostrFeedSyncFilterRecord {
        var filter: [String: AnySendableJSON] = ["kinds": .ints([1, 6])]
        if let since { filter["since"] = .int(since) }
        if let until { filter["until"] = .int(until) }
        if let limit { filter["limit"] = .int(limit) }
        return try NostrFeedSyncFilterRecord(requestID: requestID, filterIndex: 0, filter: filter)
    }

    private func completeEmptyEOSE(
        store: NostrEventStore,
        request: NostrFeedSyncRequestRecord,
        at eoseAt: Int
    ) throws {
        let filter = try coverageFilter(requestID: request.requestID, since: 10, until: 20, limit: 50)
        try store.beginFeedSyncRequest(request, filters: [filter])
        try store.markFeedSyncRequestInstalled(requestID: request.requestID, at: request.requestedAt + 1)
        try store.recordFeedSyncEOSE(
            requestID: request.requestID,
            at: eoseAt,
            eventCount: 0,
            observedOldestPosition: nil,
            observedNewestPosition: nil
        )
    }

    @Test("Atomic ingestion stores events, relay sources, and feed memberships together")
    func atomicIngestion() throws {
        let store = try NostrEventStore.inMemory()
        let definition = NostrFeedDefinitionRecord(
            feedID: "account:home:v2",
            accountID: "account",
            kind: "home",
            specificationJSON: Data(#"{}"#.utf8),
            specificationHash: "empty-spec",
            revision: 1,
            createdAt: 100,
            updatedAt: 100
        )
        let ingestedEvent = event(kind: 1, createdAt: 200, content: "ingested")
        let source = NostrEventSourceRecord(
            eventID: ingestedEvent.id,
            relayURL: "wss://relay.example",
            firstSeenAt: 210,
            lastSeenAt: 210
        )
        let membership = NostrFeedMembershipRecord(
            feedID: definition.feedID,
            eventID: ingestedEvent.id,
            sortTimestamp: ingestedEvent.createdAt,
            reason: "follow",
            insertedAt: 210,
            feedRevision: definition.revision
        )
        let membershipSource = NostrFeedMembershipSourceRecord(
            feedID: definition.feedID,
            eventID: ingestedEvent.id,
            sourceType: "relay",
            sourceID: source.relayURL,
            insertedAt: 210,
            feedRevision: definition.revision
        )
        let timelineEntry = NostrTimelineEntryRecord(
            accountID: "account",
            timelineKey: "home",
            eventID: ingestedEvent.id,
            sortTimestamp: ingestedEvent.createdAt,
            source: "follow",
            insertedAt: 210
        )
        try store.saveFeedDefinition(definition)

        try store.ingest(
            events: [ingestedEvent],
            eventSources: [source],
            feedMemberships: [membership],
            feedMembershipSources: [membershipSource],
            timelineEntries: [timelineEntry],
            receivedAt: 210
        )

        #expect(try store.event(id: ingestedEvent.id) == ingestedEvent)
        #expect(try store.eventSources(eventID: ingestedEvent.id) == [source])
        #expect(try store.feedMemberships(feedID: definition.feedID, limit: 10) == [membership])
        #expect(try store.feedMembershipSources(feedID: definition.feedID) == [membershipSource])
        #expect(try store.timelineEntries(accountID: "account", timelineKey: "home", limit: 10) == [timelineEntry])
    }

    @Test("Atomic ingestion rolls back the event when a dependent feed write fails")
    func atomicIngestionRollback() throws {
        let store = try NostrEventStore.inMemory()
        let ingestedEvent = event(kind: 1, createdAt: 200, content: "rollback")
        let source = NostrEventSourceRecord(
            eventID: ingestedEvent.id,
            relayURL: "wss://relay.example",
            firstSeenAt: 210,
            lastSeenAt: 210
        )
        let invalidMembership = NostrFeedMembershipRecord(
            feedID: "missing-feed",
            eventID: ingestedEvent.id,
            sortTimestamp: ingestedEvent.createdAt,
            reason: "follow",
            insertedAt: 210
        )

        #expect(throws: (any Error).self) {
            try store.ingest(
                events: [ingestedEvent],
                eventSources: [source],
                feedMemberships: [invalidMembership],
                receivedAt: 210
            )
        }
        #expect(try store.event(id: ingestedEvent.id) == nil)
        #expect(try store.eventSources(eventID: ingestedEvent.id).isEmpty)
    }

    @Test("Outbox failures schedule a durable retry and success clears it")
    func outboxDurableRetry() throws {
        let store = try NostrEventStore.inMemory()
        let accountID = String(repeating: "a", count: 64)
        let outboxEvent = event(kind: 1, pubkey: accountID, createdAt: 100, content: "publish")
        let record = try store.enqueueOutboxEvent(
            outboxEvent,
            accountID: accountID,
            relayURLs: ["wss://relay.example"],
            localID: "retry-event",
            createdAt: 200
        )

        try store.recordOutboxRelayResult(
            localID: record.localID,
            relayURL: "wss://relay.example",
            accepted: false,
            message: "temporary failure",
            attemptedAt: 300
        )
        let failed = try #require(store.outboxEvents(accountID: accountID).first)
        #expect(failed.status == NostrOutboxStatus.failed)
        #expect(failed.nextRetryAt == 330)

        try store.recordOutboxRelayResult(
            localID: record.localID,
            relayURL: "wss://relay.example",
            accepted: true,
            message: "saved",
            attemptedAt: 340
        )
        let published = try #require(store.outboxEvents(accountID: accountID).first)
        #expect(published.status == NostrOutboxStatus.published)
        #expect(published.nextRetryAt == nil)
        #expect(published.lastError == nil)
    }

    @Test("Outbox retries back off and permanent relay rejections become terminal")
    func outboxBackoffAndTerminalRejection() throws {
        let store = try NostrEventStore.inMemory()
        let accountID = String(repeating: "a", count: 64)
        let record = try store.enqueueOutboxEvent(
            event(kind: 1, pubkey: accountID, createdAt: 100, content: "publish"),
            accountID: accountID,
            relayURLs: ["wss://relay.example"],
            localID: "backoff-event",
            createdAt: 200
        )

        try store.recordOutboxRelayResult(
            localID: record.localID,
            relayURL: "wss://relay.example",
            accepted: false,
            message: "timeout",
            attemptedAt: 300
        )
        try store.recordOutboxRelayResult(
            localID: record.localID,
            relayURL: "wss://relay.example",
            accepted: false,
            message: "timeout",
            attemptedAt: 330
        )
        #expect(try store.outboxEvents(accountID: accountID).first?.nextRetryAt == 390)
        #expect(try store.outboxRelays(localID: record.localID).first?.attemptCount == 2)

        try store.recordOutboxRelayResult(
            localID: record.localID,
            relayURL: "wss://relay.example",
            accepted: false,
            message: "blocked: policy",
            retryable: false,
            attemptedAt: 400
        )
        let rejected = try #require(store.outboxEvents(accountID: accountID).first)
        #expect(rejected.status == NostrOutboxStatus.rejected)
        #expect(rejected.nextRetryAt == nil)
    }

    @Test("Relay sync history is bounded across all relays in a timeline")
    func relaySyncTimelineRetention() throws {
        let store = try NostrEventStore.inMemory()
        let events = (0..<11).flatMap { relayIndex in
            (0..<200).map { eventIndex in
                NostrRelaySyncEventRecord(
                    accountID: "account",
                    timelineKey: "home",
                    relayURL: "wss://relay-\(relayIndex).example",
                    kind: .eose,
                    occurredAt: relayIndex * 1_000 + eventIndex
                )
            }
        }

        try store.saveRelaySyncEvents(events)

        let retained = try store.relaySyncEvents(
            accountID: "account",
            timelineKey: "home",
            limit: 3_000
        )
        #expect(retained.count == 2_000)
        #expect(retained.first?.occurredAt == 10_199)
        #expect(retained.last?.occurredAt == 1_000)
    }

    @Test("Partial relay windows do not advance the committed reconnect cursor")
    func partialRelayWindowDoesNotAdvanceCursor() throws {
        let store = try NostrEventStore.inMemory()
        let accountID = "account"
        let relayURL = "wss://relay.example"
        try store.saveRelaySyncEvents([
            NostrRelaySyncEventRecord(
                accountID: accountID,
                timelineKey: "home",
                relayURL: relayURL,
                kind: .eose,
                occurredAt: 1_000,
                subscriptionID: "astrenza-home-forward",
                eventCount: 2,
                newestCreatedAt: 500,
                oldestCreatedAt: 400
            )
        ])
        try store.saveRelaySyncEvents([
            NostrRelaySyncEventRecord(
                accountID: accountID,
                timelineKey: "home",
                relayURL: relayURL,
                kind: .timeout,
                occurredAt: 1_100,
                subscriptionID: "astrenza-home-forward",
                eventCount: 1,
                newestCreatedAt: 900,
                oldestCreatedAt: 900
            )
        ])

        let cursor = try #require(try store.syncCursor(
            accountID: accountID,
            timelineKey: "home",
            relayURL: relayURL
        ))
        #expect(cursor.newestCreatedAt == 500)
        #expect(cursor.oldestCreatedAt == 400)
        #expect(cursor.lastEOSEAt == 1_000)
    }

    @Test("Media assets can be loaded for a viewport in one bulk request")
    func bulkMediaAssets() throws {
        let store = try NostrEventStore.inMemory()
        let withMedia = event(
            kind: 1,
            createdAt: 100,
            content: "https://cdn.example/one.jpg",
            tags: [["imeta", "url https://cdn.example/one.jpg", "m image/jpeg"]]
        )
        let withoutMedia = event(kind: 1, createdAt: 90, content: "plain")
        try store.save(events: [withMedia, withoutMedia], receivedAt: 200)

        let assets = try store.mediaAssets(eventIDs: [withoutMedia.id, withMedia.id, withMedia.id, "missing"])
        let singleEventAssets = try store.mediaAssets(eventID: withMedia.id)

        #expect(assets[withMedia.id] == singleEventAssets)
        #expect(assets[withoutMedia.id] == [])
        #expect(assets["missing"] == [])
        #expect(assets.count == 3)
    }

    @Test("Feed projection revision replacement atomically switches membership and provenance")
    func feedProjectionRevisionReplacement() throws {
        let store = try NostrEventStore.inMemory()
        let feedID = "account:home:v4"
        let first = event(kind: 1, createdAt: 300, content: "first")
        let second = event(kind: 1, createdAt: 200, content: "second")
        let third = event(kind: 1, createdAt: 100, content: "third")
        try store.save(events: [first, second, third])

        let initialDefinition = NostrFeedDefinitionRecord(
            feedID: feedID,
            accountID: "account",
            kind: "home",
            specificationJSON: Data(#"{"revision":1}"#.utf8),
            specificationHash: "revision-1",
            revision: 1,
            createdAt: 10,
            updatedAt: 10
        )
        try store.replaceFeedProjection(
            initialDefinition,
            memberships: [
                NostrFeedMembershipRecord(
                    feedID: feedID,
                    eventID: first.id,
                    sortTimestamp: first.createdAt,
                    reason: "initial",
                    insertedAt: 20,
                    feedRevision: 1
                )
            ]
        )

        let revisedDefinition = NostrFeedDefinitionRecord(
            feedID: feedID,
            accountID: "account",
            kind: "home",
            specificationJSON: Data(#"{"revision":2}"#.utf8),
            specificationHash: "revision-2",
            revision: 2,
            createdAt: 10,
            updatedAt: 30
        )
        let revisedMemberships = [second, third].map { item in
            NostrFeedMembershipRecord(
                feedID: feedID,
                eventID: item.id,
                sortTimestamp: item.createdAt,
                reason: "list",
                insertedAt: 30,
                feedRevision: 2
            )
        }
        let sources = [
            NostrFeedMembershipSourceRecord(
                feedID: feedID,
                eventID: second.id,
                sourceType: "list",
                sourceID: "friends",
                insertedAt: 30,
                feedRevision: 2
            ),
            NostrFeedMembershipSourceRecord(
                feedID: feedID,
                eventID: second.id,
                sourceType: "list",
                sourceID: "work",
                insertedAt: 31,
                feedRevision: 2
            )
        ]
        let gap = NostrFeedGapRecord(
            feedID: feedID,
            feedRevision: 2,
            newerEventID: second.id,
            olderEventID: third.id,
            state: .unresolved,
            createdAt: 32,
            updatedAt: 32
        )

        try store.replaceFeedProjection(
            revisedDefinition,
            memberships: revisedMemberships,
            sources: sources,
            gaps: [gap]
        )

        #expect(try store.feedDefinition(feedID: feedID) == revisedDefinition)
        #expect(try store.feedMemberships(feedID: feedID, limit: 10) == revisedMemberships)
        #expect(try store.feedMemberships(feedID: feedID, revision: 1, limit: 10).isEmpty)
        #expect(try store.feedMembershipSources(feedID: feedID) == sources)
        #expect(try store.feedGaps(feedID: feedID) == [gap])
    }

    @Test("Stale and conflicting feed definitions cannot replace the active projection")
    func staleFeedDefinitionWritesPreserveActiveProjection() throws {
        let store = try NostrEventStore.inMemory()
        let feedID = "account:monotonic:v4"
        let staleEvent = event(kind: 1, createdAt: 100, content: "stale")
        let newest = event(kind: 1, createdAt: 300, content: "newest")
        let oldest = event(kind: 1, createdAt: 200, content: "oldest")
        try store.save(events: [staleEvent, newest, oldest])
        let activeDefinition = NostrFeedDefinitionRecord(
            feedID: feedID,
            accountID: "account",
            kind: "home",
            specificationJSON: Data(#"{"revision":2}"#.utf8),
            specificationHash: "revision-2",
            revision: 2,
            createdAt: 10,
            updatedAt: 200
        )
        let activeMemberships = [newest, oldest].map { item in
            NostrFeedMembershipRecord(
                feedID: feedID,
                eventID: item.id,
                sortTimestamp: item.createdAt,
                reason: "active",
                insertedAt: 200,
                feedRevision: 2
            )
        }
        let activeSources = [
            NostrFeedMembershipSourceRecord(
                feedID: feedID,
                eventID: newest.id,
                sourceType: "relay",
                sourceID: "wss://active.example",
                insertedAt: 200,
                feedRevision: 2
            )
        ]
        let activeGap = NostrFeedGapRecord(
            feedID: feedID,
            feedRevision: 2,
            newerEventID: newest.id,
            olderEventID: oldest.id,
            state: .unresolved,
            createdAt: 200,
            updatedAt: 200
        )
        try store.replaceFeedProjection(
            activeDefinition,
            memberships: activeMemberships,
            sources: activeSources,
            gaps: [activeGap]
        )
        let staleDefinition = NostrFeedDefinitionRecord(
            feedID: feedID,
            accountID: "account",
            kind: "home",
            specificationJSON: Data(#"{"revision":1}"#.utf8),
            specificationHash: "revision-1",
            revision: 1,
            createdAt: 10,
            updatedAt: 300
        )
        let staleMembership = NostrFeedMembershipRecord(
            feedID: feedID,
            eventID: staleEvent.id,
            sortTimestamp: staleEvent.createdAt,
            reason: "stale",
            insertedAt: 300,
            feedRevision: 1
        )
        let staleSource = NostrFeedMembershipSourceRecord(
            feedID: feedID,
            eventID: staleEvent.id,
            sourceType: "relay",
            sourceID: "wss://stale.example",
            insertedAt: 300,
            feedRevision: 1
        )
        let staleState = NostrHomeTimelineState(
            relays: ["wss://stale.example"],
            followedPubkeys: [],
            noteEvents: [staleEvent],
            metadataEvents: []
        )

        #expect {
            try store.saveFeedDefinition(staleDefinition)
        } throws: { error in
            error as? NostrFeedProjectionError == .mismatchedRevision
        }
        #expect {
            try store.replaceFeedProjection(staleDefinition, memberships: [staleMembership])
        } throws: { error in
            error as? NostrFeedProjectionError == .mismatchedRevision
        }
        #expect {
            try store.saveHomeFeedState(
                staleState,
                accountID: "account",
                definition: staleDefinition,
                memberships: [staleMembership],
                membershipSources: [staleSource],
                savedAt: 300
            )
        } throws: { error in
            error as? NostrFeedProjectionError == .mismatchedRevision
        }

        let conflictingDefinition = NostrFeedDefinitionRecord(
            feedID: feedID,
            accountID: "account",
            kind: "home",
            specificationJSON: Data(#"{"revision":2,"conflict":true}"#.utf8),
            specificationHash: "revision-2-conflict",
            revision: 2,
            createdAt: 10,
            updatedAt: 400
        )
        #expect {
            try store.saveFeedDefinition(conflictingDefinition)
        } throws: { error in
            error as? NostrFeedProjectionError == .mismatchedRevision
        }
        #expect {
            try store.replaceFeedProjection(
                conflictingDefinition,
                memberships: activeMemberships,
                sources: activeSources,
                gaps: [activeGap]
            )
        } throws: { error in
            error as? NostrFeedProjectionError == .mismatchedRevision
        }
        #expect {
            try store.saveHomeFeedState(
                NostrHomeTimelineState(
                    relays: ["wss://conflict.example"],
                    followedPubkeys: [],
                    noteEvents: [newest, oldest],
                    metadataEvents: []
                ),
                accountID: "account",
                definition: conflictingDefinition,
                memberships: activeMemberships,
                membershipSources: activeSources,
                savedAt: 400
            )
        } throws: { error in
            error as? NostrFeedProjectionError == .mismatchedRevision
        }

        let conflictingIdentityDefinition = NostrFeedDefinitionRecord(
            feedID: feedID,
            accountID: "other-account",
            kind: "search",
            specificationJSON: activeDefinition.specificationJSON,
            specificationHash: activeDefinition.specificationHash,
            revision: activeDefinition.revision,
            createdAt: activeDefinition.createdAt,
            updatedAt: 450
        )
        #expect {
            try store.saveFeedDefinition(conflictingIdentityDefinition)
        } throws: { error in
            error as? NostrFeedProjectionError == .mismatchedFeedID
        }
        let conflictingSpecificationPayload = NostrFeedDefinitionRecord(
            feedID: feedID,
            accountID: activeDefinition.accountID,
            kind: activeDefinition.kind,
            specificationJSON: Data(#"{"revision":2,"same_hash_conflict":true}"#.utf8),
            specificationHash: activeDefinition.specificationHash,
            revision: activeDefinition.revision,
            createdAt: activeDefinition.createdAt,
            updatedAt: 460
        )
        #expect {
            try store.saveFeedDefinition(conflictingSpecificationPayload)
        } throws: { error in
            error as? NostrFeedProjectionError == .mismatchedRevision
        }
        let conflictingSortPolicy = NostrFeedDefinitionRecord(
            feedID: feedID,
            accountID: activeDefinition.accountID,
            kind: activeDefinition.kind,
            specificationJSON: activeDefinition.specificationJSON,
            specificationHash: activeDefinition.specificationHash,
            sortPolicy: "event_id_desc",
            revision: activeDefinition.revision,
            createdAt: activeDefinition.createdAt,
            updatedAt: 470
        )
        #expect {
            try store.saveFeedDefinition(conflictingSortPolicy)
        } throws: { error in
            error as? NostrFeedProjectionError == .mismatchedRevision
        }

        let staleSameSpecification = NostrFeedDefinitionRecord(
            feedID: feedID,
            accountID: "account",
            kind: "home",
            specificationJSON: activeDefinition.specificationJSON,
            specificationHash: activeDefinition.specificationHash,
            revision: activeDefinition.revision,
            createdAt: activeDefinition.createdAt,
            updatedAt: 150
        )
        try store.saveFeedDefinition(staleSameSpecification)
        #expect(try store.feedDefinition(feedID: feedID) == activeDefinition)
        let newerSameSpecification = NostrFeedDefinitionRecord(
            feedID: feedID,
            accountID: "account",
            kind: "home",
            specificationJSON: activeDefinition.specificationJSON,
            specificationHash: activeDefinition.specificationHash,
            revision: activeDefinition.revision,
            createdAt: activeDefinition.createdAt,
            updatedAt: 250
        )
        try store.saveFeedDefinition(newerSameSpecification)

        #expect(try store.feedDefinition(feedID: feedID) == newerSameSpecification)
        #expect(try store.feedMemberships(feedID: feedID, limit: 10) == activeMemberships)
        #expect(try store.feedMembershipSources(feedID: feedID) == activeSources)
        #expect(try store.feedGaps(feedID: feedID) == [activeGap])
    }

    @Test("Failed feed projection replacement preserves the prior active revision")
    func feedProjectionReplacementRollback() throws {
        let store = try NostrEventStore.inMemory()
        let feedID = "account:rollback:v4"
        let storedEvent = event(kind: 1, createdAt: 200, content: "stored")
        let missingEvent = event(kind: 1, createdAt: 300, content: "missing")
        try store.save(events: [storedEvent])

        let initialDefinition = NostrFeedDefinitionRecord(
            feedID: feedID,
            accountID: "account",
            kind: "home",
            specificationJSON: Data(#"{"revision":1}"#.utf8),
            specificationHash: "revision-1",
            revision: 1,
            createdAt: 10,
            updatedAt: 10
        )
        let initialMembership = NostrFeedMembershipRecord(
            feedID: feedID,
            eventID: storedEvent.id,
            sortTimestamp: storedEvent.createdAt,
            reason: "initial",
            insertedAt: 20,
            feedRevision: 1
        )
        try store.replaceFeedProjection(initialDefinition, memberships: [initialMembership])

        let failedDefinition = NostrFeedDefinitionRecord(
            feedID: feedID,
            accountID: "account",
            kind: "home",
            specificationJSON: Data(#"{"revision":2}"#.utf8),
            specificationHash: "revision-2",
            revision: 2,
            createdAt: 10,
            updatedAt: 30
        )
        let invalidMembership = NostrFeedMembershipRecord(
            feedID: feedID,
            eventID: missingEvent.id,
            sortTimestamp: missingEvent.createdAt,
            reason: "missing-event",
            insertedAt: 30,
            feedRevision: 2
        )

        #expect(throws: (any Error).self) {
            try store.replaceFeedProjection(failedDefinition, memberships: [invalidMembership])
        }
        #expect(try store.feedDefinition(feedID: feedID) == initialDefinition)
        #expect(try store.feedMemberships(feedID: feedID, limit: 10) == [initialMembership])
    }

    @Test("Feed windows preserve order, anchor pagination, deleted items, and gap lifecycle")
    func feedWindowsAndGaps() throws {
        let store = try NostrEventStore.inMemory()
        let feedID = "account:window:v4"
        let author = String(repeating: "a", count: 64)
        let newest = event(kind: 1, pubkey: author, createdAt: 300, content: "newest")
        let deleted = event(kind: 1, pubkey: author, createdAt: 200, content: "deleted")
        let oldest = event(kind: 1, pubkey: author, createdAt: 100, content: "oldest")
        let deletion = event(
            kind: 5,
            pubkey: author,
            createdAt: 400,
            tags: [["e", deleted.id]]
        )
        try store.save(events: [newest, deleted, oldest, deletion], receivedAt: 500)
        let definition = NostrFeedDefinitionRecord(
            feedID: feedID,
            accountID: "account",
            kind: "home",
            specificationJSON: Data(#"{}"#.utf8),
            specificationHash: "window-spec",
            revision: 1,
            createdAt: 10,
            updatedAt: 10
        )
        let memberships = [newest, deleted, oldest].map { item in
            NostrFeedMembershipRecord(
                feedID: feedID,
                eventID: item.id,
                sortTimestamp: item.createdAt,
                reason: "relay",
                insertedAt: 500,
                feedRevision: 1
            )
        }
        try store.replaceFeedProjection(definition, memberships: memberships)

        let request = coverageRequest(
            id: "gap-request",
            definition: definition,
            relayURL: "wss://relay.example",
            direction: .backward,
            purpose: .gap,
            requestedAt: 510
        )
        try store.beginFeedSyncRequest(
            request,
            filters: [try coverageFilter(requestID: request.requestID, since: 100, until: 300)]
        )
        try store.markFeedGap(
            feedID: feedID,
            newerEventID: newest.id,
            olderEventID: deleted.id,
            state: .requested,
            sourceRequestID: request.requestID,
            at: 520
        )

        let window = try #require(try store.feedWindow(feedID: feedID, limit: 3, now: 600))
        #expect(window.memberships == memberships)
        #expect(window.events.map(\.id) == [newest.id, oldest.id])
        #expect(window.deletedItems.map(\.targetEventID) == [deleted.id])
        #expect(window.gaps.first?.state == .requested)
        #expect(window.gaps.first?.sourceRequestID == request.requestID)

        try store.markFeedGap(
            feedID: feedID,
            newerEventID: newest.id,
            olderEventID: deleted.id,
            state: .unresolved,
            at: 525
        )
        let failedRequestGap = try #require(try store.feedGaps(feedID: feedID).first)
        #expect(failedRequestGap.state == .unresolved)
        #expect(failedRequestGap.updatedAt == 525)
        #expect(failedRequestGap.sourceRequestID == request.requestID)

        let around = try #require(try store.feedWindow(
            feedID: feedID,
            aroundEventID: deleted.id,
            leadingLimit: 1,
            trailingLimit: 1,
            now: 600
        ))
        #expect(around.memberships.map(\.eventID) == [newest.id, deleted.id, oldest.id])
        let newer = try #require(try store.feedWindow(
            feedID: feedID,
            newerThan: NostrTimelineEntryCursor(sortTimestamp: deleted.createdAt, eventID: deleted.id),
            limit: 10,
            now: 600
        ))
        let older = try #require(try store.feedWindow(
            feedID: feedID,
            olderThan: NostrTimelineEntryCursor(sortTimestamp: deleted.createdAt, eventID: deleted.id),
            limit: 10,
            now: 600
        ))
        #expect(newer.memberships.map(\.eventID) == [newest.id])
        #expect(older.memberships.map(\.eventID) == [oldest.id])

        try store.resolveFeedGap(
            feedID: feedID,
            newerEventID: newest.id,
            olderEventID: deleted.id,
            sourceRequestID: request.requestID,
            at: 530
        )
        #expect(try store.feedGaps(feedID: feedID).isEmpty)
        let resolvedGap = try #require(try store.feedGaps(
            feedID: feedID,
            includeResolved: true
        ).first)
        #expect(resolvedGap.state == .resolved)
        #expect(resolvedGap.resolvedAt == 530)

        try store.markFeedGap(
            feedID: feedID,
            newerEventID: newest.id,
            olderEventID: deleted.id,
            state: .requested,
            at: 529
        )
        try store.markFeedGap(
            feedID: feedID,
            newerEventID: newest.id,
            olderEventID: deleted.id,
            state: .unresolved,
            at: 530
        )
        let stillResolved = try #require(try store.feedGaps(
            feedID: feedID,
            includeResolved: true
        ).first)
        #expect(stillResolved.state == .resolved)
        #expect(stillResolved.updatedAt == 530)

        try store.markFeedGap(
            feedID: feedID,
            newerEventID: newest.id,
            olderEventID: deleted.id,
            state: .unresolved,
            at: 531
        )
        try store.markFeedGap(
            feedID: feedID,
            newerEventID: newest.id,
            olderEventID: deleted.id,
            state: .requested,
            sourceRequestID: "delayed-request",
            at: 999
        )
        let terminalResolution = try #require(try store.feedGaps(
            feedID: feedID,
            includeResolved: true
        ).first)
        #expect(terminalResolution.state == .resolved)
        #expect(terminalResolution.updatedAt == 530)
        #expect(terminalResolution.resolvedAt == 530)
        #expect(terminalResolution.sourceRequestID == request.requestID)

        try store.resolveFeedGap(
            feedID: feedID,
            newerEventID: newest.id,
            olderEventID: deleted.id,
            sourceRequestID: "stale-resolution",
            at: 500
        )
        try store.markFeedGap(
            feedID: feedID,
            newerEventID: newest.id,
            olderEventID: deleted.id,
            state: .resolved,
            sourceRequestID: "older-resolved-callback",
            at: 400
        )
        let monotonicResolution = try #require(try store.feedGaps(
            feedID: feedID,
            includeResolved: true
        ).first)
        #expect(monotonicResolution.updatedAt == 530)
        #expect(monotonicResolution.resolvedAt == 530)
        #expect(monotonicResolution.sourceRequestID == request.requestID)
    }

    @Test("Feed window limits are applied after expired events are excluded")
    func feedWindowsSkipExpiredMembershipsBeforeLimiting() throws {
        let store = try NostrEventStore.inMemory()
        let feedID = "account:expiration-window:v4"
        let expiredNewest = event(
            kind: 1,
            createdAt: 400,
            content: "expired newest",
            tags: [["expiration", "550"]]
        )
        let expiredSecond = event(
            kind: 1,
            createdAt: 350,
            content: "expired second",
            tags: [["expiration", "550"]]
        )
        let visibleNewest = event(kind: 1, createdAt: 300, content: "visible newest")
        let visibleOldest = event(kind: 1, createdAt: 200, content: "visible oldest")
        let events = [expiredNewest, expiredSecond, visibleNewest, visibleOldest]
        try store.save(events: events, receivedAt: 500)

        let definition = NostrFeedDefinitionRecord(
            feedID: feedID,
            accountID: "account",
            kind: "home",
            specificationJSON: Data(#"{}"#.utf8),
            specificationHash: "expiration-window",
            revision: 1,
            createdAt: 10,
            updatedAt: 10
        )
        try store.replaceFeedProjection(
            definition,
            memberships: events.map { item in
                NostrFeedMembershipRecord(
                    feedID: feedID,
                    eventID: item.id,
                    sortTimestamp: item.createdAt,
                    reason: "relay",
                    insertedAt: 500,
                    feedRevision: 1
                )
            }
        )

        let newest = try #require(try store.feedWindow(feedID: feedID, limit: 1, now: 600))
        #expect(newest.memberships.map(\.eventID) == [visibleNewest.id])
        #expect(newest.events.map(\.id) == [visibleNewest.id])

        let newer = try #require(try store.feedWindow(
            feedID: feedID,
            newerThan: NostrTimelineEntryCursor(
                sortTimestamp: visibleOldest.createdAt,
                eventID: visibleOldest.id
            ),
            limit: 1,
            now: 600
        ))
        #expect(newer.memberships.map(\.eventID) == [visibleNewest.id])

        let older = try #require(try store.feedWindow(
            feedID: feedID,
            olderThan: NostrTimelineEntryCursor(
                sortTimestamp: expiredNewest.createdAt,
                eventID: expiredNewest.id
            ),
            limit: 1,
            now: 600
        ))
        #expect(older.memberships.map(\.eventID) == [visibleNewest.id])

        let aroundExpiredAnchor = try #require(try store.feedWindow(
            feedID: feedID,
            aroundEventID: expiredSecond.id,
            leadingLimit: 1,
            trailingLimit: 1,
            now: 600
        ))
        #expect(aroundExpiredAnchor.memberships.map(\.eventID) == [visibleNewest.id, visibleOldest.id])

        let aroundVisibleAnchor = try #require(try store.feedWindow(
            feedID: feedID,
            aroundEventID: visibleNewest.id,
            leadingLimit: 1,
            trailingLimit: 1,
            now: 600
        ))
        #expect(aroundVisibleAnchor.memberships.map(\.eventID) == [visibleNewest.id, visibleOldest.id])

        let restored = try #require(try store.homeFeedState(
            accountID: definition.accountID,
            limit: 1,
            now: 600
        ))
        #expect(restored.noteEvents.map(\.id) == [visibleNewest.id])
    }

    @Test("Feed read state persists its boundary")
    func feedReadStatePersistsBoundary() throws {
        let store = try NostrEventStore.inMemory()
        let definition = NostrFeedDefinitionRecord(
            feedID: "account:state:v4",
            accountID: "account",
            kind: "home",
            specificationJSON: Data(#"{}"#.utf8),
            specificationHash: "state-spec",
            revision: 1,
            createdAt: 10,
            updatedAt: 10
        )
        try store.saveFeedDefinition(definition)
        let readBoundary = NostrTimelineEntryCursor(sortTimestamp: 150, eventID: "read-event")
        let state = NostrFeedReadStateRecord(
            feedID: definition.feedID,
            readBoundary: readBoundary,
            updatedAt: 100
        )

        try store.saveFeedReadState(state)

        let restored = try #require(try store.feedReadState(feedID: definition.feedID))
        #expect(restored == state)
        #expect(restored.readBoundary == readBoundary)
        #expect(restored.updatedAt == 100)
    }

    @Test("Feed read state ignores stale boundaries and accepts newer clears")
    func feedReadStateKeepsMonotonicBoundary() throws {
        let store = try NostrEventStore.inMemory()
        let definition = feedDefinition(feedID: "account:read-state")
        try store.saveFeedDefinition(definition)
        let firstBoundary = NostrTimelineEntryCursor(sortTimestamp: 150, eventID: "read-first")
        let staleBoundary = NostrTimelineEntryCursor(sortTimestamp: 50, eventID: "read-stale")
        let latestBoundary = NostrTimelineEntryCursor(sortTimestamp: 250, eventID: "read-latest")

        try store.saveFeedReadBoundary(
            feedID: definition.feedID,
            readBoundary: firstBoundary,
            updatedAt: 100
        )
        try store.saveFeedReadBoundary(
            feedID: definition.feedID,
            readBoundary: staleBoundary,
            updatedAt: 90
        )
        #expect(try store.feedReadState(feedID: definition.feedID)?.readBoundary == firstBoundary)

        try store.saveFeedReadState(NostrFeedReadStateRecord(
            feedID: definition.feedID,
            readBoundary: latestBoundary,
            updatedAt: 120
        ))
        try store.saveFeedReadState(NostrFeedReadStateRecord(
            feedID: definition.feedID,
            readBoundary: staleBoundary,
            updatedAt: 110
        ))
        let latest = try #require(try store.feedReadState(feedID: definition.feedID))
        #expect(latest.readBoundary == latestBoundary)
        #expect(latest.updatedAt == 120)

        try store.saveFeedReadBoundary(
            feedID: definition.feedID,
            readBoundary: nil,
            updatedAt: 130
        )
        let cleared = try #require(try store.feedReadState(feedID: definition.feedID))
        #expect(cleared.readBoundary == nil)
        #expect(cleared.updatedAt == 130)
    }

    @Test("Timeline metadata can update without rewriting events or projection")
    func timelineMetadataOnlySave() throws {
        let store = try NostrEventStore.inMemory()
        let accountID = String(repeating: "a", count: 64)
        let originalNote = event(kind: 1, pubkey: accountID, createdAt: 100, content: "persisted")
        let projectionOnlyNote = event(kind: 1, pubkey: accountID, createdAt: 200, content: "not persisted")
        let initialState = NostrHomeTimelineState(
            relays: ["wss://old.example"],
            followedPubkeys: [accountID],
            noteEvents: [originalNote],
            metadataEvents: []
        )
        try store.saveHomeTimelineState(initialState, accountID: accountID, savedAt: 100)
        let resolution = NostrNIP05Resolution(
            identifier: "alice@example.test",
            pubkey: accountID,
            relays: ["wss://new.example"],
            status: .verified,
            resolvedAt: Date(timeIntervalSince1970: 150)
        )
        let metadataOnlyState = NostrHomeTimelineState(
            relays: ["wss://new.example"],
            followedPubkeys: [],
            noteEvents: [projectionOnlyNote],
            metadataEvents: [],
            nip05Resolutions: [accountID: resolution],
            hasMoreOlder: false
        )

        try store.saveTimelineStateMetadata(metadataOnlyState, accountID: accountID, savedAt: 200)
        let staleState = NostrHomeTimelineState(
            relays: ["wss://stale.example"],
            followedPubkeys: [String(repeating: "b", count: 64)],
            noteEvents: [],
            metadataEvents: [],
            nip05Resolutions: [:],
            hasMoreOlder: true
        )
        try store.saveHomeTimelineState(staleState, accountID: accountID, savedAt: 150)

        let restored = try #require(
            try store.legacyHomeTimelineStateForMigration(accountID: accountID)
        )
        #expect(restored.relays == ["wss://new.example"])
        #expect(restored.followedPubkeys.isEmpty)
        #expect(restored.noteEvents == [originalNote])
        #expect(restored.nip05Resolutions == [accountID: resolution])
        #expect(restored.hasMoreOlder == false)
        #expect(try store.event(id: projectionOnlyNote.id) == nil)
    }

    @Test("Home feed state restores through Generic Feed without writing the legacy timeline index")
    func homeFeedStateUsesGenericProjection() throws {
        let store = try NostrEventStore.inMemory()
        let accountID = String(repeating: "a", count: 64)
        let note = event(kind: 1, pubkey: accountID, createdAt: 200, content: "generic restore")
        let state = NostrHomeTimelineState(
            relays: ["wss://relay.example"],
            followedPubkeys: [accountID],
            noteEvents: [note],
            metadataEvents: []
        )
        let definition = NostrFeedDefinitionRecord(
            feedID: "feed:home:\(accountID)",
            accountID: accountID,
            kind: "home",
            specificationJSON: Data(#"{"kinds":[1,6]}"#.utf8),
            specificationHash: "generic-home",
            revision: 1,
            createdAt: 210,
            updatedAt: 210
        )
        try store.saveHomeFeedState(
            state,
            accountID: accountID,
            definition: definition,
            memberships: [NostrFeedMembershipRecord(
                feedID: definition.feedID,
                eventID: note.id,
                sortTimestamp: note.createdAt,
                reason: "state",
                insertedAt: 210,
                feedRevision: definition.revision
            )],
            savedAt: 210
        )
        #expect(try store.timelineEntries(accountID: accountID, timelineKey: "home", limit: 10).isEmpty)

        let restored = try #require(try store.homeFeedState(accountID: accountID))
        #expect(restored.noteEvents == [note])
        #expect(restored.relays == state.relays)
        #expect(restored.followedPubkeys == state.followedPubkeys)
    }

    @Test("Empty Home feed restores relay, follow, sync, and read metadata")
    func emptyHomeFeedRestoresMetadata() throws {
        let store = try NostrEventStore.inMemory()
        let accountID = String(repeating: "b", count: 64)
        let followed = String(repeating: "c", count: 64)
        let definition = NostrFeedDefinitionRecord(
            feedID: "feed:home:\(accountID)",
            accountID: accountID,
            kind: "home",
            specificationJSON: Data(#"{"authors":[],"kinds":[1,6]}"#.utf8),
            specificationHash: "empty-home",
            revision: 1,
            createdAt: 300,
            updatedAt: 300
        )
        let syncEvent = NostrRelaySyncEventRecord(
            accountID: accountID,
            timelineKey: "home",
            relayURL: "wss://relay.example",
            kind: .eose,
            occurredAt: 301,
            subscriptionID: "home-forward",
            eventCount: 0,
            message: "empty EOSE"
        )
        let state = NostrHomeTimelineState(
            relays: ["wss://relay.example"],
            followedPubkeys: [followed],
            noteEvents: [],
            metadataEvents: [],
            hasMoreOlder: false,
            relaySyncEvents: [syncEvent]
        )
        let readState = NostrFeedReadStateRecord(
            feedID: definition.feedID,
            readBoundary: NostrTimelineEntryCursor(sortTimestamp: 250, eventID: "last-read-event"),
            updatedAt: 302
        )

        try store.saveHomeFeedState(
            state,
            accountID: accountID,
            definition: definition,
            memberships: [],
            readState: readState,
            savedAt: 302
        )

        let restored = try #require(try store.homeFeedState(accountID: accountID))
        #expect(restored.noteEvents.isEmpty)
        #expect(restored.relays == state.relays)
        #expect(restored.followedPubkeys == state.followedPubkeys)
        #expect(restored.hasMoreOlder == false)
        #expect(restored.relaySyncEvents == [syncEvent])
        #expect(try store.feedReadState(feedID: definition.feedID) == readState)
        #expect(try store.timelineEntries(accountID: accountID, timelineKey: "home", limit: 10).isEmpty)
    }

    @Test("An explicit empty kind 3 replaces stale followed metadata")
    func emptyContactListClearsFollowedPubkeys() throws {
        let store = try NostrEventStore.inMemory()
        let accountID = String(repeating: "e", count: 64)
        let staleFollow = String(repeating: "f", count: 64)
        let emptyContactList = event(
            kind: 3,
            pubkey: accountID,
            createdAt: 350,
            content: "",
            tags: []
        )
        let definition = NostrFeedDefinitionRecord(
            feedID: "feed:home:\(accountID)",
            accountID: accountID,
            kind: "home",
            specificationJSON: Data(#"{"authors":[],"kinds":[1,6]}"#.utf8),
            specificationHash: "empty-contact-list",
            revision: 1,
            createdAt: 350,
            updatedAt: 350
        )
        let staleState = NostrHomeTimelineState(
            relays: ["wss://relay.example"],
            followedPubkeys: [staleFollow],
            noteEvents: [],
            metadataEvents: [],
            contactListEvent: emptyContactList
        )
        try store.saveHomeFeedState(
            staleState,
            accountID: accountID,
            definition: definition,
            memberships: [],
            savedAt: 350
        )

        let restored = try #require(try store.homeFeedState(accountID: accountID))
        #expect(restored.contactListEvent == emptyContactList)
        #expect(restored.followedPubkeys.isEmpty)
    }

    @Test("Home feed state write rolls back canonical, projection, provenance, and metadata together")
    func homeFeedStateWriteIsAtomic() throws {
        let store = try NostrEventStore.inMemory()
        let accountID = String(repeating: "d", count: 64)
        let persistedCandidate = event(
            kind: 1,
            pubkey: accountID,
            createdAt: 400,
            content: "must roll back"
        )
        let missingProjectionEvent = event(
            kind: 1,
            pubkey: accountID,
            createdAt: 399,
            content: "not part of state"
        )
        let definition = NostrFeedDefinitionRecord(
            feedID: "feed:home:\(accountID)",
            accountID: accountID,
            kind: "home",
            specificationJSON: Data(#"{"kinds":[1,6]}"#.utf8),
            specificationHash: "rollback-home",
            revision: 1,
            createdAt: 410,
            updatedAt: 410
        )
        let membership = NostrFeedMembershipRecord(
            feedID: definition.feedID,
            eventID: missingProjectionEvent.id,
            sortTimestamp: missingProjectionEvent.createdAt,
            reason: "state",
            insertedAt: 410,
            feedRevision: definition.revision
        )
        let source = NostrFeedMembershipSourceRecord(
            feedID: definition.feedID,
            eventID: missingProjectionEvent.id,
            sourceType: "author",
            sourceID: accountID,
            insertedAt: 410,
            feedRevision: definition.revision
        )
        let readState = NostrFeedReadStateRecord(
            feedID: definition.feedID,
            readBoundary: nil,
            updatedAt: 410
        )
        let state = NostrHomeTimelineState(
            relays: ["wss://rollback.example"],
            followedPubkeys: [accountID],
            noteEvents: [persistedCandidate],
            metadataEvents: []
        )

        #expect(throws: (any Error).self) {
            try store.saveHomeFeedState(
                state,
                accountID: accountID,
                definition: definition,
                memberships: [membership],
                membershipSources: [source],
                readState: readState,
                savedAt: 410
            )
        }

        #expect(try store.event(id: persistedCandidate.id) == nil)
        #expect(try store.feedDefinition(feedID: definition.feedID) == nil)
        #expect(try store.homeFeedState(accountID: accountID) == nil)
        #expect(try store.feedReadState(feedID: definition.feedID) == nil)
        #expect(try store.relaySyncEvents(accountID: accountID, timelineKey: "home").isEmpty)
    }

    @Test("Ingestion rolls back a canonical event when membership provenance is orphaned")
    func atomicIngestionRejectsOrphanedMembershipSource() throws {
        let store = try NostrEventStore.inMemory()
        let definition = NostrFeedDefinitionRecord(
            feedID: "account:source-rollback:v4",
            accountID: "account",
            kind: "home",
            specificationJSON: Data(#"{}"#.utf8),
            specificationHash: "source-spec",
            revision: 1,
            createdAt: 10,
            updatedAt: 10
        )
        let ingestedEvent = event(kind: 1, createdAt: 200, content: "rollback")
        try store.saveFeedDefinition(definition)
        let orphanedSource = NostrFeedMembershipSourceRecord(
            feedID: definition.feedID,
            eventID: ingestedEvent.id,
            sourceType: "relay",
            sourceID: "wss://relay.example",
            insertedAt: 210
        )

        #expect(throws: (any Error).self) {
            try store.ingest(
                events: [ingestedEvent],
                eventSources: [],
                feedMemberships: [],
                feedMembershipSources: [orphanedSource],
                receivedAt: 210
            )
        }
        #expect(try store.event(id: ingestedEvent.id) == nil)
    }

    private func preparePreV6Schema(_ database: DatabaseQueue) throws {
        try database.write { db in
            try db.create(table: "events") { table in
                table.column("event_id", .text).primaryKey()
                table.column("pubkey", .text).notNull()
                table.column("created_at", .integer).notNull()
                table.column("kind", .integer).notNull()
                table.column("content", .text).notNull()
                table.column("tags_json", .blob).notNull()
                table.column("sig", .text).notNull()
                table.column("received_at", .integer).notNull()
                table.column("deleted_at", .integer)
                table.column("expires_at", .integer)
                table.column("raw_json", .blob).notNull()
            }
            try db.create(table: "event_tags") { table in
                table.column("event_id", .text).notNull()
                    .references("events", column: "event_id", onDelete: .cascade)
                table.column("pos", .integer).notNull()
                table.column("tag_name", .text).notNull()
                table.column("tag_value", .text)
                table.column("relay_hint", .text)
                table.column("marker", .text)
                table.column("raw_json", .blob).notNull()
                table.primaryKey(["event_id", "pos"])
            }
            try db.create(table: "media_assets") { table in
                table.column("asset_id", .text).primaryKey()
                table.column("event_id", .text).notNull()
                    .references("events", column: "event_id", onDelete: .cascade)
            }
            try db.create(table: "deletion_tombstones") { table in
                table.column("target_event_id", .text).notNull()
                table.column("deletion_event_id", .text).notNull()
                    .references("events", column: "event_id", onDelete: .cascade)
                table.column("deleted_at", .integer).notNull()
                table.column("author_pubkey", .text).notNull()
                table.primaryKey(["target_event_id", "author_pubkey"])
            }
            try db.create(table: "address_deletion_tombstones") { table in
                table.column("kind", .integer).notNull()
                table.column("pubkey", .text).notNull()
                table.column("d_tag", .text).notNull()
                table.column("deletion_event_id", .text).notNull()
                    .references("events", column: "event_id", onDelete: .cascade)
                table.column("deleted_at", .integer).notNull()
                table.primaryKey(["kind", "pubkey", "d_tag"])
            }
            try preparePreV6FeedReadStateSchema(db)
        }
    }

    private func preparePreV6FeedReadStateSchema(
        _ databaseConnection: Database
    ) throws {
        try databaseConnection.create(table: "feed_definitions") { table in
            table.column("feed_id", .text).primaryKey()
        }
        try databaseConnection.execute(
            sql: "INSERT INTO feed_definitions (feed_id) VALUES (?)",
            arguments: ["fixture-feed"]
        )
        try databaseConnection.create(table: "feed_read_state") { table in
            table.column("feed_id", .text).primaryKey()
            table.column("viewport_anchor_event_id", .text)
            table.column("viewport_anchor_offset", .double).notNull().defaults(to: 0)
            table.column("read_sort_ts", .integer)
            table.column("read_event_id", .text)
            table.column("updated_at", .integer).notNull()
            table.check(sql: "(read_sort_ts IS NULL) = (read_event_id IS NULL)")
        }
    }

    private func feedReadStateColumnNames(
        _ database: DatabaseQueue
    ) throws -> [String] {
        try database.read { databaseConnection in
            try Row.fetchAll(
                databaseConnection,
                sql: "PRAGMA table_info(feed_read_state)"
            ).map { row -> String in row["name"] }
        }
    }

    private func markPreV6MigrationsApplied(_ database: DatabaseQueue) throws {
        var migrator = DatabaseMigrator()
        for identifier in preV6MigrationIdentifiers {
            migrator.registerMigration(identifier) { _ in }
        }
        try migrator.migrate(database)
    }

    private var preV6MigrationIdentifiers: [String] {
        [
            "createNostrEventStore",
            "expandNostrEventStoreSchema",
            "addRelaySyncEvents",
            "addRelayPreferences",
            "addComposeDrafts",
            "addLocalFiltersAndBookmarks",
            "addFilterRulePresentationAndScopes",
            "addNostrLists",
            "addMediaAssets",
            "addLinkPreviews",
            "addOutbox",
            "addRelayTrafficHourlyCounters",
            "upgradeDeletionTombstonesAndAddAddresses",
            "addGenericFeedProjectionV2",
            "addOutboxRelayAttemptCount",
            "replaceGenericFeedCoverageV3",
            "replaceGenericFeedProjectionV4",
            "addPersistenceHotPathIndexesV5"
        ]
    }

    private func insertFixtureEvent(_ event: NostrEvent, db: Database) throws {
        let encoder = JSONEncoder()
        try db.execute(
            sql: """
            INSERT INTO events (
                event_id, pubkey, created_at, kind, content, tags_json, sig,
                received_at, deleted_at, expires_at, raw_json
            ) VALUES (?, ?, ?, ?, ?, ?, ?, 1, NULL, NULL, ?)
            """,
            arguments: [
                event.id,
                event.pubkey,
                event.createdAt,
                event.kind,
                event.content,
                try encoder.encode(event.tags),
                event.sig,
                try encoder.encode(event)
            ]
        )
        for (position, tag) in event.tags.enumerated() {
            guard let name = tag.first else { continue }
            try db.execute(
                sql: """
                INSERT INTO event_tags (
                    event_id, pos, tag_name, tag_value, relay_hint, marker, raw_json
                ) VALUES (?, ?, ?, ?, NULL, NULL, ?)
                """,
                arguments: [
                    event.id,
                    position,
                    name,
                    tag.count > 1 ? tag[1] : nil,
                    try encoder.encode(tag)
                ]
            )
        }
    }

    private func deletedAt(eventID: String, database: DatabaseQueue) throws -> Int? {
        try database.read { db in
            try Int.fetchOne(
                db,
                sql: "SELECT deleted_at FROM events WHERE event_id = ?",
                arguments: [eventID]
            )
        }
    }

    private func tombstoneDeletionEventID(
        targetEventID: String,
        author: String,
        database: DatabaseQueue
    ) throws -> String? {
        try database.read { db in
            try String.fetchOne(
                db,
                sql: """
                SELECT deletion_event_id
                FROM deletion_tombstones
                WHERE target_event_id = ? AND author_pubkey = ?
                """,
                arguments: [targetEventID, author]
            )
        }
    }

    private func addressTombstoneDeletionEventID(
        kind: Int,
        pubkey: String,
        dTag: String,
        database: DatabaseQueue
    ) throws -> String? {
        try database.read { db in
            try String.fetchOne(
                db,
                sql: """
                SELECT deletion_event_id
                FROM address_deletion_tombstones
                WHERE kind = ? AND pubkey = ? AND d_tag = ?
                """,
                arguments: [kind, pubkey, dTag]
            )
        }
    }

    private func feedDefinition(feedID: String) -> NostrFeedDefinitionRecord {
        NostrFeedDefinitionRecord(
            feedID: feedID,
            accountID: "account",
            kind: "home",
            specificationJSON: Data(#"{}"#.utf8),
            specificationHash: "state-spec",
            revision: 1,
            createdAt: 10,
            updatedAt: 10
        )
    }

    private func receivedAt(eventID: String, database: DatabaseQueue) throws -> Int? {
        try database.read { db in
            try Int.fetchOne(
                db,
                sql: "SELECT received_at FROM events WHERE event_id = ?",
                arguments: [eventID]
            )
        }
    }

    private func requireSendable<T: Sendable>(_ value: T) {
        _ = value
    }

    private func event(
        kind: Int,
        pubkey: String = String(repeating: "a", count: 64),
        createdAt: Int,
        content: String = "",
        tags: [[String]] = []
    ) -> NostrEvent {
        let canonical = NostrCanonicalJSON.serialize(
            pubkey: pubkey,
            createdAt: createdAt,
            kind: kind,
            tags: tags,
            content: content
        )
        let digest = SHA256.hash(data: Data(canonical.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        return NostrEvent(
            id: digest,
            pubkey: pubkey,
            createdAt: createdAt,
            kind: kind,
            tags: tags,
            content: content,
            sig: String(repeating: "1", count: 128)
        )
    }
}
