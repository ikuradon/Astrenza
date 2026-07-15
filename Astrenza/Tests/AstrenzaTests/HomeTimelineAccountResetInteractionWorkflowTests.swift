import AstrenzaCore
import Testing
@testable import Astrenza

@Suite("Home timeline account reset interaction workflow")
@MainActor
struct HomeTimelineAccountResetInteractionTests {
    @Test("Input, termination state, and current account cross the boundary")
    func routesInputAndDynamicEnvironment() throws {
        let fixture = AccountResetInteractionFixture(isRuntimeTerminating: true)

        fixture.workflow.reset(context: fixture.context)

        #expect(fixture.workflow.isRuntimeTerminating)
        let input = try #require(fixture.handler.inputs.first)
        #expect(
            input.readBoundaryWrite?.scopeID
                == fixture.readBoundaryWrite.scopeID
        )
        #expect(input.resolvedRelays == fixture.resolvedRelays)
        let effects = try #require(fixture.handler.effects)
        #expect(effects.runtimeShutdown.currentAccount() == fixture.account)

        fixture.probe.currentAccount = nil
        #expect(effects.runtimeShutdown.currentAccount() == nil)
    }

    @Test("Every reset and restart mutation uses one typed boundary")
    func routesEveryApplicationEffect() async throws {
        let fixture = AccountResetInteractionFixture()

        fixture.workflow.reset(context: fixture.context)
        let effects = try #require(fixture.handler.effects)
        let application = effects.application
        application.applyPresentationTransition(fixture.presentationTransition)
        application.clearPendingEvents()
        application.applyActivityTransition(fixture.activityTransition)
        application.invalidateListEntries()
        application.resetRealtimeState()
        application.applyContentSnapshot(fixture.contentSnapshot)
        application.applyRelayStatusSnapshot(fixture.relayStatusSnapshot)
        application.applyProjectionViewportTransition(.resetToNewest)
        application.publishRelayStatusChange()
        application.applyAccountContextTransition(.clear)
        await effects.runtimeShutdown.resetRuntimeState()
        await effects.runtimeShutdown.startRuntimeSession()
        await effects.runtimeShutdown.configureRuntime(fixture.account, true)

        #expect(fixture.probe.applicationEvents == [
            .applyPresentationTransition(
                changes: fixture.presentationTransition.changes,
                didChangeReadState:
                    fixture.presentationTransition.didChangeReadState,
                resolvedContentRevision:
                    fixture.presentationTransition.snapshot.resolvedContentRevision
            ),
            .clearPendingEvents,
            .applyActivityTransition(fixture.activityTransition),
            .invalidateListEntries,
            .resetRealtimeState,
            .applyContentSnapshot(fixture.contentSnapshot),
            .applyRelayStatusSnapshot(fixture.relayStatusSnapshot),
            .applyProjectionViewportTransition(.resetToNewest),
            .publishRelayStatusChange,
            .applyAccountContextTransition(.clear)
        ])
        #expect(fixture.probe.asyncActions == [
            .resetRuntimeState,
            .startRuntimeSession,
            .configureRuntime(
                account: fixture.account,
                forceInstall: true
            )
        ])
    }
}

@MainActor
private final class AccountResetInteractionHandlerSpy:
    HomeTimelineAccountResetHandling {
    let isRuntimeTerminating: Bool
    private(set) var inputs: [HomeTimelineAccountResetInput] = []
    private(set) var effects: HomeTimelineAccountResetEffects?

    init(isRuntimeTerminating: Bool) {
        self.isRuntimeTerminating = isRuntimeTerminating
    }

    func reset(
        _ input: HomeTimelineAccountResetInput,
        effects: HomeTimelineAccountResetEffects
    ) {
        inputs.append(input)
        self.effects = effects
    }
}

@MainActor
private final class AccountResetInteractionProbe {
    var currentAccount: NostrAccount?
    private(set) var applicationEvents: [ResetInteractionApplicationEvent] = []
    private(set) var asyncActions: [HomeTimelineAccountResetAsyncAction] = []

    init(currentAccount: NostrAccount?) {
        self.currentAccount = currentAccount
    }

    var effects: HomeAccountResetInteractionEffects {
        HomeAccountResetInteractionEffects(
            environment: HomeTimelineAccountResetEnvironment(
                currentAccount: { [self] in currentAccount }
            ),
            apply: { [self] action in
                record(action)
            },
            perform: { [self] action in
                asyncActions.append(action)
            }
        )
    }

    private func record(_ action: HomeTimelineAccountResetStoreAction) {
        switch action {
        case .applyPresentationTransition(let transition):
            applicationEvents.append(.applyPresentationTransition(
                changes: transition.changes,
                didChangeReadState: transition.didChangeReadState,
                resolvedContentRevision:
                    transition.snapshot.resolvedContentRevision
            ))
        case .clearPendingEvents:
            applicationEvents.append(.clearPendingEvents)
        case .applyActivityTransition(let transition):
            applicationEvents.append(.applyActivityTransition(transition))
        case .invalidateListEntries:
            applicationEvents.append(.invalidateListEntries)
        case .resetRealtimeState:
            applicationEvents.append(.resetRealtimeState)
        case .applyContentSnapshot(let snapshot):
            applicationEvents.append(.applyContentSnapshot(snapshot))
        case .applyRelayStatusSnapshot(let snapshot):
            applicationEvents.append(.applyRelayStatusSnapshot(snapshot))
        case .applyProjectionViewportTransition(let transition):
            applicationEvents.append(
                .applyProjectionViewportTransition(transition)
            )
        case .publishRelayStatusChange:
            applicationEvents.append(.publishRelayStatusChange)
        case .applyAccountContextTransition(let transition):
            applicationEvents.append(.applyAccountContextTransition(transition))
        }
    }
}

private enum ResetInteractionApplicationEvent: Equatable {
    case applyPresentationTransition(
        changes: HomeTimelinePresentationChanges,
        didChangeReadState: Bool,
        resolvedContentRevision: Int
    )
    case clearPendingEvents
    case applyActivityTransition(HomeTimelineActivityTransition)
    case invalidateListEntries
    case resetRealtimeState
    case applyContentSnapshot(HomeTimelineContentSnapshot)
    case applyRelayStatusSnapshot(HomeTimelineRelayStatusSnapshot)
    case applyProjectionViewportTransition(
        HomeTimelineProjectionViewportTransition
    )
    case publishRelayStatusChange
    case applyAccountContextTransition(HomeTimelineAccountContextTransition)
}

@MainActor
private struct AccountResetInteractionFixture {
    let account: NostrAccount
    let readBoundaryWrite: HomeTimelineReadBoundaryWrite
    let resolvedRelays = ["wss://one.example", "wss://two.example"]
    let presentationTransition: HomeTimelinePresentationTransition
    let activityTransition: HomeTimelineActivityTransition
    let contentSnapshot = HomeTimelineContentSnapshot.initial
    let relayStatusSnapshot = HomeTimelineRelayStatusSnapshot(
        runtimeStates: [:],
        connectedRelayCount: 0,
        plannedRelayCount: 2
    )
    let probe: AccountResetInteractionProbe
    let handler: AccountResetInteractionHandlerSpy
    let workflow: HomeAccountResetInteractionWorkflow

    init(isRuntimeTerminating: Bool = false) {
        let account = NostrAccount(
            pubkey: String(repeating: "d", count: 64),
            displayIdentifier: "reset",
            readOnly: true
        )
        let handler = AccountResetInteractionHandlerSpy(
            isRuntimeTerminating: isRuntimeTerminating
        )
        self.account = account
        readBoundaryWrite = HomeTimelineReadBoundaryWrite(
            scopeID: account.pubkey,
            feedID: "home",
            boundary: nil,
            updatedAt: 123
        )
        presentationTransition = HomeTimelinePresentationTransition(
            snapshot: HomeTimelinePresentationSnapshot(
                entries: [],
                filterStatus: TimelineFilterStatus(),
                materializedUnreadCount: 0,
                visibleUnreadBadgeCount: 0,
                resolvedContentRevision: 7,
                realtimeFollowSourceRevision: nil
            ),
            changes: [.entries, .resolvedContentRevision],
            didChangeReadState: true
        )
        activityTransition = HomeTimelineActivityTransition(
            snapshot: HomeTimelineActivitySnapshot(
                phase: .idle,
                isRefreshing: false,
                isLoadingOlder: false,
                isRealtime: false
            ),
            changes: [.phase, .realtime]
        )
        probe = AccountResetInteractionProbe(currentAccount: account)
        self.handler = handler
        workflow = HomeAccountResetInteractionWorkflow(
            accountReset: handler
        )
    }

    var context: HomeAccountResetInteractionContext {
        HomeAccountResetInteractionContext(
            state: HomeTimelineAccountResetInteractionState(
                readBoundaryWrite: readBoundaryWrite,
                resolvedRelays: resolvedRelays
            ),
            effects: probe.effects
        )
    }
}
