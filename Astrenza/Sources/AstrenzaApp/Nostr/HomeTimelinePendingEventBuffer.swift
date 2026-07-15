import Foundation

struct HomeTimelinePendingEventCountPublication: Equatable, Sendable {
    let count: Int
}

typealias HomeTimelinePendingEventCountHandler = @MainActor @Sendable (
    _ publication: HomeTimelinePendingEventCountPublication
) -> Void

@MainActor
final class HomeTimelinePendingEventBuffer {
    typealias DelayProvider = @MainActor @Sendable (
        _ nanoseconds: UInt64
    ) async throws -> Void

    private let countPublishDelayNanoseconds: UInt64
    private let delay: DelayProvider
    private var eventIDs = Set<String>()
    private var countPublicationTask: Task<Void, Never>?
    private var publicationGeneration: UInt64 = 0

    private(set) var publishedCount = 0

    init(
        countPublishDelayNanoseconds: UInt64 = 100_000_000,
        delay: @escaping DelayProvider = { nanoseconds in
            try await Task.sleep(nanoseconds: nanoseconds)
        }
    ) {
        self.countPublishDelayNanoseconds = countPublishDelayNanoseconds
        self.delay = delay
    }

    var isEmpty: Bool {
        eventIDs.isEmpty
    }

    var hasEvents: Bool {
        !eventIDs.isEmpty
    }

    var hasScheduledCountPublication: Bool {
        countPublicationTask != nil
    }

    @discardableResult
    func insert(
        eventID: String,
        onCountPublication: @escaping HomeTimelinePendingEventCountHandler
    ) -> Bool {
        guard eventIDs.insert(eventID).inserted else { return false }
        scheduleCountPublication(onCountPublication: onCountPublication)
        return true
    }

    @discardableResult
    func removeAll(
        onCountPublication: @escaping HomeTimelinePendingEventCountHandler
    ) -> Bool {
        let hadEvents = !eventIDs.isEmpty
        eventIDs.removeAll()
        cancelCountPublication()
        publishCountIfNeeded(0, onCountPublication: onCountPublication)
        return hadEvents
    }

    func replaceEventIDs(
        _ eventIDs: Set<String>,
        onCountPublication: @escaping HomeTimelinePendingEventCountHandler
    ) {
        cancelCountPublication()
        self.eventIDs = eventIDs
        publishCountIfNeeded(
            eventIDs.count,
            onCountPublication: onCountPublication
        )
    }

    private func scheduleCountPublication(
        onCountPublication: @escaping HomeTimelinePendingEventCountHandler
    ) {
        guard countPublicationTask == nil else { return }
        publicationGeneration &+= 1
        let expectedGeneration = publicationGeneration
        let delay = self.delay
        let countPublishDelayNanoseconds = self.countPublishDelayNanoseconds
        countPublicationTask = Task { @MainActor [weak self] in
            do {
                try await delay(countPublishDelayNanoseconds)
            } catch {
                guard let self,
                      publicationGeneration == expectedGeneration
                else { return }
                countPublicationTask = nil
                return
            }
            guard !Task.isCancelled,
                  let self,
                  publicationGeneration == expectedGeneration
            else { return }
            countPublicationTask = nil
            publishCountIfNeeded(
                eventIDs.count,
                onCountPublication: onCountPublication
            )
        }
    }

    private func cancelCountPublication() {
        publicationGeneration &+= 1
        countPublicationTask?.cancel()
        countPublicationTask = nil
    }

    private func publishCountIfNeeded(
        _ count: Int,
        onCountPublication: HomeTimelinePendingEventCountHandler
    ) {
        guard publishedCount != count else { return }
        publishedCount = count
        onCountPublication(HomeTimelinePendingEventCountPublication(count: count))
    }
}
