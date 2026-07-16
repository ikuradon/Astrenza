import AstrenzaCore
import Testing
@testable import Astrenza

@Suite("Home load application effects factory")
@MainActor
struct HomeLoadEffectsFactoryTests {
    @Test("Every load effect forwards payloads in call order")
    func forwardsEveryEffect() async {
        let fixture = LoadEffectFixture()
        let target = LoadEffectTargetSpy()
        let effects = HomeLoadApplicationEffectsFactory.make(target: target)

        applyLoadEffects(effects, fixture: fixture)
        await applyAsyncLoadEffects(effects, fixture: fixture)

        #expect(target.events == expectedLoadEvents(fixture))
        #expect(target.materializationArguments == [
            LoadMaterializationArguments(
                allowsRealtimeFollow: false,
                hasTransition: false
            )
        ])
        #expect(target.runtimeConfigurationForceFlags == [false])
    }

    @Test("Load effects do not retain their target")
    func doesNotRetainTarget() throws {
        var target: LoadEffectTargetSpy? = LoadEffectTargetSpy()
        weak let weakTarget = target
        let effects = HomeLoadApplicationEffectsFactory.make(
            target: try #require(target)
        )

        target = nil

        #expect(weakTarget == nil)
        effects.materializeEntries()
    }
}

@MainActor
private func applyLoadEffects(
    _ effects: HomeTimelineLoadApplicationEffects,
    fixture: LoadEffectFixture
) {
    effects.applyActivityTransition(fixture.activityTransition)
    effects.applyRelayStatusTransition(fixture.relayStatusTransition)
    effects.installProvisionalRuntimeBootstrap(fixture.account)
    effects.restartAccount(fixture.account)
    effects.replaceTimelineState(fixture.timelineState)
    effects.replaceRuntimeBootstrapState(fixture.timelineState)
    effects.replaceFollowedPubkeys(fixture.followedPubkeys)
    effects.materializeEntries()
    effects.setPhase(.loaded)
}

@MainActor
private func applyAsyncLoadEffects(
    _ effects: HomeTimelineLoadApplicationEffects,
    fixture: LoadEffectFixture
) async {
    await effects.configureRuntime(fixture.account)
    await effects.persistDatabase(fixture.account)
}

@MainActor
private func expectedLoadEvents(
    _ fixture: LoadEffectFixture
) -> [LoadEffectTargetSpy.Event] {
    [
        .activityTransition(fixture.activityTransition),
        .relayStatusTransition(fixture.relayStatusTransition),
        .installProvisionalRuntimeBootstrap(fixture.account.pubkey),
        .restartAccount(fixture.account.pubkey),
        .replaceTimelineState(fixture.timelineState),
        .replaceRuntimeBootstrapState(fixture.timelineState),
        .replaceFollowedPubkeys(fixture.followedPubkeys),
        .materializeEntries,
        .setPhase(.loaded),
        .configureRuntime(fixture.account.pubkey),
        .persistDatabase(fixture.account.pubkey)
    ]
}

private struct LoadMaterializationArguments: Equatable {
    let allowsRealtimeFollow: Bool
    let hasTransition: Bool
}

@MainActor
private struct LoadEffectFixture {
    let account = NostrAccount(
        pubkey: String(repeating: "a", count: 64),
        displayIdentifier: "load-factory",
        readOnly: true
    )

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
}

@MainActor
private final class LoadEffectTargetSpy: HomeLoadApplicationEffectTarget {
    enum Event: Equatable {
        case activityTransition(HomeTimelineActivityTransition)
        case relayStatusTransition(HomeTimelineRelayStatusTransition?)
        case installProvisionalRuntimeBootstrap(String)
        case restartAccount(String)
        case replaceTimelineState(NostrHomeTimelineState)
        case replaceRuntimeBootstrapState(NostrHomeTimelineState)
        case replaceFollowedPubkeys([String])
        case materializeEntries
        case setPhase(NostrHomeTimelinePhase)
        case setRealtime(Bool)
        case configureRuntime(String)
        case persistDatabase(String)
    }

    private(set) var events: [Event] = []
    private(set) var materializationArguments:
        [LoadMaterializationArguments] = []
    private(set) var runtimeConfigurationForceFlags: [Bool] = []

    func applyActivityTransition(
        _ transition: HomeTimelineActivityTransition
    ) {
        events.append(.activityTransition(transition))
    }

    func applyRelayStatusTransition(
        _ transition: HomeTimelineRelayStatusTransition?
    ) {
        events.append(.relayStatusTransition(transition))
    }

    func installProvisionalRuntimeBootstrapIfNeeded(account: NostrAccount) {
        events.append(.installProvisionalRuntimeBootstrap(account.pubkey))
    }

    func start(account: NostrAccount) {
        events.append(.restartAccount(account.pubkey))
    }

    func replaceTimelineState(_ state: NostrHomeTimelineState) {
        events.append(.replaceTimelineState(state))
    }

    func replaceRuntimeBootstrapState(_ state: NostrHomeTimelineState) {
        events.append(.replaceRuntimeBootstrapState(state))
    }

    func replaceFollowedPubkeys(_ pubkeys: [String]) {
        events.append(.replaceFollowedPubkeys(pubkeys))
    }

    func materializeEntries(
        allowsRealtimeFollow: Bool,
        onTransition: HomeTimelineMaterializationCoordinating
            .TransitionHandler?
    ) {
        materializationArguments.append(LoadMaterializationArguments(
            allowsRealtimeFollow: allowsRealtimeFollow,
            hasTransition: onTransition != nil
        ))
        events.append(.materializeEntries)
    }

    func applyActivityIntent(_ intent: HomeTimelineActivityIntent) {
        switch intent {
        case .setPhase(let phase):
            events.append(.setPhase(phase))
        case .setRealtime(let isRealtime):
            events.append(.setRealtime(isRealtime))
        }
    }

    func configureRelayRuntime(
        account: NostrAccount,
        forceInstall: Bool
    ) async {
        runtimeConfigurationForceFlags.append(forceInstall)
        events.append(.configureRuntime(account.pubkey))
    }

    func persistDatabase(account: NostrAccount) async {
        events.append(.persistDatabase(account.pubkey))
    }
}
