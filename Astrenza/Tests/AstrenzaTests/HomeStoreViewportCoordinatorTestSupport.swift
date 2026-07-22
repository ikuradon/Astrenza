@testable import Astrenza

@MainActor
final class StoreViewportInteractionSpy: HomeStoreViewportInteracting {
    enum Call: Equatable {
        case setRestoreAnchor(String?, String?)
        case refresh(String?)
        case refreshLatest(String?)
        case setNewestWindow(Bool, String?)
        case setScrollActive(Bool, String?)
        case dismissUnreadBadge(String?)
        case markMaterializedPostsRead([String], String?)
        case markNewestMaterializedWindowRead(String?)
        case applyPendingEvents(String?)
        case loadOlder(String?)
        case clearPendingEvents(String?)

        #if DEBUG
        case replacePendingEventIDs(Set<String>, String?)
        #endif
    }

    var applyPendingEventsResult = false
    var clearPendingEventsResult = false
    var onApplyPendingEvents: (@MainActor () async -> Bool)?
    private(set) var calls: [Call] = []

    func setRestoreProjectionAnchor(
        _ anchorEventID: String?,
        context: HomeTimelineViewportInteractionContext
    ) {
        calls.append(.setRestoreAnchor(
            anchorEventID,
            accountID(context)
        ))
    }

    func refresh(_ context: HomeTimelineViewportInteractionContext) {
        calls.append(.refresh(accountID(context)))
    }

    func refreshLatest(
        _ context: HomeTimelineViewportInteractionContext
    ) async {
        calls.append(.refreshLatest(accountID(context)))
    }

    func setTimelineAtNewestWindow(
        _ isAtNewestWindow: Bool,
        context: HomeTimelineViewportInteractionContext
    ) {
        calls.append(.setNewestWindow(
            isAtNewestWindow,
            accountID(context)
        ))
    }

    func setTimelineScrollActive(
        _ isActive: Bool,
        context: HomeTimelineViewportInteractionContext
    ) {
        calls.append(.setScrollActive(isActive, accountID(context)))
    }

    func dismissUnreadBadge(
        _ context: HomeTimelineViewportInteractionContext
    ) {
        calls.append(.dismissUnreadBadge(accountID(context)))
    }

    func markMaterializedPostsRead(
        visiblePostIDs: [TimelinePost.ID],
        context: HomeTimelineViewportInteractionContext
    ) {
        calls.append(.markMaterializedPostsRead(
            visiblePostIDs,
            accountID(context)
        ))
    }

    func markNewestMaterializedWindowRead(
        _ context: HomeTimelineViewportInteractionContext
    ) {
        calls.append(.markNewestMaterializedWindowRead(accountID(context)))
    }

    func applyPendingNewEvents(
        _ context: HomeTimelineViewportInteractionContext,
        preserving anchorPostID: TimelinePost.ID?
    ) async -> Bool {
        calls.append(.applyPendingEvents(accountID(context)))
        if let onApplyPendingEvents {
            return await onApplyPendingEvents()
        }
        return applyPendingEventsResult
    }

    func clearPendingEvents(
        _ context: HomeTimelineViewportInteractionContext
    ) -> Bool {
        calls.append(.clearPendingEvents(accountID(context)))
        return clearPendingEventsResult
    }

    func loadOlder(_ context: HomeTimelineViewportInteractionContext) {
        calls.append(.loadOlder(accountID(context)))
    }

    #if DEBUG
    func replacePendingEventIDs(
        _ eventIDs: Set<String>,
        context: HomeTimelineViewportInteractionContext
    ) {
        calls.append(.replacePendingEventIDs(
            eventIDs,
            accountID(context)
        ))
    }
    #endif

    private func accountID(
        _ context: HomeTimelineViewportInteractionContext
    ) -> String? {
        context.state.presentation.account?.pubkey
    }
}

@MainActor
final class StoreProjectionViewportSpy:
    HomeStoreProjectionViewportCoordinating {
    var restoreAnchorEventID: String?
    var isAtNewestWindow: Bool
    var applyResult = false
    private(set) var transitions: [
        HomeTimelineProjectionViewportTransition
    ] = []

    init(
        restoreAnchorEventID: String? = nil,
        isAtNewestWindow: Bool = true
    ) {
        self.restoreAnchorEventID = restoreAnchorEventID
        self.isAtNewestWindow = isAtNewestWindow
    }

    func apply(
        _ transition: HomeTimelineProjectionViewportTransition
    ) -> Bool {
        transitions.append(transition)
        return applyResult
    }
}

@MainActor
final class StoreViewportStateSpy: HomeStoreViewportStateSourcing {
    var pendingEventCount: Int

    init(pendingEventCount: Int) {
        self.pendingEventCount = pendingEventCount
    }
}

@MainActor
final class StoreViewportContextProviderSpy:
    HomeStoreViewportContextProviding {
    private let context: HomeTimelineViewportInteractionContext
    private(set) var readCount = 0

    init(context: HomeTimelineViewportInteractionContext) {
        self.context = context
    }

    func viewportContext() -> HomeTimelineViewportInteractionContext {
        readCount += 1
        return context
    }
}

@MainActor
struct StoreViewportCoordinatorFixture {
    let accountID: String
    let interaction: StoreViewportInteractionSpy
    let projection: StoreProjectionViewportSpy
    let state: StoreViewportStateSpy
    let contexts: StoreViewportContextProviderSpy
    let coordinator: HomeStoreViewportCoordinator

    init(
        restoreAnchorEventID: String? = nil,
        isAtNewestWindow: Bool = true,
        pendingEventCount: Int = 0
    ) {
        let contextFixture = StoreContextCoordinatorFixture()
        contextFixture.installSnapshots()
        let interaction = StoreViewportInteractionSpy()
        let projection = StoreProjectionViewportSpy(
            restoreAnchorEventID: restoreAnchorEventID,
            isAtNewestWindow: isAtNewestWindow
        )
        let state = StoreViewportStateSpy(
            pendingEventCount: pendingEventCount
        )
        let contexts = StoreViewportContextProviderSpy(
            context: contextFixture.coordinator.viewportContext()
        )
        accountID = contextFixture.account.pubkey
        self.interaction = interaction
        self.projection = projection
        self.state = state
        self.contexts = contexts
        coordinator = HomeStoreViewportCoordinator(
            interaction: interaction,
            projection: projection,
            state: state,
            contexts: contexts
        )
    }
}
