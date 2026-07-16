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

struct HomeStoreReadBoundarySnapshot {
    let account: NostrAccount?
    let entries: [TimelineFeedEntry]
    let currentBoundaryPostID: TimelinePost.ID?
}

@MainActor
protocol HomeStoreReadBoundarySourcing: AnyObject {
    func snapshot() -> HomeStoreReadBoundarySnapshot
    func timelineEvent(id: String) -> NostrEvent?
    func applyRestoredReadBoundary(postID: String)
}

@MainActor
final class HomeStoreReadBoundarySource: HomeStoreReadBoundarySourcing {
    typealias SnapshotProvider = @MainActor () -> HomeStoreReadBoundarySnapshot
    typealias EventProvider = @MainActor (_ id: String) -> NostrEvent?
    typealias BoundaryApplication = @MainActor (_ postID: String) -> Void

    private let snapshotProvider: SnapshotProvider
    private let eventProvider: EventProvider
    private let boundaryApplication: BoundaryApplication

    init(
        snapshot: @escaping SnapshotProvider,
        event: @escaping EventProvider,
        applyRestoredBoundary: @escaping BoundaryApplication
    ) {
        snapshotProvider = snapshot
        eventProvider = event
        boundaryApplication = applyRestoredBoundary
    }

    static func live(
        components: HomeTimelineStoreComponents,
        query: HomeStoreQueryCoordinator
    ) -> HomeStoreReadBoundarySource {
        let publishedState = components.publishedStateCoordinator
        let presentation = components.presentationWorkflow
        return HomeStoreReadBoundarySource(
            snapshot: {
                HomeStoreReadBoundarySnapshot(
                    account: publishedState.accountContext.account,
                    entries: publishedState.presentation.entries,
                    currentBoundaryPostID:
                        presentation.interactionState.readBoundaryPostID
                )
            },
            event: { eventID in
                query.timelineEvent(id: eventID)
            },
            applyRestoredBoundary: { postID in
                publishedState.applyPresentationTransition(
                    presentation.restoreReadBoundary(postID: postID)
                )
            }
        )
    }

    func snapshot() -> HomeStoreReadBoundarySnapshot {
        snapshotProvider()
    }

    func timelineEvent(id: String) -> NostrEvent? {
        eventProvider(id)
    }

    func applyRestoredReadBoundary(postID: String) {
        boundaryApplication(postID)
    }
}

@MainActor
final class HomeStoreReadBoundaryCoordinator {
    private let interaction: any HomeStoreReadBoundaryInteracting
    private let source: any HomeStoreReadBoundarySourcing

    init(
        interaction: any HomeStoreReadBoundaryInteracting,
        source: any HomeStoreReadBoundarySourcing
    ) {
        self.interaction = interaction
        self.source = source
    }

    static func live(
        components: HomeTimelineStoreComponents,
        query: HomeStoreQueryCoordinator
    ) -> HomeStoreReadBoundaryCoordinator {
        HomeStoreReadBoundaryCoordinator(
            interaction: components.readBoundaryInteractionWorkflow,
            source: HomeStoreReadBoundarySource.live(
                components: components,
                query: query
            )
        )
    }

    @discardableResult
    func restore(account: NostrAccount) async -> Bool {
        let positions = source.snapshot().entries.compactMap(\.post).map { post in
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
              source.snapshot().account?.pubkey == account.pubkey,
              let boundaryID
        else { return false }
        source.applyRestoredReadBoundary(postID: boundaryID)
        return true
    }

    @discardableResult
    func scheduleSave() -> Bool {
        let snapshot = source.snapshot()
        guard let account = snapshot.account else { return false }
        return interaction.scheduleReadBoundarySave(
            accountID: account.pubkey,
            boundaryEvent: currentBoundaryEvent(snapshot: snapshot)
        )
    }

    func boundaryWrite() -> HomeTimelineReadBoundaryWrite? {
        let snapshot = source.snapshot()
        guard let account = snapshot.account else { return nil }
        return interaction.readBoundaryWrite(
            accountID: account.pubkey,
            boundaryEvent: currentBoundaryEvent(snapshot: snapshot)
        )
    }

    private func currentBoundaryEvent(
        snapshot: HomeStoreReadBoundarySnapshot
    ) -> NostrEvent? {
        guard let boundaryID = snapshot.currentBoundaryPostID else {
            return nil
        }
        return source.timelineEvent(id: boundaryID)
    }
}
