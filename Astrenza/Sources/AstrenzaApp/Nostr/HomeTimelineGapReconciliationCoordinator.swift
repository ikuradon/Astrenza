import AstrenzaCore

protocol HomeTimelineGapReconciling: Sendable {
    func reconcile(
        newerEvent: NostrEvent,
        olderEvent: NostrEvent,
        context: HomeFeedRuntimeContext,
        relays: [String],
        inMemoryEvents: [NostrEvent]
    ) async -> HomeTimelineGapReconciliationOutput
}

extension HomeTimelineGapReconciler: HomeTimelineGapReconciling {}

protocol HomeTimelineGapReconciliationPersisting: Sendable {
    func apply(
        _ result: HomeTimelineGapReconciliationResult,
        gap: PendingGapBackfill,
        context: HomeFeedRuntimeContext
    ) -> HomeTimelineGapPersistenceOutcome
}

extension HomeTimelineBackfillPersistence: HomeTimelineGapReconciliationPersisting {}

struct HomeTimelineGapReconciliationDiagnostic: Equatable, Sendable {
    let relayURL: String
    let subscriptionID: String?
    let message: String
}

struct HomeTimelineGapReconciliationExecution: Equatable, Sendable {
    let recoveredEvents: [NostrEvent]
    let diagnostics: [HomeTimelineGapReconciliationDiagnostic]
    let reloadsProjection: Bool
}

struct HomeTimelineGapReconciliationCoordinator: Sendable {
    private let reconciler: any HomeTimelineGapReconciling
    private let persistence: any HomeTimelineGapReconciliationPersisting
    private let maximumRelayCount: Int

    init(
        reconciler: any HomeTimelineGapReconciling,
        persistence: any HomeTimelineGapReconciliationPersisting,
        maximumRelayCount: Int = 4
    ) {
        self.reconciler = reconciler
        self.persistence = persistence
        self.maximumRelayCount = maximumRelayCount
    }

    func reconcile(
        newerEvent: NostrEvent,
        olderEvent: NostrEvent,
        gap: PendingGapBackfill,
        context: HomeFeedRuntimeContext,
        relays: [String],
        inMemoryEvents: [NostrEvent]
    ) async -> HomeTimelineGapReconciliationExecution {
        let selectedRelays = Array(relays.prefix(maximumRelayCount))
        let output = await reconciler.reconcile(
            newerEvent: newerEvent,
            olderEvent: olderEvent,
            context: context,
            relays: selectedRelays,
            inMemoryEvents: inMemoryEvents
        )
        var diagnostics = output.diagnostics.map {
            HomeTimelineGapReconciliationDiagnostic(
                relayURL: $0.relayURL,
                subscriptionID: "astrenza-neg-gap",
                message: $0.message
            )
        }
        let fallbackRelayURL = relays.first ?? "runtime"

        switch persistence.apply(output.result, gap: gap, context: context) {
        case .verifiedComplete(let resolveFailure):
            if let resolveFailure {
                diagnostics.append(HomeTimelineGapReconciliationDiagnostic(
                    relayURL: fallbackRelayURL,
                    subscriptionID: nil,
                    message: "gap resolve failed: \(resolveFailure)"
                ))
            }
            return HomeTimelineGapReconciliationExecution(
                recoveredEvents: [],
                diagnostics: diagnostics,
                reloadsProjection: true
            )
        case .indeterminate:
            diagnostics.append(HomeTimelineGapReconciliationDiagnostic(
                relayURL: fallbackRelayURL,
                subscriptionID: "astrenza-neg-gap",
                message: "gap reconciliation was inconclusive"
            ))
            return HomeTimelineGapReconciliationExecution(
                recoveredEvents: [],
                diagnostics: diagnostics,
                reloadsProjection: true
            )
        case .recovered(let recoveredEvents):
            return HomeTimelineGapReconciliationExecution(
                recoveredEvents: recoveredEvents,
                diagnostics: diagnostics,
                reloadsProjection: true
            )
        case .recoveryFailed(let message):
            diagnostics.append(HomeTimelineGapReconciliationDiagnostic(
                relayURL: fallbackRelayURL,
                subscriptionID: "astrenza-gap-events",
                message: "gap negentropy save failed: \(message)"
            ))
            return HomeTimelineGapReconciliationExecution(
                recoveredEvents: [],
                diagnostics: diagnostics,
                reloadsProjection: false
            )
        }
    }
}
