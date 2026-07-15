import AstrenzaCore
import Testing
@testable import Astrenza

@Suite("Home timeline runtime interaction workflow")
@MainActor
struct HomeTimelineRuntimeInteractionTests {
    @Test("Session and setup requests stay behind typed applications")
    func routesSessionAndSetup() async {
        let fixture = RuntimeInteractionFixture()
        fixture.runtime.emitsSessionEffects = true
        fixture.runtime.emitsSetupEffects = true

        let start = fixture.workflow.startSession(context: fixture.context)
        await fixture.workflow.configure(
            account: fixture.account,
            defaultRelayURLs: fixture.relayURLs,
            forceInstall: true,
            context: fixture.context
        )
        fixture.workflow.resetSetup()

        #expect(start == fixture.runtime.startResult)
        #expect(fixture.runtime.sessionRequests == [fixture.sessionRequest])
        #expect(fixture.runtime.setupRequests == [fixture.setupRequest])
        #expect(fixture.runtime.accountValidity == [true])
        #expect(fixture.runtime.resetCount == 1)
        #expect(fixture.probe.applications == [
            .invalidateListEntries,
            .scheduleMaterialization,
            .setRealtime(false),
            .recordSetupDiagnostic(fixture.setupDiagnostic)
        ])
        #expect(fixture.probe.runtimeApplications == [
            .listProjectionInvalidation(5)
        ])
    }

    @Test("Packet context stays dynamic and events cross an async boundary")
    func routesPackets() async {
        let fixture = RuntimeInteractionFixture()
        _ = fixture.workflow.startSession(context: fixture.context)

        await fixture.runtime.routeSessionPacket(fixture.packet)
        await fixture.workflow.handlePacket(
            fixture.packet,
            isActive: true,
            context: fixture.context
        )

        #expect(fixture.probe.requestedActivity == [nil, true])
        #expect(fixture.runtime.packetContexts == [
            RuntimeInteractionPacketObservation(isActive: false),
            RuntimeInteractionPacketObservation(isActive: true)
        ])
        #expect(fixture.probe.applications == [
            .setRealtime(true),
            .applyRelayStatusTransition(nil),
            .handleBackwardCompletion(fixture.completion),
            .setRealtime(true),
            .applyRelayStatusTransition(nil),
            .handleBackwardCompletion(fixture.completion)
        ])
        #expect(fixture.probe.asyncApplications == [
            .handleEvent(
                relayURL: fixture.relayURLs[0],
                subscriptionID: fixture.subscriptionID,
                event: fixture.event
            ),
            .handleEvent(
                relayURL: fixture.relayURLs[0],
                subscriptionID: fixture.subscriptionID,
                event: fixture.event
            )
        ])
    }

    @Test("Event request, presentation providers, and helpers remain delegated")
    func routesEventsAndHelpers() async throws {
        let fixture = RuntimeInteractionFixture()

        await fixture.workflow.handleEvent(
            relayURL: fixture.relayURLs[0],
            subscriptionID: fixture.subscriptionID,
            event: fixture.event,
            context: fixture.eventContext
        )
        let remembered = fixture.workflow.rememberLatestMetadataEvent(
            fixture.event,
            consultEventStore: false,
            application: fixture.probe.runtimeApplicationEffects
        )
        fixture.workflow.resolveNIP05IfNeeded(
            for: remembered,
            state: fixture.dependencyState,
            application: fixture.probe.runtimeApplicationEffects
        )
        let enqueued = await fixture.workflow.enqueueDependencies(
            for: fixture.event,
            state: fixture.dependencyState,
            application: fixture.probe.runtimeApplicationEffects
        )

        #expect(fixture.events.inputs == [fixture.eventInput])
        #expect(fixture.probe.presentationInputs == [true])
        #expect(fixture.events.presentationStates == [fixture.presentationState])
        #expect(fixture.events.accountValidity == [true])
        #expect(fixture.probe.applications == [
            .recordEventDiagnostic(fixture.eventDiagnostic),
            .scheduleLinkPreviewResolution
        ])
        #expect(remembered == fixture.events.replacementEvent)
        #expect(fixture.events.consultEventStoreValues == [false])
        try expectDependencyContexts(fixture)
        #expect(fixture.lifecycle.events == [
            .token(accountID: fixture.account.pubkey),
            .token(accountID: fixture.account.pubkey)
        ])
        #expect(!enqueued)
        #expect(fixture.probe.runtimeApplications == [
            .pendingEventCountPublication(3),
            .listProjectionInvalidation(11),
            .materializationScheduled,
            .sourceInstallFailed("dependency install failed")
        ])
    }

    @Test("Dependency helpers require an account with a current lifecycle")
    func dependencyHelpersRejectMissingLifecycle() async {
        let fixture = RuntimeInteractionFixture(hasActiveLifecycle: false)
        let missingAccount = HomeTimelineRuntimeDependencyState(
            account: nil,
            hasRelayRuntime: true
        )

        fixture.workflow.resolveNIP05IfNeeded(
            for: fixture.event,
            state: missingAccount,
            application: fixture.probe.runtimeApplicationEffects
        )
        let missingAccountResult = await fixture.workflow.enqueueDependencies(
            for: fixture.event,
            state: missingAccount,
            application: fixture.probe.runtimeApplicationEffects
        )
        fixture.workflow.resolveNIP05IfNeeded(
            for: fixture.event,
            state: fixture.dependencyState,
            application: fixture.probe.runtimeApplicationEffects
        )
        let missingLifecycleResult = await fixture.workflow.enqueueDependencies(
            for: fixture.event,
            state: fixture.dependencyState,
            application: fixture.probe.runtimeApplicationEffects
        )

        #expect(!missingAccountResult)
        #expect(!missingLifecycleResult)
        #expect(fixture.events.resolvedContexts.isEmpty)
        #expect(fixture.events.enqueuedContexts.isEmpty)
        #expect(fixture.lifecycle.events == [
            .token(accountID: fixture.account.pubkey),
            .token(accountID: fixture.account.pubkey)
        ])
    }

    @Test("Debug lifecycle preparation begins once and reuses the active token")
    func ensureLifecycleBeginsOnce() {
        let fixture = RuntimeInteractionFixture(hasActiveLifecycle: false)

        let first = fixture.workflow.ensureLifecycle(
            accountID: fixture.account.pubkey
        )
        let second = fixture.workflow.ensureLifecycle(
            accountID: fixture.account.pubkey
        )

        #expect(first == second)
        #expect(fixture.lifecycle.events == [
            .token(accountID: fixture.account.pubkey),
            .begin(accountID: fixture.account.pubkey),
            .token(accountID: fixture.account.pubkey)
        ])
    }
}

@MainActor
private func expectDependencyContexts(
    _ fixture: RuntimeInteractionFixture
) throws {
    let resolvedContext = try #require(
        fixture.events.resolvedContexts.first
    )
    let enqueuedContext = try #require(
        fixture.events.enqueuedContexts.first
    )
    #expect(fixture.events.resolvedContexts.count == 1)
    #expect(fixture.events.enqueuedContexts.count == 1)
    expectDependencyContext(resolvedContext, fixture: fixture)
    expectDependencyContext(enqueuedContext, fixture: fixture)
}

@MainActor
private func expectDependencyContext(
    _ context: HomeTimelineRuntimeEventApplicationContext,
    fixture: RuntimeInteractionFixture
) {
    #expect(context.account == fixture.dependencyContext.account)
    #expect(context.lifecycle == fixture.dependencyContext.lifecycle)
    #expect(
        context.hasRelayRuntime == fixture.dependencyContext.hasRelayRuntime
    )
}
