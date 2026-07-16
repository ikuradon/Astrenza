import AstrenzaCore
import Testing
@testable import Astrenza

@Suite("Home account application effects factory")
@MainActor
struct HomeAccountEffectsFactoryTests {
    @Test("Every account effect forwards payloads in call order")
    func forwardsEveryEffect() async {
        let fixture = AccountApplicationEffectFixture()
        let target = AccountApplicationEffectTargetSpy()
        let effects = HomeAccountApplicationEffectsFactory.make(target: target)

        applyAccountStartEffects(effects, fixture: fixture)
        applyAccountResetEffects(effects, fixture: fixture)
        await effects.configureRuntime(fixture.account, true)

        #expect(target.events == expectedAccountStartEvents(fixture) +
            expectedAccountResetEvents(fixture) + [
                .configureRuntime(
                    accountID: fixture.account.pubkey,
                    forceInstall: true
                )
            ])
        #expect(target.materializationArguments == [
            AccountMaterializationArguments(
                allowsRealtimeFollow: false,
                hasTransition: false
            )
        ])
        #expect(target.resetRealtimeKeyCounts == [0])
    }

    @Test("Account effects do not retain their target")
    func doesNotRetainTarget() throws {
        var target: AccountApplicationEffectTargetSpy? =
            AccountApplicationEffectTargetSpy()
        weak let weakTarget = target
        let effects = HomeAccountApplicationEffectsFactory.make(
            target: try #require(target)
        )

        target = nil

        #expect(weakTarget == nil)
        effects.cancelCurrentAccount()
    }
}

@MainActor
private func applyAccountStartEffects(
    _ effects: HomeTimelineAccountApplicationEffects,
    fixture: AccountApplicationEffectFixture
) {
    effects.cancelCurrentAccount()
    effects.applyAccountContextTransition(fixture.accountContextTransition)
    effects.startRuntimeSession()
    effects.prepareHomeFeedDefinition(fixture.account)
    effects.applyProjectionViewportTransition(fixture.viewportTransition)
    effects.reloadNewestProjectionWindow(fixture.account)
    effects.materializeEntries()
    effects.applyRestoreProjectionAnchor(fixture.account)
    effects.installProvisionalRuntimeBootstrap(fixture.account)
    effects.setPhase(.resolvingRelays)
    effects.publishRelayStatusChange()
}

@MainActor
private func applyAccountResetEffects(
    _ effects: HomeTimelineAccountApplicationEffects,
    fixture: AccountApplicationEffectFixture
) {
    effects.applyPresentationTransition(fixture.presentationTransition)
    effects.clearPendingEvents()
    effects.applyActivityTransition(fixture.activityTransition)
    effects.invalidateListEntries()
    effects.resetRealtimeState()
    effects.applyContentSnapshot(fixture.contentSnapshot)
    effects.applyRelayStatusSnapshot(fixture.relayStatusSnapshot)
    effects.resetRuntimeSetup()
}

@MainActor
private func expectedAccountStartEvents(
    _ fixture: AccountApplicationEffectFixture
) -> [AccountApplicationEffectTargetSpy.Event] {
    [
        .cancelCurrentAccount,
        .accountContextTransition(fixture.accountContextTransition),
        .startRuntimeSession,
        .prepareHomeFeedDefinition(fixture.account.pubkey),
        .projectionViewportTransition(fixture.viewportTransition),
        .reloadNewestProjectionWindow(fixture.account.pubkey),
        .materializeEntries,
        .applyRestoreProjectionAnchor(fixture.account.pubkey),
        .installProvisionalRuntimeBootstrap(fixture.account.pubkey),
        .setPhase(.resolvingRelays),
        .publishRelayStatusChange
    ]
}

@MainActor
private func expectedAccountResetEvents(
    _ fixture: AccountApplicationEffectFixture
) -> [AccountApplicationEffectTargetSpy.Event] {
    [
        .presentationTransition(
            changes: fixture.presentationTransition.changes.rawValue,
            didChangeReadState:
                fixture.presentationTransition.didChangeReadState
        ),
        .clearPendingEvents,
        .activityTransition(fixture.activityTransition),
        .invalidateListEntries,
        .resetRealtimeState,
        .contentSnapshot(fixture.contentSnapshot),
        .relayStatusSnapshot(fixture.relayStatusSnapshot),
        .resetRuntimeSetup
    ]
}

private struct AccountMaterializationArguments: Equatable {
    let allowsRealtimeFollow: Bool
    let hasTransition: Bool
}

@MainActor
private struct AccountApplicationEffectFixture {
    let account = NostrAccount(
        pubkey: String(repeating: "a", count: 64),
        displayIdentifier: "account-factory",
        readOnly: true
    )

    var accountContextTransition: HomeTimelineAccountContextTransition {
        .activate(account, syncPolicy: .default(networkType: .wifi))
    }

    var viewportTransition: HomeTimelineProjectionViewportTransition {
        .restoreViewport(anchorEventID: "factory-anchor")
    }

    var presentationTransition: HomeTimelinePresentationTransition {
        HomeTimelinePresentationTransition(
            snapshot: HomeTimelinePresentationSnapshot(
                entries: [],
                filterStatus: TimelineFilterStatus(),
                materializedUnreadCount: 0,
                visibleUnreadBadgeCount: 0,
                resolvedContentRevision: 5,
                realtimeFollowSourceRevision: nil
            ),
            changes: [.entries, .resolvedContentRevision],
            didChangeReadState: true
        )
    }

    var activityTransition: HomeTimelineActivityTransition {
        HomeTimelineActivityTransition(
            snapshot: HomeTimelineActivitySnapshot(
                phase: .resolvingRelays,
                isRefreshing: false,
                isLoadingOlder: false,
                isRealtime: false
            ),
            changes: [.phase]
        )
    }

    var contentSnapshot: HomeTimelineContentSnapshot {
        HomeTimelineContentSnapshot.initial
    }

    var relayStatusSnapshot: HomeTimelineRelayStatusSnapshot {
        HomeTimelineRelayStatusSnapshot(
            runtimeStates: [:],
            connectedRelayCount: 1,
            plannedRelayCount: 3
        )
    }
}

@MainActor
private final class AccountApplicationEffectTargetSpy:
    HomeAccountApplicationEffectTarget {
    enum Event: Equatable {
        case cancelCurrentAccount
        case accountContextTransition(HomeTimelineAccountContextTransition)
        case startRuntimeSession
        case prepareHomeFeedDefinition(String)
        case projectionViewportTransition(
            HomeTimelineProjectionViewportTransition
        )
        case reloadNewestProjectionWindow(String)
        case materializeEntries
        case applyRestoreProjectionAnchor(String)
        case installProvisionalRuntimeBootstrap(String)
        case setPhase(NostrHomeTimelinePhase)
        case setRealtime(Bool)
        case publishRelayStatusChange
        case presentationTransition(changes: Int, didChangeReadState: Bool)
        case clearPendingEvents
        case activityTransition(HomeTimelineActivityTransition)
        case invalidateListEntries
        case resetRealtimeState
        case contentSnapshot(HomeTimelineContentSnapshot)
        case relayStatusSnapshot(HomeTimelineRelayStatusSnapshot)
        case resetRuntimeSetup
        case configureRuntime(accountID: String, forceInstall: Bool)
    }

    private(set) var events: [Event] = []
    private(set) var materializationArguments:
        [AccountMaterializationArguments] = []
    private(set) var resetRealtimeKeyCounts: [Int] = []

    func cancel() {
        events.append(.cancelCurrentAccount)
    }

    func applyAccountContextTransition(
        _ transition: HomeTimelineAccountContextTransition
    ) {
        events.append(.accountContextTransition(transition))
    }

    func startRuntimeSession() {
        events.append(.startRuntimeSession)
    }

    func prepareHomeFeedDefinition(account: NostrAccount) {
        events.append(.prepareHomeFeedDefinition(account.pubkey))
    }

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
        materializationArguments.append(AccountMaterializationArguments(
            allowsRealtimeFollow: allowsRealtimeFollow,
            hasTransition: onTransition != nil
        ))
        events.append(.materializeEntries)
    }

    func applyRestoreProjectionAnchorIfPossible(account: NostrAccount) {
        events.append(.applyRestoreProjectionAnchor(account.pubkey))
    }

    func installProvisionalRuntimeBootstrapIfNeeded(account: NostrAccount) {
        events.append(.installProvisionalRuntimeBootstrap(account.pubkey))
    }

    func applyActivityIntent(_ intent: HomeTimelineActivityIntent) {
        switch intent {
        case .setPhase(let phase):
            events.append(.setPhase(phase))
        case .setRealtime(let isRealtime):
            events.append(.setRealtime(isRealtime))
        }
    }

    func publishRelayStatusChange() {
        events.append(.publishRelayStatusChange)
    }

    func applyPresentationTransition(
        _ transition: HomeTimelinePresentationTransition
    ) {
        events.append(.presentationTransition(
            changes: transition.changes.rawValue,
            didChangeReadState: transition.didChangeReadState
        ))
    }

    func clearPendingNewEvents() -> Bool {
        events.append(.clearPendingEvents)
        return true
    }

    func applyActivityTransition(
        _ transition: HomeTimelineActivityTransition
    ) {
        events.append(.activityTransition(transition))
    }

    func invalidateListEntries() {
        events.append(.invalidateListEntries)
    }

    func resetHomeTimelineRealtime(
        expecting runtimeKeys: Set<RuntimeSubscriptionKey>
    ) {
        resetRealtimeKeyCounts.append(runtimeKeys.count)
        events.append(.resetRealtimeState)
    }

    func applyContentSnapshot(_ snapshot: HomeTimelineContentSnapshot) {
        events.append(.contentSnapshot(snapshot))
    }

    func applyRelayStatusSnapshot(_ snapshot: HomeTimelineRelayStatusSnapshot) {
        events.append(.relayStatusSnapshot(snapshot))
    }

    func resetRuntimeSetup() {
        events.append(.resetRuntimeSetup)
    }

    func configureRelayRuntime(
        account: NostrAccount,
        forceInstall: Bool
    ) async {
        events.append(.configureRuntime(
            accountID: account.pubkey,
            forceInstall: forceInstall
        ))
    }
}
