import AstrenzaCore

@MainActor
struct HomeStoreComposition {
    private struct Shared {
        let query: HomeStoreQueryCoordinator
        let projection: HomeStoreProjectionCoordinator
        let context: HomeStoreContextCoordinator
        let runtime: HomeStoreRuntimeCoordinator
        let viewport: HomeStoreViewportCoordinator
        let presentation: HomeStorePresentationCoordinator
        let status: HomeStoreStatusCoordinator

        var restoreCollaborators: HomeStoreRestoreCollaborators {
            HomeStoreRestoreCollaborators(
                viewport: viewport,
                projection: projection,
                presentation: presentation,
                runtime: runtime,
                status: status
            )
        }
    }

    let query: HomeStoreQueryCoordinator
    let projection: HomeStoreProjectionCoordinator
    let context: HomeStoreContextCoordinator
    let lifecycle: HomeStoreLifecycleCoordinator
    let featureActions: HomeStoreFeatureActionCoordinator
    let sync: HomeStoreSyncCoordinator
    let state: HomeStoreStateCoordinator
    let runtime: HomeStoreRuntimeCoordinator
    let viewport: HomeStoreViewportCoordinator
    let presentation: HomeStorePresentationCoordinator
    let status: HomeStoreStatusCoordinator
    let restore: HomeStoreRestoreCoordinator

    static func make(
        components: HomeTimelineStoreComponents
    ) -> HomeStoreComposition {
        let shared = makeShared(components: components)
        return HomeStoreComposition(
            query: shared.query,
            projection: shared.projection,
            context: shared.context,
            lifecycle: HomeStoreLifecycleCoordinator.live(
                components: components,
                projection: shared.projection,
                contexts: shared.context
            ),
            featureActions: HomeStoreFeatureActionCoordinator.live(
                components: components,
                contexts: shared.context
            ),
            sync: HomeStoreSyncCoordinator.live(
                components: components,
                contexts: shared.context
            ),
            state: HomeStoreStateCoordinator.live(
                components: components,
                contexts: shared.context
            ),
            runtime: shared.runtime,
            viewport: shared.viewport,
            presentation: shared.presentation,
            status: shared.status,
            restore: HomeStoreRestoreCoordinator.live(
                publishedState: components.publishedStateCoordinator,
                collaborators: shared.restoreCollaborators
            )
        )
    }

    private static func makeShared(
        components: HomeTimelineStoreComponents
    ) -> Shared {
        let query = HomeStoreQueryCoordinator(
            interaction: components.queryInteractionWorkflow
        )
        let projectionViewport = HomeProjectionViewportCoordinator()
        let context = HomeStoreContextCoordinator.live(
            components: components,
            query: query,
            projectionViewport: projectionViewport,
            hasRelayRuntime: components.relayRuntime != nil
        )
        let projection = HomeStoreProjectionCoordinator.live(
            components: components
        )
        let runtime = HomeStoreRuntimeCoordinator.live(
            components: components,
            contexts: context
        )
        let viewport = HomeStoreViewportCoordinator.live(
            components: components,
            projection: projectionViewport,
            contexts: context
        )
        let presentation = HomeStorePresentationCoordinator.live(
            components: components
        )
        let status = HomeStoreStatusCoordinator.live(
            components: components
        )
        return Shared(
            query: query,
            projection: projection,
            context: context,
            runtime: runtime,
            viewport: viewport,
            presentation: presentation,
            status: status
        )
    }
}
