import AstrenzaCore

struct HomeFeedDefinitionPlanRequest: Equatable, Sendable {
    let accountID: String
    let followedPubkeys: [String]
    let now: Int
}

struct HomeFeedDefinitionPreparationRequest: Equatable, Sendable {
    let sequence: UInt64
    let accountID: String
    let followedPubkeys: [String]
    let liveEvents: [NostrEvent]
    let now: Int
    let windowLimit: Int
}

enum HomeFeedDefinitionWindowUpdate: Equatable, Sendable {
    case preserve
    case replace(NostrFeedWindow?)
}

struct HomeFeedDefinitionPreparation: Equatable, Sendable {
    let plan: HomeFeedDefinitionPlan
    let windowUpdate: HomeFeedDefinitionWindowUpdate
}

enum HomeFeedDefinitionPreparationOutcome: Equatable, Sendable {
    case prepared(HomeFeedDefinitionPreparation)
    case unavailable
    case failed
    case superseded
}

protocol HomeFeedDefinitionPreparing: Sendable {
    func plan(
        _ request: HomeFeedDefinitionPlanRequest
    ) async -> HomeFeedDefinitionPlan?

    func prepare(
        _ request: HomeFeedDefinitionPreparationRequest
    ) async -> HomeFeedDefinitionPreparationOutcome
}

actor HomeFeedDefinitionPreparer: HomeFeedDefinitionPreparing {
    private let eventStore: NostrEventStore?
    private var latestSequenceByFeedID: [String: UInt64] = [:]

    init(eventStore: NostrEventStore?) {
        self.eventStore = eventStore
    }

    func plan(
        _ request: HomeFeedDefinitionPlanRequest
    ) async -> HomeFeedDefinitionPlan? {
        guard let eventStore else { return nil }
        return try? definitionPlan(
            accountID: request.accountID,
            followedPubkeys: request.followedPubkeys,
            now: request.now,
            eventStore: eventStore
        )
    }

    func prepare(
        _ request: HomeFeedDefinitionPreparationRequest
    ) async -> HomeFeedDefinitionPreparationOutcome {
        guard let eventStore else { return .unavailable }
        let feedID = HomeFeedProjectionBuilder.feedID(accountID: request.accountID)
        guard accept(sequence: request.sequence, feedID: feedID) else { return .superseded }
        guard !Task.isCancelled else { return .superseded }

        let plan: HomeFeedDefinitionPlan
        do {
            guard let preparedPlan = try definitionPlan(
                accountID: request.accountID,
                followedPubkeys: request.followedPubkeys,
                now: request.now,
                eventStore: eventStore
            ) else { return .unavailable }
            plan = preparedPlan
        } catch {
            return .failed
        }

        if !plan.requiresProjectionReplacement {
            do {
                try repairProjectionIfNeeded(
                    plan: plan,
                    liveEvents: request.liveEvents,
                    insertedAt: request.now,
                    eventStore: eventStore
                )
            } catch {
                return .failed
            }
            return .prepared(HomeFeedDefinitionPreparation(
                plan: plan,
                windowUpdate: .preserve
            ))
        }

        guard !Task.isCancelled else { return .superseded }
        do {
            let events = try projectionEvents(
                allowedAuthors: Set(plan.authors),
                liveEvents: request.liveEvents,
                eventStore: eventStore
            )
            guard !Task.isCancelled else { return .superseded }
            try replaceProjection(
                plan: plan,
                events: events,
                reason: "projection-rebuild",
                insertedAt: request.now,
                eventStore: eventStore
            )
            let window = try eventStore.feedWindow(
                feedID: plan.definition.feedID,
                revision: plan.definition.revision,
                limit: request.windowLimit
            )
            return .prepared(HomeFeedDefinitionPreparation(
                plan: plan,
                windowUpdate: .replace(window)
            ))
        } catch {
            return .failed
        }
    }

    private func accept(sequence: UInt64, feedID: String) -> Bool {
        guard sequence >= latestSequenceByFeedID[feedID, default: 0] else { return false }
        latestSequenceByFeedID[feedID] = sequence
        return true
    }

    private func definitionPlan(
        accountID: String,
        followedPubkeys: [String],
        now: Int,
        eventStore: NostrEventStore
    ) throws -> HomeFeedDefinitionPlan? {
        let feedID = HomeFeedProjectionBuilder.feedID(accountID: accountID)
        return HomeFeedProjectionBuilder.definitionPlan(
            accountID: accountID,
            followedPubkeys: followedPubkeys,
            existingDefinition: try eventStore.feedDefinition(feedID: feedID),
            now: now
        )
    }

    private func repairProjectionIfNeeded(
        plan: HomeFeedDefinitionPlan,
        liveEvents: [NostrEvent],
        insertedAt: Int,
        eventStore: NostrEventStore
    ) throws {
        let memberships = try eventStore.feedMemberships(
            feedID: plan.definition.feedID,
            revision: plan.definition.revision,
            limit: 1
        )
        guard memberships.isEmpty, !Task.isCancelled else { return }
        let events = try projectionEvents(
            allowedAuthors: Set(plan.authors),
            liveEvents: liveEvents,
            eventStore: eventStore
        )
        guard !events.isEmpty, !Task.isCancelled else { return }
        try replaceProjection(
            plan: plan,
            events: events,
            reason: "projection-repair",
            insertedAt: insertedAt,
            eventStore: eventStore
        )
    }

    private func replaceProjection(
        plan: HomeFeedDefinitionPlan,
        events: [NostrEvent],
        reason: String,
        insertedAt: Int,
        eventStore: NostrEventStore
    ) throws {
        try eventStore.replaceFeedProjection(
            plan.definition,
            memberships: HomeFeedProjectionBuilder.memberships(
                events: events,
                feedID: plan.definition.feedID,
                feedRevision: plan.definition.revision,
                reason: reason,
                insertedAt: insertedAt
            ),
            sources: HomeFeedProjectionBuilder.membershipSources(
                events: events,
                feedID: plan.definition.feedID,
                feedRevision: plan.definition.revision,
                reason: reason,
                insertedAt: insertedAt
            )
        )
    }

    private func projectionEvents(
        allowedAuthors: Set<String>,
        liveEvents: [NostrEvent],
        eventStore: NostrEventStore
    ) throws -> [NostrEvent] {
        guard !allowedAuthors.isEmpty else { return [] }
        let authors = Array(allowedAuthors)
        let storedNotes = try eventStore.events(
            kind: 1,
            authors: authors,
            limit: 10_000
        )
        let storedReposts = try eventStore.events(
            kind: 6,
            authors: authors,
            limit: 10_000
        )
        var eventsByID: [String: NostrEvent] = [:]
        for event in liveEvents + storedNotes + storedReposts
        where (event.kind == 1 || event.kind == 6) &&
            allowedAuthors.contains(event.pubkey) {
            eventsByID[event.id] = event
        }
        return Array(eventsByID.values)
    }
}
