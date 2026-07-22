import AstrenzaCore
import Foundation

struct HomeFeedSpecification: Codable, Sendable {
    let authors: [String]
    let kinds: [Int]
}

struct HomeFeedDefinitionPlan: Equatable, Sendable {
    let definition: NostrFeedDefinitionRecord
    let sourceAuthors: [String]
    let authors: [String]
    let requiresProjectionReplacement: Bool
}

enum HomeFeedProjectionBuilder {
    static func feedID(accountID: String) -> String {
        "feed:home:\(accountID)"
    }

    static func definitionPlan(
        accountID: String,
        followedPubkeys: [String],
        existingDefinition: NostrFeedDefinitionRecord?,
        now: Int
    ) -> HomeFeedDefinitionPlan? {
        let sourceAuthors = followedPubkeys.isEmpty ? [accountID] : followedPubkeys
        let authors = sourceAuthors.sorted()
        let specification = HomeFeedSpecification(authors: authors, kinds: [1, 6])
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let specificationJSON = try? encoder.encode(specification) else { return nil }
        let specificationHash = stableSpecificationHash(specificationJSON)
        if let existingDefinition,
           existingDefinition.specificationHash == specificationHash {
            return HomeFeedDefinitionPlan(
                definition: existingDefinition,
                sourceAuthors: sourceAuthors,
                authors: authors,
                requiresProjectionReplacement: false
            )
        }

        return HomeFeedDefinitionPlan(
            definition: NostrFeedDefinitionRecord(
                feedID: feedID(accountID: accountID),
                accountID: accountID,
                kind: "home",
                specificationJSON: specificationJSON,
                specificationHash: specificationHash,
                sortPolicy: "created_at_desc_event_id_asc",
                revision: (existingDefinition?.revision ?? 0) + 1,
                createdAt: existingDefinition?.createdAt ?? now,
                updatedAt: now
            ),
            sourceAuthors: sourceAuthors,
            authors: authors,
            requiresProjectionReplacement: true
        )
    }

    static func memberships(
        events: [NostrEvent],
        feedID: String,
        feedRevision: Int? = nil,
        reason: String,
        insertedAt: Int
    ) -> [NostrFeedMembershipRecord] {
        events.compactMap { event in
            guard event.kind == 1 || event.kind == 6 else { return nil }
            let subjectEventID = event.kind == 6
                ? event.tags.last(where: { $0.count >= 2 && $0[0] == "e" })?[1]
                : nil
            return NostrFeedMembershipRecord(
                feedID: feedID,
                eventID: event.id,
                subjectEventID: subjectEventID,
                sortTimestamp: event.createdAt,
                reason: reason,
                insertedAt: insertedAt,
                feedRevision: feedRevision
            )
        }
    }

    static func membershipSources(
        events: [NostrEvent],
        feedID: String,
        feedRevision: Int? = nil,
        reason: String,
        insertedAt: Int,
        sourceRequestID: String? = nil
    ) -> [NostrFeedMembershipSourceRecord] {
        events
            .filter { $0.kind == 1 || $0.kind == 6 }
            .flatMap { event in
                var sources = [
                    NostrFeedMembershipSourceRecord(
                        feedID: feedID,
                        eventID: event.id,
                        sourceType: "author",
                        sourceID: event.pubkey,
                        insertedAt: insertedAt,
                        feedRevision: feedRevision
                    ),
                    NostrFeedMembershipSourceRecord(
                        feedID: feedID,
                        eventID: event.id,
                        sourceType: "ingest",
                        sourceID: reason,
                        insertedAt: insertedAt,
                        feedRevision: feedRevision
                    )
                ]
                if let sourceRequestID {
                    sources.append(NostrFeedMembershipSourceRecord(
                        feedID: feedID,
                        eventID: event.id,
                        sourceType: "sync-request",
                        sourceID: sourceRequestID,
                        insertedAt: insertedAt,
                        feedRevision: feedRevision
                    ))
                }
                return sources
            }
    }

    static func mergedWindow(
        _ current: NostrFeedWindow,
        with loaded: NostrFeedWindow,
        centeredOn anchorEventID: String,
        retainedLimit: Int
    ) -> NostrFeedWindow {
        guard current.definition.feedID == loaded.definition.feedID,
              current.definition.revision == loaded.definition.revision
        else { return loaded }

        let retainedMemberships = mergedMemberships(
            current.memberships,
            loaded.memberships,
            centeredOn: anchorEventID,
            limit: retainedLimit
        )
        let retainedEventIDs = Set(retainedMemberships.map(\.eventID))
        let boundaryGap = disconnectedBoundaryGap(
            current,
            loaded
        )

        var eventsByID = Dictionary(uniqueKeysWithValues: current.events.map { ($0.id, $0) })
        loaded.events.forEach { eventsByID[$0.id] = $0 }

        return NostrFeedWindow(
            definition: loaded.definition,
            memberships: retainedMemberships,
            events: retainedMemberships.compactMap { eventsByID[$0.eventID] },
            deletedItems: mergedDeletedItems(
                current.deletedItems,
                loaded.deletedItems,
                retainedEventIDs: retainedEventIDs
            ),
            gaps: mergedGaps(
                current.gaps,
                loaded.gaps,
                boundaryGap: boundaryGap,
                retainedEventIDs: retainedEventIDs
            )
        )
    }

    private static func mergedMemberships(
        _ current: [NostrFeedMembershipRecord],
        _ loaded: [NostrFeedMembershipRecord],
        centeredOn anchorEventID: String,
        limit: Int
    ) -> [NostrFeedMembershipRecord] {
        var membershipsByEventID = Dictionary(
            uniqueKeysWithValues: current.map { ($0.eventID, $0) }
        )
        loaded.forEach { membershipsByEventID[$0.eventID] = $0 }
        let ordered = membershipsByEventID.values.sorted { lhs, rhs in
            if lhs.sortTimestamp != rhs.sortTimestamp {
                return lhs.sortTimestamp > rhs.sortTimestamp
            }
            return lhs.eventID < rhs.eventID
        }
        return retainedMemberships(ordered, centeredOn: anchorEventID, limit: limit)
    }

    private static func mergedDeletedItems(
        _ current: [NostrDeletedFeedItemRecord],
        _ loaded: [NostrDeletedFeedItemRecord],
        retainedEventIDs: Set<String>
    ) -> [NostrDeletedFeedItemRecord] {
        var itemsByTarget = Dictionary(
            uniqueKeysWithValues: current.map { ($0.targetEventID, $0) }
        )
        loaded.forEach { item in
            if let existing = itemsByTarget[item.targetEventID],
               existing.deletedAt > item.deletedAt {
                return
            }
            itemsByTarget[item.targetEventID] = item
        }
        return itemsByTarget.values
            .filter { retainedEventIDs.contains($0.targetEventID) }
            .sorted { lhs, rhs in
                if lhs.sortTimestamp != rhs.sortTimestamp {
                    return lhs.sortTimestamp > rhs.sortTimestamp
                }
                return lhs.targetEventID < rhs.targetEventID
            }
    }

    private static func mergedGaps(
        _ current: [NostrFeedGapRecord],
        _ loaded: [NostrFeedGapRecord],
        boundaryGap: NostrFeedGapRecord?,
        retainedEventIDs: Set<String>
    ) -> [NostrFeedGapRecord] {
        var gapsByBoundary: [String: NostrFeedGapRecord] = [:]
        (current + loaded + [boundaryGap].compactMap { $0 }).forEach { gap in
            let key = "\(gap.newerEventID)\u{0}\(gap.olderEventID)"
            if let existing = gapsByBoundary[key], existing.updatedAt > gap.updatedAt {
                return
            }
            gapsByBoundary[key] = gap
        }
        return gapsByBoundary.values
            .filter {
                retainedEventIDs.contains($0.newerEventID) &&
                    retainedEventIDs.contains($0.olderEventID)
            }
            .sorted { lhs, rhs in
                if lhs.updatedAt != rhs.updatedAt {
                    return lhs.updatedAt > rhs.updatedAt
                }
                if lhs.newerEventID != rhs.newerEventID {
                    return lhs.newerEventID < rhs.newerEventID
                }
                return lhs.olderEventID < rhs.olderEventID
            }
    }

    private static func disconnectedBoundaryGap(
        _ current: NostrFeedWindow,
        _ loaded: NostrFeedWindow
    ) -> NostrFeedGapRecord? {
        let currentIDs = Set(current.memberships.map(\.eventID))
        guard currentIDs.isDisjoint(
            with: loaded.memberships.map(\.eventID)
        ),
        let currentNewest = orderedMemberships(current.memberships).first,
        let currentOldest = orderedMemberships(current.memberships).last,
        let loadedNewest = orderedMemberships(loaded.memberships).first,
        let loadedOldest = orderedMemberships(loaded.memberships).last
        else { return nil }

        let newerBoundary: NostrFeedMembershipRecord
        let olderBoundary: NostrFeedMembershipRecord
        if membershipPrecedes(loadedOldest, currentNewest) {
            newerBoundary = loadedOldest
            olderBoundary = currentNewest
        } else if membershipPrecedes(currentOldest, loadedNewest) {
            newerBoundary = currentOldest
            olderBoundary = loadedNewest
        } else {
            return nil
        }

        let timestamp = max(
            newerBoundary.insertedAt,
            olderBoundary.insertedAt
        )
        return NostrFeedGapRecord(
            feedID: loaded.definition.feedID,
            feedRevision: loaded.definition.revision,
            newerEventID: newerBoundary.eventID,
            olderEventID: olderBoundary.eventID,
            state: .unresolved,
            createdAt: timestamp,
            updatedAt: timestamp
        )
    }

    private static func orderedMemberships(
        _ memberships: [NostrFeedMembershipRecord]
    ) -> [NostrFeedMembershipRecord] {
        memberships.sorted(by: membershipPrecedes)
    }

    private static func membershipPrecedes(
        _ lhs: NostrFeedMembershipRecord,
        _ rhs: NostrFeedMembershipRecord
    ) -> Bool {
        if lhs.sortTimestamp != rhs.sortTimestamp {
            return lhs.sortTimestamp > rhs.sortTimestamp
        }
        return lhs.eventID < rhs.eventID
    }

    private static func stableSpecificationHash(_ data: Data) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in data {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(hash, radix: 16)
    }

    private static func retainedMemberships(
        _ memberships: [NostrFeedMembershipRecord],
        centeredOn anchorEventID: String,
        limit: Int
    ) -> [NostrFeedMembershipRecord] {
        guard limit > 0,
              memberships.count > limit,
              let anchorIndex = memberships.firstIndex(where: { $0.eventID == anchorEventID })
        else { return memberships }

        let preferredStart = max(0, anchorIndex - limit / 2)
        let start = min(preferredStart, memberships.count - limit)
        return Array(memberships[start..<(start + limit)])
    }
}
