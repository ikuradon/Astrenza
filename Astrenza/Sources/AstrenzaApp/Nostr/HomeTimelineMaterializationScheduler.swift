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
