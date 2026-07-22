import AstrenzaCore
import Testing
@testable import Astrenza

@Suite("Home timeline viewport interaction workflow")
@MainActor
struct HomeTimelineViewportWorkflowTests {
    @Test("Presentation actions route through one typed application boundary")
    func presentationActionsRouteThroughApplicationBoundary() {
        let fixture = ViewportInteractionFixture()
        fixture.presentationProbe.scrollMaterializationPermission = true
        fixture.presentationProbe.visibleReadTransition = presentationTransition(
            changes: [.unreadCounts],
            didChangeReadState: true
        )

        fixture.workflow.setRestoreProjectionAnchor(
            "anchor",
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
            .applyProjectionViewportTransition(.setNewestWindow(false)),
            .materializeEntries(true),
            .applyPresentationTransition([.unreadCounts], true),
            .scheduleReadStateSave,
            .applyPresentationTransition([.unreadCounts], false)
        ])
    }

    @Test("Pending events preserve application order across the typed boundary")
    func pendingEventsPreserveApplicationOrder() async {
        let fixture = ViewportInteractionFixture(
            hasBufferedEvents: true,
            hasPendingProjectionReload: true
        )

        let didApply = await fixture.workflow.applyPendingNewEvents(fixture.context)

        #expect(didApply)
        #expect(fixture.applicationProbe.events == [
            .reloadNewestProjectionWindow(fixture.account),
            .materializeEntries(false),
            .waitForPendingPresentation,
            .applyPendingEventCountPublication(0),
            .clearPendingProjectionReload,
            .scheduleLinkPreviewResolution
        ])
        #expect(!fixture.workflow.hasBufferedEvents)
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
        let pendingEventBuffer = HomeTimelinePendingEventBuffer()
        pendingEventBuffer.replaceEventIDs(
            hasBufferedEvents ? ["buffered"] : []
        ) { _ in }
        self.presentationProbe = presentationProbe
        self.lifecycleProbe = lifecycleProbe
        self.hasPendingProjectionReload = hasPendingProjectionReload
        workflow = HomeTimelineViewportInteractionWorkflow(
            presentation: HomeTimelinePresentationWorkflow(
                coordinator: presentationProbe
            ),
            pendingEvents: HomeTimelinePendingEventsWorkflow(
                buffer: pendingEventBuffer
            ),
            pagination: HomeTimelinePaginationWorkflow(
                lifecycleCoordinator: lifecycleProbe
            )
        )
    }

    var context: HomeTimelineViewportInteractionContext {
        HomeViewportContextFactory(
            environment: HomeViewportContextEnvironment(
                snapshot: { [self] in
                    HomeViewportStoreSnapshot(
                        account: account,
                        restoreProjectionAnchorEventID: nil,
                        hasPendingProjectionReload:
                            hasPendingProjectionReload,
                        canBeginLoadingOlder: true,
                        hasMoreOlder: true,
                        hasTimelineEvents: true,
                        hasResolvedRelays: true,
                        hasFollowedPubkeys: true
                    )
                },
                applications: applicationProbe.applications
            )
        )
        .context()
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
        case applyPresentationTransition(HomeTimelinePresentationChanges, Bool)
        case scheduleReadStateSave
        case applyPendingEventCountPublication(Int)
        case clearPendingProjectionReload
        case scheduleLinkPreviewResolution
        case waitForPendingPresentation
    }

    private(set) var events: [Event] = []
    private(set) var loads: [HomeTimelineViewportInteractionLoad] = []

    var applications: HomeTimelineViewportApplicationEffects {
        HomeTimelineViewportApplicationEffects(
            applyProjectionViewportTransition: { [self] transition in
                events.append(.applyProjectionViewportTransition(transition))
            },
            reloadNewestProjectionWindow: { [self] account in
                events.append(.reloadNewestProjectionWindow(account))
            },
            materializeEntries: { [self] allowsRealtimeFollow in
                events.append(.materializeEntries(allowsRealtimeFollow))
            },
            waitForPendingPresentation: { [self] in
                events.append(.waitForPendingPresentation)
                return true
            },
            applyRestoreProjectionAnchor: { [self] account in
                events.append(.applyRestoreProjectionAnchor(account))
            },
            applyPresentationTransition: { [self] transition in
                events.append(.applyPresentationTransition(
                    transition.changes,
                    transition.didChangeReadState
                ))
            },
            scheduleReadStateSave: { [self] in
                events.append(.scheduleReadStateSave)
            },
            applyPendingEventCountPublication: { [self] publication in
                events.append(.applyPendingEventCountPublication(
                    publication.count
                ))
            },
            clearPendingProjectionReload: { [self] in
                events.append(.clearPendingProjectionReload)
            },
            scheduleLinkPreviewResolution: { [self] in
                events.append(.scheduleLinkPreviewResolution)
            },
            refreshLatest: { [self] account, lifecycle in
                loads.append(.refreshLatest(account, lifecycle))
            },
            loadOlder: { [self] account, lifecycle in
                loads.append(.loadOlder(account, lifecycle))
            }
        )
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
