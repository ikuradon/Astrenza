import AstrenzaCore
import Foundation
import Testing
@testable import Astrenza

@Suite("Home timeline gap backfill workflow")
@MainActor
struct HomeTimelineGapBackfillWorkflowTests {
    @Test(
        "Unavailable application context stops before requesting a gap",
        arguments: GapBackfillAvailabilityScenario.allCases
    )
    func rejectsUnavailableContext(
        scenario: GapBackfillAvailabilityScenario
    ) async {
        let fixture = GapBackfillFixture()

        let didStart = await fixture.workflow.backfill(
            scenario.request(from: fixture),
            effects: fixture.probe.effects()
        )

        #expect(!didStart)
        #expect(fixture.probe.events.isEmpty)
    }

    @Test("An unavailable request has no persistence or UI side effects")
    func unavailableRequestStopsWorkflow() async {
        let fixture = GapBackfillFixture(outcome: .unavailable)

        let didStart = await fixture.run()

        #expect(!didStart)
        #expect(fixture.probe.events == [fixture.requestEvent])
    }

    @Test("A request failure records its diagnostic and stops")
    func failedRequestRecordsDiagnostic() async {
        let diagnostic = HomeTimelineBackwardRequestDiagnostic(
            relayURL: "wss://failed.example",
            subscriptionID: "astrenza-gap-notes",
            message: "gap enqueue failed: disconnected"
        )
        let fixture = GapBackfillFixture(outcome: .failed(diagnostic))

        let didStart = await fixture.run()

        #expect(!didStart)
        #expect(fixture.probe.events == [
            fixture.requestEvent,
            .recordDiagnostic(diagnostic)
        ])
    }

    @Test("Success reloads and materializes in order")
    func successPreservesApplicationOrder() async {
        let fixture = GapBackfillFixture()

        let didStart = await fixture.run()

        #expect(didStart)
        #expect(fixture.probe.events == fixture.successEvents)
    }

}

enum GapBackfillAvailabilityScenario: CaseIterable, Sendable {
    case missingAccount
    case missingRuntime
    case missingRelays

    @MainActor
    fileprivate func request(
        from fixture: GapBackfillFixture
    ) -> HomeTimelineGapBackfillRequest {
        HomeTimelineGapBackfillRequest(
            account: self == .missingAccount ? nil : fixture.account,
            hasRelayRuntime: self != .missingRuntime,
            resolvedRelayCount: self == .missingRelays ? 0 : 1,
            gap: fixture.gap,
            direction: .older
        )
    }
}

extension GapBackfillAvailabilityScenario: CustomTestStringConvertible {
    var testDescription: String {
        switch self {
        case .missingAccount:
            "missing account"
        case .missingRuntime:
            "missing runtime"
        case .missingRelays:
            "missing relays"
        }
    }
}

@MainActor
private struct GapBackfillFixture {
    let account: NostrAccount
    let gap: TimelineGap
    let definition: NostrFeedDefinitionRecord
    let probe: GapBackfillProbe
    let workflow: HomeTimelineGapBackfillWorkflow

    var request: HomeTimelineGapBackfillRequest {
        HomeTimelineGapBackfillRequest(
            account: account,
            hasRelayRuntime: true,
            resolvedRelayCount: 1,
            gap: gap,
            direction: .older
        )
    }

    var requestEvent: GapBackfillProbe.Event {
        .requestGap(
            accountID: account.pubkey,
            gapID: gap.id,
            direction: .older
        )
    }

    var successEvents: [GapBackfillProbe.Event] {
        [
            requestEvent,
            .reloadProjection(
                accountID: account.pubkey,
                anchorEventID: gap.newerPostID
            ),
            .materializeEntries
        ]
    }

    init(
        outcome: HomeTimelineBackwardRequestOutcome? = nil
    ) {
        let accountID = String(repeating: "a", count: 64)
        account = NostrAccount(
            pubkey: accountID,
            displayIdentifier: "account",
            readOnly: true
        )
        gap = TimelineGap(
            id: "gap-newer-older",
            newerPostID: "newer",
            olderPostID: "older",
            missingEstimate: 8,
            relayCount: 1,
            state: .needsBackfill,
            backfilledPosts: []
        )
        definition = NostrFeedDefinitionRecord(
            feedID: "feed:home:\(accountID)",
            accountID: accountID,
            kind: "home",
            specificationJSON: Data(),
            specificationHash: "gap-backfill",
            revision: 1,
            createdAt: 100,
            updatedAt: 100
        )
        probe = GapBackfillProbe(
            outcome: outcome ?? .completed(definition)
        )
        workflow = HomeTimelineGapBackfillWorkflow(
            requester: probe
        )
    }

    func run() async -> Bool {
        await workflow.backfill(
            request,
            effects: probe.effects()
        )
    }
}

@MainActor
private final class GapBackfillProbe:
    HomeTimelineGapRequesting {
    enum Event: Equatable {
        case requestGap(
            accountID: String,
            gapID: String,
            direction: TimelineGapFillDirection
        )
        case recordDiagnostic(HomeTimelineBackwardRequestDiagnostic)
        case reloadProjection(accountID: String, anchorEventID: String)
        case materializeEntries
    }

    private let outcome: HomeTimelineBackwardRequestOutcome
    private(set) var events: [Event] = []

    init(
        outcome: HomeTimelineBackwardRequestOutcome
    ) {
        self.outcome = outcome
    }

    func effects() -> HomeTimelineGapBackfillEffects {
        HomeTimelineGapBackfillEffects(
            recordDiagnostic: { [weak self] diagnostic in
                self?.events.append(.recordDiagnostic(diagnostic))
            },
            reloadProjection: { [weak self] account, anchorEventID in
                self?.events.append(.reloadProjection(
                    accountID: account.pubkey,
                    anchorEventID: anchorEventID
                ))
            },
            materializeEntries: { [weak self] in
                self?.events.append(.materializeEntries)
            }
        )
    }

    func requestGap(
        account: NostrAccount,
        gap: TimelineGap,
        direction: TimelineGapFillDirection,
        policy: NostrSyncPolicy
    ) async -> HomeTimelineBackwardRequestOutcome {
        events.append(.requestGap(
            accountID: account.pubkey,
            gapID: gap.id,
            direction: direction
        ))
        return outcome
    }

}
