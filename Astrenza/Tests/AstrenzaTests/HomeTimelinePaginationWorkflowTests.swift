import AstrenzaCore
import Testing
@testable import Astrenza

@Suite("Home timeline pagination workflow")
@MainActor
struct HomeTimelinePaginationWorkflowTests {
    @Test("Refresh resets projection restore state before scheduling its load")
    func refreshResetsStateBeforeScheduling() async {
        let fixture = PaginationFixture()

        fixture.workflow.refresh(fixture.state, effects: fixture.effects)

        #expect(fixture.probe.events == [
            .resetProjectionRestoreState,
            .startPagination(fixture.lifecycle)
        ])
        await fixture.probe.runScheduledOperation()
        #expect(fixture.probe.events == [
            .resetProjectionRestoreState,
            .startPagination(fixture.lifecycle),
            .refreshLatest(fixture.account, fixture.lifecycle)
        ])
    }

    @Test("Direct refresh uses the current lifecycle without scheduling another task")
    func directRefreshRunsImmediately() async {
        let fixture = PaginationFixture()

        await fixture.workflow.refreshLatest(
            fixture.state,
            effects: fixture.effects
        )

        #expect(fixture.probe.events == [
            .refreshLatest(fixture.account, fixture.lifecycle)
        ])
        #expect(!fixture.probe.hasScheduledOperation)
    }

    @Test("Older loading schedules its load without changing projection restore state")
    func olderLoadingSchedulesLoad() async {
        let fixture = PaginationFixture()

        fixture.workflow.loadOlder(fixture.state, effects: fixture.effects)

        #expect(fixture.probe.events == [
            .startPagination(fixture.lifecycle)
        ])
        await fixture.probe.runScheduledOperation()
        #expect(fixture.probe.events == [
            .startPagination(fixture.lifecycle),
            .loadOlder(fixture.account, fixture.lifecycle)
        ])
    }

    @Test("A missing account rejects every pagination entry point")
    func missingAccountRejectsEveryEntryPoint() async {
        let fixture = PaginationFixture()
        let state = fixture.state(account: nil)

        fixture.workflow.refresh(state, effects: fixture.effects)
        await fixture.workflow.refreshLatest(state, effects: fixture.effects)
        fixture.workflow.loadOlder(state, effects: fixture.effects)

        #expect(fixture.probe.events.isEmpty)
        #expect(!fixture.probe.hasScheduledOperation)
    }

    @Test("A missing current lifecycle rejects every pagination entry point")
    func missingLifecycleRejectsEveryEntryPoint() async {
        let fixture = PaginationFixture(hasLifecycle: false)

        fixture.workflow.refresh(fixture.state, effects: fixture.effects)
        await fixture.workflow.refreshLatest(
            fixture.state,
            effects: fixture.effects
        )
        fixture.workflow.loadOlder(fixture.state, effects: fixture.effects)

        #expect(fixture.probe.events.isEmpty)
        #expect(!fixture.probe.hasScheduledOperation)
    }

    @Test(
        "Every unavailable older-page condition rejects the load",
        arguments: OlderLoadBlocker.allCases
    )
    func unavailableOlderPageRejectsLoad(_ blocker: OlderLoadBlocker) {
        let fixture = PaginationFixture()

        fixture.workflow.loadOlder(
            blocker.state(account: fixture.account),
            effects: fixture.effects
        )

        #expect(fixture.probe.events.isEmpty)
        #expect(!fixture.probe.hasScheduledOperation)
    }
}

enum OlderLoadBlocker: CaseIterable, Sendable {
    case activeLoad
    case exhausted
    case emptyTimeline
    case noRelays
    case noFollows

    func state(account: NostrAccount) -> HomeTimelinePaginationState {
        HomeTimelinePaginationState(
            account: account,
            canBeginLoadingOlder: self != .activeLoad,
            hasMoreOlder: self != .exhausted,
            hasTimelineEvents: self != .emptyTimeline,
            hasResolvedRelays: self != .noRelays,
            hasFollowedPubkeys: self != .noFollows
        )
    }
}

extension OlderLoadBlocker: CustomTestStringConvertible {
    var testDescription: String {
        switch self {
        case .activeLoad:
            "active older load"
        case .exhausted:
            "older history exhausted"
        case .emptyTimeline:
            "empty timeline"
        case .noRelays:
            "no resolved relays"
        case .noFollows:
            "no followed pubkeys"
        }
    }
}

@MainActor
private struct PaginationFixture {
    let account = NostrAccount(
        pubkey: String(repeating: "a", count: 64),
        displayIdentifier: "pagination",
        readOnly: true
    )
    let lifecycle = HomeTimelineLifecycleToken(
        accountID: String(repeating: "a", count: 64),
        generation: 1
    )
    let probe: PaginationProbe
    let workflow: HomeTimelinePaginationWorkflow

    init(hasLifecycle: Bool = true) {
        let activeLifecycle = hasLifecycle
            ? HomeTimelineLifecycleToken(
                accountID: String(repeating: "a", count: 64),
                generation: 1
            )
            : nil
        let probe = PaginationProbe(lifecycle: activeLifecycle)
        self.probe = probe
        workflow = HomeTimelinePaginationWorkflow(
            lifecycleCoordinator: probe
        )
    }

    var state: HomeTimelinePaginationState {
        state(account: account)
    }

    var effects: HomeTimelinePaginationEffects {
        probe.effects
    }

    func state(account: NostrAccount?) -> HomeTimelinePaginationState {
        HomeTimelinePaginationState(
            account: account,
            canBeginLoadingOlder: true,
            hasMoreOlder: true,
            hasTimelineEvents: true,
            hasResolvedRelays: true,
            hasFollowedPubkeys: true
        )
    }
}

@MainActor
private final class PaginationProbe: HomeTimelinePaginationScheduling {
    enum Event: Equatable {
        case resetProjectionRestoreState
        case startPagination(HomeTimelineLifecycleToken)
        case refreshLatest(NostrAccount, HomeTimelineLifecycleToken)
        case loadOlder(NostrAccount, HomeTimelineLifecycleToken)
    }

    private let lifecycle: HomeTimelineLifecycleToken?
    private var scheduledOperation: Operation?
    private(set) var events: [Event] = []

    init(lifecycle: HomeTimelineLifecycleToken?) {
        self.lifecycle = lifecycle
    }

    var hasScheduledOperation: Bool {
        scheduledOperation != nil
    }

    var effects: HomeTimelinePaginationEffects {
        HomeTimelinePaginationEffects(
            resetProjectionRestoreState: { [self] in
                events.append(.resetProjectionRestoreState)
            },
            refreshLatest: { [self] account, lifecycle in
                events.append(.refreshLatest(account, lifecycle))
            },
            loadOlder: { [self] account, lifecycle in
                events.append(.loadOlder(account, lifecycle))
            }
        )
    }

    func token(for accountID: String) -> HomeTimelineLifecycleToken? {
        guard lifecycle?.accountID == accountID else { return nil }
        return lifecycle
    }

    func startPagination(
        for token: HomeTimelineLifecycleToken,
        operation: @escaping Operation
    ) {
        events.append(.startPagination(token))
        scheduledOperation = operation
    }

    func runScheduledOperation() async {
        let operation = scheduledOperation
        scheduledOperation = nil
        await operation?()
    }
}
