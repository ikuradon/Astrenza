import AstrenzaCore

@MainActor
protocol HomeStoreReadBoundaryInteracting: AnyObject {
    func restoredReadBoundary(
        accountID: String,
        positions: [HomeTimelineReadPosition]
    ) async -> HomeTimelineReadBoundaryRestoreOutcome
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
    let restoredViewportAnchorPostID: TimelinePost.ID?
}

enum HomeStoreReadBoundaryRestorePolicy {
    struct Resolution: Equatable {
        let postID: TimelinePost.ID
        let advancesPersistedBoundary: Bool
    }

    static func resolve(
        restoredBoundary: HomeTimelineReadBoundaryRestoreOutcome,
        restoredViewportAnchorPostID: TimelinePost.ID?,
        orderedPostIDs: [TimelinePost.ID]
    ) -> Resolution? {
        switch restoredBoundary {
        case .missing:
            return nil
        case .olderThanProjection:
            guard let restoredViewportAnchorPostID,
                  orderedPostIDs.contains(restoredViewportAnchorPostID)
            else { return nil }
            return Resolution(
                postID: restoredViewportAnchorPostID,
                advancesPersistedBoundary: true
            )
        case .resolved(let persistedBoundaryPostID):
            guard let restoredViewportAnchorPostID,
                  let persistedBoundaryIndex = orderedPostIDs.firstIndex(
                    of: persistedBoundaryPostID
                  ),
                  let viewportAnchorIndex = orderedPostIDs.firstIndex(
                    of: restoredViewportAnchorPostID
                  ),
                  viewportAnchorIndex < persistedBoundaryIndex
            else {
                return Resolution(
                    postID: persistedBoundaryPostID,
                    advancesPersistedBoundary: false
                )
            }
            return Resolution(
                postID: restoredViewportAnchorPostID,
                advancesPersistedBoundary: true
            )
        }
    }
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
        query: HomeStoreQueryCoordinator,
        projectionViewport: HomeProjectionViewportCoordinator
    ) -> HomeStoreReadBoundarySource {
        let publishedState = components.publishedStateCoordinator
        let presentation = components.presentationWorkflow
        return HomeStoreReadBoundarySource(
            snapshot: {
                HomeStoreReadBoundarySnapshot(
                    account: publishedState.accountContext.account,
                    entries: publishedState.presentation.entries,
                    currentBoundaryPostID:
                        presentation.interactionState.readBoundaryPostID,
                    restoredViewportAnchorPostID:
                        projectionViewport.restoreAnchorEventID
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
        query: HomeStoreQueryCoordinator,
        projectionViewport: HomeProjectionViewportCoordinator
    ) -> HomeStoreReadBoundaryCoordinator {
        HomeStoreReadBoundaryCoordinator(
            interaction: components.readBoundaryInteractionWorkflow,
            source: HomeStoreReadBoundarySource.live(
                components: components,
                query: query,
                projectionViewport: projectionViewport
            )
        )
    }

    @discardableResult
    func restore(account: NostrAccount) async -> Bool {
        let restoreSnapshot = source.snapshot()
        let positions = restoreSnapshot.entries.compactMap(\.post).map { post in
            HomeTimelineReadPosition(
                postID: post.id,
                createdAt: post.createdAt
            )
        }
        let restoredBoundary = await interaction.restoredReadBoundary(
            accountID: account.pubkey,
            positions: positions
        )
        let currentSnapshot = source.snapshot()
        guard !Task.isCancelled,
              currentSnapshot.account?.pubkey == account.pubkey,
              currentSnapshot.restoredViewportAnchorPostID ==
                restoreSnapshot.restoredViewportAnchorPostID,
              let resolution = HomeStoreReadBoundaryRestorePolicy.resolve(
                restoredBoundary: restoredBoundary,
                restoredViewportAnchorPostID:
                    restoreSnapshot.restoredViewportAnchorPostID,
                orderedPostIDs: positions.map(\.postID)
              )
        else { return false }
        source.applyRestoredReadBoundary(postID: resolution.postID)
        if resolution.advancesPersistedBoundary,
           let boundaryEvent = source.timelineEvent(id: resolution.postID) {
            _ = interaction.scheduleReadBoundarySave(
                accountID: account.pubkey,
                boundaryEvent: boundaryEvent
            )
        }
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
