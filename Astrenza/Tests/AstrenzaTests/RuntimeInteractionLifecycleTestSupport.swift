@testable import Astrenza

enum RuntimeInteractionLifecycleEvent: Equatable {
    case token(accountID: String)
    case begin(accountID: String)
}

@MainActor
final class RuntimeInteractionLifecycleSpy:
    HomeTimelineRuntimeLifecycleTracking {
    private var currentToken: HomeTimelineLifecycleToken?
    private var generation: UInt64 = 100
    private(set) var events: [RuntimeInteractionLifecycleEvent] = []

    init(currentToken: HomeTimelineLifecycleToken?) {
        self.currentToken = currentToken
    }

    func token(for accountID: String) -> HomeTimelineLifecycleToken? {
        events.append(.token(accountID: accountID))
        guard currentToken?.accountID == accountID else { return nil }
        return currentToken
    }

    func begin(accountID: String) -> HomeTimelineLifecycleToken {
        events.append(.begin(accountID: accountID))
        generation &+= 1
        let token = HomeTimelineLifecycleToken(
            accountID: accountID,
            generation: generation
        )
        currentToken = token
        return token
    }
}
