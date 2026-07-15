import AstrenzaCore
import Testing
@testable import Astrenza

@Suite("Home timeline gap backfill interaction workflow")
@MainActor
struct HomeTimelineGapInteractionTests {
    @Test("Request and result cross the typed boundary")
    func routesRequestAndResult() async throws {
        let fixture = GapBackfillInteractionFixture(didBackfill: true)

        let didBackfill = await fixture.workflow.backfill(
            gap: fixture.gap,
            direction: .newer,
            context: fixture.context
        )

        #expect(didBackfill)
        let request = try #require(fixture.handler.requests.first)
        #expect(request.account == fixture.account)
        #expect(request.hasRelayRuntime)
        #expect(request.resolvedRelayCount == 2)
        #expect(request.gap.id == fixture.gap.id)
        #expect(request.direction == .newer)
    }

    @Test("Every gap mutation uses one typed boundary")
    func routesEveryApplicationEffect() async throws {
        let fixture = GapBackfillInteractionFixture()

        _ = await fixture.workflow.backfill(
            gap: fixture.gap,
            direction: .older,
            context: fixture.context
        )
        let effects = try #require(fixture.handler.effects)
        effects.recordDiagnostic(fixture.diagnostic)
        effects.reloadProjection(fixture.account, fixture.gap.newerPostID)
        effects.materializeEntries()

        #expect(fixture.probe.actions == [
            .recordDiagnostic(fixture.diagnostic),
            .reloadProjection(
                account: fixture.account,
                anchorEventID: fixture.gap.newerPostID
            ),
            .materializeEntries
        ])
    }
}

@MainActor
private final class GapBackfillInteractionHandlerSpy:
    HomeTimelineGapBackfillHandling {
    let didBackfill: Bool
    private(set) var requests: [HomeTimelineGapBackfillRequest] = []
    private(set) var effects: HomeTimelineGapBackfillEffects?

    init(didBackfill: Bool) {
        self.didBackfill = didBackfill
    }

    func backfill(
        _ request: HomeTimelineGapBackfillRequest,
        effects: HomeTimelineGapBackfillEffects
    ) async -> Bool {
        requests.append(request)
        self.effects = effects
        return didBackfill
    }
}

@MainActor
private final class GapBackfillInteractionProbe {
    private(set) var actions: [HomeTimelineGapBackfillStoreAction] = []

    var effects: HomeGapBackfillInteractionEffects {
        HomeGapBackfillInteractionEffects(
            apply: { [self] action in
                actions.append(action)
            }
        )
    }
}

@MainActor
private struct GapBackfillInteractionFixture {
    let account = NostrAccount(
        pubkey: String(repeating: "a", count: 64),
        displayIdentifier: "gap",
        readOnly: true
    )
    let gap = TimelineGap(
        id: "gap-newer-older",
        newerPostID: "newer",
        olderPostID: "older",
        missingEstimate: 8,
        relayCount: 2,
        state: .needsBackfill,
        backfilledPosts: []
    )
    let diagnostic = HomeTimelineBackwardRequestDiagnostic(
        relayURL: "wss://failed.example",
        subscriptionID: "astrenza-gap-notes",
        message: "gap enqueue failed"
    )
    let probe = GapBackfillInteractionProbe()
    let handler: GapBackfillInteractionHandlerSpy
    let workflow: HomeGapBackfillInteractionWorkflow

    init(didBackfill: Bool = false) {
        let handler = GapBackfillInteractionHandlerSpy(
            didBackfill: didBackfill
        )
        self.handler = handler
        workflow = HomeGapBackfillInteractionWorkflow(
            gapBackfill: handler
        )
    }

    var context: HomeGapBackfillInteractionContext {
        HomeGapBackfillInteractionContext(
            state: HomeTimelineGapBackfillInteractionState(
                account: account,
                hasRelayRuntime: true,
                resolvedRelayCount: 2
            ),
            effects: probe.effects
        )
    }
}
