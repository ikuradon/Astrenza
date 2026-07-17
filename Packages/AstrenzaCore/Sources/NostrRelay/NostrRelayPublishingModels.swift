public struct NostrOutboxRelayPublishResult: Equatable, Sendable {
    public let relayURL: String
    public let accepted: Bool
    public let message: String?

    public init(relayURL: String, accepted: Bool, message: String?) {
        self.relayURL = relayURL
        self.accepted = accepted
        self.message = message
    }
}

public enum NostrOutboxRelayPublishError: Error, Equatable, Sendable {
    case invalidEventFrame
    case relayClosed(String)
    case authRequired(String)
    case timedOut

    public static func message(for error: any Error) -> String {
        switch error {
        case NostrOutboxRelayPublishError.invalidEventFrame:
            "invalid event frame"
        case NostrOutboxRelayPublishError.relayClosed(let message):
            message
        case NostrOutboxRelayPublishError.authRequired(let challenge):
            "auth-required: \(challenge)"
        case NostrOutboxRelayPublishError.timedOut:
            "publish timed out"
        case is CancellationError:
            "publish cancelled"
        default:
            String(describing: error)
        }
    }
}
