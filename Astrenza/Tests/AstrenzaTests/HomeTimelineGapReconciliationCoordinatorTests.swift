import AstrenzaCore
import Foundation
import Testing
@testable import Astrenza

@Suite("Home timeline gap reconciliation coordinator")
struct HomeTimelineGapReconciliationCoordinatorTests {
    @Test("Reconciliation limits relay fan-out and preserves verification diagnostics")
    func limitsRelaysAndPreservesDiagnostics() async throws {
        let reconciler = GapReconcilerStub(output: HomeTimelineGapReconciliationOutput(
            result: .verifiedComplete,
            diagnostics: [HomeTimelineGapDiagnostic(
                relayURL: "wss://failed.example",
                message: "verification request was not persisted"
            )]
        ))
        let coordinator = HomeTimelineGapReconciliationCoordinator(
            reconciler: reconciler,
            persistence: GapPersistenceStub(
                outcome: .verifiedComplete(resolveFailure: "database locked")
            )
        )
        let fixture = try fixture()
        let relays = (1...5).map { "wss://relay\($0).example" }

        let execution = await coordinator.reconcile(
            newerEvent: fixture.newerEvent,
            olderEvent: fixture.olderEvent,
            gap: fixture.gap,
            context: fixture.context,
            relays: relays,
            inMemoryEvents: []
        )

        #expect(await reconciler.receivedRelays() == Array(relays.prefix(4)))
        #expect(execution == HomeTimelineGapReconciliationExecution(
            recoveredEvents: [],
            diagnostics: [
                HomeTimelineGapReconciliationDiagnostic(
                    relayURL: "wss://failed.example",
                    subscriptionID: "astrenza-neg-gap",
                    message: "verification request was not persisted"
                ),
                HomeTimelineGapReconciliationDiagnostic(
                    relayURL: relays[0],
                    subscriptionID: nil,
                    message: "gap resolve failed: database locked"
                )
            ],
            reloadsProjection: true
        ))
    }

    @Test("Indeterminate reconciliation remains reloadable and reports its status")
    func mapsIndeterminateOutcome() async throws {
        let coordinator = HomeTimelineGapReconciliationCoordinator(
            reconciler: GapReconcilerStub(output: HomeTimelineGapReconciliationOutput(
                result: .indeterminate,
                diagnostics: []
            )),
            persistence: GapPersistenceStub(outcome: .indeterminate)
        )
        let fixture = try fixture()

        let execution = await coordinator.reconcile(
            newerEvent: fixture.newerEvent,
            olderEvent: fixture.olderEvent,
            gap: fixture.gap,
            context: fixture.context,
            relays: [],
            inMemoryEvents: []
        )

        #expect(execution == HomeTimelineGapReconciliationExecution(
            recoveredEvents: [],
            diagnostics: [HomeTimelineGapReconciliationDiagnostic(
                relayURL: "runtime",
                subscriptionID: "astrenza-neg-gap",
                message: "gap reconciliation was inconclusive"
            )],
            reloadsProjection: true
        ))
    }

    @Test("Recovered events are returned for dependency resolution before reload")
    func returnsRecoveredEvents() async throws {
        let fixture = try fixture()
        let recoveredEvent = event(idCharacter: "c", createdAt: 150)
        let coordinator = HomeTimelineGapReconciliationCoordinator(
            reconciler: GapReconcilerStub(output: HomeTimelineGapReconciliationOutput(
                result: .recovered([recoveredEvent]),
                diagnostics: []
            )),
            persistence: GapPersistenceStub(outcome: .recovered([recoveredEvent]))
        )

        let execution = await coordinator.reconcile(
            newerEvent: fixture.newerEvent,
            olderEvent: fixture.olderEvent,
            gap: fixture.gap,
            context: fixture.context,
            relays: ["wss://relay.example"],
            inMemoryEvents: []
        )

        #expect(execution.recoveredEvents == [recoveredEvent])
        #expect(execution.diagnostics.isEmpty)
        #expect(execution.reloadsProjection)
    }

    @Test("Recovery persistence failure prevents projection reload")
    func preventsReloadAfterRecoveryFailure() async throws {
        let fixture = try fixture()
        let coordinator = HomeTimelineGapReconciliationCoordinator(
            reconciler: GapReconcilerStub(output: HomeTimelineGapReconciliationOutput(
                result: .recovered([event(idCharacter: "d", createdAt: 150)]),
                diagnostics: []
            )),
            persistence: GapPersistenceStub(outcome: .recoveryFailed("disk full"))
        )

        let execution = await coordinator.reconcile(
            newerEvent: fixture.newerEvent,
            olderEvent: fixture.olderEvent,
            gap: fixture.gap,
            context: fixture.context,
            relays: ["wss://relay.example"],
            inMemoryEvents: []
        )

        #expect(execution == HomeTimelineGapReconciliationExecution(
            recoveredEvents: [],
            diagnostics: [HomeTimelineGapReconciliationDiagnostic(
                relayURL: "wss://relay.example",
                subscriptionID: "astrenza-gap-events",
                message: "gap negentropy save failed: disk full"
            )],
            reloadsProjection: false
        ))
    }

    private func fixture() throws -> Fixture {
        let accountID = String(repeating: "a", count: 64)
        let specification = try JSONEncoder().encode(
            HomeFeedSpecification(authors: [accountID], kinds: [1, 6])
        )
        let definition = NostrFeedDefinitionRecord(
            feedID: "feed:home:\(accountID)",
            accountID: accountID,
            kind: "home",
            specificationJSON: specification,
            specificationHash: "specification",
            revision: 1,
            createdAt: 1,
            updatedAt: 1
        )
        let newerEvent = event(idCharacter: "1", createdAt: 200)
        let olderEvent = event(idCharacter: "2", createdAt: 100)
        return Fixture(
            context: HomeFeedRuntimeContext(definition: definition),
            gap: PendingGapBackfill(
                newerPostID: newerEvent.id,
                olderPostID: olderEvent.id,
                direction: .older
            ),
            newerEvent: newerEvent,
            olderEvent: olderEvent
        )
    }

    private func event(idCharacter: Character, createdAt: Int) -> NostrEvent {
        NostrEvent(
            id: String(repeating: String(idCharacter), count: 64),
            pubkey: String(repeating: "a", count: 64),
            createdAt: createdAt,
            kind: 1,
            tags: [],
            content: String(idCharacter),
            sig: String(repeating: "0", count: 128)
        )
    }

    private struct Fixture {
        let context: HomeFeedRuntimeContext
        let gap: PendingGapBackfill
        let newerEvent: NostrEvent
        let olderEvent: NostrEvent
    }
}

private actor GapReconcilerStub: HomeTimelineGapReconciling {
    private let output: HomeTimelineGapReconciliationOutput
    private var relays: [String] = []

    init(output: HomeTimelineGapReconciliationOutput) {
        self.output = output
    }

    func reconcile(
        newerEvent: NostrEvent,
        olderEvent: NostrEvent,
        context: HomeFeedRuntimeContext,
        relays: [String],
        inMemoryEvents: [NostrEvent]
    ) async -> HomeTimelineGapReconciliationOutput {
        self.relays = relays
        return output
    }

    func receivedRelays() -> [String] {
        relays
    }
}

private struct GapPersistenceStub: HomeTimelineGapReconciliationPersisting {
    let outcome: HomeTimelineGapPersistenceOutcome

    func apply(
        _ result: HomeTimelineGapReconciliationResult,
        gap: PendingGapBackfill,
        context: HomeFeedRuntimeContext
    ) -> HomeTimelineGapPersistenceOutcome {
        outcome
    }
}
