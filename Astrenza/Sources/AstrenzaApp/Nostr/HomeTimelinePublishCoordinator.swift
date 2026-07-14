import AstrenzaCore
import Foundation

enum HomeTimelinePublishError: Error, Equatable {
    case noRelayDestinations
}

struct HomeTimelinePreparedPublish: Equatable, Sendable {
    let accountID: String
    let event: NostrEvent
    let destinationRelayURLs: [String]
    let createdAt: Int
}

struct HomeTimelinePublishCoordinator: Sendable {
    private let eventStore: NostrEventStore

    init(eventStore: NostrEventStore) {
        self.eventStore = eventStore
    }

    func prepare(
        _ input: NostrPublishInput,
        accountID: String,
        accountWriteRelays: [String],
        fallbackRelays: [String],
        signer: any NostrEventSigning,
        createdAt: Int = Int(Date().timeIntervalSince1970)
    ) async throws -> HomeTimelinePreparedPublish {
        let unsignedEvent = input.unsignedEvent(pubkey: accountID, createdAt: createdAt)
        let signedEvent = try await signer.sign(unsignedEvent)
        let destinationRelayURLs = NostrPublishDestinationResolver.relayDestinations(
            accountWriteRelays: accountWriteRelays,
            taggedUserReadRelays: [],
            fallbackRelays: fallbackRelays
        )
        guard !destinationRelayURLs.isEmpty else {
            throw HomeTimelinePublishError.noRelayDestinations
        }

        return HomeTimelinePreparedPublish(
            accountID: accountID,
            event: signedEvent,
            destinationRelayURLs: destinationRelayURLs,
            createdAt: createdAt
        )
    }

    func persist(
        _ publish: HomeTimelinePreparedPublish,
        feedDefinition: NostrFeedDefinitionRecord?
    ) throws -> NostrEvent {
        let record = try eventStore.enqueueOutboxEvent(
            publish.event,
            accountID: publish.accountID,
            relayURLs: publish.destinationRelayURLs,
            createdAt: publish.createdAt
        )
        let memberships = feedDefinition.map { definition in
            HomeFeedProjectionBuilder.memberships(
                events: [record.event],
                feedID: definition.feedID,
                feedRevision: definition.revision,
                reason: "outbox",
                insertedAt: publish.createdAt
            )
        } ?? []
        let membershipSources = feedDefinition.map { definition in
            HomeFeedProjectionBuilder.membershipSources(
                events: [record.event],
                feedID: definition.feedID,
                feedRevision: definition.revision,
                reason: "outbox",
                insertedAt: publish.createdAt
            )
        } ?? []
        try eventStore.ingest(
            events: [record.event],
            eventSources: [],
            feedMemberships: memberships,
            feedMembershipSources: membershipSources,
            receivedAt: publish.createdAt
        )
        return record.event
    }
}
