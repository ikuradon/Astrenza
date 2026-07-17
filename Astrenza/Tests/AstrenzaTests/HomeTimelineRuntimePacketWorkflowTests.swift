import AstrenzaCore
import Testing
@testable import Astrenza

@Suite("Home timeline runtime packet workflow")
@MainActor
struct HomeTimelineRuntimePacketWorkflowTests {
    @Test("An ignored packet produces no application side effects")
    func ignoredPacketStopsBeforeApplication() async {
        let fixture = RuntimePacketWorkflowFixture(application: .ignored)

        await fixture.run()

        #expect(fixture.packetHandler.handleCount == 1)
        #expect(fixture.packetHandler.lastContext?.isActive == true)
        #expect(fixture.packetHandler.lastContext?.accountID == fixture.accountID)
        #expect(fixture.probe.events.isEmpty)
    }

    @Test("A handled packet applies its state exactly once")
    func handledPacketAppliesState() async {
        let application = HomeTimelineRuntimePacketApplication.handled(
            realtimeState: true
        )
        let fixture = RuntimePacketWorkflowFixture(application: application)

        await fixture.run()

        #expect(fixture.probe.events == [.applyState(application)])
    }

    @Test("Initial terminal state waits for pending presentation before publication")
    func initialTerminalStateWaitsForPresentation() async {
        let application = HomeTimelineRuntimePacketApplication.handled(
            realtimeState: true,
            requiresPresentationSettlement: true
        )
        let fixture = RuntimePacketWorkflowFixture(application: application)

        await fixture.run()

        #expect(fixture.probe.events == [
            .waitForPendingPresentation,
            .applyState(application)
        ])
    }

    @Test("An event applies packet state before awaiting event delivery")
    func eventRoutesAfterStateApplication() async {
        let event = runtimePacketEvent(idSeed: "4", createdAt: 400)
        let action = HomeTimelineRuntimePacketAction.event(
            relayURL: runtimePacketTestRelayURL,
            subscriptionID: "astrenza-home-forward-workflow",
            event: event
        )
        let application = HomeTimelineRuntimePacketApplication.handled(
            realtimeState: false,
            action: action
        )
        let fixture = RuntimePacketWorkflowFixture(application: application)

        await fixture.run()

        #expect(fixture.probe.events == [
            .applyState(application),
            .handleEvent(
                relayURL: runtimePacketTestRelayURL,
                subscriptionID: "astrenza-home-forward-workflow",
                event: event
            )
        ])
    }

    @Test("A backward completion applies packet state before delivery")
    func backwardCompletionRoutesAfterStateApplication() async {
        let completion = NostrBackwardREQCompletion(
            groupID: "older-workflow",
            relayURLs: [runtimePacketTestRelayURL],
            subscriptionIDs: ["older-subscription"],
            eventCount: 2,
            eoseCount: 1,
            closedCount: 0,
            timeoutCount: 0
        )
        let application = HomeTimelineRuntimePacketApplication.handled(
            action: .backwardCompleted(completion)
        )
        let fixture = RuntimePacketWorkflowFixture(application: application)

        await fixture.run()

        #expect(fixture.probe.events == [
            .applyState(application),
            .handleBackwardCompletion(completion)
        ])
    }
}

@MainActor
private struct RuntimePacketWorkflowFixture {
    let accountID = String(repeating: "c", count: 64)
    let packetHandler: RuntimePacketWorkflowHandlerStub
    let probe = RuntimePacketWorkflowProbe()
    let workflow: HomeTimelineRuntimePacketWorkflow

    init(application: HomeTimelineRuntimePacketApplication) {
        let packetHandler = RuntimePacketWorkflowHandlerStub(
            application: application
        )
        self.packetHandler = packetHandler
        self.workflow = HomeTimelineRuntimePacketWorkflow(
            packetHandler: packetHandler
        )
    }

    func run() async {
        await workflow.handle(
            .notice(relayURL: runtimePacketTestRelayURL, message: "input"),
            context: HomeTimelineRuntimePacketContext(
                isActive: true,
                accountID: accountID,
                resolvedRelays: [runtimePacketTestRelayURL],
                isCurrentFeedContext: { _ in true }
            ),
            handlers: probe.handlers
        )
    }
}

@MainActor
private final class RuntimePacketWorkflowHandlerStub: HomeTimelineRuntimePacketHandling {
    private let application: HomeTimelineRuntimePacketApplication
    private(set) var handleCount = 0
    private(set) var lastContext: RuntimePacketWorkflowObservedContext?

    init(application: HomeTimelineRuntimePacketApplication) {
        self.application = application
    }

    func handle(
        _ packet: NostrRelayRuntimePacket,
        context: HomeTimelineRuntimePacketContext
    ) -> HomeTimelineRuntimePacketApplication {
        handleCount += 1
        lastContext = RuntimePacketWorkflowObservedContext(
            isActive: context.isActive,
            accountID: context.accountID,
            resolvedRelays: context.resolvedRelays
        )
        return application
    }
}

private struct RuntimePacketWorkflowObservedContext: Equatable, Sendable {
    let isActive: Bool
    let accountID: String?
    let resolvedRelays: [String]
}

@MainActor
private final class RuntimePacketWorkflowProbe {
    private(set) var events: [RuntimePacketWorkflowProbeEvent] = []

    var handlers: HomeTimelineRuntimePacketHandlers {
        HomeTimelineRuntimePacketHandlers(
            applyState: { [weak self] application in
                self?.events.append(.applyState(application))
            },
            handleEvent: { [weak self] events in
                for event in events {
                    self?.events.append(.handleEvent(
                        relayURL: event.relayURL,
                        subscriptionID: event.subscriptionID,
                        event: event.event
                    ))
                }
            },
            handleBackwardCompletion: { [weak self] completion in
                self?.events.append(.handleBackwardCompletion(completion))
            },
            waitForPendingPresentation: { [weak self] in
                self?.events.append(.waitForPendingPresentation)
            }
        )
    }
}

private enum RuntimePacketWorkflowProbeEvent: Equatable, Sendable {
    case applyState(HomeTimelineRuntimePacketApplication)
    case waitForPendingPresentation
    case handleEvent(
        relayURL: String,
        subscriptionID: String,
        event: NostrEvent
    )
    case handleBackwardCompletion(NostrBackwardREQCompletion)
}
