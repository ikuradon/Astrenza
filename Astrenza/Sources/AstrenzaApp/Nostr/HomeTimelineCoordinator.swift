import Foundation
import AstrenzaCore

@MainActor
protocol HomeTimelineCoordinating {
    func handleRuntimePacket(
        _ packet: NostrRelayRuntimePacket,
        handlers: HomeTimelineRuntimePacketHandlers
    )
}

@MainActor
struct HomeTimelineRuntimePacketHandlers {
    let shouldHandle: () -> Bool
    let stateChanged: (_ relayURL: String, _ state: NostrRelayConnectionState) -> Void
    let event: (_ relayURL: String, _ subscriptionID: String, _ event: NostrEvent) -> Void
    let eose: (_ relayURL: String, _ subscriptionID: String) -> Void
    let closed: (_ relayURL: String, _ subscriptionID: String, _ message: String) -> Void
    let timeout: (_ relayURL: String, _ subscriptionID: String, _ message: String) -> Void
    let backwardCompleted: (_ completion: NostrBackwardREQCompletion) -> Void
    let notice: (_ relayURL: String, _ message: String) -> Void
    let auth: (_ relayURL: String, _ challenge: String) -> Void
}

@MainActor
struct HomeTimelineCoordinator: HomeTimelineCoordinating {
    func handleRuntimePacket(
        _ packet: NostrRelayRuntimePacket,
        handlers: HomeTimelineRuntimePacketHandlers
    ) {
        guard handlers.shouldHandle() else { return }

        switch packet {
        case .stateChanged(let relayURL, let state):
            handlers.stateChanged(relayURL, state)
        case .event(let relayURL, let subscriptionID, let event):
            handlers.event(relayURL, subscriptionID, event)
        case .eose(let relayURL, let subscriptionID):
            handlers.eose(relayURL, subscriptionID)
        case .closed(let relayURL, let subscriptionID, let message):
            handlers.closed(relayURL, subscriptionID, message)
        case .timeout(let relayURL, let subscriptionID, let message):
            handlers.timeout(relayURL, subscriptionID, message)
        case .backwardCompleted(let completion):
            handlers.backwardCompleted(completion)
        case .notice(let relayURL, let message):
            handlers.notice(relayURL, message)
        case .auth(let relayURL, let challenge):
            handlers.auth(relayURL, challenge)
        }
    }
}
