import AstrenzaCore

struct HomeStoreMaterializationSnapshot: Equatable, Sendable {
    let account: NostrAccount?
    let dependencies: HomeTimelineDependencyResolutionState
    let policy: NostrSyncPolicy
}

@MainActor
protocol HomeStorePresentationSourcing: AnyObject {
    var entries: [TimelineFeedEntry] { get }
    var filterStatus: TimelineFilterStatus { get }
    var materializedUnreadCount: Int { get }
    var visibleUnreadBadgeCount: Int { get }
    var resolvedContentRevision: Int { get }
    var profileMetadataRevision: Int { get }
    var realtimeFollowSourceRevision: Int? { get }

    func materializationSnapshot() -> HomeStoreMaterializationSnapshot
    func applyPresentationTransition(
        _ transition: HomeTimelinePresentationTransition
    )
}

@MainActor
final class HomeStorePresentationSource: HomeStorePresentationSourcing {
    private let publishedState: HomeTimelinePublishedStateCoordinator
    private let dataInteraction: HomeTimelineDataInteractionWorkflow

    init(
        publishedState: HomeTimelinePublishedStateCoordinator,
        dataInteraction: HomeTimelineDataInteractionWorkflow
    ) {
        self.publishedState = publishedState
        self.dataInteraction = dataInteraction
    }

    var entries: [TimelineFeedEntry] {
        publishedState.entries
    }

    var filterStatus: TimelineFilterStatus {
        publishedState.filterStatus
    }

    var materializedUnreadCount: Int {
        publishedState.materializedUnreadCount
    }

    var visibleUnreadBadgeCount: Int {
        publishedState.visibleUnreadBadgeCount
    }

    var resolvedContentRevision: Int {
        publishedState.resolvedContentRevision
    }

    var profileMetadataRevision: Int {
        publishedState.profileMetadataRevision
    }

    var realtimeFollowSourceRevision: Int? {
        publishedState.realtimeFollowSourceRevision
    }

    func materializationSnapshot() -> HomeStoreMaterializationSnapshot {
        HomeStoreMaterializationSnapshot(
            account: publishedState.accountContext.account,
            dependencies: dataInteraction.dependencyResolutionState,
            policy: publishedState.accountContext.syncPolicy
        )
    }

    func applyPresentationTransition(
        _ transition: HomeTimelinePresentationTransition
    ) {
        publishedState.applyPresentationTransition(transition)
    }
}

@MainActor
protocol HomeStoreProjectionMaterializing: AnyObject {
    func materialize(
        _ request: HomeTimelineMaterializationRequest,
        onTransition: @escaping HomeTimelineMaterializationCoordinating
            .TransitionHandler
    )
}

extension HomeProjectionInteractionWorkflow:
    HomeStoreProjectionMaterializing {}

@MainActor
protocol HomeStorePresentationScheduling: AnyObject {
    var interactionState: HomeTimelinePresentationInteractionState { get }

    func requestNewestProjectionReload()
    func clearNewestProjectionReload()
    func restoreReadBoundary(
        postID: TimelinePost.ID
    ) -> HomeTimelinePresentationTransition
    func scheduleMaterialization(
        delayNanoseconds: UInt64?,
        allowsRealtimeFollow: Bool?,
        materialize: @escaping HomeTimelinePresentationCoordinating
            .MaterializeHandler
    )

    #if DEBUG
    func replaceEntriesForTesting(
        _ entries: [TimelineFeedEntry],
        renderFingerprint: [Int]
    ) -> HomeTimelinePresentationTransition
    func setReadBoundaryForTesting(
        postID: TimelinePost.ID
    ) -> HomeTimelinePresentationTransition
    #endif
}

extension HomeTimelinePresentationWorkflow:
    HomeStorePresentationScheduling {}

@MainActor
final class HomeStorePresentationCoordinator {
    private let source: any HomeStorePresentationSourcing
    private let projection: any HomeStoreProjectionMaterializing
    private let scheduler: any HomeStorePresentationScheduling

    init(
        source: any HomeStorePresentationSourcing,
        projection: any HomeStoreProjectionMaterializing,
        scheduler: any HomeStorePresentationScheduling
    ) {
        self.source = source
        self.projection = projection
        self.scheduler = scheduler
    }

    static func live(
        components: HomeTimelineStoreComponents
    ) -> HomeStorePresentationCoordinator {
        HomeStorePresentationCoordinator(
            source: HomeStorePresentationSource(
                publishedState: components.publishedStateCoordinator,
                dataInteraction: components.dataInteractionWorkflow
            ),
            projection: components.projectionInteractionWorkflow,
            scheduler: components.presentationWorkflow
        )
    }

    var entries: [TimelineFeedEntry] {
        source.entries
    }

    var filterStatus: TimelineFilterStatus {
        source.filterStatus
    }

    var materializedUnreadCount: Int {
        source.materializedUnreadCount
    }

    var visibleUnreadBadgeCount: Int {
        source.visibleUnreadBadgeCount
    }

    var resolvedContentRevision: Int {
        source.resolvedContentRevision
    }

    var profileMetadataRevision: Int {
        source.profileMetadataRevision
    }

    var realtimeFollowSourceRevision: Int? {
        source.realtimeFollowSourceRevision
    }

    var currentReadBoundaryPostID: TimelinePost.ID? {
        scheduler.interactionState.readBoundaryPostID
    }

    func applyPresentationTransition(
        _ transition: HomeTimelinePresentationTransition
    ) {
        source.applyPresentationTransition(transition)
    }

    func requestNewestProjectionReload() {
        scheduler.requestNewestProjectionReload()
    }

    func clearNewestProjectionReload() {
        scheduler.clearNewestProjectionReload()
    }

    func restoreReadBoundary(postID: TimelinePost.ID) {
        applyPresentationTransition(
            scheduler.restoreReadBoundary(postID: postID)
        )
    }

    func materializeEntries(
        allowsRealtimeFollow: Bool,
        onTransition: HomeTimelineMaterializationCoordinating
            .TransitionHandler?
    ) {
        let snapshot = source.materializationSnapshot()
        projection.materialize(
            HomeTimelineMaterializationRequest(
                account: snapshot.account,
                nip05Resolutions: snapshot.dependencies.nip05Resolutions,
                profileResolutionStates:
                    snapshot.dependencies.profileResolutionStates,
                policy: snapshot.policy,
                allowsRealtimeFollow: allowsRealtimeFollow
            )
        ) { [weak self] transition in
            guard let self else { return }
            applyPresentationTransition(transition)
            onTransition?(transition)
        }
    }

    func scheduleMaterialization(
        delayNanoseconds: UInt64?,
        allowsRealtimeFollow: Bool?
    ) {
        scheduler.scheduleMaterialization(
            delayNanoseconds: delayNanoseconds,
            allowsRealtimeFollow: allowsRealtimeFollow
        ) { [weak self] allowsRealtimeFollow in
            self?.materializeEntries(
                allowsRealtimeFollow: allowsRealtimeFollow,
                onTransition: nil
            )
        }
    }
}

#if DEBUG
extension HomeStorePresentationCoordinator {
    func replaceEntriesForTesting(
        _ entries: [TimelineFeedEntry],
        renderFingerprint: [Int]
    ) {
        applyPresentationTransition(
            scheduler.replaceEntriesForTesting(
                entries,
                renderFingerprint: renderFingerprint
            )
        )
    }

    func setReadBoundaryForTesting(postID: TimelinePost.ID) {
        applyPresentationTransition(
            scheduler.setReadBoundaryForTesting(postID: postID)
        )
    }
}
#endif
