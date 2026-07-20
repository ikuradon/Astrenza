import AstrenzaCore
import Foundation

private struct HashtagFeedSpecification: Codable, Sendable {
    let hashtag: String
    let kinds: [Int]
}

struct HashtagRelayEvent: Sendable {
    let relayURL: String
    let event: NostrEvent
}

actor HashtagFeedRepository {
    private static let kinds = [1, 6]
    private let identity: HashtagFeedIdentity
    private let accountID: String
    private let eventStore: NostrEventStore
    private let eventIngestor: HomeTimelineEventIngestor

    init(
        identity: HashtagFeedIdentity,
        accountID: String,
        eventStore: NostrEventStore
    ) {
        self.identity = identity
        self.accountID = accountID
        self.eventStore = eventStore
        eventIngestor = HomeTimelineEventIngestor(eventStore: eventStore)
    }

    func prepare(
        windowLimit: Int,
        restoreAnchorEventID: String?
    ) throws -> NostrFeedWindow? {
        let now = Int(Date().timeIntervalSince1970)
        let definition = try definition(now: now)
        let localEvents = try eventStore.events(
            kinds: Self.kinds,
            tagName: "t",
            tagValue: identity.hashtag,
            limit: max(windowLimit, 500),
            now: now
        )
        let memberships = memberships(
            for: localEvents,
            definition: definition,
            reason: "local",
            insertedAt: now
        )
        let sources = membershipSources(
            for: localEvents,
            definition: definition,
            insertedAt: now
        )
        let existing = try eventStore.feedDefinition(feedID: definition.feedID)
        if existing?.revision == definition.revision,
           existing?.specificationHash == definition.specificationHash {
            try eventStore.saveFeedDefinition(definition)
            try eventStore.saveFeedMemberships(memberships)
            try eventStore.saveFeedMembershipSources(sources)
        } else {
            try eventStore.replaceFeedProjection(
                definition,
                memberships: memberships,
                sources: sources
            )
        }
        return try window(
            limit: windowLimit,
            around: restoreAnchorEventID,
            now: now
        )
    }

    func ingest(
        _ relayEvents: [HashtagRelayEvent],
        reason: String,
        windowLimit: Int,
        restoreAnchorEventID: String?
    ) async throws -> NostrFeedWindow? {
        guard !relayEvents.isEmpty else {
            return try window(
                limit: windowLimit,
                around: restoreAnchorEventID
            )
        }
        let definition = try definition(
            now: Int(Date().timeIntervalSince1970)
        )
        for relayEvent in relayEvents where includes(relayEvent.event) {
            let insertedAt = Int(Date().timeIntervalSince1970)
            let membership = memberships(
                for: [relayEvent.event],
                definition: definition,
                reason: reason,
                insertedAt: insertedAt
            ).first
            _ = try await eventIngestor.ingest(
                event: relayEvent.event,
                relayURL: relayEvent.relayURL,
                feedMembership: membership,
                feedMembershipSources: membershipSources(
                    for: [relayEvent.event],
                    definition: definition,
                    insertedAt: insertedAt
                )
            )
        }
        return try window(
            limit: windowLimit,
            around: restoreAnchorEventID
        )
    }

    func projectLocalOlder(
        until: Int,
        windowLimit: Int,
        restoreAnchorEventID: String?
    ) throws -> NostrFeedWindow? {
        let now = Int(Date().timeIntervalSince1970)
        let definition = try definition(now: now)
        let events = try eventStore.events(
            kinds: Self.kinds,
            tagName: "t",
            tagValue: identity.hashtag,
            until: until,
            limit: 200,
            now: now
        )
        try eventStore.saveFeedMemberships(memberships(
            for: events,
            definition: definition,
            reason: "local-older",
            insertedAt: now
        ))
        try eventStore.saveFeedMembershipSources(membershipSources(
            for: events,
            definition: definition,
            insertedAt: now
        ))
        return try window(
            limit: windowLimit,
            around: restoreAnchorEventID
        )
    }

    func loadWindow(
        limit: Int,
        restoreAnchorEventID: String?
    ) throws -> NostrFeedWindow? {
        try window(limit: limit, around: restoreAnchorEventID)
    }

    private func window(
        limit: Int,
        around restoreAnchorEventID: String?,
        now: Int = Int(Date().timeIntervalSince1970)
    ) throws -> NostrFeedWindow? {
        let feedID = identity.feedID(accountID: accountID)
        if let restoreAnchorEventID,
           let anchored = try eventStore.feedWindow(
               feedID: feedID,
               aroundEventID: restoreAnchorEventID,
               leadingLimit: 80,
               trailingLimit: max(160, limit - 81),
               now: now
           ),
           anchored.memberships.contains(where: {
               $0.eventID == restoreAnchorEventID
           }) {
            return anchored
        }
        return try eventStore.feedWindow(
            feedID: feedID,
            limit: limit,
            now: now
        )
    }

    private func definition(now: Int) throws -> NostrFeedDefinitionRecord {
        let feedID = identity.feedID(accountID: accountID)
        let existing = try eventStore.feedDefinition(feedID: feedID)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let specificationJSON = try encoder.encode(HashtagFeedSpecification(
            hashtag: identity.hashtag,
            kinds: Self.kinds
        ))
        let specificationHash = HashtagFeedIdentity.stableHash(
            String(decoding: specificationJSON, as: UTF8.self)
        )
        let revision = existing?.specificationHash == specificationHash
            ? existing?.revision ?? 1
            : (existing?.revision ?? 0) + 1
        return NostrFeedDefinitionRecord(
            feedID: feedID,
            accountID: accountID,
            kind: "hashtag",
            specificationJSON: specificationJSON,
            specificationHash: specificationHash,
            sortPolicy: "created_at_desc_event_id_asc",
            revision: revision,
            createdAt: existing?.createdAt ?? now,
            updatedAt: now
        )
    }

    private func includes(_ event: NostrEvent) -> Bool {
        Self.kinds.contains(event.kind) && event.tags.contains { tag in
            tag.count >= 2 && tag[0] == "t" &&
                tag[1].precomposedStringWithCanonicalMapping
                    .lowercased() == identity.hashtag
        }
    }

    private func memberships(
        for events: [NostrEvent],
        definition: NostrFeedDefinitionRecord,
        reason: String,
        insertedAt: Int
    ) -> [NostrFeedMembershipRecord] {
        events.filter(includes).map { event in
            NostrFeedMembershipRecord(
                feedID: definition.feedID,
                eventID: event.id,
                subjectEventID: event.kind == 6
                    ? event.tags.last(where: {
                        $0.count >= 2 && $0[0] == "e"
                    })?[1]
                    : nil,
                sortTimestamp: event.createdAt,
                reason: reason,
                insertedAt: insertedAt,
                feedRevision: definition.revision
            )
        }
    }

    private func membershipSources(
        for events: [NostrEvent],
        definition: NostrFeedDefinitionRecord,
        insertedAt: Int
    ) -> [NostrFeedMembershipSourceRecord] {
        events.filter(includes).map { event in
            NostrFeedMembershipSourceRecord(
                feedID: definition.feedID,
                eventID: event.id,
                sourceType: "hashtag",
                sourceID: identity.hashtag,
                insertedAt: insertedAt,
                feedRevision: definition.revision
            )
        }
    }
}
