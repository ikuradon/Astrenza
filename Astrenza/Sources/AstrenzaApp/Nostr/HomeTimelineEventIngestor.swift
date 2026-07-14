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
    ) throws -> HomeTimelineProjectedEventIngestResult {
        let projectsIntoCurrentFeed = feedContextsMatch(
            active: request.activeFeedContext,
            request: request.requestContext
        ) && request.requestContext?.includes(request.event) == true
        return try ingestProjectedEvent(
            event: request.event,
            relayURL: request.relayURL,
            activeFeedContext: request.activeFeedContext,
            projectionReason: .forward,
            sourceRequestID: request.sourceRequestID,
            projectsIntoCurrentFeed: projectsIntoCurrentFeed
        )
    }

    func ingestBackward(
        _ request: HomeTimelineBackwardEventIngestRequest
    ) throws -> HomeTimelineProjectedEventIngestResult {
        let projectsIntoCurrentFeed = request.projectionReason != nil &&
            request.requestContext != nil &&
            (request.activeRequestContext == nil || request.requestContext == request.activeRequestContext) &&
            feedContextsMatch(
                active: request.activeFeedContext,
                request: request.requestContext
            ) &&
            request.requestContext?.includes(request.event) == true
        return try ingestProjectedEvent(
            event: request.event,
            relayURL: request.relayURL,
            activeFeedContext: request.activeFeedContext,
            projectionReason: request.projectionReason,
            sourceRequestID: request.sourceRequestID,
            projectsIntoCurrentFeed: projectsIntoCurrentFeed
        )
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

    private func ingestProjectedEvent(
        event: NostrEvent,
        relayURL: String,
        activeFeedContext: HomeFeedRuntimeContext?,
        projectionReason: HomeTimelineFeedProjectionReason?,
        sourceRequestID: String?,
        projectsIntoCurrentFeed: Bool
    ) throws -> HomeTimelineProjectedEventIngestResult {
        let receivedAt = now()
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
        let eventResult = try ingest(
            event: event,
            relayURL: relayURL,
            feedMembership: feedMembership,
            feedMembershipSources: feedMembershipSources,
            receivedAt: receivedAt
        )
        return HomeTimelineProjectedEventIngestResult(
            eventResult: eventResult,
            projectsIntoCurrentFeed: projectsIntoCurrentFeed
        )
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
