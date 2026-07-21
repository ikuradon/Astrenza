import Foundation

struct HomeTimelineMaterializationPass: Equatable, Sendable {
    let generation: UInt64
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
    private var materializationGeneration: UInt64 = 0
    private var isMaterializationInFlight = false
    private var inFlightAllowsRealtimeFollow: Bool?

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
        scheduledTask != nil ||
            needsMaterializationAfterScroll ||
            isMaterializationInFlight
    }

    func reset(renderFingerprint: [Int] = []) {
        scheduledTask?.cancel()
        scheduledTask = nil
        isScrollActive = false
        needsMaterializationAfterScroll = false
        followState.reset()
        self.renderFingerprint = renderFingerprint
        needsNewestProjectionReload = false
        invalidateMaterialization(preservingRealtimeFollowIntent: false)
    }

    func setScrollActive(_ isActive: Bool, materialize: @escaping MaterializeHandler) {
        guard isScrollActive != isActive else { return }
        isScrollActive = isActive
        if isActive {
            guard scheduledTask != nil || isMaterializationInFlight else {
                return
            }
            needsMaterializationAfterScroll = true
            scheduledTask?.cancel()
            scheduledTask = nil
            invalidateMaterialization(preservingRealtimeFollowIntent: true)
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
            invalidateMaterialization(preservingRealtimeFollowIntent: true)
            return nil
        }
        followState.clearPendingPermission()
        needsMaterializationAfterScroll = false
        materializationGeneration &+= 1
        isMaterializationInFlight = true
        inFlightAllowsRealtimeFollow = allowsRealtimeFollow
        return HomeTimelineMaterializationPass(
            generation: materializationGeneration,
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
        if isMaterializationInFlight {
            invalidateMaterialization(preservingRealtimeFollowIntent: true)
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

    func completeMaterialization(
        _ pass: HomeTimelineMaterializationPass
    ) -> Bool {
        guard isMaterializationInFlight,
              !isScrollActive,
              pass.generation == materializationGeneration
        else { return false }
        isMaterializationInFlight = false
        inFlightAllowsRealtimeFollow = nil
        return true
    }

    func cancelMaterialization() {
        scheduledTask?.cancel()
        scheduledTask = nil
        needsMaterializationAfterScroll = false
        followState.clearPendingPermission()
        invalidateMaterialization(preservingRealtimeFollowIntent: false)
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

    private func invalidateMaterialization(
        preservingRealtimeFollowIntent: Bool
    ) {
        if preservingRealtimeFollowIntent,
           let inFlightAllowsRealtimeFollow {
            followState.enqueue(
                allowsRealtimeFollow: inFlightAllowsRealtimeFollow
            )
        }
        inFlightAllowsRealtimeFollow = nil
        materializationGeneration &+= 1
        isMaterializationInFlight = false
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
