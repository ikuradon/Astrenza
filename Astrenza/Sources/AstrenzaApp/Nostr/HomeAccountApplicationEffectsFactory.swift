import AstrenzaCore

@MainActor
protocol HomeAccountApplicationEffectTarget: AnyObject {
    func cancel()
    func applyAccountContextTransition(
        _ transition: HomeTimelineAccountContextTransition
    )
    func startRuntimeSession()
    func prepareHomeFeedDefinition(account: NostrAccount)
    func applyProjectionViewportTransition(
        _ transition: HomeTimelineProjectionViewportTransition
    )
    func reloadNewestProjectionWindow(account: NostrAccount)
    func materializeEntries(
        allowsRealtimeFollow: Bool,
        onTransition: HomeTimelineMaterializationCoordinating
            .TransitionHandler?
    )
    func applyRestoreProjectionAnchorIfPossible(account: NostrAccount)
    func installProvisionalRuntimeBootstrapIfNeeded(account: NostrAccount)
    func applyActivityIntent(_ intent: HomeTimelineActivityIntent)
    func publishRelayStatusChange()
    func applyPresentationTransition(
        _ transition: HomeTimelinePresentationTransition
    )
    @discardableResult
    func clearPendingNewEvents() -> Bool
    func applyActivityTransition(_ transition: HomeTimelineActivityTransition)
    func invalidateListEntries()
    func resetHomeTimelineRealtime(
        expecting runtimeKeys: Set<RuntimeSubscriptionKey>
    )
    func applyContentSnapshot(_ snapshot: HomeTimelineContentSnapshot)
    func applyRelayStatusSnapshot(_ snapshot: HomeTimelineRelayStatusSnapshot)
    func resetRuntimeSetup()
    func configureRelayRuntime(
        account: NostrAccount,
        forceInstall: Bool
    ) async
}

@MainActor
enum HomeAccountApplicationEffectsFactory {
    static func make(
        target: any HomeAccountApplicationEffectTarget
    ) -> HomeTimelineAccountApplicationEffects {
        let bindings = Bindings(target: target)
        return HomeTimelineAccountApplicationEffects(
            cancelCurrentAccount: bindings.cancelCurrentAccount,
            applyAccountContextTransition:
                bindings.applyAccountContextTransition,
            startRuntimeSession: bindings.startRuntimeSession,
            prepareHomeFeedDefinition: bindings.prepareHomeFeedDefinition,
            applyProjectionViewportTransition:
                bindings.applyProjectionViewportTransition,
            reloadNewestProjectionWindow:
                bindings.reloadNewestProjectionWindow,
            materializeEntries: bindings.materializeEntries,
            applyRestoreProjectionAnchor:
                bindings.applyRestoreProjectionAnchor,
            installProvisionalRuntimeBootstrap:
                bindings.installProvisionalRuntimeBootstrap,
            setPhase: bindings.setPhase,
            publishRelayStatusChange: bindings.publishRelayStatusChange,
            applyPresentationTransition:
                bindings.applyPresentationTransition,
            clearPendingEvents: bindings.clearPendingEvents,
            applyActivityTransition: bindings.applyActivityTransition,
            invalidateListEntries: bindings.invalidateListEntries,
            resetRealtimeState: bindings.resetRealtimeState,
            applyContentSnapshot: bindings.applyContentSnapshot,
            applyRelayStatusSnapshot: bindings.applyRelayStatusSnapshot,
            resetRuntimeSetup: bindings.resetRuntimeSetup,
            configureRuntime: bindings.configureRuntime
        )
    }
}

@MainActor
private struct Bindings {
    weak var target: (any HomeAccountApplicationEffectTarget)?

    var cancelCurrentAccount: HomeTimelineAccountApplicationEffects.Action {
        { [weak target] in
            target?.cancel()
        }
    }

    var applyAccountContextTransition:
        HomeTimelineAccountApplicationEffects.AccountContextTransition {
        { [weak target] transition in
            target?.applyAccountContextTransition(transition)
        }
    }

    var startRuntimeSession: HomeTimelineAccountApplicationEffects.Action {
        { [weak target] in
            target?.startRuntimeSession()
        }
    }

    var prepareHomeFeedDefinition:
        HomeTimelineAccountApplicationEffects.Account {
        { [weak target] account in
            target?.prepareHomeFeedDefinition(account: account)
        }
    }

    var applyProjectionViewportTransition:
        HomeTimelineAccountApplicationEffects.ProjectionViewportTransition {
        { [weak target] transition in
            target?.applyProjectionViewportTransition(transition)
        }
    }

    var reloadNewestProjectionWindow:
        HomeTimelineAccountApplicationEffects.Account {
        { [weak target] account in
            target?.reloadNewestProjectionWindow(account: account)
        }
    }

    var materializeEntries: HomeTimelineAccountApplicationEffects.Action {
        { [weak target] in
            target?.materializeEntries(
                allowsRealtimeFollow: false,
                onTransition: nil
            )
        }
    }

    var applyRestoreProjectionAnchor:
        HomeTimelineAccountApplicationEffects.Account {
        { [weak target] account in
            target?.applyRestoreProjectionAnchorIfPossible(account: account)
        }
    }

    var installProvisionalRuntimeBootstrap:
        HomeTimelineAccountApplicationEffects.Account {
        { [weak target] account in
            target?.installProvisionalRuntimeBootstrapIfNeeded(
                account: account
            )
        }
    }

    var setPhase: HomeTimelineAccountApplicationEffects.Phase {
        { [weak target] phase in
            target?.applyActivityIntent(.setPhase(phase))
        }
    }

    var publishRelayStatusChange:
        HomeTimelineAccountApplicationEffects.Action {
        { [weak target] in
            target?.publishRelayStatusChange()
        }
    }

    var applyPresentationTransition:
        HomeTimelineAccountApplicationEffects.PresentationTransition {
        { [weak target] transition in
            target?.applyPresentationTransition(transition)
        }
    }

    var clearPendingEvents: HomeTimelineAccountApplicationEffects.Action {
        { [weak target] in
            _ = target?.clearPendingNewEvents()
        }
    }

    var applyActivityTransition:
        HomeTimelineAccountApplicationEffects.ActivityTransition {
        { [weak target] transition in
            target?.applyActivityTransition(transition)
        }
    }

    var invalidateListEntries:
        HomeTimelineAccountApplicationEffects.Action {
        { [weak target] in
            target?.invalidateListEntries()
        }
    }

    var resetRealtimeState: HomeTimelineAccountApplicationEffects.Action {
        { [weak target] in
            target?.resetHomeTimelineRealtime(expecting: [])
        }
    }

    var applyContentSnapshot:
        HomeTimelineAccountApplicationEffects.ContentSnapshot {
        { [weak target] snapshot in
            target?.applyContentSnapshot(snapshot)
        }
    }

    var applyRelayStatusSnapshot:
        HomeTimelineAccountApplicationEffects.RelayStatusSnapshot {
        { [weak target] snapshot in
            target?.applyRelayStatusSnapshot(snapshot)
        }
    }

    var resetRuntimeSetup: HomeTimelineAccountApplicationEffects.Action {
        { [weak target] in
            target?.resetRuntimeSetup()
        }
    }

    var configureRuntime:
        HomeTimelineAccountApplicationEffects.RuntimeConfiguration {
        { [weak target] account, forceInstall in
            await target?.configureRelayRuntime(
                account: account,
                forceInstall: forceInstall
            )
        }
    }
}
