import AstrenzaCore

@MainActor
protocol HomeStoreApplicationEffectTarget: AnyObject {
    func applyPresentationTransition(
        _ transition: HomeTimelinePresentationTransition
    )
    func applyContentSnapshot(_ snapshot: HomeTimelineContentSnapshot)
    func applyRelayStatusSnapshot(_ snapshot: HomeTimelineRelayStatusSnapshot)
    func applyListProjectionInvalidation(
        _ invalidation: HomeTimelineListProjectionInvalidation
    )
    func applyPendingEventCountPublication(
        _ publication: HomeTimelinePendingEventCountPublication
    )
    func reloadProjectionWindow(
        account: NostrAccount,
        around anchorEventID: String?,
        mergingWithCurrentWindow: Bool,
        onCompletion: HomeTimelineMaterializationCoordinating
            .ProjectionReloadHandler?
    )
    func reloadNewestProjectionWindow(account: NostrAccount)
    func requestNewestProjectionReload()
    func scheduleMaterializeEntries(
        delayNanoseconds: UInt64?,
        allowsRealtimeFollow: Bool?
    )
    func materializeEntries(
        allowsRealtimeFollow: Bool,
        onTransition: HomeTimelineMaterializationCoordinating
            .TransitionHandler?
    )
    func applyRelayStatusTransition(
        _ transition: HomeTimelineRelayStatusTransition?
    )
    func applyActivityIntent(_ intent: HomeTimelineActivityIntent)
    func handleBackwardCompletion(_ completion: NostrBackwardREQCompletion)
    func invalidateListEntries()
    func scheduleLinkPreviewResolution()
    func publishRelayStatusChange()
    func handleRuntimeEvent(
        relayURL: String,
        subscriptionID: String,
        event: NostrEvent
    ) async
    func persistDatabase(account: NostrAccount) async
}

@MainActor
enum HomeStoreApplicationEffectsFactory {
    static func make(
        target: any HomeStoreApplicationEffectTarget
    ) -> HomeTimelineStoreApplicationEffects {
        let bindings = Bindings(target: target)
        return HomeTimelineStoreApplicationEffects(
            applyPresentationTransition: bindings.applyPresentationTransition,
            applyContentSnapshot: bindings.applyContentSnapshot,
            applyRelayStatusSnapshot: bindings.applyRelayStatusSnapshot,
            applyListProjectionInvalidation:
                bindings.applyListProjectionInvalidation,
            applyPendingEventCountPublication:
                bindings.applyPendingEventCountPublication,
            reloadProjection: bindings.reloadProjection,
            reloadNewestProjectionWindow:
                bindings.reloadNewestProjectionWindow,
            requestNewestProjectionReload:
                bindings.requestNewestProjectionReload,
            scheduleMaterialization: bindings.scheduleMaterialization,
            materializeEntries: bindings.materializeEntries,
            applyRelayStatusTransition: bindings.applyRelayStatusTransition,
            setRealtime: bindings.setRealtime,
            setPhase: bindings.setPhase,
            handleBackwardCompletion: bindings.handleBackwardCompletion,
            invalidateListEntries: bindings.invalidateListEntries,
            scheduleLinkPreviewResolution:
                bindings.scheduleLinkPreviewResolution,
            publishRelayStatusChange: bindings.publishRelayStatusChange,
            handleRuntimeEvent: bindings.handleRuntimeEvent,
            persistDatabase: bindings.persistDatabase
        )
    }
}

@MainActor
private struct Bindings {
    weak var target: (any HomeStoreApplicationEffectTarget)?

    var applyPresentationTransition:
        HomeTimelineStoreApplicationEffects.PresentationTransition {
        { [weak target] transition in
            target?.applyPresentationTransition(transition)
        }
    }

    var applyContentSnapshot:
        HomeTimelineStoreApplicationEffects.ContentSnapshot {
        { [weak target] snapshot in
            target?.applyContentSnapshot(snapshot)
        }
    }

    var applyRelayStatusSnapshot:
        HomeTimelineStoreApplicationEffects.RelayStatusSnapshot {
        { [weak target] snapshot in
            target?.applyRelayStatusSnapshot(snapshot)
        }
    }

    var applyListProjectionInvalidation:
        HomeTimelineStoreApplicationEffects.ListProjectionInvalidation {
        { [weak target] invalidation in
            target?.applyListProjectionInvalidation(invalidation)
        }
    }

    var applyPendingEventCountPublication:
        HomeTimelineStoreApplicationEffects.PendingEventCountPublication {
        { [weak target] publication in
            target?.applyPendingEventCountPublication(publication)
        }
    }

    var reloadProjection: HomeTimelineStoreApplicationEffects.ProjectionReload {
        { [weak target] account, anchorEventID, merging in
            target?.reloadProjectionWindow(
                account: account,
                around: anchorEventID,
                mergingWithCurrentWindow: merging,
                onCompletion: nil
            )
        }
    }

    var reloadNewestProjectionWindow:
        HomeTimelineStoreApplicationEffects.Account {
        { [weak target] account in
            target?.reloadNewestProjectionWindow(account: account)
        }
    }

    var requestNewestProjectionReload:
        HomeTimelineStoreApplicationEffects.Action {
        { [weak target] in
            target?.requestNewestProjectionReload()
        }
    }

    var scheduleMaterialization:
        HomeTimelineStoreApplicationEffects.MaterializationSchedule {
        { [weak target] delay, realtimeFollow in
            target?.scheduleMaterializeEntries(
                delayNanoseconds: delay,
                allowsRealtimeFollow: realtimeFollow
            )
        }
    }

    var materializeEntries: HomeTimelineStoreApplicationEffects.Action {
        { [weak target] in
            target?.materializeEntries(
                allowsRealtimeFollow: false,
                onTransition: nil
            )
        }
    }

    var applyRelayStatusTransition:
        HomeTimelineStoreApplicationEffects.RelayStatusTransition {
        { [weak target] transition in
            target?.applyRelayStatusTransition(transition)
        }
    }

    var setRealtime: HomeTimelineStoreApplicationEffects.Realtime {
        { [weak target] isRealtime in
            target?.applyActivityIntent(.setRealtime(isRealtime))
        }
    }

    var setPhase: HomeTimelineStoreApplicationEffects.Phase {
        { [weak target] phase in
            target?.applyActivityIntent(.setPhase(phase))
        }
    }

    var handleBackwardCompletion:
        HomeTimelineStoreApplicationEffects.BackwardCompletion {
        { [weak target] completion in
            target?.handleBackwardCompletion(completion)
        }
    }

    var invalidateListEntries: HomeTimelineStoreApplicationEffects.Action {
        { [weak target] in
            target?.invalidateListEntries()
        }
    }

    var scheduleLinkPreviewResolution:
        HomeTimelineStoreApplicationEffects.Action {
        { [weak target] in
            target?.scheduleLinkPreviewResolution()
        }
    }

    var publishRelayStatusChange:
        HomeTimelineStoreApplicationEffects.Action {
        { [weak target] in
            target?.publishRelayStatusChange()
        }
    }

    var handleRuntimeEvent: HomeTimelineStoreApplicationEffects.RuntimeEvent {
        { [weak target] relayURL, subscriptionID, event in
            await target?.handleRuntimeEvent(
                relayURL: relayURL,
                subscriptionID: subscriptionID,
                event: event
            )
        }
    }

    var persistDatabase: HomeTimelineStoreApplicationEffects.AsyncAccount {
        { [weak target] account in
            await target?.persistDatabase(account: account)
        }
    }
}
