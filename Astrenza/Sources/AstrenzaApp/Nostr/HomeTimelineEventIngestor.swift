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
        let embeddedEvent = event.embeddedRepostTarget
        let eventsToSave = [event] + (embeddedEvent.map { [$0] } ?? [])

        try eventStore?.save(events: eventsToSave)
        try eventStore?.recordEventSources(eventIDs: eventsToSave.map(\.id), relayURL: relayURL)

        return HomeTimelineEventIngestResult(
            primaryEventID: event.id,
            embeddedEvent: embeddedEvent,
            savedEventIDs: eventsToSave.map(\.id)
        )
    }
}
