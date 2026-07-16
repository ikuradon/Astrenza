import AstrenzaCore

@MainActor
protocol HomeLoadApplicationEffectTarget: AnyObject {
    func applyActivityTransition(_ transition: HomeTimelineActivityTransition)
    func applyRelayStatusTransition(
        _ transition: HomeTimelineRelayStatusTransition?
    )
    func installProvisionalRuntimeBootstrapIfNeeded(account: NostrAccount)
    func start(account: NostrAccount)
    func replaceTimelineState(_ state: NostrHomeTimelineState)
    func replaceRuntimeBootstrapState(_ state: NostrHomeTimelineState)
    func replaceFollowedPubkeys(_ pubkeys: [String])
    func materializeEntries(
        allowsRealtimeFollow: Bool,
        onTransition: HomeTimelineMaterializationCoordinating
            .TransitionHandler?
    )
    func applyActivityIntent(_ intent: HomeTimelineActivityIntent)
    func configureRelayRuntime(
        account: NostrAccount,
        forceInstall: Bool
    ) async
    func persistDatabase(account: NostrAccount) async
}

@MainActor
enum HomeLoadApplicationEffectsFactory {
    static func make(
        target: any HomeLoadApplicationEffectTarget
    ) -> HomeTimelineLoadApplicationEffects {
        let bindings = Bindings(target: target)
        return HomeTimelineLoadApplicationEffects(
            applyActivityTransition: bindings.applyActivityTransition,
            applyRelayStatusTransition: bindings.applyRelayStatusTransition,
            installProvisionalRuntimeBootstrap:
                bindings.installProvisionalRuntimeBootstrap,
            restartAccount: bindings.restartAccount,
            replaceTimelineState: bindings.replaceTimelineState,
            replaceRuntimeBootstrapState:
                bindings.replaceRuntimeBootstrapState,
            replaceFollowedPubkeys: bindings.replaceFollowedPubkeys,
            materializeEntries: bindings.materializeEntries,
            setPhase: bindings.setPhase,
            configureRuntime: bindings.configureRuntime,
            persistDatabase: bindings.persistDatabase
        )
    }
}

@MainActor
private struct Bindings {
    weak var target: (any HomeLoadApplicationEffectTarget)?

    var applyActivityTransition:
        HomeTimelineLoadApplicationEffects.ActivityTransition {
        { [weak target] transition in
            target?.applyActivityTransition(transition)
        }
    }

    var applyRelayStatusTransition:
        HomeTimelineLoadApplicationEffects.RelayStatusTransition {
        { [weak target] transition in
            target?.applyRelayStatusTransition(transition)
        }
    }

    var installProvisionalRuntimeBootstrap:
        HomeTimelineLoadApplicationEffects.Account {
        { [weak target] account in
            target?.installProvisionalRuntimeBootstrapIfNeeded(
                account: account
            )
        }
    }

    var restartAccount: HomeTimelineLoadApplicationEffects.Account {
        { [weak target] account in
            target?.start(account: account)
        }
    }

    var replaceTimelineState:
        HomeTimelineLoadApplicationEffects.TimelineState {
        { [weak target] state in
            target?.replaceTimelineState(state)
        }
    }

    var replaceRuntimeBootstrapState:
        HomeTimelineLoadApplicationEffects.TimelineState {
        { [weak target] state in
            target?.replaceRuntimeBootstrapState(state)
        }
    }

    var replaceFollowedPubkeys:
        HomeTimelineLoadApplicationEffects.FollowedPubkeys {
        { [weak target] pubkeys in
            target?.replaceFollowedPubkeys(pubkeys)
        }
    }

    var materializeEntries: HomeTimelineLoadApplicationEffects.Action {
        { [weak target] in
            target?.materializeEntries(
                allowsRealtimeFollow: false,
                onTransition: nil
            )
        }
    }

    var setPhase: HomeTimelineLoadApplicationEffects.Phase {
        { [weak target] phase in
            target?.applyActivityIntent(.setPhase(phase))
        }
    }

    var configureRuntime: HomeTimelineLoadApplicationEffects.AsyncAccount {
        { [weak target] account in
            await target?.configureRelayRuntime(
                account: account,
                forceInstall: false
            )
        }
    }

    var persistDatabase: HomeTimelineLoadApplicationEffects.AsyncAccount {
        { [weak target] account in
            await target?.persistDatabase(account: account)
        }
    }
}
