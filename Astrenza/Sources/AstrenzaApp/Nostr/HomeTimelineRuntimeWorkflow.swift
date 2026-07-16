import AstrenzaCore

@MainActor
protocol HomeTimelineRuntimeSessionStarting: AnyObject {
    @discardableResult
    func start(
        _ request: HomeTimelineRuntimeSessionRequest,
        handlers: HomeTimelineRuntimeSessionHandlers
    ) -> HomeTimelineRuntimeSessionStart
}

extension HomeTimelineRuntimeSessionCoordinator: HomeTimelineRuntimeSessionStarting {}

@MainActor
protocol HomeTimelineRuntimeSetupManaging: AnyObject {
    func reset()

    func configure(
        _ request: HomeTimelineRuntimeSetupRequest,
        handlers: HomeTimelineRuntimeSetupHandlers
    ) async
}

extension HomeTimelineRuntimeSetupCoordinator: HomeTimelineRuntimeSetupManaging {}

@MainActor
protocol HomeTimelineRuntimePacketRouting: AnyObject {
    func handle(
        _ packet: NostrRelayRuntimePacket,
        context: HomeTimelineRuntimePacketContext,
        handlers: HomeTimelineRuntimePacketHandlers
    ) async

    func handle(
        _ packets: [NostrRelayRuntimePacket],
        context: HomeTimelineRuntimePacketContext,
        handlers: HomeTimelineRuntimePacketHandlers
    ) async
}

extension HomeTimelineRuntimePacketRouting {
    func handle(
        _ packets: [NostrRelayRuntimePacket],
        context: HomeTimelineRuntimePacketContext,
        handlers: HomeTimelineRuntimePacketHandlers
    ) async {
        for packet in packets {
            await handle(packet, context: context, handlers: handlers)
        }
    }
}

extension HomeTimelineRuntimePacketWorkflow: HomeTimelineRuntimePacketRouting {}

struct HomeTimelineRuntimePacketEffects: Sendable {
    typealias ContextProvider = @MainActor @Sendable () -> HomeTimelineRuntimePacketContext?
    typealias RealtimeEffect = @MainActor @Sendable (_ isRealtime: Bool) -> Void
    typealias RelayStatusEffect = @MainActor @Sendable (
        _ transition: HomeTimelineRelayStatusTransition?
    ) -> Void

    let context: ContextProvider
    let setRealtime: RealtimeEffect
    let applyRelayStatusTransition: RelayStatusEffect
    let handleEvent: HomeTimelineRuntimePacketHandlers.EventHandler
    let handleBackwardCompletion:
        HomeTimelineRuntimePacketHandlers.BackwardCompletionHandler
}

struct HomeTimelineRuntimeSessionEffects: Sendable {
    typealias Action = @MainActor @Sendable () -> Void

    let isAccountCurrent: HomeTimelineRuntimeSessionHandlers.AccountValidity
    let application: HomeTimelineRuntimeApplicationEffects
    let packet: HomeTimelineRuntimePacketEffects
    let publishProfileMetadataChange: Action
    let invalidateListEntries: Action
    let scheduleMaterialization: Action
}

struct HomeTimelineRuntimeSetupEffects: Sendable {
    typealias RealtimeEffect = @MainActor @Sendable (_ isRealtime: Bool) -> Void
    typealias DiagnosticEffect = @MainActor @Sendable (
        _ diagnostic: HomeTimelineRuntimeSetupDiagnostic
    ) -> Void

    let setRealtime: RealtimeEffect
    let recordDiagnostic: DiagnosticEffect
}

@MainActor
final class HomeTimelineRuntimeWorkflow {
    private let session: any HomeTimelineRuntimeSessionStarting
    private let setup: any HomeTimelineRuntimeSetupManaging
    private let packetRouter: any HomeTimelineRuntimePacketRouting

    init(
        session: any HomeTimelineRuntimeSessionStarting,
        setup: any HomeTimelineRuntimeSetupManaging,
        packetRouter: any HomeTimelineRuntimePacketRouting
    ) {
        self.session = session
        self.setup = setup
        self.packetRouter = packetRouter
    }

    @discardableResult
    func startSession(
        _ request: HomeTimelineRuntimeSessionRequest,
        effects: HomeTimelineRuntimeSessionEffects
    ) -> HomeTimelineRuntimeSessionStart {
        session.start(
            request,
            handlers: sessionHandlers(effects: effects)
        )
    }

    func configure(
        _ request: HomeTimelineRuntimeSetupRequest,
        effects: HomeTimelineRuntimeSetupEffects
    ) async {
        await setup.configure(
            request,
            handlers: setupHandlers(effects: effects)
        )
    }

    func resetSetup() {
        setup.reset()
    }

    func handlePackets(
        _ packets: [NostrRelayRuntimePacket],
        effects: HomeTimelineRuntimePacketEffects
    ) async {
        guard let context = effects.context() else { return }
        await packetRouter.handle(
            packets,
            context: context,
            handlers: packetHandlers(effects: effects)
        )
    }

    func handlePacket(
        _ packet: NostrRelayRuntimePacket,
        effects: HomeTimelineRuntimePacketEffects
    ) async {
        await handlePackets([packet], effects: effects)
    }

    private func sessionHandlers(
        effects: HomeTimelineRuntimeSessionEffects
    ) -> HomeTimelineRuntimeSessionHandlers {
        HomeTimelineRuntimeSessionHandlers(
            isAccountCurrent: effects.isAccountCurrent,
            handlePacket: { [weak self] packets in
                await self?.handlePackets(packets, effects: effects.packet)
            },
            applicationEffects: effects.application,
            perform: { [weak self] command in
                self?.apply(command, effects: effects)
            }
        )
    }

    private func setupHandlers(
        effects: HomeTimelineRuntimeSetupEffects
    ) -> HomeTimelineRuntimeSetupHandlers {
        HomeTimelineRuntimeSetupHandlers(
            perform: { [weak self] command in
                self?.apply(command, effects: effects)
            }
        )
    }

    private func packetHandlers(
        effects: HomeTimelineRuntimePacketEffects
    ) -> HomeTimelineRuntimePacketHandlers {
        HomeTimelineRuntimePacketHandlers(
            applyState: { [weak self] application in
                self?.apply(application, effects: effects)
            },
            handleEvent: effects.handleEvent,
            handleBackwardCompletion: effects.handleBackwardCompletion
        )
    }

    private func apply(
        _ command: HomeTimelineRuntimeSessionCommand,
        effects: HomeTimelineRuntimeSessionEffects
    ) {
        switch command {
        case .profileMetadataChanged:
            effects.publishProfileMetadataChange()
        case .profileDirectoryChanged:
            effects.invalidateListEntries()
            effects.scheduleMaterialization()
        }
    }

    private func apply(
        _ command: HomeTimelineRuntimeSetupCommand,
        effects: HomeTimelineRuntimeSetupEffects
    ) {
        switch command {
        case .setRealtime(let isRealtime):
            effects.setRealtime(isRealtime)
        case .recordDiagnostic(let diagnostic):
            effects.recordDiagnostic(diagnostic)
        }
    }

    private func apply(
        _ application: HomeTimelineRuntimePacketApplication,
        effects: HomeTimelineRuntimePacketEffects
    ) {
        if let realtimeState = application.realtimeState {
            effects.setRealtime(realtimeState)
        }
        effects.applyRelayStatusTransition(application.relayStatusTransition)
    }
}
