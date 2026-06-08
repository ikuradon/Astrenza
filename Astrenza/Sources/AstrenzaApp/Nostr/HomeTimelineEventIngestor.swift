import Foundation
import AstrenzaCore

struct HomeTimelineEventIngestResult: Equatable {
    let primaryEventID: String
    let embeddedEvent: NostrEvent?
    let savedEventIDs: [String]
}

struct HomeTimelineEventIngestor {
    let eventStore: NostrEventStore?

    func ingest(event: NostrEvent, relayURL: String) throws -> HomeTimelineEventIngestResult {
        let embeddedEvent = embeddedRepostTarget(from: event)
        let eventsToSave = [event] + (embeddedEvent.map { [$0] } ?? [])

        try eventStore?.save(events: eventsToSave)
        try eventStore?.recordEventSources(eventIDs: eventsToSave.map(\.id), relayURL: relayURL)

        return HomeTimelineEventIngestResult(
            primaryEventID: event.id,
            embeddedEvent: embeddedEvent,
            savedEventIDs: eventsToSave.map(\.id)
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
