import AstrenzaCore
import Testing
@testable import Astrenza

@Suite("Home timeline runtime event coordinator")
@MainActor
struct HomeTimelineRuntimeEventCoordinatorTests {
    @Test("Processed events apply once and finish runtime bookkeeping")
    func processedEventApplication() async throws {
        var plan = HomeTimelineRuntimeEventApplicationPlan()
        plan.projectionUpdate = .reloadNewestAndSchedule(allowsRealtimeFollow: true)
        let result = HomeTimelineRuntimeEventProcessingResult(
            applicationPlan: plan,
            backwardRequestKey: "backward-key"
        )
        let system = try RuntimeEventCoordinatorTestSystem(
            outcome: .processed(result)
        )
        system.processor.beforePresentationSample = {
            system.probe.state = HomeTimelineRuntimeEventPresentationState(
                receivedWhileRealtime: false,
                hasRestoreProjectionAnchor: false,
                isTimelineAtNewestWindow: true,
                hasPendingEvents: false
            )
        }

        await system.coordinator.handle(
            system.request(receivedWhileRealtime: true),
            handlers: system.probe.handlers
        )

        #expect(system.processor.calls == [RuntimeEventProcessingCall(
            relayURL: "wss://relay.example",
            subscriptionID: "astrenza-home-forward-test",
            event: system.event
        )])
        #expect(system.processor.presentationStates == [
            HomeTimelineRuntimeEventPresentationState(
                receivedWhileRealtime: true,
                hasRestoreProjectionAnchor: false,
                isTimelineAtNewestWindow: true,
                hasPendingEvents: false
            )
        ])
        #expect(system.processor.activeFeedContexts[0]?.accountID == system.account.pubkey)
        #expect(system.application.appliedPlans == [plan])
        #expect(system.application.backwardRequestKeys == ["backward-key"])
        #expect(system.application.applicationContexts[0].account == system.account)
        #expect(system.application.applicationContexts[0].lifecycle == system.lifecycleToken)
        #expect(system.application.applicationContexts[0].hasRelayRuntime)
        #expect(system.probe.commands == [.scheduleLinkPreviewResolution])
        #expect(system.recorder.records == [RuntimeEventFeedRecord(
            event: system.event,
            relayURL: "wss://relay.example",
            subscriptionID: "astrenza-home-forward-test"
        )])
    }

    @Test("Persistence failures become diagnostics without applying the event")
    func persistenceFailureDiagnostic() async throws {
        let system = try RuntimeEventCoordinatorTestSystem(
            outcome: .persistenceFailed("event save failed")
        )

        await system.coordinator.handle(
            system.request(),
            handlers: system.probe.handlers
        )

        #expect(system.application.appliedPlans.isEmpty)
        #expect(system.recorder.records.isEmpty)
        #expect(system.probe.commands == [
            .recordDiagnostic(HomeTimelineRuntimeEventDiagnostic(
                relayURL: "wss://relay.example",
                subscriptionID: "astrenza-home-forward-test",
                message: "event save failed"
            ))
        ])
    }

    @Test("Ignored events do not produce application side effects")
    func ignoredEvent() async throws {
        let system = try RuntimeEventCoordinatorTestSystem(outcome: .ignored)

        await system.coordinator.handle(
            system.request(),
            handlers: system.probe.handlers
        )

        #expect(system.application.appliedPlans.isEmpty)
        #expect(system.recorder.records.isEmpty)
        #expect(system.probe.commands.isEmpty)
    }

    @Test("Superseded accounts cannot apply a persisted event")
    func supersededAccount() async throws {
        let system = try RuntimeEventCoordinatorTestSystem(
            outcome: .processed(HomeTimelineRuntimeEventProcessingResult(
                applicationPlan: HomeTimelineRuntimeEventApplicationPlan(),
                backwardRequestKey: nil
            ))
        )
        system.probe.isAccountCurrent = false

        await system.coordinator.handle(
            system.request(),
            handlers: system.probe.handlers
        )

        #expect(system.application.appliedPlans.isEmpty)
        #expect(system.recorder.records.isEmpty)
        #expect(system.probe.commands.isEmpty)
    }

    @Test("Superseded lifecycle cannot apply a persisted event")
    func supersededLifecycle() async throws {
        let system = try RuntimeEventCoordinatorTestSystem(
            outcome: .processed(HomeTimelineRuntimeEventProcessingResult(
                applicationPlan: HomeTimelineRuntimeEventApplicationPlan(),
                backwardRequestKey: nil
            ))
        )
        system.processor.beforePresentationSample = {
            _ = system.lifecycle.cancel()
        }

        await system.coordinator.handle(
            system.request(),
            handlers: system.probe.handlers
        )

        #expect(system.application.appliedPlans.isEmpty)
        #expect(system.recorder.records.isEmpty)
        #expect(system.probe.commands.isEmpty)
    }

    @Test("Rejected application does not complete presentation bookkeeping")
    func rejectedApplication() async throws {
        let system = try RuntimeEventCoordinatorTestSystem(
            outcome: .processed(HomeTimelineRuntimeEventProcessingResult(
                applicationPlan: HomeTimelineRuntimeEventApplicationPlan(),
                backwardRequestKey: nil
            )),
            applyResult: false
        )

        await system.coordinator.handle(
            system.request(),
            handlers: system.probe.handlers
        )

        #expect(system.application.appliedPlans.count == 1)
        #expect(system.recorder.records.isEmpty)
        #expect(system.probe.commands.isEmpty)
    }

    @Test("Missing lifecycle prevents persistence work from starting")
    func missingLifecycle() async throws {
        let system = try RuntimeEventCoordinatorTestSystem(outcome: .ignored)
        _ = system.lifecycle.cancel()

        await system.coordinator.handle(
            system.request(),
            handlers: system.probe.handlers
        )

        #expect(system.processor.calls.isEmpty)
    }
}
