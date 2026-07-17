import AstrenzaCore
import Foundation
@testable import Astrenza

@MainActor
final class OlderPageFixture {
    let account: NostrAccount
    let lifecycle: HomeTimelineLifecycleCoordinator
    let lifecycleToken: HomeTimelineLifecycleToken
    let activity: HomeTimelineActivityCoordinator
    let remoteInput: HomeTimelineOlderPageRemoteInput
    let probe: OlderPageProbe
    let workflow: HomeTimelineOlderPageWorkflow

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

    var beginActivityEvent: OlderPageProbe.Event {
        activityEvent(
            phase: .idle,
            isLoadingOlder: true,
            changes: .loadingOlder
        )
    }

    var loadedActivityEvent: OlderPageProbe.Event {
        activityEvent(
            phase: .loaded,
            isLoadingOlder: true,
            changes: .phase
        )
    }

    var endLoadedActivityEvent: OlderPageProbe.Event {
        activityEvent(
            phase: .loaded,
            isLoadingOlder: false,
            changes: .loadingOlder
        )
    }

    var endIdleActivityEvent: OlderPageProbe.Event {
        activityEvent(
            phase: .idle,
            isLoadingOlder: false,
            changes: .loadingOlder
        )
    }

    var runtimeRequestEvent: OlderPageProbe.Event {
        .requestOlder(account.pubkey)
    }

    var prepareRemoteInputEvent: OlderPageProbe.Event {
        .prepareRemoteInput(account.pubkey)
    }

    var runtimeSuccessEvents: [OlderPageProbe.Event] {
        [
            beginActivityEvent,
            runtimeRequestEvent,
            loadedActivityEvent,
            endLoadedActivityEvent
        ]
    }

    var remoteSuccessEvents: [OlderPageProbe.Event] {
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
        runtimeOutcome: HomeTimelineBackwardRequestOutcome? = nil,
        remoteOutcome: HomeTimelineRemoteLoadOutcome = .cancelled,
        hasRemoteInput: Bool = true
    ) {
        let account = NostrAccount(
            pubkey: String(repeating: "a", count: 64),
            displayIdentifier: "account",
            readOnly: true
        )
        let lifecycle = HomeTimelineLifecycleCoordinator()
        let lifecycleToken = lifecycle.begin(accountID: account.pubkey)
        let activity = HomeTimelineActivityCoordinator()
        let currentEvent = Self.event(idCharacter: "1", createdAt: 100)
        let backfillEvent = Self.event(idCharacter: "2", createdAt: 50)
        let remoteInput = HomeTimelineOlderPageRemoteInput(
            current: NostrHomeTimelineState(
                relays: ["wss://relay.example"],
                followedPubkeys: [account.pubkey],
                noteEvents: [currentEvent],
                metadataEvents: []
            ),
            localBackfillEvents: [backfillEvent]
        )
        let definition = NostrFeedDefinitionRecord(
            feedID: "feed:home:\(account.pubkey)",
            accountID: account.pubkey,
            kind: "home",
            specificationJSON: Data(),
            specificationHash: "older-page",
            revision: 1,
            createdAt: 100,
            updatedAt: 100
        )
        let probe = OlderPageProbe(
            runtimeOutcome: runtimeOutcome ?? .completed(definition),
            remoteOutcome: remoteOutcome,
            remoteInput: hasRemoteInput ? remoteInput : nil
        )

        self.account = account
        self.lifecycle = lifecycle
        self.lifecycleToken = lifecycleToken
        self.activity = activity
        self.remoteInput = remoteInput
        self.probe = probe
        self.workflow = HomeTimelineOlderPageWorkflow(
            requester: probe,
            remoteLoader: probe,
            activityCoordinator: activity,
            lifecycleCoordinator: lifecycle
        )
    }

    func run(hasRelayRuntime: Bool) async {
        await workflow.load(
            HomeTimelineOlderPageRequest(
                account: account,
                lifecycle: lifecycleToken,
                hasRelayRuntime: hasRelayRuntime
            ),
            handlers: probe.handlers()
        )
    }

    private func activityEvent(
        phase: NostrHomeTimelinePhase,
        isLoadingOlder: Bool,
        changes: HomeTimelineActivityChanges
    ) -> OlderPageProbe.Event {
        .command(.applyActivityTransition(HomeTimelineActivityTransition(
            snapshot: HomeTimelineActivitySnapshot(
                phase: phase,
                isRefreshing: false,
                isLoadingOlder: isLoadingOlder,
                isRealtime: false
            ),
            changes: changes
        )))
    }

    private static func event(
        idCharacter: Character,
        createdAt: Int
    ) -> NostrEvent {
        NostrEvent(
            id: String(repeating: String(idCharacter), count: 64),
            pubkey: String(repeating: "a", count: 64),
            createdAt: createdAt,
            kind: 1,
            tags: [],
            content: String(idCharacter),
            sig: String(repeating: "0", count: 128)
        )
    }
}

@MainActor
final class OlderPageProbe:
    HomeTimelineOlderPageRequesting,
    HomeTimelineOlderPageRemoteLoading {
    enum Event: Equatable {
        case command(HomeTimelineOlderPageCommand)
        case requestOlder(String)
        case prepareRemoteInput(String)
        case loadRemote(
            accountID: String,
            input: HomeTimelineOlderPageRemoteInput,
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
    private let runtimeOutcome: HomeTimelineBackwardRequestOutcome
    private let remoteInput: HomeTimelineOlderPageRemoteInput?
    private(set) var events: [Event] = []

    init(
        runtimeOutcome: HomeTimelineBackwardRequestOutcome,
        remoteOutcome: HomeTimelineRemoteLoadOutcome,
        remoteInput: HomeTimelineOlderPageRemoteInput?
    ) {
        self.runtimeOutcome = runtimeOutcome
        self.remoteOutcome = remoteOutcome
        self.remoteInput = remoteInput
    }

    func handlers() -> HomeTimelineOlderPageHandlers {
        HomeTimelineOlderPageHandlers(
            perform: { [weak self] command in
                self?.events.append(.command(command))
            },
            prepareRemoteInput: { [weak self] account in
                guard let self else { return nil }
                events.append(.prepareRemoteInput(account.pubkey))
                return remoteInput
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

    func requestOlder(
        account: NostrAccount,
        policy: NostrSyncPolicy
    ) async -> HomeTimelineBackwardRequestOutcome {
        events.append(.requestOlder(account.pubkey))
        beforeRuntimeReturn?()
        return runtimeOutcome
    }

    func loadOlderPage(
        account: NostrAccount,
        current: NostrHomeTimelineState,
        localBackfillEvents: [NostrEvent]?,
        policy: NostrSyncPolicy,
        isCurrent: @escaping @MainActor @Sendable () -> Bool
    ) async -> HomeTimelineRemoteLoadOutcome {
        events.append(.loadRemote(
            accountID: account.pubkey,
            input: HomeTimelineOlderPageRemoteInput(
                current: current,
                localBackfillEvents: localBackfillEvents
            ),
            isCurrent: isCurrent()
        ))
        beforeRemoteReturn?()
        return remoteOutcome
    }
}
