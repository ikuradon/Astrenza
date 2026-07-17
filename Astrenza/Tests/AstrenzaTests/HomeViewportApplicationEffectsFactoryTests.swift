import AstrenzaCore
import Testing
@testable import Astrenza

@Suite("Home viewport application effects factory")
@MainActor
struct HomeViewportEffectsFactoryTests {
    @Test("Every viewport effect forwards payloads in call order")
    func forwardsEveryEffect() async {
        let fixture = ViewportEffectFixture()
        let target = ViewportEffectTargetSpy()
        let effects = HomeViewportApplicationEffectsFactory.make(
            target: target
        )

        applyViewportEffects(effects, fixture: fixture)
        await applyViewportLoadEffects(effects, fixture: fixture)

        #expect(target.events == expectedViewportEvents(fixture))
        #expect(target.materializationArguments == [
            ViewportMaterializationArguments(
                allowsRealtimeFollow: true,
                hasTransition: false
            )
        ])
    }

    @Test("Viewport effects do not retain their target")
    func doesNotRetainTarget() throws {
        var target: ViewportEffectTargetSpy? = ViewportEffectTargetSpy()
        weak let weakTarget = target
        let effects = HomeViewportApplicationEffectsFactory.make(
            target: try #require(target)
        )

        target = nil

        #expect(weakTarget == nil)
        effects.clearPendingProjectionReload()
    }
}

@MainActor
private func applyViewportEffects(
    _ effects: HomeTimelineViewportApplicationEffects,
    fixture: ViewportEffectFixture
) {
    effects.applyProjectionViewportTransition(.setRestoreAnchor("anchor"))
    effects.reloadNewestProjectionWindow(fixture.account)
    effects.materializeEntries(true)
    effects.applyRestoreProjectionAnchor(fixture.account)
    effects.applyPresentationTransition(fixture.presentationTransition)
    effects.scheduleReadStateSave()
    effects.applyPendingEventCountPublication(
        HomeTimelinePendingEventCountPublication(count: 3)
    )
    effects.clearPendingProjectionReload()
    effects.scheduleLinkPreviewResolution()
}

@MainActor
private func applyViewportLoadEffects(
    _ effects: HomeTimelineViewportApplicationEffects,
    fixture: ViewportEffectFixture
) async {
    _ = await effects.waitForPendingPresentation()
    await effects.refreshLatest(fixture.account, fixture.lifecycle)
    await effects.loadOlder(fixture.account, fixture.lifecycle)
}

@MainActor
private func expectedViewportEvents(
    _ fixture: ViewportEffectFixture
) -> [ViewportEffectTargetSpy.Event] {
    [
        .projectionViewportTransition(.setRestoreAnchor("anchor")),
        .reloadNewestProjectionWindow(fixture.account.pubkey),
        .materializeEntries,
        .applyRestoreProjectionAnchor(fixture.account.pubkey),
        .presentationTransition(
            changes: fixture.presentationTransition.changes.rawValue,
            didChangeReadState:
                fixture.presentationTransition.didChangeReadState
        ),
        .scheduleReadStateSave,
        .pendingEventCountPublication(3),
        .clearPendingProjectionReload,
        .scheduleLinkPreviewResolution,
        .waitForPendingPresentation,
        .refreshLatest(
            accountID: fixture.account.pubkey,
            lifecycle: fixture.lifecycle
        ),
        .loadOlder(
            accountID: fixture.account.pubkey,
            lifecycle: fixture.lifecycle
        )
    ]
}

private struct ViewportMaterializationArguments: Equatable {
    let allowsRealtimeFollow: Bool
    let hasTransition: Bool
}

@MainActor
private struct ViewportEffectFixture {
    let account = NostrAccount(
        pubkey: String(repeating: "a", count: 64),
        displayIdentifier: "viewport-factory",
        readOnly: true
    )

    var lifecycle: HomeTimelineLifecycleToken {
        HomeTimelineLifecycleToken(
            accountID: account.pubkey,
            generation: 9
        )
    }

    var presentationTransition: HomeTimelinePresentationTransition {
        HomeTimelinePresentationTransition(
            snapshot: HomeTimelinePresentationSnapshot(
                entries: [],
                filterStatus: TimelineFilterStatus(),
                materializedUnreadCount: 0,
                visibleUnreadBadgeCount: 0,
                resolvedContentRevision: 6,
                realtimeFollowSourceRevision: nil
            ),
            changes: [.entries, .resolvedContentRevision],
            didChangeReadState: true
        )
    }
}

@MainActor
private final class ViewportEffectTargetSpy:
    HomeViewportApplicationEffectTarget {
    enum Event: Equatable {
        case projectionViewportTransition(
            HomeTimelineProjectionViewportTransition
        )
        case reloadNewestProjectionWindow(String)
        case materializeEntries
        case applyRestoreProjectionAnchor(String)
        case presentationTransition(changes: Int, didChangeReadState: Bool)
        case scheduleReadStateSave
        case pendingEventCountPublication(Int)
        case clearPendingProjectionReload
        case scheduleLinkPreviewResolution
        case waitForPendingPresentation
        case refreshLatest(
            accountID: String,
            lifecycle: HomeTimelineLifecycleToken
        )
        case loadOlder(
            accountID: String,
            lifecycle: HomeTimelineLifecycleToken
        )
    }

    private(set) var events: [Event] = []
    private(set) var materializationArguments:
        [ViewportMaterializationArguments] = []

    func applyProjectionViewportTransition(
        _ transition: HomeTimelineProjectionViewportTransition
    ) {
        events.append(.projectionViewportTransition(transition))
    }

    func reloadNewestProjectionWindow(account: NostrAccount) {
        events.append(.reloadNewestProjectionWindow(account.pubkey))
    }

    func materializeEntries(
        allowsRealtimeFollow: Bool,
        onTransition: HomeTimelineMaterializationCoordinating
            .TransitionHandler?
    ) {
        materializationArguments.append(ViewportMaterializationArguments(
            allowsRealtimeFollow: allowsRealtimeFollow,
            hasTransition: onTransition != nil
        ))
        events.append(.materializeEntries)
    }

    func applyRestoreProjectionAnchorIfPossible(account: NostrAccount) {
        events.append(.applyRestoreProjectionAnchor(account.pubkey))
    }

    func waitForPendingPresentation() async -> Bool {
        events.append(.waitForPendingPresentation)
        return true
    }

    func applyPresentationTransition(
        _ transition: HomeTimelinePresentationTransition
    ) {
        events.append(.presentationTransition(
            changes: transition.changes.rawValue,
            didChangeReadState: transition.didChangeReadState
        ))
    }

    func scheduleHomeFeedReadStateSave() {
        events.append(.scheduleReadStateSave)
    }

    func applyPendingEventCountPublication(
        _ publication: HomeTimelinePendingEventCountPublication
    ) {
        events.append(.pendingEventCountPublication(publication.count))
    }

    func clearPendingProjectionReload() {
        events.append(.clearPendingProjectionReload)
    }

    func scheduleLinkPreviewResolution() {
        events.append(.scheduleLinkPreviewResolution)
    }

    func refreshLatest(
        account: NostrAccount,
        lifecycle: HomeTimelineLifecycleToken
    ) async {
        events.append(.refreshLatest(
            accountID: account.pubkey,
            lifecycle: lifecycle
        ))
    }

    func loadOlder(
        account: NostrAccount,
        lifecycle: HomeTimelineLifecycleToken
    ) async {
        events.append(.loadOlder(
            accountID: account.pubkey,
            lifecycle: lifecycle
        ))
    }
}
