import AstrenzaCore

enum HomeFeedWindowSelection: Sendable {
    case newest(limit: Int)
    case anchored(
        eventID: String,
        leadingLimit: Int,
        trailingLimit: Int,
        retainedLimit: Int
    )
}

struct HomeFeedWindowLoadRequest: Sendable {
    let definition: NostrFeedDefinitionRecord
    let selection: HomeFeedWindowSelection
    let currentWindow: NostrFeedWindow?
}

protocol HomeFeedWindowLoading: Sendable {
    func load(
        _ request: HomeFeedWindowLoadRequest
    ) async throws -> sending NostrFeedWindow?
}

nonisolated struct HomeFeedWindowLoader: HomeFeedWindowLoading {
    private let eventStore: NostrEventStore?

    init(eventStore: NostrEventStore?) {
        self.eventStore = eventStore
    }

    @concurrent
    func load(
        _ request: HomeFeedWindowLoadRequest
    ) async throws -> sending NostrFeedWindow? {
        guard !Task.isCancelled, let eventStore else { return nil }

        switch request.selection {
        case .newest(let limit):
            let loaded = try eventStore.feedWindow(
                feedID: request.definition.feedID,
                revision: request.definition.revision,
                limit: limit
            )
            return Task.isCancelled ? nil : loaded

        case .anchored(
            let eventID,
            let leadingLimit,
            let trailingLimit,
            let retainedLimit
        ):
            guard let loaded = try eventStore.feedWindow(
                feedID: request.definition.feedID,
                revision: request.definition.revision,
                aroundEventID: eventID,
                leadingLimit: leadingLimit,
                trailingLimit: trailingLimit
            ), loaded.memberships.contains(where: { $0.eventID == eventID })
            else { return nil }
            guard !Task.isCancelled else { return nil }
            guard let currentWindow = request.currentWindow else { return loaded }
            return HomeFeedProjectionBuilder.mergedWindow(
                currentWindow,
                with: loaded,
                centeredOn: eventID,
                retainedLimit: retainedLimit
            )
        }
    }
}
