import AstrenzaCore

@MainActor
protocol HomeViewportApplicationEffectTarget: AnyObject {
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
    func applyPresentationTransition(
        _ transition: HomeTimelinePresentationTransition
    )
    func scheduleHomeFeedReadStateSave()
    func applyPendingEventCountPublication(
        _ publication: HomeTimelinePendingEventCountPublication
    )
    func clearPendingProjectionReload()
    func scheduleLinkPreviewResolution()
    func refreshLatest(
        account: NostrAccount,
        lifecycle: HomeTimelineLifecycleToken
    ) async
    func loadOlder(
        account: NostrAccount,
        lifecycle: HomeTimelineLifecycleToken
    ) async
}

@MainActor
enum HomeViewportApplicationEffectsFactory {
    static func make(
        target: any HomeViewportApplicationEffectTarget
    ) -> HomeTimelineViewportApplicationEffects {
        let bindings = Bindings(target: target)
        return HomeTimelineViewportApplicationEffects(
            applyProjectionViewportTransition:
                bindings.applyProjectionViewportTransition,
            reloadNewestProjectionWindow:
                bindings.reloadNewestProjectionWindow,
            materializeEntries: bindings.materializeEntries,
            applyRestoreProjectionAnchor:
                bindings.applyRestoreProjectionAnchor,
            applyPresentationTransition:
                bindings.applyPresentationTransition,
            scheduleReadStateSave: bindings.scheduleReadStateSave,
            applyPendingEventCountPublication:
                bindings.applyPendingEventCountPublication,
            clearPendingProjectionReload:
                bindings.clearPendingProjectionReload,
            scheduleLinkPreviewResolution:
                bindings.scheduleLinkPreviewResolution,
            refreshLatest: bindings.refreshLatest,
            loadOlder: bindings.loadOlder
        )
    }
}

@MainActor
private struct Bindings {
    weak var target: (any HomeViewportApplicationEffectTarget)?

    var applyProjectionViewportTransition:
        HomeTimelineViewportApplicationEffects.ProjectionViewportTransition {
        { [weak target] transition in
            target?.applyProjectionViewportTransition(transition)
        }
    }

    var reloadNewestProjectionWindow:
        HomeTimelineViewportApplicationEffects.Account {
        { [weak target] account in
            target?.reloadNewestProjectionWindow(account: account)
        }
    }

    var materializeEntries:
        HomeTimelineViewportApplicationEffects.RealtimeFollowPermission {
        { [weak target] allowsRealtimeFollow in
            target?.materializeEntries(
                allowsRealtimeFollow: allowsRealtimeFollow,
                onTransition: nil
            )
        }
    }

    var applyRestoreProjectionAnchor:
        HomeTimelineViewportApplicationEffects.Account {
        { [weak target] account in
            target?.applyRestoreProjectionAnchorIfPossible(account: account)
        }
    }

    var applyPresentationTransition:
        HomeTimelineViewportApplicationEffects.PresentationTransition {
        { [weak target] transition in
            target?.applyPresentationTransition(transition)
        }
    }

    var scheduleReadStateSave:
        HomeTimelineViewportApplicationEffects.Action {
        { [weak target] in
            target?.scheduleHomeFeedReadStateSave()
        }
    }

    var applyPendingEventCountPublication:
        HomeTimelineViewportApplicationEffects.PendingEventCountPublication {
        { [weak target] publication in
            target?.applyPendingEventCountPublication(publication)
        }
    }

    var clearPendingProjectionReload:
        HomeTimelineViewportApplicationEffects.Action {
        { [weak target] in
            target?.clearPendingProjectionReload()
        }
    }

    var scheduleLinkPreviewResolution:
        HomeTimelineViewportApplicationEffects.Action {
        { [weak target] in
            target?.scheduleLinkPreviewResolution()
        }
    }

    var refreshLatest:
        HomeTimelineViewportApplicationEffects.AccountLifecycle {
        { [weak target] account, lifecycle in
            await target?.refreshLatest(
                account: account,
                lifecycle: lifecycle
            )
        }
    }

    var loadOlder: HomeTimelineViewportApplicationEffects.AccountLifecycle {
        { [weak target] account, lifecycle in
            await target?.loadOlder(
                account: account,
                lifecycle: lifecycle
            )
        }
    }
}
