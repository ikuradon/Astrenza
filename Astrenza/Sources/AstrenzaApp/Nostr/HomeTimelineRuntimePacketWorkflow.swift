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
        _ relayURL: String,
        _ subscriptionID: String,
        _ event: NostrEvent
    ) async -> Void
    typealias BackwardCompletionHandler = @MainActor @Sendable (
        _ completion: NostrBackwardREQCompletion
    ) -> Void

    let applyState: StateHandler
    let handleEvent: EventHandler
    let handleBackwardCompletion: BackwardCompletionHandler
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
        let application = packetHandler.handle(packet, context: context)
        guard application.wasHandled else { return }

        handlers.applyState(application)
        switch application.action {
        case .event(let relayURL, let subscriptionID, let event):
            await handlers.handleEvent(relayURL, subscriptionID, event)
        case .backwardCompleted(let completion):
            handlers.handleBackwardCompletion(completion)
        case nil:
            break
        }
    }
}
