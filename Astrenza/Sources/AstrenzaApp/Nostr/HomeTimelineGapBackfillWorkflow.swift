import AstrenzaCore

@MainActor
protocol HomeTimelineGapRequesting: Sendable {
    func requestGap(
        account: NostrAccount,
        gap: TimelineGap,
        direction: TimelineGapFillDirection,
        policy: NostrSyncPolicy
    ) async -> HomeTimelineBackwardRequestOutcome
}

extension HomeTimelineBackwardRequestCoordinator: HomeTimelineGapRequesting {}

struct HomeTimelineGapBackfillRequest {
    let account: NostrAccount?
    let hasRelayRuntime: Bool
    let resolvedRelayCount: Int
    let syncPolicy: NostrSyncPolicy
    let gap: TimelineGap
    let direction: TimelineGapFillDirection

    init(
        account: NostrAccount?,
        hasRelayRuntime: Bool,
        resolvedRelayCount: Int,
        syncPolicy: NostrSyncPolicy = .default(),
        gap: TimelineGap,
        direction: TimelineGapFillDirection
    ) {
        self.account = account
        self.hasRelayRuntime = hasRelayRuntime
        self.resolvedRelayCount = resolvedRelayCount
        self.syncPolicy = syncPolicy
        self.gap = gap
        self.direction = direction
    }
}

struct HomeTimelineGapBackfillEffects: Sendable {
    typealias DiagnosticEffect = @MainActor @Sendable (
        _ diagnostic: HomeTimelineBackwardRequestDiagnostic
    ) -> Void
    typealias ProjectionEffect = @MainActor @Sendable (
        _ account: NostrAccount,
        _ anchorEventID: String
    ) -> Void
    typealias VoidEffect = @MainActor @Sendable () -> Void

    let recordDiagnostic: DiagnosticEffect
    let reloadProjection: ProjectionEffect
    let materializeEntries: VoidEffect
}

@MainActor
final class HomeTimelineGapBackfillWorkflow {
    private let requester: any HomeTimelineGapRequesting

    init(requester: any HomeTimelineGapRequesting) {
        self.requester = requester
    }

    func backfill(
        _ request: HomeTimelineGapBackfillRequest,
        effects: HomeTimelineGapBackfillEffects
    ) async -> Bool {
        guard let account = request.account,
              request.hasRelayRuntime,
              request.resolvedRelayCount > 0
        else { return false }

        let outcome = await requester.requestGap(
            account: account,
            gap: request.gap,
            direction: request.direction,
            policy: request.syncPolicy
        )
        switch outcome {
        case .unavailable:
            return false
        case .failed(let diagnostic):
            effects.recordDiagnostic(diagnostic)
            return false
        case .completed:
            effects.reloadProjection(account, request.gap.newerPostID)
            effects.materializeEntries()
            return true
        }
    }
}
