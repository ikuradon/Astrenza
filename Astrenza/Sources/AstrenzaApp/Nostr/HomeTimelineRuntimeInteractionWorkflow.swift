import AstrenzaCore

@MainActor
protocol HomeTimelineRuntimeRouting: AnyObject {
    @discardableResult
    func startSession(
        _ request: HomeTimelineRuntimeSessionRequest,
        effects: HomeTimelineRuntimeSessionEffects
    ) -> HomeTimelineRuntimeSessionStart

    func configure(
        _ request: HomeTimelineRuntimeSetupRequest,
        effects: HomeTimelineRuntimeSetupEffects
    ) async

    func resetSetup()

    func handlePacket(
        _ packet: NostrRelayRuntimePacket,
        effects: HomeTimelineRuntimePacketEffects
    ) async

    func handlePackets(
        _ packets: [NostrRelayRuntimePacket],
        effects: HomeTimelineRuntimePacketEffects
    ) async
}

extension HomeTimelineRuntimeRouting {
    func handlePackets(
        _ packets: [NostrRelayRuntimePacket],
        effects: HomeTimelineRuntimePacketEffects
    ) async {
        for packet in packets {
            await handlePacket(packet, effects: effects)
        }
    }
}

extension HomeTimelineRuntimeWorkflow: HomeTimelineRuntimeRouting {}

@MainActor
protocol HomeTimelineRuntimeEventRouting: AnyObject {
    func handle(
        _ input: HomeTimelineRuntimeEventInput,
        effects: HomeTimelineRuntimeEventEffects
    ) async

    func handle(
        _ inputs: [HomeTimelineRuntimeEventInput],
        effects: HomeTimelineRuntimeEventEffects
    ) async

    func rememberLatestMetadataEvent(
        _ event: NostrEvent,
        consultEventStore: Bool,
        effects: HomeTimelineRuntimeApplicationEffects
    ) -> NostrEvent

    func resolveNIP05IfNeeded(
        for metadataEvent: NostrEvent,
        context: HomeTimelineRuntimeEventApplicationContext,
        effects: HomeTimelineRuntimeApplicationEffects
    )

    func enqueueDependencies(
        for event: NostrEvent,
        context: HomeTimelineRuntimeEventApplicationContext,
        effects: HomeTimelineRuntimeApplicationEffects
    ) async -> Bool
}

extension HomeTimelineRuntimeEventRouting {
    func handle(
        _ inputs: [HomeTimelineRuntimeEventInput],
        effects: HomeTimelineRuntimeEventEffects
    ) async {
        for input in inputs {
            await handle(input, effects: effects)
        }
    }
}

extension HomeTimelineRuntimeEventWorkflow: HomeTimelineRuntimeEventRouting {}

@MainActor
protocol HomeTimelineRuntimeLifecycleTracking: AnyObject {
    func token(for accountID: String) -> HomeTimelineLifecycleToken?

    #if DEBUG
    func begin(accountID: String) -> HomeTimelineLifecycleToken
    #endif
}

extension HomeTimelineLifecycleCoordinator:
    HomeTimelineRuntimeLifecycleTracking {}

@MainActor
final class HomeTimelineRuntimeInteractionWorkflow {
    private let runtime: any HomeTimelineRuntimeRouting
    private let events: any HomeTimelineRuntimeEventRouting
    private let lifecycle: any HomeTimelineRuntimeLifecycleTracking
    private let relayStatus: any HomeTimelineRelayStatusRecording
    private let relayPlanner: HomeTimelineRuntimeRelayPlanner

    init(
        runtime: any HomeTimelineRuntimeRouting,
        events: any HomeTimelineRuntimeEventRouting,
        lifecycle: any HomeTimelineRuntimeLifecycleTracking,
        relayStatus: any HomeTimelineRelayStatusRecording,
        relayPlanner: HomeTimelineRuntimeRelayPlanner = .init()
    ) {
        self.runtime = runtime
        self.events = events
        self.lifecycle = lifecycle
        self.relayStatus = relayStatus
        self.relayPlanner = relayPlanner
    }

    @discardableResult
    func startSession(
        context: HomeTimelineRuntimeInteractionContext
    ) -> HomeTimelineRuntimeSessionStart {
        runtime.startSession(
            relayPlanner.sessionRequest(state: context.state),
            effects: sessionEffects(for: context.effects)
        )
    }

    func configure(
        account: NostrAccount,
        forceInstall: Bool,
        context: HomeTimelineRuntimeInteractionContext
    ) async {
        await runtime.configure(
            relayPlanner.setupRequest(
                account: account,
                forceInstall: forceInstall,
                state: context.state
            ),
            effects: setupEffects(
                state: context.state,
                for: context.effects
            )
        )
    }

    func provisionalBootstrapRelayURLs(
        account: NostrAccount,
        state: HomeTimelineRuntimeInteractionState
    ) -> [String]? {
        relayPlanner.provisionalBootstrapRelayURLs(
            account: account,
            resolvedRelayURLs: state.resolvedRelays,
            bootstrapRelayURLs: state.bootstrapRelayURLs,
            hasRelayRuntime: state.hasRelayRuntime
        )
    }

    func resetSetup() {
        runtime.resetSetup()
    }

    func handlePacket(
        _ packet: NostrRelayRuntimePacket,
        isActive: Bool? = nil,
        context: HomeTimelineRuntimeInteractionContext
    ) async {
        await runtime.handlePackets(
            [packet],
            effects: packetEffects(
                isActive: isActive,
                effects: context.effects
            )
        )
    }

    func handleEvents(
        _ envelopes: [HomeTimelineRuntimeEventEnvelope],
        context: HomeTimelineRuntimeEventContext
    ) async {
        await events.handle(
            envelopes.map { envelope in
                HomeTimelineRuntimeEventInput(
                    relayURL: envelope.relayURL,
                    subscriptionID: envelope.subscriptionID,
                    event: envelope.event,
                    account: context.state.account,
                    hasRelayRuntime: context.state.hasRelayRuntime,
                    receivedWhileRealtime: context.state.receivedWhileRealtime
                )
            },
            effects: eventEffects(
                state: context.state,
                for: context.effects
            )
        )
    }

    func handleEvent(
        relayURL: String,
        subscriptionID: String,
        event: NostrEvent,
        context: HomeTimelineRuntimeEventContext
    ) async {
        await handleEvents(
            [HomeTimelineRuntimeEventEnvelope(
                relayURL: relayURL,
                subscriptionID: subscriptionID,
                event: event
            )],
            context: context
        )
    }

    @discardableResult
    func rememberLatestMetadataEvent(
        _ event: NostrEvent,
        consultEventStore: Bool,
        application: HomeTimelineRuntimeApplicationEffects
    ) -> NostrEvent {
        events.rememberLatestMetadataEvent(
            event,
            consultEventStore: consultEventStore,
            effects: application
        )
    }

    func resolveNIP05IfNeeded(
        for metadataEvent: NostrEvent,
        state: HomeTimelineRuntimeDependencyState,
        application: HomeTimelineRuntimeApplicationEffects
    ) {
        guard let context = dependencyContext(for: state) else { return }
        events.resolveNIP05IfNeeded(
            for: metadataEvent,
            context: context,
            effects: application
        )
    }

    func enqueueDependencies(
        for event: NostrEvent,
        state: HomeTimelineRuntimeDependencyState,
        application: HomeTimelineRuntimeApplicationEffects
    ) async -> Bool {
        guard let context = dependencyContext(for: state) else { return false }
        return await enqueueDependencies(
            for: event,
            context: context,
            application: application
        )
    }

    func enqueueDependencies(
        for event: NostrEvent,
        context: HomeTimelineRuntimeEventApplicationContext,
        application: HomeTimelineRuntimeApplicationEffects
    ) async -> Bool {
        await events.enqueueDependencies(
            for: event,
            context: context,
            effects: application
        )
    }

    private func dependencyContext(
        for state: HomeTimelineRuntimeDependencyState
    ) -> HomeTimelineRuntimeEventApplicationContext? {
        guard let account = state.account,
              let lifecycle = lifecycle.token(for: account.pubkey)
        else { return nil }
        return HomeTimelineRuntimeEventApplicationContext(
            account: account,
            lifecycle: lifecycle,
            hasRelayRuntime: state.hasRelayRuntime
        )
    }

    private func sessionEffects(
        for effects: HomeTimelineRuntimeInteractionEffects
    ) -> HomeTimelineRuntimeSessionEffects {
        HomeTimelineRuntimeSessionEffects(
            isAccountCurrent: effects.environment.isAccountCurrent,
            application: effects.runtimeApplication,
            packet: packetEffects(isActive: nil, effects: effects),
            publishProfileMetadataChange: {
                effects.apply(.publishProfileMetadataChange)
            },
            invalidateListEntries: {
                effects.apply(.invalidateListEntries)
            },
            scheduleMaterialization: {
                effects.apply(.scheduleMaterialization)
            }
        )
    }

    private func packetEffects(
        isActive: Bool?,
        effects: HomeTimelineRuntimeInteractionEffects
    ) -> HomeTimelineRuntimePacketEffects {
        HomeTimelineRuntimePacketEffects(
            context: {
                effects.environment.packetContext(isActive)
            },
            setRealtime: { isRealtime in
                effects.apply(.setRealtime(isRealtime))
            },
            applyRelayStatusTransition: { transition in
                effects.apply(.applyRelayStatusTransition(transition))
            },
            handleEvent: { events in
                await effects.perform(.handleEvents(events))
            },
            handleBackwardCompletion: { completion in
                effects.apply(.handleBackwardCompletion(completion))
            }
        )
    }

    private func setupEffects(
        state: HomeTimelineRuntimeInteractionState,
        for effects: HomeTimelineRuntimeInteractionEffects
    ) -> HomeTimelineRuntimeSetupEffects {
        HomeTimelineRuntimeSetupEffects(
            setRealtime: { isRealtime in
                effects.apply(.setRealtime(isRealtime))
            },
            recordDiagnostic: { diagnostic in
                effects.apply(.applyRelayStatusTransition(
                    self.relayStatus.recordDiagnostic(
                        diagnostic,
                        accountID: state.account?.pubkey,
                        resolvedRelays: state.resolvedRelays
                    )
                ))
            }
        )
    }

    private func eventEffects(
        state: HomeTimelineRuntimeEventInteractionState,
        for effects: HomeTimelineRuntimeEventStoreEffects
    ) -> HomeTimelineRuntimeEventEffects {
        HomeTimelineRuntimeEventEffects(
            presentationState: effects.environment.presentationState,
            isAccountCurrent: effects.environment.isAccountCurrent,
            application: effects.runtimeApplication,
            recordDiagnostic: { diagnostic in
                effects.apply(.applyRelayStatusTransition(
                    self.relayStatus.recordDiagnostic(
                        diagnostic,
                        accountID: state.account?.pubkey,
                        resolvedRelays: state.resolvedRelays
                    )
                ))
            },
            scheduleLinkPreviewResolution: {
                effects.apply(.scheduleLinkPreviewResolution)
            }
        )
    }
}

#if DEBUG
extension HomeTimelineRuntimeInteractionWorkflow {
    @discardableResult
    func ensureLifecycle(accountID: String) -> HomeTimelineLifecycleToken {
        if let token = lifecycle.token(for: accountID) {
            return token
        }
        return lifecycle.begin(accountID: accountID)
    }
}
#endif
