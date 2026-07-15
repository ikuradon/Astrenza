import AstrenzaCore
import Testing
@testable import Astrenza

@Suite("Home timeline account start coordinator")
@MainActor
struct HomeTimelineAccountStartCoordinatorTests {
    @Test("Starting the current account only resumes runtime and outbox work")
    func resumesCurrentAccount() {
        let account = HomeTimelineAccountStartProbe.account()
        let probe = HomeTimelineAccountStartProbe(currentAccountID: account.pubkey)

        probe.start(account: account, hasRelayRuntime: true)

        #expect(probe.events == [
            .command(.startRuntimeSession),
            .command(.activateOutbox(accountID: account.pubkey))
        ])
        #expect(probe.lifecycle.currentToken == nil)
    }

    @Test("A fresh account restores state before selecting its projection and initial phase")
    func startsFreshAccountInOrder() async {
        let account = HomeTimelineAccountStartProbe.account()
        let probe = HomeTimelineAccountStartProbe(
            cachedSnapshotFound: false,
            restoredViewport: nil
        )

        probe.start(account: account, hasRelayRuntime: false)

        let lifecycle = probe.lifecycle.token(accountID: account.pubkey)
        #expect(probe.events == [
            .beginLifecycle(account.pubkey),
            .resolveSyncPolicy(account.pubkey, fallback: probe.fallbackSyncPolicy),
            .command(.setAccount(account, syncPolicy: probe.resolvedSyncPolicy)),
            .scheduleLoad(lifecycle),
            .command(.activateOutbox(accountID: account.pubkey))
        ])
        #expect(probe.accountID == account.pubkey)
        #expect(probe.syncPolicy == probe.resolvedSyncPolicy)
        #expect(probe.lifecycle.scheduledLoadCount == 1)

        await probe.lifecycle.runScheduledLoad()

        #expect(probe.events == [
            .beginLifecycle(account.pubkey),
            .resolveSyncPolicy(account.pubkey, fallback: probe.fallbackSyncPolicy),
            .command(.setAccount(account, syncPolicy: probe.resolvedSyncPolicy)),
            .scheduleLoad(lifecycle),
            .command(.activateOutbox(accountID: account.pubkey)),
            .restoreCachedSnapshot(account),
            .setRuntimeBootstrapCompleted(false, lifecycle),
            .command(.prepareHomeFeedDefinition(account)),
            .restoreViewport(account.pubkey),
            .command(.reloadNewestProjectionWindow(account)),
            .command(.materializeEntries),
            .command(.installProvisionalRuntimeBootstrap(account)),
            .command(.setPhase(.resolvingRelays)),
            .waitForCachedPresentation,
            .restoreCachedReadState(account),
            .command(.startRuntimeSession)
        ])
        #expect(probe.loadedAccount == account)
        #expect(probe.loadedLifecycle == lifecycle)
    }

    @Test("An account switch cancels first and restores the persisted viewport anchor")
    func switchesAccountAndRestoresViewport() async {
        let account = HomeTimelineAccountStartProbe.account()
        let viewport = HomeTimelineRestoredViewport(anchorEventID: "restore-anchor")
        let probe = HomeTimelineAccountStartProbe(
            currentAccountID: String(repeating: "b", count: 64),
            cachedSnapshotFound: true,
            restoredSnapshotHasEntries: true,
            restoredSnapshotHasRelays: true,
            restoredViewport: viewport
        )

        probe.start(account: account, hasRelayRuntime: true)

        let lifecycle = probe.lifecycle.token(accountID: account.pubkey)
        #expect(probe.events == [
            .command(.cancelCurrentAccount),
            .beginLifecycle(account.pubkey),
            .resolveSyncPolicy(account.pubkey, fallback: probe.fallbackSyncPolicy),
            .command(.setAccount(account, syncPolicy: probe.resolvedSyncPolicy)),
            .scheduleLoad(lifecycle),
            .command(.activateOutbox(accountID: account.pubkey))
        ])

        await probe.lifecycle.runScheduledLoad()

        #expect(probe.events == [
            .command(.cancelCurrentAccount),
            .beginLifecycle(account.pubkey),
            .resolveSyncPolicy(account.pubkey, fallback: probe.fallbackSyncPolicy),
            .command(.setAccount(account, syncPolicy: probe.resolvedSyncPolicy)),
            .scheduleLoad(lifecycle),
            .command(.activateOutbox(accountID: account.pubkey)),
            .restoreCachedSnapshot(account),
            .setRuntimeBootstrapCompleted(true, lifecycle),
            .command(.prepareHomeFeedDefinition(account)),
            .restoreViewport(account.pubkey),
            .command(.applyRestoredViewport(viewport)),
            .command(.applyRestoreProjectionAnchor(account)),
            .command(.installProvisionalRuntimeBootstrap(account)),
            .command(.setPhase(.loaded)),
            .waitForCachedPresentation,
            .restoreCachedReadState(account),
            .command(.startRuntimeSession)
        ])
        #expect(probe.restoreProjectionAnchorEventID == viewport.anchorEventID)
        #expect(probe.lifecycle.scheduledLoadCount == 1)
    }

    @Test("Cached offline entries preserve the current phase")
    func cachedOfflineEntriesDoNotReplacePhase() async {
        let account = HomeTimelineAccountStartProbe.account()
        let probe = HomeTimelineAccountStartProbe(
            cachedSnapshotFound: true,
            restoredSnapshotHasEntries: true,
            restoredSnapshotHasRelays: true
        )

        probe.start(account: account, hasRelayRuntime: false)
        await probe.lifecycle.runScheduledLoad()

        #expect(!probe.commands.contains { command in
            if case .setPhase = command { return true }
            return false
        })
        #expect(probe.lifecycle.scheduledLoadCount == 1)
    }

    @Test("A stale lifecycle cannot finish startup after cache restoration")
    func staleLifecycleDoesNotFinishStartup() async {
        let account = HomeTimelineAccountStartProbe.account()
        let probe = HomeTimelineAccountStartProbe(cachedSnapshotFound: true)

        probe.start(account: account, hasRelayRuntime: true)
        probe.lifecycle.invalidateCurrentToken()
        await probe.lifecycle.runScheduledLoad()

        let lifecycle = probe.lifecycle.token(accountID: account.pubkey)
        #expect(probe.events == [
            .beginLifecycle(account.pubkey),
            .resolveSyncPolicy(account.pubkey, fallback: probe.fallbackSyncPolicy),
            .command(.setAccount(account, syncPolicy: probe.resolvedSyncPolicy)),
            .scheduleLoad(lifecycle),
            .command(.activateOutbox(accountID: account.pubkey)),
            .restoreCachedSnapshot(account)
        ])
        #expect(probe.loadedAccount == nil)
    }

    @Test("A stale lifecycle cannot start runtime after read state restoration")
    func staleLifecycleAfterReadStateDoesNotStartRuntime() async {
        let account = HomeTimelineAccountStartProbe.account()
        let probe = HomeTimelineAccountStartProbe(
            invalidateDuringReadStateRestore: true
        )

        probe.start(account: account, hasRelayRuntime: true)
        await probe.lifecycle.runScheduledLoad()

        #expect(probe.events.contains(.waitForCachedPresentation))
        #expect(probe.events.contains(.restoreCachedReadState(account)))
        #expect(!probe.commands.contains(.startRuntimeSession))
        #expect(probe.loadedAccount == nil)
    }
}

@MainActor
private final class HomeTimelineAccountStartProbe {
    enum Event: Equatable {
        case beginLifecycle(String)
        case resolveSyncPolicy(String, fallback: NostrSyncPolicy)
        case command(HomeTimelineAccountStartCommand)
        case restoreCachedSnapshot(NostrAccount)
        case setRuntimeBootstrapCompleted(Bool, HomeTimelineLifecycleToken)
        case restoreViewport(String)
        case waitForCachedPresentation
        case restoreCachedReadState(NostrAccount)
        case scheduleLoad(HomeTimelineLifecycleToken)
    }

    let fallbackSyncPolicy = NostrSyncPolicy.default(networkType: .wifi)
    let resolvedSyncPolicy = NostrSyncPolicy.default(
        networkType: .cellular,
        lowPowerMode: true
    )
    let lifecycle: HomeTimelineAccountStartLifecycleProbe

    private(set) var accountID: String?
    private(set) var syncPolicy: NostrSyncPolicy
    private(set) var restoreProjectionAnchorEventID: String?
    private(set) var hasEntries: Bool
    private(set) var hasResolvedRelays: Bool
    private(set) var events: [Event] = []
    private(set) var loadedAccount: NostrAccount?
    private(set) var loadedLifecycle: HomeTimelineLifecycleToken?

    private var coordinator: HomeTimelineAccountStartCoordinator?
    private let cachedSnapshotFound: Bool
    private let restoredSnapshotHasEntries: Bool
    private let restoredSnapshotHasRelays: Bool
    private let viewport: HomeTimelineRestoredViewport?
    private let invalidateDuringReadStateRestore: Bool

    init(
        currentAccountID: String? = nil,
        cachedSnapshotFound: Bool = false,
        restoredSnapshotHasEntries: Bool = false,
        restoredSnapshotHasRelays: Bool = false,
        restoredViewport: HomeTimelineRestoredViewport? = nil,
        invalidateDuringReadStateRestore: Bool = false
    ) {
        accountID = currentAccountID
        syncPolicy = fallbackSyncPolicy
        restoreProjectionAnchorEventID = nil
        hasEntries = false
        hasResolvedRelays = false
        self.cachedSnapshotFound = cachedSnapshotFound
        self.restoredSnapshotHasEntries = restoredSnapshotHasEntries
        self.restoredSnapshotHasRelays = restoredSnapshotHasRelays
        viewport = restoredViewport
        self.invalidateDuringReadStateRestore = invalidateDuringReadStateRestore
        lifecycle = HomeTimelineAccountStartLifecycleProbe()
        lifecycle.record = { [weak self] event in
            self?.events.append(event)
        }
    }

    var commands: [HomeTimelineAccountStartCommand] {
        events.compactMap { event in
            guard case .command(let command) = event else { return nil }
            return command
        }
    }

    func start(account: NostrAccount, hasRelayRuntime: Bool) {
        if coordinator == nil {
            coordinator = HomeTimelineAccountStartCoordinator(
                lifecycleCoordinator: lifecycle,
                resolveSyncPolicy: { [weak self] accountID, fallback in
                    guard let self else { return fallback }
                    events.append(.resolveSyncPolicy(accountID, fallback: fallback))
                    return resolvedSyncPolicy
                }
            )
        }
        coordinator?.start(
            HomeTimelineAccountStartRequest(
                account: account,
                hasRelayRuntime: hasRelayRuntime
            ),
            handlers: handlers
        )
    }

    var handlers: HomeTimelineAccountStartHandlers {
        HomeTimelineAccountStartHandlers(
            state: { [unowned self] in state },
            perform: { [weak self] command in
                self?.apply(command)
            },
            restoreCachedSnapshot: { [weak self] account in
                guard let self else { return false }
                events.append(.restoreCachedSnapshot(account))
                hasEntries = restoredSnapshotHasEntries
                hasResolvedRelays = restoredSnapshotHasRelays
                return cachedSnapshotFound
            },
            restoredViewport: { [weak self] accountID in
                guard let self else { return nil }
                events.append(.restoreViewport(accountID))
                return viewport
            },
            waitForCachedPresentation: { [weak self] in
                self?.events.append(.waitForCachedPresentation)
            },
            restoreCachedReadState: { [weak self] account in
                guard let self else { return }
                events.append(.restoreCachedReadState(account))
                if invalidateDuringReadStateRestore {
                    lifecycle.invalidateCurrentToken()
                }
            },
            load: { [weak self] account, lifecycle in
                self?.loadedAccount = account
                self?.loadedLifecycle = lifecycle
            }
        )
    }

    private var state: HomeTimelineAccountStartState {
        HomeTimelineAccountStartState(
            accountID: accountID,
            syncPolicy: syncPolicy,
            restoreProjectionAnchorEventID: restoreProjectionAnchorEventID,
            hasEntries: hasEntries,
            hasResolvedRelays: hasResolvedRelays
        )
    }

    private func apply(_ command: HomeTimelineAccountStartCommand) {
        events.append(.command(command))
        switch command {
        case .cancelCurrentAccount:
            accountID = nil
            restoreProjectionAnchorEventID = nil
            hasEntries = false
            hasResolvedRelays = false
        case .setAccount(let account, let syncPolicy):
            accountID = account.pubkey
            self.syncPolicy = syncPolicy
        case .applyRestoredViewport(let viewport):
            restoreProjectionAnchorEventID = viewport.anchorEventID
        case .startRuntimeSession,
             .prepareHomeFeedDefinition,
             .reloadNewestProjectionWindow,
             .materializeEntries,
             .applyRestoreProjectionAnchor,
             .installProvisionalRuntimeBootstrap,
             .setPhase,
             .activateOutbox:
            break
        }
    }

    static func account() -> NostrAccount {
        NostrAccount(
            pubkey: String(repeating: "a", count: 64),
            displayIdentifier: "npub-test",
            readOnly: true
        )
    }
}

@MainActor
private final class HomeTimelineAccountStartLifecycleProbe:
    HomeTimelineAccountLifecycleCoordinating {
    var record: ((HomeTimelineAccountStartProbe.Event) -> Void)?

    private(set) var currentToken: HomeTimelineLifecycleToken?
    private(set) var hasCompletedRuntimeBootstrap = false
    private(set) var scheduledLoadCount = 0
    private var scheduledLoad: HomeTimelineAccountLoadOperation?

    func token(accountID: String) -> HomeTimelineLifecycleToken {
        HomeTimelineLifecycleToken(accountID: accountID, generation: 7)
    }

    func begin(accountID: String) -> HomeTimelineLifecycleToken {
        let token = token(accountID: accountID)
        currentToken = token
        hasCompletedRuntimeBootstrap = false
        record?(.beginLifecycle(accountID))
        return token
    }

    func isCurrent(_ token: HomeTimelineLifecycleToken) -> Bool {
        currentToken == token
    }

    func setRuntimeBootstrapCompleted(
        _ isCompleted: Bool,
        for token: HomeTimelineLifecycleToken
    ) -> Bool {
        record?(.setRuntimeBootstrapCompleted(isCompleted, token))
        guard currentToken == token else { return false }
        hasCompletedRuntimeBootstrap = isCompleted
        return true
    }

    func startLoad(
        for token: HomeTimelineLifecycleToken,
        operation: @escaping HomeTimelineAccountLoadOperation
    ) {
        scheduledLoadCount += 1
        scheduledLoad = operation
        record?(.scheduleLoad(token))
    }

    func runScheduledLoad() async {
        guard let scheduledLoad else { return }
        await scheduledLoad()
    }

    func invalidateCurrentToken() {
        currentToken = nil
    }
}
