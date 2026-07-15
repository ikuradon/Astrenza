import AstrenzaCore
import Testing
@testable import Astrenza

@Suite("Home timeline link preview interaction workflow")
@MainActor
struct HomeTimelineLinkPreviewInteractionTests {
    @Test("Scheduling preserves scope and records persistence failures")
    func routesSchedulingAndFailure() {
        let fixture = LinkPreviewInteractionFixture()

        let scheduled = fixture.workflow.schedule(
            state: fixture.state,
            effects: fixture.effects
        )
        fixture.scheduler.completeUpdate()
        fixture.scheduler.fail("persistence failed")

        #expect(scheduled)
        #expect(fixture.scheduler.schedules == [
            LinkPreviewSchedule(
                scopeID: fixture.account.pubkey,
                policy: .default()
            )
        ])
        #expect(fixture.probe.events == [
            .updated,
            .application(.applyRelayStatusTransition(
                fixture.relayStatus.transition
            ))
        ])
        #expect(fixture.relayStatus.records == [fixture.failureRecord])
    }

    @Test("Scheduling rejects a missing account without side effects")
    func requiresAccount() {
        let fixture = LinkPreviewInteractionFixture()

        let scheduled = fixture.workflow.schedule(
            state: HomeTimelineLinkPreviewInteractionState(
                accountID: nil,
                resolvedRelays: fixture.resolvedRelays,
                policy: .default()
            ),
            effects: fixture.effects
        )

        #expect(!scheduled)
        #expect(fixture.scheduler.schedules.isEmpty)
        #expect(fixture.probe.events.isEmpty)
        #expect(fixture.relayStatus.records.isEmpty)
    }
}

private struct LinkPreviewSchedule: Equatable {
    let scopeID: String
    let policy: NostrSyncPolicy
}

@MainActor
private final class LinkPreviewSchedulingSpy: HomeTimelineLinkPreviewScheduling {
    private var didUpdate: (@MainActor () -> Void)?
    private var didFail: (@MainActor (String) -> Void)?
    private(set) var schedules: [LinkPreviewSchedule] = []

    func schedule(
        scopeID: String,
        policy: NostrSyncPolicy,
        didUpdate: @escaping @MainActor () -> Void,
        didFail: @escaping @MainActor (String) -> Void
    ) -> Bool {
        schedules.append(LinkPreviewSchedule(
            scopeID: scopeID,
            policy: policy
        ))
        self.didUpdate = didUpdate
        self.didFail = didFail
        return true
    }

    func completeUpdate() {
        didUpdate?()
    }

    func fail(_ message: String) {
        didFail?(message)
    }
}

@MainActor
private final class LinkPreviewInteractionProbe {
    enum Event: Equatable {
        case updated
        case application(HomeTimelineLinkPreviewStoreAction)
    }

    private(set) var events: [Event] = []

    var effects: HomeLinkPreviewInteractionEffects {
        HomeLinkPreviewInteractionEffects(
            didUpdate: { [self] in events.append(.updated) },
            apply: { [self] action in events.append(.application(action)) }
        )
    }
}

@MainActor
private struct LinkPreviewInteractionFixture {
    let account = NostrAccount(
        pubkey: String(repeating: "a", count: 64),
        displayIdentifier: "link-preview",
        readOnly: true
    )
    let resolvedRelays = ["wss://relay.example"]
    let scheduler = LinkPreviewSchedulingSpy()
    let relayStatus = RelayStatusRecordingSpy()
    let probe = LinkPreviewInteractionProbe()
    let workflow: HomeLinkPreviewInteractionWorkflow

    init() {
        workflow = HomeLinkPreviewInteractionWorkflow(
            linkPreviews: scheduler,
            relayStatus: relayStatus
        )
    }

    var state: HomeTimelineLinkPreviewInteractionState {
        HomeTimelineLinkPreviewInteractionState(
            accountID: account.pubkey,
            resolvedRelays: resolvedRelays,
            policy: .default()
        )
    }

    var effects: HomeLinkPreviewInteractionEffects {
        probe.effects
    }

    var failureRecord: HomeTimelineRelayStatusRecord {
        HomeTimelineRelayStatusRecord(
            accountID: account.pubkey,
            resolvedRelays: resolvedRelays,
            relayURL: "link-preview",
            kind: .partialFailure,
            subscriptionID: nil,
            eventCount: 0,
            newestCreatedAt: nil,
            oldestCreatedAt: nil,
            message: "link preview save failed: persistence failed"
        )
    }
}
