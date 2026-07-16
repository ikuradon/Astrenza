import AstrenzaCore
@testable import Astrenza

@MainActor
final class RuntimeInteractionRoutingSpy: HomeTimelineRuntimeRouting {
    let startResult = HomeTimelineRuntimeSessionStart(
        didStartProfileUpdates: true,
        didStartRuntimeEvents: true
    )
    var event: NostrEvent?
    var completion: NostrBackwardREQCompletion?
    var setupDiagnostic: HomeTimelineRuntimeSetupDiagnostic?
    var emitsSessionEffects = false
    var emitsSetupEffects = false
    private(set) var sessionRequests: [HomeTimelineRuntimeSessionRequest] = []
    private(set) var setupRequests: [HomeTimelineRuntimeSetupRequest] = []
    private(set) var accountValidity: [Bool] = []
    private(set) var packetContexts: [RuntimeInteractionPacketObservation] = []
    private(set) var resetCount = 0
    private var sessionPacketEffects: HomeTimelineRuntimePacketEffects?

    func startSession(
        _ request: HomeTimelineRuntimeSessionRequest,
        effects: HomeTimelineRuntimeSessionEffects
    ) -> HomeTimelineRuntimeSessionStart {
        sessionRequests.append(request)
        sessionPacketEffects = effects.packet
        accountValidity.append(
            effects.isAccountCurrent(request.account?.pubkey ?? "missing")
        )
        if emitsSessionEffects {
            effects.application.applyListProjectionInvalidation(
                HomeTimelineListProjectionInvalidation(revision: 5)
            )
            effects.publishProfileMetadataChange()
            effects.invalidateListEntries()
            effects.scheduleMaterialization()
        }
        return startResult
    }

    func configure(
        _ request: HomeTimelineRuntimeSetupRequest,
        effects: HomeTimelineRuntimeSetupEffects
    ) async {
        setupRequests.append(request)
        guard emitsSetupEffects, let setupDiagnostic else { return }
        effects.setRealtime(false)
        effects.recordDiagnostic(setupDiagnostic)
    }

    func resetSetup() {
        resetCount += 1
    }

    func handlePacket(
        _ packet: NostrRelayRuntimePacket,
        effects: HomeTimelineRuntimePacketEffects
    ) async {
        guard let context = effects.context() else { return }
        packetContexts.append(RuntimeInteractionPacketObservation(
            isActive: context.isActive
        ))
        effects.setRealtime(true)
        effects.applyRelayStatusTransition(nil)
        if let event {
            await effects.handleEvent(
                "wss://relay.example",
                "astrenza-home-forward-interaction",
                event
            )
        }
        if let completion {
            effects.handleBackwardCompletion(completion)
        }
    }

    func routeSessionPacket(_ packet: NostrRelayRuntimePacket) async {
        guard let sessionPacketEffects else { return }
        await handlePacket(packet, effects: sessionPacketEffects)
    }
}

struct RuntimeInteractionPacketObservation: Equatable {
    let isActive: Bool
}

@MainActor
final class RuntimeInteractionEventRoutingSpy:
    HomeTimelineRuntimeEventRouting {
    var replacementEvent: NostrEvent
    private(set) var inputs: [HomeTimelineRuntimeEventInput] = []
    private(set) var presentationStates:
        [HomeTimelineRuntimeEventPresentationState] = []
    private(set) var accountValidity: [Bool] = []
    private(set) var consultEventStoreValues: [Bool] = []
    private(set) var resolvedContexts:
        [HomeTimelineRuntimeEventApplicationContext] = []
    private(set) var enqueuedContexts:
        [HomeTimelineRuntimeEventApplicationContext] = []

    init(replacementEvent: NostrEvent) {
        self.replacementEvent = replacementEvent
    }

    func handle(
        _ input: HomeTimelineRuntimeEventInput,
        effects: HomeTimelineRuntimeEventEffects
    ) async {
        inputs.append(input)
        presentationStates.append(
            effects.presentationState(input.receivedWhileRealtime)
        )
        accountValidity.append(
            effects.isAccountCurrent(input.account?.pubkey ?? "missing")
        )
        effects.application.applyPendingEventCountPublication(
            HomeTimelinePendingEventCountPublication(count: 3)
        )
        effects.recordDiagnostic(HomeTimelineRuntimeEventDiagnostic(
            relayURL: input.relayURL,
            subscriptionID: input.subscriptionID,
            message: "save failed"
        ))
        effects.scheduleLinkPreviewResolution()
    }

    func rememberLatestMetadataEvent(
        _ event: NostrEvent,
        consultEventStore: Bool,
        effects: HomeTimelineRuntimeApplicationEffects
    ) -> NostrEvent {
        consultEventStoreValues.append(consultEventStore)
        effects.applyListProjectionInvalidation(
            HomeTimelineListProjectionInvalidation(revision: 11)
        )
        return replacementEvent
    }

    func resolveNIP05IfNeeded(
        for metadataEvent: NostrEvent,
        context: HomeTimelineRuntimeEventApplicationContext,
        effects: HomeTimelineRuntimeApplicationEffects
    ) {
        resolvedContexts.append(context)
        effects.scheduleMaterialization(.standard)
    }

    func enqueueDependencies(
        for event: NostrEvent,
        context: HomeTimelineRuntimeEventApplicationContext,
        effects: HomeTimelineRuntimeApplicationEffects
    ) async -> Bool {
        enqueuedContexts.append(context)
        effects.sourceInstallFailed("dependency install failed")
        return false
    }
}

@MainActor
final class RuntimeInteractionProbe {
    var applications: [HomeTimelineRuntimeStoreAction] = []
    var asyncApplications: [HomeTimelineRuntimeStoreAsyncAction] = []
    var runtimeApplications: [RuntimeInteractionRuntimeApplication] = []
    var requestedActivity: [Bool?] = []
    var presentationInputs: [Bool] = []

    var runtimeApplicationEffects: HomeTimelineRuntimeApplicationEffects {
        HomeTimelineRuntimeApplicationEffects(
            applyListProjectionInvalidation: { [self] invalidation in
                runtimeApplications.append(
                    .listProjectionInvalidation(invalidation.revision)
                )
            },
            applyPendingEventCountPublication: { [self] publication in
                runtimeApplications.append(
                    .pendingEventCountPublication(publication.count)
                )
            },
            reloadProjection: { _, _ in },
            reloadNewestProjection: { _ in },
            scheduleMaterialization: { [self] _ in
                runtimeApplications.append(.materializationScheduled)
            },
            persistTimelineMetadata: { _ in },
            sourceInstallFailed: { [self] message in
                runtimeApplications.append(.sourceInstallFailed(message))
            }
        )
    }
}

enum RuntimeInteractionRuntimeApplication: Equatable {
    case listProjectionInvalidation(Int)
    case pendingEventCountPublication(Int)
    case materializationScheduled
    case sourceInstallFailed(String)
}

@MainActor
struct RuntimeInteractionFixture {
    let account = NostrAccount(
        pubkey: String(repeating: "a", count: 64),
        displayIdentifier: "interaction",
        readOnly: true
    )
    let relayURLs = ["wss://relay.example"]
    let subscriptionID = "astrenza-home-forward-interaction"
    let policy = NostrSyncPolicy.default(
        networkType: .unknown,
        lowPowerMode: false
    )
    let event = runtimePacketEvent(idSeed: "8", createdAt: 800)
    let replacementEvent = runtimePacketEvent(idSeed: "9", createdAt: 900)
    let completion = NostrBackwardREQCompletion(
        groupID: "older-runtime-interaction",
        relayURLs: ["wss://relay.example"],
        subscriptionIDs: ["astrenza-home-older"],
        eventCount: 2,
        eoseCount: 1,
        closedCount: 0,
        timeoutCount: 0
    )
    let setupDiagnostic = HomeTimelineRuntimeSetupDiagnostic(
        relayURL: "wss://relay.example",
        subscriptionID: "astrenza-home-forward-interaction",
        message: "install failed"
    )
    let lifecycleToken = HomeTimelineLifecycleToken(
        accountID: String(repeating: "a", count: 64),
        generation: 7
    )
    let runtime: RuntimeInteractionRoutingSpy
    let events: RuntimeInteractionEventRoutingSpy
    let lifecycle: RuntimeInteractionLifecycleSpy
    let relayStatus: RelayStatusRecordingSpy
    let probe = RuntimeInteractionProbe()
    let workflow: HomeTimelineRuntimeInteractionWorkflow

    init(hasActiveLifecycle: Bool = true) {
        let runtime = RuntimeInteractionRoutingSpy()
        let events = RuntimeInteractionEventRoutingSpy(
            replacementEvent: replacementEvent
        )
        let lifecycle = RuntimeInteractionLifecycleSpy(
            currentToken: hasActiveLifecycle ? lifecycleToken : nil
        )
        let relayStatus = RelayStatusRecordingSpy()
        runtime.event = event
        runtime.completion = completion
        runtime.setupDiagnostic = setupDiagnostic
        self.runtime = runtime
        self.events = events
        self.lifecycle = lifecycle
        self.relayStatus = relayStatus
        self.workflow = HomeTimelineRuntimeInteractionWorkflow(
            runtime: runtime,
            events: events,
            lifecycle: lifecycle,
            relayStatus: relayStatus
        )
    }

    var dependencyState: HomeTimelineRuntimeDependencyState {
        HomeTimelineRuntimeDependencyState(
            account: account,
            hasRelayRuntime: true
        )
    }

    var dependencyContext: HomeTimelineRuntimeEventApplicationContext {
        HomeTimelineRuntimeEventApplicationContext(
            account: account,
            lifecycle: lifecycleToken,
            hasRelayRuntime: true
        )
    }

    var context: HomeTimelineRuntimeInteractionContext {
        HomeTimelineRuntimeInteractionContext(
            state: HomeTimelineRuntimeInteractionState(
                account: account,
                resolvedRelays: relayURLs,
                bootstrapRelayURLs: [],
                policy: policy,
                hasRelayRuntime: true,
                isTerminating: false
            ),
            effects: HomeTimelineRuntimeInteractionEffects(
                environment: HomeTimelineRuntimeStoreEnvironment(
                    packetContext: { [probe, account, relayURLs] isActive in
                        probe.requestedActivity.append(isActive)
                        return HomeTimelineRuntimePacketContext(
                            isActive: isActive ?? false,
                            accountID: account.pubkey,
                            resolvedRelays: relayURLs,
                            isCurrentFeedContext: { _ in true }
                        )
                    },
                    isAccountCurrent: { [account] in $0 == account.pubkey }
                ),
                runtimeApplication: probe.runtimeApplicationEffects,
                apply: { [probe] in probe.applications.append($0) },
                perform: { [probe] in probe.asyncApplications.append($0) }
            )
        )
    }

    let presentationState = HomeTimelineRuntimeEventPresentationState(
        receivedWhileRealtime: true,
        hasRestoreProjectionAnchor: true,
        isTimelineAtNewestWindow: false,
        hasPendingEvents: true
    )

    var eventContext: HomeTimelineRuntimeEventContext {
        HomeTimelineRuntimeEventContext(
            state: HomeTimelineRuntimeEventInteractionState(
                account: account,
                resolvedRelays: relayURLs,
                hasRelayRuntime: true,
                receivedWhileRealtime: true
            ),
            effects: HomeTimelineRuntimeEventStoreEffects(
                environment: HomeTimelineRuntimeEventEnvironment(
                    presentationState: { [probe, presentationState] value in
                        probe.presentationInputs.append(value)
                        return presentationState
                    },
                    isAccountCurrent: { [account] in $0 == account.pubkey }
                ),
                runtimeApplication: probe.runtimeApplicationEffects,
                apply: { [probe] in probe.applications.append($0) }
            )
        )
    }

    var sessionRequest: HomeTimelineRuntimeSessionRequest {
        HomeTimelineRuntimeSessionRequest(
            account: account,
            profileRelayURLs: relayURLs,
            hasRelayRuntime: true,
            isTerminating: false
        )
    }

    var setupRequest: HomeTimelineRuntimeSetupRequest {
        HomeTimelineRuntimeSetupRequest(
            account: account,
            defaultRelayURLs: relayURLs,
            policy: policy,
            hasRelayRuntime: true,
            isTerminating: false,
            forceInstall: true
        )
    }

    var eventInput: HomeTimelineRuntimeEventInput {
        HomeTimelineRuntimeEventInput(
            relayURL: relayURLs[0],
            subscriptionID: subscriptionID,
            event: event,
            account: account,
            hasRelayRuntime: true,
            receivedWhileRealtime: true
        )
    }

    var eventDiagnostic: HomeTimelineRuntimeEventDiagnostic {
        HomeTimelineRuntimeEventDiagnostic(
            relayURL: relayURLs[0],
            subscriptionID: subscriptionID,
            message: "save failed"
        )
    }

    var packet: NostrRelayRuntimePacket {
        .notice(relayURL: relayURLs[0], message: "ready")
    }
}
