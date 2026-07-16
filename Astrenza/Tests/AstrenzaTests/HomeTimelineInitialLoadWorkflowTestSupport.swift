import AstrenzaCore
@testable import Astrenza

@MainActor
final class InitialLoadFixture {
    let account: NostrAccount
    let lifecycle: HomeTimelineLifecycleCoordinator
    let lifecycleToken: HomeTimelineLifecycleToken
    let activity: HomeTimelineActivityCoordinator
    let probe: InitialLoadProbe
    let workflow: HomeTimelineInitialLoadWorkflow

    var idleActivity: HomeTimelineActivitySnapshot {
        activitySnapshot(phase: .idle)
    }

    var resolvingRelaysActivity: HomeTimelineActivitySnapshot {
        activitySnapshot(phase: .resolvingRelays)
    }

    var loadingActivity: HomeTimelineActivitySnapshot {
        activitySnapshot(phase: .loadingHome)
    }

    var installProvisionalEvent: InitialLoadProbe.Event {
        .command(.installProvisionalRuntimeBootstrap(account))
    }

    var configureRuntimeEvent: InitialLoadProbe.Event {
        .configureRuntime(account.pubkey)
    }

    var loadInitialEvent: InitialLoadProbe.Event {
        .loadInitial(accountID: account.pubkey, isCurrent: true)
    }

    var loadRuntimeBootstrapEvent: InitialLoadProbe.Event {
        .loadRuntimeBootstrap(accountID: account.pubkey, isCurrent: true)
    }

    var resolvingRelaysEvent: InitialLoadProbe.Event {
        phaseEvent(
            phase: .resolvingRelays,
            previousPhase: .idle
        )
    }

    var resolvingContactsEvent: InitialLoadProbe.Event {
        phaseEvent(
            phase: .resolvingContacts,
            previousPhase: .resolvingRelays
        )
    }

    var loadingEvent: InitialLoadProbe.Event {
        phaseEvent(
            phase: .loadingHome,
            previousPhase: .resolvingContacts
        )
    }

    var repeatedLoadingEvent: InitialLoadProbe.Event {
        .command(.applyActivityTransition(HomeTimelineActivityTransition(
            snapshot: loadingActivity,
            changes: []
        )))
    }

    var applyInitialOutcomeEvent: InitialLoadProbe.Event {
        .applyOutcome(
            probe.initialOutcome,
            operation: .initial,
            accountID: account.pubkey,
            lifecycle: lifecycleToken
        )
    }

    var applyFreshBootstrapOutcomeEvent: InitialLoadProbe.Event {
        bootstrapOutcomeEvent(hadCachedBootstrap: false)
    }

    var applyCachedBootstrapOutcomeEvent: InitialLoadProbe.Event {
        bootstrapOutcomeEvent(hadCachedBootstrap: true)
    }

    var nonRuntimeStageEvents: [InitialLoadProbe.Event] {
        [
            loadInitialEvent,
            resolvingRelaysEvent,
            resolvingContactsEvent,
            loadingEvent,
            repeatedLoadingEvent,
            applyInitialOutcomeEvent
        ]
    }

    init(
        hadCachedBootstrap: Bool = false,
        hasResolvedRelaysAfterProvisional: Bool = false,
        stages: [NostrHomeTimelineLoadStage] = [],
        callsDidFetch: Bool = false
    ) {
        let account = NostrAccount(
            pubkey: String(repeating: "c", count: 64),
            displayIdentifier: "account",
            readOnly: true
        )
        let lifecycle = HomeTimelineLifecycleCoordinator()
        let lifecycleToken = lifecycle.begin(accountID: account.pubkey)
        if hadCachedBootstrap {
            _ = lifecycle.setRuntimeBootstrapCompleted(
                true,
                for: lifecycleToken
            )
        }
        let activity = HomeTimelineActivityCoordinator()
        let state = NostrHomeTimelineState(
            relays: ["wss://relay.example"],
            followedPubkeys: [account.pubkey],
            noteEvents: [Self.event()],
            metadataEvents: []
        )
        let probe = InitialLoadProbe(
            initialOutcome: .loaded(state),
            bootstrapOutcome: .loaded(state),
            hasResolvedRelaysAfterProvisional: hasResolvedRelaysAfterProvisional,
            stages: stages,
            callsDidFetch: callsDidFetch
        )

        self.account = account
        self.lifecycle = lifecycle
        self.lifecycleToken = lifecycleToken
        self.activity = activity
        self.probe = probe
        self.workflow = HomeTimelineInitialLoadWorkflow(
            remoteLoader: probe,
            activityCoordinator: activity,
            lifecycleCoordinator: lifecycle
        )
    }

    func run(hasRelayRuntime: Bool) async {
        await workflow.load(
            HomeTimelineInitialLoadRequest(
                account: account,
                lifecycle: lifecycleToken,
                hasRelayRuntime: hasRelayRuntime
            ),
            handlers: probe.handlers()
        )
    }

    private func phaseEvent(
        phase: NostrHomeTimelinePhase,
        previousPhase: NostrHomeTimelinePhase
    ) -> InitialLoadProbe.Event {
        .command(.applyActivityTransition(HomeTimelineActivityTransition(
            snapshot: activitySnapshot(phase: phase),
            changes: phase == previousPhase ? [] : .phase
        )))
    }

    private func activitySnapshot(
        phase: NostrHomeTimelinePhase
    ) -> HomeTimelineActivitySnapshot {
        HomeTimelineActivitySnapshot(
            phase: phase,
            isRefreshing: false,
            isLoadingOlder: false,
            isRealtime: false
        )
    }

    private func bootstrapOutcomeEvent(
        hadCachedBootstrap: Bool
    ) -> InitialLoadProbe.Event {
        .applyOutcome(
            probe.bootstrapOutcome,
            operation: .runtimeBootstrap(
                hadCachedBootstrap: hadCachedBootstrap
            ),
            accountID: account.pubkey,
            lifecycle: lifecycleToken
        )
    }

    private static func event() -> NostrEvent {
        NostrEvent(
            id: String(repeating: "1", count: 64),
            pubkey: String(repeating: "c", count: 64),
            createdAt: 100,
            kind: 1,
            tags: [],
            content: "initial",
            sig: String(repeating: "0", count: 128)
        )
    }
}

@MainActor
final class InitialLoadProbe: HomeTimelineInitialLoadRemoteLoading {
    enum Event: Equatable {
        case command(HomeTimelineInitialLoadCommand)
        case queryResolvedRelays
        case configureRuntime(String)
        case loadInitial(accountID: String, isCurrent: Bool)
        case loadRuntimeBootstrap(accountID: String, isCurrent: Bool)
        case applyOutcome(
            HomeTimelineRemoteLoadOutcome,
            operation: HomeTimelineLoadOperation,
            accountID: String,
            lifecycle: HomeTimelineLifecycleToken
        )
    }

    let initialOutcome: HomeTimelineRemoteLoadOutcome
    let bootstrapOutcome: HomeTimelineRemoteLoadOutcome
    var beforeStageCallbacks: (@MainActor () -> Void)?
    var beforeRuntimeReturn: (@MainActor () -> Void)?
    private let hasResolvedRelaysAfterProvisional: Bool
    private let stages: [NostrHomeTimelineLoadStage]
    private let callsDidFetch: Bool
    private(set) var events: [Event] = []

    init(
        initialOutcome: HomeTimelineRemoteLoadOutcome,
        bootstrapOutcome: HomeTimelineRemoteLoadOutcome,
        hasResolvedRelaysAfterProvisional: Bool,
        stages: [NostrHomeTimelineLoadStage],
        callsDidFetch: Bool
    ) {
        self.initialOutcome = initialOutcome
        self.bootstrapOutcome = bootstrapOutcome
        self.hasResolvedRelaysAfterProvisional = hasResolvedRelaysAfterProvisional
        self.stages = stages
        self.callsDidFetch = callsDidFetch
    }

    func handlers() -> HomeTimelineInitialLoadHandlers {
        HomeTimelineInitialLoadHandlers(
            perform: { [weak self] command in
                self?.events.append(.command(command))
            },
            hasResolvedRelays: { [weak self] in
                guard let self else { return false }
                events.append(.queryResolvedRelays)
                return hasResolvedRelaysAfterProvisional
            },
            configureRuntime: { [weak self] account in
                guard let self else { return }
                events.append(.configureRuntime(account.pubkey))
                beforeRuntimeReturn?()
            },
            applyOutcome: { [weak self] outcome, operation, account, lifecycle in
                self?.events.append(.applyOutcome(
                    outcome,
                    operation: operation,
                    accountID: account.pubkey,
                    lifecycle: lifecycle
                ))
            }
        )
    }

    func loadInitialState(
        account: NostrAccount,
        policy: NostrSyncPolicy,
        isCurrent: @escaping @MainActor @Sendable () -> Bool,
        didReceiveStage: @escaping @MainActor @Sendable (
            NostrHomeTimelineLoadStage
        ) -> Void,
        didFetch: @escaping @MainActor @Sendable () -> Void
    ) async -> HomeTimelineRemoteLoadOutcome {
        events.append(.loadInitial(
            accountID: account.pubkey,
            isCurrent: isCurrent()
        ))
        runCallbacks(
            didReceiveStage: didReceiveStage,
            didFetch: didFetch
        )
        return initialOutcome
    }

    func loadRuntimeBootstrapState(
        account: NostrAccount,
        policy: NostrSyncPolicy,
        isCurrent: @escaping @MainActor @Sendable () -> Bool,
        didReceiveStage: @escaping @MainActor @Sendable (
            NostrHomeTimelineLoadStage
        ) -> Void,
        didFetch: @escaping @MainActor @Sendable () -> Void
    ) async -> HomeTimelineRemoteLoadOutcome {
        events.append(.loadRuntimeBootstrap(
            accountID: account.pubkey,
            isCurrent: isCurrent()
        ))
        runCallbacks(
            didReceiveStage: didReceiveStage,
            didFetch: didFetch
        )
        return bootstrapOutcome
    }

    private func runCallbacks(
        didReceiveStage: @MainActor @Sendable (
            NostrHomeTimelineLoadStage
        ) -> Void,
        didFetch: @MainActor @Sendable () -> Void
    ) {
        beforeStageCallbacks?()
        for stage in stages {
            didReceiveStage(stage)
        }
        if callsDidFetch {
            didFetch()
        }
    }
}
