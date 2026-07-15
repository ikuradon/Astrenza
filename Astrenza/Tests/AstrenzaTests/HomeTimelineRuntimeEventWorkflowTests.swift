import AstrenzaCore
import Testing
@testable import Astrenza

@Suite("Home timeline runtime event workflow")
@MainActor
struct HomeTimelineRuntimeEventWorkflowTests {
    @Test("Event input and every emitted command route through stable effects")
    func routesEventAndApplicationCommands() async throws {
        let account = runtimeEventWorkflowAccount()
        let event = runtimeEventWorkflowEvent(kind: 1)
        let coordinator = RuntimeEventWorkflowCoordinatorSpy()
        coordinator.emitsHandleEffects = true
        let probe = RuntimeEventWorkflowEffectProbe(account: account)
        let workflow = HomeTimelineRuntimeEventWorkflow(coordinator: coordinator)
        let input = HomeTimelineRuntimeEventInput(
            relayURL: "wss://relay.example",
            subscriptionID: "astrenza-home-forward-workflow",
            event: event,
            account: account,
            hasRelayRuntime: true,
            receivedWhileRealtime: true
        )

        await workflow.handle(input, effects: probe.eventEffects)

        #expect(coordinator.requests == [HomeTimelineRuntimeEventRequest(
            relayURL: input.relayURL,
            subscriptionID: input.subscriptionID,
            event: input.event,
            account: input.account,
            hasRelayRuntime: input.hasRelayRuntime,
            receivedWhileRealtime: input.receivedWhileRealtime
        )])
        #expect(coordinator.presentationStates == [probe.presentationState])
        #expect(coordinator.accountValidityResults == [true])
        #expect(probe.effects == [
            .applyListProjectionInvalidation(7),
            .applyPendingEventCountPublication(3),
            .reloadProjection(
                anchorEventID: "anchor",
                materialization: .scheduled(allowsRealtimeFollow: true)
            ),
            .reloadNewestProjection(allowsRealtimeFollow: false),
            .scheduleMaterialization(.deferredDependencies),
            .persistTimelineMetadata(account),
            .sourceInstallFailed("install failed"),
            .recordDiagnostic(HomeTimelineRuntimeEventDiagnostic(
                relayURL: input.relayURL,
                subscriptionID: input.subscriptionID,
                message: "save failed"
            )),
            .scheduleLinkPreviewResolution
        ])
    }

    @Test("Metadata and dependency helpers preserve context, results, and effects")
    func delegatesApplicationHelpers() async throws {
        let account = runtimeEventWorkflowAccount()
        let lifecycle = HomeTimelineLifecycleCoordinator()
        let token = lifecycle.begin(accountID: account.pubkey)
        let context = HomeTimelineRuntimeEventApplicationContext(
            account: account,
            lifecycle: token,
            hasRelayRuntime: true
        )
        let metadata = runtimeEventWorkflowEvent(kind: 0)
        let dependency = runtimeEventWorkflowEvent(idCharacter: "2", kind: 1)
        let replacement = runtimeEventWorkflowEvent(idCharacter: "3", kind: 0)
        let coordinator = RuntimeEventWorkflowCoordinatorSpy()
        coordinator.replacementMetadataEvent = replacement
        coordinator.enqueueResult = false
        let probe = RuntimeEventWorkflowEffectProbe(account: account)
        let workflow = HomeTimelineRuntimeEventWorkflow(coordinator: coordinator)

        let remembered = workflow.rememberLatestMetadataEvent(
            metadata,
            consultEventStore: false,
            effects: probe.applicationEffects
        )
        workflow.resolveNIP05IfNeeded(
            for: remembered,
            context: context,
            effects: probe.applicationEffects
        )
        let enqueued = await workflow.enqueueDependencies(
            for: dependency,
            context: context,
            effects: probe.applicationEffects
        )

        #expect(remembered == replacement)
        #expect(coordinator.rememberedEvents == [metadata])
        #expect(coordinator.consultEventStoreValues == [false])
        #expect(coordinator.resolvedEvents == [replacement])
        #expect(coordinator.enqueuedEvents == [dependency])
        let resolvedContext = try #require(coordinator.resolvedContexts.first)
        #expect(resolvedContext.account == account)
        #expect(resolvedContext.lifecycle == token)
        #expect(resolvedContext.hasRelayRuntime)
        let enqueuedContext = try #require(coordinator.enqueuedContexts.first)
        #expect(enqueuedContext.account == account)
        #expect(enqueuedContext.lifecycle == token)
        #expect(enqueuedContext.hasRelayRuntime)
        #expect(!enqueued)
        #expect(probe.effects == [
            .applyListProjectionInvalidation(11),
            .scheduleMaterialization(.standard),
            .sourceInstallFailed("dependency install failed")
        ])
    }
}

@MainActor
private final class RuntimeEventWorkflowCoordinatorSpy: HomeTimelineRuntimeEventCoordinating {
    var emitsHandleEffects = false
    var replacementMetadataEvent: NostrEvent?
    var enqueueResult = true
    private(set) var requests: [HomeTimelineRuntimeEventRequest] = []
    private(set) var presentationStates: [HomeTimelineRuntimeEventPresentationState] = []
    private(set) var accountValidityResults: [Bool] = []
    private(set) var rememberedEvents: [NostrEvent] = []
    private(set) var consultEventStoreValues: [Bool] = []
    private(set) var resolvedEvents: [NostrEvent] = []
    private(set) var resolvedContexts: [HomeTimelineRuntimeEventApplicationContext] = []
    private(set) var enqueuedEvents: [NostrEvent] = []
    private(set) var enqueuedContexts: [HomeTimelineRuntimeEventApplicationContext] = []

    func handle(
        _ request: HomeTimelineRuntimeEventRequest,
        handlers: HomeTimelineRuntimeEventHandlers
    ) async {
        requests.append(request)
        presentationStates.append(
            handlers.presentationState(request.receivedWhileRealtime)
        )
        accountValidityResults.append(
            handlers.isAccountCurrent(request.account?.pubkey ?? "missing")
        )
        guard emitsHandleEffects else { return }

        handlers.application.applyListProjectionInvalidation(
            HomeTimelineListProjectionInvalidation(revision: 7)
        )
        handlers.application.applyPendingEventCountPublication(
            HomeTimelinePendingEventCountPublication(count: 3)
        )
        handlers.application.perform(.reloadProjection(
            anchorEventID: "anchor",
            materialization: .scheduled(allowsRealtimeFollow: true)
        ))
        handlers.application.perform(.requestNewestProjectionReloadAndSchedule(
            allowsRealtimeFollow: false
        ))
        handlers.application.perform(.scheduleMaterialization(
            .deferredDependencies
        ))
        if let account = request.account {
            await handlers.application.persistTimelineMetadata(account)
        }
        handlers.application.sourceInstallFailed("install failed")
        handlers.perform(.recordDiagnostic(HomeTimelineRuntimeEventDiagnostic(
            relayURL: request.relayURL,
            subscriptionID: request.subscriptionID,
            message: "save failed"
        )))
        handlers.perform(.scheduleLinkPreviewResolution)
    }

    func rememberLatestMetadataEvent(
        _ event: NostrEvent,
        consultEventStore: Bool,
        handlers: HomeTimelineRuntimeEventApplicationHandlers
    ) -> NostrEvent {
        rememberedEvents.append(event)
        consultEventStoreValues.append(consultEventStore)
        handlers.applyListProjectionInvalidation(
            HomeTimelineListProjectionInvalidation(revision: 11)
        )
        return replacementMetadataEvent ?? event
    }

    func resolveNIP05IfNeeded(
        for metadataEvent: NostrEvent,
        context: HomeTimelineRuntimeEventApplicationContext,
        handlers: HomeTimelineRuntimeEventApplicationHandlers
    ) {
        resolvedEvents.append(metadataEvent)
        resolvedContexts.append(context)
        handlers.perform(.scheduleMaterialization(.standard))
    }

    func enqueueDependencies(
        for event: NostrEvent,
        context: HomeTimelineRuntimeEventApplicationContext,
        handlers: HomeTimelineRuntimeEventApplicationHandlers
    ) async -> Bool {
        enqueuedEvents.append(event)
        enqueuedContexts.append(context)
        handlers.sourceInstallFailed("dependency install failed")
        return enqueueResult
    }
}

@MainActor
private final class RuntimeEventWorkflowEffectProbe {
    let presentationState = HomeTimelineRuntimeEventPresentationState(
        receivedWhileRealtime: true,
        hasRestoreProjectionAnchor: true,
        isTimelineAtNewestWindow: false,
        hasPendingEvents: true
    )
    private let account: NostrAccount
    private(set) var effects: [RuntimeEventWorkflowEffect] = []

    init(account: NostrAccount) {
        self.account = account
    }

    var eventEffects: HomeTimelineRuntimeEventEffects {
        HomeTimelineRuntimeEventEffects(
            presentationState: { [self] _ in presentationState },
            isAccountCurrent: { [self] accountID in accountID == account.pubkey },
            application: applicationEffects,
            recordDiagnostic: { [self] diagnostic in
                effects.append(.recordDiagnostic(diagnostic))
            },
            scheduleLinkPreviewResolution: { [self] in
                effects.append(.scheduleLinkPreviewResolution)
            }
        )
    }

    var applicationEffects: HomeTimelineRuntimeApplicationEffects {
        HomeTimelineRuntimeApplicationEffects(
            applyListProjectionInvalidation: { [self] invalidation in
                effects.append(.applyListProjectionInvalidation(
                    invalidation.revision
                ))
            },
            applyPendingEventCountPublication: { [self] publication in
                effects.append(.applyPendingEventCountPublication(
                    publication.count
                ))
            },
            reloadProjection: { [self] anchorEventID, materialization in
                effects.append(.reloadProjection(
                    anchorEventID: anchorEventID,
                    materialization: materialization
                ))
            },
            reloadNewestProjection: { [self] allowsRealtimeFollow in
                effects.append(.reloadNewestProjection(
                    allowsRealtimeFollow: allowsRealtimeFollow
                ))
            },
            scheduleMaterialization: { [self] schedule in
                effects.append(.scheduleMaterialization(schedule))
            },
            persistTimelineMetadata: { [self] account in
                effects.append(.persistTimelineMetadata(account))
            },
            sourceInstallFailed: { [self] message in
                effects.append(.sourceInstallFailed(message))
            }
        )
    }
}

private enum RuntimeEventWorkflowEffect: Equatable, Sendable {
    case applyListProjectionInvalidation(Int)
    case applyPendingEventCountPublication(Int)
    case reloadProjection(
        anchorEventID: String?,
        materialization: HomeTimelineRuntimeEventApplicationPlan.DeletionMaterialization
    )
    case reloadNewestProjection(allowsRealtimeFollow: Bool)
    case scheduleMaterialization(HomeTimelineRuntimeEventApplicationPlan.MaterializationSchedule)
    case persistTimelineMetadata(NostrAccount)
    case sourceInstallFailed(String)
    case recordDiagnostic(HomeTimelineRuntimeEventDiagnostic)
    case scheduleLinkPreviewResolution
}

private func runtimeEventWorkflowAccount() -> NostrAccount {
    NostrAccount(
        pubkey: String(repeating: "a", count: 64),
        displayIdentifier: "workflow",
        readOnly: true
    )
}

private func runtimeEventWorkflowEvent(
    idCharacter: Character = "1",
    kind: Int
) -> NostrEvent {
    NostrEvent(
        id: String(repeating: String(idCharacter), count: 64),
        pubkey: String(repeating: "a", count: 64),
        createdAt: kind == 0 ? 100 : 200,
        kind: kind,
        tags: [],
        content: kind == 0 ? #"{"name":"Alice"}"# : "event",
        sig: String(repeating: "b", count: 128)
    )
}
