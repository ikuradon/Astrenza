import AstrenzaCore

enum HomeTimelineAccountContextTransition: Equatable, Sendable {
    case activate(NostrAccount, syncPolicy: NostrSyncPolicy)
    case clear
}

struct HomeTimelinePublishedAccountContextState: Equatable, Sendable {
    private(set) var account: NostrAccount?
    private(set) var syncPolicy: NostrSyncPolicy

    init(
        account: NostrAccount? = nil,
        syncPolicy: NostrSyncPolicy
    ) {
        self.account = account
        self.syncPolicy = syncPolicy
    }

    func applying(
        _ transition: HomeTimelineAccountContextTransition
    ) -> HomeTimelinePublishedAccountContextState? {
        let next: HomeTimelinePublishedAccountContextState
        switch transition {
        case .activate(let account, let syncPolicy):
            next = HomeTimelinePublishedAccountContextState(
                account: account,
                syncPolicy: syncPolicy
            )
        case .clear:
            next = HomeTimelinePublishedAccountContextState(
                syncPolicy: syncPolicy
            )
        }
        return next == self ? nil : next
    }
}
