import AstrenzaCore
import Testing
@testable import Astrenza

@Suite("Home viewport context factory")
@MainActor
struct HomeViewportContextFactoryTests {
    @Test("Each context projects the current viewport state")
    func contextProjectsCurrentState() {
        let fixture = ViewportContextFactoryFixture()
        let context = fixture.factory.context()

        #expect(context.state.presentation.account == fixture.account)
        #expect(
            context.state.presentation.restoreProjectionAnchorEventID ==
                "anchor"
        )
        #expect(context.state.pendingEvents == HomeTimelinePendingEventsState(
            account: fixture.account,
            hasPendingProjectionReload: true
        ))
        #expect(context.state.pagination == HomeTimelinePaginationState(
            account: fixture.account,
            canBeginLoadingOlder: true,
            hasMoreOlder: true,
            hasTimelineEvents: true,
            hasResolvedRelays: true,
            hasFollowedPubkeys: true
        ))

        fixture.probe.snapshot = fixture.replacementSnapshot
        let replacement = fixture.factory.context()

        #expect(
            replacement.state.presentation.account ==
                fixture.replacementAccount
        )
        #expect(
            replacement.state.presentation
                .restoreProjectionAnchorEventID == nil
        )
        #expect(
            replacement.state.pendingEvents ==
                HomeTimelinePendingEventsState(
                    account: fixture.replacementAccount,
                    hasPendingProjectionReload: false
                )
        )
        #expect(
            replacement.state.pagination == HomeTimelinePaginationState(
                account: fixture.replacementAccount,
                canBeginLoadingOlder: false,
                hasMoreOlder: false,
                hasTimelineEvents: false,
                hasResolvedRelays: false,
                hasFollowedPubkeys: false
            )
        )
    }

    @Test("Cached component effects preserve every typed route")
    func componentEffectsPreserveRoutes() async {
        let fixture = ViewportContextFactoryFixture()
        let context = fixture.factory.context()

        await fixture.invokeAllEffects(in: context)

        #expect(fixture.probe.events == [
            .projection(.setRestoreAnchor("presentation")),
            .reloadNewest(fixture.account),
            .materialize(true),
            .applyRestoreAnchor(fixture.account),
            .presentationTransition(
                fixture.presentationTransition.changes,
                fixture.presentationTransition.didChangeReadState
            ),
            .scheduleReadStateSave,
            .projection(.resetToNewest),
            .reloadNewest(fixture.account),
            .pendingEventCount(3),
            .clearPendingProjectionReload,
            .materialize(false),
            .scheduleLinkPreviewResolution,
            .projection(.setNewestWindow(false))
        ])
        #expect(fixture.probe.loads == [
            .refreshLatest(fixture.account, fixture.lifecycle),
            .loadOlder(fixture.account, fixture.lifecycle)
        ])
    }
}

@MainActor
private final class ViewportContextFactoryProbe {
    enum Event: Equatable {
        case projection(HomeTimelineProjectionViewportTransition)
        case reloadNewest(NostrAccount)
        case materialize(Bool)
        case applyRestoreAnchor(NostrAccount)
        case presentationTransition(HomeTimelinePresentationChanges, Bool)
        case scheduleReadStateSave
        case pendingEventCount(Int)
        case clearPendingProjectionReload
        case scheduleLinkPreviewResolution
    }

    var snapshot: HomeViewportStoreSnapshot?
    private(set) var events: [Event] = []
    private(set) var loads: [HomeTimelineViewportInteractionLoad] = []

    init(snapshot: HomeViewportStoreSnapshot) {
        self.snapshot = snapshot
    }

    var environment: HomeViewportContextEnvironment {
        HomeViewportContextEnvironment(
            snapshot: { [self] in snapshot },
            applications: HomeTimelineViewportApplicationEffects(
                applyProjectionViewportTransition: { [self] transition in
                    events.append(.projection(transition))
                },
                reloadNewestProjectionWindow: { [self] account in
                    events.append(.reloadNewest(account))
                },
                materializeEntries: { [self] allowsRealtimeFollow in
                    events.append(.materialize(allowsRealtimeFollow))
                },
                waitForPendingPresentation: { true },
                applyRestoreProjectionAnchor: { [self] account in
                    events.append(.applyRestoreAnchor(account))
                },
                applyPresentationTransition: { [self] transition in
                    events.append(.presentationTransition(
                        transition.changes,
                        transition.didChangeReadState
                    ))
                },
                scheduleReadStateSave: { [self] in
                    events.append(.scheduleReadStateSave)
                },
                applyPendingEventCountPublication: { [self] publication in
                    events.append(.pendingEventCount(publication.count))
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
        )
    }
}

@MainActor
private struct ViewportContextFactoryFixture {
    let account = NostrAccount(
        pubkey: String(repeating: "a", count: 64),
        displayIdentifier: "viewport-context",
        readOnly: true
    )
    let replacementAccount = NostrAccount(
        pubkey: String(repeating: "b", count: 64),
        displayIdentifier: "replacement",
        readOnly: true
    )
    let lifecycle = HomeTimelineLifecycleToken(
        accountID: String(repeating: "a", count: 64),
        generation: 7
    )
    let probe: ViewportContextFactoryProbe
    let factory: HomeViewportContextFactory

    init() {
        let account = NostrAccount(
            pubkey: String(repeating: "a", count: 64),
            displayIdentifier: "viewport-context",
            readOnly: true
        )
        let probe = ViewportContextFactoryProbe(
            snapshot: HomeViewportStoreSnapshot(
                account: account,
                restoreProjectionAnchorEventID: "anchor",
                hasPendingProjectionReload: true,
                canBeginLoadingOlder: true,
                hasMoreOlder: true,
                hasTimelineEvents: true,
                hasResolvedRelays: true,
                hasFollowedPubkeys: true
            )
        )
        self.probe = probe
        factory = HomeViewportContextFactory(environment: probe.environment)
    }

    var replacementSnapshot: HomeViewportStoreSnapshot {
        HomeViewportStoreSnapshot(
            account: replacementAccount,
            restoreProjectionAnchorEventID: nil,
            hasPendingProjectionReload: false,
            canBeginLoadingOlder: false,
            hasMoreOlder: false,
            hasTimelineEvents: false,
            hasResolvedRelays: false,
            hasFollowedPubkeys: false
        )
    }

    var presentationTransition: HomeTimelinePresentationTransition {
        HomeTimelinePresentationTransition(
            snapshot: HomeTimelinePresentationSnapshot(
                entries: [],
                filterStatus: TimelineFilterStatus(),
                materializedUnreadCount: 0,
                visibleUnreadBadgeCount: 0,
                resolvedContentRevision: 4,
                realtimeFollowSourceRevision: nil
            ),
            changes: [.entries, .resolvedContentRevision],
            didChangeReadState: true
        )
    }

    func invokeAllEffects(
        in context: HomeTimelineViewportInteractionContext
    ) async {
        context.presentationEffects.applyProjectionViewportTransition(
            .setRestoreAnchor("presentation")
        )
        context.presentationEffects.reloadNewestProjectionWindow(account)
        context.presentationEffects.materializeEntries(true)
        context.presentationEffects.applyRestoreProjectionAnchor(account)
        context.presentationEffects.applyPresentationTransition(
            presentationTransition
        )
        context.presentationEffects.scheduleReadStateSave()

        context.pendingEventsEffects.applyProjectionViewportTransition(
            .resetToNewest
        )
        context.pendingEventsEffects.reloadNewestProjection(account)
        context.pendingEventsEffects.applyPendingEventCountPublication(
            HomeTimelinePendingEventCountPublication(count: 3)
        )
        context.pendingEventsEffects.clearPendingProjectionReload()
        context.pendingEventsEffects.materializeEntries()
        context.pendingEventsEffects.scheduleLinkPreviewResolution()

        context.paginationEffects.applyProjectionViewportTransition(
            .setNewestWindow(false)
        )
        await context.paginationEffects.refreshLatest(account, lifecycle)
        await context.paginationEffects.loadOlder(account, lifecycle)
    }
}
