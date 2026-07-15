import AstrenzaCore

@MainActor
protocol HomeTimelineGapBackfillHandling: AnyObject {
    func backfill(
        _ request: HomeTimelineGapBackfillRequest,
        effects: HomeTimelineGapBackfillEffects
    ) async -> Bool
}

extension HomeTimelineGapBackfillWorkflow: HomeTimelineGapBackfillHandling {}

struct HomeTimelineGapBackfillInteractionState: Sendable {
    let account: NostrAccount?
    let hasRelayRuntime: Bool
    let resolvedRelayCount: Int
}

enum HomeTimelineGapBackfillStoreAction: Equatable, Sendable {
    case recordDiagnostic(HomeTimelineBackwardRequestDiagnostic)
    case reloadProjection(account: NostrAccount, anchorEventID: String)
    case materializeEntries
}

struct HomeGapBackfillInteractionEffects: Sendable {
    typealias ApplicationEffect = @MainActor @Sendable (
        _ action: HomeTimelineGapBackfillStoreAction
    ) -> Void

    let apply: ApplicationEffect
}

struct HomeGapBackfillInteractionContext: Sendable {
    let state: HomeTimelineGapBackfillInteractionState
    let effects: HomeGapBackfillInteractionEffects
}

@MainActor
final class HomeGapBackfillInteractionWorkflow {
    private let gapBackfill: any HomeTimelineGapBackfillHandling

    init(gapBackfill: any HomeTimelineGapBackfillHandling) {
        self.gapBackfill = gapBackfill
    }

    func backfill(
        gap: TimelineGap,
        direction: TimelineGapFillDirection,
        context: HomeGapBackfillInteractionContext
    ) async -> Bool {
        await gapBackfill.backfill(
            HomeTimelineGapBackfillRequest(
                account: context.state.account,
                hasRelayRuntime: context.state.hasRelayRuntime,
                resolvedRelayCount: context.state.resolvedRelayCount,
                gap: gap,
                direction: direction
            ),
            effects: gapBackfillEffects(for: context.effects)
        )
    }

    private func gapBackfillEffects(
        for effects: HomeGapBackfillInteractionEffects
    ) -> HomeTimelineGapBackfillEffects {
        HomeTimelineGapBackfillEffects(
            recordDiagnostic: { diagnostic in
                effects.apply(.recordDiagnostic(diagnostic))
            },
            reloadProjection: { account, anchorEventID in
                effects.apply(.reloadProjection(
                    account: account,
                    anchorEventID: anchorEventID
                ))
            },
            materializeEntries: {
                effects.apply(.materializeEntries)
            }
        )
    }
}
