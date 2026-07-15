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
    let resolvedRelays: [String]
}

enum HomeTimelineGapBackfillStoreAction: Equatable, Sendable {
    case applyRelayStatusTransition(HomeTimelineRelayStatusTransition)
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
    private let relayStatus: any HomeTimelineRelayStatusRecording

    init(
        gapBackfill: any HomeTimelineGapBackfillHandling,
        relayStatus: any HomeTimelineRelayStatusRecording
    ) {
        self.gapBackfill = gapBackfill
        self.relayStatus = relayStatus
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
                resolvedRelayCount: context.state.resolvedRelays.count,
                gap: gap,
                direction: direction
            ),
            effects: gapBackfillEffects(for: context)
        )
    }

    private func gapBackfillEffects(
        for context: HomeGapBackfillInteractionContext
    ) -> HomeTimelineGapBackfillEffects {
        let effects = context.effects
        return HomeTimelineGapBackfillEffects(
            recordDiagnostic: { diagnostic in
                guard let transition = self.relayStatus.recordDiagnostic(
                    diagnostic,
                    accountID: context.state.account?.pubkey,
                    resolvedRelays: context.state.resolvedRelays
                ) else { return }
                effects.apply(.applyRelayStatusTransition(transition))
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
