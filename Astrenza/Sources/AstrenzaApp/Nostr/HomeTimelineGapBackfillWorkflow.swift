import AstrenzaCore

@MainActor
protocol HomeTimelineGapRequesting: Sendable {
    func requestGap(
        account: NostrAccount,
        gap: TimelineGap,
        direction: TimelineGapFillDirection
    ) async -> HomeTimelineBackwardRequestOutcome
}

extension HomeTimelineBackwardRequestCoordinator: HomeTimelineGapRequesting {}

@MainActor
protocol HomeTimelineGapRequestPersisting: Sendable {
    func markGapRequested(
        newerEventID: String,
        olderEventID: String,
        definition: NostrFeedDefinitionRecord
    ) throws
}

extension HomeTimelineBackfillPersistence: HomeTimelineGapRequestPersisting {}

struct HomeTimelineGapBackfillRequest {
    let account: NostrAccount?
    let hasRelayRuntime: Bool
    let resolvedRelayCount: Int
    let gap: TimelineGap
    let direction: TimelineGapFillDirection
}

enum HomeTimelineGapBackfillCommand: Equatable, Sendable {
    case recordDiagnostic(HomeTimelineBackwardRequestDiagnostic)
    case reloadProjection(account: NostrAccount, anchorEventID: String)
    case materializeEntries
}

struct HomeTimelineGapBackfillHandlers: Sendable {
    typealias CommandHandler = @MainActor @Sendable (
        _ command: HomeTimelineGapBackfillCommand
    ) -> Void

    let perform: CommandHandler
}

@MainActor
final class HomeTimelineGapBackfillWorkflow {
    private let requester: any HomeTimelineGapRequesting
    private let persistence: any HomeTimelineGapRequestPersisting

    init(
        requester: any HomeTimelineGapRequesting,
        persistence: any HomeTimelineGapRequestPersisting
    ) {
        self.requester = requester
        self.persistence = persistence
    }

    func backfill(
        _ request: HomeTimelineGapBackfillRequest,
        handlers: HomeTimelineGapBackfillHandlers
    ) async -> Bool {
        guard let account = request.account,
              request.hasRelayRuntime,
              request.resolvedRelayCount > 0
        else { return false }

        let outcome = await requester.requestGap(
            account: account,
            gap: request.gap,
            direction: request.direction
        )
        switch outcome {
        case .unavailable:
            return false
        case .failed(let diagnostic):
            handlers.perform(.recordDiagnostic(diagnostic))
            return false
        case .installed(let definition):
            try? persistence.markGapRequested(
                newerEventID: request.gap.newerPostID,
                olderEventID: request.gap.olderPostID,
                definition: definition
            )
            handlers.perform(.reloadProjection(
                account: account,
                anchorEventID: request.gap.newerPostID
            ))
            handlers.perform(.materializeEntries)
            return true
        }
    }
}
