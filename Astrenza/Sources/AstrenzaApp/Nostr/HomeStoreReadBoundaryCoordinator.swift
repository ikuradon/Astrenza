import AstrenzaCore

@MainActor
protocol HomeStoreReadBoundaryInteracting: AnyObject {
    func restoredReadBoundaryPostID(
        accountID: String,
        positions: [HomeTimelineReadPosition]
    ) async -> String?
    func readBoundaryWrite(
        accountID: String,
        boundaryEvent: NostrEvent?
    ) -> HomeTimelineReadBoundaryWrite?
    func scheduleReadBoundarySave(
        accountID: String,
        boundaryEvent: NostrEvent?
    ) -> Bool
}

extension HomeReadBoundaryInteractionWorkflow:
    HomeStoreReadBoundaryInteracting {}

@MainActor
protocol HomeStoreReadBoundaryTarget: AnyObject {
    var account: NostrAccount? { get }
    var entries: [TimelineFeedEntry] { get }
    var currentReadBoundaryPostID: String? { get }

    func timelineEvent(id: String) -> NostrEvent?
    func applyRestoredReadBoundary(postID: String)
}

@MainActor
final class HomeStoreReadBoundaryCoordinator {
    private let interaction: any HomeStoreReadBoundaryInteracting
    private weak var target: (any HomeStoreReadBoundaryTarget)?

    init(
        interaction: any HomeStoreReadBoundaryInteracting,
        target: (any HomeStoreReadBoundaryTarget)? = nil
    ) {
        self.interaction = interaction
        self.target = target
    }

    func bind(target: any HomeStoreReadBoundaryTarget) {
        self.target = target
    }

    @discardableResult
    func restore(account: NostrAccount) async -> Bool {
        guard let entries = target?.entries else { return false }
        let positions = entries.compactMap(\.post).map { post in
            HomeTimelineReadPosition(
                postID: post.id,
                createdAt: post.createdAt
            )
        }
        let boundaryID = await interaction.restoredReadBoundaryPostID(
            accountID: account.pubkey,
            positions: positions
        )
        guard !Task.isCancelled,
              let target,
              target.account?.pubkey == account.pubkey,
              let boundaryID
        else { return false }
        target.applyRestoredReadBoundary(postID: boundaryID)
        return true
    }

    @discardableResult
    func scheduleSave() -> Bool {
        guard let target, let account = target.account else { return false }
        return interaction.scheduleReadBoundarySave(
            accountID: account.pubkey,
            boundaryEvent: currentBoundaryEvent(target: target)
        )
    }

    func boundaryWrite() -> HomeTimelineReadBoundaryWrite? {
        guard let target, let account = target.account else { return nil }
        return interaction.readBoundaryWrite(
            accountID: account.pubkey,
            boundaryEvent: currentBoundaryEvent(target: target)
        )
    }

    private func currentBoundaryEvent(
        target: any HomeStoreReadBoundaryTarget
    ) -> NostrEvent? {
        guard let boundaryID = target.currentReadBoundaryPostID else {
            return nil
        }
        return target.timelineEvent(id: boundaryID)
    }
}
