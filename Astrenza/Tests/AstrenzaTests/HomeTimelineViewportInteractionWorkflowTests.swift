import AstrenzaCore
import Foundation
import Testing
@testable import Astrenza

@Suite("Home timeline viewport interaction workflow")
@MainActor
struct HomeTimelineViewportWorkflowTests {
    @Test("Presentation actions route through one typed application boundary")
    func presentationActionsRouteThroughApplicationBoundary() {
        let fixture = ViewportInteractionFixture()
        let viewport = fixture.viewport()
        fixture.presentationProbe.scrollMaterializationPermission = true
        fixture.presentationProbe.visibleReadTransition = presentationTransition(
            changes: [.unreadCounts],
            didChangeReadState: true
        )

        fixture.workflow.setRestoreProjectionAnchor(
            "anchor",
            context: fixture.context
        )
        fixture.workflow.saveViewportState(
            viewport,
            context: fixture.context
        )
        fixture.workflow.setTimelineAtNewestWindow(
            false,
            context: fixture.context
        )
        fixture.workflow.setTimelineScrollActive(
            false,
            context: fixture.context
        )
        fixture.workflow.markMaterializedPostsRead(
            visiblePostIDs: ["visible"],
            context: fixture.context
        )
        fixture.workflow.dismissUnreadBadge(fixture.context)

        #expect(fixture.applicationProbe.events == [
            .applyProjectionViewportTransition(.setRestoreAnchor("anchor")),
            .applyRestoreProjectionAnchor(fixture.account),
            .scheduleViewportState(viewport),
            .applyProjectionViewportTransition(.setNewestWindow(false)),
            .materializeEntries(true),
            .applyPresentationTransition([.unreadCounts], true),
            .scheduleReadStateSave,
            .applyPresentationTransition([.unreadCounts], false)
        ])
    }

    @Test("Pending events preserve application order across the typed boundary")
    func pendingEventsPreserveApplicationOrder() {
        let fixture = ViewportInteractionFixture(
            hasBufferedEvents: true,
            hasPendingProjectionReload: true
        )

        let didApply = fixture.workflow.applyPendingNewEvents(fixture.context)

        #expect(didApply)
        #expect(fixture.applicationProbe.events == [
            .applyProjectionViewportTransition(.resetToNewest),
            .reloadNewestProjectionWindow(fixture.account),
            .clearBufferedEvents,
            .clearPendingProjectionReload,
            .materializeEntries(false),
            .scheduleLinkPreviewResolution
        ])
    }

    @Test("Pagination routes scheduled and direct loads through one async boundary")
    func paginationRoutesThroughLoadBoundary() async {
        let fixture = ViewportInteractionFixture()

        fixture.workflow.refresh(fixture.context)
        #expect(fixture.applicationProbe.events == [
            .applyProjectionViewportTransition(.resetToNewest)
        ])
        await fixture.lifecycleProbe.runScheduledOperation()

        await fixture.workflow.refreshLatest(fixture.context)
        fixture.workflow.loadOlder(fixture.context)
        await fixture.lifecycleProbe.runScheduledOperation()

        #expect(fixture.applicationProbe.loads == [
            .refreshLatest(fixture.account, fixture.lifecycle),
            .refreshLatest(fixture.account, fixture.lifecycle),
            .loadOlder(fixture.account, fixture.lifecycle)
        ])
    }
}

@MainActor
private struct ViewportInteractionFixture {
    let account = NostrAccount(
        pubkey: String(repeating: "a", count: 64),
        displayIdentifier: "viewport-interaction",
        readOnly: true
    )
    let feedID = "home-feed"
    let lifecycle = HomeTimelineLifecycleToken(
        accountID: String(repeating: "a", count: 64),
        generation: 1
    )
    let presentationProbe: PresentationProbe
    let lifecycleProbe: ViewportInteractionLifecycleProbe
    let applicationProbe = ViewportInteractionApplicationProbe()
    let workflow: HomeTimelineViewportInteractionWorkflow
    let hasBufferedEvents: Bool
    let hasPendingProjectionReload: Bool

    init(
        hasBufferedEvents: Bool = false,
        hasPendingProjectionReload: Bool = false
    ) {
        let presentationProbe = PresentationProbe()
        let lifecycleProbe = ViewportInteractionLifecycleProbe(
            lifecycle: HomeTimelineLifecycleToken(
                accountID: String(repeating: "a", count: 64),
                generation: 1
            )
        )
        self.presentationProbe = presentationProbe
        self.lifecycleProbe = lifecycleProbe
        self.hasBufferedEvents = hasBufferedEvents
        self.hasPendingProjectionReload = hasPendingProjectionReload
        workflow = HomeTimelineViewportInteractionWorkflow(
            presentation: HomeTimelinePresentationWorkflow(
                coordinator: presentationProbe
            ),
            pendingEvents: HomeTimelinePendingEventsWorkflow(),
            pagination: HomeTimelinePaginationWorkflow(
                lifecycleCoordinator: lifecycleProbe
            )
        )
    }

    var context: HomeTimelineViewportInteractionContext {
        HomeTimelineViewportInteractionContext(
            state: HomeTimelineViewportInteractionState(
                presentation: HomeTimelinePresentationAppState(
                    account: account,
                    restoreProjectionAnchorEventID: nil
                ),
                pendingEvents: HomeTimelinePendingEventsState(
                    account: account,
                    hasBufferedEvents: hasBufferedEvents,
                    hasPendingProjectionReload: hasPendingProjectionReload
                ),
                pagination: HomeTimelinePaginationState(
                    account: account,
                    canBeginLoadingOlder: true,
                    hasMoreOlder: true,
                    hasTimelineEvents: true,
                    hasResolvedRelays: true,
                    hasFollowedPubkeys: true
                )
            ),
            effects: applicationProbe.effects
        )
    }

    func viewport() -> TimelineViewportState {
        TimelineViewportState(
            accountID: account.pubkey,
            timelineKey: "home",
            anchorPostID: "anchor",
            anchorOffset: 12,
            contentOffset: 120,
            updatedAt: Date(timeIntervalSince1970: 100)
        )
    }
}

@MainActor
private final class ViewportInteractionApplicationProbe {
    enum Event: Equatable {
        case applyProjectionViewportTransition(
            HomeTimelineProjectionViewportTransition
        )
        case reloadNewestProjectionWindow(NostrAccount)
        case materializeEntries(Bool)
        case applyRestoreProjectionAnchor(NostrAccount)
        case scheduleViewportState(TimelineViewportState)
        case applyPresentationTransition(HomeTimelinePresentationChanges, Bool)
        case scheduleReadStateSave
        case clearBufferedEvents
        case clearPendingProjectionReload
        case scheduleLinkPreviewResolution
    }

    private(set) var events: [Event] = []
    private(set) var loads: [HomeTimelineViewportInteractionLoad] = []

    var effects: HomeTimelineViewportInteractionEffects {
        HomeTimelineViewportInteractionEffects(
            apply: { [self] application in
                record(application)
            },
            load: { [self] load in
                loads.append(load)
            }
        )
    }

    private func record(
        _ application: HomeTimelineViewportApplication
    ) {
        switch application {
        case .applyProjectionViewportTransition(let transition):
            events.append(.applyProjectionViewportTransition(transition))
        case .reloadNewestProjectionWindow(let account):
            events.append(.reloadNewestProjectionWindow(account))
        case .materializeEntries(let allowsRealtimeFollow):
            events.append(.materializeEntries(allowsRealtimeFollow))
        case .applyRestoreProjectionAnchor(let account):
            events.append(.applyRestoreProjectionAnchor(account))
        case .scheduleViewportState(let state):
            events.append(.scheduleViewportState(state))
        case .applyPresentationTransition(let transition):
            events.append(.applyPresentationTransition(
                transition.changes,
                transition.didChangeReadState
            ))
        case .scheduleReadStateSave:
            events.append(.scheduleReadStateSave)
        case .clearBufferedEvents:
            events.append(.clearBufferedEvents)
        case .clearPendingProjectionReload:
            events.append(.clearPendingProjectionReload)
        case .scheduleLinkPreviewResolution:
            events.append(.scheduleLinkPreviewResolution)
        }
    }
}

@MainActor
private final class ViewportInteractionLifecycleProbe:
    HomeTimelinePaginationScheduling {
    typealias PaginationOperation = HomeTimelinePaginationScheduling.Operation

    private let lifecycle: HomeTimelineLifecycleToken
    private var scheduledOperation: PaginationOperation?

    init(lifecycle: HomeTimelineLifecycleToken) {
        self.lifecycle = lifecycle
    }

    func token(for accountID: String) -> HomeTimelineLifecycleToken? {
        lifecycle.accountID == accountID ? lifecycle : nil
    }

    func startPagination(
        for token: HomeTimelineLifecycleToken,
        operation: @escaping PaginationOperation
    ) {
        guard token == lifecycle else { return }
        scheduledOperation = operation
    }

    func runScheduledOperation() async {
        let operation = scheduledOperation
        scheduledOperation = nil
        await operation?()
    }
}
