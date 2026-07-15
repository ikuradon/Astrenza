import AstrenzaCore
import Testing
@testable import Astrenza

@Suite("Home timeline filter interaction workflow")
@MainActor
struct HomeFilterInteractionTests {
    @Test("Effective rules and the injected timestamp cross the facade")
    func routesEffectiveRuleRead() {
        let fixture = FilterInteractionFixture()

        let ruleSet = fixture.workflow.effectiveRuleSet(
            accountID: fixture.accountID
        )

        #expect(ruleSet == fixture.ruleSet)
        #expect(fixture.manager.events == [
            .effectiveRuleSet(
                accountID: fixture.accountID,
                timestamp: fixture.timestamp
            )
        ])
        #expect(fixture.probe.actions.isEmpty)
    }

    @Test("Changed suspend and resume operations rematerialize in order")
    func changedOperationsApplyOrderedActions() {
        let fixture = FilterInteractionFixture(
            didSuspend: true,
            didResume: true
        )

        let didSuspend = fixture.workflow.perform(
            .suspend,
            context: fixture.context
        )
        let didResume = fixture.workflow.perform(
            .resume,
            context: fixture.context
        )

        #expect(didSuspend)
        #expect(didResume)
        #expect(fixture.manager.events == [.suspend, .resume])
        #expect(fixture.probe.actions == [
            .invalidateListEntries,
            .materializeEntries,
            .invalidateListEntries,
            .materializeEntries
        ])
    }

    @Test("Idempotent suspend and resume operations do not publish actions")
    func unchangedOperationsAreNoOp() {
        let fixture = FilterInteractionFixture(
            didSuspend: false,
            didResume: false
        )

        let didSuspend = fixture.workflow.perform(
            .suspend,
            context: fixture.context
        )
        let didResume = fixture.workflow.perform(
            .resume,
            context: fixture.context
        )

        #expect(!didSuspend)
        #expect(!didResume)
        #expect(fixture.manager.events == [.suspend, .resume])
        #expect(fixture.probe.actions.isEmpty)
    }
}

private enum FilterInteractionEvent: Equatable {
    case effectiveRuleSet(accountID: String?, timestamp: Int)
    case suspend
    case resume
}

@MainActor
private final class FilterInteractionManagerSpy:
    HomeTimelineFilterManaging {
    private let ruleSet: NostrFilterRuleSet?
    private let didSuspend: Bool
    private let didResume: Bool
    private(set) var events: [FilterInteractionEvent] = []

    init(
        ruleSet: NostrFilterRuleSet?,
        didSuspend: Bool,
        didResume: Bool
    ) {
        self.ruleSet = ruleSet
        self.didSuspend = didSuspend
        self.didResume = didResume
    }

    func effectiveRuleSet(
        accountID: String?,
        now: Int
    ) -> NostrFilterRuleSet? {
        events.append(.effectiveRuleSet(
            accountID: accountID,
            timestamp: now
        ))
        return ruleSet
    }

    func suspend() -> Bool {
        events.append(.suspend)
        return didSuspend
    }

    func resume() -> Bool {
        events.append(.resume)
        return didResume
    }
}

@MainActor
private final class FilterInteractionProbe {
    private(set) var actions: [HomeTimelineFilterStoreAction] = []

    var effects: HomeFilterInteractionEffects {
        HomeFilterInteractionEffects(
            apply: { [self] action in
                actions.append(action)
            }
        )
    }
}

@MainActor
private struct FilterInteractionFixture {
    let accountID = String(repeating: "a", count: 64)
    let timestamp = 123
    let ruleSet: NostrFilterRuleSet
    let manager: FilterInteractionManagerSpy
    let probe = FilterInteractionProbe()
    let workflow: HomeTimelineFilterInteractionWorkflow

    init(
        didSuspend: Bool = false,
        didResume: Bool = false
    ) {
        let accountID = String(repeating: "a", count: 64)
        let timestamp = 123
        let ruleSet = NostrFilterRuleSet(rules: [
            NostrFilterRuleRecord(
                ruleID: "rule",
                accountID: accountID,
                kind: .keyword,
                value: "muted",
                createdAt: timestamp,
                updatedAt: timestamp
            )
        ])
        let manager = FilterInteractionManagerSpy(
            ruleSet: ruleSet,
            didSuspend: didSuspend,
            didResume: didResume
        )
        self.ruleSet = ruleSet
        self.manager = manager
        workflow = HomeTimelineFilterInteractionWorkflow(
            filter: manager,
            currentTimestamp: { timestamp }
        )
    }

    var context: HomeFilterInteractionContext {
        HomeFilterInteractionContext(effects: probe.effects)
    }
}
