import AstrenzaCore

@MainActor
protocol HomeRestoreProjectionAnchorTarget: AnyObject {
    var account: NostrAccount? { get }
    var restoreProjectionAnchorEventID: String? { get }

    func reloadProjectionWindow(
        account: NostrAccount,
        around anchorEventID: String?,
        mergingWithCurrentWindow: Bool,
        onCompletion: HomeTimelineMaterializationCoordinating
            .ProjectionReloadHandler?
    )
    func materializeEntries(
        allowsRealtimeFollow: Bool,
        onTransition: HomeTimelineMaterializationCoordinating
            .TransitionHandler?
    )
    func scheduleLinkPreviewResolution()
    func applyActivityIntent(_ intent: HomeTimelineActivityIntent)
}

@MainActor
final class HomeRestoreProjectionAnchorWorkflow {
    private weak var target: (any HomeRestoreProjectionAnchorTarget)?

    init(target: any HomeRestoreProjectionAnchorTarget) {
        self.target = target
    }

    func restoreIfPossible(account: NostrAccount) {
        guard let target,
              let anchorEventID = target.restoreProjectionAnchorEventID
        else { return }

        target.reloadProjectionWindow(
            account: account,
            around: anchorEventID,
            mergingWithCurrentWindow: false
        ) { [weak target] didReload in
            guard didReload,
                  let target,
                  target.account?.pubkey == account.pubkey,
                  target.restoreProjectionAnchorEventID == anchorEventID
            else { return }

            target.materializeEntries(
                allowsRealtimeFollow: false
            ) { [weak target] transition in
                guard let target else { return }
                target.scheduleLinkPreviewResolution()
                if !transition.snapshot.entries.isEmpty {
                    target.applyActivityIntent(.setPhase(.loaded))
                }
            }
        }
    }
}
