import AstrenzaCore
import Testing
@testable import Astrenza

@Suite("Home timeline load application dispatcher")
@MainActor
struct HomeTimelineLoadDispatcherTests {
    @Test("Applications preserve effect order and payloads")
    func applicationsDispatchEffects() {
        let fixture = LoadApplicationDispatcherFixture()
        let applications: [HomeTimelineLoadApplication] = [
            .applyActivityTransition(fixture.activityTransition),
            .applyRelayStatusTransition(fixture.relayStatusTransition),
            .installProvisionalRuntimeBootstrap(fixture.account),
            .restartAccount(fixture.account),
            .replaceTimelineState(fixture.timelineState),
            .replaceRuntimeBootstrapState(fixture.timelineState),
            .replaceFollowedPubkeys(fixture.followedPubkeys),
            .materializeEntries,
            .setPhase(.loaded)
        ]

        for application in applications {
            fixture.dispatcher.apply(application, effects: fixture.effects)
        }

        #expect(fixture.probe.events == [
            .activityTransition(fixture.activityTransition),
            .relayStatusTransition(fixture.relayStatusTransition),
            .installProvisionalRuntimeBootstrap(fixture.account.pubkey),
            .restartAccount(fixture.account.pubkey),
            .replaceTimelineState(fixture.timelineState),
            .replaceRuntimeBootstrapState(fixture.timelineState),
            .replaceFollowedPubkeys(fixture.followedPubkeys),
            .materializeEntries,
            .setPhase(.loaded)
        ])
    }

    @Test("Async applications preserve account and order")
    func asyncApplicationsDispatchEffects() async {
        let fixture = LoadApplicationDispatcherFixture()

        await fixture.dispatcher.perform(
            .configureRuntime(fixture.account),
            effects: fixture.effects
        )
        await fixture.dispatcher.perform(
            .persistDatabase(fixture.account),
            effects: fixture.effects
        )

        #expect(fixture.probe.events == [
            .configureRuntime(fixture.account.pubkey),
            .persistDatabase(fixture.account.pubkey)
        ])
    }
}

@MainActor
private final class LoadApplicationDispatchProbe {
    enum Event: Equatable {
        case activityTransition(HomeTimelineActivityTransition)
        case relayStatusTransition(HomeTimelineRelayStatusTransition)
        case installProvisionalRuntimeBootstrap(String)
        case restartAccount(String)
        case replaceTimelineState(NostrHomeTimelineState)
        case replaceRuntimeBootstrapState(NostrHomeTimelineState)
        case replaceFollowedPubkeys([String])
        case materializeEntries
        case setPhase(NostrHomeTimelinePhase)
        case configureRuntime(String)
        case persistDatabase(String)
    }

    var events: [Event] = []
}

@MainActor
private struct LoadApplicationDispatcherFixture {
    let dispatcher = HomeTimelineLoadDispatcher()
    let probe = LoadApplicationDispatchProbe()

    var account: NostrAccount {
        NostrAccount(
            pubkey: String(repeating: "a", count: 64),
            displayIdentifier: "load-dispatcher",
            readOnly: true
        )
    }

    var followedPubkeys: [String] {
        [account.pubkey, String(repeating: "b", count: 64)]
    }

    var timelineState: NostrHomeTimelineState {
        NostrHomeTimelineState(
            relays: ["wss://relay.example"],
            followedPubkeys: followedPubkeys,
            noteEvents: [],
            metadataEvents: []
        )
    }

    var activityTransition: HomeTimelineActivityTransition {
        HomeTimelineActivityTransition(
            snapshot: HomeTimelineActivitySnapshot(
                phase: .loadingHome,
                isRefreshing: true,
                isLoadingOlder: false,
                isRealtime: true
            ),
            changes: [.phase, .refreshing, .realtime]
        )
    }

    var relayStatusTransition: HomeTimelineRelayStatusTransition {
        HomeTimelineRelayStatusTransition(
            snapshot: HomeTimelineRelayStatusSnapshot(
                runtimeStates: [:],
                connectedRelayCount: 1,
                plannedRelayCount: 2
            ),
            invalidatedRealtimeRelayURL: "wss://relay.example",
            publishesStatusChange: true
        )
    }

    var effects: HomeTimelineLoadApplicationEffects {
        HomeTimelineLoadApplicationEffects(
            applyActivityTransition: { [probe] transition in
                probe.events.append(.activityTransition(transition))
            },
            applyRelayStatusTransition: { [probe] transition in
                probe.events.append(.relayStatusTransition(transition))
            },
            installProvisionalRuntimeBootstrap: { [probe] account in
                probe.events.append(.installProvisionalRuntimeBootstrap(
                    account.pubkey
                ))
            },
            restartAccount: { [probe] account in
                probe.events.append(.restartAccount(account.pubkey))
            },
            replaceTimelineState: { [probe] state in
                probe.events.append(.replaceTimelineState(state))
            },
            replaceRuntimeBootstrapState: { [probe] state in
                probe.events.append(.replaceRuntimeBootstrapState(state))
            },
            replaceFollowedPubkeys: { [probe] pubkeys in
                probe.events.append(.replaceFollowedPubkeys(pubkeys))
            },
            materializeEntries: { [probe] in
                probe.events.append(.materializeEntries)
            },
            setPhase: { [probe] phase in
                probe.events.append(.setPhase(phase))
            },
            configureRuntime: { [probe] account in
                probe.events.append(.configureRuntime(account.pubkey))
            },
            persistDatabase: { [probe] account in
                probe.events.append(.persistDatabase(account.pubkey))
            }
        )
    }
}
