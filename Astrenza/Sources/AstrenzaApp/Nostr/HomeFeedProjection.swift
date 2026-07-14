import AstrenzaCore
import Foundation

struct HomeFeedSpecification: Codable, Sendable {
    let authors: [String]
    let kinds: [Int]
}

struct HomeFeedDefinitionPlan {
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

        var membershipsByEventID = Dictionary(
            uniqueKeysWithValues: current.memberships.map { ($0.eventID, $0) }
        )
        loaded.memberships.forEach { membershipsByEventID[$0.eventID] = $0 }
        let orderedMemberships = membershipsByEventID.values.sorted { lhs, rhs in
            if lhs.sortTimestamp != rhs.sortTimestamp {
                return lhs.sortTimestamp > rhs.sortTimestamp
            }
            return lhs.eventID < rhs.eventID
        }
        let retainedMemberships = retainedMemberships(
            orderedMemberships,
            centeredOn: anchorEventID,
            limit: retainedLimit
        )
        let retainedEventIDs = Set(retainedMemberships.map(\.eventID))

        var eventsByID = Dictionary(uniqueKeysWithValues: current.events.map { ($0.id, $0) })
        loaded.events.forEach { eventsByID[$0.id] = $0 }

        var deletedItemsByTarget = Dictionary(
            uniqueKeysWithValues: current.deletedItems.map { ($0.targetEventID, $0) }
        )
        loaded.deletedItems.forEach { item in
            if let existing = deletedItemsByTarget[item.targetEventID],
               existing.deletedAt > item.deletedAt {
                return
            }
            deletedItemsByTarget[item.targetEventID] = item
        }

        var gapsByBoundary: [String: NostrFeedGapRecord] = [:]
        (current.gaps + loaded.gaps).forEach { gap in
            let key = "\(gap.newerEventID)\u{0}\(gap.olderEventID)"
            if let existing = gapsByBoundary[key], existing.updatedAt > gap.updatedAt {
                return
            }
            gapsByBoundary[key] = gap
        }

        return NostrFeedWindow(
            definition: loaded.definition,
            memberships: retainedMemberships,
            events: retainedMemberships.compactMap { eventsByID[$0.eventID] },
            deletedItems: deletedItemsByTarget.values
                .filter { retainedEventIDs.contains($0.targetEventID) }
                .sorted { lhs, rhs in
                    if lhs.sortTimestamp != rhs.sortTimestamp {
                        return lhs.sortTimestamp > rhs.sortTimestamp
                    }
                    return lhs.targetEventID < rhs.targetEventID
                },
            gaps: gapsByBoundary.values
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
        )
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

@MainActor
final class HomeFeedProjectionController {
    let windowLimit: Int
    let retainedWindowLimit: Int
    let anchorLeadingLimit: Int
    let anchorTrailingLimit: Int

    private let eventStore: NostrEventStore?
    private(set) var definition: NostrFeedDefinitionRecord?
    private(set) var window: NostrFeedWindow?
    private(set) var generation: UInt64 = 0
    private(set) var sourceAuthors: [String]?

    init(
        eventStore: NostrEventStore?,
        windowLimit: Int = 240,
        retainedWindowLimit: Int = HomeTimelinePersistenceProjection.retainedEventLimit,
        anchorLeadingLimit: Int = 80,
        anchorTrailingLimit: Int = 160
    ) {
        self.eventStore = eventStore
        self.windowLimit = windowLimit
        self.retainedWindowLimit = retainedWindowLimit
        self.anchorLeadingLimit = anchorLeadingLimit
        self.anchorTrailingLimit = anchorTrailingLimit
    }

    func reset() {
        definition = nil
        window = nil
        sourceAuthors = nil
        generation &+= 1
    }

    func clearWindow() {
        window = nil
        generation &+= 1
    }

    func definitionPlan(
        accountID: String,
        followedPubkeys: [String],
        now: Int
    ) -> HomeFeedDefinitionPlan? {
        guard let eventStore else { return nil }
        let feedID = HomeFeedProjectionBuilder.feedID(accountID: accountID)
        return HomeFeedProjectionBuilder.definitionPlan(
            accountID: accountID,
            followedPubkeys: followedPubkeys,
            existingDefinition: try? eventStore.feedDefinition(feedID: feedID),
            now: now
        )
    }

    func ensureDefinition(
        accountID: String,
        followedPubkeys: [String],
        liveEvents: [NostrEvent],
        now: Int = Int(Date().timeIntervalSince1970)
    ) {
        guard let eventStore else { return }
        let nextSourceAuthors = followedPubkeys.isEmpty ? [accountID] : followedPubkeys
        if definition?.accountID == accountID, sourceAuthors == nextSourceAuthors {
            return
        }
        guard let plan = definitionPlan(
            accountID: accountID,
            followedPubkeys: followedPubkeys,
            now: now
        ) else { return }
        if !plan.requiresProjectionReplacement {
            definition = plan.definition
            sourceAuthors = nextSourceAuthors
            repairProjectionIfNeeded(
                definition: plan.definition,
                allowedAuthors: Set(plan.authors),
                liveEvents: liveEvents
            )
            return
        }

        do {
            let projectionEvents = cachedProjectionEvents(
                allowedAuthors: Set(plan.authors),
                liveEvents: liveEvents
            )
            let memberships = HomeFeedProjectionBuilder.memberships(
                events: projectionEvents,
                feedID: plan.definition.feedID,
                feedRevision: plan.definition.revision,
                reason: "projection-rebuild",
                insertedAt: now
            )
            try eventStore.replaceFeedProjection(
                plan.definition,
                memberships: memberships,
                sources: HomeFeedProjectionBuilder.membershipSources(
                    events: projectionEvents,
                    feedID: plan.definition.feedID,
                    feedRevision: plan.definition.revision,
                    reason: "projection-rebuild",
                    insertedAt: now
                )
            )
            activate(
                definition: plan.definition,
                window: try? eventStore.feedWindow(
                    feedID: plan.definition.feedID,
                    revision: plan.definition.revision,
                    limit: windowLimit
                ),
                sourceAuthors: plan.sourceAuthors
            )
        } catch {
            reset()
        }
    }

    @discardableResult
    func reloadNewest(
        accountID: String,
        followedPubkeys: [String],
        liveEvents: [NostrEvent]
    ) -> NostrFeedWindow? {
        ensureDefinition(
            accountID: accountID,
            followedPubkeys: followedPubkeys,
            liveEvents: liveEvents
        )
        guard let eventStore,
              let definition,
              let loaded = try? eventStore.feedWindow(
                feedID: definition.feedID,
                revision: definition.revision,
                limit: windowLimit
              )
        else { return nil }
        window = loaded
        generation &+= 1
        return loaded
    }

    @discardableResult
    func reload(
        accountID: String,
        followedPubkeys: [String],
        liveEvents: [NostrEvent],
        around anchorEventID: String?,
        mergingWithCurrentWindow: Bool
    ) -> NostrFeedWindow? {
        ensureDefinition(
            accountID: accountID,
            followedPubkeys: followedPubkeys,
            liveEvents: liveEvents
        )
        guard let eventStore, let definition else { return nil }
        let loaded: NostrFeedWindow?
        if let anchorEventID {
            loaded = try? eventStore.feedWindow(
                feedID: definition.feedID,
                revision: definition.revision,
                aroundEventID: anchorEventID,
                leadingLimit: anchorLeadingLimit,
                trailingLimit: anchorTrailingLimit
            )
        } else {
            loaded = try? eventStore.feedWindow(
                feedID: definition.feedID,
                revision: definition.revision,
                limit: windowLimit
            )
        }
        guard let loaded else { return nil }
        if let anchorEventID,
           !loaded.memberships.contains(where: { $0.eventID == anchorEventID }) {
            return nil
        }

        let nextWindow: NostrFeedWindow
        if mergingWithCurrentWindow,
           let window,
           let anchorEventID {
            nextWindow = HomeFeedProjectionBuilder.mergedWindow(
                window,
                with: loaded,
                centeredOn: anchorEventID,
                retainedLimit: retainedWindowLimit
            )
        } else {
            nextWindow = loaded
        }
        window = nextWindow
        generation &+= 1
        return nextWindow
    }

    func activate(
        definition: NostrFeedDefinitionRecord,
        window: NostrFeedWindow?,
        sourceAuthors: [String]
    ) {
        self.definition = definition
        self.window = window
        self.sourceAuthors = sourceAuthors
        generation &+= 1
    }

    func runtimeContext() -> HomeFeedRuntimeContext? {
        definition.map(HomeFeedRuntimeContext.init)
    }

    func isCurrent(_ context: HomeFeedRuntimeContext?, accountID: String?) -> Bool {
        guard let context else { return false }
        return context.matches(definition) && accountID == context.accountID
    }

    private func repairProjectionIfNeeded(
        definition: NostrFeedDefinitionRecord,
        allowedAuthors: Set<String>,
        liveEvents: [NostrEvent]
    ) {
        guard let eventStore else { return }
        let existingMemberships = (try? eventStore.feedMemberships(
            feedID: definition.feedID,
            revision: definition.revision,
            limit: 1
        )) ?? []
        guard existingMemberships.isEmpty else { return }
        let currentEvents = cachedProjectionEvents(
            allowedAuthors: allowedAuthors,
            liveEvents: liveEvents
        )
        guard !currentEvents.isEmpty else { return }
        let now = Int(Date().timeIntervalSince1970)
        try? eventStore.replaceFeedProjection(
            definition,
            memberships: HomeFeedProjectionBuilder.memberships(
                events: currentEvents,
                feedID: definition.feedID,
                feedRevision: definition.revision,
                reason: "projection-repair",
                insertedAt: now
            ),
            sources: HomeFeedProjectionBuilder.membershipSources(
                events: currentEvents,
                feedID: definition.feedID,
                feedRevision: definition.revision,
                reason: "projection-repair",
                insertedAt: now
            )
        )
    }

    private func cachedProjectionEvents(
        allowedAuthors: Set<String>,
        liveEvents: [NostrEvent]
    ) -> [NostrEvent] {
        guard let eventStore, !allowedAuthors.isEmpty else {
            return liveEvents.filter { event in
                (event.kind == 1 || event.kind == 6) && allowedAuthors.contains(event.pubkey)
            }
        }
        let authors = Array(allowedAuthors)
        let storedNotes = (try? eventStore.events(kind: 1, authors: authors, limit: 10_000)) ?? []
        let storedReposts = (try? eventStore.events(kind: 6, authors: authors, limit: 10_000)) ?? []
        var eventsByID: [String: NostrEvent] = [:]
        for event in liveEvents + storedNotes + storedReposts
        where (event.kind == 1 || event.kind == 6) && allowedAuthors.contains(event.pubkey) {
            eventsByID[event.id] = event
        }
        return Array(eventsByID.values)
    }
}
