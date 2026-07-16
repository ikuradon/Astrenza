import AstrenzaCore

struct HomeStoreRestoreIdentity: Equatable, Sendable {
    let accountID: String?
    let anchorEventID: String?
}

@MainActor
protocol HomeStoreRestoreSourcing: AnyObject {
    func restoreIdentity() -> HomeStoreRestoreIdentity
}

@MainActor
final class HomeStoreRestoreSource: HomeStoreRestoreSourcing {
    private let publishedState: HomeTimelinePublishedStateCoordinator
    private let viewport: HomeStoreViewportCoordinator

    init(
        publishedState: HomeTimelinePublishedStateCoordinator,
        viewport: HomeStoreViewportCoordinator
    ) {
        self.publishedState = publishedState
        self.viewport = viewport
    }

    func restoreIdentity() -> HomeStoreRestoreIdentity {
        HomeStoreRestoreIdentity(
            accountID: publishedState.accountContext.account?.pubkey,
            anchorEventID: viewport.restoreProjectionAnchorEventID
        )
    }
}

@MainActor
protocol HomeStoreRestoreProjectionReloading: AnyObject {
    func reloadProjection(
        account: NostrAccount,
        around anchorEventID: String?,
        mergingWithCurrentWindow: Bool,
        onCompletion: HomeTimelineMaterializationCoordinating
            .ProjectionReloadHandler?
    )
}

extension HomeStoreProjectionCoordinator:
    HomeStoreRestoreProjectionReloading {}

@MainActor
protocol HomeStoreRestoreMaterializing: AnyObject {
    func materializeEntries(
        allowsRealtimeFollow: Bool,
        onTransition: HomeTimelineMaterializationCoordinating
            .TransitionHandler?
    )
}

extension HomeStorePresentationCoordinator:
    HomeStoreRestoreMaterializing {}

@MainActor
protocol HomeStoreRestoreLinkPreviewScheduling: AnyObject {
    @discardableResult
    func scheduleLinkPreviewResolution() -> Bool
}

extension HomeStoreRuntimeCoordinator:
    HomeStoreRestoreLinkPreviewScheduling {}

@MainActor
protocol HomeStoreRestoreActivityPublishing: AnyObject {
    func applyActivityIntent(_ intent: HomeTimelineActivityIntent)
}

extension HomeStoreStatusCoordinator:
    HomeStoreRestoreActivityPublishing {}

@MainActor
struct HomeStoreRestoreCollaborators {
    let viewport: HomeStoreViewportCoordinator
    let projection: HomeStoreProjectionCoordinator
    let presentation: HomeStorePresentationCoordinator
    let runtime: HomeStoreRuntimeCoordinator
    let status: HomeStoreStatusCoordinator
}

@MainActor
final class HomeStoreRestoreCoordinator {
    private let source: any HomeStoreRestoreSourcing
    private let projection: any HomeStoreRestoreProjectionReloading
    private let presentation: any HomeStoreRestoreMaterializing
    private let linkPreview: any HomeStoreRestoreLinkPreviewScheduling
    private let activity: any HomeStoreRestoreActivityPublishing

    init(
        source: any HomeStoreRestoreSourcing,
        projection: any HomeStoreRestoreProjectionReloading,
        presentation: any HomeStoreRestoreMaterializing,
        linkPreview: any HomeStoreRestoreLinkPreviewScheduling,
        activity: any HomeStoreRestoreActivityPublishing
    ) {
        self.source = source
        self.projection = projection
        self.presentation = presentation
        self.linkPreview = linkPreview
        self.activity = activity
    }

    static func live(
        publishedState: HomeTimelinePublishedStateCoordinator,
        collaborators: HomeStoreRestoreCollaborators
    ) -> HomeStoreRestoreCoordinator {
        HomeStoreRestoreCoordinator(
            source: HomeStoreRestoreSource(
                publishedState: publishedState,
                viewport: collaborators.viewport
            ),
            projection: collaborators.projection,
            presentation: collaborators.presentation,
            linkPreview: collaborators.runtime,
            activity: collaborators.status
        )
    }

    func restoreIfPossible(account: NostrAccount) {
        guard let anchorEventID = source.restoreIdentity().anchorEventID
        else { return }

        let expectedIdentity = HomeStoreRestoreIdentity(
            accountID: account.pubkey,
            anchorEventID: anchorEventID
        )
        projection.reloadProjection(
            account: account,
            around: anchorEventID,
            mergingWithCurrentWindow: false
        ) { [weak self] didReload in
            guard didReload,
                  let self,
                  source.restoreIdentity() == expectedIdentity
            else { return }

            presentation.materializeEntries(
                allowsRealtimeFollow: false
            ) { [weak self] transition in
                guard let self else { return }
                linkPreview.scheduleLinkPreviewResolution()
                if !transition.snapshot.entries.isEmpty {
                    activity.applyActivityIntent(.setPhase(.loaded))
                }
            }
        }
    }
}
