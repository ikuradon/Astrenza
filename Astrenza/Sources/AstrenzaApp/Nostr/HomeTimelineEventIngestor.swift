import Foundation
import AstrenzaCore

struct HomeTimelineEventIngestResult: Equatable, Sendable {
    let primaryEventID: String
    let embeddedEvent: NostrEvent?
    let savedEventIDs: [String]
}

struct HomeTimelineProjectedEventIngestResult: Equatable, Sendable {
    let eventResult: HomeTimelineEventIngestResult
    let projectsIntoCurrentFeed: Bool
}

enum HomeTimelineFeedProjectionReason: String, Sendable {
    case forward
    case older
    case gap
}

struct HomeTimelineForwardEventIngestRequest: Sendable {
    let event: NostrEvent
    let relayURL: String
    let activeFeedContext: HomeFeedRuntimeContext?
    let requestContext: HomeFeedRuntimeContext?
    let sourceRequestID: String?
}

struct HomeTimelineBackwardEventIngestRequest: Sendable {
    let event: NostrEvent
    let relayURL: String
    let activeFeedContext: HomeFeedRuntimeContext?
    let requestContext: HomeFeedRuntimeContext?
    let activeRequestContext: HomeFeedRuntimeContext?
    let projectionReason: HomeTimelineFeedProjectionReason?
    let sourceRequestID: String?
}

enum HomeTimelineProjectedEventIngestRequest: Sendable {
    case forward(HomeTimelineForwardEventIngestRequest)
    case backward(HomeTimelineBackwardEventIngestRequest)
}

struct HomeTimelineDependencyCacheResult: Sendable {
    let cachedProfiles: [NostrEvent]
    let snapshot: NostrDependencyFetchCacheSnapshot
}

actor HomeTimelineEventIngestor {
    typealias Now = @Sendable () -> Int

    let eventStore: NostrEventStore?
    private let now: Now

    init(
        eventStore: NostrEventStore?,
        now: @escaping Now = { Int(Date().timeIntervalSince1970) }
    ) {
        self.eventStore = eventStore
        self.now = now
    }

    func ingestForward(
        _ request: HomeTimelineForwardEventIngestRequest
    ) async throws -> HomeTimelineProjectedEventIngestResult {
        try await ingestProjectedEvents([.forward(request)])[0]
    }

    func ingestBackward(
        _ request: HomeTimelineBackwardEventIngestRequest
    ) async throws -> HomeTimelineProjectedEventIngestResult {
        try await ingestProjectedEvents([.backward(request)])[0]
    }

    func ingestProjectedEvents(
        _ requests: [HomeTimelineProjectedEventIngestRequest]
    ) async throws -> [HomeTimelineProjectedEventIngestResult] {
        guard !requests.isEmpty else { return [] }
        let receivedAt = now()
        var events: [NostrEvent] = []
        var eventSources: [NostrEventSourceRecord] = []
        var feedMemberships: [NostrFeedMembershipRecord] = []
        var feedMembershipSources: [NostrFeedMembershipSourceRecord] = []
        var results: [HomeTimelineProjectedEventIngestResult] = []
        results.reserveCapacity(requests.count)

        for request in requests {
            let projection = projectedIngestDescription(
                for: request,
                receivedAt: receivedAt
            )
            let embeddedEvent = embeddedRepostTarget(from: projection.event)
            let eventsToSave = [projection.event] + (embeddedEvent.map { [$0] } ?? [])
            events.append(contentsOf: eventsToSave)
            eventSources.append(contentsOf: eventsToSave.map { storedEvent in
                NostrEventSourceRecord(
                    eventID: storedEvent.id,
                    relayURL: projection.relayURL,
                    firstSeenAt: receivedAt,
                    lastSeenAt: receivedAt
                )
            })
            if let membership = projection.feedMembership {
                feedMemberships.append(membership)
            }
            feedMembershipSources.append(contentsOf: projection.feedMembershipSources)
            results.append(HomeTimelineProjectedEventIngestResult(
                eventResult: HomeTimelineEventIngestResult(
                    primaryEventID: projection.event.id,
                    embeddedEvent: embeddedEvent,
                    savedEventIDs: eventsToSave.map(\.id)
                ),
                projectsIntoCurrentFeed: projection.projectsIntoCurrentFeed
            ))
        }

        try eventStore?.ingest(
            events: events,
            eventSources: eventSources,
            feedMemberships: feedMemberships,
            feedMembershipSources: feedMembershipSources,
            receivedAt: receivedAt
        )
        return results
    }

    func ingest(
        event: NostrEvent,
        relayURL: String,
        feedMembership: NostrFeedMembershipRecord? = nil,
        feedMembershipSources: [NostrFeedMembershipSourceRecord] = []
    ) throws -> HomeTimelineEventIngestResult {
        try ingest(
            event: event,
            relayURL: relayURL,
            feedMembership: feedMembership,
            feedMembershipSources: feedMembershipSources,
            receivedAt: now()
        )
    }

    private func projectedIngestDescription(
        for request: HomeTimelineProjectedEventIngestRequest,
        receivedAt: Int
    ) -> ProjectedIngestDescription {
        let event: NostrEvent
        let relayURL: String
        let activeFeedContext: HomeFeedRuntimeContext?
        let projectionReason: HomeTimelineFeedProjectionReason?
        let sourceRequestID: String?
        let projectsIntoCurrentFeed: Bool

        switch request {
        case .forward(let forward):
            event = forward.event
            relayURL = forward.relayURL
            activeFeedContext = forward.activeFeedContext
            projectionReason = .forward
            sourceRequestID = forward.sourceRequestID
            projectsIntoCurrentFeed = feedContextsMatch(
                active: forward.activeFeedContext,
                request: forward.requestContext
            ) && forward.requestContext?.includes(forward.event) == true
        case .backward(let backward):
            event = backward.event
            relayURL = backward.relayURL
            activeFeedContext = backward.activeFeedContext
            projectionReason = backward.projectionReason
            sourceRequestID = backward.sourceRequestID
            projectsIntoCurrentFeed = backward.projectionReason != nil &&
                backward.requestContext != nil &&
                (backward.activeRequestContext == nil ||
                    backward.requestContext == backward.activeRequestContext) &&
                feedContextsMatch(
                    active: backward.activeFeedContext,
                    request: backward.requestContext
                ) && backward.requestContext?.includes(backward.event) == true
        }

        let feedMembership = projectedFeedMembership(
            event: event,
            activeFeedContext: activeFeedContext,
            projectionReason: projectionReason,
            insertedAt: receivedAt,
            projectsIntoCurrentFeed: projectsIntoCurrentFeed
        )
        let feedMembershipSources = projectedFeedMembershipSources(
            event: event,
            activeFeedContext: activeFeedContext,
            projectionReason: projectionReason,
            sourceRequestID: sourceRequestID,
            insertedAt: receivedAt,
            projectsIntoCurrentFeed: projectsIntoCurrentFeed
        )
        return ProjectedIngestDescription(
            event: event,
            relayURL: relayURL,
            feedMembership: feedMembership,
            feedMembershipSources: feedMembershipSources,
            projectsIntoCurrentFeed: projectsIntoCurrentFeed
        )
    }

    private struct ProjectedIngestDescription {
        let event: NostrEvent
        let relayURL: String
        let feedMembership: NostrFeedMembershipRecord?
        let feedMembershipSources: [NostrFeedMembershipSourceRecord]
        let projectsIntoCurrentFeed: Bool
    }

    private func ingest(
        event: NostrEvent,
        relayURL: String,
        feedMembership: NostrFeedMembershipRecord?,
        feedMembershipSources: [NostrFeedMembershipSourceRecord],
        receivedAt: Int
    ) throws -> HomeTimelineEventIngestResult {
        let embeddedEvent = embeddedRepostTarget(from: event)
        let eventsToSave = [event] + (embeddedEvent.map { [$0] } ?? [])
        try eventStore?.ingest(
            events: eventsToSave,
            eventSources: eventsToSave.map { storedEvent in
                NostrEventSourceRecord(
                    eventID: storedEvent.id,
                    relayURL: relayURL,
                    firstSeenAt: receivedAt,
                    lastSeenAt: receivedAt
                )
            },
            feedMemberships: feedMembership.map { [$0] } ?? [],
            feedMembershipSources: feedMembershipSources,
            receivedAt: receivedAt
        )

        return HomeTimelineEventIngestResult(
            primaryEventID: event.id,
            embeddedEvent: embeddedEvent,
            savedEventIDs: eventsToSave.map(\.id)
        )
    }

    private func feedContextsMatch(
        active: HomeFeedRuntimeContext?,
        request: HomeFeedRuntimeContext?
    ) -> Bool {
        guard let active, let request else { return false }
        return active.feedID == request.feedID &&
            active.accountID == request.accountID &&
            active.revision == request.revision &&
            active.specificationHash == request.specificationHash
    }

    private func projectedFeedMembership(
        event: NostrEvent,
        activeFeedContext: HomeFeedRuntimeContext?,
        projectionReason: HomeTimelineFeedProjectionReason?,
        insertedAt: Int,
        projectsIntoCurrentFeed: Bool
    ) -> NostrFeedMembershipRecord? {
        guard projectsIntoCurrentFeed,
              let activeFeedContext,
              let projectionReason
        else { return nil }
        return HomeFeedProjectionBuilder.memberships(
            events: [event],
            feedID: activeFeedContext.feedID,
            feedRevision: activeFeedContext.revision,
            reason: projectionReason.rawValue,
            insertedAt: insertedAt
        ).first
    }

    private func projectedFeedMembershipSources(
        event: NostrEvent,
        activeFeedContext: HomeFeedRuntimeContext?,
        projectionReason: HomeTimelineFeedProjectionReason?,
        sourceRequestID: String?,
        insertedAt: Int,
        projectsIntoCurrentFeed: Bool
    ) -> [NostrFeedMembershipSourceRecord] {
        guard projectsIntoCurrentFeed,
              let activeFeedContext,
              let projectionReason
        else { return [] }
        return HomeFeedProjectionBuilder.membershipSources(
            events: [event],
            feedID: activeFeedContext.feedID,
            feedRevision: activeFeedContext.revision,
            reason: projectionReason.rawValue,
            insertedAt: insertedAt,
            sourceRequestID: sourceRequestID
        )
    }

    func dependencyCacheResult(
        dependencies: NostrEventDependencies,
        liveMetadataEvents: [NostrEvent],
        liveNoteEventIDs: Set<String>,
        now: Int
    ) -> HomeTimelineDependencyCacheResult {
        guard let eventStore else {
            return HomeTimelineDependencyCacheResult(
                cachedProfiles: [],
                snapshot: NostrDependencyFetchCacheSnapshot(
                    profileReceivedAtByPubkey: Dictionary(
                        uniqueKeysWithValues: liveMetadataEvents.map { ($0.pubkey, now) }
                    ),
                    sourceEventIDs: liveNoteEventIDs
                )
            )
        }

        let profilePubkeys = Set(dependencies.profilePubkeys)
        let cachedProfiles = (try? eventStore.latestReplaceableEvents(
            pubkeys: profilePubkeys,
            kind: 0
        )) ?? []
        let profileReceivedAtByPubkey = ((try? eventStore.latestReplaceableEventReceivedAtByPubkey(
            pubkeys: profilePubkeys,
            kind: 0
        )) ?? [:]).merging(
            Dictionary(uniqueKeysWithValues: liveMetadataEvents.map { ($0.pubkey, now) }),
            uniquingKeysWith: { stored, _ in stored }
        )
        let cachedSourceEventIDs = Set(
            ((try? eventStore.events(ids: dependencies.sourceEventIDs)) ?? []).map(\.id)
        )
        return HomeTimelineDependencyCacheResult(
            cachedProfiles: cachedProfiles,
            snapshot: NostrDependencyFetchCacheSnapshot(
                profileReceivedAtByPubkey: profileReceivedAtByPubkey,
                sourceEventIDs: liveNoteEventIDs.union(cachedSourceEventIDs)
            )
        )
    }

    func embeddedRepostTarget(from event: NostrEvent) -> NostrEvent? {
        guard event.kind == 6,
              let data = event.content.data(using: .utf8),
              let embedded = try? JSONDecoder().decode(NostrEvent.self, from: data),
              embedded.kind == 1,
              embedded.hasValidShape
        else {
            return nil
        }
        return embedded
    }
}
