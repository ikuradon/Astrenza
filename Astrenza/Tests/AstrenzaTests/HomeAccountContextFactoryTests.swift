import AstrenzaCore
import Testing
@testable import Astrenza

@Suite("Home account context factory")
@MainActor
struct HomeAccountContextFactoryTests {
    @Test("Start context projects live state without reading reset boundary")
    func startContextUsesLiveStateOnly() {
        let fixture = AccountContextFactoryFixture()
        let context = fixture.factory.startContext()

        #expect(context.state == HomeTimelineAccountStartInteractionState(
            hasRelayRuntime: true
        ))
        #expect(context.effects.environment.state() ==
            HomeTimelineAccountStartStoreState(
                accountID: fixture.account.pubkey,
                syncPolicy: fixture.syncPolicy,
                restoreProjectionAnchorEventID: "anchor",
                hasEntries: true,
                hasResolvedRelays: true
            ))
        #expect(fixture.probe.readBoundaryCount == 0)

        fixture.probe.snapshot = fixture.replacementSnapshot
        #expect(context.effects.environment.state() ==
            HomeTimelineAccountStartStoreState(
                accountID: fixture.replacementAccount.pubkey,
                syncPolicy: .default(networkType: .wifi),
                restoreProjectionAnchorEventID: nil,
                hasEntries: false,
                hasResolvedRelays: false
            ))
        #expect(fixture.probe.readBoundaryCount == 0)
    }

    @Test("Reset context captures boundary while current account stays live")
    func resetContextUsesBoundaryAndLiveAccount() {
        let fixture = AccountContextFactoryFixture()
        let context = fixture.factory.resetContext()

        #expect(
            context.state.readBoundaryWrite?.scopeID ==
                fixture.readBoundaryWrite.scopeID
        )
        #expect(context.state.resolvedRelays == fixture.resolvedRelays)
        #expect(fixture.probe.readBoundaryCount == 1)
        #expect(
            context.effects.environment.currentAccount() == fixture.account
        )

        fixture.probe.snapshot = fixture.replacementSnapshot
        #expect(
            context.effects.environment.currentAccount() ==
                fixture.replacementAccount
        )
        fixture.probe.snapshot = nil
        #expect(context.effects.environment.currentAccount() == nil)
    }

    @Test("Start and reset dependencies route through injected effects")
    func routesLifecycleEffects() async {
        let fixture = AccountContextFactoryFixture()
        let start = fixture.factory.startContext()
        let reset = fixture.factory.resetContext()
        let request = fixture.loadRequest

        #expect(await start.effects.environment.restoreCachedSnapshot(
            fixture.account
        ))
        #expect(
            start.effects.environment.restoredViewport(
                fixture.account.pubkey
            ) == fixture.restoredViewport
        )
        await start.effects.environment.waitForCachedPresentation()
        await start.effects.environment.restoreCachedReadState(
            fixture.account
        )
        start.effects.apply(.account(.startRuntimeSession))
        await start.effects.load(request)
        reset.effects.apply(.clearPendingEvents)
        await reset.effects.perform(.resetRuntimeState)

        #expect(fixture.probe.dependencies == [
            .restoreCachedSnapshot(fixture.account),
            .restoreViewport(fixture.account.pubkey),
            .waitForCachedPresentation,
            .restoreCachedReadState(fixture.account),
            .load(request)
        ])
        #expect(fixture.probe.startActions == [
            .account(.startRuntimeSession)
        ])
        #expect(fixture.probe.resetEvents == [.clearPendingEvents])
        #expect(fixture.probe.resetAsyncActions == [.resetRuntimeState])
    }
}

private enum AccountContextDependency: Equatable, Sendable {
    case restoreCachedSnapshot(NostrAccount)
    case restoreViewport(String)
    case waitForCachedPresentation
    case restoreCachedReadState(NostrAccount)
    case load(HomeTimelineAccountStartLoadRequest)
}

private enum AccountContextResetEvent: Equatable {
    case clearPendingEvents
    case other
}

@MainActor
private final class AccountContextFactoryProbe {
    var snapshot: HomeAccountLifecycleSnapshot?
    let readBoundaryWrite: HomeTimelineReadBoundaryWrite
    let restoredViewport: HomeTimelineRestoredViewport
    private(set) var readBoundaryCount = 0
    private(set) var dependencies: [AccountContextDependency] = []
    private(set) var startActions: [HomeTimelineAccountStartStoreAction] = []
    private(set) var resetEvents: [AccountContextResetEvent] = []
    private(set) var resetAsyncActions:
        [HomeTimelineAccountResetAsyncAction] = []

    init(
        snapshot: HomeAccountLifecycleSnapshot,
        readBoundaryWrite: HomeTimelineReadBoundaryWrite,
        restoredViewport: HomeTimelineRestoredViewport
    ) {
        self.snapshot = snapshot
        self.readBoundaryWrite = readBoundaryWrite
        self.restoredViewport = restoredViewport
    }

    var environment: HomeAccountLifecycleEnvironment {
        HomeAccountLifecycleEnvironment(
            snapshot: { [self] in snapshot },
            readBoundaryWrite: { [self] in
                readBoundaryCount += 1
                return readBoundaryWrite
            },
            restoreCachedSnapshot: { [self] account in
                dependencies.append(.restoreCachedSnapshot(account))
                return true
            },
            restoredViewport: { [self] accountID in
                dependencies.append(.restoreViewport(accountID))
                return restoredViewport
            },
            waitForCachedPresentation: { [self] in
                dependencies.append(.waitForCachedPresentation)
            },
            restoreCachedReadState: { [self] account in
                dependencies.append(.restoreCachedReadState(account))
            },
            applyStart: { [self] action in
                startActions.append(action)
            },
            load: { [self] request in
                dependencies.append(.load(request))
            },
            applyReset: { [self] action in
                resetEvents.append(Self.resetEvent(for: action))
            },
            performReset: { [self] action in
                resetAsyncActions.append(action)
            }
        )
    }

    private static func resetEvent(
        for action: HomeTimelineAccountResetStoreAction
    ) -> AccountContextResetEvent {
        switch action {
        case .clearPendingEvents:
            .clearPendingEvents
        default:
            .other
        }
    }
}

@MainActor
private struct AccountContextFactoryFixture {
    let account: NostrAccount
    let replacementAccount: NostrAccount
    let syncPolicy: NostrSyncPolicy
    let resolvedRelays = ["wss://one.example", "wss://two.example"]
    let readBoundaryWrite: HomeTimelineReadBoundaryWrite
    let restoredViewport = HomeTimelineRestoredViewport(
        anchorEventID: "restored"
    )
    let probe: AccountContextFactoryProbe

    init() {
        let account = NostrAccount(
            pubkey: String(repeating: "a", count: 64),
            displayIdentifier: "account-context",
            readOnly: true
        )
        let replacement = NostrAccount(
            pubkey: String(repeating: "b", count: 64),
            displayIdentifier: "replacement",
            readOnly: true
        )
        let syncPolicy = NostrSyncPolicy.default(
            networkType: .cellular,
            lowPowerMode: true
        )
        let readBoundaryWrite = HomeTimelineReadBoundaryWrite(
            scopeID: account.pubkey,
            feedID: "home",
            boundary: nil,
            updatedAt: 100
        )
        self.account = account
        replacementAccount = replacement
        self.syncPolicy = syncPolicy
        self.readBoundaryWrite = readBoundaryWrite
        probe = AccountContextFactoryProbe(
            snapshot: HomeAccountLifecycleSnapshot(
                account: account,
                syncPolicy: syncPolicy,
                restoreProjectionAnchorEventID: "anchor",
                hasEntries: true,
                resolvedRelays: resolvedRelays,
                hasRelayRuntime: true
            ),
            readBoundaryWrite: readBoundaryWrite,
            restoredViewport: restoredViewport
        )
    }

    var factory: HomeAccountContextFactory {
        HomeAccountContextFactory(environment: probe.environment)
    }

    var replacementSnapshot: HomeAccountLifecycleSnapshot {
        HomeAccountLifecycleSnapshot(
            account: replacementAccount,
            syncPolicy: .default(networkType: .wifi),
            restoreProjectionAnchorEventID: nil,
            hasEntries: false,
            resolvedRelays: [],
            hasRelayRuntime: false
        )
    }

    var loadRequest: HomeTimelineAccountStartLoadRequest {
        HomeTimelineAccountStartLoadRequest(
            account: account,
            lifecycle: HomeTimelineLifecycleToken(
                accountID: account.pubkey,
                generation: 7
            )
        )
    }
}
