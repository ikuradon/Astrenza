import AstrenzaCore

@MainActor
protocol HomeTimelineRuntimePacketHandling: AnyObject {
    func handle(
        _ packet: NostrRelayRuntimePacket,
        context: HomeTimelineRuntimePacketContext
    ) -> HomeTimelineRuntimePacketApplication
}

extension HomeTimelineRuntimePacketCoordinator: HomeTimelineRuntimePacketHandling {}

struct HomeTimelineRuntimePacketHandlers: Sendable {
    typealias StateHandler = @MainActor @Sendable (
        _ application: HomeTimelineRuntimePacketApplication
    ) -> Void
    typealias EventHandler = @MainActor @Sendable (
        _ events: [HomeTimelineRuntimeEventEnvelope]
    ) async -> Void
    typealias BackwardCompletionHandler = @MainActor @Sendable (
        _ completion: NostrBackwardREQCompletion
    ) -> Void
    typealias PresentationSettlement = @MainActor @Sendable () async -> Void

    let applyState: StateHandler
    let handleEvent: EventHandler
    let handleBackwardCompletion: BackwardCompletionHandler
    let waitForPendingPresentation: PresentationSettlement
}

@MainActor
final class HomeTimelineRuntimePacketWorkflow {
    private let packetHandler: any HomeTimelineRuntimePacketHandling

    init(packetHandler: any HomeTimelineRuntimePacketHandling) {
        self.packetHandler = packetHandler
    }

    func handle(
        _ packet: NostrRelayRuntimePacket,
        context: HomeTimelineRuntimePacketContext,
        handlers: HomeTimelineRuntimePacketHandlers
    ) async {
        await handle([packet], context: context, handlers: handlers)
    }

    func handle(
        _ packets: [NostrRelayRuntimePacket],
        context: HomeTimelineRuntimePacketContext,
        handlers: HomeTimelineRuntimePacketHandlers
    ) async {
        var pendingEvents: [HomeTimelineRuntimeEventEnvelope] = []

        func flushEvents() async {
            guard !pendingEvents.isEmpty else { return }
            let events = pendingEvents
            pendingEvents.removeAll(keepingCapacity: true)
            await handlers.handleEvent(events)
        }

        for packet in packets {
            let application = packetHandler.handle(packet, context: context)
            guard application.wasHandled else { continue }

            switch application.action {
            case .event(
                let relayURL,
                let subscriptionID,
                let event,
                let receivedWhileRealtime
            ):
                handlers.applyState(application)
                pendingEvents.append(HomeTimelineRuntimeEventEnvelope(
                    relayURL: relayURL,
                    subscriptionID: subscriptionID,
                    event: event,
                    receivedWhileRealtime: receivedWhileRealtime
                ))
            case .backwardCompleted(let completion):
                await flushEvents()
                handlers.applyState(application)
                handlers.handleBackwardCompletion(completion)
            case nil:
                await flushEvents()
                if application.requiresPresentationSettlement {
                    await handlers.waitForPendingPresentation()
                }
                handlers.applyState(application)
            }
        }
        await flushEvents()
    }
}
