import AstrenzaCore
@testable import Astrenza

@MainActor
final class RefreshFixture {
    let account: NostrAccount
    let lifecycle: HomeTimelineLifecycleCoordinator
    let lifecycleToken: HomeTimelineLifecycleToken
    let activity: HomeTimelineActivityCoordinator
    let remoteInput: HomeTimelineRefreshRemoteInput
    let probe: RefreshProbe
    let workflow: HomeTimelineRefreshWorkflow

    var initialActivity: HomeTimelineActivitySnapshot {
        HomeTimelineActivitySnapshot(
            phase: .idle,
            isRefreshing: false,
            isLoadingOlder: false,
            isRealtime: false
        )
    }

    var loadedIdleActivity: HomeTimelineActivitySnapshot {
        HomeTimelineActivitySnapshot(
            phase: .loaded,
            isRefreshing: false,
            isLoadingOlder: false,
            isRealtime: false
        )
    }

    var beginActivityEvent: RefreshProbe.Event {
        activityEvent(
            phase: .idle,
            isRefreshing: true,
            changes: .refreshing
        )
    }

    var loadedActivityEvent: RefreshProbe.Event {
        activityEvent(
            phase: .loaded,
            isRefreshing: true,
            changes: .phase
        )
    }

    var endLoadedActivityEvent: RefreshProbe.Event {
        activityEvent(
            phase: .loaded,
            isRefreshing: false,
            changes: .refreshing
        )
    }

    var endIdleActivityEvent: RefreshProbe.Event {
        activityEvent(
            phase: .idle,
            isRefreshing: false,
            changes: .refreshing
        )
    }

    var configureRuntimeEvent: RefreshProbe.Event {
        .configureRuntime(account.pubkey)
    }

    var prepareRemoteInputEvent: RefreshProbe.Event {
        .prepareRemoteInput(account.pubkey)
    }

    var runtimeSuccessEvents: [RefreshProbe.Event] {
        [
            beginActivityEvent,
            configureRuntimeEvent,
            loadedActivityEvent,
            endLoadedActivityEvent
        ]
    }

    var remoteSuccessEvents: [RefreshProbe.Event] {
        [
            beginActivityEvent,
            prepareRemoteInputEvent,
            .loadRemote(
                accountID: account.pubkey,
                input: remoteInput,
                isCurrent: true
            ),
            .applyRemoteOutcome(
                probe.remoteOutcome,
                accountID: account.pubkey,
                lifecycle: lifecycleToken
            ),
            endIdleActivityEvent
        ]
    }

    init(
        remoteOutcome: HomeTimelineRemoteLoadOutcome? = nil,
        hasRemoteInput: Bool = true
    ) {
        let account = NostrAccount(
            pubkey: String(repeating: "b", count: 64),
            displayIdentifier: "account",
            readOnly: true
        )
        let lifecycle = HomeTimelineLifecycleCoordinator()
        let lifecycleToken = lifecycle.begin(accountID: account.pubkey)
        let activity = HomeTimelineActivityCoordinator()
        let remoteInput = HomeTimelineRefreshRemoteInput(
            current: NostrHomeTimelineState(
                relays: ["wss://relay.example"],
                followedPubkeys: [account.pubkey],
                noteEvents: [Self.event()],
                metadataEvents: []
            )
        )
        let probe = RefreshProbe(
            remoteOutcome: remoteOutcome ?? .loaded(remoteInput.current),
            remoteInput: hasRemoteInput ? remoteInput : nil
        )

        self.account = account
        self.lifecycle = lifecycle
        self.lifecycleToken = lifecycleToken
        self.activity = activity
        self.remoteInput = remoteInput
        self.probe = probe
        self.workflow = HomeTimelineRefreshWorkflow(
            remoteLoader: probe,
            activityCoordinator: activity,
            lifecycleCoordinator: lifecycle
        )
    }

    func run(
        hasTimelineEvents: Bool = true,
        hasRelayRuntime: Bool
    ) async {
        await workflow.refresh(
            HomeTimelineRefreshRequest(
                account: account,
                lifecycle: lifecycleToken,
                hasTimelineEvents: hasTimelineEvents,
                hasRelayRuntime: hasRelayRuntime
            ),
            handlers: probe.handlers()
        )
    }

    private func activityEvent(
        phase: NostrHomeTimelinePhase,
        isRefreshing: Bool,
        changes: HomeTimelineActivityChanges
    ) -> RefreshProbe.Event {
        .command(.applyActivityTransition(HomeTimelineActivityTransition(
            snapshot: HomeTimelineActivitySnapshot(
                phase: phase,
                isRefreshing: isRefreshing,
                isLoadingOlder: false,
                isRealtime: false
            ),
            changes: changes
        )))
    }

    private static func event() -> NostrEvent {
        NostrEvent(
            id: String(repeating: "1", count: 64),
            pubkey: String(repeating: "b", count: 64),
            createdAt: 100,
            kind: 1,
            tags: [],
            content: "refresh",
            sig: String(repeating: "0", count: 128)
        )
    }
}

@MainActor
final class RefreshProbe: HomeTimelineRefreshRemoteLoading {
    enum Event: Equatable {
        case command(HomeTimelineRefreshCommand)
        case prepareRemoteInput(String)
        case configureRuntime(String)
        case loadRemote(
            accountID: String,
            input: HomeTimelineRefreshRemoteInput,
            isCurrent: Bool
        )
        case applyRemoteOutcome(
            HomeTimelineRemoteLoadOutcome,
            accountID: String,
            lifecycle: HomeTimelineLifecycleToken
        )
    }

    let remoteOutcome: HomeTimelineRemoteLoadOutcome
    var beforeRuntimeReturn: (@MainActor () -> Void)?
    var beforeRemoteReturn: (@MainActor () -> Void)?
    private let remoteInput: HomeTimelineRefreshRemoteInput?
    private(set) var events: [Event] = []

    init(
        remoteOutcome: HomeTimelineRemoteLoadOutcome,
        remoteInput: HomeTimelineRefreshRemoteInput?
    ) {
        self.remoteOutcome = remoteOutcome
        self.remoteInput = remoteInput
    }

    func handlers() -> HomeTimelineRefreshHandlers {
        HomeTimelineRefreshHandlers(
            perform: { [weak self] command in
                self?.events.append(.command(command))
            },
            prepareRemoteInput: { [weak self] account in
                guard let self else { return nil }
                events.append(.prepareRemoteInput(account.pubkey))
                return remoteInput
            },
            configureRuntime: { [weak self] account in
                guard let self else { return }
                events.append(.configureRuntime(account.pubkey))
                beforeRuntimeReturn?()
            },
            applyRemoteOutcome: { [weak self] outcome, account, lifecycle in
                self?.events.append(.applyRemoteOutcome(
                    outcome,
                    accountID: account.pubkey,
                    lifecycle: lifecycle
                ))
            }
        )
    }

    func refreshState(
        account: NostrAccount,
        current: NostrHomeTimelineState,
        policy: NostrSyncPolicy,
        isCurrent: @escaping @MainActor @Sendable () -> Bool
    ) async -> HomeTimelineRemoteLoadOutcome {
        events.append(.loadRemote(
            accountID: account.pubkey,
            input: HomeTimelineRefreshRemoteInput(current: current),
            isCurrent: isCurrent()
        ))
        beforeRemoteReturn?()
        return remoteOutcome
    }
}
