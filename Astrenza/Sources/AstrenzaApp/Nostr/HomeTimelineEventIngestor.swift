import Foundation
import AstrenzaCore

struct HomeTimelineEventIngestResult: Equatable, Sendable {
    let primaryEventID: String
    let embeddedEvent: NostrEvent?
    let savedEventIDs: [String]
}

struct HomeTimelineDependencyCacheResult: Sendable {
    let cachedProfiles: [NostrEvent]
    let snapshot: NostrDependencyFetchCacheSnapshot
}

actor HomeTimelineEventIngestor {
    let eventStore: NostrEventStore?

    init(eventStore: NostrEventStore?) {
        self.eventStore = eventStore
    }

    func ingest(
        event: NostrEvent,
        relayURL: String,
        feedMembership: NostrFeedMembershipRecord? = nil,
        feedMembershipSources: [NostrFeedMembershipSourceRecord] = []
    ) throws -> HomeTimelineEventIngestResult {
        let embeddedEvent = embeddedRepostTarget(from: event)
        let eventsToSave = [event] + (embeddedEvent.map { [$0] } ?? [])
        let seenAt = Int(Date().timeIntervalSince1970)
        try eventStore?.ingest(
            events: eventsToSave,
            eventSources: eventsToSave.map { storedEvent in
                NostrEventSourceRecord(
                    eventID: storedEvent.id,
                    relayURL: relayURL,
                    firstSeenAt: seenAt,
                    lastSeenAt: seenAt
                )
            },
            feedMemberships: feedMembership.map { [$0] } ?? [],
            feedMembershipSources: feedMembershipSources,
            receivedAt: seenAt
        )

        return HomeTimelineEventIngestResult(
            primaryEventID: event.id,
            embeddedEvent: embeddedEvent,
            savedEventIDs: eventsToSave.map(\.id)
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
