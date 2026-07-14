import Foundation

struct HomeTimelineMaterializationPass: Equatable {
    let allowsRealtimeFollow: Bool
    let shouldReloadNewestProjection: Bool
}

@MainActor
final class HomeTimelineMaterializationScheduler {
    typealias MaterializeHandler = @MainActor @Sendable (_ allowsRealtimeFollow: Bool) -> Void

    let defaultDelayNanoseconds: UInt64

    private var scheduledTask: Task<Void, Never>?
    private var isScrollActive = false
    private var needsMaterializationAfterScroll = false
    private var followState = HomeTimelineMaterializationFollowState()
    private var renderFingerprint: [Int] = []
    private var needsNewestProjectionReload = false

    init(defaultDelayNanoseconds: UInt64 = 16_000_000) {
        self.defaultDelayNanoseconds = defaultDelayNanoseconds
    }

    var realtimeFollowSourceRevision: Int? {
        followState.sourceRevision
    }

    var hasPendingNewestProjectionReload: Bool {
        needsNewestProjectionReload
    }

    var hasPendingMaterialization: Bool {
        scheduledTask != nil || needsMaterializationAfterScroll
    }

    func reset(renderFingerprint: [Int] = []) {
        scheduledTask?.cancel()
        scheduledTask = nil
        isScrollActive = false
        needsMaterializationAfterScroll = false
        followState.reset()
        self.renderFingerprint = renderFingerprint
        needsNewestProjectionReload = false
    }

    func setScrollActive(_ isActive: Bool, materialize: @escaping MaterializeHandler) {
        guard isScrollActive != isActive else { return }
        isScrollActive = isActive
        if isActive {
            guard scheduledTask != nil else { return }
            needsMaterializationAfterScroll = true
            scheduledTask?.cancel()
            scheduledTask = nil
        } else if needsMaterializationAfterScroll {
            schedule(materialize: materialize)
        }
    }

    func requestNewestProjectionReload() {
        needsNewestProjectionReload = true
    }

    func clearNewestProjectionReload() {
        needsNewestProjectionReload = false
    }

    func beginMaterialization(
        allowsRealtimeFollow: Bool
    ) -> HomeTimelineMaterializationPass? {
        scheduledTask?.cancel()
        scheduledTask = nil
        guard !isScrollActive else {
            needsMaterializationAfterScroll = true
            followState.enqueue(allowsRealtimeFollow: allowsRealtimeFollow)
            return nil
        }
        followState.clearPendingPermission()
        needsMaterializationAfterScroll = false
        return HomeTimelineMaterializationPass(
            allowsRealtimeFollow: allowsRealtimeFollow,
            shouldReloadNewestProjection: needsNewestProjectionReload
        )
    }

    func schedule(
        delayNanoseconds: UInt64? = nil,
        allowsRealtimeFollow: Bool? = nil,
        materialize: @escaping MaterializeHandler
    ) {
        if let allowsRealtimeFollow {
            followState.enqueue(allowsRealtimeFollow: allowsRealtimeFollow)
        }
        needsMaterializationAfterScroll = true
        guard !isScrollActive, scheduledTask == nil else { return }
        let delay = delayNanoseconds ?? defaultDelayNanoseconds
        scheduledTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: delay)
            guard let self, !Task.isCancelled else { return }
            self.scheduledTask = nil
            let allowsRealtimeFollow = self.followState.consumePendingPermission()
            self.needsMaterializationAfterScroll = false
            materialize(allowsRealtimeFollow)
        }
    }

    func shouldPublish(renderFingerprint: [Int]) -> Bool {
        guard renderFingerprint != self.renderFingerprint else { return false }
        self.renderFingerprint = renderFingerprint
        return true
    }

    func replaceRenderFingerprint(_ renderFingerprint: [Int]) {
        self.renderFingerprint = renderFingerprint
    }

    func didPublish(revision: Int, allowsRealtimeFollow: Bool) {
        followState.didPublish(
            revision: revision,
            allowsRealtimeFollow: allowsRealtimeFollow
        )
    }
}

@MainActor
final class HomeTimelinePendingEventBuffer {
    typealias CountPublisher = @MainActor @Sendable (_ count: Int) -> Void
    typealias DelayProvider = @MainActor @Sendable (_ nanoseconds: UInt64) async throws -> Void

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
        onCountChange: @escaping CountPublisher
    ) -> Bool {
        guard eventIDs.insert(eventID).inserted else { return false }
        scheduleCountPublication(onCountChange: onCountChange)
        return true
    }

    @discardableResult
    func removeAll(onCountChange: @escaping CountPublisher) -> Bool {
        let hadEvents = !eventIDs.isEmpty
        eventIDs.removeAll()
        cancelCountPublication()
        publishCountIfNeeded(0, onCountChange: onCountChange)
        return hadEvents
    }

    func replaceEventIDs(
        _ eventIDs: Set<String>,
        onCountChange: @escaping CountPublisher
    ) {
        cancelCountPublication()
        self.eventIDs = eventIDs
        publishCountIfNeeded(eventIDs.count, onCountChange: onCountChange)
    }

    private func scheduleCountPublication(onCountChange: @escaping CountPublisher) {
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
            publishCountIfNeeded(eventIDs.count, onCountChange: onCountChange)
        }
    }

    private func cancelCountPublication() {
        publicationGeneration &+= 1
        countPublicationTask?.cancel()
        countPublicationTask = nil
    }

    private func publishCountIfNeeded(
        _ count: Int,
        onCountChange: CountPublisher
    ) {
        guard publishedCount != count else { return }
        publishedCount = count
        onCountChange(count)
    }
}

struct HomeTimelineMaterializationFollowState {
    private var pendingAllowsRealtimeFollow: Bool?
    private(set) var sourceRevision: Int?

    mutating func reset() {
        pendingAllowsRealtimeFollow = nil
        sourceRevision = nil
    }

    mutating func enqueue(allowsRealtimeFollow: Bool) {
        pendingAllowsRealtimeFollow =
            (pendingAllowsRealtimeFollow ?? true) && allowsRealtimeFollow
    }

    mutating func consumePendingPermission() -> Bool {
        defer { pendingAllowsRealtimeFollow = nil }
        return pendingAllowsRealtimeFollow == true
    }

    mutating func clearPendingPermission() {
        pendingAllowsRealtimeFollow = nil
    }

    mutating func didPublish(revision: Int, allowsRealtimeFollow: Bool) {
        sourceRevision = allowsRealtimeFollow ? revision : nil
    }
}
