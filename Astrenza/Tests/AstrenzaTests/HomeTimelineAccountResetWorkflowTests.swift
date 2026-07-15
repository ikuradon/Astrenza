import AstrenzaCore
import Testing
@testable import Astrenza

@Suite("Home timeline account reset workflow")
@MainActor
struct HomeTimelineAccountResetWorkflowTests {
    @Test("Reset input and every application handler preserve their values")
    func mapsResetInputAndApplicationEffects() {
        let fixtures = AccountResetWorkflowFixtures()
        let reset = AccountResetWorkflowCoordinatorSpy(
            fixtures: fixtures,
            emitsApplicationEffects: true,
            cancellationGeneration: 42
        )
        let shutdown = RuntimeShutdownWorkflowCoordinatorSpy(isTerminating: true)
        let probe = AccountResetWorkflowEffectProbe(account: fixtures.account)
        let workflow = HomeTimelineAccountResetWorkflow(
            resetCoordinator: reset,
            runtimeShutdownCoordinator: shutdown
        )

        workflow.reset(
            HomeTimelineAccountResetInput(
                readBoundaryWrite: fixtures.readBoundaryWrite,
                resolvedRelays: fixtures.resolvedRelays
            ),
            effects: probe.effects
        )

        #expect(workflow.isRuntimeTerminating)
        #expect(reset.readBoundaryWrite?.scopeID == fixtures.readBoundaryWrite.scopeID)
        #expect(reset.resolvedRelays == fixtures.resolvedRelays)
        #expect(probe.applicationEvents == [
            .applyPresentationTransition,
            .clearPendingEvents,
            .applyActivityTransition,
            .invalidateListEntries,
            .resetRealtimeState,
            .applyContentSnapshot,
            .applyRelayStatusSnapshot,
            .resetProjectionRestoreState,
            .publishRelayStatusChange,
            .applyAccountContextTransition(.clear)
        ])
        #expect(probe.presentationChanges == fixtures.presentationTransition.changes)
        #expect(
            probe.presentationDidChangeReadState ==
                fixtures.presentationTransition.didChangeReadState
        )
        #expect(probe.activityTransition == fixtures.activityTransition)
        #expect(probe.contentSnapshot == fixtures.contentSnapshot)
        #expect(probe.relayStatusSnapshot == fixtures.relayStatusSnapshot)
        #expect(shutdown.cancellationGenerations == [42])
    }

    @Test("Runtime restart commands route through stable async effects")
    func routesRuntimeRestartCommands() async throws {
        let fixtures = AccountResetWorkflowFixtures()
        let reset = AccountResetWorkflowCoordinatorSpy(
            fixtures: fixtures,
            cancellationGeneration: 7
        )
        let shutdown = RuntimeShutdownWorkflowCoordinatorSpy()
        let probe = AccountResetWorkflowEffectProbe(account: fixtures.account)
        let workflow = HomeTimelineAccountResetWorkflow(
            resetCoordinator: reset,
            runtimeShutdownCoordinator: shutdown
        )

        workflow.reset(
            HomeTimelineAccountResetInput(
                readBoundaryWrite: nil,
                resolvedRelays: []
            ),
            effects: probe.effects
        )

        let handlers = try #require(shutdown.handlers)
        #expect(handlers.currentAccount() == fixtures.account)
        await handlers.perform(.resetRuntimeState)
        await handlers.perform(.startRuntimeSession)
        await handlers.perform(.configureRuntime(
            account: fixtures.account,
            forceInstall: true
        ))
        #expect(probe.shutdownEvents == [
            .resetRuntimeState,
            .startRuntimeSession,
            .configureRuntime(fixtures.account, true)
        ])
    }
}

@MainActor
private final class AccountResetWorkflowCoordinatorSpy:
    HomeTimelineAccountResetCoordinating {
    private let fixtures: AccountResetWorkflowFixtures
    private let emitsApplicationEffects: Bool
    private let cancellationGeneration: UInt64?
    private(set) var readBoundaryWrite: HomeTimelineReadBoundaryWrite?
    private(set) var resolvedRelays: [String] = []

    init(
        fixtures: AccountResetWorkflowFixtures,
        emitsApplicationEffects: Bool = false,
        cancellationGeneration: UInt64? = nil
    ) {
        self.fixtures = fixtures
        self.emitsApplicationEffects = emitsApplicationEffects
        self.cancellationGeneration = cancellationGeneration
    }

    func reset(
        context: HomeTimelineAccountResetContext,
        handlers: HomeTimelineAccountResetHandlers
    ) {
        readBoundaryWrite = context.readBoundaryWrite
        resolvedRelays = context.resolvedRelays
        if emitsApplicationEffects {
            handlers.applyPresentationTransition(fixtures.presentationTransition)
            handlers.clearPendingEvents()
            handlers.applyActivityTransition(fixtures.activityTransition)
            handlers.invalidateListEntries()
            handlers.resetRealtimeState()
            handlers.applyContentSnapshot(fixtures.contentSnapshot)
            handlers.applyRelayStatusSnapshot(fixtures.relayStatusSnapshot)
            handlers.resetProjectionRestoreState()
            handlers.publishRelayStatusChange()
            handlers.applyAccountContextTransition(.clear)
        }
        if let cancellationGeneration {
            handlers.scheduleRuntimeShutdown(cancellationGeneration)
        }
    }
}

@MainActor
private final class RuntimeShutdownWorkflowCoordinatorSpy:
    HomeTimelineRuntimeShutdownCoordinating {
    var isTerminating: Bool
    private(set) var cancellationGenerations: [UInt64] = []
    private(set) var handlers: HomeTimelineRuntimeShutdownHandlers?

    init(isTerminating: Bool = false) {
        self.isTerminating = isTerminating
    }

    func schedule(
        cancellationGeneration: UInt64,
        handlers: HomeTimelineRuntimeShutdownHandlers
    ) -> Bool {
        cancellationGenerations.append(cancellationGeneration)
        self.handlers = handlers
        return true
    }
}

@MainActor
private final class AccountResetWorkflowEffectProbe {
    private let account: NostrAccount
    private(set) var applicationEvents: [AccountResetWorkflowApplicationEvent] = []
    private(set) var shutdownEvents: [AccountResetWorkflowShutdownEvent] = []
    private(set) var presentationChanges: HomeTimelinePresentationChanges?
    private(set) var presentationDidChangeReadState: Bool?
    private(set) var activityTransition: HomeTimelineActivityTransition?
    private(set) var contentSnapshot: HomeTimelineContentSnapshot?
    private(set) var relayStatusSnapshot: HomeTimelineRelayStatusSnapshot?

    init(account: NostrAccount) {
        self.account = account
    }

    var effects: HomeTimelineAccountResetEffects {
        HomeTimelineAccountResetEffects(
            application: applicationEffects,
            runtimeShutdown: shutdownEffects
        )
    }

    private var applicationEffects: HomeTimelineAccountResetAppEffects {
        HomeTimelineAccountResetAppEffects(
            applyPresentationTransition: { [self] transition in
                applicationEvents.append(.applyPresentationTransition)
                presentationChanges = transition.changes
                presentationDidChangeReadState = transition.didChangeReadState
            },
            clearPendingEvents: { [self] in
                applicationEvents.append(.clearPendingEvents)
            },
            applyActivityTransition: { [self] transition in
                applicationEvents.append(.applyActivityTransition)
                activityTransition = transition
            },
            invalidateListEntries: { [self] in
                applicationEvents.append(.invalidateListEntries)
            },
            resetRealtimeState: { [self] in
                applicationEvents.append(.resetRealtimeState)
            },
            applyContentSnapshot: { [self] snapshot in
                applicationEvents.append(.applyContentSnapshot)
                contentSnapshot = snapshot
            },
            applyRelayStatusSnapshot: { [self] snapshot in
                applicationEvents.append(.applyRelayStatusSnapshot)
                relayStatusSnapshot = snapshot
            },
            resetProjectionRestoreState: { [self] in
                applicationEvents.append(.resetProjectionRestoreState)
            },
            publishRelayStatusChange: { [self] in
                applicationEvents.append(.publishRelayStatusChange)
            },
            applyAccountContextTransition: { [self] transition in
                applicationEvents.append(.applyAccountContextTransition(transition))
            }
        )
    }

    private var shutdownEffects: HomeTimelineRuntimeShutdownEffects {
        HomeTimelineRuntimeShutdownEffects(
            currentAccount: { [self] in account },
            resetRuntimeState: { [self] in
                shutdownEvents.append(.resetRuntimeState)
            },
            startRuntimeSession: { [self] in
                shutdownEvents.append(.startRuntimeSession)
            },
            configureRuntime: { [self] account, forceInstall in
                shutdownEvents.append(.configureRuntime(account, forceInstall))
            }
        )
    }
}

private struct AccountResetWorkflowFixtures {
    let account = NostrAccount(
        pubkey: String(repeating: "a", count: 64),
        displayIdentifier: "workflow",
        readOnly: true
    )
    let readBoundaryWrite = HomeTimelineReadBoundaryWrite(
        scopeID: "account",
        feedID: "home",
        boundary: nil,
        updatedAt: 123
    )
    let resolvedRelays = ["wss://relay.one", "wss://relay.two"]
    let presentationTransition = HomeTimelinePresentationTransition(
        snapshot: HomeTimelinePresentationSnapshot(
            entries: [],
            filterStatus: TimelineFilterStatus(),
            materializedUnreadCount: 0,
            visibleUnreadBadgeCount: 0,
            resolvedContentRevision: 1,
            realtimeFollowSourceRevision: nil
        ),
        changes: [.entries],
        didChangeReadState: true
    )
    let activityTransition = HomeTimelineActivityTransition(
        snapshot: HomeTimelineActivitySnapshot(
            phase: .idle,
            isRefreshing: false,
            isLoadingOlder: false,
            isRealtime: false
        ),
        changes: [.phase]
    )
    let contentSnapshot = HomeTimelineContentSnapshot.initial
    let relayStatusSnapshot = HomeTimelineRelayStatusSnapshot(
        runtimeStates: [:],
        connectedRelayCount: 0,
        plannedRelayCount: 1
    )
}

private enum AccountResetWorkflowApplicationEvent: Equatable {
    case applyPresentationTransition
    case clearPendingEvents
    case applyActivityTransition
    case invalidateListEntries
    case resetRealtimeState
    case applyContentSnapshot
    case applyRelayStatusSnapshot
    case resetProjectionRestoreState
    case publishRelayStatusChange
    case applyAccountContextTransition(HomeTimelineAccountContextTransition)
}

private enum AccountResetWorkflowShutdownEvent: Equatable {
    case resetRuntimeState
    case startRuntimeSession
    case configureRuntime(NostrAccount, Bool)
}
