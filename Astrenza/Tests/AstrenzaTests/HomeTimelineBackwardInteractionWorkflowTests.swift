import AstrenzaCore
import Testing
@testable import Astrenza

@Suite("Home timeline backward interaction workflow")
@MainActor
struct HomeTimelineBackwardInteractionTests {
    @Test("Completion input and every effect cross one typed boundary")
    func routesInputAndEffects() async throws {
        let fixture = BackwardInteractionFixture()

        fixture.workflow.handle(
            fixture.completion,
            context: fixture.context
        )
        let effects = try #require(fixture.backward.effects)
        let resolved = await effects.resolveDependencies(
            fixture.event,
            fixture.account,
            fixture.lifecycle
        )

        #expect(fixture.backward.inputs == [
            HomeTimelineBackwardCompletionInput(
                completion: fixture.completion,
                account: fixture.account
            )
        ])
        #expect(fixture.probe.actions == [
            .applyContentSnapshot(.initial),
            .applyRelayStatusTransition(fixture.relayStatus.transition),
            .reloadProjection(
                account: fixture.account,
                anchorEventID: "anchor",
                mergingWithCurrentWindow: true
            ),
            .materializeEntries,
            .scheduleLinkPreviewResolution,
            .incrementRelayStatusRevision
        ])
        #expect(fixture.relayStatus.records == [fixture.diagnosticRecord])
        #expect(fixture.probe.dependencyRequests == [
            HomeTimelineBackwardDependencyRequest(
                event: fixture.event,
                account: fixture.account,
                lifecycle: fixture.lifecycle
            )
        ])
        #expect(!resolved)
    }

    @Test("Cancellation remains delegated to backward processing")
    func delegatesCancellation() {
        let fixture = BackwardInteractionFixture()

        fixture.workflow.cancel()

        #expect(fixture.backward.cancelCount == 1)
    }
}

@MainActor
private final class BackwardInteractionHandlerSpy:
    HomeTimelineBackwardCompletionHandling {
    let diagnostic: HomeTimelineBackwardAppDiagnostic
    private(set) var inputs: [HomeTimelineBackwardCompletionInput] = []
    private(set) var effects: HomeTimelineBackwardCompletionAppEffects?
    private(set) var cancelCount = 0

    init(diagnostic: HomeTimelineBackwardAppDiagnostic) {
        self.diagnostic = diagnostic
    }

    func handle(
        _ input: HomeTimelineBackwardCompletionInput,
        effects: HomeTimelineBackwardCompletionAppEffects
    ) {
        inputs.append(input)
        self.effects = effects
        effects.applyContentSnapshot(.initial)
        effects.recordDiagnostic(diagnostic)
        guard let account = input.account else { return }
        effects.reloadProjection(account, "anchor", true)
        effects.materializeEntries()
        effects.scheduleLinkPreviewResolution()
        effects.incrementRelayStatusRevision()
    }

    func cancel() {
        cancelCount += 1
    }
}

@MainActor
private final class BackwardInteractionProbe {
    var actions: [HomeTimelineBackwardStoreAction] = []
    var dependencyRequests: [HomeTimelineBackwardDependencyRequest] = []

    var effects: HomeTimelineBackwardInteractionEffects {
        HomeTimelineBackwardInteractionEffects(
            apply: { [self] action in
                actions.append(action)
            },
            resolveDependencies: { [self] request in
                dependencyRequests.append(request)
                return false
            }
        )
    }
}

@MainActor
private struct BackwardInteractionFixture {
    let account = backwardCompletionWorkflowAccount()
    let resolvedRelays = ["wss://backward.example"]
    let completion = backwardCompletionWorkflowCompletion()
    let event = backwardCompletionWorkflowEvent()
    let lifecycle: HomeTimelineLifecycleToken
    let diagnostic = HomeTimelineBackwardAppDiagnostic(
        relayURL: "wss://backward.example",
        subscriptionID: "astrenza-backward",
        message: "backward failed"
    )
    let backward: BackwardInteractionHandlerSpy
    let probe = BackwardInteractionProbe()
    let relayStatus = RelayStatusRecordingSpy()
    let workflow: HomeTimelineBackwardInteractionWorkflow

    init() {
        let coordinator = HomeTimelineLifecycleCoordinator()
        lifecycle = coordinator.begin(accountID: account.pubkey)
        let backward = BackwardInteractionHandlerSpy(diagnostic: diagnostic)
        self.backward = backward
        workflow = HomeTimelineBackwardInteractionWorkflow(
            backward: backward,
            relayStatus: relayStatus
        )
    }

    var diagnosticRecord: HomeTimelineRelayStatusRecord {
        HomeTimelineRelayStatusRecord(
            accountID: account.pubkey,
            resolvedRelays: resolvedRelays,
            relayURL: diagnostic.relayURL,
            kind: .partialFailure,
            subscriptionID: diagnostic.subscriptionID,
            eventCount: 0,
            newestCreatedAt: nil,
            oldestCreatedAt: nil,
            message: diagnostic.message
        )
    }

    var context: HomeTimelineBackwardInteractionContext {
        HomeTimelineBackwardInteractionContext(
            state: HomeTimelineBackwardInteractionState(
                account: account,
                resolvedRelays: resolvedRelays
            ),
            effects: probe.effects
        )
    }
}
