import AstrenzaCore
import Testing
@testable import Astrenza

@Suite("Home timeline account application dispatcher")
@MainActor
struct HomeAccountApplicationDispatcherTests {
    @Test("Account start actions preserve order and payloads")
    func startActionsDispatchEffects() {
        let fixture = AccountApplicationDispatcherFixture()
        let account = fixture.account
        let contextTransition = fixture.accountContextTransition
        let viewportTransition = fixture.viewportTransition
        let actions: [HomeTimelineAccountStartStoreAction] = [
            .account(.cancelCurrentAccount),
            .account(.applyAccountContextTransition(contextTransition)),
            .account(.startRuntimeSession),
            .account(.prepareHomeFeedDefinition(account)),
            .projection(.applyProjectionViewportTransition(viewportTransition)),
            .projection(.reloadNewestProjectionWindow(account)),
            .projection(.materializeEntries),
            .projection(.applyRestoreProjectionAnchor(account)),
            .account(.installProvisionalRuntimeBootstrap(account)),
            .account(.setPhase(.resolvingRelays)),
            .account(.publishOutboxRelayResults)
        ]

        for action in actions {
            fixture.dispatcher.apply(action, effects: fixture.effects)
        }

        #expect(fixture.probe.events == [
            .cancelCurrentAccount,
            .accountContextTransition(contextTransition),
            .startRuntimeSession,
            .prepareHomeFeedDefinition(account.pubkey),
            .projectionViewportTransition(viewportTransition),
            .reloadNewestProjectionWindow(account.pubkey),
            .materializeEntries,
            .applyRestoreProjectionAnchor(account.pubkey),
            .installProvisionalRuntimeBootstrap(account.pubkey),
            .setPhase(.resolvingRelays),
            .publishRelayStatusChange
        ])
    }

    @Test("Account reset actions preserve order and payloads")
    func resetActionsDispatchEffects() {
        let fixture = AccountApplicationDispatcherFixture()
        let presentation = fixture.presentationTransition
        let activity = fixture.activityTransition
        let content = fixture.contentSnapshot
        let relayStatus = fixture.relayStatusSnapshot
        let viewport = fixture.viewportTransition
        let context = fixture.accountContextTransition
        let actions: [HomeTimelineAccountResetStoreAction] = [
            .applyPresentationTransition(presentation),
            .clearPendingEvents,
            .applyActivityTransition(activity),
            .invalidateListEntries,
            .resetRealtimeState,
            .applyContentSnapshot(content),
            .applyRelayStatusSnapshot(relayStatus),
            .applyProjectionViewportTransition(viewport),
            .publishRelayStatusChange,
            .applyAccountContextTransition(context)
        ]

        for action in actions {
            fixture.dispatcher.apply(action, effects: fixture.effects)
        }

        #expect(fixture.probe.events == [
            .presentationTransition(
                changes: presentation.changes.rawValue,
                didChangeReadState: presentation.didChangeReadState
            ),
            .clearPendingEvents,
            .activityTransition(activity),
            .invalidateListEntries,
            .resetRealtimeState,
            .contentSnapshot(content),
            .relayStatusSnapshot(relayStatus),
            .projectionViewportTransition(viewport),
            .publishRelayStatusChange,
            .accountContextTransition(context)
        ])
    }

    @Test("Runtime reset preserves setup realtime restart and configuration order")
    func resetRuntimeActionsDispatchEffects() async {
        let fixture = AccountApplicationDispatcherFixture()

        await fixture.dispatcher.perform(
            .resetRuntimeState,
            effects: fixture.effects
        )
        await fixture.dispatcher.perform(
            .startRuntimeSession,
            effects: fixture.effects
        )
        await fixture.dispatcher.perform(
            .configureRuntime(account: fixture.account, forceInstall: true),
            effects: fixture.effects
        )

        #expect(fixture.probe.events == [
            .resetRuntimeSetup,
            .resetRealtimeState,
            .startRuntimeSession,
            .configureRuntime(
                accountID: fixture.account.pubkey,
                forceInstall: true
            )
        ])
    }
}

@MainActor
private final class AccountApplicationDispatchProbe {
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
        case publishRelayStatusChange
        case presentationTransition(
            changes: Int,
            didChangeReadState: Bool
        )
        case clearPendingEvents
        case activityTransition(HomeTimelineActivityTransition)
        case invalidateListEntries
        case resetRealtimeState
        case contentSnapshot(HomeTimelineContentSnapshot)
        case relayStatusSnapshot(HomeTimelineRelayStatusSnapshot)
        case resetRuntimeSetup
        case configureRuntime(accountID: String, forceInstall: Bool)
    }

    var events: [Event] = []
}

@MainActor
private struct AccountApplicationDispatcherFixture {
    let dispatcher = HomeTimelineAccountApplicationDispatcher()
    let probe = AccountApplicationDispatchProbe()

    var account: NostrAccount {
        NostrAccount(
            pubkey: String(repeating: "a", count: 64),
            displayIdentifier: "account-dispatcher",
            readOnly: true
        )
    }

    var accountContextTransition: HomeTimelineAccountContextTransition {
        .activate(
            account,
            syncPolicy: .default(networkType: .wifi)
        )
    }

    var viewportTransition: HomeTimelineProjectionViewportTransition {
        .restoreViewport(anchorEventID: "anchor")
    }

    var presentationTransition: HomeTimelinePresentationTransition {
        HomeTimelinePresentationTransition(
            snapshot: HomeTimelinePresentationSnapshot(
                entries: [],
                filterStatus: TimelineFilterStatus(),
                materializedUnreadCount: 0,
                visibleUnreadBadgeCount: 0,
                resolvedContentRevision: 2,
                realtimeFollowSourceRevision: nil
            ),
            changes: [.entries, .resolvedContentRevision],
            didChangeReadState: true
        )
    }

    var activityTransition: HomeTimelineActivityTransition {
        HomeTimelineActivityTransition(
            snapshot: HomeTimelineActivitySnapshot(
                phase: .idle,
                isRefreshing: false,
                isLoadingOlder: false,
                isRealtime: false
            ),
            changes: [.phase, .realtime]
        )
    }

    var contentSnapshot: HomeTimelineContentSnapshot {
        HomeTimelineContentSnapshot.initial
    }

    var relayStatusSnapshot: HomeTimelineRelayStatusSnapshot {
        HomeTimelineRelayStatusSnapshot(
            runtimeStates: [:],
            connectedRelayCount: 0,
            plannedRelayCount: 2
        )
    }

    var effects: HomeTimelineAccountApplicationEffects {
        HomeTimelineAccountApplicationEffects(
            cancelCurrentAccount: { [probe] in
                probe.events.append(.cancelCurrentAccount)
            },
            applyAccountContextTransition: { [probe] transition in
                probe.events.append(.accountContextTransition(transition))
            },
            startRuntimeSession: { [probe] in
                probe.events.append(.startRuntimeSession)
            },
            prepareHomeFeedDefinition: { [probe] account in
                probe.events.append(.prepareHomeFeedDefinition(account.pubkey))
            },
            applyProjectionViewportTransition: { [probe] transition in
                probe.events.append(.projectionViewportTransition(transition))
            },
            reloadNewestProjectionWindow: { [probe] account in
                probe.events.append(
                    .reloadNewestProjectionWindow(account.pubkey)
                )
            },
            materializeEntries: { [probe] in
                probe.events.append(.materializeEntries)
            },
            applyRestoreProjectionAnchor: { [probe] account in
                probe.events.append(.applyRestoreProjectionAnchor(
                    account.pubkey
                ))
            },
            installProvisionalRuntimeBootstrap: { [probe] account in
                probe.events.append(.installProvisionalRuntimeBootstrap(
                    account.pubkey
                ))
            },
            setPhase: { [probe] phase in
                probe.events.append(.setPhase(phase))
            },
            publishRelayStatusChange: { [probe] in
                probe.events.append(.publishRelayStatusChange)
            },
            applyPresentationTransition: { [probe] transition in
                probe.events.append(.presentationTransition(
                    changes: transition.changes.rawValue,
                    didChangeReadState: transition.didChangeReadState
                ))
            },
            clearPendingEvents: { [probe] in
                probe.events.append(.clearPendingEvents)
            },
            applyActivityTransition: { [probe] transition in
                probe.events.append(.activityTransition(transition))
            },
            invalidateListEntries: { [probe] in
                probe.events.append(.invalidateListEntries)
            },
            resetRealtimeState: { [probe] in
                probe.events.append(.resetRealtimeState)
            },
            applyContentSnapshot: { [probe] snapshot in
                probe.events.append(.contentSnapshot(snapshot))
            },
            applyRelayStatusSnapshot: { [probe] snapshot in
                probe.events.append(.relayStatusSnapshot(snapshot))
            },
            resetRuntimeSetup: { [probe] in
                probe.events.append(.resetRuntimeSetup)
            },
            configureRuntime: { [probe] account, forceInstall in
                probe.events.append(.configureRuntime(
                    accountID: account.pubkey,
                    forceInstall: forceInstall
                ))
            }
        )
    }
}
