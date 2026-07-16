import AstrenzaCore

@MainActor
protocol HomeStoreViewportInteracting: AnyObject {
    func setRestoreProjectionAnchor(
        _ anchorEventID: String?,
        context: HomeTimelineViewportInteractionContext
    )
    func refresh(_ context: HomeTimelineViewportInteractionContext)
    func refreshLatest(
        _ context: HomeTimelineViewportInteractionContext
    ) async
    func setTimelineAtNewestWindow(
        _ isAtNewestWindow: Bool,
        context: HomeTimelineViewportInteractionContext
    )
    func setTimelineScrollActive(
        _ isActive: Bool,
        context: HomeTimelineViewportInteractionContext
    )
    func dismissUnreadBadge(
        _ context: HomeTimelineViewportInteractionContext
    )
    func markMaterializedPostsRead(
        visiblePostIDs: [TimelinePost.ID],
        context: HomeTimelineViewportInteractionContext
    )
    func markNewestMaterializedWindowRead(
        _ context: HomeTimelineViewportInteractionContext
    )
    func applyPendingNewEvents(
        _ context: HomeTimelineViewportInteractionContext
    ) -> Bool
    func clearPendingEvents(
        _ context: HomeTimelineViewportInteractionContext
    ) -> Bool
    func loadOlder(_ context: HomeTimelineViewportInteractionContext)

    #if DEBUG
    func replacePendingEventIDs(
        _ eventIDs: Set<String>,
        context: HomeTimelineViewportInteractionContext
    )
    #endif
}

extension HomeTimelineViewportInteractionWorkflow:
    HomeStoreViewportInteracting {}

@MainActor
protocol HomeStoreProjectionViewportCoordinating: AnyObject {
    var restoreAnchorEventID: String? { get }
    var isAtNewestWindow: Bool { get }

    @discardableResult
    func apply(
        _ transition: HomeTimelineProjectionViewportTransition
    ) -> Bool
}

extension HomeProjectionViewportCoordinator:
    HomeStoreProjectionViewportCoordinating {}

@MainActor
protocol HomeStoreViewportContextProviding: AnyObject {
    func viewportContext() -> HomeTimelineViewportInteractionContext
}

extension HomeStoreContextCoordinator: HomeStoreViewportContextProviding {}

@MainActor
final class HomeStoreViewportCoordinator {
    private let interaction: any HomeStoreViewportInteracting
    private let projection: any HomeStoreProjectionViewportCoordinating
    private let contexts: any HomeStoreViewportContextProviding

    init(
        interaction: any HomeStoreViewportInteracting,
        projection: any HomeStoreProjectionViewportCoordinating,
        contexts: any HomeStoreViewportContextProviding
    ) {
        self.interaction = interaction
        self.projection = projection
        self.contexts = contexts
    }

    static func live(
        components: HomeTimelineStoreComponents,
        projection: HomeProjectionViewportCoordinator,
        contexts: HomeStoreContextCoordinator
    ) -> HomeStoreViewportCoordinator {
        HomeStoreViewportCoordinator(
            interaction: components.viewportInteractionWorkflow,
            projection: projection,
            contexts: contexts
        )
    }

    var restoreProjectionAnchorEventID: String? {
        projection.restoreAnchorEventID
    }

    var isTimelineAtNewestWindow: Bool {
        projection.isAtNewestWindow
    }

    func setRestoreProjectionAnchor(_ anchorEventID: String?) {
        interaction.setRestoreProjectionAnchor(
            anchorEventID,
            context: contexts.viewportContext()
        )
    }

    func refresh() {
        interaction.refresh(contexts.viewportContext())
    }

    func refreshLatest() async {
        await interaction.refreshLatest(contexts.viewportContext())
    }

    func setTimelineAtNewestWindow(_ isAtNewestWindow: Bool) {
        interaction.setTimelineAtNewestWindow(
            isAtNewestWindow,
            context: contexts.viewportContext()
        )
    }

    func setTimelineScrollActive(_ isActive: Bool) {
        interaction.setTimelineScrollActive(
            isActive,
            context: contexts.viewportContext()
        )
    }

    func dismissUnreadBadge() {
        interaction.dismissUnreadBadge(contexts.viewportContext())
    }

    func markMaterializedPostsRead(
        visiblePostIDs: [TimelinePost.ID]
    ) {
        interaction.markMaterializedPostsRead(
            visiblePostIDs: visiblePostIDs,
            context: contexts.viewportContext()
        )
    }

    func markNewestMaterializedWindowRead() {
        interaction.markNewestMaterializedWindowRead(
            contexts.viewportContext()
        )
    }

    @discardableResult
    func applyPendingNewEvents() -> Bool {
        interaction.applyPendingNewEvents(contexts.viewportContext())
    }

    func loadOlder() {
        interaction.loadOlder(contexts.viewportContext())
    }

    @discardableResult
    func clearPendingNewEvents() -> Bool {
        interaction.clearPendingEvents(contexts.viewportContext())
    }

    @discardableResult
    func applyProjectionViewportTransition(
        _ transition: HomeTimelineProjectionViewportTransition
    ) -> Bool {
        projection.apply(transition)
    }

    #if DEBUG
    func replacePendingEventIDs(_ eventIDs: Set<String>) {
        interaction.replacePendingEventIDs(
            eventIDs,
            context: contexts.viewportContext()
        )
    }
    #endif
}
